-- ============================================================================
-- UI 初始化绑定
-- Grow A Garden
-- ============================================================================
-- 分批承接 main.lua 中各 View / Controller 的 Init 参数绑定。
-- 已迁移 6A：UIController、SeedPackView、TaskView。
-- 已迁移 6B：ActivityView、SocialView、ModelPreviewView、CommissionView。
-- 已迁移 6C：PlantPanelView、BagDetailView、BulkSellView、CodexView。
-- 已迁移 6D：MainView、ProfileView、SettingsView、TalentView、ExpansionView、LeaderboardView。
-- ============================================================================

local UiBindings = {}

local deps_ = {}

function UiBindings.Init(deps)
    deps_ = deps or {}
end

local function RebuildUI()
    if deps_.rebuildUI ~= nil then deps_.rebuildUI() end
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then deps_.showToast(text, silent) end
end

function UiBindings.InitUIController()
    deps_.UIController.Init({
        config = deps_.CONFIG,
        NetworkRecovery = deps_.NetworkRecovery,
        plants = deps_.PLANTS,
        seedBag = deps_.getSeedBag(),
        getPlots = deps_.getPlots,
        getSelectedPlotIndex = deps_.getSelectedPlotIndex,
        getSelectedSeed = deps_.getSelectedSeed,
        getSelectedBagItem = deps_.getSelectedBagItem,
        getUnlockedPlotCount = deps_.getUnlockedPlotCount,
        getMoney = function() return deps_.WalletSystem.GetBalance() end,
        getTourValue = function() return deps_.ProgressionSystem.GetTourValue() end,
        getTalentLevel = function() return deps_.TalentSystem.GetLevel() end,
        getTalentPoints = function() return deps_.TalentSystem.GetTalentPoints() end,
        hasUnlockableTalent = function() return deps_.TalentSystem.HasUnlockableTalent() end,
        isFarmView = function() return deps_.getViewMode() == deps_.ViewMode.FARM end,
        isPlantView = function() return deps_.getViewMode() == deps_.ViewMode.PLANT end,
        isVisitMode = function() return deps_.SocialGardenSystem.IsVisitMode() end,
        returnHome = function() deps_.SocialGardenSystem.ReturnHome() end,
        rarityOrder = deps_.RARITY_ORDER,
        countSeedPacks = deps_.countSeedPacks,
        countMaturePlants = deps_.countMaturePlants,
        countPlotPlants = deps_.countPlotPlants,
        buildSeedPackOverlay = deps_.buildSeedPackOverlay,
        buildSeedPackOpeningOverlay = deps_.buildSeedPackOpeningOverlay,
        createBagPreview = deps_.createBagPreview,
        retryLoading = deps_.retryLoading,
        resetSave = deps_.resetSave,
        suppressWorldTap = deps_.suppressWorldTap,
        showToast = deps_.showToast,
    })
end

function UiBindings.InitSeedPackView()
    deps_.SeedPackView.Init({
        plants = deps_.PLANTS,
        rarityOrder = deps_.RARITY_ORDER,
        seedPackConfig = deps_.SEED_PACK_CONFIG,
        seedPacks = deps_.getSeedPacks(),
        getUiRarityColor = deps_.getUiRarityColor,
        countPackResults = deps_.countPackResults,
        countSeedPacks = deps_.countSeedPacks,
        getFirstAvailablePackId = deps_.getFirstAvailablePackId,
        openSeedPack = deps_.openSeedPack,
        openAllSeedPacks = deps_.openAllSeedPacks,
        requestRareSeedPackAdReward = deps_.requestRareSeedPackAdReward,
        getAdSeedPackDaily = function()
            local state = deps_.SocialGardenSystem.GetState and deps_.SocialGardenSystem.GetState() or {}
            local daily = state.daily or {}
            return { count = daily.seedPackAdCount or 0, limit = daily.seedPackAdLimit or 3 }
        end,
        suppressWorldTap = deps_.suppressWorldTap,
        closePackPanel = function() deps_.SeedPackOpeningController.ClosePanel() end,
        skipOpening = function() deps_.SeedPackOpeningController.SkipOpening() end,
        getSynthesisTarget = function(packId) return deps_.InventorySystem.GetSynthesisTarget(packId) end,
        synthesizePack = function(packId, count)
            local ok = deps_.EconomyCloudSystem.SynthesizePack(packId, count)
            if ok then ShowToast("正在请求服务器合成种子包...") end
            return ok, nil
        end,
        showToast = deps_.showToast,
        showFloatingToast = function(text)
            deps_.FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = RebuildUI,
        emitSeedPackChanged = function()
            deps_.EventBus.Emit(deps_.UIEvents.SEEDPACK_CHANGED, { reason = "seed_pack_view" })
        end,
    })
