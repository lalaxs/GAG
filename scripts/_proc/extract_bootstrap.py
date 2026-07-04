from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

SERVER_CTX_NAMES = sorted(
    {
        "ServerEventHandlers", "ServerEconomyActions", "ServerEconomyState",
        "SERVER_MUTATION_TALENT_BONUSES", "DEFAULT_HARVEST_BAG_CAPACITY",
        "MAX_HARVEST_BAG_CAPACITY", "BAG_CAPACITY_BONUSES", "ServerGlobals",
        "ServerCommission", "ServerLeaderboard", "ServerCropRules", "ServerFarmState",
        "ServerActivity", "ServerRewards", "ServerSteal", "ServerShop", "SocialServer",
        "GiftServer", "RequestGuard", "InventoryRules", "ServerConfig", "ServerTuning",
        "GameConfig", "Shared", "DeepCopy", "PickGiftSeedId", "SendFullAvailableSeedShop",
        "BroadcastFullAvailableSeedShop", "EnsureSeedShopState", "BuildSeedShopQuotaKey",
        "SendSeedShopState", "GetServerMutationTalentBonus", "GetMaxCropsPerPlot",
        "BuildAuthoritativeCrop", "SyncProgressionTourValueFromFarm",
        "FindFarmCropFromHarvestPayload", "RefreshAuthCrop", "GetHarvestBagCapacityFromState",
        "AddServerHarvestExp", "RollHarvestDropPack", "ApplyActivityHarvestReward",
        "RollSeedFromPack", "IsValidPackId", "IsValidSellMode", "BuildVisitGardenFromAuthFarm",
        "CalculateAuthFarmTourValue", "GetActivityRankInfo", "GetIncomeRankInfo",
        "GetCurrentActivityCycleInfo", "GetPreviousActivityCycleInfo", "GetActivityConfig",
        "GetNicknameMap", "AddActivityRankCommit", "AddTourRankCommit", "AddIncomeRankCommit",
        "BuildInitialEconomyState", "NormalizeEconomyState", "NormalizeFarmState",
        "NormalizeActivityState", "NormalizeTalentState", "NormalizeProgressionState",
        "NormalizeDailyTaskState", "NormalizeUserId", "NormalizePlantIndex",
        "NormalizePlotIndex", "NormalizeLocalPos", "NormalizePositiveCount", "NextRevision",
        "GetFarmPlot", "FindFarmCrop", "SendError", "SendPlayerProfile", "RequestEconomyState",
        "RequestAuthFarmState", "RequestLeaderboardAuthority", "ClaimActivityRankRewardAuthority",
        "RequestSteal", "GrantAdReward", "BuySeed", "ClearPlayerSave", "PlantSeedAuthority",
        "HarvestCropAuthority", "OpenSeedPackAuthority", "SellHarvested",
        "RequestCommissionsAuthority", "CompleteCommissionAuthority",
        "SubmitActivityCropAuthority", "ExchangeActivityRewardAuthority",
        "DrawActivityPackAuthority", "ClaimDailyRewardAuthority", "SynthesizePackAuthority",
        "UnlockTalentAuthority", "ExpandPlotAuthority", "RollWeighted", "RandomRange",
        "RandItem", "CopyNumericKeyMap", "RecalculateAuthoritativeItemPrice",
        "GetConnectionKey", "GetConnectionUserId", "GetRequestUserId", "ReadRequest", "Send", "Now",
    },
    key=len,
    reverse=True,
)

CLIENT_MODULE_NAMES = sorted(
    {
        "UiEventBindings", "UiRuntime", "NetworkRecovery", "FarmRuntime", "ModelPreviewSystem",
        "ProgressionSystem", "PlantActionController", "UiBindings", "PlotDisplayController",
        "WalletSystem", "InventorySystem", "SeedPackSystem", "ActivitySystem", "AdRewardSystem",
        "AdRewardActions", "CommissionSystem", "SeedPackOpeningController", "PlayerSystem",
        "TalentSystem", "ExpansionController", "CropSystem", "Shop", "EconomyCloudSystem",
        "SocialGardenSystem", "LeaderboardSystem", "InteractionSystem", "GameLoop", "UIController",
        "FarmSystem", "CameraSystem", "SceneSystem", "AudioSystem", "FloatingToast", "EventBus",
        "UIEvents", "ModalRegistry", "PlantVisual", "SeedVisual", "PlotBounceAnimator",
        "ProfileView", "SocialView", "LeaderboardView", "ModelPreviewView", "ActivityView",
        "SettingsView", "CommissionView", "ExpansionView", "TalentView", "BulkSellView",
        "CodexView", "MainView", "SeedPackView", "TaskView", "PlantPanelView", "BagDetailView",
        "UI", "GameConfig", "CONFIG", "PLANTS", "RARITY_ORDER", "SEED_PACK_CONFIG",
        "DAILY_TASK_CONFIG", "ViewMode", "RARITY_COLORS", "materials_",
    },
    key=len,
    reverse=True,
)

