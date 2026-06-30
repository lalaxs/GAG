-- ============================================================================
-- 服务端活动系统
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的活动周期、活动奖励、活动兑换和活动抽取权威逻辑。
-- ============================================================================

local ServerActivity = {}

local deps_ = {}

function ServerActivity.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function NormalizeActivityState(activity)
    return deps_.NormalizeActivityState(activity)
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

local function SendMissingEconomyState(connection, eventName, requestId)
    Send(connection, eventName, { success = false, message = "存档尚未初始化，请重新进入游戏", requestId = requestId })
end

local function NormalizePositiveCount(value, maxValue)
    return deps_.NormalizePositiveCount(value, maxValue)
end

local function NormalizePlantIndex(value)
    return deps_.NormalizePlantIndex(value)
end

local function IsValidPackId(packId)
    return deps_.IsValidPackId(packId)
end

local function RollWeighted(pool)
    return deps_.RollWeighted(pool)
end

local function NextRevision(state)
    deps_.NextRevision(state)
end

local function AddActivityRankCommit(commit, uid, state)
    deps_.AddActivityRankCommit(commit, uid, state)
end

function ServerActivity.GetActiveActivityId()
    return deps_.GameConfig.GetActiveActivityId and deps_.GameConfig.GetActiveActivityId(Now()) or "sweet"
end

function ServerActivity.GetCurrentActivityCycleInfo()
    if deps_.GameConfig.GetActivityCycleInfo then
        return deps_.GameConfig.GetActivityCycleInfo(Now())
    end
    return { activityId = ServerActivity.GetActiveActivityId(), cycleId = "sweet_0", cycleIndex = 0, timeLeft = 0 }
end

function ServerActivity.GetPreviousActivityCycleInfo()
    local current = ServerActivity.GetCurrentActivityCycleInfo()
    local duration = math.max(1, math.floor(tonumber(current.duration or ((deps_.GameConfig.ACTIVITY_CONFIG and deps_.GameConfig.ACTIVITY_CONFIG.cycleDays or 3) * 86400)) or 1))
    local previousTime = math.max(0, math.floor(tonumber(current.cycleStart or Now()) or Now()) - 1)
    if previousTime <= 0 then return nil end
    if deps_.GameConfig.GetActivityCycleInfo then
        return deps_.GameConfig.GetActivityCycleInfo(previousTime)
    end
    return { activityId = ServerActivity.GetActiveActivityId(previousTime), cycleId = "sweet_0", cycleIndex = 0, timeLeft = duration }
end

function ServerActivity.GetActivityConfig(activityId)
    return ((deps_.GameConfig.ACTIVITY_CONFIG or {}).activities or {})[activityId]
end

function ServerActivity.HasSpecialMutation(item, key)
    local specials = item and item.mutation and item.mutation.specials
    if type(specials) ~= "table" then return false end
    for _, special in ipairs(specials) do
        if special.key == key then return true end
    end
    return false
end

function ServerActivity.GetRarityOrder(rarity)
    return (deps_.GameConfig.RARITY_ORDER or {})[rarity or "普通"] or 1
end

function ServerActivity.GetSweetSubmitValue(item)
    if item == nil then return 0 end
    if not ServerActivity.HasSpecialMutation(item, "candy") and not ServerActivity.HasSpecialMutation(item, "honey") then return 0 end
    local rarityOrder = ServerActivity.GetRarityOrder(item.rarity)
    local base = 5 + rarityOrder * 4 + math.floor((tonumber(item.price or 0) or 0) / 1300)
    if ServerActivity.HasSpecialMutation(item, "honey") then base = math.floor(base * 1.2 + 0.5) end
    if item.weightTier == "Giant" then base = math.floor(base * 1.12 + 0.5) end
    return math.max(3, base)
end

function ServerActivity.FindSweetReward(rewardId)
    local activity = ServerActivity.GetActivityConfig("sweet")
    for _, reward in ipairs(activity and activity.exchangeRewards or {}) do
        if reward.id == rewardId then return reward end
    end
    return nil
end

function ServerActivity.GetDarkSeedWeight(plantIndex)
    local plant = deps_.GameConfig.PLANTS and deps_.GameConfig.PLANTS[plantIndex]
    local weights = { 55, 32, 16, 7, 3 }
    return weights[ServerActivity.GetRarityOrder(plant and plant.rarity)] or 1
