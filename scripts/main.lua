require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local ModalRegistry = require("ui.modal_registry")
local Shop = require("shop")
local SeedVisual = require("visuals.seed_visual")
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
local GameLoop = require("runtime.game_loop")
local ClientBootstrap = require("runtime.client_bootstrap")
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
local lastEnterPlantAuthFarmRequestAt_ = 0
local ENTER_PLANT_AUTH_FARM_COOLDOWN = 30
local initialUiReady_ = false
local initialUiBuildPending_ = false
local initialPlayerReady_ = false
local initialSocialSnapshotUploaded_ = false
local initialPlotBounceStarted_ = false
local selectedBagItem_ = nil
local ViewMode = CameraSystem.ViewMode
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local plantTab_ = "seed"  -- "seed" | "harvest" | "bag"
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
    -- 纯服务器游戏：权威数据由 serverCloud 保存；保留空实现以兼容现有 deps 注入。
end

function SaveGameNow()
    -- 纯服务器游戏：Stop 时不再写本地存档。
    return true
end

function ClearGameSave()
    local requested = EconomyCloudSystem.ClearSave()
    if not requested and ShowToast ~= nil then
        ShowToast("服务器尚未就绪，无法清除存档")
    end
    saveDisabled_ = true
    return requested
end

function ResetSaveFromLoading()
    local requested = EconomyCloudSystem.ClearSave({ reopenSave = true })
    if not requested then
        if ShowToast ~= nil then ShowToast("服务器尚未就绪，无法重开存档") end
        return false
    end
    saveDisabled_ = true
    return true
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
        local now = os and os.time and os.time() or 0
        if now - lastEnterPlantAuthFarmRequestAt_ >= ENTER_PLANT_AUTH_FARM_COOLDOWN then
            lastEnterPlantAuthFarmRequestAt_ = now
            print(string.format("[种植模式] 进入前后台请求权威农场刷新 plot=%d", selectedPlot_))
            EconomyCloudSystem.RequestAuthFarm({ reason = "enter_plant_view", background = true })
        else
            print(string.format("[种植模式] 跳过进入前权威刷新 plot=%d cooldown=%ds", selectedPlot_, ENTER_PLANT_AUTH_FARM_COOLDOWN - (now - lastEnterPlantAuthFarmRequestAt_)))
        end
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

function FlushPendingRebuildUI(dt)
    UiRuntime.FlushPendingRebuild(dt)
end

HandleClearSaveCompleted = function(success)
    SettingsView.HandleClearSaveCompleted(success)
    if UIController ~= nil and UIController.HandleResetSaveCompleted ~= nil then
        UIController.HandleResetSaveCompleted(success)
    end
    if not success then return end

    if PlayerSystem ~= nil and PlayerSystem.ClearSave ~= nil then
        PlayerSystem.ClearSave()
    end

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

function HandleNetworkRecoveryServerConnected(eventType, eventData)
    NetworkRecovery.HandleServerConnected()
end

function HandleNetworkRecoveryNetworkReconnecting(eventType, eventData)
    NetworkRecovery.HandleNetworkReconnecting()
end

function HandleNetworkRecoveryNetworkReconnected(eventType, eventData)
    NetworkRecovery.HandleNetworkReconnected()
end

function HandleNetworkRecoveryConnectFailed(eventType, eventData)
    NetworkRecovery.HandleConnectFailed()
end

function HandleNetworkRecoveryTransportConnected(eventType, eventData)
    NetworkRecovery.HandleTransportConnected(eventData)
end

function HandleNetworkRecoveryTransportDisconnected(eventType, eventData)
    NetworkRecovery.HandleTransportDisconnected(eventData)
end