CLIENT_FUNC_NAMES = sorted(
    {
        "SampleStart", "RegisterModalGuards", "RefreshUI", "RebuildUI", "ShowToast", "InitMaterials",
        "CreateScene", "CreateFarm", "ApplyUnlockedPlotCount", "SyncInventoryRefs", "MarkSaveDirty",
        "SubscribeUIEvents", "EnsureInitialUiReady", "RefreshSelection", "UpdateCamera", "CreateSkybox",
        "InitBGM", "GetGardenLevel", "AddSeedToBag", "AddSeedPack", "ApplyAuthoritativeFarmState",
        "CompletePlantGuide", "BuildVisitPlots", "RestoreOwnFarm",
        "RequestNetworkRecoverySync", "UpdateNetworkRecovery", "HandleClearSaveCompleted",
        "StartSinglePlotBounceAnimation", "PerformPlotAction", "EnterPlantView", "EnterFarmView",
        "OpenCommissionPanel", "OpenSeedPackHub", "OpenTaskPanel", "GetHighestPackIcon",
        "SetSelectedSeedIndex", "CountSeedPacks", "CountMaturePlants", "CountPlotPlants",
        "HarvestNearestMature", "OpenBagItemDetail", "CloseBagItemDetail", "SellBagItem",
        "SellHarvestedByFilter", "BuildSeedPackOverlay", "BuildSeedPackOpeningOverlay",
        "CreateBagPreview", "GetUiRarityColor", "CountPackResults", "GetFirstAvailablePackId",
        "OpenSeedPack", "OpenAllSeedPacks", "RequestRareSeedPackAdReward", "RequestSuppressWorldTap",
        "RequestStealAttemptsAdReward", "FlushPendingRebuildUI", "UpdateCameraTargetForPlotDisplay",
        "GetPlantGuideStep", "RequestMaturePlotAdReward", "ClearGameSave", "ZoomPlantView",
        "SetPlotDisplayMode", "SwitchNextFocusedPlot", "PlotWorldPosition", "ClampToPlot",
        "FindPlantAtLocalPosition", "SelectPlotByDelta", "CycleSeed", "BuySelectedSeed",
        "SellAllHarvested", "PlantSeed", "GetViewMode", "AreAllDailyTasksCompleted",
        "UpdateCurrentTourValue", "ClearBagPreview", "SampleInitMouseMode",
        "HandleInput", "UpdateTouchCameraGesture", "UpdatePlotBounceAnimation", "UpdatePlants",
        "UpdateSeedPackOpening",
    },
    key=len,
    reverse=True,
)

