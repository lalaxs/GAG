-- ============================================================================
-- 扩地流程控制器
-- Grow A Garden
-- ============================================================================
-- 只封装扩地交易与状态同步流程，不改变原有校验顺序、提示和 UI 刷新行为。
-- ============================================================================

local AudioSystem = require("systems.audio_system")

local ExpansionController = {}

local deps_ = {}

local function ShowToast(text)
    if deps_.showToast ~= nil then
        deps_.showToast(text)
    end
end

function ExpansionController.Init(deps)
    deps_ = deps or {}
end

function ExpansionController.ExpandNextPlot()
    local ProgressionSystem = deps_.ProgressionSystem
    local TalentSystem = deps_.TalentSystem
    local WalletSystem = deps_.WalletSystem

    local canExpand, reason = ProgressionSystem.CanAffordNextPlot(TalentSystem.GetLevel(), WalletSystem.GetBalance(), ProgressionSystem.GetTourValue())
    if not canExpand then
        ShowToast(reason or "暂时无法扩展地块")
        return false
    end

    local requirement = ProgressionSystem.GetExpansionRequirement()
    if requirement == nil then
        ShowToast("已经扩展到最大地块")
        return false
    end

    if not WalletSystem.Spend(requirement.gold) then
        ShowToast("金币不足")
        return false
    end

    if not ProgressionSystem.UnlockNextPlot() then
        WalletSystem.Add(requirement.gold)
        ShowToast("扩展失败")
        return false
    end

    local unlockedPlotCount = ProgressionSystem.GetUnlockedPlotCount()
    if deps_.setUnlockedPlotCount ~= nil then
        deps_.setUnlockedPlotCount(unlockedPlotCount)
    end
    if deps_.setSelectedPlot ~= nil then
        deps_.setSelectedPlot(unlockedPlotCount)
    end
    if deps_.isSinglePlotDisplay ~= nil and deps_.isSinglePlotDisplay() and deps_.setFocusedPlotIndex ~= nil then
        deps_.setFocusedPlotIndex(unlockedPlotCount)
    end
    if deps_.applyUnlockedPlotCount ~= nil then
        deps_.applyUnlockedPlotCount()
    end
    if deps_.startSinglePlotBounceAnimation ~= nil then
        deps_.startSinglePlotBounceAnimation(unlockedPlotCount)
    end
    if deps_.rebuildUI ~= nil then
        deps_.rebuildUI()
    end
    if deps_.refreshUI ~= nil then
        deps_.refreshUI(true)
    end

    local maxPlots = ProgressionSystem.GetMaxPlotCount()
    if unlockedPlotCount >= maxPlots then
        ShowToast("解锁成功！所有地块已全部解锁")
    else
        ShowToast(string.format("解锁成功！第 %d 块地已开放", unlockedPlotCount))
    end
    return true
end

return ExpansionController
