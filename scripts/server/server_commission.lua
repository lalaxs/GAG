-- ============================================================================
-- 服务端委托系统
-- Grow A Garden
-- ============================================================================
-- 委托状态独立云存；经济消耗/奖励统一修改 PlayerStateService 内存状态。
-- ============================================================================

local ServerCommission = {}

local ServerCloudStore = require("server.server_cloud_store")

local deps_ = {}
local ServerConfig = require("config.server_tuning")

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

local COMMISSION_STATE_KEY = ServerConfig.Commission.STATE_KEY
local COMMISSION_REFRESH_INTERVAL = ServerConfig.Commission.REFRESH_INTERVAL
local COMMISSION_COUNT = ServerConfig.Commission.COUNT
local COMMISSION_CUSTOMERS = ServerConfig.Commission.CUSTOMERS
local COMMISSION_COLOR_REQUIREMENTS = ServerConfig.Commission.COLOR_REQUIREMENTS
local COMMISSION_SPECIAL_REQUIREMENTS = ServerConfig.Commission.SPECIAL_REQUIREMENTS
local COMMISSION_PACK_DIFFICULTY = ServerConfig.Commission.PACK_DIFFICULTY
local COMMISSION_REWARD_POOLS = ServerConfig.Commission.REWARD_POOLS

ServerCommission.COMMISSION_STATE_KEY = COMMISSION_STATE_KEY

function ServerCommission.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function RandItem(list)
    return deps_.RandItem(list)
end

local function RandomRange(minValue, maxValue)
    return deps_.RandomRange(minValue, maxValue)
end

local function RollWeighted(pool)
    return deps_.RollWeighted(pool)
end

local function SendMutationResult(connection, eventName, result, requestId)
    if type(result) == "table" and type(result.response) == "table" then
        Send(connection, eventName, result.response)
        return
    end
    Send(connection, eventName, {
        success = false,
        message = type(result) == "table" and result.message or "同步失败",
        retryable = type(result) == "table" and result.retryable == true,
        requestId = requestId,
    })
end

function ServerCommission.FindMutationByKey(list, key)
    if list == nil then return nil end
    for _, item in ipairs(list) do
        if item.key == key then return item end
    end
    return nil
end

function ServerCommission.IsCommissionEligiblePlant(plant)
    return plant ~= nil and plant.limited ~= true and plant.activityTag == nil
end

