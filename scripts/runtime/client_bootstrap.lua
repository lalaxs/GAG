-- ============================================================================
-- 客户端启动引导 (Client Bootstrap)
-- Grow A Garden
-- ============================================================================

local ClientBootstrap = {}

local NetworkClient = require("client.network_client")

function ClientBootstrap.Start(ctx)
    ctx.SampleStart()
    ctx.UiEventBindings.Init({
        EventBus = ctx.EventBus,
        UIEvents = ctx.UIEvents,
        ModalRegistry = ctx.ModalRegistry,
        UIController = ctx.UIController,
        SocialView = ctx.SocialView,
        LeaderboardView = ctx.LeaderboardView,
        SeedPackView = ctx.SeedPackView,
        TaskView = ctx.TaskView,
        ModelPreviewSystem = ctx.ModelPreviewSystem,
        ActivityView = ctx.ActivityView,
        ProfileView = ctx.ProfileView,
        SettingsView = ctx.SettingsView,
        Shop = ctx.Shop,
        CommissionView = ctx.CommissionView,
        ExpansionView = ctx.ExpansionView,
        TalentView = ctx.TalentView,
        BulkSellView = ctx.BulkSellView,
        CodexView = ctx.CodexView,
        refreshUI = ctx.RefreshUI,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
    })
    ctx.RegisterModalGuards()
    graphics.windowTitle = ctx.CONFIG.Title
    math.randomseed(os.time())
    ctx.setSaveDisabled(true)
    ctx.setInitialUiReady(false)
    ctx.setInitialUiBuildPending(false)
    ctx.setInitialPlayerReady(false)
    ctx.setInitialSocialSnapshotUploaded(false)
    ctx.setInitialPlotBounceStarted(false)
    ctx.UiRuntime.Init({
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        UIController = ctx.UIController,
        ModalRegistry = ctx.ModalRegistry,
        PlotBounceAnimator = ctx.PlotBounceAnimator,
        SocialGardenSystem = ctx.SocialGardenSystem,
        getPlots = ctx.getPlots,
        showInitialFarm = function() ctx.FarmRuntime.ShowInitialFarm() end,
        isInitialUiReady = ctx.isInitialUiReady,
        setInitialUiReady = ctx.setInitialUiReady,
        setInitialUiBuildPending = ctx.setInitialUiBuildPending,
        isPendingRebuildUI = ctx.isPendingRebuildUI,
        setPendingRebuildUI = ctx.setPendingRebuildUI,
        isInitialPlotBounceStarted = ctx.isInitialPlotBounceStarted,
        setInitialPlotBounceStarted = ctx.setInitialPlotBounceStarted,
        isInitialSocialSnapshotUploaded = ctx.isInitialSocialSnapshotUploaded,
        setInitialSocialSnapshotUploaded = ctx.setInitialSocialSnapshotUploaded,
        showToast = ctx.ShowToast,
        initBGM = ctx.InitBGM,
    })
    ctx.NetworkRecovery.Init({
        SocialGardenSystem = ctx.SocialGardenSystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        showToast = ctx.ShowToast,
        getScene = ctx.getScene,
    })
    ctx.NetworkRecovery.ResetLoadingState()
    ctx.UIController.ShowLoading("正在同步服务器数据...")

    ctx.InitMaterials()
    ctx.FarmSystem.Init(ctx.CONFIG, ctx.materials_)
    ctx.CreateScene()
    ctx.FarmRuntime.Init({
        FarmSystem = ctx.FarmSystem,
        CropSystem = ctx.CropSystem,
        ProgressionSystem = ctx.ProgressionSystem,
        PlotDisplayController = ctx.PlotDisplayController,
        PlotBounceAnimator = ctx.PlotBounceAnimator,
        CameraSystem = ctx.CameraSystem,
        getScene = ctx.getScene,
        getPlots = ctx.getPlots,
        setPlots = ctx.setPlots,
        getOwnFarmPlotsSave = ctx.getOwnFarmPlotsSave,
        setOwnFarmPlotsSave = ctx.setOwnFarmPlotsSave,
        getUnlockedPlotCount = ctx.getUnlockedPlotCount,
        setUnlockedPlotCount = ctx.setUnlockedPlotCount,
        getSelectedPlot = ctx.getSelectedPlotIndex,
        setSelectedPlot = ctx.setSelectedPlot,
        refreshSelection = ctx.RefreshSelection,
        updateCamera = ctx.UpdateCamera,
        updateCameraTargetForPlotDisplay = ctx.UpdateCameraTargetForPlotDisplay,
        isInitialUiReady = ctx.isInitialUiReady,
        setInitialPlotBounceStarted = ctx.setInitialPlotBounceStarted,
        markSaveDirty = ctx.MarkSaveDirty,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        refreshUI = ctx.RefreshUI,
    })
    ctx.ModelPreviewSystem.Init(ctx.GameConfig, {
        scene = ctx.getScene(),
        cameraNode = ctx.getCameraNode(),
        PlantVisual = ctx.PlantVisual,
    })
    ctx.ProgressionSystem.Init(ctx.CONFIG)
    ctx.setUnlockedPlotCount(ctx.ProgressionSystem.GetUnlockedPlotCount())
    ctx.CreateFarm()
    ctx.PlantActionController.Init({
        config = ctx.CONFIG,
        plants = ctx.PLANTS,
        seedBag = ctx.getSeedBag(),
        CropSystem = ctx.CropSystem,
        InventorySystem = ctx.InventorySystem,
        WalletSystem = ctx.WalletSystem,
        TalentSystem = ctx.TalentSystem,
        ActivitySystem = ctx.ActivitySystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        getPlots = ctx.getPlots,
        getSelectedPlot = ctx.getSelectedPlotIndex,
        setSelectedPlot = ctx.setSelectedPlot,
        getSelectedSeed = ctx.getSelectedSeed,
        setSelectedSeed = ctx.setSelectedSeed,
        setSelectedBagItem = ctx.setSelectedBagItem,
        getPlantTab = ctx.getPlantTab,
        isPlantView = function() return ctx.GetViewMode() == ctx.ViewMode.PLANT end,
        addSeedToBag = ctx.AddSeedToBag,
        clearBagPreview = ctx.ClearBagPreview,
        markDirty = ctx.MarkSaveDirty,
        refreshSelection = ctx.RefreshSelection,
        refreshUI = ctx.RefreshUI,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        showToast = ctx.ShowToast,
        countPlotPlants = ctx.CountPlotPlants,
        countMaturePlants = ctx.CountMaturePlants,
        findPlantAtLocalPosition = ctx.FindPlantAtLocalPosition,
        refreshTourValue = ctx.UpdateCurrentTourValue,
    })

    ctx.UiBindings.Init({
        CONFIG = ctx.CONFIG,
        GameConfig = ctx.GameConfig,
        PLANTS = ctx.PLANTS,
        RARITY_ORDER = ctx.RARITY_ORDER,
        SEED_PACK_CONFIG = ctx.SEED_PACK_CONFIG,
        DAILY_TASK_CONFIG = ctx.DAILY_TASK_CONFIG,
        ViewMode = ctx.ViewMode,
        UIController = ctx.UIController,
        SeedPackView = ctx.SeedPackView,
        TaskView = ctx.TaskView,
        ActivityView = ctx.ActivityView,
        SocialView = ctx.SocialView,
        ModelPreviewView = ctx.ModelPreviewView,
        CommissionView = ctx.CommissionView,
        PlantPanelView = ctx.PlantPanelView,
        BagDetailView = ctx.BagDetailView,
        BulkSellView = ctx.BulkSellView,
        CodexView = ctx.CodexView,
        MainView = ctx.MainView,
        ProfileView = ctx.ProfileView,
        SettingsView = ctx.SettingsView,
        TalentView = ctx.TalentView,
        ExpansionView = ctx.ExpansionView,
        LeaderboardView = ctx.LeaderboardView,
        Shop = ctx.Shop,
        PlayerSystem = ctx.PlayerSystem,
        LeaderboardSystem = ctx.LeaderboardSystem,
        PlotDisplayController = ctx.PlotDisplayController,
        ActivitySystem = ctx.ActivitySystem,
        ModelPreviewSystem = ctx.ModelPreviewSystem,
        CommissionSystem = ctx.CommissionSystem,
        CameraSystem = ctx.CameraSystem,
        WalletSystem = ctx.WalletSystem,
        ProgressionSystem = ctx.ProgressionSystem,
        TalentSystem = ctx.TalentSystem,
        SocialGardenSystem = ctx.SocialGardenSystem,
        SeedPackOpeningController = ctx.SeedPackOpeningController,
        InventorySystem = ctx.InventorySystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        FloatingToast = ctx.FloatingToast,
        EventBus = ctx.EventBus,
        UIEvents = ctx.UIEvents,
        getSeedBag = ctx.getSeedBag,
        getHarvested = ctx.getHarvested,
        getSeedPacks = ctx.getSeedPacks,
        getCollectedPlants = ctx.getCollectedPlants,
        getCodexStats = ctx.getCodexStats,
        getDailyTaskState = ctx.getDailyTaskState,
        getPlots = ctx.getPlots,
        getSelectedPlotIndex = ctx.getSelectedPlotIndex,
        getSelectedPlot = ctx.getSelectedPlotObject,
        getSelectedSeed = ctx.getSelectedSeed,
        setSelectedSeedIndex = ctx.SetSelectedSeedIndex,
        getSelectedBagItem = ctx.getSelectedBagItem,
        getUnlockedPlotCount = ctx.getUnlockedPlotCount,
        getPlantTab = ctx.getPlantTab,
        getViewMode = ctx.GetViewMode,
        countSeedPacks = ctx.CountSeedPacks,
        countMaturePlants = ctx.CountMaturePlants,
        countPlotPlants = ctx.CountPlotPlants,
        harvestNearestMature = ctx.HarvestNearestMature,
        openBagItemDetail = ctx.OpenBagItemDetail,
        closeBagItemDetail = ctx.CloseBagItemDetail,
        sellBagItem = ctx.SellBagItem,
        sellHarvestedByFilter = ctx.SellHarvestedByFilter,
        buildSeedPackOverlay = ctx.BuildSeedPackOverlay,
        buildSeedPackOpeningOverlay = ctx.BuildSeedPackOpeningOverlay,
        createBagPreview = ctx.CreateBagPreview,
        getUiRarityColor = ctx.GetUiRarityColor,
        countPackResults = ctx.CountPackResults,
        getFirstAvailablePackId = ctx.GetFirstAvailablePackId,
        openSeedPack = ctx.OpenSeedPack,
        openAllSeedPacks = ctx.OpenAllSeedPacks,
        requestRareSeedPackAdReward = ctx.RequestRareSeedPackAdReward,
        suppressWorldTap = ctx.RequestSuppressWorldTap,
        requestStealAttemptsAdReward = ctx.RequestStealAttemptsAdReward,
        flushPendingRebuildUI = ctx.FlushPendingRebuildUI,
        updateCameraTargetForPlotDisplay = ctx.UpdateCameraTargetForPlotDisplay,
        refreshUI = ctx.RefreshUI,
        showToast = ctx.ShowToast,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        getTaskModal = ctx.getTaskModal,
        setTaskModal = ctx.setTaskModal,
        areAllDailyTasksCompleted = ctx.AreAllDailyTasksCompleted,
        setPlantTab = ctx.setPlantTab,
        enterPlantView = ctx.EnterPlantView,
        enterFarmView = ctx.EnterFarmView,
        openCommissionPanel = ctx.OpenCommissionPanel,
        openSeedPackHub = ctx.OpenSeedPackHub,
        openTaskPanel = ctx.OpenTaskPanel,
        getHighestPackIcon = ctx.GetHighestPackIcon,
        clearSelectedBagItem = ctx.clearSelectedBagItem,
        clearBagPreview = function()
            if ctx.ClearBagPreview ~= nil then ctx.ClearBagPreview() end
        end,
        getPlantGuideStep = ctx.GetPlantGuideStep,
        requestMaturePlotAdReward = ctx.RequestMaturePlotAdReward,
        clearGameSave = ctx.ClearGameSave,
        zoomPlantView = ctx.ZoomPlantView,
        setPlotDisplayMode = ctx.SetPlotDisplayMode,
        switchNextFocusedPlot = ctx.SwitchNextFocusedPlot,
        markSaveDirty = ctx.MarkSaveDirty,
    })
    ctx.UiBindings.InitUIController()
    ctx.SubscribeUIEvents()
    ctx.PlotDisplayController.Init({
        config = ctx.CONFIG,
        ViewMode = ctx.ViewMode,
        getViewMode = ctx.GetViewMode,
        getPlots = ctx.getPlots,
        getSelectedPlot = ctx.getSelectedPlotIndex,
        setSelectedPlot = ctx.setSelectedPlot,
        getUnlockedPlotCount = ctx.getUnlockedPlotCount,
        plotWorldPosition = ctx.PlotWorldPosition,
        setCameraTarget = function(position) ctx.CameraSystem.SetTarget(position) end,
        refreshFarmSelection = function(plots, selectedPlot) ctx.FarmSystem.RefreshSelection(plots, selectedPlot) end,
        applyUnlockedPlotCount = function(plots, unlockedPlotCount) ctx.FarmSystem.ApplyUnlockedPlotCount(plots, unlockedPlotCount) end,
        isPlotBounceActive = function() return ctx.PlotBounceAnimator.IsActive() end,
        startSinglePlotBounceAnimation = ctx.StartSinglePlotBounceAnimation,
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        refreshUI = ctx.RefreshUI,
    })
    ctx.ApplyUnlockedPlotCount()

    ctx.WalletSystem.Init(ctx.CONFIG.StartMoney)
    ctx.InventorySystem.Init(ctx.GameConfig, {
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 5 })
        end,
        getHarvestBagBonus = function()
            return ctx.TalentSystem.GetBonus("bagCapacity")
        end,
    })

    ctx.SeedPackSystem.Init(ctx.GameConfig, ctx.InventorySystem)
    ctx.ActivitySystem.Init(ctx.GameConfig, ctx.InventorySystem, {
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 5 })
        end,
    })
    ctx.AdRewardSystem.Init({
        showToast = ctx.ShowToast,
    })
    ctx.AdRewardActions.Init({
        AdRewardSystem = ctx.AdRewardSystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        SocialGardenSystem = ctx.SocialGardenSystem,
        getPlots = ctx.getPlots,
        getSelectedPlotIndex = ctx.getSelectedPlotIndex,
        getSelectedPlot = ctx.getSelectedPlotObject,
        showToast = ctx.ShowToast,
    })
    ctx.CommissionSystem.Init(ctx.GameConfig, ctx.InventorySystem, {
        showToast = ctx.ShowToast,
        getPlayerLevel = function()
            return ctx.TalentSystem.GetLevel()
        end,
        requestServerRefresh = function()
            return ctx.EconomyCloudSystem.RequestCommissions()
        end,
        onRefresh = function()
            print("[委托] 新委托已刷新")
        end,
    })
    ctx.SeedPackOpeningController.Init({
        plants = ctx.PLANTS,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        rarityOrder = ctx.RARITY_ORDER,
        countSeedPacks = ctx.CountSeedPacks,
        showToast = ctx.ShowToast,
        markDirty = ctx.MarkSaveDirty,
        refreshUI = ctx.RefreshUI,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
    })

    ctx.UiBindings.InitSeedPackView()

    ctx.UiBindings.InitTaskView()

    ctx.UiBindings.InitActivityView()

    ctx.UiBindings.InitSocialView()

    ctx.UiBindings.InitModelPreviewView()

    ctx.UiBindings.InitCommissionView()

    ctx.UiBindings.InitPlantPanelView()

    ctx.UiBindings.InitBagDetailView()

    ctx.UiBindings.InitBulkSellView()

    ctx.UiBindings.InitCodexView()

    ctx.UiBindings.InitMainView()

    ctx.PlayerSystem.Init({
        onChanged = function()
            ctx.setInitialPlayerReady(ctx.PlayerSystem.GetUserId() ~= nil)
            ctx.MarkSaveDirty()
            if ctx.ProfileView.IsOpen() then
                ctx.ProfileView.RebuildProfileContent()
            end
            if ctx.isInitialPlayerReady() then
                ctx.EnsureInitialUiReady()
                if ctx.SocialGardenSystem ~= nil then ctx.SocialGardenSystem.UploadSnapshot() end
            end
            if ctx.RebuildUI ~= nil then
                ctx.RebuildUI()
            else
                ctx.RefreshUI(true)
            end
        end,
    })

    ctx.UiBindings.InitProfileView()

    ctx.UiBindings.InitSettingsView()

    ctx.TalentSystem.Init({
        onHarvestExp = function(_exp)
            ctx.RefreshUI(true)
        end,
        onLevelUp = function(level, pointGain)
            ctx.ProgressionSystem.SetGardenLevel(level)
            local levelUpText = "升级! 等级 " .. level .. " — 获得 " .. (pointGain or 1) .. " 天赋点"
            ctx.ShowToast(levelUpText)
            ctx.FloatingToast.Show(levelUpText, { fontSize = 22, duration = 2.0, yRatio = 0.29, priority = 10 })
            local plotLabel = ctx.UIController.GetLabel("plotLabel")
            if plotLabel ~= nil then
                plotLabel:SetText("LV" .. level)
            end
        end,
        getGold = function()
            return ctx.WalletSystem.GetBalance()
        end,
        spendGold = function(_amount)
            ctx.ShowToast("金币消耗必须由服务器确认")
            return false
        end,
    })

    ctx.UiBindings.InitTalentView()

    ctx.ExpansionController.Init({
        ProgressionSystem = ctx.ProgressionSystem,
        TalentSystem = ctx.TalentSystem,
        WalletSystem = ctx.WalletSystem,
        setUnlockedPlotCount = ctx.setUnlockedPlotCount,
        setSelectedPlot = ctx.setSelectedPlot,
        isSinglePlotDisplay = function() return ctx.PlotDisplayController.IsSingleMode() end,
        setFocusedPlotIndex = function(plotIndex) ctx.PlotDisplayController.SetFocusedPlotIndex(plotIndex) end,
        applyUnlockedPlotCount = ctx.ApplyUnlockedPlotCount,
        startSinglePlotBounceAnimation = ctx.StartSinglePlotBounceAnimation,
        showToast = ctx.ShowToast,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        refreshUI = ctx.RefreshUI,
        expandPlot = function()
            return ctx.EconomyCloudSystem.ExpandPlot()
        end,
    })

    ctx.UiBindings.InitExpansionView()

    ctx.CropSystem.Init(ctx.GameConfig, {
        InventorySystem = ctx.InventorySystem,
        PlantVisual = ctx.PlantVisual,
        SeedVisual = ctx.SeedVisual,
        TalentSystem = ctx.TalentSystem,
        ActivitySystem = ctx.ActivitySystem,
        showToast = ctx.ShowToast,
    })

    -- 初始化商店系统
    ctx.Shop.Init({
        serverAuthoritative = true,
        PLANTS = ctx.PLANTS,
        getMoney = function() return ctx.WalletSystem.GetBalance() end,
        getGardenLevel = ctx.GetGardenLevel,
        onBuy = function(_cost, plantIndex, count, seedName, refreshId)
            count = math.max(1, math.floor(tonumber(count or 1) or 1))
            if plantIndex ~= nil and ctx.EconomyCloudSystem.BuySeed(plantIndex, nil, count, seedName, refreshId) then
                ctx.ShowToast("正在请求服务器购买...")
                return true
            end
            ctx.ShowToast("服务器尚未就绪，无法购买")
            return false
        end,
        requestSeedShop = function()
            return ctx.EconomyCloudSystem.RequestSeedShop()
        end,
        showToast = ctx.ShowToast,
    })

    -- 纯服务器游戏：不从客户端本地存档恢复经济、背包或农场。

    ctx.EconomyCloudSystem.Init({
        WalletSystem = ctx.WalletSystem,
        InventorySystem = ctx.InventorySystem,
        Shop = ctx.Shop,
        TalentSystem = ctx.TalentSystem,
        ProgressionSystem = ctx.ProgressionSystem,
        CommissionSystem = ctx.CommissionSystem,
        ActivitySystem = ctx.ActivitySystem,
        SocialGardenSystem = ctx.SocialGardenSystem,
        getGold = function() return ctx.WalletSystem.GetBalance() end,
        getUserId = function() return ctx.PlayerSystem.GetUserId() end,
        syncInventoryRefs = ctx.SyncInventoryRefs,
        markDirty = ctx.MarkSaveDirty,
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 6 })
        end,
        onInitialSyncProgress = function(isReady)
            if isReady then ctx.EnsureInitialUiReady() end
        end,
        onPlantSeedConfirmed = function(data)
            ctx.CompletePlantGuide()
            ctx.PlantActionController.ApplyConfirmedPlantSeed(data)
        end,
        onHarvestCropConfirmed = function(data)
            ctx.PlantActionController.ApplyConfirmedHarvestCrop(data)
        end,
        onSeedPackOpened = function(data)
            ctx.SeedPackOpeningController.ApplyServerOpenResult(data)
        end,
        onActivityDrawResult = function(rewards)
            ctx.ActivityView.ShowAlienDrawResult(rewards)
        end,
        onActivityDrawFailed = function()
            ctx.ActivityView.CancelAlienDrawPending()
        end,
        onAuthFarmReceived = function(farm)
            if ctx.SocialGardenSystem.IsVisitMode() then
                if type(farm) == "table" and type(farm.plots) == "table" then
                    ctx.setOwnFarmPlotsSave(farm.plots)
                    print("[权威农场] 拜访模式下收到自己的农场数据，已缓存等待返回")
                end
                return
            end
            ctx.ApplyAuthoritativeFarmState(farm)
        end,
        onAdRewardGranted = function(data)
            if data ~= nil and data.daily ~= nil then
                ctx.SocialGardenSystem.ApplyAdRewardDaily(data.daily)
            end
            if data ~= nil and data.rewardType == "steal_attempts" then
                ctx.SocialGardenSystem.RequestSocialState()
            elseif data ~= nil and data.rewardType == "rare_seed_pack" then
                ctx.EventBus.Emit(ctx.UIEvents.SEEDPACK_CHANGED, { reason = "ad_reward" })
            elseif data ~= nil and data.rewardType == "mature_plot" then
                ctx.RefreshSelection()
                ctx.UIController.RefreshPlantContent()
            end
        end,
        onAdRewardFailed = function(data)
            if data ~= nil and data.daily ~= nil then
                ctx.SocialGardenSystem.ApplyAdRewardDaily(data.daily)
            end
        end,
        onClearSaveCompleted = function(success)
            if ctx.HandleClearSaveCompleted ~= nil then
                ctx.HandleClearSaveCompleted(success)
            end
        end,
        onProgressionApplied = function(_progression)
            local previousUnlocked = ctx.getUnlockedPlotCount()
            ctx.setUnlockedPlotCount(ctx.ProgressionSystem.GetUnlockedPlotCount())
            ctx.ApplyUnlockedPlotCount()
            if ctx.isInitialUiReady() and ctx.getUnlockedPlotCount() > previousUnlocked then
                ctx.StartSinglePlotBounceAnimation(ctx.getUnlockedPlotCount())
            end
            ctx.RefreshSelection()
            ctx.RefreshUI(true)
        end,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        refreshUI = ctx.RefreshUI,
    })

    ctx.SocialGardenSystem.Init({
        getScene = ctx.getScene,
        getPlots = ctx.getPlots,
        getPlants = function() return ctx.PLANTS end,
        getUnlockedPlotCount = ctx.getUnlockedPlotCount,
        getTourValue = function() return ctx.ProgressionSystem.GetTourValue() end,
        getBestTourValue = function() return ctx.ProgressionSystem.GetBestTourValue() end,
        getUserId = function() return ctx.PlayerSystem.GetUserId() end,
        getDisplayName = function() return ctx.PlayerSystem.GetDisplayName() end,
        getAvatarProfile = function() return ctx.PlayerSystem.GetSelectedAvatarProfile() end,
        addSeedToBag = ctx.AddSeedToBag,
        addSeedPack = ctx.AddSeedPack,
        enterVisitMode = function(garden)
            if ctx.SocialView ~= nil and ctx.SocialView.IsOpen ~= nil and ctx.SocialView.IsOpen() then
                ctx.SocialView.Close()
            end
            if ctx.LeaderboardView ~= nil and ctx.LeaderboardView.IsOpen ~= nil and ctx.LeaderboardView.IsOpen() then
                ctx.LeaderboardView.Close()
            end
            ctx.BuildVisitPlots(garden)
            if ctx.EnsureInitialUiReady ~= nil then ctx.EnsureInitialUiReady() end
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
            if ctx.FlushPendingRebuildUI ~= nil then ctx.FlushPendingRebuildUI() end
            if ctx.RefreshUI ~= nil then ctx.RefreshUI(true) end
        end,
        enterStealingMode = function(_garden)
            ctx.PlotDisplayController.SetDisplayMode("single")
            ctx.CameraSystem.EnterPlantView()
            ctx.RefreshSelection()
            ctx.UpdateCamera()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        exitStealingMode = function(_garden)
            ctx.CameraSystem.EnterFarmView()
            ctx.PlotDisplayController.SetDisplayMode("all")
            ctx.RefreshSelection()
            ctx.UpdateCamera()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        returnHome = function()
            ctx.RestoreOwnFarm()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = function()
            if ctx.RebuildUI ~= nil then ctx.RebuildUI() end
        end,
        markDirty = ctx.MarkSaveDirty,
        applyEconomyState = function(state)
            ctx.EconomyCloudSystem.ApplyAuthoritativeState(state)
        end,
    })

    NetworkClient.Init({
        SocialGardenSystem = ctx.SocialGardenSystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
    })

    ctx.LeaderboardSystem.Init({
        showToast = ctx.ShowToast,
        showFloatingToast = function(text)
            ctx.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.34, priority = 8 })
        end,
        applyEconomyState = function(state)
            ctx.EconomyCloudSystem.ApplyAuthoritativeState(state)
        end,
        getUnlockedAvatarMap = function()
            return ctx.PlayerSystem.GetUnlockedAvatarMap()
        end,
        unlockAvatarReward = function(avatarRef)
            return ctx.PlayerSystem.UnlockAvatarReward(avatarRef)
        end,
    })

    ctx.UiBindings.InitLeaderboardView()

    ctx.InteractionSystem.Init(ctx.CONFIG, ctx.CameraSystem, {
        getCamera = ctx.getCamera,
        getPlots = ctx.getPlots,
        getSelectedPlot = ctx.getSelectedPlotObject,
        getSelectedPlotIndex = ctx.getSelectedPlotIndex,
        getSelectedSeedIndex = ctx.getSelectedSeed,
        getPlantTab = ctx.getPlantTab,
        setSelectedPlot = ctx.setSelectedPlot,
        plotWorldPosition = ctx.PlotWorldPosition,
        clampToPlot = ctx.ClampToPlot,
        refreshSelection = ctx.RefreshSelection,
        refreshUI = ctx.RefreshUI,
        showToast = ctx.ShowToast,
        performPlotAction = function(plotIndex, localPos)
            if ctx.SocialGardenSystem.IsVisitMode() then
                if ctx.SocialGardenSystem.IsStealingMode() then
                    ctx.SocialGardenSystem.RequestStealAtLocalPosition(localPos)
                else
                    ctx.ShowToast("点击偷菜按钮后，再选择成熟作物")
                end
            else
                ctx.PerformPlotAction(plotIndex, localPos)
            end
        end,
        selectPlotByDelta = ctx.SelectPlotByDelta,
        cycleSeed = ctx.CycleSeed,
        buySelectedSeed = ctx.BuySelectedSeed,
        sellAllHarvested = ctx.SellAllHarvested,
        enterPlantView = ctx.EnterPlantView,
        countMaturePlants = ctx.CountMaturePlants,
        countPlotPlants = ctx.CountPlotPlants,
        findPlantAtLocalPosition = ctx.FindPlantAtLocalPosition,
        harvestNearestMature = ctx.HarvestNearestMature,
        plantSeed = ctx.PlantSeed,
        isUIBlocking = function()
            if ctx.ModalRegistry ~= nil and ctx.ModalRegistry.AnyOpen ~= nil and ctx.ModalRegistry.AnyOpen() then
                return true
            end
            return ctx.SocialView.IsOpen() or ctx.LeaderboardView.IsOpen() or ctx.ModelPreviewSystem.IsOpen() or ctx.ActivityView.IsOpen() or ctx.ProfileView.IsOpen() or ctx.SettingsView.IsOpen() or ctx.Shop.IsOpen() or ctx.CommissionView.IsOpen() or ctx.ExpansionView.IsOpen() or ctx.TalentView.IsOpen() or ctx.BulkSellView.IsOpen() or ctx.CodexView.IsOpen()
        end,
    })

    -- 权威同步由 NetworkRecovery + CLIENT_READY 全量下发触发，不在无连接时预请求。
    ctx.NetworkRecovery.ResetConnectionState()

    ctx.GameLoop.Init({
        updateNetworkRecovery = ctx.UpdateNetworkRecovery,
        isInitialUiReady = ctx.isInitialUiReady,
        PlayerSystem = ctx.PlayerSystem,
        EconomyCloudSystem = ctx.EconomyCloudSystem,
        AdRewardSystem = ctx.AdRewardSystem,
        SocialGardenSystem = ctx.SocialGardenSystem,
        LeaderboardSystem = ctx.LeaderboardSystem,
        NetworkRecovery = ctx.NetworkRecovery,
        UIController = ctx.UIController,
        requestNetworkRecoverySync = ctx.RequestNetworkRecoverySync,
        ensureInitialUiReady = ctx.EnsureInitialUiReady,
        FloatingToast = ctx.FloatingToast,
        AudioSystem = ctx.AudioSystem,
        ModelPreviewSystem = ctx.ModelPreviewSystem,
        handleInput = ctx.HandleInput,
        updateTouchCameraGesture = ctx.UpdateTouchCameraGesture,
        updatePlotBounceAnimation = ctx.UpdatePlotBounceAnimation,
        updatePlants = ctx.UpdatePlants,
        updateSeedPackOpening = ctx.UpdateSeedPackOpening,
        Shop = ctx.Shop,
        CommissionSystem = ctx.CommissionSystem,
        flushPendingRebuildUI = ctx.FlushPendingRebuildUI,
        refreshUI = ctx.RefreshUI,
    })

    ctx.RefreshSelection()
    ctx.UpdateCamera()
    ctx.CreateSkybox()
    if NetworkClient.IsClientMode() then
        ctx.SocialGardenSystem.BindServerConnection(true)
    end
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ServerReady", "HandleNetworkRecoveryServerReady")
    SubscribeToEvent("ServerDisconnected", "HandleNetworkRecoveryServerDisconnected")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    ctx.SampleInitMouseMode(MM_FREE)

    print("[启动] 客户端模块初始化完成，等待服务器权威同步")
end

return ClientBootstrap
