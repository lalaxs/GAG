-- ============================================================================
-- 服务端偷菜系统
-- Grow A Garden
-- ============================================================================
-- 目标农场走目标会话 MutateFarm；小偷经济走小偷队列；两侧均 flush 成功后再写旁路记录。
-- ============================================================================

local UserId = require("utils.user_id")
local ServerCloudStore = require("server.server_cloud_store")

local ServerSteal = {}

local STEAL_RATE_LIMIT_BACKOFF = 8
local STEAL_DAILY_CACHE_TTL = 12
local stealBackoffUntilByUid_ = {}
local stealDailyCacheByUid_ = {}

local deps_ = {}

function ServerSteal.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function NormalizePlantIndex(value)
    return deps_.NormalizePlantIndex(value)
end

local function NormalizePositiveCount(value, maxValue)
    return deps_.NormalizePositiveCount(value, maxValue)
end

local function NormalizeUserId(userId)
    if deps_.NormalizeUserId ~= nil then return deps_.NormalizeUserId(userId) end
    return UserId.Normalize(userId)
end

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

local function IsRateLimitReason(reason)
    return string.find(tostring(reason or ""), "read rate limit exceeded", 1, true) ~= nil
end

local function StealBackoffKey(uid)
    return tostring(NormalizeUserId(uid) or uid or "unknown")
end

local function EnterStealBackoff(uid, reason)
    if not IsRateLimitReason(reason) then return end
    stealBackoffUntilByUid_[StealBackoffKey(uid)] = Now() + STEAL_RATE_LIMIT_BACKOFF
end

local function IsStealBackoffActive(uid)
    local key = StealBackoffKey(uid)
    local untilTime = tonumber(stealBackoffUntilByUid_[key] or 0) or 0
    if untilTime <= 0 then return false end
    if Now() < untilTime then return true end
    stealBackoffUntilByUid_[key] = nil
    return false
end

local function SendRateLimitedPayload()
    return {
        code = "RATE_LIMITED",
        retryable = true,
    }
end

local function GetCachedStealDaily(uid)
    local cache = stealDailyCacheByUid_[StealBackoffKey(uid)]
    if cache == nil then return nil end
    if tostring(cache.day or "") ~= tostring(os and os.date and os.date("%Y%m%d", Now()) or "unknown") then
        stealDailyCacheByUid_[StealBackoffKey(uid)] = nil
        return nil
    end
    if Now() - (tonumber(cache.updatedAt or 0) or 0) > STEAL_DAILY_CACHE_TTL then return nil end
    return cache
end

local function StoreStealDaily(uid, stealCount, stealLimit)
    local count = math.max(0, math.floor(tonumber(stealCount or 0) or 0))
    local limit = math.max(0, math.floor(tonumber(stealLimit or deps_.dailyStealLimit or 0) or 0))
    stealDailyCacheByUid_[StealBackoffKey(uid)] = {
        stealCount = count,
        stealLimit = limit,
        updatedAt = Now(),
        day = os and os.date and os.date("%Y%m%d", Now()) or "unknown",
    }
    return count, limit
end

local function AddCachedStealCount(uid, delta, stealLimit)
    local cache = GetCachedStealDaily(uid)
    local current = cache and cache.stealCount or 0
    local limit = stealLimit or (cache and cache.stealLimit) or deps_.dailyStealLimit
    StoreStealDaily(uid, current + (delta or 0), limit)
end

function ServerSteal.RefreshStealDailyCache(uid, daily)
    if type(daily) ~= "table" then return false end
    local cached = GetCachedStealDaily(uid)
    local stealCount = tonumber(daily.stealCount)
    if stealCount == nil and cached ~= nil then stealCount = cached.stealCount end
    if stealCount == nil then return false end
    local stealLimit = tonumber(daily.stealLimit or daily.limit or (cached and cached.stealLimit) or deps_.dailyStealLimit)
    StoreStealDaily(uid, stealCount, stealLimit)
    return true
end

local function GetFarmPlot(state, plotIndex)
    return deps_.GetFarmPlot(state, plotIndex)
end

local function FindFarmCrop(state, cropId)
    return deps_.FindFarmCrop(state, cropId)
end

local function RefreshAuthCrop(crop)
    deps_.RefreshAuthCrop(crop)
end

local function IsCropStolenToday(crop)
    if deps_.IsCropStolenToday ~= nil then
        return deps_.IsCropStolenToday(crop) == true
    end
    if type(crop) ~= "table" or crop.stolen ~= true then return false end
    local stolenAt = tonumber(crop.stolenAt or 0) or 0
    if stolenAt <= 0 then return false end
    return os.date("%Y%m%d", stolenAt) == os.date("%Y%m%d", Now())
