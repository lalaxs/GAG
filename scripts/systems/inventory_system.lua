-- ============================================================================
-- 背包与奖励系统 (Inventory System)
-- Grow A Garden
-- ============================================================================
-- 管理：种子背包、银种 Buff 计数、收获背包、种子包、每日任务、收集奖励。
-- UI 层仍可读取返回的状态表，但所有写入通过本模块接口完成。
-- ============================================================================

local InventoryRules = require("systems.inventory_rules")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")

local InventorySystem = {}

local cfg_ = nil
local callbacks_ = {}
local localMutationsEnabled_ = true

local function IsClientRuntime()
    return IsClientMode ~= nil and IsClientMode()
end

local function CanMutateLocalState(actionName)
    if localMutationsEnabled_ == true then return true end
    if IsClientRuntime() then
        print("[背包] 已阻止客户端本地权威写入: " .. tostring(actionName or "unknown"))
        return false
    end
    return true
end

local function EmitTaskChanged(reason)
    EventBus.Emit(UIEvents.TASK_CHANGED, { reason = reason })
end

local SYNTHESIS_MAP = InventoryRules.SYNTHESIS_MAP
local PITY_THRESHOLDS = InventoryRules.PITY_THRESHOLDS
local DAILY_REWARD_PACK_WEIGHTS = InventoryRules.DAILY_REWARD_PACK_WEIGHTS
local HARVEST_DROP_PACK_WEIGHTS = InventoryRules.HARVEST_DROP_PACK_WEIGHTS
local HARVEST_DROP_PACK_WEIGHTS_BY_RARITY = InventoryRules.HARVEST_DROP_PACK_WEIGHTS_BY_RARITY
local HARVEST_DROP_RATES_BY_RARITY = InventoryRules.HARVEST_DROP_RATES_BY_RARITY

local DEFAULT_HARVEST_BAG_CAPACITY = 20
local MAX_HARVEST_BAG_CAPACITY = 100

local state_ = {
    seedBag = {},
    seedBagBuffs = {},
    harvested = {},
    seedPacks = {},
    collectedPlants = {},
    codexStats = {},
    silverRewardClaimed = {},
    pityCounters = {},  -- { [packId] = number } 保底计数器
    tutorial = {
        plantGuideDone = false,
    },
    dailyTaskState = {
        progress = { plant = 0, harvest = 0, sell = 0 },
        rewardClaimed = false,
    },
}

local function RollWeighted(pool)
    return InventoryRules.RollWeighted(pool)
end

local function IsLimitedSeed(seedId)
    local plant = cfg_ and cfg_.PLANTS and cfg_.PLANTS[seedId]
    return plant ~= nil and (plant.limited == true or plant.activityTag ~= nil)
end

local function GetPackRollPool(packCfg)
    if packCfg.allowLimitedSeeds == true then
        return packCfg.weightPool
    end

    local filtered = {}
    for _, item in ipairs(packCfg.weightPool or {}) do
        if not IsLimitedSeed(item.seedId) then
            table.insert(filtered, item)
        end
    end
    if #filtered == 0 then
        return packCfg.weightPool
    end
    return filtered
end

local function RollSeedFromPack(packCfg)
    local item = RollWeighted(GetPackRollPool(packCfg))
    return item.seedId
end

--- 获取该包对应的"跨级"品级（高一级）的 packId
local function GetUpgradePackId(packId)
    return SYNTHESIS_MAP[packId]
end

--- 保底感知的种子抽取：如果触发保底，从高一级池子里抽
local function RollSeedWithPity(packCfg)
    local packId = packCfg.packId
    local threshold = PITY_THRESHOLDS[packId]
    local upgradePackId = GetUpgradePackId(packId)

    -- 如果没有更高品级（传奇包），直接正常抽
    if threshold == nil or upgradePackId == nil then
        return RollSeedFromPack(packCfg), false, packId
    end

    local pity = state_.pityCounters[packId] or 0

    -- 保底触发：从高一级池子里抽
    if pity >= threshold then
        local upgradeCfg = cfg_.SEED_PACK_CONFIG[upgradePackId]
        if upgradeCfg ~= nil then
            state_.pityCounters[packId] = 0
            print(string.format("[保底] %s 保底触发！从 %s 池抽取", packCfg.packName, upgradeCfg.packName))
            return RollSeedFromPack(upgradeCfg), true, upgradePackId
        end
    end

    -- 正常抽取
    local seedId = RollSeedFromPack(packCfg)

    -- 检查是否抽到了跨级种子（如果配置了跨级池子中的种子则重置保底）
    local plant = cfg_.PLANTS[seedId]
    local seedRarity = plant and plant.rarity or packCfg.packRarity
    local rarityOrder = cfg_.RARITY_ORDER or {}
    local isUpgrade = (rarityOrder[seedRarity] or 0) > (rarityOrder[packCfg.packRarity] or 0)

    if isUpgrade then
        state_.pityCounters[packId] = 0
    else
        state_.pityCounters[packId] = pity + 1
    end

    return seedId, isUpgrade, packId
