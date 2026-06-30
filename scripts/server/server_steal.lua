-- ============================================================================
-- 服务端偷菜系统
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的偷菜次数、作物领取记录和偷菜奖励逻辑。
-- ============================================================================

local ServerSteal = {}

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
    return "steal_record_" .. tostring(targetUid) .. "_" .. tostring(cropId or "unknown")
end

function ServerSteal.BuildStealCropClaimKey(cropId)
    return "steal_crop_claim_" .. tostring(cropId or "unknown")
end

function ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
    cropIndex = NormalizePositiveCount(cropIndex or 1, GetMaxCropsPerPlot())
    cropId = tostring(cropId or "")
    if targetUid == nil or targetUid <= 0 then
        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "目标花园无效" })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "不能偷自己的菜" })
        return
    end

    serverCloud:Get(targetUid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(scores)
            local farmState = NormalizeFarmState(scores[deps_.Shared.KEYS.AUTH_FARM_STATE])
            local crop, actualPlotIndex, actualIndex = FindFarmCrop(farmState, cropId)
            if crop == nil and cropId == "" then
                local plot = GetFarmPlot(farmState, 1)
                crop = plot.plants[cropIndex]
                actualPlotIndex = 1
                actualIndex = cropIndex
            end
            if crop == nil then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "没有找到这株作物" })
                return
            end
            RefreshAuthCrop(crop)
            local actualCropId = tostring(crop.serverCropId or crop.cropId or cropId)
            if crop.mature ~= true then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物还没成熟" })
                return
            end
            if crop.stolen == true then
                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了" })
                return
            end

            local recordKey = ServerSteal.BuildStealRecordKey(targetUid, actualCropId)
            local cropClaimKey = ServerSteal.BuildStealCropClaimKey(actualCropId)
            serverCloud.list:Get(uid, recordKey, {
                ok = function(records)
                    if records ~= nil and #records > 0 then
                        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物你已经偷过了", requestId = requestId })
                        return
                    end
                    serverCloud.list:Get(targetUid, cropClaimKey, {
                        ok = function(claimRows)
                            if claimRows ~= nil and #claimRows > 0 then
                                Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了", requestId = requestId })
                                return
                            end

                            local reward = ServerSteal.RollStealReward(crop)
                            serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
                                ok = function(economyRows)
                                    local economy = GetExistingEconomyState(economyRows)
                                    if economy == nil then
                                        Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "存档尚未初始化，请重新进入游戏", requestId = requestId })
                                        return
                                    end
                                    if reward.type == "seed" then
                                        local seedId = NormalizePlantIndex(reward.seedId or crop.plantIndex or 1) or 1
                                        local current = tonumber(economy.seedBag[seedId] or 0) or 0
                                        economy.seedBag[seedId] = current + 1
                                        economy.collectedPlants[seedId] = true
                                        reward.seedId = seedId
                                    end

                                    local now = Now()
                                    crop.stolen = true
                                    crop.stolenBy = uid
                                    crop.stolenAt = now
                                    crop.stealable = false
                                    crop.stealReward = reward
                                    farmState.updatedAt = now
                                    NextRevision(farmState)
                                    economy.updatedAt = now
                                    NextRevision(economy)

                                    local log = {
                                        thiefUserId = uid,
                                        targetUserId = targetUid,
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
                                    local response = {
                                        success = true,
                                        message = message,
                                        requestId = requestId,
                                        reward = reward,
                                        cropId = actualCropId,
                                        cropIndex = actualIndex,
                                        daily = { stealCountDelta = 1, limit = stealLimit or deps_.dailyStealLimit },
                                        state = economy,
                                    }
                                    local c = serverCloud:BatchCommit("权威偷菜")
                                    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, economy)
                                    c:ScoreSet(targetUid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                                    c:ListAdd(uid, recordKey, { targetUserId = targetUid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, cropClaimKey, { thiefUserId = uid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, deps_.Shared.KEYS.STEAL_LOGS, log)
                                    c:QuotaAdd(uid, "daily_steal", 1, stealLimit or deps_.dailyStealLimit, "day", 1)
                                    deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                                    c:Commit({
                                        ok = function()
                                            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, response)
                                        end,
                                        error = function(_, reason)
                                            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜失败: " .. tostring(reason), requestId = requestId, state = economy })
                                        end,
                                    })
                                end,
                                error = function(_, reason)
                                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = requestId })
                                end,
                            })
                        end,
                        error = function(_, reason)
                            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "作物偷取记录读取失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜记录读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "读取目标花园失败: " .. tostring(reason) })
        end,
    })
end

function ServerSteal.RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    serverCloud.quota:Get(uid, "daily_steal_ad_bonus", {
        ok = function(bonusRows)
            local bonusRow = bonusRows and bonusRows[1]
            local bonus = math.max(0, math.floor(tonumber(bonusRow and bonusRow.value or 0) or 0))
            local stealLimit = deps_.dailyStealLimit + bonus
            serverCloud.quota:Get(uid, "daily_steal", {
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
                    Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数上限读取失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

return ServerSteal
