require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local ModalRegistry = require("ui.modal_registry")
local Shop = require("shop")
local SeedVisual = require("seed_visual")
local GameConfig = require("config.game_config")
local InventorySystem = require("systems.inventory_system")
local ProgressionSystem = require("systems.progression_system")
local PlantVisual = require("visuals.plant_visual")
local CropSystem = require("systems.crop_system")
local FarmSystem = require("systems.farm_system")
local Format = require("utils.format")

local SceneSystem = require("systems.scene_system")
local CameraSystem = require("systems.camera_system")
local InteractionSystem = require("systems.interaction_system")
local AudioSystem = require("systems.audio_system")
local SeedPackSystem = require("systems.seed_pack_system")
local CommissionSystem = require("systems.commission_system")
AdRewardSystem = require("systems.ad_reward_system")
local SeedPackOpeningController = require("controllers.seed_pack_opening_controller")
local ExpansionController = require("controllers.expansion_controller")
local PlotDisplayController = require("controllers.plot_display_controller")
local UIController = require("controllers.ui_controller")
local PlantActionController = require("controllers.plant_action_controller")
local WalletSystem = require("systems.wallet_system")
local TalentSystem = require("systems.talent_system")
local ActivitySystem = require("systems.activity_system")
local ModelPreviewSystem = require("systems.model_preview_system")
local PlayerSystem = require("systems.player_system")
local SocialGardenSystem = require("systems.social_garden_system")
local EconomyCloudSystem = require("systems.economy_cloud_system")
local LeaderboardSystem = require("systems.leaderboard_system")
local NetworkRecovery = require("runtime.network_recovery")
local FarmRuntime = require("runtime.farm_runtime")
local AdRewardActions = require("runtime.ad_reward_actions")
local UiEventBindings = require("runtime.ui_event_bindings")
local UiRuntime = require("runtime.ui_runtime")
local UiBindings = require("runtime.ui_bindings")
-- 纯服务器游戏：主游戏进度只从服务端 serverCloud 同步，客户端不再读写本地完整存档。
local TalentView = require("ui.talent_view")
local ExpansionView = require("ui.expansion_view")
local SeedPackView = require("ui.seed_pack_view")
local TaskView = require("ui.task_view")
local CommissionView = require("ui.commission_view")
local CodexView = require("ui.codex_view")
local PlantPanelView = require("ui.plant_panel_view")
local BagDetailView = require("ui.bag_detail_view")
local MainView = require("ui.main_view")
local ActivityView = require("ui.activity_view")
local ModelPreviewView = require("ui.model_preview_view")
local ProfileView = require("ui.profile_view")
local SocialView = require("ui.social_view")
local LeaderboardView = require("ui.leaderboard_view")
local SettingsView = require("ui.settings_view")
local BulkSellView = require("ui.bulk_sell_view")
local FloatingToast = require("ui.floating_toast")
local PlotBounceAnimator = require("visuals.plot_bounce_animator")

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
local CONFIG = GameConfig.CONFIG
local RARITY_COLORS = GameConfig.RARITY_COLORS
local PLANTS = GameConfig.PLANTS
local RARITY_ORDER = GameConfig.RARITY_ORDER
local SEED_PACK_CONFIG = GameConfig.SEED_PACK_CONFIG
local DAILY_TASK_CONFIG = GameConfig.DAILY_TASK_CONFIG

local materials_ = PlantVisual.materials
local plots_ = {}
local selectedPlot_ = 1
local selectedSeed_ = 1
local inventoryState_ = InventorySystem.GetState()
local seedBag_ = inventoryState_.seedBag
local seedBagBuffs_ = inventoryState_.seedBagBuffs
local harvested_ = inventoryState_.harvested
local seedPacks_ = inventoryState_.seedPacks
local collectedPlants_ = inventoryState_.collectedPlants
local tutorialState_ = inventoryState_.tutorial
local codexStats_ = inventoryState_.codexStats
local silverRewardClaimed_ = inventoryState_.silverRewardClaimed
local dailyTaskState_ = inventoryState_.dailyTaskState
local taskModal_ = nil
local pendingRebuildUI_ = false
local harvestPanelRefreshTimer_ = 0
local initialUiReady_ = false
local initialUiBuildPending_ = false
local initialPlayerReady_ = false
local initialSocialSnapshotUploaded_ = false
local initialPlotBounceStarted_ = false
local selectedBagItem_ = nil
local ViewMode = CameraSystem.ViewMode
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local plantTab_ = "seed"  -- "seed" | "harvest" | "bag"
local saveData_ = nil
local hasSaveData_ = false
local saveTimer_ = 0
local saveDirty_ = false
local SAVE_FLUSH_INTERVAL = 1.0
local saveDisabled_ = true
local ownFarmPlotsSave_ = nil
local suppressNextWorldTap_ = false
-- 以下函数名需要跨初始化闭包互相引用，使用全局可避免 main.lua 顶层 local 超过 Lua 限制。

function SyncInventoryRefs()
    inventoryState_ = InventorySystem.GetState()
    seedBag_ = inventoryState_.seedBag
    seedBagBuffs_ = inventoryState_.seedBagBuffs
    harvested_ = inventoryState_.harvested
    seedPacks_ = inventoryState_.seedPacks
    collectedPlants_ = inventoryState_.collectedPlants
    tutorialState_ = inventoryState_.tutorial
    codexStats_ = inventoryState_.codexStats
    silverRewardClaimed_ = inventoryState_.silverRewardClaimed
    dailyTaskState_ = inventoryState_.dailyTaskState
end

function MarkSaveDirty()
    -- 纯服务器游戏：客户端不保存权威玩法进度；此函数仅保留给现有依赖调用。
    saveDirty_ = false
    saveTimer_ = 0
end

function SaveGameNow()
    -- 纯服务器游戏：权威数据由 serverCloud 保存。
    saveDirty_ = false
    saveTimer_ = 0
    return true
end

function ClearGameSave()
    local requested = EconomyCloudSystem.ClearSave()
    if not requested and ShowToast ~= nil then
        ShowToast("服务器尚未就绪，无法清除存档")
    end
    saveDirty_ = false
    saveDisabled_ = true
    return requested
