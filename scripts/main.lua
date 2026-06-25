require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
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
local SeedPackOpeningController = require("controllers.seed_pack_opening_controller")
local ExpansionController = require("controllers.expansion_controller")
local PlotDisplayController = require("controllers.plot_display_controller")
local UIController = require("controllers.ui_controller")
local PlantActionController = require("controllers.plant_action_controller")
local WalletSystem = require("systems.wallet_system")
local TalentSystem = require("systems.talent_system")
local PlayerSystem = require("systems.player_system")
local TalentView = require("ui.talent_view")
local ExpansionView = require("ui.expansion_view")
local SeedPackView = require("ui.seed_pack_view")
local TaskView = require("ui.task_view")
local CommissionView = require("ui.commission_view")
local CodexView = require("ui.codex_view")
local PlantPanelView = require("ui.plant_panel_view")
local BagDetailView = require("ui.bag_detail_view")
local MainView = require("ui.main_view")
local ProfileView = require("ui.profile_view")
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
local RARITY_PLANT_INDICES = GameConfig.RARITY_PLANT_INDICES
local SEED_PACK_CONFIG = GameConfig.SEED_PACK_CONFIG
local SEED_PACK_BY_RARITY = GameConfig.SEED_PACK_BY_RARITY
local DAILY_TASK_CONFIG = GameConfig.DAILY_TASK_CONFIG
local SEED_STACK_MAX = GameConfig.SEED_STACK_MAX
local COLOR_MUTATIONS = GameConfig.COLOR_MUTATIONS
local SPECIAL_MUTATIONS = GameConfig.SPECIAL_MUTATIONS

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
local codexStats_ = inventoryState_.codexStats
local silverRewardClaimed_ = inventoryState_.silverRewardClaimed
local dailyTaskState_ = inventoryState_.dailyTaskState
local taskModal_ = nil
local selectedBagItem_ = nil
local ViewMode = CameraSystem.ViewMode
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local plantTab_ = "seed"  -- "seed" | "harvest" | "bag"
local gameTime_ = 0
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

