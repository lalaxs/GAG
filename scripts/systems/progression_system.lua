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
}

function ProgressionSystem.Init(config)
    config_ = config
    state_.unlockedPlotCount = config.InitialUnlockedPlots or 1
    state_.gardenLevel = math.max(1, state_.unlockedPlotCount)
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

function ProgressionSystem.CanUnlockNextPlot()
    return state_.unlockedPlotCount < ProgressionSystem.GetMaxPlotCount()
end

function ProgressionSystem.GetNextPlotUnlockCost()
    local nextPlotIndex = state_.unlockedPlotCount + 1
    return 500 * nextPlotIndex * nextPlotIndex
end

function ProgressionSystem.UnlockNextPlot()
    if not ProgressionSystem.CanUnlockNextPlot() then
        return false
    end
    state_.unlockedPlotCount = state_.unlockedPlotCount + 1
    state_.gardenLevel = math.max(state_.gardenLevel, state_.unlockedPlotCount)
    return true
end

function ProgressionSystem.GetSaveData()
    return {
        unlockedPlotCount = state_.unlockedPlotCount,
        gardenLevel = state_.gardenLevel,
    }
end

function ProgressionSystem.LoadSaveData(data)
    if data == nil then return end
    state_.unlockedPlotCount = data.unlockedPlotCount or state_.unlockedPlotCount
    state_.gardenLevel = data.gardenLevel or math.max(1, state_.unlockedPlotCount)
end

return ProgressionSystem