CLIENT_CLOSURE_REPLACEMENTS = [
    (r"function\(\) return plots_\[selectedPlot_\] end", "ctx.getSelectedPlotObject"),
    (r"function\(plotIndex\) selectedPlot_ = plotIndex end", "ctx.setSelectedPlot"),
    (r"function\(value\) selectedPlot_ = value end", "ctx.setSelectedPlot"),
    (r"function\(seedIndex\) selectedSeed_ = seedIndex end", "ctx.setSelectedSeed"),
    (r"function\(item\) selectedBagItem_ = item end", "ctx.setSelectedBagItem"),
    (r"function\(tab\) plantTab_ = tab end", "ctx.setPlantTab"),
    (r"function\(modal\) taskModal_ = modal end", "ctx.setTaskModal"),
    (r"function\(\) selectedBagItem_ = nil end", "ctx.clearSelectedBagItem"),
    (r"function\(count\) unlockedPlotCount_ = count end", "ctx.setUnlockedPlotCount"),
    (r"function\(value\) plots_ = value end", "ctx.setPlots"),
    (r"function\(value\) ownFarmPlotsSave_ = value end", "ctx.setOwnFarmPlotsSave"),
    (r"function\(value\) initialUiReady_ = value end", "ctx.setInitialUiReady"),
    (r"function\(value\) initialUiBuildPending_ = value end", "ctx.setInitialUiBuildPending"),
    (r"function\(value\) initialPlotBounceStarted_ = value end", "ctx.setInitialPlotBounceStarted"),
    (r"function\(value\) initialSocialSnapshotUploaded_ = value end", "ctx.setInitialSocialSnapshotUploaded"),
    (r"function\(value\) pendingRebuildUI_ = value end", "ctx.setPendingRebuildUI"),
    (r"function\(\) return initialUiReady_ end", "ctx.isInitialUiReady"),
    (r"function\(\) return initialUiBuildPending_ end", "ctx.isInitialUiBuildPending"),
    (r"function\(\) return pendingRebuildUI_ end", "ctx.isPendingRebuildUI"),
    (r"function\(\) return initialPlotBounceStarted_ end", "ctx.isInitialPlotBounceStarted"),
    (r"function\(\) return initialSocialSnapshotUploaded_ end", "ctx.isInitialSocialSnapshotUploaded"),
    (r"function\(\) return initialPlayerReady_ end", "ctx.isInitialPlayerReady"),
    (r"function\(\) return scene_ end", "ctx.getScene"),
    (r"function\(\) return camera_ end", "ctx.getCamera"),
    (r"function\(\) return plots_ end", "ctx.getPlots"),
    (r"function\(\) return ownFarmPlotsSave_ end", "ctx.getOwnFarmPlotsSave"),
    (r"function\(\) return unlockedPlotCount_ end", "ctx.getUnlockedPlotCount"),
    (r"function\(\) return selectedPlot_ end", "ctx.getSelectedPlotIndex"),
    (r"function\(\) return selectedSeed_ end", "ctx.getSelectedSeed"),
    (r"function\(\) return seedBag_ end", "ctx.getSeedBag"),
    (r"function\(\) return harvested_ end", "ctx.getHarvested"),
    (r"function\(\) return seedPacks_ end", "ctx.getSeedPacks"),
    (r"function\(\) return collectedPlants_ end", "ctx.getCollectedPlants"),
    (r"function\(\) return codexStats_ end", "ctx.getCodexStats"),
    (r"function\(\) return dailyTaskState_ end", "ctx.getDailyTaskState"),
    (r"function\(\) return selectedBagItem_ end", "ctx.getSelectedBagItem"),
    (r"function\(\) return plantTab_ end", "ctx.getPlantTab"),
    (r"function\(\) return taskModal_ end", "ctx.getTaskModal"),
]

CLIENT_ASSIGNMENTS = [
    (r"\bsaveDisabled_\s*=\s*true\b", "ctx.setSaveDisabled(true)"),
    (r"\binitialUiReady_\s*=\s*false\b", "ctx.setInitialUiReady(false)"),
    (r"\binitialUiBuildPending_\s*=\s*false\b", "ctx.setInitialUiBuildPending(false)"),
    (r"\binitialPlayerReady_\s*=\s*false\b", "ctx.setInitialPlayerReady(false)"),
    (r"\binitialSocialSnapshotUploaded_\s*=\s*false\b", "ctx.setInitialSocialSnapshotUploaded(false)"),
    (r"\binitialPlotBounceStarted_\s*=\s*false\b", "ctx.setInitialPlotBounceStarted(false)"),
    (r"\bunlockedPlotCount_\s*=\s*ProgressionSystem\.GetUnlockedPlotCount\(\)", "ctx.setUnlockedPlotCount(ctx.ProgressionSystem.GetUnlockedPlotCount())"),
    (r"\binitialPlayerReady_\s*=\s*PlayerSystem\.GetUserId\(\)\s*~=\s*nil", "ctx.setInitialPlayerReady(ctx.PlayerSystem.GetUserId() ~= nil)"),
    (r"\bownFarmPlotsSave_\s*=\s*farm\.plots\b", "ctx.setOwnFarmPlotsSave(farm.plots)"),
    (r"\bunlockedPlotCount_\s*=\s*ProgressionSystem\.GetUnlockedPlotCount\(\)", "ctx.setUnlockedPlotCount(ctx.ProgressionSystem.GetUnlockedPlotCount())"),
    (r"\blocal previousUnlocked = unlockedPlotCount_\b", "local previousUnlocked = ctx.getUnlockedPlotCount()"),
    (r"\bif initialUiReady_ and unlockedPlotCount_ > previousUnlocked then\b", "if ctx.isInitialUiReady() and ctx.getUnlockedPlotCount() > previousUnlocked then"),
    (r"\bif initialPlayerReady_ then\b", "if ctx.isInitialPlayerReady() then"),
    (r"\bscene = scene_\b", "scene = ctx.getScene()"),
    (r"\bcameraNode = cameraNode_\b", "cameraNode = ctx.getCameraNode()"),
    (r"\bseedBag = seedBag_\b", "seedBag = ctx.getSeedBag()"),
]