function HandleNetworkRecoveryTransportConnectFailed(eventType, eventData)
    NetworkRecovery.HandleTransportConnectFailed(eventData)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    GameLoop.HandleUpdate(eventType, eventData)
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
    ClientBootstrap.Start({
        SampleStart = SampleStart,
        UiEventBindings = UiEventBindings,
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
        RegisterModalGuards = RegisterModalGuards,
        RefreshUI = RefreshUI,
        RebuildUI = RebuildUI,
        CONFIG = CONFIG,
        GameConfig = GameConfig,
        UiRuntime = UiRuntime,
        NetworkRecovery = NetworkRecovery,
        FarmRuntime = FarmRuntime,
        InitMaterials = InitMaterials,
        FarmSystem = FarmSystem,
        materials_ = materials_,
        CreateScene = CreateScene,
        CropSystem = CropSystem,
        ProgressionSystem = ProgressionSystem,
        PlotDisplayController = PlotDisplayController,
        PlotBounceAnimator = PlotBounceAnimator,
        CameraSystem = CameraSystem,
        RefreshSelection = RefreshSelection,
        UpdateCamera = UpdateCamera,
        UpdateCameraTargetForPlotDisplay = UpdateCameraTargetForPlotDisplay,
        MarkSaveDirty = MarkSaveDirty,
        ShowToast = ShowToast,
        CreateFarm = CreateFarm,
        PlantActionController = PlantActionController,
        PLANTS = PLANTS,
        InventorySystem = InventorySystem,
        WalletSystem = WalletSystem,
        TalentSystem = TalentSystem,
        ActivitySystem = ActivitySystem,
        EconomyCloudSystem = EconomyCloudSystem,
        UiBindings = UiBindings,
        RARITY_ORDER = RARITY_ORDER,
        SEED_PACK_CONFIG = SEED_PACK_CONFIG,
        DAILY_TASK_CONFIG = DAILY_TASK_CONFIG,
        ViewMode = ViewMode,
        PlayerSystem = PlayerSystem,
        LeaderboardSystem = LeaderboardSystem,
        SeedPackOpeningController = SeedPackOpeningController,
        FloatingToast = FloatingToast,
        SetSelectedSeedIndex = SetSelectedSeedIndex,
        CountSeedPacks = CountSeedPacks,
        CountMaturePlants = CountMaturePlants,
        CountPlotPlants = CountPlotPlants,
        HarvestNearestMature = HarvestNearestMature,
        OpenBagItemDetail = OpenBagItemDetail,
        CloseBagItemDetail = CloseBagItemDetail,
        SellBagItem = SellBagItem,
        SellHarvestedByFilter = SellHarvestedByFilter,
        BuildSeedPackOverlay = BuildSeedPackOverlay,
        BuildSeedPackOpeningOverlay = BuildSeedPackOpeningOverlay,
        CreateBagPreview = CreateBagPreview,
        GetUiRarityColor = GetUiRarityColor,
        CountPackResults = CountPackResults,
        GetFirstAvailablePackId = GetFirstAvailablePackId,
        OpenSeedPack = OpenSeedPack,
        OpenAllSeedPacks = OpenAllSeedPacks,
        RequestRareSeedPackAdReward = RequestRareSeedPackAdReward,
        RequestSuppressWorldTap = RequestSuppressWorldTap,
        RequestStealAttemptsAdReward = RequestStealAttemptsAdReward,
        FlushPendingRebuildUI = FlushPendingRebuildUI,
        AreAllDailyTasksCompleted = AreAllDailyTasksCompleted,
        EnterPlantView = EnterPlantView,
        EnterFarmView = EnterFarmView,
        OpenCommissionPanel = OpenCommissionPanel,
        OpenSeedPackHub = OpenSeedPackHub,
        OpenTaskPanel = OpenTaskPanel,
        GetHighestPackIcon = GetHighestPackIcon,
        ClearBagPreview = ClearBagPreview,
        GetPlantGuideStep = GetPlantGuideStep,
        RequestMaturePlotAdReward = RequestMaturePlotAdReward,
        ClearGameSave = ClearGameSave,
        ResetSaveFromLoading = ResetSaveFromLoading,
        ZoomPlantView = ZoomPlantView,
        SetPlotDisplayMode = SetPlotDisplayMode,
        SwitchNextFocusedPlot = SwitchNextFocusedPlot,
        SubscribeUIEvents = SubscribeUIEvents,
        PlotWorldPosition = PlotWorldPosition,
        StartSinglePlotBounceAnimation = StartSinglePlotBounceAnimation,
        ApplyUnlockedPlotCount = ApplyUnlockedPlotCount,
        SeedPackSystem = SeedPackSystem,
        AdRewardSystem = AdRewardSystem,
        AdRewardActions = AdRewardActions,
        CommissionSystem = CommissionSystem,
        ExpansionController = ExpansionController,
        PlantVisual = PlantVisual,
        SeedVisual = SeedVisual,
        GetGardenLevel = GetGardenLevel,
        SyncInventoryRefs = SyncInventoryRefs,
        CompletePlantGuide = CompletePlantGuide,
        ApplyAuthoritativeFarmState = ApplyAuthoritativeFarmState,
        AddSeedToBag = AddSeedToBag,
        AddSeedPack = AddSeedPack,
        BuildVisitPlots = BuildVisitPlots,
        RestoreOwnFarm = RestoreOwnFarm,
        HandleClearSaveCompleted = HandleClearSaveCompleted,
        SocialGardenSystem = SocialGardenSystem,
        InteractionSystem = InteractionSystem,
        ClampToPlot = ClampToPlot,
        PerformPlotAction = PerformPlotAction,
        SelectPlotByDelta = SelectPlotByDelta,
        CycleSeed = CycleSeed,
        BuySelectedSeed = BuySelectedSeed,
        SellAllHarvested = SellAllHarvested,
        PlantSeed = PlantSeed,
        GetViewMode = GetViewMode,
        FindPlantAtLocalPosition = FindPlantAtLocalPosition,
        GameLoop = GameLoop,
        AudioSystem = AudioSystem,
        UpdateNetworkRecovery = UpdateNetworkRecovery,
        RequestNetworkRecoverySync = RequestNetworkRecoverySync,
        RetryLoading = function()
            if EconomyCloudSystem ~= nil and EconomyCloudSystem.RetryInitialSync ~= nil then
                EconomyCloudSystem.RetryInitialSync("loading_retry")
            end
            if UIController ~= nil and UIController.ShowLoading ~= nil then
                UIController.ShowLoading("正在重新同步存档...")
            end
            if NetworkRecovery ~= nil and NetworkRecovery.RetryNow ~= nil then
                return NetworkRecovery.RetryNow()
            end
            return true
        end,
        EnsureInitialUiReady = EnsureInitialUiReady,
        HandleInput = HandleInput,
        UpdateTouchCameraGesture = UpdateTouchCameraGesture,
        UpdatePlotBounceAnimation = UpdatePlotBounceAnimation,
        UpdatePlants = UpdatePlants,
        UpdateSeedPackOpening = UpdateSeedPackOpening,
        CreateSkybox = CreateSkybox,
        SampleInitMouseMode = SampleInitMouseMode,
        InitBGM = InitBGM,
        PlantPanelView = PlantPanelView,
        BagDetailView = BagDetailView,
        MainView = MainView,
        ModelPreviewView = ModelPreviewView,
        getScene = function() return scene_ end,
        getCamera = function() return camera_ end,
        getCameraNode = function() return cameraNode_ end,
        getPlots = function() return plots_ end,
        setPlots = function(value) plots_ = value end,
        getOwnFarmPlotsSave = function() return ownFarmPlotsSave_ end,
        setOwnFarmPlotsSave = function(value) ownFarmPlotsSave_ = value end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        setUnlockedPlotCount = function(value) unlockedPlotCount_ = value end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedPlotObject = function() return plots_[selectedPlot_] end,
        setSelectedPlot = function(value) selectedPlot_ = value end,
        getSelectedSeed = function() return selectedSeed_ end,
        setSelectedSeed = function(value) selectedSeed_ = value end,
        getSelectedBagItem = function() return selectedBagItem_ end,
        setSelectedBagItem = function(value) selectedBagItem_ = value end,
        clearSelectedBagItem = function() selectedBagItem_ = nil end,
        getPlantTab = function() return plantTab_ end,
        setPlantTab = function(value) plantTab_ = value end,
        getTaskModal = function() return taskModal_ end,
        setTaskModal = function(value) taskModal_ = value end,
        getSeedBag = function() return seedBag_ end,
        getHarvested = function() return harvested_ end,
        getSeedPacks = function() return seedPacks_ end,
        getCollectedPlants = function() return collectedPlants_ end,
        getCodexStats = function() return codexStats_ end,
        getDailyTaskState = function() return dailyTaskState_ end,
        setSaveDisabled = function(value) saveDisabled_ = value end,
        setInitialUiReady = function(value) initialUiReady_ = value end,
        isInitialUiReady = function() return initialUiReady_ end,
        setInitialUiBuildPending = function(value) initialUiBuildPending_ = value end,
        isInitialUiBuildPending = function() return initialUiBuildPending_ end,
        setInitialPlayerReady = function(value) initialPlayerReady_ = value end,
        isInitialPlayerReady = function() return initialPlayerReady_ end,
        setInitialSocialSnapshotUploaded = function(value) initialSocialSnapshotUploaded_ = value end,
        isInitialSocialSnapshotUploaded = function() return initialSocialSnapshotUploaded_ end,
        setInitialPlotBounceStarted = function(value) initialPlotBounceStarted_ = value end,
        isInitialPlotBounceStarted = function() return initialPlotBounceStarted_ end,
        setPendingRebuildUI = function(value) pendingRebuildUI_ = value end,
        isPendingRebuildUI = function() return pendingRebuildUI_ end,
    })
end
function Stop()
    UnsubscribeUIEvents()
    SocialView.Shutdown()
    if SocialGardenSystem.IsVisitMode() then
        SocialGardenSystem.ReturnHome()
    end
    SocialGardenSystem.UploadSnapshot()
    UI.Shutdown()
end
