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
local unsubscribeSocialChanged_ = nil
local unsubscribeSeedPackChanged_ = nil
local unsubscribeCommissionChanged_ = nil
local unsubscribeActivityChanged_ = nil
local unsubscribeTaskChanged_ = nil
local unsubscribeTalentChanged_ = nil
local unsubscribeWalletChanged_ = nil
local unsubscribeInventoryChanged_ = nil
local unsubscribeFarmChanged_ = nil
local unsubscribePlayerChanged_ = nil
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
local RefreshUI = nil
local ShowToast = nil
local RebuildUI = nil
local SelectPlotByDelta = nil
local ClearBagPreview = nil
local OpenSeedPackHub = nil
local OpenTaskPanel = nil
local OpenCommissionPanel = nil
local ExpandNextPlot = nil
local UpdateCameraTargetForPlotDisplay = nil
local RefreshSelection = nil
local UpdateCurrentTourValue = nil
local CreateFarm = nil
local DisposeCurrentFarm = nil
local ApplyUnlockedPlotCount = nil
local HandleClearSaveCompleted = nil
local EnsureInitialUiReady = nil

local function SyncInventoryRefs()
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

local function MarkSaveDirty()
    -- 纯服务器游戏：客户端不保存权威玩法进度；此函数仅保留给现有依赖调用。
    saveDirty_ = false
    saveTimer_ = 0
end

local function SaveGameNow()
    -- 纯服务器游戏：权威数据由 serverCloud 保存。
    saveDirty_ = false
    saveTimer_ = 0
    return true
end

local function ClearGameSave()
    local requested = EconomyCloudSystem.ClearSave()
    if not requested and ShowToast ~= nil then
        ShowToast("服务器尚未就绪，无法清除存档")
    end
    saveDirty_ = false
    saveDisabled_ = true
    return requested
end

local function ApplyAuthoritativeFarmState(farm)
    if type(farm) ~= "table" or type(farm.plots) ~= "table" then return false end
    local serverUnlocked = ProgressionSystem.GetUnlockedPlotCount()
    local farmRecreated = false
    if serverUnlocked ~= unlockedPlotCount_ then
        ownFarmPlotsSave_ = CropSystem.GetPlotsSaveData(plots_)
        DisposeCurrentFarm()
        unlockedPlotCount_ = serverUnlocked
        CreateFarm()
        ApplyUnlockedPlotCount()
        farmRecreated = true
    end
    CropSystem.ClearPlots(plots_)
    CropSystem.RestorePlotsFromSave(plots_, farm.plots)
    if farmRecreated and initialUiReady_ then
        PlotBounceAnimator.StartAll(plots_)
        initialPlotBounceStarted_ = true
    end
    ownFarmPlotsSave_ = CropSystem.GetPlotsSaveData(plots_)
    UpdateCurrentTourValue()
    RefreshSelection()
    MarkSaveDirty()
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
    print("[权威农场] 已从服务器重建本地农场")
    return true
end

local function AddSeedToBag(plantIndex, count, buff)
    local added = InventorySystem.AddSeedToBag(plantIndex, count, buff)
    if added > 0 then MarkSaveDirty() end
    return added
end

local function CountSeedPacks()
    return InventorySystem.CountSeedPacks()
end

local function GetHighestPackIcon()
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

local function AddSeedPack(packId, count)
    local ok = InventorySystem.AddSeedPack(packId, count)
    if ok then MarkSaveDirty() end
    return ok
end

local function IsTaskCompleted(taskCfg)
    return InventorySystem.IsTaskCompleted(taskCfg)
end

local function AreAllDailyTasksCompleted()
    return InventorySystem.AreAllDailyTasksCompleted()
end

local function AddDailyProgress(key, amount)
    InventorySystem.AddDailyProgress(key, amount)
end

local function CheckSilverPackRewards()
    InventorySystem.CheckSilverPackRewards()
end

local function InitMaterials()
    PlantVisual.InitMaterials()
end

local function ResolvePlantMaterial(plant, mutation)
    return PlantVisual.ResolvePlantMaterial(plant, mutation)
end

local function CreatePlantVisual(parent, plant, mutation, material)
    return PlantVisual.CreatePlantVisual(parent, plant, mutation, material)
end

local function CreateSpecialEffects(plantData)
    PlantVisual.CreateSpecialEffects(plantData)
end

local function CreateScene()
    scene_, cameraNode_, camera_ = SceneSystem.CreateScene()
    CameraSystem.Init(CONFIG, cameraNode_)
end

local function CreateSkybox()
    SceneSystem.CreateSkybox(scene_)
end

local function UpdateCamera()
    CameraSystem.UpdateCamera()
end

local function GetViewMode()
    return CameraSystem.GetViewMode()
end

local function IsPlantGuideDone()
    return tutorialState_ ~= nil and tutorialState_.plantGuideDone == true
end