end

local function IsStealTimestampToday(timestamp)
    timestamp = tonumber(timestamp or 0) or 0
    if timestamp <= 0 then return false end
    return os.date("%Y%m%d", timestamp) == os.date("%Y%m%d", Now())
end

local function HasTodayStealRows(rows)
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and IsStealTimestampToday(value.stolenAt or value.time) then
            return true
        end
    end
    return false
end

local function GetMaxCropsPerPlot()
    return deps_.GetMaxCropsPerPlot()
end

function ServerSteal.GetStealChance(crop)
    local rarity = crop and crop.rarity or crop and crop.config and crop.config.rarity or "普通"
    local chances = {
        ["普通"] = 0.80,
        ["罕见"] = 0.65,
        ["稀有"] = 0.48,
        ["史诗"] = 0.32,
        ["传奇"] = 0.18,
        ["神话"] = 0.10,
    }
    return chances[rarity] or 0.45
end

function ServerSteal.RollStealReward(crop)
    local seedId = crop and crop.plantIndex or 1
    local chance = ServerSteal.GetStealChance(crop)
    if math.random() <= chance then
        return { type = "seed", seedId = seedId, count = 1, chance = chance }
    end
    return { type = "none", chance = chance }
end

function ServerSteal.BuildStealRecordKey(targetUid, cropId)
    return "steal_record_" .. tostring(NormalizeUserId(targetUid) or targetUid) .. "_" .. tostring(cropId or "unknown")
end

function ServerSteal.BuildStealCropClaimKey(cropId)
    return "steal_crop_claim_" .. tostring(cropId or "unknown")
end

local function SendFail(connection, requestId, message, extra)
    local payload = { success = false, message = message or "偷菜失败", requestId = requestId }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, payload)
end

local function CommitStealSideEffects(ctx)
    local c = serverCloud:BatchCommit("权威偷菜")
    ---@diagnostic disable-next-line: param-type-mismatch
    -- 按自然日刷新：跨天后同一作物可再次被抢占（与 stealable 日重置一致）
    c:QuotaAdd(ctx.targetCloudUid, ctx.cropClaimKey, 1, 1, "day", 1)
    ---@diagnostic disable-next-line: param-type-mismatch
    c:ListAdd(ctx.thiefCloudUid, ctx.recordKey, {
        targetUserId = ctx.targetUserId,
        cropId = ctx.actualCropId,
        stolenAt = Now(),
    })
    ---@diagnostic disable-next-line: param-type-mismatch
    c:ListAdd(ctx.targetCloudUid, ctx.cropClaimKey, {
        thiefUserId = ctx.thiefUid,
        cropId = ctx.actualCropId,
        stolenAt = Now(),
    })
    ---@diagnostic disable-next-line: param-type-mismatch
    c:ListAdd(ctx.targetCloudUid, deps_.Shared.KEYS.STEAL_LOGS, ctx.log)
    ---@diagnostic disable-next-line: param-type-mismatch
    c:QuotaAdd(ctx.thiefCloudUid, "daily_steal", 1, ctx.stealLimit or deps_.dailyStealLimit, "day", 1)
    deps_.RequestGuard.AddToCommit(c, ctx.uid, ctx.requestRecordKey, ctx.response)
    c:Commit({
        ok = function() end,
        error = function(_, reason)
            print("[偷菜] 附加记录提交失败: " .. tostring(reason))
        end,
    })
    AddCachedStealCount(ctx.uid, 1, ctx.stealLimit)
    Send(ctx.connection, deps_.Shared.EVENTS.STEAL_RESPONSE, ctx.response)
end

local function RollbackTargetCrop(targetUserId, actualCropId, done)
    deps_.PlayerStateService.MutateFarm(targetUserId, "steal_rollback", function(farm)
        local crop = FindFarmCrop(farm, actualCropId)
        if crop ~= nil then
            crop.stolen = false
            crop.stolenBy = nil
            crop.stolenAt = nil
            crop.stealable = true
            crop.stealReward = nil
        end
        return { success = true }
    end, function()
        if done ~= nil then done() end
    end)
end

function ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
    local thiefUid = NormalizeUserId(uid)
    local targetUserId = NormalizeUserId(targetUid)
    local thiefCloudUid = CloudUid(thiefUid or uid)
    local targetCloudUid = CloudUid(targetUserId)
    cropIndex = NormalizePositiveCount(cropIndex or 1, GetMaxCropsPerPlot())
    cropId = tostring(cropId or "")
    if thiefUid == nil or targetUserId == nil then
        SendFail(connection, requestId, "目标花园无效")
        return
    end
    if thiefUid == targetUserId then
        SendFail(connection, requestId, "不能偷自己的菜")
        return
    end

    local function afterListsOk()
        -- 1) 目标农场队列：标记被偷（Load 会建会话，与目标自己的操作串行）
        deps_.PlayerStateService.MutateFarm(targetUserId, "steal_mark", function(farm)
            local crop, actualPlotIndex, actualIndex = FindFarmCrop(farm, cropId)
            if crop == nil and cropId == "" then
                local plot = GetFarmPlot(farm, 1)
                crop = plot and plot.plants and plot.plants[cropIndex]
                actualPlotIndex = 1
                actualIndex = cropIndex
            end
            if crop == nil then
                return { success = false, message = "没有找到这株作物" }
            end
            RefreshAuthCrop(crop)
            local actualCropId = tostring(crop.serverCropId or crop.cropId or cropId)
            if crop.mature ~= true then
                return { success = false, message = "这株作物还没成熟" }
            end
            if IsCropStolenToday(crop) then
                return { success = false, message = "这株作物今天已经被偷过了" }
            end
            -- 跨日旧标记：清掉后允许今日再偷
            if crop.stolen == true then
                crop.stolen = false
                crop.stolenBy = nil
                crop.stolenAt = nil
                crop.stealReward = nil
            end

            local reward = ServerSteal.RollStealReward(crop)
            local now = Now()
            crop.stolen = true
            crop.stolenBy = thiefUid
            crop.stolenAt = now
            crop.stealable = false
            crop.stealReward = reward

            local log = {
                thiefUserId = thiefUid,
                targetUserId = targetUserId,
                cropId = actualCropId,
                cropIndex = actualIndex,
                cropName = crop.name or "作物",
                seedId = crop.plantIndex or reward.seedId or 1,
                gotSeed = reward.type == "seed",
                reward = reward,
                stolenAt = now,
                time = now,
            }
            return {
                success = true,
                reward = reward,
                log = log,
                actualCropId = actualCropId,
                actualIndex = actualIndex,
            }
        end, function(markResult)
            if markResult == nil or markResult.success ~= true then
                SendFail(connection, requestId, markResult and markResult.message or "偷菜失败")
                return
            end

            local reward = markResult.reward
            local log = markResult.log
            local actualCropId = markResult.actualCropId

            -- 2) 小偷经济队列：发奖
            deps_.PlayerStateService.MutateEconomy(thiefUid, "steal_reward", function(economy)
                if reward.type == "seed" then
                    local seedId = NormalizePlantIndex(reward.seedId or 1) or 1
                    local current = tonumber(economy.seedBag[seedId] or 0) or 0
                    economy.seedBag[seedId] = current + 1
                    economy.collectedPlants[seedId] = true
                    reward.seedId = seedId
                end
                local message = "偷菜成功，但没有获得种子"
                if reward.type == "seed" then
                    message = "偷菜成功，奖励已发放"
                end
                return {
                    success = true,
                    response = {
                        success = true,
                        message = message,
                        requestId = requestId,
                        reward = reward,
                        cropId = actualCropId,
                        cropIndex = markResult.actualIndex,
                        daily = { stealCountDelta = 1, limit = stealLimit or deps_.dailyStealLimit },
                        state = economy,
                    },
                }
            end, function(rewardResult)
                if rewardResult == nil or rewardResult.success ~= true then
                    RollbackTargetCrop(targetUserId, actualCropId, function()
                        SendFail(connection, requestId, rewardResult and rewardResult.message or "偷菜失败")
                    end)
                    return
                end
                CommitStealSideEffects({
                    uid = uid,
                    connection = connection,
                    thiefUid = thiefUid,
                    targetUserId = targetUserId,
                    thiefCloudUid = thiefCloudUid,
                    targetCloudUid = targetCloudUid,
                    recordKey = ServerSteal.BuildStealRecordKey(targetUserId, actualCropId),
                    cropClaimKey = ServerSteal.BuildStealCropClaimKey(actualCropId),
                    actualCropId = actualCropId,
                    log = log,
                    stealLimit = stealLimit,
                    requestRecordKey = requestRecordKey,
                    response = rewardResult.response,
                })
            end)
        end)
    end

    -- 先用 cropId 查个人记录；最终以 mark 后的 actualCropId 写记录
    local function checkClaimThenMark(actualCropIdForCheck)
        local recordKeyCheck = ServerSteal.BuildStealRecordKey(targetUserId, actualCropIdForCheck)
        local cropClaimKey = ServerSteal.BuildStealCropClaimKey(actualCropIdForCheck)
        ServerCloudStore.ListGet(thiefCloudUid, recordKeyCheck, {
            ok = function(records)
                if HasTodayStealRows(records) then
                    SendFail(connection, requestId, "这株作物你今天已经偷过了")
                    return
                end
                ServerCloudStore.ListGet(targetCloudUid, cropClaimKey, {
                    ok = function(claimRows)
                        if HasTodayStealRows(claimRows) then
                            SendFail(connection, requestId, "这株作物今天已经被偷过了")
                            return
                        end
                        afterListsOk()
                    end,
                    error = function(_, reason)
                        EnterStealBackoff(uid, reason)
                        if IsRateLimitReason(reason) then
                            SendFail(connection, requestId, "服务器繁忙，请稍后再试", SendRateLimitedPayload())
                        else
                            SendFail(connection, requestId, "作物偷取记录读取失败: " .. tostring(reason))
                        end
                    end,
                })
            end,
            error = function(_, reason)
                EnterStealBackoff(uid, reason)
                if IsRateLimitReason(reason) then
                    SendFail(connection, requestId, "服务器繁忙，请稍后再试", SendRateLimitedPayload())
                else
                    SendFail(connection, requestId, "偷菜记录读取失败: " .. tostring(reason))
                end
            end,
        })
    end

    if cropId ~= "" then
        checkClaimThenMark(cropId)
    else
        -- 无 cropId 时跳过 claim 预检，由 MutateFarm 内 stolen 标记兜底
        afterListsOk()
    end