end

function ApplyAuthoritativeFarmState(farm)
    return FarmRuntime.ApplyAuthoritativeFarmState(farm)
end

function AddSeedToBag(plantIndex, count, buff)
    local added = InventorySystem.AddSeedToBag(plantIndex, count, buff)
    if added > 0 then MarkSaveDirty() end
    return added
end

function CountSeedPacks()
    return InventorySystem.CountSeedPacks()
end

function GetHighestPackIcon()
    local bestOrder = 0
    local bestIcon = "image/seedpack_icon/seedpack_0.png"
    for packId, cfg in pairs(SEED_PACK_CONFIG) do
        local owned = seedPacks_[packId] or 0
        if owned > 0 then
            local order = RARITY_ORDER[cfg.packRarity or "普通"] or 0
            if order > bestOrder then
                bestOrder = order
                bestIcon = cfg.packIcon or "image/seedpack_icon/seedpack_0.png"
            end
        end
    end
    return bestIcon
end

function AddSeedPack(packId, count)
    local ok = InventorySystem.AddSeedPack(packId, count)
    if ok then MarkSaveDirty() end
    return ok
end

function IsTaskCompleted(taskCfg)
    return InventorySystem.IsTaskCompleted(taskCfg)
end

function AreAllDailyTasksCompleted()
    return InventorySystem.AreAllDailyTasksCompleted()
end

function AddDailyProgress(key, amount)
    InventorySystem.AddDailyProgress(key, amount)
end

function CheckSilverPackRewards()
    InventorySystem.CheckSilverPackRewards()
end

function InitMaterials()
    PlantVisual.InitMaterials()
end

function ResolvePlantMaterial(plant, mutation)
    return PlantVisual.ResolvePlantMaterial(plant, mutation)
end

function CreatePlantVisual(parent, plant, mutation, material)
    return PlantVisual.CreatePlantVisual(parent, plant, mutation, material)
end

function CreateSpecialEffects(plantData)
    PlantVisual.CreateSpecialEffects(plantData)
end

function CreateScene()
    scene_, cameraNode_, camera_ = SceneSystem.CreateScene()
    CameraSystem.Init(CONFIG, cameraNode_)
end

function CreateSkybox()
    SceneSystem.CreateSkybox(scene_)
end

function UpdateCamera()
    CameraSystem.UpdateCamera()
end

function GetViewMode()
    return CameraSystem.GetViewMode()
end

function IsPlantGuideDone()
    return tutorialState_ ~= nil and tutorialState_.plantGuideDone == true
end

function ShouldShowPlantGuide()
    return initialUiReady_ == true and not IsPlantGuideDone() and not SocialGardenSystem.IsVisitMode()
end

function GetPlantGuideStep()
    if not ShouldShowPlantGuide() then return "done" end
    if GetViewMode() == ViewMode.FARM then return "start" end
    if plantTab_ ~= "seed" then return "seed_tab" end
    return "plant"
end

function CompletePlantGuide()
    if tutorialState_ == nil then return end
    tutorialState_.plantGuideDone = true
end

function EnterPlantView()
    selectedPlot_ = Clamp(selectedPlot_, 1, math.max(1, unlockedPlotCount_))
    if ShouldShowPlantGuide() then
        plantTab_ = "seed"
    end
    if EconomyCloudSystem ~= nil and EconomyCloudSystem.RequestAuthFarm ~= nil then
        print(string.format("[种植模式] 进入前请求权威农场刷新 plot=%d", selectedPlot_))
        EconomyCloudSystem.RequestAuthFarm({ force = true, reason = "enter_plant_view" })
    end
    CameraSystem.SetTarget(FarmSystem.PlotWorldPosition(selectedPlot_))
    CameraSystem.EnterPlantView()
    RefreshSelection()
    ShowToast(string.format("进入第 %d 块地种植模式", selectedPlot_), true)
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

function EnterFarmView()
    CameraSystem.EnterFarmView()
    UpdateCameraTargetForPlotDisplay()
    selectedBagItem_ = nil
    if ClearBagPreview ~= nil then
        ClearBagPreview()
    end
    ShowToast("自由查看农场", true)
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

function PlotWorldPosition(index)
    return FarmSystem.PlotWorldPosition(index)
end

CreateFarm = function()
    FarmRuntime.CreateFarm()
end

DisposeCurrentFarm = function()
    FarmRuntime.DisposeCurrentFarm()
end

function BuildVisitPlots(garden)
    FarmRuntime.BuildVisitPlots(garden)
end

function RestoreOwnFarm()
    FarmRuntime.RestoreOwnFarm()
end

function IsServerConnectionAvailable()
    return NetworkRecovery.IsServerConnectionAvailable()
end

function RequestNetworkRecoverySync(reason)
    return NetworkRecovery.RequestSync(reason)
end

function RestoreOwnFarmForNetworkRecovery(message)
    return NetworkRecovery.RestoreOwnFarm(message)
end

function UpdateNetworkRecovery(dt)
    NetworkRecovery.Update(dt)
end

--- 启动地块依次弹出动画
function StartPlotBounceAnimation()
    PlotBounceAnimator.StartAll(plots_)
end

function StartSinglePlotBounceAnimation(plotIndex)
    PlotBounceAnimator.StartSingle(plots_, plotIndex)
end

--- 更新地块弹出动画
function UpdatePlotBounceAnimation(dt)
    PlotBounceAnimator.Update(plots_, dt)
end

UpdateCameraTargetForPlotDisplay = function()
    PlotDisplayController.UpdateCameraTarget()
end

RefreshSelection = function()
    PlotDisplayController.RefreshSelection()
end

function SetPlotDisplayMode(mode)
    PlotDisplayController.SetDisplayMode(mode)
end

function SwitchNextFocusedPlot()
    PlotDisplayController.SwitchNextFocusedPlot()
end

function ZoomPlantView(direction)
    CameraSystem.AdjustDistance(direction * 0.9, CONFIG.PlantViewMinDistance, CONFIG.PlantViewMaxDistance)
end

ApplyUnlockedPlotCount = function()
    FarmRuntime.ApplyUnlockedPlotCount()
