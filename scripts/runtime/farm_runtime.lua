-- ============================================================================
-- 农场运行时基础生命周期
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有农场创建、销毁、拜访切换和观光值更新逻辑。
-- 不改变地块显示、相机、动画、恢复顺序和提示文案。
-- ============================================================================

local FarmRuntime = {}

local deps_ = {}

function FarmRuntime.Init(deps)
    deps_ = deps or {}
end

local function GetPlots()
    if deps_.getPlots ~= nil then return deps_.getPlots() end
    return {}
end

local function SetPlots(plots)
    if deps_.setPlots ~= nil then deps_.setPlots(plots) end
end

local function GetOwnFarmPlotsSave()
    if deps_.getOwnFarmPlotsSave ~= nil then return deps_.getOwnFarmPlotsSave() end
    return nil
end

local function SetOwnFarmPlotsSave(value)
    if deps_.setOwnFarmPlotsSave ~= nil then deps_.setOwnFarmPlotsSave(value) end
end

local function GetUnlockedPlotCount()
    if deps_.getUnlockedPlotCount ~= nil then return deps_.getUnlockedPlotCount() end
    return 1
end

local function SetUnlockedPlotCount(value)
    if deps_.setUnlockedPlotCount ~= nil then deps_.setUnlockedPlotCount(value) end
end

local function SetSelectedPlot(value)
    if deps_.setSelectedPlot ~= nil then deps_.setSelectedPlot(value) end
end

local function GetSelectedPlot()
    if deps_.getSelectedPlot ~= nil then return deps_.getSelectedPlot() end
    return 1
end

function FarmRuntime.CreateFarm()
    SetPlots(deps_.FarmSystem.CreateFarm(deps_.getScene(), GetUnlockedPlotCount(), LOCAL))
end

function FarmRuntime.DisposeCurrentFarm()
    local plots = GetPlots()
    if plots ~= nil then
        SetOwnFarmPlotsSave(deps_.CropSystem.GetPlotsSaveData(plots))
        for _, plot in ipairs(plots) do
            if plot.node ~= nil then
                plot.node:Dispose()
            end
        end
    end
    SetPlots({})
end

function FarmRuntime.BuildVisitPlots(garden)
    FarmRuntime.DisposeCurrentFarm()
    local plotIndex = tonumber(garden and garden.visitablePlotIndex or 1) or 1
    SetPlots(deps_.FarmSystem.CreateFarm(deps_.getScene(), 1, LOCAL))
    SetUnlockedPlotCount(1)
    SetSelectedPlot(1)
    local plotData = garden and garden.plot or nil
    if plotData ~= nil then
        deps_.CropSystem.RestorePlotsFromSave(GetPlots(), {
            [1] = { plants = plotData.plants or {} },
        })
    end
    deps_.PlotDisplayController.SetDisplayMode("all")
    deps_.CameraSystem.EnterFarmView()
    deps_.refreshSelection()
    deps_.updateCamera()
    print(string.format("[社交花园] 已加载玩家 %s 的可参观地块 %d", tostring(garden and garden.nickname or "好友"), plotIndex))
end

function FarmRuntime.RestoreOwnFarm()
    local restorePlots = GetOwnFarmPlotsSave() or deps_.CropSystem.GetPlotsSaveData(GetPlots())
    FarmRuntime.DisposeCurrentFarm()
    SetOwnFarmPlotsSave(restorePlots)
    SetUnlockedPlotCount(deps_.ProgressionSystem.GetUnlockedPlotCount())
    FarmRuntime.CreateFarm()
    deps_.CropSystem.RestorePlotsFromSave(GetPlots(), GetOwnFarmPlotsSave())
    SetOwnFarmPlotsSave(nil)
    deps_.PlotDisplayController.ApplyUnlockedPlotCount()
    deps_.PlotBounceAnimator.StartAll(GetPlots())
    SetSelectedPlot(Clamp(GetSelectedPlot(), 1, math.max(1, GetUnlockedPlotCount())))
    deps_.CameraSystem.EnterFarmView()
    deps_.updateCameraTargetForPlotDisplay()
    deps_.refreshSelection()
    deps_.updateCamera()
end

function FarmRuntime.UpdateCurrentTourValue()
    local value = deps_.CropSystem.CalculateTotalSightValue(GetPlots())
    deps_.ProgressionSystem.SetCurrentTourValue(value)
    return value
end

function FarmRuntime.ApplyUnlockedPlotCount()
    deps_.PlotDisplayController.ApplyUnlockedPlotCount()
end

function FarmRuntime.ApplyAuthoritativeFarmState(farm)
    if type(farm) ~= "table" or type(farm.plots) ~= "table" then return false end
    local serverUnlocked = deps_.ProgressionSystem.GetUnlockedPlotCount()
    local farmRecreated = false
    if serverUnlocked ~= GetUnlockedPlotCount() then
        SetOwnFarmPlotsSave(deps_.CropSystem.GetPlotsSaveData(GetPlots()))
        FarmRuntime.DisposeCurrentFarm()
        SetUnlockedPlotCount(serverUnlocked)
        FarmRuntime.CreateFarm()
        FarmRuntime.ApplyUnlockedPlotCount()
        farmRecreated = true
    end
    deps_.CropSystem.ClearPlots(GetPlots())
    deps_.CropSystem.RestorePlotsFromSave(GetPlots(), farm.plots)
    if farmRecreated and deps_.isInitialUiReady ~= nil and deps_.isInitialUiReady() then
        deps_.PlotBounceAnimator.StartAll(GetPlots())
        if deps_.setInitialPlotBounceStarted ~= nil then
            deps_.setInitialPlotBounceStarted(true)
        end
    end
    SetOwnFarmPlotsSave(deps_.CropSystem.GetPlotsSaveData(GetPlots()))
    FarmRuntime.UpdateCurrentTourValue()
    deps_.refreshSelection()
    if deps_.markSaveDirty ~= nil then deps_.markSaveDirty() end
    if deps_.rebuildUI ~= nil then deps_.rebuildUI() end
    deps_.refreshUI(true)
    print("[权威农场] 已从服务器重建本地农场")
    return true
end

return FarmRuntime
