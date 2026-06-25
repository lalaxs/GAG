-- ============================================================================
-- 委托系统 (Commission System)
-- Grow A Garden
-- ============================================================================
-- 管理限时作物求购委托：每 30 分钟刷新一批委托，玩家提交满足作物类型、
-- 变异和重量要求的背包作物后，获得稀有至传奇种子包。
-- ============================================================================

local AudioSystem = require("systems.audio_system")

local CommissionSystem = {}

local cfg_ = nil
local inventory_ = nil
local callbacks_ = {}
local getPlayerLevel_ = nil

local REFRESH_INTERVAL = 30 * 60
local COMMISSION_COUNT = 3

local state_ = {
    commissions = {},
    timer = 0,
    lastRefreshRealTime = 0,
}

local CUSTOMER_NAMES = {
    "露露", "阿麦", "青木", "莓莓", "小枫", "云朵商人", "花园旅人", "星屑收藏家",
}

local COLOR_REQUIREMENTS = {
    "yellow", "blue", "red", "white", "purple", "black",
}

local SPECIAL_REQUIREMENTS = {
    "wet", "frozen", "cloud", "chocolate", "pollen", "glow", "stardust", "ceramic", "rainbow", "void", "gold",
}

local PACK_DIFFICULTY = {
    pack_common = {
        mutationKinds = { "basic" },
        minWeightScale = { 0.90, 1.20 },
    },
    pack_uncommon = {
        mutationKinds = { "color", "basic" },
        minWeightScale = { 1.00, 1.40 },
    },
    pack_rare = {
        mutationKinds = { "color", "basic" },
        minWeightScale = { 1.05, 1.55 },
    },
    pack_epic = {
        mutationKinds = { "color", "special" },
        minWeightScale = { 1.35, 2.20 },
    },
    pack_legendary = {
        mutationKinds = { "special", "giant" },
        minWeightScale = { 2.00, 3.60 },
    },
}

local LEVEL_RARITY_TIERS = {
    { minLevel = 1, maxLevel = 5, rarityPool = { "普通" } },
    { minLevel = 6, maxLevel = 10, rarityPool = { "普通", "罕见" } },
    { minLevel = 11, maxLevel = 15, rarityPool = { "普通", "罕见", "稀有" } },
    { minLevel = 16, maxLevel = 20, rarityPool = { "普通", "罕见", "稀有", "史诗" } },
    { minLevel = 21, maxLevel = nil, rarityPool = { "普通", "罕见", "稀有", "史诗", "传奇" } },
}

local REWARD_PACK_POOLS_BY_PLANT_RARITY = {
    ["普通"] = {
        { packId = "pack_common", weight = 94 },
        { packId = "pack_uncommon", weight = 6 },
    },
    ["罕见"] = {
        { packId = "pack_common", weight = 35 },
        { packId = "pack_uncommon", weight = 55 },
        { packId = "pack_rare", weight = 10 },
    },
    ["稀有"] = {
        { packId = "pack_common", weight = 18 },
        { packId = "pack_uncommon", weight = 30 },
        { packId = "pack_rare", weight = 45 },
        { packId = "pack_epic", weight = 7 },
    },
    ["史诗"] = {
        { packId = "pack_common", weight = 8 },
        { packId = "pack_uncommon", weight = 18 },
        { packId = "pack_rare", weight = 32 },
        { packId = "pack_epic", weight = 38 },
        { packId = "pack_legendary", weight = 4 },
    },
    ["传奇"] = {
        { packId = "pack_common", weight = 3 },
        { packId = "pack_uncommon", weight = 10 },
        { packId = "pack_rare", weight = 22 },
        { packId = "pack_epic", weight = 40 },
        { packId = "pack_legendary", weight = 25 },
    },
}