SERVER_CTX_TABLE = """function Start()
    ServerBootstrap.Start({
        Shared = Shared,
        GameConfig = GameConfig,
        ServerTuning = ServerTuning,
        ServerConfig = ServerConfig,
        InventoryRules = InventoryRules,
        RequestGuard = RequestGuard,
        ServerShop = ServerShop,
        ServerCropRules = ServerCropRules,
        ServerFarmState = ServerFarmState,
        ServerEconomyState = ServerEconomyState,
        ServerCommission = ServerCommission,
        ServerActivity = ServerActivity,
        ServerLeaderboard = ServerLeaderboard,
        ServerRewards = ServerRewards,
        ServerEconomyActions = ServerEconomyActions,
        ServerSteal = ServerSteal,
        GiftServer = GiftServer,
        SocialServer = SocialServer,
        ServerEventHandlers = ServerEventHandlers,
        ServerGlobals = ServerGlobals,
        SERVER_MUTATION_TALENT_BONUSES = SERVER_MUTATION_TALENT_BONUSES,
        DEFAULT_HARVEST_BAG_CAPACITY = DEFAULT_HARVEST_BAG_CAPACITY,
        MAX_HARVEST_BAG_CAPACITY = MAX_HARVEST_BAG_CAPACITY,
        BAG_CAPACITY_BONUSES = BAG_CAPACITY_BONUSES,
        connections = connections_,
        connectionUsers = connectionUsers_,
        setScene = function(scene) scene_ = scene end,
        getScene = function() return scene_ end,
        Send = Send,
        Now = Now,
        DeepCopy = DeepCopy,
        PickGiftSeedId = PickGiftSeedId,
        NormalizePlantIndex = NormalizePlantIndex,
        NormalizePlotIndex = NormalizePlotIndex,
        NormalizeLocalPos = NormalizeLocalPos,
        NormalizePositiveCount = NormalizePositiveCount,
        NormalizeUserId = NormalizeUserId,
        NormalizeEconomyState = NormalizeEconomyState,
        NormalizeFarmState = NormalizeFarmState,
        NormalizeActivityState = NormalizeActivityState,
        NormalizeTalentState = NormalizeTalentState,
        NormalizeProgressionState = NormalizeProgressionState,
        NormalizeDailyTaskState = NormalizeDailyTaskState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NextRevision = NextRevision,
        RollWeighted = RollWeighted,
        RandomRange = RandomRange,
        RandItem = RandItem,
        CopyNumericKeyMap = CopyNumericKeyMap,
        RecalculateAuthoritativeItemPrice = RecalculateAuthoritativeItemPrice,
        CalculateAuthFarmTourValue = CalculateAuthFarmTourValue,
        GetActivityRankInfo = GetActivityRankInfo,
        GetIncomeRankInfo = GetIncomeRankInfo,
        GetCurrentActivityCycleInfo = GetCurrentActivityCycleInfo,
        GetPreviousActivityCycleInfo = GetPreviousActivityCycleInfo,
        GetActivityConfig = GetActivityConfig,
        GetNicknameMap = GetNicknameMap,
        AddActivityRankCommit = AddActivityRankCommit,
        AddTourRankCommit = AddTourRankCommit,
        AddIncomeRankCommit = AddIncomeRankCommit,
        EnsureSeedShopState = EnsureSeedShopState,
        SendFullAvailableSeedShop = SendFullAvailableSeedShop,
        BroadcastFullAvailableSeedShop = BroadcastFullAvailableSeedShop,
        BuildSeedShopQuotaKey = BuildSeedShopQuotaKey,
        SendSeedShopState = SendSeedShopState,
        GetServerMutationTalentBonus = GetServerMutationTalentBonus,
        GetMaxCropsPerPlot = GetMaxCropsPerPlot,
        BuildAuthoritativeCrop = BuildAuthoritativeCrop,
        SyncProgressionTourValueFromFarm = SyncProgressionTourValueFromFarm,
        FindFarmCropFromHarvestPayload = FindFarmCropFromHarvestPayload,
        RefreshAuthCrop = RefreshAuthCrop,
        GetHarvestBagCapacityFromState = GetHarvestBagCapacityFromState,
        AddServerHarvestExp = AddServerHarvestExp,
        RollHarvestDropPack = RollHarvestDropPack,
        ApplyActivityHarvestReward = ApplyActivityHarvestReward,
        RollSeedFromPack = RollSeedFromPack,
        IsValidPackId = IsValidPackId,
        IsValidSellMode = IsValidSellMode,
        BuildVisitGardenFromAuthFarm = BuildVisitGardenFromAuthFarm,
        GetFarmPlot = GetFarmPlot,
        FindFarmCrop = FindFarmCrop,
        SendError = SendError,
        SendPlayerProfile = SendPlayerProfile,
        RequestEconomyState = RequestEconomyState,
        RequestAuthFarmState = RequestAuthFarmState,
        RequestLeaderboardAuthority = RequestLeaderboardAuthority,
        ClaimActivityRankRewardAuthority = ClaimActivityRankRewardAuthority,
        RequestSteal = RequestSteal,
        GrantAdReward = GrantAdReward,
        BuySeed = BuySeed,
        ClearPlayerSave = ClearPlayerSave,
        PlantSeedAuthority = PlantSeedAuthority,
        HarvestCropAuthority = HarvestCropAuthority,
        OpenSeedPackAuthority = OpenSeedPackAuthority,
        SellHarvested = SellHarvested,
        RequestCommissionsAuthority = RequestCommissionsAuthority,
        CompleteCommissionAuthority = CompleteCommissionAuthority,
        SubmitActivityCropAuthority = SubmitActivityCropAuthority,
        ExchangeActivityRewardAuthority = ExchangeActivityRewardAuthority,
        DrawActivityPackAuthority = DrawActivityPackAuthority,
        ClaimDailyRewardAuthority = ClaimDailyRewardAuthority,
        SynthesizePackAuthority = SynthesizePackAuthority,
        UnlockTalentAuthority = UnlockTalentAuthority,
        ExpandPlotAuthority = ExpandPlotAuthority,
        GetConnectionKey = GetConnectionKey,
        GetConnectionUserId = GetConnectionUserId,
        GetRequestUserId = GetRequestUserId,
        ReadRequest = ReadRequest,
    })
end"""