function ServerCommission.PickCommissionPlantIndex(level)
    local rarityPool = { "普通" }
    if level >= 21 then rarityPool = { "普通", "罕见", "稀有", "史诗", "传奇" }
    elseif level >= 16 then rarityPool = { "普通", "罕见", "稀有", "史诗" }
    elseif level >= 11 then rarityPool = { "普通", "罕见", "稀有" }
    elseif level >= 6 then rarityPool = { "普通", "罕见" } end
    local pool = {}
    for _, rarity in ipairs(rarityPool) do
        local indices = deps_.GameConfig.RARITY_PLANT_INDICES and deps_.GameConfig.RARITY_PLANT_INDICES[rarity] or {}
        for _, plantIndex in ipairs(indices) do
            if ServerCommission.IsCommissionEligiblePlant(deps_.GameConfig.PLANTS[plantIndex]) then pool[#pool + 1] = plantIndex end
        end
    end
    return pool[math.random(1, math.max(1, #pool))] or 1
end

function ServerCommission.GetCommissionRewardPack(plant)
    local pool = COMMISSION_REWARD_POOLS[plant and plant.rarity or "普通"] or COMMISSION_REWARD_POOLS["普通"]
    local picked = RollWeighted(pool)
    return picked and picked.packId or "pack_common"
end

function ServerCommission.BuildCommissionMutationRequirement(packId)
    local difficulty = COMMISSION_PACK_DIFFICULTY[packId] or COMMISSION_PACK_DIFFICULTY.pack_rare
    local kind = RandItem(difficulty.mutationKinds)
    if kind == "color" then
        local key = RandItem(COMMISSION_COLOR_REQUIREMENTS)
        local mutation = ServerCommission.FindMutationByKey(deps_.GameConfig.COLOR_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "颜色变异" }
    elseif kind == "special" then
        local key = RandItem(COMMISSION_SPECIAL_REQUIREMENTS)
        local mutation = ServerCommission.FindMutationByKey(deps_.GameConfig.SPECIAL_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "特殊变异" }
    elseif kind == "giant" then
        return { kind = kind, key = "Giant", name = "巨大作物" }
    end
    return { kind = "basic", key = "basic", name = "任意基础变异" }
end

function ServerCommission.BuildCommission(index, level)
    local plantIndex = ServerCommission.PickCommissionPlantIndex(level)
    local plant = deps_.GameConfig.PLANTS[plantIndex]
    local rewardPackId = ServerCommission.GetCommissionRewardPack(plant)
    local difficulty = COMMISSION_PACK_DIFFICULTY[rewardPackId] or COMMISSION_PACK_DIFFICULTY.pack_rare
    local scale = difficulty.minWeightScale
    local minWeight = (plant and plant.baseWeight or 1.0) * RandomRange(scale[1], scale[2])
    local packCfg = deps_.GameConfig.SEED_PACK_CONFIG[rewardPackId]
    return {
        id = string.format("commission_%d_%d_%d", Now(), index, math.random(1000, 9999)),
        customer = RandItem(COMMISSION_CUSTOMERS),
        plantIndex = plantIndex,
        plantName = plant and plant.name or "作物",
        plantRarity = plant and plant.rarity or "普通",
        mutation = ServerCommission.BuildCommissionMutationRequirement(rewardPackId),
        minWeight = minWeight,
        rewardPackId = rewardPackId,
        rewardPackName = packCfg and packCfg.packName or "普通种子包",
        completed = false,
    }
end

function ServerCommission.NormalizeCommissionState(state, level)
    state = type(state) == "table" and state or {}
    local now = Now()
    local lastRefresh = tonumber(state.lastRefreshRealTime or 0) or 0
    state.commissions = type(state.commissions) == "table" and state.commissions or {}
    if #state.commissions == 0 or now - lastRefresh >= COMMISSION_REFRESH_INTERVAL then
        state.commissions = {}
        for i = 1, COMMISSION_COUNT do state.commissions[#state.commissions + 1] = ServerCommission.BuildCommission(i, level or 1) end
        state.lastRefreshRealTime = now
        state.timer = COMMISSION_REFRESH_INTERVAL
    else
        state.timer = math.max(0, COMMISSION_REFRESH_INTERVAL - (now - lastRefresh))
    end
    return state
end

function ServerCommission.HasColorMutation(item, key)
    local colorMutation = item and item.mutation and item.mutation.colorMutation
    return colorMutation ~= nil and colorMutation.key == key
end

local function HasSpecialMutation(item, key)
    local specials = item and item.mutation and item.mutation.specials
    if specials == nil then return false end
    for _, special in ipairs(specials) do if special.key == key then return true end end
    return false
end

function ServerCommission.HasBasicMutation(item)
    local mutation = item and item.mutation
    return mutation ~= nil and (mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil)
end

function ServerCommission.CommissionItemMatches(commission, item)
    if commission == nil or item == nil then return false end
    if item.plantIndex ~= commission.plantIndex then return false end
    if (item.weight or 0) < (commission.minWeight or 0) then return false end
    local req = commission.mutation
    if req == nil then return true end
    if req.kind == "color" then return ServerCommission.HasColorMutation(item, req.key) end
    if req.kind == "special" then return HasSpecialMutation(item, req.key) end
    if req.kind == "giant" then return item.weightTier == "Giant" end
    if req.kind == "basic" then return ServerCommission.HasBasicMutation(item) end
    return true
end

function ServerCommission.RequestCommissionsAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    deps_.PlayerStateService.Load(uid, function(session, err)
        if session == nil then
            Send(connection, deps_.Shared.EVENTS.COMMISSIONS_RESPONSE, { success = false, retryable = true, message = "同步失败", requestId = payload.requestId })
            return
        end
        local level = session.economy and session.economy.talent and session.economy.talent.level or 1
        ServerCloudStore.Get(uid, COMMISSION_STATE_KEY, {
            ok = function(rows)
                local commissionState = ServerCommission.NormalizeCommissionState(rows[COMMISSION_STATE_KEY], level)
                ServerCloudStore.SetScore(uid, COMMISSION_STATE_KEY, commissionState)
                Send(connection, deps_.Shared.EVENTS.COMMISSIONS_RESPONSE, { success = true, requestId = payload.requestId, commission = commissionState })
            end,
            error = function()
                local commissionState = ServerCommission.NormalizeCommissionState(nil, level)
                ServerCloudStore.SetScore(uid, COMMISSION_STATE_KEY, commissionState)
                Send(connection, deps_.Shared.EVENTS.COMMISSIONS_RESPONSE, { success = true, requestId = payload.requestId, commission = commissionState })
            end,
        })
    end)
end

function ServerCommission.CompleteCommissionAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    ServerCloudStore.Get(uid, COMMISSION_STATE_KEY, {
        ok = function(rows)
            deps_.PlayerStateService.MutateEconomy(uid, "complete_commission", function(economy)
                local commissionState = ServerCommission.NormalizeCommissionState(rows[COMMISSION_STATE_KEY], economy.talent and economy.talent.level or 1)
                local commission = nil
                for _, row in ipairs(commissionState.commissions or {}) do
                    if row.id == payload.commissionId then commission = row; break end
                end
                local itemIndex = math.floor(tonumber(payload.itemIndex or 0) or 0)
                local item = itemIndex > 0 and economy.harvested[itemIndex] or nil
                if commission == nil then return { success = false, response = { success = false, message = "委托不存在", requestId = payload.requestId, state = economy, commission = commissionState } } end
                if commission.completed then return { success = false, response = { success = false, message = "委托已完成", requestId = payload.requestId, state = economy, commission = commissionState } } end
                if item == nil then return { success = false, response = { success = false, message = "作物已不存在", requestId = payload.requestId, state = economy, commission = commissionState } } end
                if not ServerCommission.CommissionItemMatches(commission, item) then return { success = false, response = { success = false, message = "作物不满足委托条件", requestId = payload.requestId, state = economy, commission = commissionState } } end
                table.remove(economy.harvested, itemIndex)
                economy.seedPacks[commission.rewardPackId] = (tonumber(economy.seedPacks[commission.rewardPackId] or 0) or 0) + 1
                commission.completed = true
                local message = string.format("完成%s的委托，获得%s", commission.customer or "客人", commission.rewardPackName or "种子包")
                return { success = true, response = { success = true, message = message, requestId = payload.requestId, state = economy, commission = commissionState } }
            end, function(result)
                local response = result and result.response or nil
                if result ~= nil and result.success == true and type(response) == "table" then
                    local c = serverCloud:BatchCommit("委托状态保存")
                    ServerCloudStore.BatchScoreSet(c, uid, COMMISSION_STATE_KEY, response.commission)
                    c:Commit({
                        ok = function() end,
                        error = function(_, reason) print("[委托] 状态保存失败: " .. tostring(reason)) end,
                    })
                end
                SendMutationResult(connection, deps_.Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, result, payload.requestId)
            end)
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "委托数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

return ServerCommission