end

local function IsRarityCollected(rarity)
    local list = cfg_.RARITY_PLANT_INDICES[rarity]
    if list == nil then return false end
    for _, plantIndex in ipairs(list) do
        if not state_.collectedPlants[plantIndex] then
            return false
        end
    end
    return true
end

function InventorySystem.Init(config, callbacks)
    cfg_ = config
    callbacks_ = callbacks or {}
    localMutationsEnabled_ = callbacks_.allowLocalMutations ~= false
end

function InventorySystem.SetLocalMutationsEnabled(enabled)
    localMutationsEnabled_ = enabled == true
end

function InventorySystem.AreLocalMutationsEnabled()
    return localMutationsEnabled_ == true
end

function InventorySystem.GetState()
    return state_
end

local function CopyNumericKeyMap(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        local numericKey = tonumber(key)
        if numericKey ~= nil then
            result[math.floor(numericKey)] = value
        else
            result[key] = value
        end
    end
    return result
end

local function CopyTable(source, fallback)
    if type(source) == "table" then return source end
    return fallback or {}
end

local function ReplaceTable(target, source)
    for key in pairs(target) do
        target[key] = nil
    end
    if type(source) ~= "table" then return target end
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

function InventorySystem.GetSaveData()
    return {
        seedBag = state_.seedBag,
        seedBagBuffs = state_.seedBagBuffs,
        harvested = state_.harvested,
        seedPacks = state_.seedPacks,
        collectedPlants = state_.collectedPlants,
        codexStats = state_.codexStats,
        silverRewardClaimed = state_.silverRewardClaimed,
        pityCounters = state_.pityCounters,
        tutorial = state_.tutorial,
        dailyTaskState = state_.dailyTaskState,
    }
end

function InventorySystem.LoadSaveData(data)
    if data == nil then return end
    ReplaceTable(state_.seedBag, CopyNumericKeyMap(data.seedBag))
    ReplaceTable(state_.seedBagBuffs, CopyNumericKeyMap(data.seedBagBuffs))
    ReplaceTable(state_.harvested, CopyTable(data.harvested))
    ReplaceTable(state_.seedPacks, CopyTable(data.seedPacks))
    ReplaceTable(state_.collectedPlants, CopyNumericKeyMap(data.collectedPlants))
    ReplaceTable(state_.codexStats, CopyNumericKeyMap(data.codexStats))
    ReplaceTable(state_.silverRewardClaimed, CopyTable(data.silverRewardClaimed))
    ReplaceTable(state_.pityCounters, CopyTable(data.pityCounters))
    ReplaceTable(state_.tutorial, CopyTable(data.tutorial, { plantGuideDone = false }))
    state_.tutorial.plantGuideDone = state_.tutorial.plantGuideDone == true
    ReplaceTable(state_.dailyTaskState, CopyTable(data.dailyTaskState, { progress = { plant = 0, harvest = 0, sell = 0 }, rewardClaimed = false }))
    state_.dailyTaskState.progress = CopyTable(state_.dailyTaskState.progress, { plant = 0, harvest = 0, sell = 0 })
end

function InventorySystem.GetSeedBag()
    return state_.seedBag
end

function InventorySystem.GetSeedBagBuffs()
    return state_.seedBagBuffs
end

function InventorySystem.GetHarvested()
    return state_.harvested
end

function InventorySystem.GetSeedPacks()
    return state_.seedPacks
end

function InventorySystem.GetCollectedPlants()
    return state_.collectedPlants
end

function InventorySystem.GetTutorialState()
    return state_.tutorial
end

function InventorySystem.GetCodexStats()
    return state_.codexStats
end

function InventorySystem.GetDailyTaskState()
    return state_.dailyTaskState
end

function InventorySystem.GetSilverRewardClaimed()
    return state_.silverRewardClaimed
end

function InventorySystem.AddSeedToBag(plantIndex, count, buff)
    if not CanMutateLocalState("AddSeedToBag") then return 0 end
    if plantIndex == nil or cfg_.PLANTS[plantIndex] == nil then return 0 end
    count = count or 1
    buff = buff or 0
    local current = state_.seedBag[plantIndex] or 0
    local addCount = math.max(0, math.floor(tonumber(count or 0) or 0))
    if addCount <= 0 then return 0 end
    state_.seedBag[plantIndex] = current + addCount
    if buff > 0 then
        state_.seedBagBuffs[plantIndex] = (state_.seedBagBuffs[plantIndex] or 0) + addCount
    end
    return addCount
end

function InventorySystem.RemoveSeedFromBag(plantIndex)
    if not CanMutateLocalState("RemoveSeedFromBag") then return 0 end
    local owned = state_.seedBag[plantIndex] or 0
    if owned <= 0 then return 0 end
    state_.seedBag[plantIndex] = owned - 1
    local buffCount = state_.seedBagBuffs[plantIndex] or 0
    if buffCount > 0 then
        state_.seedBagBuffs[plantIndex] = buffCount - 1
        return 0.01
    end
    return 0
end

function InventorySystem.CountSeedPacks()
    local total = 0
    for packId, count in pairs(state_.seedPacks) do
        if cfg_.SEED_PACK_CONFIG[packId] ~= nil then
            total = total + count
        end
    end
    return total
end

function InventorySystem.AddSeedPack(packId, count)
    if not CanMutateLocalState("AddSeedPack") then return false end
    local packCfg = cfg_.SEED_PACK_CONFIG[packId]
    if packCfg == nil then return false end
    count = count or 1
    local current = state_.seedPacks[packId] or 0
    state_.seedPacks[packId] = math.min(packCfg.stackMax or 999, current + count)
    print(string.format("[种子包] 获得 %s x%d", packCfg.packName, count))
    return true
end

function InventorySystem.IsTaskCompleted(taskCfg)
    return (state_.dailyTaskState.progress[taskCfg.key] or 0) >= taskCfg.target
end

function InventorySystem.AreAllDailyTasksCompleted()
    for _, task in ipairs(cfg_.DAILY_TASK_CONFIG) do
        if not InventorySystem.IsTaskCompleted(task) then
            return false
        end
    end
    return true
end

function InventorySystem.AddDailyProgress(key, amount)
    if not CanMutateLocalState("AddDailyProgress") then return end
    if state_.dailyTaskState.progress[key] == nil then return end
    amount = amount or 1
    local before = state_.dailyTaskState.progress[key]
    state_.dailyTaskState.progress[key] = math.min(99, before + amount)
    if state_.dailyTaskState.progress[key] ~= before then
        EmitTaskChanged("progress")
    end
end

function InventorySystem.CheckSilverPackRewards()
    if not CanMutateLocalState("CheckSilverPackRewards") then return end
    for rarity, packId in pairs(cfg_.SEED_PACK_BY_RARITY) do
        if not state_.silverRewardClaimed[rarity] and IsRarityCollected(rarity) then
            state_.silverRewardClaimed[rarity] = true
            InventorySystem.AddSeedPack(packId, 1)
            if callbacks_.showToast then
                callbacks_.showToast("完成" .. rarity .. "收集，获得" .. cfg_.SEED_PACK_CONFIG[packId].packName)
            end
        end
    end
end

function InventorySystem.GetHarvestBagCapacity()
    local bonus = 0
    if callbacks_.getHarvestBagBonus then
        bonus = callbacks_.getHarvestBagBonus() or 0
    end
    return math.min(MAX_HARVEST_BAG_CAPACITY, DEFAULT_HARVEST_BAG_CAPACITY + math.floor(bonus))
end

function InventorySystem.IsHarvestBagFull()
    return #state_.harvested >= InventorySystem.GetHarvestBagCapacity()
end

function InventorySystem.GetHarvestBagMaxCapacity()
    return MAX_HARVEST_BAG_CAPACITY
end

function InventorySystem.AddHarvestedCrop(crop)
    if not CanMutateLocalState("AddHarvestedCrop") then return false end
    if crop == nil then return false end
    if InventorySystem.IsHarvestBagFull() then
        print(string.format("背包已满: %d/%d", #state_.harvested, InventorySystem.GetHarvestBagCapacity()))
        if callbacks_.showToast then
            callbacks_.showToast("背包已满，出售作物或点天赋扩容")
        end
        if callbacks_.showFloatingToast then
            callbacks_.showFloatingToast("背包已满")
        end
        return false
    end
    table.insert(state_.harvested, {
        name = crop.name,
        price = crop.price,
        sightValue = crop.sightValue,
        rarity = crop.config.rarity,
        plantIndex = crop.plantIndex,
        weight = crop.weight,
        baseWeight = crop.baseWeight,
        weightTier = crop.weightTier,
        weightMultiplier = crop.weightMultiplier,
        mutation = crop.mutation,
    })
    state_.collectedPlants[crop.plantIndex] = true
    local stats = state_.codexStats[crop.plantIndex]
    if stats == nil then
        stats = {
            harvestCount = 0,
            maxWeight = 0,
            maxPrice = 0,
        }
        state_.codexStats[crop.plantIndex] = stats
    end
    stats.harvestCount = (stats.harvestCount or 0) + 1
    stats.maxWeight = math.max(stats.maxWeight or 0, crop.weight or 0)
    stats.maxPrice = math.max(stats.maxPrice or 0, crop.price or 0)
    InventorySystem.AddDailyProgress("harvest", 1)
    InventorySystem.CheckSilverPackRewards()
    return true
end

function InventorySystem.CountHarvestedValue()
    local value = 0
    for _, item in ipairs(state_.harvested) do
        value = value + item.price
    end
    return value
end

function InventorySystem.SellAllHarvested()
    if not CanMutateLocalState("SellAllHarvested") then return 0 end
    if #state_.harvested == 0 then
        print("背包没有可出售作物")
        return 0
    end
    local total = InventorySystem.CountHarvestedValue()
    for i = #state_.harvested, 1, -1 do
        table.remove(state_.harvested, i)
    end
    InventorySystem.AddDailyProgress("sell", 1)
    print("出售全部作物，获得金币 " .. total)
    return total
end

function InventorySystem.SellBagItem(item)
    if not CanMutateLocalState("SellBagItem") then return 0 end
    if item == nil then return 0 end
    for i = 1, #state_.harvested do
        if state_.harvested[i] == item then
            local earned = item.price or 0
            table.remove(state_.harvested, i)
            InventorySystem.AddDailyProgress("sell", 1)
            print("出售作物 " .. (item.name or "作物") .. "，获得金币 " .. earned)
            return earned
        end
    end
    return 0
end

function InventorySystem.ConsumeHarvestedItem(item)
    if not CanMutateLocalState("ConsumeHarvestedItem") then return false end
    if item == nil then return false end
    for i = 1, #state_.harvested do
        if state_.harvested[i] == item then
            table.remove(state_.harvested, i)
            print("消耗背包作物用于委托: " .. (item.name or "作物"))
            return true
        end
    end
    return false
end

local function IsBasicMutatedHarvestItem(item)
    local mutation = item and item.mutation
    if mutation == nil then return false end
    return mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil
end

local function IsSpecialMutatedHarvestItem(item)
    local specials = item and item.mutation and item.mutation.specials
    return specials ~= nil and #specials > 0
end

local function HasAnyHarvestSellFilter(filter)
    filter = filter or {}
    return filter.basicMutation or filter.specialMutation or filter.giant
end

local function DoesHarvestItemMatchSellFilter(item, filter)
    filter = filter or {}
    local isBasicMutated = IsBasicMutatedHarvestItem(item)
    local isSpecialMutated = IsSpecialMutatedHarvestItem(item)
    local isGiant = item ~= nil and item.weightTier == "Giant"

    if not HasAnyHarvestSellFilter(filter) then
        return not isBasicMutated and not isSpecialMutated and not isGiant
    end
    if filter.basicMutation and isBasicMutated then return true end
    if filter.specialMutation and isSpecialMutated then return true end
    if filter.giant and isGiant then return true end
    return false
end

function InventorySystem.PreviewSellHarvestedByFilter(filter)
    local count = 0
    local total = 0
    for _, item in ipairs(state_.harvested) do
        if DoesHarvestItemMatchSellFilter(item, filter) then
            count = count + 1
            total = total + (item.price or 0)
        end
    end
    return count, total
end

function InventorySystem.SellHarvestedByFilter(filter)
    if not CanMutateLocalState("SellHarvestedByFilter") then return 0, 0 end
    local count, total = InventorySystem.PreviewSellHarvestedByFilter(filter)
    if count <= 0 then
        return 0, 0
    end
    for i = #state_.harvested, 1, -1 do
        if DoesHarvestItemMatchSellFilter(state_.harvested[i], filter) then
            table.remove(state_.harvested, i)
        end
    end
    InventorySystem.AddDailyProgress("sell", 1)
    print(string.format("批量出售作物 %d 个，获得金币 %d", count, total))
    return count, total
end

function InventorySystem.CountPackResults(results)
    local counts = {}
    for _, result in ipairs(results) do
        counts[result.seedId] = (counts[result.seedId] or 0) + 1
    end
    return counts
end

function InventorySystem.CanReceivePackResults(results)
    return type(results) == "table"
end

function InventorySystem.BuildSeedPackResults(packCfg, packCount)
    local results = {}
    for _ = 1, packCount do
        for _ = 1, packCfg.onceOpenCount do
            local seedId, isPity, rollPackId = RollSeedWithPity(packCfg)
            table.insert(results, {
                seedId = seedId,
                packId = packCfg.packId,
                rollPackId = rollPackId or packCfg.packId,
                seedBuff = packCfg.seedBuff or 0,
                isNew = not state_.collectedPlants[seedId],
                isPity = isPity,
            })
        end
    end
    return results
end

function InventorySystem.ApplyPackResults(results)
    if not CanMutateLocalState("ApplyPackResults") then return false end
    for _, result in ipairs(results) do
        InventorySystem.AddSeedToBag(result.seedId, 1, result.seedBuff)
    end
end

function InventorySystem.GetFirstAvailablePackId()
    local packs = {}
    for packId, packCfg in pairs(cfg_.SEED_PACK_CONFIG) do
        if (state_.seedPacks[packId] or 0) > 0 then
            local rarityOrder = (cfg_.RARITY_ORDER or {})[packCfg.packRarity or "普通"] or 0
            if packCfg.allowLimitedSeeds then rarityOrder = rarityOrder + 100 end
            table.insert(packs, { packId = packId, order = rarityOrder })
        end
    end
    table.sort(packs, function(a, b)
        if a.order == b.order then return a.packId < b.packId end
        return a.order < b.order
    end)
    return packs[1] and packs[1].packId or nil
end

function InventorySystem.OpenSeedPack(packId, packCount)
    if not CanMutateLocalState("OpenSeedPack") then return nil, "服务器确认后才能开启种子包" end
    local packCfg = cfg_.SEED_PACK_CONFIG[packId]
    local owned = state_.seedPacks[packId] or 0
    packCount = math.min(packCount or 1, owned)
    if packCfg == nil or packCount <= 0 then return nil end

    local results = InventorySystem.BuildSeedPackResults(packCfg, packCount)
    state_.seedPacks[packId] = owned - packCount
    InventorySystem.ApplyPackResults(results)
    return results
end

function InventorySystem.PreviewSeedPack(packId, packCount)
    if not CanMutateLocalState("PreviewSeedPack") then return nil, "服务器确认后才能预览种子包" end
    local packCfg = cfg_.SEED_PACK_CONFIG[packId]
    local owned = state_.seedPacks[packId] or 0
    packCount = math.min(packCount or 1, owned)
    if packCfg == nil or packCount <= 0 then return nil end

    local results = InventorySystem.BuildSeedPackResults(packCfg, packCount)
    state_.seedPacks[packId] = owned - packCount
    return results
end

function InventorySystem.ConfirmSeedPackResults(results)
    if not CanMutateLocalState("ConfirmSeedPackResults") then return false end
    if results == nil then return false end
    InventorySystem.ApplyPackResults(results)
    return true
end

function InventorySystem.ClaimDailyReward()
    if not CanMutateLocalState("ClaimDailyReward") then return false, nil end
    if not InventorySystem.AreAllDailyTasksCompleted() or state_.dailyTaskState.rewardClaimed then
        return false, nil
    end
    state_.dailyTaskState.rewardClaimed = true

    -- 奖励 3 个随机种子包（最高稀有品质）
    local rewards = {}
    for _ = 1, 3 do
        local picked = RollWeighted(DAILY_REWARD_PACK_WEIGHTS)
        InventorySystem.AddSeedPack(picked.packId, 1)
        table.insert(rewards, picked.packId)
    end
    print(string.format("[每日] 领取每日奖励：%s, %s, %s", rewards[1], rewards[2], rewards[3]))
    EmitTaskChanged("daily_reward_claimed")
    EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "daily_reward_claimed" })
    EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = "daily_reward_claimed" })
    return true, rewards