end

ClearBagPreview = function()
end

function CreateBagPreview(item)
end

function CloseBagItemDetail()
    selectedBagItem_ = nil
    ClearBagPreview()
    if RebuildUI ~= nil then RebuildUI() end
end

function OpenBagItemDetail(item)
    if item == nil then return end
    selectedBagItem_ = item
    CreateBagPreview(item)
    if RebuildUI ~= nil then RebuildUI() end
end


function ClampToPlot(localPos)
    return CropSystem.ClampToPlot(localPos)
end

function FindPlantAtLocalPosition(plot, localPos, matureOnly)
    return CropSystem.FindPlantAtLocalPosition(plot, localPos, matureOnly)
end

function PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    local ok, reason = PlantActionController.PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    if ok then MarkSaveDirty() end
    return ok, reason
end

function HarvestNearestMature(plotIndex, localPos)
    local success, harvestInfo = PlantActionController.HarvestNearestMature(plotIndex, localPos)
    if success then
        if harvestInfo and harvestInfo.pendingServer then
            ShowToast("正在请求服务器收获...", true)
            return success, harvestInfo
        end
        MarkSaveDirty()
        EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "harvest_crop" })
        EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = "harvest_crop" })
        local cropName = harvestInfo and harvestInfo.name or "作物"
        local exp = harvestInfo and harvestInfo.exp or 0
        local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
        ShowToast(text, true)
        FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
    end
    return success, harvestInfo
end

function PlantSeed(plotIndex, plantIndex)
    local ok, reason = PlantActionController.PlantSeed(plotIndex, plantIndex)
    if ok then MarkSaveDirty() end
    return ok, reason
end

function BuySelectedSeed()
    local ok, reason = PlantActionController.BuySelectedSeed()
    if ok then MarkSaveDirty() end
    return ok, reason
end

function SellAllHarvested()
    local ok, value = PlantActionController.SellAllHarvested()
    if ok then MarkSaveDirty() end
    return ok, value
end

function SellBagItem(item)
    local ok, value = PlantActionController.SellBagItem(item)
    if ok then MarkSaveDirty() end
    return ok, value
end

function SellHarvestedByFilter(filter)
    local ok, value = PlantActionController.SellHarvestedByFilter(filter)
    if ok then MarkSaveDirty() end
    return ok, value
end

function CountPlotPlants(plot)
    return CropSystem.CountPlotPlants(plot)
end

function CountMaturePlants(plot)
    return CropSystem.CountMaturePlants(plot)
end

function GetPlotText(plot)
    return CropSystem.GetPlotText(plot)
end

ShowToast = function(text, silent)
    UIController.ShowToast(text)
end

function FindNextOwnedSeedIndex(startIndex)
    return PlantActionController.FindNextOwnedSeedIndex(startIndex)
end

function EnsureSelectedSeedAvailable()
    return PlantActionController.EnsureSelectedSeedAvailable()
end

function SelectNextOwnedSeedIfEmpty(fromIndex)
    return PlantActionController.SelectNextOwnedSeedIfEmpty(fromIndex)
end

function SetSelectedSeedIndex(index)
    PlantActionController.SetSelectedSeedIndex(index)
end

function GetUiRarityColor(rarity)
    local c = RARITY_COLORS[rarity]
    if c == nil then return {200, 200, 200, 255} end
    return { math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), 255 }
end

function CountPackResults(results)
    return SeedPackSystem.CountResults(results)
end

function GetFirstAvailablePackId()
    return SeedPackSystem.GetFirstAvailablePackId()
end



function OpenSeedPack(packId)
    SeedPackOpeningController.OpenPack(packId)
end

function OpenAllSeedPacks(packId)
    SeedPackOpeningController.OpenAllPacks(packId)
end

ShowAdRewardPrompt = function(title, message, rewardType, extra)
    return AdRewardActions.ShowPrompt(title, message, rewardType, extra)
end

RequestStealAttemptsAdReward = function()
    return AdRewardActions.RequestStealAttempts()
end

RequestRareSeedPackAdReward = function()
    return AdRewardActions.RequestRareSeedPack()
end

RequestMaturePlotAdReward = function()
    return AdRewardActions.RequestMaturePlot()
end

function IsInitialUiBlocked()
    return UiRuntime.IsInitialUiBlocked()
end

OpenSeedPackHub = function()
    if IsInitialUiBlocked() then return end
    SeedPackOpeningController.OpenHub()
end

function BuildSeedPackOverlay()
    return SeedPackOpeningController.BuildPackOverlay()
end

function BuildSeedPackOpeningOverlay()
    return SeedPackOpeningController.BuildOpeningOverlay()
end

OpenTaskPanel = function()
    if IsInitialUiBlocked() then return end
    TaskView.Open()
end

OpenCommissionPanel = function()
    if IsInitialUiBlocked() then return end
    CommissionView.Show()
end

ExpandNextPlot = function()
    if IsInitialUiBlocked() then return false end
    return ExpansionController.ExpandNextPlot()
end


function PerformPlotAction(plotIndex, localPos)
    PlantActionController.PerformPlotAction(plotIndex, localPos)
end

function SelectSeedIndex(index)
    PlantActionController.SelectSeedIndex(index)
end

function SubscribeUIEvents()
    UiEventBindings.Subscribe()
end

function UnsubscribeUIEvents()
    UiEventBindings.Unsubscribe()
end

function RegisterModalGuards()
    UiEventBindings.RegisterModalGuards()
end

function IsInitialDataReady()
    return UiRuntime.IsInitialDataReady()
end

EnsureInitialUiReady = function()
    return UiRuntime.EnsureInitialUiReady()
end

RefreshUI = function(force)
    UiRuntime.Refresh(force)
end

RebuildUI = function()
    UiRuntime.Rebuild()
end

function FlushPendingRebuildUI()
    UiRuntime.FlushPendingRebuild()
end