end

function UiBindings.InitTaskView()
    deps_.TaskView.Init({
        dailyTaskConfig = deps_.DAILY_TASK_CONFIG,
        dailyTaskState = deps_.getDailyTaskState(),
        seedPackConfig = deps_.SEED_PACK_CONFIG,
        getTaskModal = deps_.getTaskModal,
        setTaskModal = deps_.setTaskModal,
        areAllDailyTasksCompleted = deps_.areAllDailyTasksCompleted,
        claimDailyReward = function()
            local ok = deps_.EconomyCloudSystem.ClaimDailyReward()
            if ok then ShowToast("正在请求服务器发放每日奖励...") end
            return ok, nil
        end,
        suppressWorldTap = deps_.suppressWorldTap,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitActivityView()
    deps_.ActivityView.Init({
        plants = deps_.PLANTS,
        seedPackConfig = deps_.SEED_PACK_CONFIG,
        activityConfig = deps_.GameConfig.ACTIVITY_CONFIG,
        getActiveActivity = function() return deps_.ActivitySystem.GetActiveActivity() end,
        getActivityState = function(activityId) return deps_.ActivitySystem.GetState()[activityId] end,
        getTimeLeftText = function() return deps_.ActivitySystem.GetTimeLeftText() end,
        getSweetSubmitItems = function() return deps_.ActivitySystem.GetSweetSubmitItems() end,
        submitSweetCrop = function(item)
            local ok = deps_.EconomyCloudSystem.SubmitActivityCrop(item)
            if ok then ShowToast("正在请求服务器上交作物...") end
            return ok, ok and nil or "server_required"
        end,
        exchangeSweetReward = function(rewardId)
            local ok = deps_.EconomyCloudSystem.ExchangeActivityReward(rewardId)
            if ok then ShowToast("正在请求服务器兑换奖励...") end
            return ok, ok and nil or "server_required"
        end,
        drawAlienPack = function(count)
            local ok = deps_.EconomyCloudSystem.DrawActivityPack(count)
            if ok then ShowToast("正在请求服务器抽取奖励...") end
            return ok, ok and nil or "server_required"
        end,
        getLeaderboard = function(activityId) return deps_.ActivitySystem.GetLeaderboard(activityId) end,
        suppressWorldTap = deps_.suppressWorldTap,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitSocialView()
    deps_.SocialView.Init({
        SocialGardenSystem = deps_.SocialGardenSystem,
        suppressWorldTap = deps_.suppressWorldTap,
        getSelectedPlotIndex = deps_.getSelectedPlotIndex,
        requestStealAttemptsAdReward = deps_.requestStealAttemptsAdReward,
        showToast = deps_.showToast,
        onClosed = deps_.flushPendingRebuildUI,
    })
end

function UiBindings.InitModelPreviewView()
    deps_.ModelPreviewView.Init({
        isOpen = function() return deps_.ModelPreviewSystem.IsOpen() end,
        openPreview = function() deps_.ModelPreviewSystem.Open() end,
        closePreview = function()
            deps_.ModelPreviewSystem.Close()
            deps_.CameraSystem.EnterFarmView()
            deps_.updateCameraTargetForPlotDisplay()
        end,
        nextPreview = function() deps_.ModelPreviewSystem.Next() end,
        prevPreview = function() deps_.ModelPreviewSystem.Prev() end,
        showKind = function(kind) return deps_.ModelPreviewSystem.ShowKind(kind) end,
        getCurrentItem = function() return deps_.ModelPreviewSystem.GetCurrentItem() end,
        suppressWorldTap = deps_.suppressWorldTap,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitCommissionView()
    deps_.CommissionView.Init({
        seedPackConfig = deps_.SEED_PACK_CONFIG,
        getCommissions = function() return deps_.CommissionSystem.GetCommissions() end,
        getTimeLeftText = function() return deps_.CommissionSystem.GetTimeLeftText() end,
        getRequirementText = function(commission) return deps_.CommissionSystem.GetRequirementText(commission) end,
        getMatchingItems = function(commission) return deps_.CommissionSystem.GetMatchingHarvestedItems(commission) end,
        completeCommission = function(commission, item)
            local ok = deps_.EconomyCloudSystem.CompleteCommission(commission, item)
            deps_.refreshUI(true)
            return ok
        end,
        suppressWorldTap = deps_.suppressWorldTap,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitPlantPanelView()
    deps_.PlantPanelView.Init({
        plants = deps_.PLANTS,
        seedBag = deps_.getSeedBag(),
        harvested = deps_.getHarvested(),
        getHarvestBagCapacity = function() return deps_.InventorySystem.GetHarvestBagCapacity() end,
        getHarvestBagMaxCapacity = function() return deps_.InventorySystem.GetHarvestBagMaxCapacity() end,
        getSelectedPlot = deps_.getSelectedPlot,
        getSelectedPlotIndex = deps_.getSelectedPlotIndex,
        getSelectedSeed = deps_.getSelectedSeed,
        setSelectedSeed = deps_.setSelectedSeedIndex,
        getPlantTab = deps_.getPlantTab,
        getUnlockedPlotCount = deps_.getUnlockedPlotCount,
        getVisitablePlotIndex = function() return deps_.SocialGardenSystem.GetVisitablePlotIndex() end,
        setVisitablePlotIndex = function(plotIndex) return deps_.SocialGardenSystem.SetVisitablePlotIndex(plotIndex) end,
        getUiRarityColor = deps_.getUiRarityColor,
        suppressWorldTap = deps_.suppressWorldTap,
        rebuildUI = RebuildUI,
        refreshPanel = function()
            deps_.UIController.RefreshPlantContent()
        end,
        harvestNearestMature = deps_.harvestNearestMature,
        openBagItemDetail = deps_.openBagItemDetail,
        openBulkSell = function()
            deps_.suppressWorldTap()
            deps_.BulkSellView.Show()
        end,
    })
end

function UiBindings.InitBagDetailView()
    deps_.BagDetailView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        closeBagItemDetail = deps_.closeBagItemDetail,
        sellBagItem = deps_.sellBagItem,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
        refreshInventoryPanels = function()
            deps_.UIController.RefreshInventoryPanels()
            deps_.refreshUI(true)
        end,
    })
end

function UiBindings.InitBulkSellView()
    deps_.BulkSellView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        previewSellHarvestedByFilter = function(filter)
            return deps_.InventorySystem.PreviewSellHarvestedByFilter(filter)
        end,
        sellHarvestedByFilter = deps_.sellHarvestedByFilter,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitCodexView()
    deps_.CodexView.Init({
        plants = deps_.PLANTS,
        collectedPlants = deps_.getCollectedPlants(),
        codexStats = deps_.getCodexStats(),
        suppressWorldTap = deps_.suppressWorldTap,
    })
end

function UiBindings.InitMainView()
    deps_.MainView.Init({
        isFarmView = function() return deps_.getViewMode() == deps_.ViewMode.FARM end,
        isPlantView = function() return deps_.getViewMode() == deps_.ViewMode.PLANT end,
        isVisitMode = function() return deps_.SocialGardenSystem.IsVisitMode() end,
        isStealingMode = function() return deps_.SocialGardenSystem.IsStealingMode() end,
        getVisitGarden = function() return deps_.SocialGardenSystem.GetVisitGarden() end,
        countStealableCrops = function() return deps_.SocialGardenSystem.CountStealableCrops() end,
        getMatureVisitCrops = function() return deps_.SocialGardenSystem.GetMatureVisitCrops() end,
        getStealChanceText = function(crop) return deps_.SocialGardenSystem.GetStealChanceText(crop) end,
        stealVisitCrop = function(index, cropId) deps_.SocialGardenSystem.RequestSteal(index, cropId) end,
        getVisitTourValue = function() return deps_.SocialGardenSystem.GetVisitTourValue() end,
        getVisitLikeCount = function() return deps_.SocialGardenSystem.GetVisitLikeCount() end,
        hasLikedVisitGarden = function() return deps_.SocialGardenSystem.HasLikedVisitGarden() end,
        likeVisitGarden = function() deps_.SocialGardenSystem.LikeVisitGarden(); RebuildUI() end,
        sendFriendRequestToVisitGarden = function()
            local garden = deps_.SocialGardenSystem.GetVisitGarden()
            if garden == nil or garden.userId == nil then
                ShowToast("当前花园玩家 ID 无效")
                return false
            end
            return deps_.SocialGardenSystem.SendFriendRequest(garden.userId)
        end,
        beginStealingMode = function() deps_.SocialGardenSystem.BeginStealingMode() end,
        endStealingMode = function() deps_.SocialGardenSystem.EndStealingMode() end,
        getPlantTab = deps_.getPlantTab,
        getSelectedPlotIndex = deps_.getSelectedPlotIndex,
        getUnlockedPlotCount = deps_.getUnlockedPlotCount,
        getVisitablePlotIndex = function() return deps_.SocialGardenSystem.GetVisitablePlotIndex() end,
        setVisitablePlotIndex = function(plotIndex) return deps_.SocialGardenSystem.SetVisitablePlotIndex(plotIndex) end,
        setPlantTab = deps_.setPlantTab,
        suppressWorldTap = deps_.suppressWorldTap,
        enterPlantView = deps_.enterPlantView,
        enterFarmView = deps_.enterFarmView,
        returnHome = function() deps_.SocialGardenSystem.ReturnHome() end,
        openShop = function() deps_.Shop.Open() end,
        openCommission = deps_.openCommissionPanel,
        openSeedPackHub = deps_.openSeedPackHub,
        openTaskPanel = deps_.openTaskPanel,
        countSeedPacks = deps_.countSeedPacks,
        getHighestPackIcon = deps_.getHighestPackIcon,
        clearSelectedBagItem = deps_.clearSelectedBagItem,
        clearBagPreview = deps_.clearBagPreview,
        rebuildUI = RebuildUI,
        onTalentOpen = function()
            deps_.suppressWorldTap()
            deps_.TalentView.Show()
        end,
        onExpansionOpen = function()
            deps_.suppressWorldTap()
            deps_.ExpansionView.Show()
        end,
        onCodexOpen = function()
            deps_.suppressWorldTap()
            deps_.CodexView.Show()
        end,
        isExpansionMaxed = function()
            return not deps_.ProgressionSystem.CanUnlockNextPlot()
        end,
        getPlantGuideStep = deps_.getPlantGuideStep,
        requestMaturePlotAdReward = deps_.requestMaturePlotAdReward,
    })
end

function UiBindings.InitProfileView()
    deps_.ProfileView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        getDisplayName = function() return deps_.PlayerSystem.GetDisplayName() end,
        getTapNickname = function() return deps_.PlayerSystem.GetTapNickname() end,
        getUserId = function() return deps_.PlayerSystem.GetUserId() end,
        getAvatars = function() return deps_.PlayerSystem.GetAvatars() end,
        getSelectedAvatar = function() return deps_.PlayerSystem.GetSelectedAvatar() end,
        getSelectedAvatarIndex = function() return deps_.PlayerSystem.GetSelectedAvatarIndex() end,
        selectAvatar = function(index) return deps_.PlayerSystem.SelectAvatar(index) end,
        setNickname = function(name) return deps_.PlayerSystem.SetNickname(name) end,
        NetworkClient = deps_.NetworkClient,
        Shared = deps_.Shared,
        updateProfile = function(onComplete)
            local payload = deps_.PlayerSystem.GetProfileUpdatePayload(onComplete)
            return deps_.NetworkClient.SendRequest(deps_.Shared.EVENTS.UPDATE_PLAYER_PROFILE, payload)
        end,
        getLevel = function() return deps_.TalentSystem.GetLevel() end,
        getExp = function() return deps_.TalentSystem.GetExp() end,
        getExpToNextLevel = function() return deps_.TalentSystem.GetExpToNextLevel() end,
        getTourValue = function() return deps_.ProgressionSystem.GetTourValue() end,
        getBestTourValue = function() return deps_.ProgressionSystem.GetBestTourValue() end,
        showToast = deps_.showToast,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitSettingsView()
    deps_.SettingsView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        clearSave = deps_.clearGameSave,
        showToast = deps_.showToast,
        getPlotDisplayMode = function()
            return deps_.PlotDisplayController.GetDisplayMode()
        end,
        isPowerSaveMode = function()
            return deps_.PlayerSystem.IsPowerSaveMode()
        end,
        setPowerSaveMode = function(enabled)
            return deps_.PlayerSystem.SetPowerSaveMode(enabled)
        end,
        isPlantView = function()
            return deps_.getViewMode() == deps_.ViewMode.PLANT
        end,
        zoomPlantView = deps_.zoomPlantView,
        getFocusedPlotIndex = function()
            return deps_.PlotDisplayController.GetFocusedPlotIndex()
        end,
        getUnlockedPlotCount = deps_.getUnlockedPlotCount,
        setPlotDisplayMode = deps_.setPlotDisplayMode,
        switchNextPlot = deps_.switchNextFocusedPlot,
        requestMaturePlotAdReward = deps_.requestMaturePlotAdReward,
        onClearSaveSuccess = function()
            deps_.SettingsView.Close()
        end,
        rebuildUI = RebuildUI,
    })
end

function UiBindings.InitTalentView()
    deps_.TalentView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        unlockTalent = function(talentId)
            return deps_.EconomyCloudSystem.UnlockTalent(talentId)
        end,
        showToast = deps_.showToast,
        onTalentChanged = deps_.markSaveDirty,
    })
end

function UiBindings.InitExpansionView()
    deps_.ExpansionView.Init({
        suppressWorldTap = deps_.suppressWorldTap,
        getLevel = function()
            return deps_.TalentSystem.GetLevel()
        end,
        getGold = function()
            return deps_.WalletSystem.GetBalance()
        end,
        getTourValue = function()
            return deps_.ProgressionSystem.GetTourValue()
        end,
        expandNextPlot = function()
            local ok = deps_.EconomyCloudSystem.ExpandPlot()
            if ok then ShowToast("正在请求服务器扩地...") end
            return ok, ok and nil or "server_required"
        end,
    })
end

function UiBindings.InitLeaderboardView()
    deps_.LeaderboardView.Init({
        LeaderboardSystem = deps_.LeaderboardSystem,
        SocialGardenSystem = deps_.SocialGardenSystem,
        getActiveActivityId = function() return deps_.ActivitySystem.GetActiveActivityId() end,
        getMyNickname = function() return deps_.PlayerSystem.GetDisplayName() end,
        getMyUserId = function() return deps_.PlayerSystem.GetUserId() end,
        getMyAvatar = function() return deps_.PlayerSystem.GetSelectedAvatarProfile() end,
        visitPlayer = function(userId)
            local ok = deps_.SocialGardenSystem.VisitPlayer(userId)
            if ok then deps_.ActivityView.Close() end
            return ok
        end,
        suppressWorldTap = deps_.suppressWorldTap,
    })
end

return UiBindings