end

-- ============================================================================
-- 三合一种子包合成
-- ============================================================================

--- 检查是否可以合成（需要 3 个同品级种子包）
function InventorySystem.CanSynthesizePack(packId)
    local targetId = SYNTHESIS_MAP[packId]
    if targetId == nil then return false end -- 传奇包不可合成
    local owned = state_.seedPacks[packId] or 0
    return owned >= 3
end

--- 执行三合一合成：消耗 3 个同品级包，获得 1 个高品级包
function InventorySystem.SynthesizePack(packId)
    if not CanMutateLocalState("SynthesizePack") then return false, nil end
    if not InventorySystem.CanSynthesizePack(packId) then return false, nil end
    local targetId = SYNTHESIS_MAP[packId]
    state_.seedPacks[packId] = (state_.seedPacks[packId] or 0) - 3
    InventorySystem.AddSeedPack(targetId, 1)
    local sourceName = cfg_.SEED_PACK_CONFIG[packId] and cfg_.SEED_PACK_CONFIG[packId].packName or packId
    local targetName = cfg_.SEED_PACK_CONFIG[targetId] and cfg_.SEED_PACK_CONFIG[targetId].packName or targetId
    print(string.format("[合成] %s x3 → %s x1", sourceName, targetName))
    return true, targetId