HandleClearSaveCompleted = function(success)
    SettingsView.HandleClearSaveCompleted(success)
    if not success then return end

    SettingsView.Close()
    ProfileView.Close()
    selectedBagItem_ = nil
    plantTab_ = "seed"
    if ClearBagPreview ~= nil then
        ClearBagPreview()
    end

    CameraSystem.EnterFarmView()
    PlotDisplayController.SetDisplayMode("all")
    selectedPlot_ = Clamp(selectedPlot_, 1, math.max(1, unlockedPlotCount_))
    UpdateCameraTargetForPlotDisplay()
    RefreshSelection()
    UpdateCamera()

    UIController.RefreshInventoryPanels()
    pendingRebuildUI_ = false
    UIController.Rebuild()
    RefreshUI(true)
    FloatingToast.Show("存档已清除，已返回主界面", { fontSize = 20, duration = 1.8, yRatio = 0.38, priority = 10 })
end

SelectPlotByDelta = function(dx, dz)
    PlotDisplayController.SelectPlotByDelta(dx, dz)
end

function CycleSeed(delta)
    PlantActionController.CycleSeed(delta)
end

function RequestSuppressWorldTap()
    suppressNextWorldTap_ = true
    if InteractionSystem ~= nil and InteractionSystem.SuppressNextWorldTap ~= nil then
        InteractionSystem.SuppressNextWorldTap()
    end
end

function SyncWorldTapSuppression()
    if suppressNextWorldTap_ then
        InteractionSystem.SuppressNextWorldTap()
        suppressNextWorldTap_ = false
    end
end

function HandleMouseButtonDown(eventType, eventData)
    SyncWorldTapSuppression()
    InteractionSystem.HandleMouseButtonDown(eventData)
end

function HandleMouseMove(eventType, eventData)
    InteractionSystem.HandleMouseMove(eventData)
end

function HandleMouseWheel(eventType, eventData)
    InteractionSystem.HandleMouseWheel(eventData)
end

function HandleTouchBegin(eventType, eventData)
    SyncWorldTapSuppression()
    InteractionSystem.HandleTouchBegin(eventData)
end

function HandleTouchMove(eventType, eventData)
    InteractionSystem.HandleTouchMove(eventData)
end

function UpdateTouchCameraGesture()
    InteractionSystem.UpdateTouchCameraGesture()
end

function HandleInput(dt)
    InteractionSystem.HandleInput(dt)
end

UpdateCurrentTourValue = function()
    return FarmRuntime.UpdateCurrentTourValue()
end

function UpdatePlants(dt)
    local maturedThisFrame = CropSystem.UpdatePlants(plots_, dt, PlayerSystem.IsMatureCropRotationEnabled())
    UpdateCurrentTourValue()
    if plantTab_ == "harvest" and GetViewMode() == ViewMode.PLANT then
        harvestPanelRefreshTimer_ = harvestPanelRefreshTimer_ + dt
        if maturedThisFrame and RebuildUI ~= nil then
            harvestPanelRefreshTimer_ = 0
            RebuildUI()
        elseif harvestPanelRefreshTimer_ >= 1.0 and not ModalRegistry.AnyOpen() then
            harvestPanelRefreshTimer_ = 0
            PlantPanelView.RefreshHarvestCountdowns(plots_[selectedPlot_])
        end
    else
        harvestPanelRefreshTimer_ = 0
    end
end

function UpdateSeedPackOpening(dt)
    SeedPackOpeningController.Update(dt)
end

function HandleNetworkRecoveryServerReady(eventType, eventData)
    NetworkRecovery.HandleServerReady()
end

function HandleNetworkRecoveryServerDisconnected(eventType, eventData)
    NetworkRecovery.HandleServerDisconnected()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateNetworkRecovery(dt)

    if not initialUiReady_ then
        PlayerSystem.Update(dt)
        EconomyCloudSystem.Update(dt)
        AdRewardSystem.Update(dt)
        SocialGardenSystem.Update(dt)
        LeaderboardSystem.Update(dt)
        if NetworkRecovery.UpdateLoading(dt) then
            UIController.ShowLoading("服务器响应较慢，正在重试同步...")
            RequestNetworkRecoverySync("loading_timeout")
        end
        EnsureInitialUiReady()
        FloatingToast.Update(dt)
        UIController.Update(dt)
        AudioSystem.Update(dt)
        return
    end

    if not ModelPreviewSystem.IsOpen() then
        HandleInput(dt)
        UpdateTouchCameraGesture()
    end
    UpdatePlotBounceAnimation(dt)
    UpdatePlants(dt)
    UpdateSeedPackOpening(dt)
    ModelPreviewSystem.Update(dt)
    Shop.Update(dt)
    PlayerSystem.Update(dt)
    EconomyCloudSystem.Update(dt)
    AdRewardSystem.Update(dt)
    SocialGardenSystem.Update(dt)
    LeaderboardSystem.Update(dt)
    CommissionSystem.Update(dt)
    if saveDirty_ then
        saveTimer_ = saveTimer_ + dt
        if saveTimer_ >= SAVE_FLUSH_INTERVAL then
            local saved = SaveGameNow()
            if saved then
                SocialGardenSystem.UploadSnapshot()
                saveDirty_ = false
                saveTimer_ = 0
            else
                saveTimer_ = 0
            end
        end
    end
    FloatingToast.Update(dt)

    UIController.Update(dt)
    FlushPendingRebuildUI()
    AudioSystem.Update(dt)
    RefreshUI(false)
end

--- 获取花园等级（基于玩家当前等级）
function GetGardenLevel()
    return TalentSystem.GetLevel()
end

function InitBGM()
    AudioSystem.InitSFX(scene_)
    AudioSystem.InitBGM(scene_)
end

function HandleSoundFinished(eventType, eventData)
    AudioSystem.HandleSoundFinished(eventData)
end

