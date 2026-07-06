-- ============================================================================
-- 服务端偷菜系统
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的偷菜次数、作物领取记录和偷菜奖励逻辑。
-- ============================================================================

local UserId = require("utils.user_id")
local ServerCloudStore = require("server.server_cloud_store")

local ServerSteal = {}

local STEAL_RATE_LIMIT_BACKOFF = 8
local stealBackoffUntilByUid_ = {}

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

local function NormalizeEconomyState(state)
    return deps_.NormalizeEconomyState(state)
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

local function BuildInitialEconomyState()
    return deps_.BuildInitialEconomyState()
end

local function GetExistingEconomyState(scores)
    local state = scores and scores[deps_.Shared.KEYS.ECONOMY_STATE]
    if type(state) ~= "table" then return nil end
    return NormalizeEconomyState(state)
end

local function NormalizeFarmState(state)
    return deps_.NormalizeFarmState(state)
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

local function NextRevision(state)
    deps_.NextRevision(state)
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

function ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
    local thiefUid = NormalizeUserId(uid)
    local targetUserId = NormalizeUserId(targetUid)
    local thiefCloudUid = CloudUid(thiefUid or uid)
    local targetCloudUid = CloudUid(targetUserId)
    cropIndex = NormalizePositiveCount(cropIndex or 1, GetMaxCropsPerPlot())
    cropId = tostring(cropId or "")
    if thiefUid == nil or targetUserId == nil then
        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "目标花园无效", requestId = requestId })
        return
    end
    if thiefUid == targetUserId then
        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "不能偷自己的菜", requestId = requestId })
        return
    end

    local function beginStealWithFarm(farmState)
            local crop, actualPlotIndex, actualIndex = FindFarmCrop(farmState, cropId)
            if crop == nil and cropId == "" then
                local plot = GetFarmPlot(farmState, 1)
                crop = plot.plants[cropIndex]
                actualPlotIndex = 1
                actualIndex = cropIndex
            end
            if crop == nil then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "没有找到这株作物", requestId = requestId })
                return
            end
            RefreshAuthCrop(crop)
            local actualCropId = tostring(crop.serverCropId or crop.cropId or cropId)
            if crop.mature ~= true then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物还没成熟", requestId = requestId })
                return
            end
            if crop.stolen == true then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了", requestId = requestId })
                return
            end

            local recordKey = ServerSteal.BuildStealRecordKey(targetUserId, actualCropId)
            local cropClaimKey = ServerSteal.BuildStealCropClaimKey(actualCropId)
            ServerCloudStore.ListGet(thiefCloudUid, recordKey, {
                ok = function(records)
                    if records ~= nil and #records > 0 then
                        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物你已经偷过了", requestId = requestId })
                        return
                    end
                    ServerCloudStore.ListGet(targetCloudUid, cropClaimKey, {
                        ok = function(claimRows)
                            if claimRows ~= nil and #claimRows > 0 then
                                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了", requestId = requestId })
                                return
                            end

                            local reward = ServerSteal.RollStealReward(crop)
                            deps_.PlayerStateService.MutateEconomy(thiefUid, "steal_reward", function(economy)
                                if reward.type == "seed" then
                                    local seedId = NormalizePlantIndex(reward.seedId or crop.plantIndex or 1) or 1
                                    local current = tonumber(economy.seedBag[seedId] or 0) or 0
                                    economy.seedBag[seedId] = current + 1
                                    economy.collectedPlants[seedId] = true
                                    reward.seedId = seedId
                                end

                                local now = Now()
                                crop.stolen = true
                                crop.stolenBy = thiefUid
                                crop.stolenAt = now
                                crop.stealable = false
                                crop.stealReward = reward
                                farmState.updatedAt = now
                                NextRevision(farmState)

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
                                        cropIndex = actualIndex,
                                        daily = { stealCountDelta = 1, limit = stealLimit or deps_.dailyStealLimit },
                                        state = economy,
                                    },
                                    log = log,
                                }
                            end, function(result)
                                local response = result and result.response or nil
                                if result == nil or result.success ~= true or type(response) ~= "table" then
                                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = result and result.message or "偷菜失败", requestId = requestId })
                                    return
                                end
                                local log = result.log
                                -- 目标若有内存会话，标记脏档并由会话 flush，避免用过期云档覆盖
                                if deps_.PlayerStateService.HasLoadedSession(targetUserId) then
                                    deps_.PlayerStateService.MarkDirty(targetUserId, "farm")
                                    deps_.PlayerStateService.Flush(targetUserId)
                                end
                                local c = serverCloud:BatchCommit("权威偷菜")
                                ---@diagnostic disable-next-line: param-type-mismatch
                                c:QuotaAdd(targetCloudUid, cropClaimKey, 1, 1)
                                if not deps_.PlayerStateService.HasLoadedSession(targetUserId) then
                                    ServerCloudStore.BatchScoreSet(c, targetUserId, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                                end
                                ---@diagnostic disable-next-line: param-type-mismatch
                                c:ListAdd(thiefCloudUid, recordKey, { targetUserId = targetUserId, cropId = actualCropId, stolenAt = Now() })
                                ---@diagnostic disable-next-line: param-type-mismatch
                                c:ListAdd(targetCloudUid, cropClaimKey, { thiefUserId = thiefUid, cropId = actualCropId, stolenAt = Now() })
                                ---@diagnostic disable-next-line: param-type-mismatch
                                c:ListAdd(targetCloudUid, deps_.Shared.KEYS.STEAL_LOGS, log)
                                ---@diagnostic disable-next-line: param-type-mismatch
                                c:QuotaAdd(thiefCloudUid, "daily_steal", 1, stealLimit or deps_.dailyStealLimit, "day", 1)
                                deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                                c:Commit({
                                    ok = function() end,
                                    error = function(_, reason)
                                        print("[偷菜] 附加记录提交失败: " .. tostring(reason))
                                    end,
                                })
                                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, response)
                            end)
                        end,
                        error = function(_, reason)
                            EnterStealBackoff(uid, reason)
                            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "作物偷取记录读取失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    EnterStealBackoff(uid, reason)
                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜记录读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
    end

    local targetSession = deps_.PlayerStateService.GetSession(targetUserId)
    if targetSession ~= nil and type(targetSession.farm) == "table" then
        beginStealWithFarm(targetSession.farm)
        return
    end

    ServerCloudStore.Get(targetCloudUid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(farmScores)
            local farmState = NormalizeFarmState(farmScores[deps_.Shared.KEYS.AUTH_FARM_STATE])
            beginStealWithFarm(farmState)
        end,
        error = function(_, reason)
            EnterStealBackoff(uid, reason)
            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "读取目标花园失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

function ServerSteal.RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    if IsStealBackoffActive(uid) then
        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "服务器繁忙，请稍后再偷菜", requestId = requestId })
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
                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            EnterStealBackoff(uid, reason)
            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数上限读取失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

return ServerSteal
