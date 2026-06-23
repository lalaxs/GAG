-- ============================================================================
-- 等级与地块解锁系统 (Progression System)
-- Grow A Garden
-- ============================================================================
-- 管理花园等级、已解锁地块数量，以及后续通过等级/金币解锁更多地块的规则。
-- 当前版本保持现有行为：初始解锁数量即当前等级。
-- ============================================================================

local ProgressionSystem = {}

local config_ = nil
local state_ = {
    unlockedPlotCount = 1,
    gardenLevel = 1,
    tourValue = 0,
}

local EXPANSION_REQUIREMENTS = {
    [2] = { level = 2, gold = 500, tour = 30 },
    [3] = { level = 3, gold = 1500, tour = 80 },
    [4] = { level = 5, gold = 5000, tour = 180 },
    [5] = { level = 7, gold = 12000, tour = 360 },
    [6] = { level = 9, gold = 30000, tour = 650 },
    [7] = { level = 12, gold = 80000, tour = 1100 },
    [8] = { level = 15, gold = 180000, tour = 1700 },
    [9] = { level = 18, gold = 360000, tour = 2500 },
}

local function ClampUnlockedPlotCount(value)
    local maxCount = ProgressionSystem.GetMaxPlotCount()
    return Clamp(value or 1, 1, maxCount)
end

function ProgressionSystem.Init(config)
    config_ = config
    state_.unlockedPlotCount = ClampUnlockedPlotCount(config.InitialUnlockedPlots or 1)
    state_.gardenLevel = math.max(1, state_.unlockedPlotCount)
    state_.tourValue = 0
end

function ProgressionSystem.GetUnlockedPlotCount()
    return state_.unlockedPlotCount
end

function ProgressionSystem.GetGardenLevel()
    return math.max(1, state_.gardenLevel)
end

function ProgressionSystem.GetMaxPlotCount()
    if config_ == nil then return state_.unlockedPlotCount end
    return (config_.GridCols or 1) * (config_.GridRows or 1)
end

function ProgressionSystem.GetTourValue()
    return state_.tourValue
end

function ProgressionSystem.AddTourValue(amount)
    amount = amount or 0
    if amount <= 0 then return 0 end
    state_.tourValue = state_.tourValue + amount
    return amount
end

function ProgressionSystem.SetGardenLevel(level)
    state_.gardenLevel = math.max(1, level or 1)
end

function ProgressionSystem.GetNextPlotIndex()
    if not ProgressionSystem.CanUnlockNextPlot() then return nil end
    return state_.unlockedPlotCount + 1
end

function ProgressionSystem.GetExpansionRequirement(plotIndex)
    if plotIndex == nil then
        plotIndex = ProgressionSystem.GetNextPlotIndex()
    end
    if plotIndex == nil then return nil end
    return EXPANSION_REQUIREMENTS[plotIndex] or {
        level = math.max(1, plotIndex),
        gold = 500 * plotIndex * plotIndex,
        tour = 30 * plotIndex * plotIndex,
    }
end

function ProgressionSystem.CanUnlockNextPlot()
    return state_.unlockedPlotCount < ProgressionSystem.GetMaxPlotCount()
end

function ProgressionSystem.CanAffordNextPlot(level, gold, tourValue)
    if not ProgressionSystem.CanUnlockNextPlot() then
        return false, "已扩展到最大地块"
    end
    local requirement = ProgressionSystem.GetExpansionRequirement()
    if requirement == nil then
        return false, "没有可扩展地块"
    end
    level = level or state_.gardenLevel
    gold = gold or 0
    tourValue = tourValue or state_.tourValue
    if level < requirement.level then
        return false, "等级不足"
    end
    if gold < requirement.gold then
        return false, "金币不足"
    end
    if tourValue < requirement.tour then
        return false, "观光值不足"
    end
    return true, nil
end

function ProgressionSystem.GetNextPlotUnlockCost()
    local requirement = ProgressionSystem.GetExpansionRequirement()
    return requirement and requirement.gold or 0
end

function ProgressionSystem.UnlockNextPlot()
    if not ProgressionSystem.CanUnlockNextPlot() then
        return false
    end
    state_.unlockedPlotCount = ClampUnlockedPlotCount(state_.unlockedPlotCount + 1)
    state_.gardenLevel = math.max(state_.gardenLevel, state_.unlockedPlotCount)
    print(string.format("[扩地] 已解锁第 %d 块地", state_.unlockedPlotCount))
    return true
end

function ProgressionSystem.GetSaveData()
    return {
        unlockedPlotCount = state_.unlockedPlotCount,
        gardenLevel = state_.gardenLevel,
        tourValue = state_.tourValue,
    }
end

function ProgressionSystem.LoadSaveData(data)
    if data == nil then return end
    state_.unlockedPlotCount = ClampUnlockedPlotCount(data.unlockedPlotCount or state_.unlockedPlotCount)
    state_.gardenLevel = data.gardenLevel or math.max(1, state_.unlockedPlotCount)
    state_.tourValue = data.tourValue or state_.tourValue
end

return ProgressionSystem