end

function ServerActivity.RollDarkSeed(activity)
    local pool = activity and activity.darkSeedPool or { 42, 43, 44, 45, 46, 47 }
    local weightedPool = {}
    for _, plantIndex in ipairs(pool) do
        weightedPool[#weightedPool + 1] = { plantIndex = plantIndex, weight = ServerActivity.GetDarkSeedWeight(plantIndex) }
    end
    local picked = RollWeighted(weightedPool)
    return picked and picked.plantIndex or pool[1]
end

function ServerActivity.ApplyActivityHarvestReward(state, crop)
    local activityId = ServerActivity.GetActiveActivityId()
    local activity = ServerActivity.GetActivityConfig(activityId)
    if activity == nil or crop == nil then return nil end
    state.activity = NormalizeActivityState(state.activity)
    local rarityOrder = ServerActivity.GetRarityOrder(crop.rarity)
    if activityId == "alien" then
        local chance = ({ 0.18, 0.28, 0.42, 0.58, 0.85 })[rarityOrder] or 0.18
        if math.random() <= chance then
            local amount = 1
            state.activity.alien.genes = state.activity.alien.genes + amount
            state.activity.alien.totalGenes = state.activity.alien.totalGenes + amount
            local text = "获得外星基因 x" .. tostring(amount)
            return { type = "alien_gene", amount = amount, activityId = activityId, toastText = text, message = text }
        end
    elseif activityId == "dark" and (ServerActivity.HasSpecialMutation(crop, "devour") or ServerActivity.HasSpecialMutation(crop, "void")) then
        state.activity.dark.devourHarvestCount = state.activity.dark.devourHarvestCount + 1
        local rates = activity.darkSeedDropRates or { 0.40, 0.55, 0.70, 0.85, 1.00 }
        if math.random() <= (rates[rarityOrder] or 0.40) then
            local plantIndex = ServerActivity.RollDarkSeed(activity)
            local current = tonumber(state.seedBag[plantIndex] or 0) or 0
            state.seedBag[plantIndex] = current + 1
            state.collectedPlants[plantIndex] = true
            state.activity.dark.darkSeedDrops = state.activity.dark.darkSeedDrops + 1
            local plant = deps_.GameConfig.PLANTS[plantIndex]
            local text = "黑暗来临掉落: " .. (plant and (plant.name .. "种子") or "限定种子")
            return { type = "dark_seed", plantIndex = plantIndex, activityId = activityId, toastText = text, message = text }
        end
    end
    return nil
end

function ServerActivity.SubmitActivityCropAuthority(uid, payload, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = GetExistingEconomyState(scores)
            if state == nil then
                SendMissingEconomyState(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, payload.requestId)
                return
            end
            if ServerActivity.GetActiveActivityId() ~= "sweet" then
                Send(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "当前不是甜蜜蜜活动", requestId = payload.requestId, state = state })
                return
            end
            local itemIndex = math.floor(tonumber(payload.itemIndex or 0) or 0)
            local item = itemIndex > 0 and state.harvested[itemIndex] or nil
            local value = ServerActivity.GetSweetSubmitValue(item)
            if item == nil or value <= 0 then
                Send(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "请选择糖果或蜂蜜变异作物", requestId = payload.requestId, state = state })
                return
            end
            table.remove(state.harvested, itemIndex)
            state.activity = NormalizeActivityState(state.activity)
            state.activity.sweet.value = state.activity.sweet.value + value
            state.activity.sweet.submitted = state.activity.sweet.submitted + value
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "上交成功，甜蜜值 +" .. value, requestId = payload.requestId, value = value, state = state }
            local c = serverCloud:BatchCommit("活动作物上交")
            c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            AddActivityRankCommit(c, uid, state)
            deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "上交失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