function Start()
    SampleStart()
    UiEventBindings.Init({
        EventBus = EventBus,
        UIEvents = UIEvents,
        ModalRegistry = ModalRegistry,
        UIController = UIController,
        SocialView = SocialView,
        LeaderboardView = LeaderboardView,
        SeedPackView = SeedPackView,
        TaskView = TaskView,
        ModelPreviewSystem = ModelPreviewSystem,
        ActivityView = ActivityView,
        ProfileView = ProfileView,
        SettingsView = SettingsView,
        Shop = Shop,
        CommissionView = CommissionView,
        ExpansionView = ExpansionView,
        TalentView = TalentView,
        BulkSellView = BulkSellView,
        CodexView = CodexView,
        refreshUI = RefreshUI,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })
    RegisterModalGuards()
    graphics.windowTitle = CONFIG.Title
    math.randomseed(os.time())
    saveData_, hasSaveData_ = nil, false
    saveDisabled_ = true
    initialUiReady_ = false
    initialUiBuildPending_ = false
    initialPlayerReady_ = false
    initialSocialSnapshotUploaded_ = false
    initialPlotBounceStarted_ = false
    UiRuntime.Init({
        EconomyCloudSystem = EconomyCloudSystem,
        UIController = UIController,
        ModalRegistry = ModalRegistry,
        PlotBounceAnimator = PlotBounceAnimator,
        SocialGardenSystem = SocialGardenSystem,
        getPlots = function() return plots_ end,
        showInitialFarm = function() FarmRuntime.ShowInitialFarm() end,
        isInitialUiReady = function() return initialUiReady_ end,
        setInitialUiReady = function(value) initialUiReady_ = value end,
        setInitialUiBuildPending = function(value) initialUiBuildPending_ = value end,
        isPendingRebuildUI = function() return pendingRebuildUI_ end,
        setPendingRebuildUI = function(value) pendingRebuildUI_ = value end,
        isInitialPlotBounceStarted = function() return initialPlotBounceStarted_ end,
        setInitialPlotBounceStarted = function(value) initialPlotBounceStarted_ = value end,
        isInitialSocialSnapshotUploaded = function() return initialSocialSnapshotUploaded_ end,
        setInitialSocialSnapshotUploaded = function(value) initialSocialSnapshotUploaded_ = value end,
        showToast = ShowToast,
    })
    NetworkRecovery.Init({
        SocialGardenSystem = SocialGardenSystem,
        EconomyCloudSystem = EconomyCloudSystem,
        showToast = ShowToast,
    })
    NetworkRecovery.ResetLoadingState()
    UIController.ShowLoading("正在同步服务器数据...")

    InitMaterials()
    FarmSystem.Init(CONFIG, materials_)
    CreateScene()
    FarmRuntime.Init({
        FarmSystem = FarmSystem,
        CropSystem = CropSystem,
        ProgressionSystem = ProgressionSystem,
        PlotDisplayController = PlotDisplayController,
        PlotBounceAnimator = PlotBounceAnimator,
        CameraSystem = CameraSystem,
        getScene = function() return scene_ end,
        getPlots = function() return plots_ end,
        setPlots = function(value) plots_ = value end,
        getOwnFarmPlotsSave = function() return ownFarmPlotsSave_ end,
        setOwnFarmPlotsSave = function(value) ownFarmPlotsSave_ = value end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        setUnlockedPlotCount = function(value) unlockedPlotCount_ = value end,
        getSelectedPlot = function() return selectedPlot_ end,
        setSelectedPlot = function(value) selectedPlot_ = value end,
        refreshSelection = RefreshSelection,
        updateCamera = UpdateCamera,
        updateCameraTargetForPlotDisplay = UpdateCameraTargetForPlotDisplay,
        isInitialUiReady = function() return initialUiReady_ end,
        setInitialPlotBounceStarted = function(value) initialPlotBounceStarted_ = value end,
        markSaveDirty = MarkSaveDirty,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshUI = RefreshUI,
    })
    ModelPreviewSystem.Init(GameConfig, {
        scene = scene_,
        cameraNode = cameraNode_,
        PlantVisual = PlantVisual,
    })
    ProgressionSystem.Init(CONFIG)
    unlockedPlotCount_ = ProgressionSystem.GetUnlockedPlotCount()
    CreateFarm()
    PlantActionController.Init({
        config = CONFIG,
        plants = PLANTS,
        seedBag = seedBag_,
        CropSystem = CropSystem,
        InventorySystem = InventorySystem,
        WalletSystem = WalletSystem,
        TalentSystem = TalentSystem,
        ActivitySystem = ActivitySystem,
        EconomyCloudSystem = EconomyCloudSystem,
        getPlots = function() return plots_ end,
        getSelectedPlot = function() return selectedPlot_ end,
        setSelectedPlot = function(plotIndex) selectedPlot_ = plotIndex end,
        getSelectedSeed = function() return selectedSeed_ end,
        setSelectedSeed = function(seedIndex) selectedSeed_ = seedIndex end,
        setSelectedBagItem = function(item) selectedBagItem_ = item end,
        getPlantTab = function() return plantTab_ end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        addSeedToBag = AddSeedToBag,
        clearBagPreview = ClearBagPreview,
        markDirty = MarkSaveDirty,
        refreshSelection = RefreshSelection,
        refreshUI = RefreshUI,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        showToast = ShowToast,
        countPlotPlants = CountPlotPlants,
        countMaturePlants = CountMaturePlants,
        findPlantAtLocalPosition = FindPlantAtLocalPosition,
        refreshTourValue = UpdateCurrentTourValue,
    })

    UiBindings.Init({
        CONFIG = CONFIG,
        GameConfig = GameConfig,
        PLANTS = PLANTS,
        RARITY_ORDER = RARITY_ORDER,
        SEED_PACK_CONFIG = SEED_PACK_CONFIG,
        DAILY_TASK_CONFIG = DAILY_TASK_CONFIG,
        ViewMode = ViewMode,
        UIController = UIController,
        SeedPackView = SeedPackView,
        TaskView = TaskView,
        ActivityView = ActivityView,
        SocialView = SocialView,
        ModelPreviewView = ModelPreviewView,
        CommissionView = CommissionView,
        PlantPanelView = PlantPanelView,
        BagDetailView = BagDetailView,
        BulkSellView = BulkSellView,
        CodexView = CodexView,
        MainView = MainView,
        ProfileView = ProfileView,
        SettingsView = SettingsView,
        TalentView = TalentView,
        ExpansionView = ExpansionView,
        LeaderboardView = LeaderboardView,
        Shop = Shop,
        PlayerSystem = PlayerSystem,
        LeaderboardSystem = LeaderboardSystem,
        PlotDisplayController = PlotDisplayController,
        ActivitySystem = ActivitySystem,
        ModelPreviewSystem = ModelPreviewSystem,
        CommissionSystem = CommissionSystem,
        CameraSystem = CameraSystem,
        WalletSystem = WalletSystem,
        ProgressionSystem = ProgressionSystem,
        TalentSystem = TalentSystem,
        SocialGardenSystem = SocialGardenSystem,
        SeedPackOpeningController = SeedPackOpeningController,
        InventorySystem = InventorySystem,
        EconomyCloudSystem = EconomyCloudSystem,
        FloatingToast = FloatingToast,
        EventBus = EventBus,
        UIEvents = UIEvents,
        getSeedBag = function() return seedBag_ end,
        getHarvested = function() return harvested_ end,
        getSeedPacks = function() return seedPacks_ end,
        getCollectedPlants = function() return collectedPlants_ end,
        getCodexStats = function() return codexStats_ end,
        getDailyTaskState = function() return dailyTaskState_ end,
        getPlots = function() return plots_ end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedPlot = function() return plots_[selectedPlot_] end,
        getSelectedSeed = function() return selectedSeed_ end,
        setSelectedSeedIndex = SetSelectedSeedIndex,
        getSelectedBagItem = function() return selectedBagItem_ end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        getPlantTab = function() return plantTab_ end,
        getViewMode = GetViewMode,
        countSeedPacks = CountSeedPacks,
        countMaturePlants = CountMaturePlants,
        countPlotPlants = CountPlotPlants,
        harvestNearestMature = HarvestNearestMature,
        openBagItemDetail = OpenBagItemDetail,
        closeBagItemDetail = CloseBagItemDetail,
        sellBagItem = SellBagItem,
        sellHarvestedByFilter = SellHarvestedByFilter,
        buildSeedPackOverlay = BuildSeedPackOverlay,
        buildSeedPackOpeningOverlay = BuildSeedPackOpeningOverlay,
        createBagPreview = CreateBagPreview,
        getUiRarityColor = GetUiRarityColor,
        countPackResults = CountPackResults,
        getFirstAvailablePackId = GetFirstAvailablePackId,
        openSeedPack = OpenSeedPack,
        openAllSeedPacks = OpenAllSeedPacks,
        requestRareSeedPackAdReward = RequestRareSeedPackAdReward,
        suppressWorldTap = RequestSuppressWorldTap,
        requestStealAttemptsAdReward = RequestStealAttemptsAdReward,
        flushPendingRebuildUI = FlushPendingRebuildUI,
        updateCameraTargetForPlotDisplay = UpdateCameraTargetForPlotDisplay,
        refreshUI = RefreshUI,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        getTaskModal = function() return taskModal_ end,
        setTaskModal = function(modal) taskModal_ = modal end,
        areAllDailyTasksCompleted = AreAllDailyTasksCompleted,
        setPlantTab = function(tab) plantTab_ = tab end,
        enterPlantView = EnterPlantView,
        enterFarmView = EnterFarmView,
        openCommissionPanel = OpenCommissionPanel,
        openSeedPackHub = OpenSeedPackHub,
        openTaskPanel = OpenTaskPanel,
        getHighestPackIcon = GetHighestPackIcon,
        clearSelectedBagItem = function() selectedBagItem_ = nil end,
        clearBagPreview = function()
            if ClearBagPreview ~= nil then ClearBagPreview() end
        end,
        getPlantGuideStep = GetPlantGuideStep,
        requestMaturePlotAdReward = RequestMaturePlotAdReward,
        clearGameSave = ClearGameSave,
        zoomPlantView = ZoomPlantView,
        setPlotDisplayMode = SetPlotDisplayMode,
        switchNextFocusedPlot = SwitchNextFocusedPlot,
        markSaveDirty = MarkSaveDirty,
    })
    UiBindings.InitUIController()
    SubscribeUIEvents()
    PlotDisplayController.Init({
        config = CONFIG,
        ViewMode = ViewMode,
        getViewMode = GetViewMode,
        getPlots = function() return plots_ end,
        getSelectedPlot = function() return selectedPlot_ end,
        setSelectedPlot = function(plotIndex) selectedPlot_ = plotIndex end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        plotWorldPosition = PlotWorldPosition,
        setCameraTarget = function(position) CameraSystem.SetTarget(position) end,
        refreshFarmSelection = function(plots, selectedPlot) FarmSystem.RefreshSelection(plots, selectedPlot) end,
        applyUnlockedPlotCount = function(plots, unlockedPlotCount) FarmSystem.ApplyUnlockedPlotCount(plots, unlockedPlotCount) end,
        isPlotBounceActive = function() return PlotBounceAnimator.IsActive() end,
        startSinglePlotBounceAnimation = StartSinglePlotBounceAnimation,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshUI = RefreshUI,
    })
    ApplyUnlockedPlotCount()

    WalletSystem.Init(CONFIG.StartMoney)
    InventorySystem.Init(GameConfig, {
        allowLocalMutations = false,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 5 })
        end,
        getHarvestBagBonus = function()
            return TalentSystem.GetBonus("bagCapacity")
        end,
    })

    SeedPackSystem.Init(GameConfig, InventorySystem)
    ActivitySystem.Init(GameConfig, InventorySystem, {
        allowLocalRewards = false,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 5 })
        end,
    })
    AdRewardSystem.Init({
        showToast = ShowToast,
    })
    AdRewardActions.Init({
        AdRewardSystem = AdRewardSystem,
        EconomyCloudSystem = EconomyCloudSystem,
        SocialGardenSystem = SocialGardenSystem,
        getPlots = function() return plots_ end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedPlot = function() return plots_[selectedPlot_] end,
        showToast = ShowToast,
    })
    CommissionSystem.Init(GameConfig, InventorySystem, {
        allowLocalMutations = false,
        showToast = ShowToast,
        getPlayerLevel = function()
            return TalentSystem.GetLevel()
        end,
        requestServerRefresh = function()
            return EconomyCloudSystem.RequestCommissions()
        end,
        onRefresh = function()
            print("[委托] 新委托已刷新")
        end,
    })
    SeedPackOpeningController.Init({
        plants = PLANTS,
        EconomyCloudSystem = EconomyCloudSystem,
        rarityOrder = RARITY_ORDER,
        countSeedPacks = CountSeedPacks,
        showToast = ShowToast,
        markDirty = MarkSaveDirty,
        refreshUI = RefreshUI,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    UiBindings.InitSeedPackView()

    UiBindings.InitTaskView()

    UiBindings.InitActivityView()

    UiBindings.InitSocialView()

    UiBindings.InitModelPreviewView()

    UiBindings.InitCommissionView()

    UiBindings.InitPlantPanelView()

    UiBindings.InitBagDetailView()

    UiBindings.InitBulkSellView()

    UiBindings.InitCodexView()

    UiBindings.InitMainView()

    PlayerSystem.Init({
        onChanged = function()
            initialPlayerReady_ = PlayerSystem.GetUserId() ~= nil
            MarkSaveDirty()
            if ProfileView.IsOpen() then
                ProfileView.RebuildProfileContent()
            end
            if initialPlayerReady_ then
                EnsureInitialUiReady()
                if SocialGardenSystem ~= nil then SocialGardenSystem.UploadSnapshot() end
            end
            if RebuildUI ~= nil then
                RebuildUI()
            else
                RefreshUI(true)
            end
        end,
    })

    UiBindings.InitProfileView()

    UiBindings.InitSettingsView()

    TalentSystem.Init({
        allowLocalMutations = false,
        onHarvestExp = function(_exp)
            RefreshUI(true)
        end,
        onLevelUp = function(level, pointGain)
            ProgressionSystem.SetGardenLevel(level)
            local levelUpText = "升级! 等级 " .. level .. " — 获得 " .. (pointGain or 1) .. " 天赋点"
            ShowToast(levelUpText)
            FloatingToast.Show(levelUpText, { fontSize = 22, duration = 2.0, yRatio = 0.29, priority = 10 })
            local plotLabel = UIController.GetLabel("plotLabel")
            if plotLabel ~= nil then
                plotLabel:SetText("LV" .. level)
            end
        end,
        getGold = function()
            return WalletSystem.GetBalance()
        end,
        spendGold = function(_amount)
            ShowToast("金币消耗必须由服务器确认")
            return false
        end,
    })

    UiBindings.InitTalentView()

    ExpansionController.Init({
        ProgressionSystem = ProgressionSystem,
        TalentSystem = TalentSystem,
        WalletSystem = WalletSystem,
        setUnlockedPlotCount = function(count) unlockedPlotCount_ = count end,
        setSelectedPlot = function(plotIndex) selectedPlot_ = plotIndex end,
        isSinglePlotDisplay = function() return PlotDisplayController.IsSingleMode() end,
        setFocusedPlotIndex = function(plotIndex) PlotDisplayController.SetFocusedPlotIndex(plotIndex) end,
        applyUnlockedPlotCount = ApplyUnlockedPlotCount,
        startSinglePlotBounceAnimation = StartSinglePlotBounceAnimation,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshUI = RefreshUI,
        expandPlot = function()
            return EconomyCloudSystem.ExpandPlot()
        end,
    })

    UiBindings.InitExpansionView()

    CropSystem.Init(GameConfig, {
        InventorySystem = InventorySystem,
        PlantVisual = PlantVisual,
        SeedVisual = SeedVisual,
        TalentSystem = TalentSystem,
        ActivitySystem = ActivitySystem,
        showToast = ShowToast,
    })

    -- 初始化商店系统
    Shop.Init({
        serverAuthoritative = true,
        PLANTS = PLANTS,
        getMoney = function() return WalletSystem.GetBalance() end,
        getGardenLevel = GetGardenLevel,
        onBuy = function(_cost, plantIndex, count, seedName, refreshId)
            count = math.max(1, math.floor(tonumber(count or 1) or 1))
            if plantIndex ~= nil and EconomyCloudSystem.BuySeed(plantIndex, nil, count, seedName, refreshId) then
                ShowToast("正在请求服务器购买...")
                return true
            end
            ShowToast("服务器尚未就绪，无法购买")
            return false
        end,
        requestSeedShop = function()
            return EconomyCloudSystem.RequestSeedShop()
        end,
        showToast = ShowToast,
    })

    -- 纯服务器游戏：不从客户端本地存档恢复经济、背包或农场。

    EconomyCloudSystem.Init({
        WalletSystem = WalletSystem,
        InventorySystem = InventorySystem,
        Shop = Shop,
        TalentSystem = TalentSystem,
        ProgressionSystem = ProgressionSystem,
        CommissionSystem = CommissionSystem,
        ActivitySystem = ActivitySystem,
        SocialGardenSystem = SocialGardenSystem,
        getGold = function() return WalletSystem.GetBalance() end,
        getUserId = function() return PlayerSystem.GetUserId() end,
        syncInventoryRefs = SyncInventoryRefs,
        markDirty = MarkSaveDirty,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 6 })
        end,
        onInitialSyncProgress = function(isReady)
            if isReady then EnsureInitialUiReady() end
        end,
        onPlantSeedConfirmed = function(data)
            CompletePlantGuide()
            PlantActionController.ApplyConfirmedPlantSeed(data)
        end,
        onHarvestCropConfirmed = function(data)
            PlantActionController.ApplyConfirmedHarvestCrop(data)
        end,
        onSeedPackOpened = function(data)
            SeedPackOpeningController.ApplyServerOpenResult(data)
        end,
        onActivityDrawResult = function(rewards)
            ActivityView.ShowAlienDrawResult(rewards)
        end,
        onActivityDrawFailed = function()
            ActivityView.CancelAlienDrawPending()
        end,
        onAuthFarmReceived = function(farm)
            if SocialGardenSystem.IsVisitMode() then
                if type(farm) == "table" and type(farm.plots) == "table" then
                    ownFarmPlotsSave_ = farm.plots
                    print("[权威农场] 拜访模式下收到自己的农场数据，已缓存等待返回")
                end
                return
            end
            ApplyAuthoritativeFarmState(farm)
        end,
        onAdRewardGranted = function(data)
            if data ~= nil and data.daily ~= nil then
                SocialGardenSystem.ApplyAdRewardDaily(data.daily)
            end
            if data ~= nil and data.rewardType == "steal_attempts" then
                SocialGardenSystem.RequestSocialState()
            elseif data ~= nil and data.rewardType == "rare_seed_pack" then
                EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "ad_reward" })
            elseif data ~= nil and data.rewardType == "mature_plot" then
                RefreshSelection()
                UIController.RefreshPlantContent()
            end
        end,
        onAdRewardFailed = function(data)
            if data ~= nil and data.daily ~= nil then
                SocialGardenSystem.ApplyAdRewardDaily(data.daily)
            end
        end,
        onClearSaveCompleted = function(success)
            if HandleClearSaveCompleted ~= nil then
                HandleClearSaveCompleted(success)
            end
        end,
        onProgressionApplied = function(_progression)
            local previousUnlocked = unlockedPlotCount_
            unlockedPlotCount_ = ProgressionSystem.GetUnlockedPlotCount()
            ApplyUnlockedPlotCount()
            if initialUiReady_ and unlockedPlotCount_ > previousUnlocked then
                StartSinglePlotBounceAnimation(unlockedPlotCount_)
            end
            RefreshSelection()
            RefreshUI(true)
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshUI = RefreshUI,
    })

    SocialGardenSystem.Init({
        getScene = function() return scene_ end,
        getPlots = function() return plots_ end,
        getPlants = function() return PLANTS end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        getTourValue = function() return ProgressionSystem.GetTourValue() end,
        getBestTourValue = function() return ProgressionSystem.GetBestTourValue() end,
        getUserId = function() return PlayerSystem.GetUserId() end,
        getDisplayName = function() return PlayerSystem.GetDisplayName() end,
        getAvatarProfile = function() return PlayerSystem.GetSelectedAvatarProfile() end,
        addSeedToBag = AddSeedToBag,
        addSeedPack = AddSeedPack,
        enterVisitMode = function(garden)
            BuildVisitPlots(garden)
            if RebuildUI ~= nil then RebuildUI() end
        end,
        enterStealingMode = function(_garden)
            PlotDisplayController.SetDisplayMode("single")
            CameraSystem.EnterPlantView()
            RefreshSelection()
            UpdateCamera()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        exitStealingMode = function(_garden)
            CameraSystem.EnterFarmView()
            PlotDisplayController.SetDisplayMode("all")
            RefreshSelection()
            UpdateCamera()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        returnHome = function()
            RestoreOwnFarm()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        markDirty = MarkSaveDirty,
        applyEconomyState = function(state)
            EconomyCloudSystem.ApplyAuthoritativeState(state)
        end,
    })

    LeaderboardSystem.Init({
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.34, priority = 8 })
        end,
        applyEconomyState = function(state)
            EconomyCloudSystem.ApplyAuthoritativeState(state)
        end,
        getUnlockedAvatarMap = function()
            return PlayerSystem.GetUnlockedAvatarMap()
        end,
        unlockAvatarReward = function(avatarRef)
            return PlayerSystem.UnlockAvatarReward(avatarRef)
        end,
    })

    UiBindings.InitLeaderboardView()

    InteractionSystem.Init(CONFIG, CameraSystem, {
        getCamera = function() return camera_ end,
        getPlots = function() return plots_ end,
        getSelectedPlot = function() return plots_[selectedPlot_] end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedSeedIndex = function() return selectedSeed_ end,
        getPlantTab = function() return plantTab_ end,
        setSelectedPlot = function(plotIndex) selectedPlot_ = plotIndex end,
        plotWorldPosition = PlotWorldPosition,
        clampToPlot = ClampToPlot,
        refreshSelection = RefreshSelection,
        refreshUI = RefreshUI,
        showToast = ShowToast,
        performPlotAction = function(plotIndex, localPos)
            if SocialGardenSystem.IsVisitMode() then
                if SocialGardenSystem.IsStealingMode() then
                    SocialGardenSystem.RequestStealAtLocalPosition(localPos)
                else
                    ShowToast("点击偷菜按钮后，再选择成熟作物")
                end
            else
                PerformPlotAction(plotIndex, localPos)
            end
        end,
        selectPlotByDelta = SelectPlotByDelta,
        cycleSeed = CycleSeed,
        buySelectedSeed = BuySelectedSeed,
        sellAllHarvested = SellAllHarvested,
        enterPlantView = EnterPlantView,
        countMaturePlants = CountMaturePlants,
        countPlotPlants = CountPlotPlants,
        findPlantAtLocalPosition = FindPlantAtLocalPosition,
        harvestNearestMature = HarvestNearestMature,
        plantSeed = PlantSeed,
        isUIBlocking = function()
            return SocialView.IsOpen() or LeaderboardView.IsOpen() or ModelPreviewSystem.IsOpen() or ActivityView.IsOpen() or ProfileView.IsOpen() or SettingsView.IsOpen() or Shop.IsOpen() or CommissionView.IsOpen() or ExpansionView.IsOpen() or TalentView.IsOpen() or BulkSellView.IsOpen() or CodexView.IsOpen()
        end,
    })

    EconomyCloudSystem.RequestState()
    EconomyCloudSystem.RequestAuthFarm()
    NetworkRecovery.ResetConnectionState()
    EnsureInitialUiReady()

    RefreshSelection()
    UpdateCamera()
    CreateSkybox()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ServerReady", "HandleNetworkRecoveryServerReady")
    SubscribeToEvent("ServerDisconnected", "HandleNetworkRecoveryServerDisconnected")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SampleInitMouseMode(MM_FREE)

    -- BGM 随机列表循环播放
    InitBGM()

    print("=== Grow A Garden 核心玩法原型启动 ===")
end

function Stop()
    UnsubscribeUIEvents()
    SocialView.Shutdown()
    if SocialGardenSystem.IsVisitMode() then
        SocialGardenSystem.ReturnHome()
    end
    SaveGameNow()
    UI.Shutdown()
end