local function ShouldShowPlantGuide()
    return initialUiReady_ == true and not IsPlantGuideDone() and not SocialGardenSystem.IsVisitMode()
end

local function GetPlantGuideStep()
    if not ShouldShowPlantGuide() then return "done" end
    if GetViewMode() == ViewMode.FARM then return "start" end
    if plantTab_ ~= "seed" then return "seed_tab" end
    return "plant"
end

local function CompletePlantGuide()
    if tutorialState_ == nil then return end
    tutorialState_.plantGuideDone = true
end

local function EnterPlantView()
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

local function EnterFarmView()
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

local function PlotWorldPosition(index)
    return FarmSystem.PlotWorldPosition(index)
end

CreateFarm = function()
    plots_ = FarmSystem.CreateFarm(scene_, unlockedPlotCount_, LOCAL)
end

DisposeCurrentFarm = function()
    if plots_ ~= nil then
        ownFarmPlotsSave_ = CropSystem.GetPlotsSaveData(plots_)
        for _, plot in ipairs(plots_) do
            if plot.node ~= nil then
                plot.node:Dispose()
            end
        end
    end
    plots_ = {}
end

local function BuildVisitPlots(garden)
    DisposeCurrentFarm()
    local plotIndex = tonumber(garden and garden.visitablePlotIndex or 1) or 1
    plots_ = FarmSystem.CreateFarm(scene_, 1, LOCAL)
    unlockedPlotCount_ = 1
    selectedPlot_ = 1
    local plotData = garden and garden.plot or nil
    if plotData ~= nil then
        CropSystem.RestorePlotsFromSave(plots_, {
            [1] = { plants = plotData.plants or {} },
        })
    end
    PlotDisplayController.SetDisplayMode("all")
    CameraSystem.EnterFarmView()
    RefreshSelection()
    UpdateCamera()
    print(string.format("[社交花园] 已加载玩家 %s 的可参观地块 %d", tostring(garden and garden.nickname or "好友"), plotIndex))
end

local function RestoreOwnFarm()
    local restorePlots = ownFarmPlotsSave_ or CropSystem.GetPlotsSaveData(plots_)
    DisposeCurrentFarm()
    ownFarmPlotsSave_ = restorePlots
    unlockedPlotCount_ = ProgressionSystem.GetUnlockedPlotCount()
    CreateFarm()
    CropSystem.RestorePlotsFromSave(plots_, ownFarmPlotsSave_)
    ownFarmPlotsSave_ = nil
    PlotDisplayController.ApplyUnlockedPlotCount()
    PlotBounceAnimator.StartAll(plots_)
    selectedPlot_ = Clamp(selectedPlot_, 1, math.max(1, unlockedPlotCount_))
    CameraSystem.EnterFarmView()
    UpdateCameraTargetForPlotDisplay()
    RefreshSelection()
    UpdateCamera()
end

--- 启动地块依次弹出动画
local function StartPlotBounceAnimation()
    PlotBounceAnimator.StartAll(plots_)
end

local function StartSinglePlotBounceAnimation(plotIndex)
    PlotBounceAnimator.StartSingle(plots_, plotIndex)
end

--- 更新地块弹出动画
local function UpdatePlotBounceAnimation(dt)
    PlotBounceAnimator.Update(plots_, dt)
end

UpdateCameraTargetForPlotDisplay = function()
    PlotDisplayController.UpdateCameraTarget()
end

RefreshSelection = function()
    PlotDisplayController.RefreshSelection()
end

local function SetPlotDisplayMode(mode)
    PlotDisplayController.SetDisplayMode(mode)
end

local function SwitchNextFocusedPlot()
    PlotDisplayController.SwitchNextFocusedPlot()
end

local function ZoomPlantView(direction)
    CameraSystem.AdjustDistance(direction * 0.9, CONFIG.PlantViewMinDistance, CONFIG.PlantViewMaxDistance)
end

ApplyUnlockedPlotCount = function()
    PlotDisplayController.ApplyUnlockedPlotCount()
end

ClearBagPreview = function()
end

local function CreateBagPreview(item)
end

local function CloseBagItemDetail()
    selectedBagItem_ = nil
    ClearBagPreview()
    if RebuildUI ~= nil then RebuildUI() end
end

local function OpenBagItemDetail(item)
    if item == nil then return end
    selectedBagItem_ = item
    CreateBagPreview(item)
    if RebuildUI ~= nil then RebuildUI() end
end


local function ClampToPlot(localPos)
    return CropSystem.ClampToPlot(localPos)
end

local function FindPlantAtLocalPosition(plot, localPos, matureOnly)
    return CropSystem.FindPlantAtLocalPosition(plot, localPos, matureOnly)
end

local function PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    local ok, reason = PlantActionController.PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    if ok then MarkSaveDirty() end
    return ok, reason
end

local function HarvestNearestMature(plotIndex, localPos)
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

