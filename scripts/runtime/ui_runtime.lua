-- ============================================================================
-- UI 运行时刷新状态机
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有初始 UI 就绪、刷新、延迟 Rebuild 和初始阻塞逻辑。
-- 不改变 loading、首次弹出动画、社交快照上传、modal 延迟刷新时机。
-- ============================================================================

local UiRuntime = {}

local deps_ = {}

function UiRuntime.Init(deps)
    deps_ = deps or {}
end

local function IsInitialUiReady()
    return deps_.isInitialUiReady ~= nil and deps_.isInitialUiReady()
end

local function SetInitialUiReady(value)
    if deps_.setInitialUiReady ~= nil then deps_.setInitialUiReady(value) end
end

local function SetInitialUiBuildPending(value)
    if deps_.setInitialUiBuildPending ~= nil then deps_.setInitialUiBuildPending(value) end
end

local function IsPendingRebuildUI()
    return deps_.isPendingRebuildUI ~= nil and deps_.isPendingRebuildUI()
end

local function SetPendingRebuildUI(value)
    if deps_.setPendingRebuildUI ~= nil then deps_.setPendingRebuildUI(value) end
end

local function IsInitialPlotBounceStarted()
    return deps_.isInitialPlotBounceStarted ~= nil and deps_.isInitialPlotBounceStarted()
end

local function SetInitialPlotBounceStarted(value)
    if deps_.setInitialPlotBounceStarted ~= nil then deps_.setInitialPlotBounceStarted(value) end
end

local function IsInitialSocialSnapshotUploaded()
    return deps_.isInitialSocialSnapshotUploaded ~= nil and deps_.isInitialSocialSnapshotUploaded()
end

local function SetInitialSocialSnapshotUploaded(value)
    if deps_.setInitialSocialSnapshotUploaded ~= nil then deps_.setInitialSocialSnapshotUploaded(value) end
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then deps_.showToast(text, silent) end
end

function UiRuntime.IsInitialDataReady()
    return deps_.EconomyCloudSystem.IsInitialSyncReady ~= nil and deps_.EconomyCloudSystem.IsInitialSyncReady()
end

function UiRuntime.EnsureInitialUiReady()
    if IsInitialUiReady() then return true end
    if not UiRuntime.IsInitialDataReady() then return false end
    SetInitialUiReady(true)
    SetInitialUiBuildPending(false)
    SetPendingRebuildUI(false)
    if not IsInitialPlotBounceStarted() then
        deps_.PlotBounceAnimator.StartAll(deps_.getPlots())
        SetInitialPlotBounceStarted(true)
    end
    deps_.UIController.Rebuild()
    UiRuntime.Refresh(true)
    if IsInitialSocialSnapshotUploaded() ~= true then
        deps_.SocialGardenSystem.UploadSnapshot()
        SetInitialSocialSnapshotUploaded(true)
    end
    print("[启动同步] 初始权威数据已同步，显示主界面")
    return true
end

function UiRuntime.Refresh(force)
    if not IsInitialUiReady() then
        SetInitialUiBuildPending(true)
        return
    end
    deps_.UIController.Refresh(force)
end

function UiRuntime.Rebuild()
    if not IsInitialUiReady() then
        SetInitialUiBuildPending(true)
        return
    end
    if deps_.ModalRegistry.AnyOpen() then
        SetPendingRebuildUI(true)
        return
    end
    SetPendingRebuildUI(false)
    deps_.UIController.Rebuild()
end

function UiRuntime.FlushPendingRebuild()
    if not IsInitialUiReady() then
        UiRuntime.EnsureInitialUiReady()
        return
    end
    if IsPendingRebuildUI() and not deps_.ModalRegistry.AnyOpen() then
        SetPendingRebuildUI(false)
        deps_.UIController.Rebuild()
    end
end

function UiRuntime.IsInitialUiBlocked()
    if IsInitialUiReady() then return false end
    ShowToast("正在同步服务器数据，请稍后")
    UiRuntime.EnsureInitialUiReady()
    return true
end

return UiRuntime
