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
    currentTourValue = 0,
    bestTourValue = 0,
}

local function BuildExpansionRequirements()
    local requirements = config_ and config_.LAND_UNLOCK_REQUIREMENTS or nil
    if requirements ~= nil then
        return requirements
    end
    local sightReq = config_ and config_.LAND_UNLOCK_SIGHT_REQUIREMENTS or nil
    return {
        [2] = { level = 2, gold = 600, tour = sightReq and sightReq[2] or 180 },
        [3] = { level = 4, gold = 2200, tour = sightReq and sightReq[3] or 550 },
        [4] = { level = 6, gold = 7500, tour = sightReq and sightReq[4] or 1300 },
        [5] = { level = 9, gold = 25000, tour = sightReq and sightReq[5] or 3000 },
        [6] = { level = 12, gold = 85000, tour = sightReq and sightReq[6] or 6500 },
        [7] = { level = 16, gold = 260000, tour = sightReq and sightReq[7] or 13000 },
        [8] = { level = 21, gold = 780000, tour = sightReq and sightReq[8] or 25000 },
        [9] = { level = 26, gold = 2200000, tour = sightReq and sightReq[9] or 45000 },
    }
end

local function ClampUnlockedPlotCount(value)
    local maxCount = ProgressionSystem.GetMaxPlotCount()
    return Clamp(value or 1, 1, maxCount)
end

function ProgressionSystem.Init(config)
    config_ = config
    state_.unlockedPlotCount = ClampUnlockedPlotCount(config.InitialUnlockedPlots or 1)
    state_.gardenLevel = math.max(1, state_.unlockedPlotCount)
    state_.currentTourValue = 0
    state_.bestTourValue = 0
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
    return state_.currentTourValue
end

function ProgressionSystem.GetBestTourValue()
    return state_.bestTourValue
end

function ProgressionSystem.GetLeaderboardTourValue()
    return state_.bestTourValue
end

function ProgressionSystem.SetCurrentTourValue(value)
    value = math.max(0, math.floor((value or 0) + 0.5))
    state_.currentTourValue = value
    if value > state_.bestTourValue then
        state_.bestTourValue = value
    end
    return state_.currentTourValue
end

function ProgressionSystem.AddTourValue(amount)
    amount = amount or 0
    if amount <= 0 then return 0 end
    return ProgressionSystem.SetCurrentTourValue(state_.currentTourValue + amount)
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
    local requirements = BuildExpansionRequirements()
    return requirements[plotIndex] or {
        level = math.max(1, plotIndex),
        gold = 3000 * plotIndex * plotIndex,
        tour = 600 * plotIndex * plotIndex,
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
    tourValue = tourValue or state_.currentTourValue
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
        currentTourValue = state_.currentTourValue,
        bestTourValue = state_.bestTourValue,
    }
end

function ProgressionSystem.LoadSaveData(data, options)
    if data == nil then return end
    options = options or {}
    state_.unlockedPlotCount = ClampUnlockedPlotCount(data.unlockedPlotCount or state_.unlockedPlotCount)
    state_.gardenLevel = data.gardenLevel or math.max(1, state_.unlockedPlotCount)
    if options.skipTourFields ~= true then
        if data.currentTourValue ~= nil then
            state_.currentTourValue = math.max(0, math.floor(tonumber(data.currentTourValue) or 0))
        elseif data.tourValue ~= nil then
            state_.currentTourValue = math.max(0, math.floor(tonumber(data.tourValue) or 0))
        end
        state_.bestTourValue = math.max(tonumber(data.bestTourValue or 0) or 0, state_.currentTourValue)
    end
end

return ProgressionSystem