end

function ServerSteal.RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    if IsStealBackoffActive(uid) then
        SendFail(connection, requestId, "服务器繁忙，请稍后再试", SendRateLimitedPayload())
        return
    end
    local cachedDaily = GetCachedStealDaily(uid)
    if cachedDaily ~= nil then
        local stealCount = math.max(0, math.floor(tonumber(cachedDaily.stealCount or 0) or 0))
        local stealLimit = math.max(0, math.floor(tonumber(cachedDaily.stealLimit or deps_.dailyStealLimit) or deps_.dailyStealLimit))
        if stealCount >= stealLimit then
            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, {
                success = false,
                code = "STEAL_LIMIT_REACHED",
                message = "偷取次数不足",
                requestId = requestId,
                daily = { stealCount = stealCount, limit = stealLimit },
            })
            return
        end
        ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
        return
    end
    local thiefCloudUid = CloudUid(NormalizeUserId(uid) or uid)
    ServerCloudStore.QuotaGet(thiefCloudUid, "daily_steal_ad_bonus", {
        ok = function(bonusRows)
            local bonusRow = bonusRows and bonusRows[1]
            local bonus = math.max(0, math.floor(tonumber(bonusRow and bonusRow.value or 0) or 0))
            local stealLimit = deps_.dailyStealLimit + bonus
            ServerCloudStore.QuotaGet(thiefCloudUid, "daily_steal", {
                ok = function(quotaRows)
                    local row = quotaRows and quotaRows[1]
                    local stealCount = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                    StoreStealDaily(uid, stealCount, stealLimit)
                    if stealCount >= stealLimit then
                        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, {
                            success = false,
                            code = "STEAL_LIMIT_REACHED",
                            message = "偷取次数不足",
                            requestId = requestId,
                            daily = { stealCount = stealCount, limit = stealLimit },
                        })
                        return
                    end
                    ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
                end,
                error = function(_, reason)
                    EnterStealBackoff(uid, reason)
                    if IsRateLimitReason(reason) then
                        SendFail(connection, requestId, "服务器繁忙，请稍后再试", SendRateLimitedPayload())
                    else
                        SendFail(connection, requestId, "偷菜次数读取失败: " .. tostring(reason))
                    end
                end,
            })
        end,
        error = function(_, reason)
            EnterStealBackoff(uid, reason)
            if IsRateLimitReason(reason) then
                SendFail(connection, requestId, "服务器繁忙，请稍后再试", SendRateLimitedPayload())
            else
                SendFail(connection, requestId, "偷菜次数上限读取失败: " .. tostring(reason))
            end
        end,
    })
end

return ServerSteal