local function RollWeighted(pool)
    local totalWeight = 0
    for _, item in ipairs(pool) do
        totalWeight = totalWeight + item.weight
    end
    local roll = math.random() * totalWeight
    local cursor = 0
    for _, item in ipairs(pool) do
        cursor = cursor + item.weight
        if roll <= cursor then
            return item
        end
    end
    return pool[#pool]
end

local function RandItem(list)
    return list[math.random(1, #list)]
end

local function RandomRange(minValue, maxValue)
    return minValue + math.random() * (maxValue - minValue)
end

local function FindMutationByKey(list, key)
    if list == nil then return nil end
    for _, item in ipairs(list) do
        if item.key == key then
            return item
        end
    end
    return nil
end

local function IsCommissionEligiblePlant(plant)
    return plant ~= nil and plant.limited ~= true and plant.activityTag == nil
end

local function GetPlantIndicesByRarity(rarity)
    local result = {}
    local rarityIndices = cfg_.RARITY_PLANT_INDICES and cfg_.RARITY_PLANT_INDICES[rarity]
    if rarityIndices ~= nil then
        for _, plantIndex in ipairs(rarityIndices) do
            local plant = cfg_.PLANTS[plantIndex]
            if IsCommissionEligiblePlant(plant) then
                table.insert(result, plantIndex)
            end
        end
    end
    return result
end

local function GetCurrentPlayerLevel()
    if getPlayerLevel_ ~= nil then
        return math.max(1, getPlayerLevel_() or 1)
    end
    return 1
end

local function GetLevelRarityPool(level)
    for _, tier in ipairs(LEVEL_RARITY_TIERS) do
        local maxLevel = tier.maxLevel or math.huge
        if level >= tier.minLevel and level <= maxLevel then
            return tier.rarityPool
        end
    end
    return LEVEL_RARITY_TIERS[#LEVEL_RARITY_TIERS].rarityPool
end

local function BuildPlantPoolByRarities(rarityPool)
    local result = {}
    for _, rarity in ipairs(rarityPool) do
        local indices = GetPlantIndicesByRarity(rarity)
        for _, plantIndex in ipairs(indices) do
            table.insert(result, plantIndex)
        end
    end
    return result
end

local function PickPlantForCurrentLevel()
    local level = GetCurrentPlayerLevel()
    local rarityPool = GetLevelRarityPool(level)
    local pool = BuildPlantPoolByRarities(rarityPool)
    if #pool == 0 then
        pool = BuildPlantPoolByRarities({ "普通" })
    end
    if #pool == 0 then
        return 1
    end
    return RandItem(pool)
end

local function GetRewardPackForPlant(plant)
    local rarity = plant and plant.rarity or "普通"
    local pool = REWARD_PACK_POOLS_BY_PLANT_RARITY[rarity] or REWARD_PACK_POOLS_BY_PLANT_RARITY["普通"]
    local reward = RollWeighted(pool)
    return reward and reward.packId or "pack_common"
end

local function BuildMutationRequirement(packId)
    local difficulty = PACK_DIFFICULTY[packId] or PACK_DIFFICULTY.pack_rare
    local kind = RandItem(difficulty.mutationKinds)
    if kind == "color" then
        local key = RandItem(COLOR_REQUIREMENTS)
        local mutation = FindMutationByKey(cfg_.COLOR_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "颜色变异" }
    elseif kind == "special" then
        local key = RandItem(SPECIAL_REQUIREMENTS)
        local mutation = FindMutationByKey(cfg_.SPECIAL_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "特殊变异" }
    elseif kind == "giant" then
        return { kind = kind, key = "Giant", name = "巨大作物" }
    end
    return { kind = "basic", key = "basic", name = "任意基础变异" }
end

local function BuildMinWeight(packId, plantIndex)
    local difficulty = PACK_DIFFICULTY[packId] or PACK_DIFFICULTY.pack_rare
    local plant = cfg_.PLANTS[plantIndex]
    local baseWeight = plant and plant.baseWeight or 1.0
    local scaleRange = difficulty.minWeightScale
    return baseWeight * RandomRange(scaleRange[1], scaleRange[2])
end

local function FormatWeight(weight)
    return string.format("%.2fkg", weight or 0)
end

local function FormatTimer(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function BuildCommission(index)
    local plantIndex = PickPlantForCurrentLevel()
    local plant = cfg_.PLANTS[plantIndex]
    local rewardPackId = GetRewardPackForPlant(plant)
    local mutationRequirement = BuildMutationRequirement(rewardPackId)
    local minWeight = BuildMinWeight(rewardPackId, plantIndex)
    local packCfg = cfg_.SEED_PACK_CONFIG[rewardPackId]
    local customer = RandItem(CUSTOMER_NAMES)

    return {
        id = string.format("commission_%d_%d", os.time(), index),
        customer = customer,
        plantIndex = plantIndex,
        plantName = plant and plant.name or "作物",
        plantRarity = plant and plant.rarity or "普通",
        mutation = mutationRequirement,
        minWeight = minWeight,
        rewardPackId = rewardPackId,
        rewardPackName = packCfg and packCfg.packName or "普通种子包",
        completed = false,
    }
end

local function RefreshCommissions()
    state_.commissions = {}
    for i = 1, COMMISSION_COUNT do
        table.insert(state_.commissions, BuildCommission(i))
    end
    state_.timer = REFRESH_INTERVAL
    state_.lastRefreshRealTime = os.time()
    if callbacks_.onRefresh then
        callbacks_.onRefresh()
    end
    print(string.format("[委托] 已刷新 %d 个委托，下次刷新 %s", #state_.commissions, FormatTimer(state_.timer)))
end

local function HasColorMutation(item, key)
    local colorMutation = item and item.mutation and item.mutation.colorMutation
    return colorMutation ~= nil and colorMutation.key == key
end

local function HasSpecialMutation(item, key)
    local specials = item and item.mutation and item.mutation.specials
    if specials == nil then return false end
    for _, special in ipairs(specials) do
        if special.key == key then
            return true
        end
    end
    return false
end

local function HasBasicMutation(item)
    local mutation = item and item.mutation
    if mutation == nil then return false end
    return mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil
end

local function MatchesMutation(item, requirement)
    if requirement == nil then return true end
    if requirement.kind == "color" then
        return HasColorMutation(item, requirement.key)
    elseif requirement.kind == "special" then
        return HasSpecialMutation(item, requirement.key)
    elseif requirement.kind == "giant" then
        return item ~= nil and item.weightTier == "Giant"
    elseif requirement.kind == "basic" then
        return HasBasicMutation(item)
    end
    return true
end

function CommissionSystem.Init(config, inventorySystem, callbacks)
    cfg_ = config
    inventory_ = inventorySystem
    callbacks_ = callbacks or {}
    getPlayerLevel_ = callbacks_.getPlayerLevel
    RefreshCommissions()
end

function CommissionSystem.GetState()
    return state_
end

function CommissionSystem.GetCommissions()
    return state_.commissions
end

function CommissionSystem.GetTimeLeftText()
    return FormatTimer(state_.timer)
end

function CommissionSystem.GetRequirementText(commission)
    if commission == nil then return "未知委托" end
    return string.format("求购 %s · %s · ≥%s", commission.plantName, commission.mutation.name, FormatWeight(commission.minWeight))
end

function CommissionSystem.DoesItemMatch(commission, item)
    if commission == nil or item == nil then return false end
    if item.plantIndex ~= commission.plantIndex then return false end
    if (item.weight or 0) < (commission.minWeight or 0) then return false end
    return MatchesMutation(item, commission.mutation)
end

function CommissionSystem.GetMatchingHarvestedItems(commission)
    local result = {}
    if inventory_ == nil then return result end
    local harvested = inventory_.GetHarvested()
    for _, item in ipairs(harvested) do
        if CommissionSystem.DoesItemMatch(commission, item) then
            table.insert(result, item)
        end
    end
    table.sort(result, function(a, b)
        return (a.weight or 0) > (b.weight or 0)
    end)
    return result
end

function CommissionSystem.CompleteCommission(commission, item)
    if commission == nil or item == nil then
        return false, "委托或作物无效"
    end
    if commission.completed then
        return false, "委托已完成"
    end
    if not CommissionSystem.DoesItemMatch(commission, item) then
        return false, "作物不满足委托条件"
    end
    if not inventory_.ConsumeHarvestedItem(item) then
        return false, "作物已不存在"
    end
    inventory_.AddSeedPack(commission.rewardPackId, 1)
    commission.completed = true
    local text = string.format("完成%s的委托，获得%s", commission.customer, commission.rewardPackName)
    if callbacks_.showToast then
        callbacks_.showToast(text)
    end
    print("[委托] " .. text)
    return true, text
end

function CommissionSystem.Update(dt)
    if state_.timer > 0 then
        state_.timer = state_.timer - dt
        if state_.timer <= 0 then
            RefreshCommissions()
        end
    end
end

function CommissionSystem.RefreshNow()
    RefreshCommissions()
end

function CommissionSystem.HandleOffline()
    if state_.lastRefreshRealTime <= 0 then return end
    local now = os.time()
    local elapsed = now - state_.lastRefreshRealTime
    if elapsed >= state_.timer then
        RefreshCommissions()
    else
        state_.timer = state_.timer - elapsed
        state_.lastRefreshRealTime = now
    end
end

function CommissionSystem.GetSaveData()
    return {
        commissions = state_.commissions,
        timer = state_.timer,
        lastRefreshRealTime = state_.lastRefreshRealTime,
    }
end

function CommissionSystem.LoadSaveData(data)
    if data == nil then return end
    state_.commissions = data.commissions or {}
    state_.timer = data.timer or 0
    state_.lastRefreshRealTime = data.lastRefreshRealTime or 0
    if #state_.commissions == 0 then
        RefreshCommissions()
    else
        CommissionSystem.HandleOffline()
    end
end

return CommissionSystem
