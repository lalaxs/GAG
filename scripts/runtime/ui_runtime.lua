-- ============================================================================
-- UI 运行时刷新状态机
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有初始 UI 就绪、刷新、延迟 Rebuild 和初始阻塞逻辑。
-- 不改变 loading、首次弹出动画、社交快照上传、modal 延迟刷新时机。
-- ============================================================================

local UiRuntime = {}

local deps_ = {}
local REBUILD_DEBOUNCE_SEC = 0.08
local rebuildDelayRemaining_ = 0

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

local function ExecuteRebuild()
    rebuildDelayRemaining_ = 0
    SetPendingRebuildUI(false)
    deps_.UIController.Rebuild()
end

function UiRuntime.IsInitialDataReady()
    -- 进主界面必须等核心权威数据：经济+农场真实首包。失败只显示 Loading/重开页。
    local economy = deps_.EconomyCloudSystem
    local economyReady = false
    if economy ~= nil and economy.CanEnterInitialUi ~= nil then
        economyReady = economy.CanEnterInitialUi()
    elseif economy ~= nil and economy.IsInitialSyncReady ~= nil then
        economyReady = economy.IsInitialSyncReady()
    end
    local playerReady = deps_.isInitialPlayerReady == nil or deps_.isInitialPlayerReady()
    return economyReady and playerReady
end

function UiRuntime.EnsureInitialUiReady()
    if IsInitialUiReady() then return true end
    if not UiRuntime.IsInitialDataReady() then return false end
    SetInitialUiReady(true)
    SetInitialUiBuildPending(false)
    SetPendingRebuildUI(false)
    if deps_.showInitialFarm ~= nil then
        deps_.showInitialFarm()
    end
    if not IsInitialPlotBounceStarted() then
        deps_.PlotBounceAnimator.StartAll(deps_.getPlots())
        SetInitialPlotBounceStarted(true)
    end
    ExecuteRebuild()
    UiRuntime.Refresh(true)
    if IsInitialSocialSnapshotUploaded() ~= true then
        local canUploadSnapshot = true
        if deps_.EconomyCloudSystem ~= nil
            and deps_.EconomyCloudSystem.IsInitialAuthorityDegraded ~= nil
            and deps_.EconomyCloudSystem.IsInitialAuthorityDegraded() == true then
            canUploadSnapshot = false
            print("[启动同步] 当前为只读降级模式，跳过初始花园快照上传")
        end
        if canUploadSnapshot and deps_.SocialGardenSystem.UploadSnapshot() then
            SetInitialSocialSnapshotUploaded(true)
        end
    end
    if deps_.initBGM ~= nil then
        deps_.initBGM()
    end
    print("[启动同步] 初始权威数据已同步，显示主界面")
    print("=== Grow A Garden 核心玩法原型启动 ===")
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
    SetPendingRebuildUI(true)
    if rebuildDelayRemaining_ <= 0 then
        rebuildDelayRemaining_ = REBUILD_DEBOUNCE_SEC
    end
end

function UiRuntime.FlushPendingRebuild(dt)
    if not IsInitialUiReady() then
        UiRuntime.EnsureInitialUiReady()
        return
    end
    if not IsPendingRebuildUI() or deps_.ModalRegistry.AnyOpen() then return end

    if dt == nil then
        rebuildDelayRemaining_ = 0
    else
        rebuildDelayRemaining_ = math.max(0, rebuildDelayRemaining_ - dt)
    end
    if rebuildDelayRemaining_ <= 0 then
        ExecuteRebuild()
    end
end

function UiRuntime.IsInitialUiBlocked()
    if IsInitialUiReady() then return false end
    ShowToast("同步中")
    UiRuntime.EnsureInitialUiReady()
    return true
end

return UiRuntime