CLIENT_CTX_TABLE = """function Start()
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
        setTaskModal = function(value) taskModal_ = modal end,
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
end"""


def extract_function_body(lines, start_line, end_line_exclusive):
    body_lines = lines[start_line:end_line_exclusive]
    body = "".join(body_lines).rstrip()
    if body.endswith("end"):
        body = body[:-3].rstrip()
    return body


def transform_server_body(body):
    text = body
    text = re.sub(r"\bscene_\s*=\s*Scene\(\)", "ctx.setScene(Scene())", text)
    text = re.sub(r"\bconnections_\b", "ctx.connections", text)
    text = re.sub(r"\bconnectionUsers_\b", "ctx.connectionUsers", text)
    text = re.sub(r"\bscene_\b", "ctx.getScene()", text)
    text = re.sub(r"getConnections = function\(\) return ctx\.connections end", "getConnections = function() return ctx.connections end", text)
    for name in SERVER_CTX_NAMES:
        text = re.sub(rf"\b{re.escape(name)}\b", f"ctx.{name}", text)
    text = text.replace("ctx.ctx.", "ctx.")
    text = re.sub(r"\bClampValue = ClampValue\b", "ClampValue = ServerUtils.ClampValue", text)
    return text


def transform_client_body(body):
    text = body
    for pattern, replacement in CLIENT_CLOSURE_REPLACEMENTS:
        text = re.sub(pattern, replacement, text)
    for pattern, replacement in CLIENT_ASSIGNMENTS:
        text = re.sub(pattern, replacement, text)
    for name in CLIENT_MODULE_NAMES:
        text = re.sub(rf"\b{re.escape(name)}\b", f"ctx.{name}", text)
    for name in CLIENT_FUNC_NAMES:
        text = re.sub(rf"\b{re.escape(name)}\b", f"ctx.{name}", text)
    text = text.replace("ctx.ctx.", "ctx.")
    text = re.sub(r"(\w+)\.ctx\.(\w+)", r"\1.\2", text)
    return text