local function PlantSeed(plotIndex, plantIndex)
    local ok, reason = PlantActionController.PlantSeed(plotIndex, plantIndex)
    if ok then MarkSaveDirty() end
    return ok, reason
end

local function BuySelectedSeed()
    local ok, reason = PlantActionController.BuySelectedSeed()
    if ok then MarkSaveDirty() end
    return ok, reason
end

local function SellAllHarvested()
    local ok, value = PlantActionController.SellAllHarvested()
    if ok then MarkSaveDirty() end
    return ok, value
end

local function SellBagItem(item)
    local ok, value = PlantActionController.SellBagItem(item)
    if ok then MarkSaveDirty() end
    return ok, value
end

local function SellHarvestedByFilter(filter)
    local ok, value = PlantActionController.SellHarvestedByFilter(filter)
    if ok then MarkSaveDirty() end
    return ok, value
end

local function CountPlotPlants(plot)
    return CropSystem.CountPlotPlants(plot)
end

local function CountMaturePlants(plot)
    return CropSystem.CountMaturePlants(plot)
end

local function GetPlotText(plot)
    return CropSystem.GetPlotText(plot)
end

ShowToast = function(text, silent)
    UIController.ShowToast(text)
end

local function FindNextOwnedSeedIndex(startIndex)
    return PlantActionController.FindNextOwnedSeedIndex(startIndex)
end

local function EnsureSelectedSeedAvailable()
    return PlantActionController.EnsureSelectedSeedAvailable()
end

local function SelectNextOwnedSeedIfEmpty(fromIndex)
    return PlantActionController.SelectNextOwnedSeedIfEmpty(fromIndex)
end

local function SetSelectedSeedIndex(index)
    PlantActionController.SetSelectedSeedIndex(index)
end

local function GetUiRarityColor(rarity)
    local c = RARITY_COLORS[rarity]
    if c == nil then return {200, 200, 200, 255} end
    return { math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), 255 }
end

local function CountPackResults(results)
    return SeedPackSystem.CountResults(results)
end

local function GetFirstAvailablePackId()
    return SeedPackSystem.GetFirstAvailablePackId()
end



local function OpenSeedPack(packId)
    SeedPackOpeningController.OpenPack(packId)
end

local function OpenAllSeedPacks(packId)
    SeedPackOpeningController.OpenAllPacks(packId)
end

ShowAdRewardPrompt = function(title, message, rewardType, extra)
    return AdRewardSystem.ConfirmAndShow({
        title = title,
        message = message,
        onSuccess = function()
            if EconomyCloudSystem.RequestAdReward(rewardType, extra or {}) then
                ShowToast("广告观看完成，正在发放奖励...")
            end
        end,
    })
end

RequestStealAttemptsAdReward = function()
    return AdRewardSystem.Show({
        onSuccess = function()
            if EconomyCloudSystem.RequestAdReward("steal_attempts", {}) then
                ShowToast("广告观看完成，正在发放奖励...")
            end
        end,
    })
end

RequestRareSeedPackAdReward = function()
    return ShowAdRewardPrompt("领取稀有种子包", "观看广告后，获得稀有种子包 x5。", "rare_seed_pack")
end

RequestMaturePlotAdReward = function()
    local socialState = SocialGardenSystem.GetState and SocialGardenSystem.GetState() or {}
    local daily = socialState.daily or {}
    local matureAdCount = math.max(0, math.floor(tonumber(daily.matureAdCount or 0) or 0))
    local matureAdLimit = math.max(5, math.floor(tonumber(daily.matureAdLimit or 5) or 5))
    if matureAdCount >= matureAdLimit then
        ShowToast("今日快速成熟广告已达上限")
        return false
    end
    local plot = plots_[selectedPlot_]
    if plot == nil or plot.plants == nil or #plot.plants == 0 then
        ShowToast("当前地块没有作物")
        return false
    end
    local hasImmature = false
    for _, crop in ipairs(plot.plants) do
        if crop.mature ~= true and crop.harvested ~= true then
            hasImmature = true
            break
        end
    end
    if not hasImmature then
        ShowToast("该地块作物已经成熟")
        return false
    end
    return ShowAdRewardPrompt("全部成熟", "观看广告后，当前地块作物将全部成熟。", "mature_plot", { plotIndex = selectedPlot_ })
end

local function IsInitialUiBlocked()
    if initialUiReady_ then return false end
    if ShowToast ~= nil then ShowToast("正在同步服务器数据，请稍后") end
    EnsureInitialUiReady()
    return true
end

OpenSeedPackHub = function()
    if IsInitialUiBlocked() then return end
    SeedPackOpeningController.OpenHub()
end

local function BuildSeedPackOverlay()
    return SeedPackOpeningController.BuildPackOverlay()
end

local function BuildSeedPackOpeningOverlay()
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