end

--- 获取合成目标包 ID
function InventorySystem.GetSynthesisTarget(packId)
    return SYNTHESIS_MAP[packId]
end

-- ============================================================================
-- 收获掉落种子包
-- ============================================================================

--- 收获时调用，根据来源作物品级和天赋加成决定是否掉落种子包
--- @param rarity string 作物稀有度
--- @param dropRateBonus number 掉包率相对加成（来自天赋系统）
--- @param packQualityBonus number 品质提升等级（预留）
--- @return string|nil 掉落的种子包 ID，nil 表示未掉落
function InventorySystem.RollHarvestDrop(rarity, dropRateBonus, packQualityBonus)
    if not CanMutateLocalState("RollHarvestDrop") then return nil end
    rarity = rarity or "普通"
    dropRateBonus = dropRateBonus or 0
    packQualityBonus = packQualityBonus or 0

    local baseRate = HARVEST_DROP_RATES_BY_RARITY[rarity] or 0.01
    local finalRate = math.min(baseRate * (1.0 + dropRateBonus), 0.25)
    if math.random() > finalRate then return nil end

    local sourcePool = HARVEST_DROP_PACK_WEIGHTS_BY_RARITY[rarity] or HARVEST_DROP_PACK_WEIGHTS
    local adjustedPool = {}
    for i, item in ipairs(sourcePool) do
        local weight = item.weight
        if i <= 2 then
            weight = math.max(5, weight - packQualityBonus * 15)
        else
            weight = weight + packQualityBonus * 10
        end
        table.insert(adjustedPool, { packId = item.packId, weight = weight })
    end

    local picked = RollWeighted(adjustedPool)
    InventorySystem.AddSeedPack(picked.packId, 1)
    print(string.format("[掉落] %s作物收获掉落种子包: %s", rarity, picked.packId))
    return picked.packId
