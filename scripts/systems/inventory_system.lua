-- ============================================================================
-- 背包与奖励系统 (Inventory System)
-- Grow A Garden
-- ============================================================================
-- 管理：种子背包、银种 Buff 计数、收获背包、种子包、每日任务、收集奖励。
-- UI 层仍可读取返回的状态表，但所有写入通过本模块接口完成。
-- ============================================================================

local InventorySystem = {}

local cfg_ = nil
local callbacks_ = {}

local state_ = {
    seedBag = {},
    seedBagBuffs = {},
    harvested = {},
    seedPacks = {},
    collectedPlants = {},
    silverRewardClaimed = {},
    dailyTaskState = {
        progress = { plant = 0, harvest = 0, sell = 0 },
        rewardClaimed = false,
    },
}

local function RollSeedFromPack(packCfg)
    local totalWeight = 0
    for _, item in ipairs(packCfg.weightPool) do
        totalWeight = totalWeight + item.weight
    end
    local roll = math.random() * totalWeight
    local cursor = 0
    for _, item in ipairs(packCfg.weightPool) do
        cursor = cursor + item.weight
        if roll <= cursor then
            return item.seedId
        end
    end
    return packCfg.weightPool[#packCfg.weightPool].seedId
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
end

function InventorySystem.GetState()
    return state_
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

function InventorySystem.GetDailyTaskState()
    return state_.dailyTaskState
end

function InventorySystem.GetSilverRewardClaimed()
    return state_.silverRewardClaimed
end

function InventorySystem.AddSeedToBag(plantIndex, count, buff)
    if plantIndex == nil or cfg_.PLANTS[plantIndex] == nil then return 0 end
    count = count or 1
    buff = buff or 0
    local current = state_.seedBag[plantIndex] or 0
    local addCount = math.min(count, cfg_.SEED_STACK_MAX - current)
    if addCount <= 0 then return 0 end
    state_.seedBag[plantIndex] = current + addCount
    if buff > 0 then
        state_.seedBagBuffs[plantIndex] = (state_.seedBagBuffs[plantIndex] or 0) + addCount
    end
    return addCount
end

function InventorySystem.RemoveSeedFromBag(plantIndex)
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
    if state_.dailyTaskState.progress[key] == nil then return end
    amount = amount or 1
    state_.dailyTaskState.progress[key] = math.min(99, state_.dailyTaskState.progress[key] + amount)
end

function InventorySystem.CheckSilverPackRewards()
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

function InventorySystem.AddHarvestedCrop(crop)
    if crop == nil then return false end
    table.insert(state_.harvested, {
        name = crop.name,
        price = crop.price,
        rarity = crop.config.rarity,
        plantIndex = crop.plantIndex,
        weight = crop.weight,
        baseWeight = crop.baseWeight,
        weightTier = crop.weightTier,
        weightMultiplier = crop.weightMultiplier,
        mutation = crop.mutation,
    })
    state_.collectedPlants[crop.plantIndex] = true
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

function InventorySystem.CountPackResults(results)
    local counts = {}
    for _, result in ipairs(results) do
        counts[result.seedId] = (counts[result.seedId] or 0) + 1
    end
    return counts
end

function InventorySystem.CanReceivePackResults(results)
    local counts = InventorySystem.CountPackResults(results)
    for seedId, count in pairs(counts) do
        if (state_.seedBag[seedId] or 0) + count > cfg_.SEED_STACK_MAX then
            return false
        end
    end
    return true
end

function InventorySystem.BuildSeedPackResults(packCfg, packCount)
    local results = {}
    for _ = 1, packCount do
        for _ = 1, packCfg.onceOpenCount do
            local seedId = RollSeedFromPack(packCfg)
            table.insert(results, {
                seedId = seedId,
                packId = packCfg.packId,
                seedBuff = packCfg.seedBuff or 0,
                isNew = not state_.collectedPlants[seedId],
            })
        end
    end
    return results
end

function InventorySystem.ApplyPackResults(results)
    for _, result in ipairs(results) do
        InventorySystem.AddSeedToBag(result.seedId, 1, result.seedBuff)
    end
end

function InventorySystem.GetFirstAvailablePackId()
    for packId, packCfg in pairs(cfg_.SEED_PACK_CONFIG) do
        if (state_.seedPacks[packId] or 0) > 0 then
            return packCfg.packId
        end
    end
    return nil
end

function InventorySystem.OpenSeedPack(packId, packCount)
    local packCfg = cfg_.SEED_PACK_CONFIG[packId]
    local owned = state_.seedPacks[packId] or 0
    packCount = math.min(packCount or 1, owned)
    if packCfg == nil or packCount <= 0 then return nil end

    local results = InventorySystem.BuildSeedPackResults(packCfg, packCount)
    if not InventorySystem.CanReceivePackResults(results) then
        return nil, "背包空间不足，无法开启礼包"
    end
    state_.seedPacks[packId] = owned - packCount
    InventorySystem.ApplyPackResults(results)
    return results
end

function InventorySystem.PreviewSeedPack(packId, packCount)
    local packCfg = cfg_.SEED_PACK_CONFIG[packId]
    local owned = state_.seedPacks[packId] or 0
    packCount = math.min(packCount or 1, owned)
    if packCfg == nil or packCount <= 0 then return nil end

    local results = InventorySystem.BuildSeedPackResults(packCfg, packCount)
    if not InventorySystem.CanReceivePackResults(results) then
        return nil, "背包空间不足，无法开启礼包"
    end
    state_.seedPacks[packId] = owned - packCount
    return results
end

function InventorySystem.ConfirmSeedPackResults(results)
    if results == nil then return false end
    InventorySystem.ApplyPackResults(results)
    return true
end

function InventorySystem.ClaimDailyReward()
    if not InventorySystem.AreAllDailyTasksCompleted() or state_.dailyTaskState.rewardClaimed then
        return false
    end
    state_.dailyTaskState.rewardClaimed = true
    InventorySystem.AddSeedPack("pack_common", 1)
    return true
end

return InventorySystem