function ServerActivity.ExchangeActivityRewardAuthority(uid, payload, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = GetExistingEconomyState(scores)
            if state == nil then
                SendMissingEconomyState(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, payload.requestId)
                return
            end
            if ServerActivity.GetActiveActivityId() ~= "sweet" then
                Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "当前不是甜蜜蜜活动", requestId = payload.requestId, state = state })
                return
            end
            local reward = ServerActivity.FindSweetReward(tostring(payload.rewardId or ""))
            if reward == nil then
                Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励不存在", requestId = payload.requestId, state = state })
                return
            end
            state.activity = NormalizeActivityState(state.activity)
            local claimed = tonumber(state.activity.sweet.exchanged[reward.id] or 0) or 0
            if reward.limit ~= nil and claimed >= reward.limit then
                Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "已兑换完", requestId = payload.requestId, state = state })
                return
            end
            if state.activity.sweet.value < reward.cost then
                Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "甜蜜值不足", requestId = payload.requestId, state = state })
                return
            end
            state.activity.sweet.value = state.activity.sweet.value - reward.cost
            state.activity.sweet.exchanged[reward.id] = claimed + 1
            if reward.type == "seed" then
                local plantIndex = NormalizePlantIndex(reward.plantIndex)
                if plantIndex == nil then Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励种子不存在", requestId = payload.requestId, state = state }); return end
                local current = tonumber(state.seedBag[plantIndex] or 0) or 0
                state.seedBag[plantIndex] = current + (reward.count or 1)
                state.collectedPlants[plantIndex] = true
            elseif reward.type == "pack" then
                if not IsValidPackId(reward.packId) then Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励种子包不存在", requestId = payload.requestId, state = state }); return end
                state.seedPacks[reward.packId] = (tonumber(state.seedPacks[reward.packId] or 0) or 0) + (reward.count or 1)
            end
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "兑换成功: " .. tostring(reward.name or "奖励"), requestId = payload.requestId, reward = reward, state = state }
            local c = serverCloud:BatchCommit("活动奖励兑换")
            c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "兑换失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

function ServerActivity.DrawActivityPackAuthority(uid, payload, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = GetExistingEconomyState(scores)
            if state == nil then
                SendMissingEconomyState(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, payload.requestId)
                return
            end
            if ServerActivity.GetActiveActivityId() ~= "alien" then
                Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "当前不是外星基因活动", requestId = payload.requestId, state = state })
                return
            end
            local activity = ServerActivity.GetActivityConfig("alien")
            local drawCount = NormalizePositiveCount(payload.count or 1, 10)
            drawCount = drawCount >= 10 and 10 or 1
            local cost = drawCount >= 10 and (activity.drawCostTen or 95) or (activity.drawCost or 10)
            state.activity = NormalizeActivityState(state.activity)
            if state.activity.alien.genes < cost then
                Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "外星基因不足", requestId = payload.requestId, state = state })
                return
            end
            state.activity.alien.genes = state.activity.alien.genes - cost
            state.activity.alien.drawCount = state.activity.alien.drawCount + drawCount
            local rewards = {}
            for _ = 1, drawCount do
                local picked = RollWeighted(activity.drawPool)
                if picked ~= nil then
                    local reward = { type = picked.type, packId = picked.packId, plantIndex = picked.plantIndex, count = picked.count or 1, name = picked.name }
                    if picked.type == "pack" and IsValidPackId(picked.packId) then
                        state.seedPacks[picked.packId] = (tonumber(state.seedPacks[picked.packId] or 0) or 0) + (picked.count or 1)
                        rewards[#rewards + 1] = reward
                    elseif picked.type == "seed" then
                        local plantIndex = NormalizePlantIndex(picked.plantIndex)
                        if plantIndex ~= nil then
                            local current = tonumber(state.seedBag[plantIndex] or 0) or 0
                            local addCount = math.max(0, math.floor(tonumber(picked.count or 1) or 1))
                            state.seedBag[plantIndex] = current + addCount
                            state.collectedPlants[plantIndex] = true
                            reward.count = addCount
                            rewards[#rewards + 1] = reward
                        end
                    end
                end
            end
            if #rewards <= 0 then
                state.activity.alien.genes = state.activity.alien.genes + cost
                state.activity.alien.drawCount = math.max(0, state.activity.alien.drawCount - drawCount)
                Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "未抽中奖励", requestId = payload.requestId, state = state })
                return
            end
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "基因抽取完成", requestId = payload.requestId, rewards = rewards, state = state }
            local c = serverCloud:BatchCommit("活动基因抽取")
            c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "抽取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

return ServerActivity