end

-- ============================================================================
-- 保底系统查询接口
-- ============================================================================

--- 获取某个包的保底进度
function InventorySystem.GetPityProgress(packId)
    local threshold = PITY_THRESHOLDS[packId]
    if threshold == nil then return 0, 0 end
    local current = state_.pityCounters[packId] or 0
    return current, threshold
end



-- ============================================================================
-- 收藏成就奖励（增强版：集齐品级奖励更多包）
-- ============================================================================

function InventorySystem.CheckSilverPackRewardsEnhanced()
    if not CanMutateLocalState("CheckSilverPackRewardsEnhanced") then return end
    for rarity, packId in pairs(cfg_.SEED_PACK_BY_RARITY) do
        if not state_.silverRewardClaimed[rarity] and IsRarityCollected(rarity) then
            state_.silverRewardClaimed[rarity] = true
            -- 集齐奖励：该品级包 x2 + 上一级包 x1
            InventorySystem.AddSeedPack(packId, 2)
            local upgradeId = SYNTHESIS_MAP[packId]
            if upgradeId ~= nil then
                InventorySystem.AddSeedPack(upgradeId, 1)
            end
            if callbacks_.showToast then
                callbacks_.showToast("完成" .. rarity .. "收集！获得种子包奖励")
            end
        end
    end
end

return InventorySystem