local function RandItem(list)
    return list[math.random(1, #list)]
end

local function RandomRange(minValue, maxValue)
    return minValue + math.random() * (maxValue - minValue)
end

local function RollCropWeightScale()
    local r = math.random()
    if r < 0.25 then
        return RandomRange(0.45, 0.8), "Light"
    elseif r < 0.80 then
        return RandomRange(0.8, 1.25), "Normal"
    elseif r < 0.97 then
        return RandomRange(1.25, 2.5), "Large"
    end
    return RandomRange(3.0, 6.0), "Giant"
end

local function GetWeightBonusForPlot(plotIndex)
    return 1.0
end

local function AddSeedToBag(plantIndex, count, buff)
    return InventorySystem.AddSeedToBag(plantIndex, count, buff)
end

local function RemoveSeedFromBag(plantIndex)
    return InventorySystem.RemoveSeedFromBag(plantIndex)
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
    return InventorySystem.AddSeedPack(packId, count)
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

local function HasSpecial(mutation, key)
    return PlantVisual.HasSpecial(mutation, key)
end

local function CreateMaterial(name, color, metallic, roughness, emissive)
    return PlantVisual.CreateMaterial(name, color, metallic, roughness, emissive)
end

local function CreateTransparentMaterial(name, color)
    return PlantVisual.CreateTransparentMaterial(name, color)
end

local function CreateUnlitMaterial(name, color)
    return PlantVisual.CreateUnlitMaterial(name, color)
end

local function AddModel(parent, name, modelPath, position, scale, material)
    return PlantVisual.AddModel(parent, name, modelPath, position, scale, material)
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

local function EnterPlantView()
    selectedPlot_ = Clamp(selectedPlot_, 1, math.max(1, unlockedPlotCount_))
    CameraSystem.SetTarget(FarmSystem.PlotWorldPosition(selectedPlot_))
    CameraSystem.EnterPlantView()
    RefreshSelection()
    ShowToast(string.format("进入第 %d 块地种植模式", selectedPlot_))
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
    ShowToast("自由查看农场")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function PlotWorldPosition(index)
    return FarmSystem.PlotWorldPosition(index)
end

local function CreateFarm()
    plots_ = FarmSystem.CreateFarm(scene_, unlockedPlotCount_)
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

local function ApplyUnlockedPlotCount()
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
    return PlantActionController.PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
end

local function HarvestNearestMature(plotIndex, localPos)
    local success, harvestInfo = PlantActionController.HarvestNearestMature(plotIndex, localPos)
    if success then
        local cropName = harvestInfo and harvestInfo.name or "作物"
        local exp = harvestInfo and harvestInfo.exp or 0
        local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
        ShowToast(text)
        FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
    end
    return success, harvestInfo
end

local function PlantSeed(plotIndex, plantIndex)
    return PlantActionController.PlantSeed(plotIndex, plantIndex)
end

local function BuySelectedSeed()
    return PlantActionController.BuySelectedSeed()
end

local function SellAllHarvested()
    return PlantActionController.SellAllHarvested()
end

local function SellBagItem(item)
    return PlantActionController.SellBagItem(item)
end

local function SellHarvestedByFilter(filter)
    return PlantActionController.SellHarvestedByFilter(filter)
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

ShowToast = function(text)
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

OpenSeedPackHub = function()
    SeedPackOpeningController.OpenHub()
end

local function BuildSeedPackOverlay()
    return SeedPackOpeningController.BuildPackOverlay()
end

local function BuildSeedPackOpeningOverlay()
    return SeedPackOpeningController.BuildOpeningOverlay()
end

OpenTaskPanel = function()
    TaskView.Open()
end

OpenCommissionPanel = function()
    CommissionView.Show()
end

ExpandNextPlot = function()
    return ExpansionController.ExpandNextPlot()
end


local function PerformPlotAction(plotIndex, localPos)
    PlantActionController.PerformPlotAction(plotIndex, localPos)
end

local function SelectSeedIndex(index)
    PlantActionController.SelectSeedIndex(index)
end

RefreshUI = function(force)
    UIController.Refresh(force)
end

RebuildUI = function()
    UIController.Rebuild()
end

SelectPlotByDelta = function(dx, dz)
    PlotDisplayController.SelectPlotByDelta(dx, dz)
end

local function CycleSeed(delta)
    PlantActionController.CycleSeed(delta)
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

local function UpdateCurrentTourValue()
    local value = CropSystem.CalculateTotalSightValue(plots_)
    ProgressionSystem.SetCurrentTourValue(value)
    return value
end

local function UpdatePlants(dt)
    local maturedThisFrame = CropSystem.UpdatePlants(plots_, dt)
    UpdateCurrentTourValue()
    if maturedThisFrame and plantTab_ == "harvest" and GetViewMode() == ViewMode.PLANT and RebuildUI ~= nil then
        RebuildUI()
    end
end

local function UpdateSeedPackOpening(dt)
    SeedPackOpeningController.Update(dt)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    HandleInput(dt)
    UpdateTouchCameraGesture()
    UpdatePlotBounceAnimation(dt)
    UpdatePlants(dt)
    UpdateSeedPackOpening(dt)
    Shop.Update(dt)
    CommissionSystem.Update(dt)
    FloatingToast.Update(dt)

    UIController.Update(dt)
    RefreshUI(false)
end

--- 获取花园等级（基于玩家当前等级）
local function GetGardenLevel()
    return TalentSystem.GetLevel()
end

function InitBGM()
    AudioSystem.InitBGM(scene_)
end

function HandleSoundFinished(eventType, eventData)
    AudioSystem.HandleSoundFinished(eventData)
end

function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title
    math.randomseed(os.time())

    InitMaterials()
    FarmSystem.Init(CONFIG, materials_)
    CreateScene()
    ProgressionSystem.Init(CONFIG)
    PlayerSystem.Init({
        onChanged = function()
            if ProfileView.IsOpen() then return end
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })
    unlockedPlotCount_ = ProgressionSystem.GetUnlockedPlotCount()
    CreateFarm()
    PlantActionController.Init({
        config = CONFIG,
        plants = PLANTS,
        seedBag = seedBag_,
        CropSystem = CropSystem,
        InventorySystem = InventorySystem,
        WalletSystem = WalletSystem,
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
        isFarmView = function() return GetViewMode() == ViewMode.FARM end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        countSeedPacks = CountSeedPacks,
        countMaturePlants = CountMaturePlants,
        countPlotPlants = CountPlotPlants,
        buildSeedPackOverlay = BuildSeedPackOverlay,
        buildSeedPackOpeningOverlay = BuildSeedPackOpeningOverlay,
        createBagPreview = CreateBagPreview,
    })
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
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        refreshUI = RefreshUI,
    })
    StartPlotBounceAnimation()
    ApplyUnlockedPlotCount()

    WalletSystem.Init(CONFIG.StartMoney)
    InventorySystem.Init(GameConfig, {
        showToast = ShowToast,
        showFloatingToast = function(text)
            FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 5 })
        end,
        getHarvestBagBonus = function()
            return TalentSystem.GetBonus("bagCapacity")
        end,
    })

    SeedPackSystem.Init(GameConfig, InventorySystem)
    CommissionSystem.Init(GameConfig, InventorySystem, {
        showToast = ShowToast,
        onRefresh = function()
            print("[委托] 新委托已刷新")
        end,
    })
    SeedPackOpeningController.Init({
        countSeedPacks = CountSeedPacks,
        showToast = ShowToast,
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
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        closePackPanel = function() SeedPackOpeningController.ClosePanel() end,
        skipOpening = function() SeedPackOpeningController.SkipOpening() end,
        getSynthesisTarget = function(packId) return InventorySystem.GetSynthesisTarget(packId) end,
        synthesizePack = function(packId) return InventorySystem.SynthesizePack(packId) end,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    TaskView.Init({
        dailyTaskConfig = DAILY_TASK_CONFIG,
        dailyTaskState = dailyTaskState_,
        seedPackConfig = SEED_PACK_CONFIG,
        getTaskModal = function() return taskModal_ end,
        setTaskModal = function(modal) taskModal_ = modal end,
        areAllDailyTasksCompleted = AreAllDailyTasksCompleted,
        claimDailyReward = function() return InventorySystem.ClaimDailyReward() end,
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        showToast = ShowToast,
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
            local ok = CommissionSystem.CompleteCommission(commission, item)
            RefreshUI(true)
            return ok
        end,
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
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
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        harvestNearestMature = HarvestNearestMature,
        openBagItemDetail = OpenBagItemDetail,
        openBulkSell = function()
            suppressNextWorldTap_ = true
            BulkSellView.Show()
        end,
    })

    BagDetailView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        closeBagItemDetail = CloseBagItemDetail,
        sellBagItem = SellBagItem,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    BulkSellView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
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
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
    })

    MainView.Init({
        isFarmView = function() return GetViewMode() == ViewMode.FARM end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        getPlantTab = function() return plantTab_ end,
        setPlantTab = function(tab) plantTab_ = tab end,
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        enterPlantView = EnterPlantView,
        enterFarmView = EnterFarmView,
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
            suppressNextWorldTap_ = true
            TalentView.Show()
        end,
        onExpansionOpen = function()
            suppressNextWorldTap_ = true
            ExpansionView.Show()
        end,
        onCodexOpen = function()
            suppressNextWorldTap_ = true
            CodexView.Show()
        end,
        isExpansionMaxed = function()
            return not ProgressionSystem.CanUnlockNextPlot()
        end,
    })

    ProfileView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        getDisplayName = function() return PlayerSystem.GetDisplayName() end,
        getTapNickname = function() return PlayerSystem.GetTapNickname() end,
        getUserId = function() return PlayerSystem.GetUserId() end,
        getAvatars = function() return PlayerSystem.GetAvatars() end,
        getSelectedAvatar = function() return PlayerSystem.GetSelectedAvatar() end,
        getSelectedAvatarIndex = function() return PlayerSystem.GetSelectedAvatarIndex() end,
        selectAvatar = function(index) PlayerSystem.SelectAvatar(index) end,
        setNickname = function(name) return PlayerSystem.SetNickname(name) end,
        getLevel = function() return TalentSystem.GetLevel() end,
        getExp = function() return TalentSystem.GetExp() end,
        getExpToNextLevel = function() return TalentSystem.GetExpToNextLevel() end,
        getTourValue = function() return ProgressionSystem.GetTourValue() end,
        showToast = ShowToast,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    SettingsView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        getPlotDisplayMode = function()
            return PlotDisplayController.GetDisplayMode()
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
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    TalentSystem.Init({
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
        spendGold = function(amount)
            WalletSystem.Spend(amount)
        end,
    })

    TalentView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        onTalentChanged = function()
            -- 天赋变更后刷新UI
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
    })

    ExpansionView.Init({
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
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
            return ExpandNextPlot()
        end,
    })

    CropSystem.Init(GameConfig, {
        InventorySystem = InventorySystem,
        PlantVisual = PlantVisual,
        SeedVisual = SeedVisual,
        TalentSystem = TalentSystem,
        showToast = ShowToast,
    })

    -- 初始化商店系统
    Shop.Init({
        PLANTS = PLANTS,
        getMoney = function() return WalletSystem.GetBalance() end,
        getGardenLevel = GetGardenLevel,
        onBuy = function(cost, plantIndex)
            WalletSystem.Spend(cost)
            if plantIndex ~= nil then
                AddSeedToBag(plantIndex, 1, 0)
            end
            RefreshUI(true)
        end,
        showToast = ShowToast,
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
        performPlotAction = PerformPlotAction,
        selectPlotByDelta = SelectPlotByDelta,
        cycleSeed = CycleSeed,
        buySelectedSeed = BuySelectedSeed,
        sellAllHarvested = SellAllHarvested,
        enterPlantView = EnterPlantView,
        countMaturePlants = CountMaturePlants,
        countPlotPlants = CountPlotPlants,
        harvestNearestMature = HarvestNearestMature,
        plantSeed = PlantSeed,
        isUIBlocking = function()
            return ProfileView.IsOpen() or SettingsView.IsOpen() or Shop.IsOpen() or CommissionView.IsOpen() or ExpansionView.IsOpen() or TalentView.IsOpen() or BulkSellView.IsOpen() or CodexView.IsOpen()
        end,
    })

    AddSeedToBag(1, 6, 0)
    AddSeedToBag(21, 4, 0)
    AddSeedToBag(2, 2, 0)
    AddSeedPack("pack_common", 1)

    RebuildUI()
    RefreshUI(true)

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
    print("已赠送胡萝卜x6、玉米x4、番茄x2，以及普通种子包x1。")
end

function Stop()
    UI.Shutdown()
end
