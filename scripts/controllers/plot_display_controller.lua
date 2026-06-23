-- ============================================================================
-- 地块显示与选择控制器
-- Grow A Garden
-- ============================================================================
-- 统一管理全部/单地块显示、方向键选择、聚焦地块切换和相机目标同步。
-- ============================================================================

local FloatingToast = require("ui.floating_toast")

local PlotDisplayController = {}

local deps_ = {}
local displayMode_ = "all"
local focusedPlotIndex_ = 1

local function ShowToast(text)
    if deps_.showToast ~= nil then
        deps_.showToast(text)
    end
end

local function RebuildUI()
    if deps_.rebuildUI ~= nil then
        deps_.rebuildUI()
    end
end

local function RefreshUI(force)
    if deps_.refreshUI ~= nil then
        deps_.refreshUI(force)
    end
end

local function GetUnlockedPlotCount()
    if deps_.getUnlockedPlotCount ~= nil then
        return deps_.getUnlockedPlotCount()
    end
    return 1
end

local function GetSelectedPlot()
    if deps_.getSelectedPlot ~= nil then
        return deps_.getSelectedPlot()
    end
    return 1
end

local function SetSelectedPlot(plotIndex)
    if deps_.setSelectedPlot ~= nil then
        deps_.setSelectedPlot(plotIndex)
    end
end

local function GetPlots()
    if deps_.getPlots ~= nil then
        return deps_.getPlots()
    end
    return {}
end

local function PlotWorldPosition(index)
    return deps_.plotWorldPosition(index)
end

local function SetPlotVisible(plot, index, visible)
    if plot == nil or plot.node == nil then return end
    plot.visible = visible
    plot.node:SetWorldPosition(visible and PlotWorldPosition(index) or Vector3(0, -1000, 0))
    plot.node:SetEnabledRecursive(visible)
    -- 如果弹出动画已结束，直接设置目标 scale
    if visible and (deps_.isPlotBounceActive == nil or not deps_.isPlotBounceActive()) and plot.targetScale ~= nil then
        plot.node.scale = plot.targetScale
    end
    if plot.selection ~= nil then
        plot.selection:SetEnabledRecursive(false)
    end
    if plot.plants ~= nil then
        for _, crop in ipairs(plot.plants) do
            if crop.root ~= nil then
                crop.root:SetEnabledRecursive(visible)
            end
        end
    end
end

local function GetUnlockedPlotsCenter()
    local count = math.max(1, GetUnlockedPlotCount())
    local sumX = 0
    local sumZ = 0
    for i = 1, count do
        local pos = PlotWorldPosition(i)
        sumX = sumX + pos.x
        sumZ = sumZ + pos.z
    end
    return Vector3(sumX / count, 0, sumZ / count)
end

function PlotDisplayController.Init(deps)
    deps_ = deps or {}
    displayMode_ = "all"
    focusedPlotIndex_ = 1
end

function PlotDisplayController.GetDisplayMode()
    return displayMode_
end

function PlotDisplayController.GetFocusedPlotIndex()
    return focusedPlotIndex_
end

function PlotDisplayController.SetFocusedPlotIndex(plotIndex)
    focusedPlotIndex_ = plotIndex
end

function PlotDisplayController.IsSingleMode()
    return displayMode_ == "single"
end

function PlotDisplayController.UpdateCameraTarget()
    if deps_.getViewMode() == deps_.ViewMode.PLANT then
        deps_.setCameraTarget(PlotWorldPosition(GetSelectedPlot()))
    elseif displayMode_ == "single" then
        deps_.setCameraTarget(PlotWorldPosition(focusedPlotIndex_))
    else
        deps_.setCameraTarget(GetUnlockedPlotsCenter())
    end
end

function PlotDisplayController.ApplyDisplayMode()
    local plots = GetPlots()
    if #plots == 0 then return end
    focusedPlotIndex_ = Clamp(focusedPlotIndex_, 1, math.max(1, GetUnlockedPlotCount()))
    if displayMode_ == "single" then
        for i, plot in ipairs(plots) do
            SetPlotVisible(plot, i, i == focusedPlotIndex_)
        end
    else
        for i, plot in ipairs(plots) do
            SetPlotVisible(plot, i, i <= GetUnlockedPlotCount())
        end
    end
    PlotDisplayController.UpdateCameraTarget()
end

function PlotDisplayController.RefreshSelection()
    deps_.refreshFarmSelection(GetPlots(), GetSelectedPlot())
    PlotDisplayController.ApplyDisplayMode()
end

function PlotDisplayController.SetDisplayMode(mode)
    if mode ~= "single" then
        displayMode_ = "all"
    else
        displayMode_ = "single"
        focusedPlotIndex_ = 1
        SetSelectedPlot(focusedPlotIndex_)
    end
    PlotDisplayController.ApplyDisplayMode()
    PlotDisplayController.RefreshSelection()
    if displayMode_ == "single" then
        deps_.startSinglePlotBounceAnimation(focusedPlotIndex_)
        ShowToast(string.format("仅显示第 %d 块地", focusedPlotIndex_))
    else
        ShowToast("已显示全部地块")
    end
    RebuildUI()
    RefreshUI(true)
end

function PlotDisplayController.SwitchNextFocusedPlot()
    local unlockedPlotCount = GetUnlockedPlotCount()
    if unlockedPlotCount <= 0 then return end
    focusedPlotIndex_ = focusedPlotIndex_ + 1
    if focusedPlotIndex_ > unlockedPlotCount then
        focusedPlotIndex_ = 1
    end
    SetSelectedPlot(focusedPlotIndex_)
    PlotDisplayController.ApplyDisplayMode()
    PlotDisplayController.RefreshSelection()
    deps_.startSinglePlotBounceAnimation(focusedPlotIndex_)
    FloatingToast.Show(string.format("已切换到第 %d 块地", focusedPlotIndex_))
    ShowToast(string.format("已切换到第 %d 块地", focusedPlotIndex_))
    RebuildUI()
    RefreshUI(true)
end

function PlotDisplayController.ApplyUnlockedPlotCount()
    deps_.applyUnlockedPlotCount(GetPlots(), GetUnlockedPlotCount())
    local selectedPlot = GetSelectedPlot()
    if selectedPlot > GetUnlockedPlotCount() then
        SetSelectedPlot(GetUnlockedPlotCount())
    end
    if focusedPlotIndex_ > GetUnlockedPlotCount() then
        focusedPlotIndex_ = math.max(1, GetUnlockedPlotCount())
    end
    PlotDisplayController.RefreshSelection()
end

function PlotDisplayController.SelectPlotByDelta(dx, dz)
    if displayMode_ == "single" then
        SetSelectedPlot(focusedPlotIndex_)
        PlotDisplayController.RefreshSelection()
        RefreshUI(true)
        return
    end
    local selectedPlot = GetSelectedPlot()
    local config = deps_.config
    local col = ((selectedPlot - 1) % config.GridCols) + 1
    local row = math.floor((selectedPlot - 1) / config.GridCols) + 1
    col = Clamp(col + dx, 1, config.GridCols)
    row = Clamp(row + dz, 1, config.GridRows)
    SetSelectedPlot((row - 1) * config.GridCols + col)
    PlotDisplayController.RefreshSelection()
    RefreshUI(true)
end

return PlotDisplayController