local function PerformPlotAction(plotIndex, localPos)
    PlantActionController.PerformPlotAction(plotIndex, localPos)
end

local function SelectSeedIndex(index)
    PlantActionController.SelectSeedIndex(index)
end

local function SubscribeUIEvents()
    if unsubscribeSocialChanged_ == nil then
        unsubscribeSocialChanged_ = EventBus.On(UIEvents.SOCIAL_CHANGED, function()
            if not SocialView.IsOpen() and RebuildUI ~= nil then
                RebuildUI()
            end
        end)
    end
    if unsubscribeSeedPackChanged_ == nil then
        unsubscribeSeedPackChanged_ = EventBus.On(UIEvents.SEEDPACK_CHANGED, function()
            if SeedPackView.IsOpen() then
                SeedPackView.RebuildModalContent()
            end
            UIController.RefreshInventoryPanels()
            RefreshUI(true)
        end)
    end
    if unsubscribeCommissionChanged_ == nil then
        unsubscribeCommissionChanged_ = EventBus.On(UIEvents.COMMISSION_CHANGED, function()
            if CommissionView.IsOpen() then
                CommissionView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeActivityChanged_ == nil then
        unsubscribeActivityChanged_ = EventBus.On(UIEvents.ACTIVITY_CHANGED, function()
            if ActivityView.IsOpen() then
                ActivityView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeTaskChanged_ == nil then
        unsubscribeTaskChanged_ = EventBus.On(UIEvents.TASK_CHANGED, function()
            if TaskView.IsOpen() then
                TaskView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeTalentChanged_ == nil then
        unsubscribeTalentChanged_ = EventBus.On(UIEvents.TALENT_CHANGED, function(payload)
            if TalentView.IsOpen() then
                local successText = payload ~= nil and payload.successText or nil
                TalentView.RefreshContent(successText)
            end
            RefreshUI(true)
        end)
    end
    if unsubscribeWalletChanged_ == nil then
        unsubscribeWalletChanged_ = EventBus.On(UIEvents.WALLET_CHANGED, function()
            RefreshUI(true)
        end)
    end
    if unsubscribeInventoryChanged_ == nil then
        unsubscribeInventoryChanged_ = EventBus.On(UIEvents.INVENTORY_CHANGED, function()
            if not UIController.RefreshInventoryPanels() and RebuildUI ~= nil then
                RebuildUI()
            end
            RefreshUI(true)
        end)
    end
    if unsubscribeFarmChanged_ == nil then
        unsubscribeFarmChanged_ = EventBus.On(UIEvents.FARM_CHANGED, function()
            if not UIController.RefreshPlantContent() and RebuildUI ~= nil then
                RebuildUI()
            end
            RefreshUI(true)
        end)
    end
    if unsubscribePlayerChanged_ == nil then
        unsubscribePlayerChanged_ = EventBus.On(UIEvents.PLAYER_CHANGED, function()
            if ProfileView.IsOpen() then
                ProfileView.RebuildProfileContent()
            end
            if RebuildUI ~= nil then
                RebuildUI()
            else
                RefreshUI(true)
            end
        end)
    end
end

local function UnsubscribeUIEvents()
    if unsubscribeSocialChanged_ ~= nil then
        unsubscribeSocialChanged_()
        unsubscribeSocialChanged_ = nil
    end
    if unsubscribeSeedPackChanged_ ~= nil then
        unsubscribeSeedPackChanged_()
        unsubscribeSeedPackChanged_ = nil
    end
    if unsubscribeCommissionChanged_ ~= nil then
        unsubscribeCommissionChanged_()
        unsubscribeCommissionChanged_ = nil
    end
    if unsubscribeActivityChanged_ ~= nil then
        unsubscribeActivityChanged_()
        unsubscribeActivityChanged_ = nil
    end
    if unsubscribeTaskChanged_ ~= nil then
        unsubscribeTaskChanged_()
        unsubscribeTaskChanged_ = nil
    end
    if unsubscribeTalentChanged_ ~= nil then
        unsubscribeTalentChanged_()
        unsubscribeTalentChanged_ = nil
    end
    if unsubscribeWalletChanged_ ~= nil then
        unsubscribeWalletChanged_()
        unsubscribeWalletChanged_ = nil
    end
    if unsubscribeInventoryChanged_ ~= nil then
        unsubscribeInventoryChanged_()
        unsubscribeInventoryChanged_ = nil
    end
    if unsubscribeFarmChanged_ ~= nil then
        unsubscribeFarmChanged_()
        unsubscribeFarmChanged_ = nil
    end
    if unsubscribePlayerChanged_ ~= nil then
        unsubscribePlayerChanged_()
        unsubscribePlayerChanged_ = nil
    end
end

local function RegisterModalGuards()
    ModalRegistry.Register("social", function() return SocialView.IsOpen() end)
    ModalRegistry.Register("leaderboard", function() return LeaderboardView.IsOpen() end)
    ModalRegistry.Register("seedPack", function() return SeedPackView.IsOpen() end)
    ModalRegistry.Register("task", function() return TaskView.IsOpen() end)
    ModalRegistry.Register("modelPreview", function() return ModelPreviewSystem.IsOpen() end)
    ModalRegistry.Register("activity", function() return ActivityView.IsOpen() end)
    ModalRegistry.Register("profile", function() return ProfileView.IsOpen() end)
    ModalRegistry.Register("settings", function() return SettingsView.IsOpen() end)
    ModalRegistry.Register("shop", function() return Shop.IsOpen() end)
    ModalRegistry.Register("commission", function() return CommissionView.IsOpen() end)
    ModalRegistry.Register("expansion", function() return ExpansionView.IsOpen() end)
    ModalRegistry.Register("talent", function() return TalentView.IsOpen() end)
    ModalRegistry.Register("bulkSell", function() return BulkSellView.IsOpen() end)
    ModalRegistry.Register("codex", function() return CodexView.IsOpen() end)
end

local function IsInitialDataReady()
    return EconomyCloudSystem.IsInitialSyncReady ~= nil and EconomyCloudSystem.IsInitialSyncReady()
end

EnsureInitialUiReady = function()
    if initialUiReady_ then return true end
    if not IsInitialDataReady() then return false end
    initialUiReady_ = true
    initialUiBuildPending_ = false
    pendingRebuildUI_ = false
    if not initialPlotBounceStarted_ then
        PlotBounceAnimator.StartAll(plots_)
        initialPlotBounceStarted_ = true
    end
    UIController.Rebuild()
    RefreshUI(true)
    if initialSocialSnapshotUploaded_ ~= true then
        SocialGardenSystem.UploadSnapshot()
        initialSocialSnapshotUploaded_ = true
    end
    print("[启动同步] 初始权威数据已同步，显示主界面")
    return true
end

RefreshUI = function(force)
    if not initialUiReady_ then
        initialUiBuildPending_ = true
        return
    end
    UIController.Refresh(force)
end

RebuildUI = function()
    if not initialUiReady_ then
        initialUiBuildPending_ = true
        return
    end
    if ModalRegistry.AnyOpen() then
        pendingRebuildUI_ = true
        return
    end
    pendingRebuildUI_ = false
    UIController.Rebuild()
end

local function FlushPendingRebuildUI()
    if not initialUiReady_ then
        EnsureInitialUiReady()
        return
    end
    if pendingRebuildUI_ and not ModalRegistry.AnyOpen() then
        pendingRebuildUI_ = false
        UIController.Rebuild()
    end
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

local function CycleSeed(delta)
    PlantActionController.CycleSeed(delta)
end

local function RequestSuppressWorldTap()
    suppressNextWorldTap_ = true
    if InteractionSystem ~= nil and InteractionSystem.SuppressNextWorldTap ~= nil then
        InteractionSystem.SuppressNextWorldTap()
    end
end

local function SyncWorldTapSuppression()
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

local function UpdateTouchCameraGesture()
    InteractionSystem.UpdateTouchCameraGesture()
end

local function HandleInput(dt)
    InteractionSystem.HandleInput(dt)
end

UpdateCurrentTourValue = function()
    local value = CropSystem.CalculateTotalSightValue(plots_)
    ProgressionSystem.SetCurrentTourValue(value)
    return value
end

local function UpdatePlants(dt)
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

local function UpdateSeedPackOpening(dt)
    SeedPackOpeningController.Update(dt)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if not initialUiReady_ then
        PlayerSystem.Update(dt)
        EconomyCloudSystem.Update(dt)
        AdRewardSystem.Update(dt)
        SocialGardenSystem.Update(dt)
        LeaderboardSystem.Update(dt)
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
local function GetGardenLevel()
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
    UIController.ShowLoading("正在同步服务器数据...")

    InitMaterials()
    FarmSystem.Init(CONFIG, materials_)
    CreateScene()
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

    UIController.Init({
        config = CONFIG,
        plants = PLANTS,
        seedBag = seedBag_,
        getPlots = function() return plots_ end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedSeed = function() return selectedSeed_ end,
        getSelectedBagItem = function() return selectedBagItem_ end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        getMoney = function() return WalletSystem.GetBalance() end,
        getTourValue = function() return ProgressionSystem.GetTourValue() end,
        getTalentLevel = function() return TalentSystem.GetLevel() end,
        getTalentPoints = function() return TalentSystem.GetTalentPoints() end,
        hasUnlockableTalent = function() return TalentSystem.HasUnlockableTalent() end,
        isFarmView = function() return GetViewMode() == ViewMode.FARM end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        isVisitMode = function() return SocialGardenSystem.IsVisitMode() end,
        returnHome = function() SocialGardenSystem.ReturnHome() end,
        rarityOrder = RARITY_ORDER,
        countSeedPacks = CountSeedPacks,
        countMaturePlants = CountMaturePlants,
        countPlotPlants = CountPlotPlants,
        buildSeedPackOverlay = BuildSeedPackOverlay,
        buildSeedPackOpeningOverlay = BuildSeedPackOpeningOverlay,
        createBagPreview = CreateBagPreview,
    })
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

    SeedPackView.Init({
        plants = PLANTS,
        rarityOrder = RARITY_ORDER,
        seedPackConfig = SEED_PACK_CONFIG,
        seedPacks = seedPacks_,
        getUiRarityColor = GetUiRarityColor,
        countPackResults = CountPackResults,
        countSeedPacks = CountSeedPacks,
        getFirstAvailablePackId = GetFirstAvailablePackId,
        openSeedPack = OpenSeedPack,
        openAllSeedPacks = OpenAllSeedPacks,
        requestRareSeedPackAdReward = RequestRareSeedPackAdReward,
        getAdSeedPackDaily = function()
            local state = SocialGardenSystem.GetState and SocialGardenSystem.GetState() or {}
            local daily = state.daily or {}
            return { count = daily.seedPackAdCount or 0, limit = daily.seedPackAdLimit or 3 }
        end,
        suppressWorldTap = RequestSuppressWorldTap,
        closePackPanel = function() SeedPackOpeningController.ClosePanel() end,
        skipOpening = function() SeedPackOpeningController.SkipOpening() end,
        getSynthesisTarget = function(packId) return InventorySystem.GetSynthesisTarget(packId) end,
        synthesizePack = function(packId)
            local ok = EconomyCloudSystem.SynthesizePack(packId)
            if ok then ShowToast("正在请求服务器合成种子包...") end
            return ok, nil
        end,
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.42, priority = 8 })
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        emitSeedPackChanged = function()
            EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "seed_pack_view" })
        end,
    })

    TaskView.Init({
        dailyTaskConfig = DAILY_TASK_CONFIG,
        dailyTaskState = dailyTaskState_,
        seedPackConfig = SEED_PACK_CONFIG,
        getTaskModal = function() return taskModal_ end,
        setTaskModal = function(modal) taskModal_ = modal end,
        areAllDailyTasksCompleted = AreAllDailyTasksCompleted,
        claimDailyReward = function()
            local ok = EconomyCloudSystem.ClaimDailyReward()
            if ok then ShowToast("正在请求服务器发放每日奖励...") end
            return ok, nil
        end,
        suppressWorldTap = RequestSuppressWorldTap,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    ActivityView.Init({
        plants = PLANTS,
        seedPackConfig = SEED_PACK_CONFIG,
        activityConfig = GameConfig.ACTIVITY_CONFIG,
        getActiveActivity = function() return ActivitySystem.GetActiveActivity() end,
        getActivityState = function(activityId) return ActivitySystem.GetState()[activityId] end,
        getTimeLeftText = function() return ActivitySystem.GetTimeLeftText() end,
        getSweetSubmitItems = function() return ActivitySystem.GetSweetSubmitItems() end,
        submitSweetCrop = function(item)
            local ok = EconomyCloudSystem.SubmitActivityCrop(item)
            if ok then ShowToast("正在请求服务器上交作物...") end
            return ok, ok and nil or "server_required"
        end,
        exchangeSweetReward = function(rewardId)
            local ok = EconomyCloudSystem.ExchangeActivityReward(rewardId)
            if ok then ShowToast("正在请求服务器兑换奖励...") end
            return ok, ok and nil or "server_required"
        end,
        drawAlienPack = function(count)
            local ok = EconomyCloudSystem.DrawActivityPack(count)
            if ok then ShowToast("正在请求服务器抽取奖励...") end
            return ok, ok and nil or "server_required"
        end,
        getLeaderboard = function(activityId) return ActivitySystem.GetLeaderboard(activityId) end,
        suppressWorldTap = RequestSuppressWorldTap,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    SocialView.Init({
        SocialGardenSystem = SocialGardenSystem,
        suppressWorldTap = RequestSuppressWorldTap,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        requestStealAttemptsAdReward = RequestStealAttemptsAdReward,
        showToast = ShowToast,
        onClosed = FlushPendingRebuildUI,
    })

    ModelPreviewView.Init({
        isOpen = function() return ModelPreviewSystem.IsOpen() end,
        openPreview = function() ModelPreviewSystem.Open() end,
        closePreview = function()
            ModelPreviewSystem.Close()
            CameraSystem.EnterFarmView()
            UpdateCameraTargetForPlotDisplay()
        end,
        nextPreview = function() ModelPreviewSystem.Next() end,
        prevPreview = function() ModelPreviewSystem.Prev() end,
        showKind = function(kind) return ModelPreviewSystem.ShowKind(kind) end,
        getCurrentItem = function() return ModelPreviewSystem.GetCurrentItem() end,
        suppressWorldTap = RequestSuppressWorldTap,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    CommissionView.Init({
        seedPackConfig = SEED_PACK_CONFIG,
        getCommissions = function() return CommissionSystem.GetCommissions() end,
        getTimeLeftText = function() return CommissionSystem.GetTimeLeftText() end,
        getRequirementText = function(commission) return CommissionSystem.GetRequirementText(commission) end,
        getMatchingItems = function(commission) return CommissionSystem.GetMatchingHarvestedItems(commission) end,
        completeCommission = function(commission, item)
            local ok = EconomyCloudSystem.CompleteCommission(commission, item)
            RefreshUI(true)
            return ok
        end,
        suppressWorldTap = RequestSuppressWorldTap,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    PlantPanelView.Init({
        plants = PLANTS,
        seedBag = seedBag_,
        harvested = harvested_,
        getHarvestBagCapacity = function() return InventorySystem.GetHarvestBagCapacity() end,
        getHarvestBagMaxCapacity = function() return InventorySystem.GetHarvestBagMaxCapacity() end,
        getSelectedPlot = function() return plots_[selectedPlot_] end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedSeed = function() return selectedSeed_ end,
        setSelectedSeed = SetSelectedSeedIndex,
        getPlantTab = function() return plantTab_ end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        getVisitablePlotIndex = function() return SocialGardenSystem.GetVisitablePlotIndex() end,
        setVisitablePlotIndex = function(plotIndex) return SocialGardenSystem.SetVisitablePlotIndex(plotIndex) end,
        getUiRarityColor = GetUiRarityColor,
        suppressWorldTap = RequestSuppressWorldTap,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshPanel = function()
            UIController.RefreshPlantContent()
        end,
        harvestNearestMature = HarvestNearestMature,
        openBagItemDetail = OpenBagItemDetail,
        openBulkSell = function()
            RequestSuppressWorldTap()
            BulkSellView.Show()
        end,
    })

    BagDetailView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        closeBagItemDetail = CloseBagItemDetail,
        sellBagItem = SellBagItem,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshInventoryPanels = function()
            UIController.RefreshInventoryPanels()
            RefreshUI(true)
        end,
    })

    BulkSellView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        previewSellHarvestedByFilter = function(filter)
            return InventorySystem.PreviewSellHarvestedByFilter(filter)
        end,
        sellHarvestedByFilter = SellHarvestedByFilter,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    CodexView.Init({
        plants = PLANTS,
        collectedPlants = collectedPlants_,
        codexStats = codexStats_,
        suppressWorldTap = RequestSuppressWorldTap,
    })

    MainView.Init({
        isFarmView = function() return GetViewMode() == ViewMode.FARM end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        isVisitMode = function() return SocialGardenSystem.IsVisitMode() end,
        isStealingMode = function() return SocialGardenSystem.IsStealingMode() end,
        getVisitGarden = function() return SocialGardenSystem.GetVisitGarden() end,
        countStealableCrops = function() return SocialGardenSystem.CountStealableCrops() end,
        getMatureVisitCrops = function() return SocialGardenSystem.GetMatureVisitCrops() end,
        getStealChanceText = function(crop) return SocialGardenSystem.GetStealChanceText(crop) end,
        stealVisitCrop = function(index, cropId) SocialGardenSystem.RequestSteal(index, cropId) end,
        getVisitTourValue = function() return SocialGardenSystem.GetVisitTourValue() end,
        getVisitLikeCount = function() return SocialGardenSystem.GetVisitLikeCount() end,
        hasLikedVisitGarden = function() return SocialGardenSystem.HasLikedVisitGarden() end,
        likeVisitGarden = function() SocialGardenSystem.LikeVisitGarden(); if RebuildUI ~= nil then RebuildUI() end end,
        sendFriendRequestToVisitGarden = function()
            local garden = SocialGardenSystem.GetVisitGarden()
            if garden == nil or garden.userId == nil then
                ShowToast("当前花园玩家 ID 无效")
                return false
            end
            return SocialGardenSystem.SendFriendRequest(garden.userId)
        end,
        beginStealingMode = function() SocialGardenSystem.BeginStealingMode() end,
        endStealingMode = function() SocialGardenSystem.EndStealingMode() end,
        getPlantTab = function() return plantTab_ end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getUnlockedPlotCount = function() return unlockedPlotCount_ end,
        getVisitablePlotIndex = function() return SocialGardenSystem.GetVisitablePlotIndex() end,
        setVisitablePlotIndex = function(plotIndex) return SocialGardenSystem.SetVisitablePlotIndex(plotIndex) end,
        setPlantTab = function(tab) plantTab_ = tab end,
        suppressWorldTap = RequestSuppressWorldTap,
        enterPlantView = EnterPlantView,
        enterFarmView = EnterFarmView,
        returnHome = function() SocialGardenSystem.ReturnHome() end,
        openShop = function() Shop.Open() end,
        openCommission = OpenCommissionPanel,
        openSeedPackHub = OpenSeedPackHub,
        openTaskPanel = OpenTaskPanel,
        countSeedPacks = CountSeedPacks,
        getHighestPackIcon = GetHighestPackIcon,
        clearSelectedBagItem = function() selectedBagItem_ = nil end,
        clearBagPreview = function()
            if ClearBagPreview ~= nil then ClearBagPreview() end
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        onTalentOpen = function()
            RequestSuppressWorldTap()
            TalentView.Show()
        end,
        onExpansionOpen = function()
            RequestSuppressWorldTap()
            ExpansionView.Show()
        end,
        onCodexOpen = function()
            RequestSuppressWorldTap()
            CodexView.Show()
        end,
        isExpansionMaxed = function()
            return not ProgressionSystem.CanUnlockNextPlot()
        end,
        getPlantGuideStep = GetPlantGuideStep,
        requestMaturePlotAdReward = RequestMaturePlotAdReward,
    })

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

    ProfileView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        getDisplayName = function() return PlayerSystem.GetDisplayName() end,
        getTapNickname = function() return PlayerSystem.GetTapNickname() end,
        getUserId = function() return PlayerSystem.GetUserId() end,
        getAvatars = function() return PlayerSystem.GetAvatars() end,
        getSelectedAvatar = function() return PlayerSystem.GetSelectedAvatar() end,
        getSelectedAvatarIndex = function() return PlayerSystem.GetSelectedAvatarIndex() end,
        selectAvatar = function(index) return PlayerSystem.SelectAvatar(index) end,
        setNickname = function(name) return PlayerSystem.SetNickname(name) end,
        getLevel = function() return TalentSystem.GetLevel() end,
        getExp = function() return TalentSystem.GetExp() end,
        getExpToNextLevel = function() return TalentSystem.GetExpToNextLevel() end,
        getTourValue = function() return ProgressionSystem.GetTourValue() end,
        getBestTourValue = function() return ProgressionSystem.GetBestTourValue() end,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    SettingsView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        clearSave = ClearGameSave,
        showToast = ShowToast,
        getPlotDisplayMode = function()
            return PlotDisplayController.GetDisplayMode()
        end,
        isPowerSaveMode = function()
            return PlayerSystem.IsPowerSaveMode()
        end,
        setPowerSaveMode = function(enabled)
            return PlayerSystem.SetPowerSaveMode(enabled)
        end,
        isPlantView = function()
            return GetViewMode() == ViewMode.PLANT
        end,
        zoomPlantView = function(direction)
            ZoomPlantView(direction)
        end,
        getFocusedPlotIndex = function()
            return PlotDisplayController.GetFocusedPlotIndex()
        end,
        getUnlockedPlotCount = function()
            return unlockedPlotCount_
        end,
        setPlotDisplayMode = function(mode)
            SetPlotDisplayMode(mode)
        end,
        switchNextPlot = function()
            SwitchNextFocusedPlot()
        end,
        requestMaturePlotAdReward = RequestMaturePlotAdReward,
        onClearSaveSuccess = function()
            SettingsView.Close()
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

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

    TalentView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        unlockTalent = function(talentId)
            return EconomyCloudSystem.UnlockTalent(talentId)
        end,
        showToast = ShowToast,
        onTalentChanged = function()
            MarkSaveDirty()
        end,
    })

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

    ExpansionView.Init({
        suppressWorldTap = RequestSuppressWorldTap,
        getLevel = function()
            return TalentSystem.GetLevel()
        end,
        getGold = function()
            return WalletSystem.GetBalance()
        end,
        getTourValue = function()
            return ProgressionSystem.GetTourValue()
        end,
        expandNextPlot = function()
            local ok = EconomyCloudSystem.ExpandPlot()
            if ok then ShowToast("正在请求服务器扩地...") end
            return ok, ok and nil or "server_required"
        end,
    })

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
        getGold = function() return WalletSystem.GetBalance() end,
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

    LeaderboardView.Init({
        LeaderboardSystem = LeaderboardSystem,
        SocialGardenSystem = SocialGardenSystem,
        getActiveActivityId = function() return ActivitySystem.GetActiveActivityId() end,
        getMyNickname = function() return PlayerSystem.GetDisplayName() end,
        getMyAvatar = function() return PlayerSystem.GetSelectedAvatarProfile() end,
        visitPlayer = function(userId)
            local ok = SocialGardenSystem.VisitPlayer(userId)
            if ok then ActivityView.Close() end
            return ok
        end,
        suppressWorldTap = RequestSuppressWorldTap,
    })

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
    EconomyCloudSystem.RequestCommissions()
    EnsureInitialUiReady()

    RefreshSelection()
    UpdateCamera()
    CreateSkybox()
    SubscribeToEvent("Update", "HandleUpdate")
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