def replace_function(lines, func_name, new_func_text):
    pattern = re.compile(rf"\nfunction {func_name}\(\)\n")
    match = pattern.search("\n" + "".join(lines))
    if not match:
        raise SystemExit(f"{func_name} not found")
    start = match.start() + 1
    end_match = re.search(rf"\nfunction \w+", "\n" + "".join(lines)[match.end():])
    if end_match:
        end = match.end() + end_match.start()
    else:
        end = len("".join(lines))
    prefix = "".join(lines)[:start]
    suffix = "".join(lines)[end:]
    return prefix + new_func_text + suffix


def extract_server():
    path = ROOT / "server_main.lua"
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    body = extract_function_body(lines, 673, 929)
    bootstrap_body = transform_server_body(body)
    bootstrap = (
        "-- ============================================================================\n"
        "-- 服务端启动引导 (Server Bootstrap)\n"
        "-- Grow A Garden\n"
        "-- ============================================================================\n\n"
        "local ServerUtils = require(\"server.server_utils\")\n\n"
        "local ServerBootstrap = {}\n\n"
        "function ServerBootstrap.Start(ctx)\n"
        + bootstrap_body
        + "\nend\n\nreturn ServerBootstrap\n"
    )
    (ROOT / "runtime" / "server_bootstrap.lua").write_text(bootstrap, encoding="utf-8")

    content = path.read_text(encoding="utf-8")
    content = content.replace(
        'local ServerGlobals = require("runtime.server_globals")',
        'local ServerGlobals = require("runtime.server_globals")\nlocal ServerBootstrap = require("runtime.server_bootstrap")',
        1,
    )
    content = replace_function(content.splitlines(keepends=True), "Start", SERVER_CTX_TABLE + "\n")
    path.write_text(content, encoding="utf-8")
    print("server_bootstrap:", len(bootstrap.splitlines()), "lines")
    print("server_main:", len(content.splitlines()), "lines")


def extract_client():
    path = ROOT / "main.lua"
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    body = extract_function_body(lines, 706, 1387)
    bootstrap_body = transform_client_body(body)
    bootstrap = (
        "-- ============================================================================\n"
        "-- 客户端启动引导 (Client Bootstrap)\n"
        "-- Grow A Garden\n"
        "-- ============================================================================\n\n"
        "local ClientBootstrap = {}\n\n"
        "function ClientBootstrap.Start(ctx)\n"
        + bootstrap_body
        + "\nend\n\nreturn ClientBootstrap\n"
    )
    (ROOT / "runtime" / "client_bootstrap.lua").write_text(bootstrap, encoding="utf-8")

    content = path.read_text(encoding="utf-8")
    content = content.replace(
        'local GameLoop = require("runtime.game_loop")',
        'local GameLoop = require("runtime.game_loop")\nlocal ClientBootstrap = require("runtime.client_bootstrap")',
        1,
    )
    fixed_ctx = CLIENT_CTX_TABLE.replace(
        "setTaskModal = function(value) taskModal_ = modal end",
        "setTaskModal = function(value) taskModal_ = value end",
    )
    content = replace_function(content.splitlines(keepends=True), "Start", fixed_ctx + "\n")
    path.write_text(content, encoding="utf-8")
    print("client_bootstrap:", len(bootstrap.splitlines()), "lines")
    print("main:", len(content.splitlines()), "lines")


if __name__ == "__main__":
    extract_server()
    extract_client()
    print("done")
