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

local SceneSystem = require("systems.scene_system")
local CameraSystem = require("systems.camera_system")
local InteractionSystem = require("systems.interaction_system")
local AudioSystem = require("systems.audio_system")
local SeedPackSystem = require("systems.seed_pack_system")
local WalletSystem = require("systems.wallet_system")
local SeedPackView = require("ui.seed_pack_view")
local TaskView = require("ui.task_view")
local PlantPanelView = require("ui.plant_panel_view")
local BagDetailView = require("ui.bag_detail_view")
local MainView = require("ui.main_view")

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Widget|nil
local moneyLabel_ = nil
---@type Widget|nil
local seedLabel_ = nil
---@type Widget|nil
local plotLabel_ = nil
---@type Widget|nil
local actionLabel_ = nil
---@type Widget|nil
local actionButton_ = nil
---@type Widget|nil
local inventoryLabel_ = nil
---@type Widget|nil
local helpLabel_ = nil
---@type Widget|nil
local toastLabel_ = nil
---@type Widget|nil
local seedPackBadgeLabel_ = nil
local seedButtons_ = {}

local CONFIG = GameConfig.CONFIG
local RARITY_COLORS = GameConfig.RARITY_COLORS
local PLANTS = GameConfig.PLANTS
local RARITY_ORDER = GameConfig.RARITY_ORDER
local RARITY_PLANT_INDICES = GameConfig.RARITY_PLANT_INDICES
local SEED_PACK_CONFIG = GameConfig.SEED_PACK_CONFIG
local SILVER_PACK_BY_RARITY = GameConfig.SILVER_PACK_BY_RARITY
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
local silverRewardClaimed_ = inventoryState_.silverRewardClaimed
local dailyTaskState_ = inventoryState_.dailyTaskState
local seedPackModal_ = nil
local taskModal_ = nil
local seedPackReveal_ = nil
local seedPackPanelOpen_ = false
local seedPackResultTitle_ = nil
local seedPackResultItems_ = nil
local selectedBagItem_ = nil
local ViewMode = CameraSystem.ViewMode
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local uiRefreshTimer_ = 0
local uiInitialized_ = false
local plantTab_ = "seed"  -- "seed" | "harvest" | "bag"
local gameTime_ = 0
local toastTimer_ = 0
local suppressNextWorldTap_ = false
local RefreshUI = nil
local ShowToast = nil
local RebuildUI = nil
local SelectPlotByDelta = nil
local ClearBagPreview = nil
local OpenSeedPackHub = nil
local OpenTaskPanel = nil

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
    CameraSystem.EnterPlantView()
    ShowToast("进入种植模式，点击田地播种或收获")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function EnterFarmView()
    CameraSystem.EnterFarmView()
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

local function RefreshSelection()
    FarmSystem.RefreshSelection(plots_, selectedPlot_)
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
    return CropSystem.PlantSeedAt(plots_, plotIndex, plantIndex, centerLocalPos)
end

local function HarvestNearestMature(plotIndex, localPos)
    return CropSystem.HarvestNearestMature(plots_, plotIndex, localPos)
end

local function PlantSeed(plotIndex, plantIndex)
    return PlantSeedAt(plotIndex, plantIndex, Vector3(0, 0, 0))
end

local function BuySelectedSeed()
    local plant = PLANTS[selectedSeed_]
    if not WalletSystem.Spend(plant.seedPrice) then
        print("金币不足，无法购买: " .. plant.name)
        return false
    end
    AddSeedToBag(selectedSeed_, 1, 0)
    print("购买种子: " .. plant.name .. "，剩余金币 " .. WalletSystem.GetBalance())
    return true
end

local function SellAllHarvested()
    local total = InventorySystem.SellAllHarvested()
    if total > 0 then
        selectedBagItem_ = nil
        if ClearBagPreview ~= nil then
            ClearBagPreview()
        end
        WalletSystem.Add(total)
    end
    return total
end

local function SellBagItem(item)
    local earned = InventorySystem.SellBagItem(item)
    if earned > 0 then
        selectedBagItem_ = nil
        if ClearBagPreview ~= nil then
            ClearBagPreview()
        end
        WalletSystem.Add(earned)
    end
    return earned
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
    toastTimer_ = 2.0
    if toastLabel_ ~= nil then
        toastLabel_:SetText(text)
    end
    print(text)
end

local function RefreshSeedButtons()
    for i, button in ipairs(seedButtons_) do
        local plant = PLANTS[i]
        local owned = seedBag_[i] or 0
        if i == selectedSeed_ then
            button:SetText(string.format("%s  x%d", plant.name, owned))
        else
            button:SetText(string.format("%s\n%d金", plant.name, plant.seedPrice))
        end
    end
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

local function OpenSeedPackResultModal(title, results)
    seedPackPanelOpen_ = false
    seedPackResultTitle_ = title
    seedPackResultItems_ = results
    if RebuildUI ~= nil then RebuildUI() end
end

local function OpenSeedPack(packId, packCount)
    local results, err, title = SeedPackSystem.OpenPack(packId, packCount)
    if results == nil then
        if err ~= nil then
            ShowToast(err)
        end
        return
    end
    RefreshUI(true)
    OpenSeedPackResultModal(title, results)
end

OpenSeedPackHub = function()
    if CountSeedPacks() <= 0 then
        ShowToast("暂无可开启的种子包")
        return
    end
    seedPackResultTitle_ = nil
    seedPackResultItems_ = nil
    seedPackPanelOpen_ = true
    if RebuildUI ~= nil then RebuildUI() end
end

local function BuildSeedPackOverlay()
    return SeedPackView.BuildPackOverlay(seedPackPanelOpen_)
end

local function BuildSeedPackResultOverlay()
    return SeedPackView.BuildResultOverlay(seedPackResultTitle_, seedPackResultItems_)
end

OpenTaskPanel = function()
    TaskView.Open()
end


local function PerformPlotAction(plotIndex, localPos)
    selectedPlot_ = plotIndex
    RefreshSelection()
    local plot = plots_[selectedPlot_]
    if plot == nil then return end

    if not plot.unlocked then
        ShowToast("这块田地尚未解锁")
        RefreshUI(true)
        return
    end

    if GetViewMode() ~= ViewMode.PLANT then
        ShowToast("当前是查看状态，请先点击下方“开始种植”")
        RefreshUI(true)
        return
    end

    -- 根据当前 Tab 决定操作
    if plantTab_ == "seed" then
        -- 播种模式：点击土地播种
        if CountPlotPlants(plot) >= CONFIG.MaxCropsPerPlot then
            ShowToast("这块田地已满")
        elseif PlantSeedAt(selectedPlot_, selectedSeed_, localPos or Vector3(0, 0, 0)) then
            ShowToast("已播种 " .. PLANTS[selectedSeed_].name)
        else
            ShowToast("没有该种子，前往商店购买")
        end
    elseif plantTab_ == "harvest" then
        -- 收获模式：点击成熟作物收获
        if CountMaturePlants(plot) <= 0 then
            ShowToast("当前地块暂无成熟作物")
        else
            local crop = nil
            if localPos ~= nil then
                crop = FindPlantAtLocalPosition(plot, localPos, true)
            end
            if crop ~= nil then
                local cropName = crop.name
                if HarvestNearestMature(selectedPlot_, localPos) then
                    ShowToast("收获 " .. cropName)
                end
            else
                if HarvestNearestMature(selectedPlot_, nil) then
                    ShowToast("收获成功")
                end
            end
        end
    else
        ShowToast("切换到播种或收获进行操作")
    end
    if RebuildUI then RebuildUI() end
end

local function SelectSeedIndex(index)
    selectedSeed_ = Clamp(index, 1, #PLANTS)
    ShowToast("已选择 " .. PLANTS[selectedSeed_].name)
    RefreshUI(true)
end

RefreshUI = function(force)
    uiRefreshTimer_ = uiRefreshTimer_ + 0.016
    if not force and uiRefreshTimer_ < 0.1 then return end
    uiRefreshTimer_ = 0

    local seed = PLANTS[selectedSeed_]
    local owned = seedBag_[selectedSeed_] or 0
    local selectedPlot = plots_[selectedPlot_]
    local actionText = ""
    if GetViewMode() == ViewMode.FARM then
        actionText = "点击田地查看状态，点击下方按钮开始种植"
    elseif selectedPlot ~= nil and CountMaturePlants(selectedPlot) > 0 then
        actionText = "点击成熟作物收获，点击空位继续播种"
    elseif selectedPlot ~= nil and CountPlotPlants(selectedPlot) < CONFIG.MaxCropsPerPlot then
        actionText = "点击田地播种，种子会在附近散开"
    else
        actionText = "田地已满，等待成熟后收获"
    end

    if moneyLabel_ ~= nil then
        moneyLabel_:SetText("金币 " .. WalletSystem.GetBalance())
    end
    if seedLabel_ ~= nil then
        seedLabel_:SetText("观光 0")  -- 观光值暂未实装
    end
    if plotLabel_ ~= nil then
        plotLabel_:SetText("LV" .. unlockedPlotCount_)
    end
    if helpLabel_ ~= nil then
        helpLabel_:SetText(string.format("已解锁区域 %d/%d", unlockedPlotCount_, #plots_))
    end
    if actionButton_ ~= nil then
        if GetViewMode() == ViewMode.FARM then
            actionButton_:SetText("开始种植")
        else
            actionButton_:SetText("返回花园")
        end
    end
    if seedPackBadgeLabel_ ~= nil then
        seedPackBadgeLabel_:SetText(tostring(CountSeedPacks()))
    end
    RefreshSeedButtons()
end

local function BuildPlantTabContent()
    return PlantPanelView.BuildContent()
end

RebuildUI = function()
    local previewItem = selectedBagItem_

    local ACNHTheme = require("ui_theme_acnh")

    if not uiInitialized_ then
        UI.Init({
            theme = ACNHTheme.theme,
            fonts = {
                { family = "sans", weights = {
                    normal = "Fonts/ResourceHanRoundedCN-Bold.ttf",
                    bold = "Fonts/ResourceHanRoundedCN-Bold.ttf",
                } },
            },
            scale = UI.Scale.DEFAULT,
        })
        uiInitialized_ = true
    end

    local labels = MainView.CreateLabels()
    moneyLabel_ = labels.moneyLabel
    seedLabel_ = labels.seedLabel
    seedPackBadgeLabel_ = labels.seedPackBadgeLabel
    plotLabel_ = labels.plotLabel
    actionLabel_ = labels.actionLabel
    inventoryLabel_ = labels.inventoryLabel
    toastLabel_ = labels.toastLabel
    helpLabel_ = labels.helpLabel

    local root = MainView.BuildRoot(labels, {
        plantContent = BuildPlantTabContent(),
        bagDetail = BagDetailView.Build(selectedBagItem_, GetViewMode() == ViewMode.PLANT),
        seedPackOverlay = BuildSeedPackOverlay(),
        seedPackResultOverlay = BuildSeedPackResultOverlay(),
    })
    actionButton_ = labels.actionButton
    UI.SetRoot(root)
    if previewItem ~= nil then
        CreateBagPreview(previewItem)
    end
    RefreshUI(true)
end

SelectPlotByDelta = function(dx, dz)
    local col = ((selectedPlot_ - 1) % CONFIG.GridCols) + 1
    local row = math.floor((selectedPlot_ - 1) / CONFIG.GridCols) + 1
    col = Clamp(col + dx, 1, CONFIG.GridCols)
    row = Clamp(row + dz, 1, CONFIG.GridRows)
    selectedPlot_ = (row - 1) * CONFIG.GridCols + col
    RefreshSelection()
    RefreshUI(true)
end

local function CycleSeed(delta)
    selectedSeed_ = selectedSeed_ + delta
    if selectedSeed_ < 1 then selectedSeed_ = #PLANTS end
    if selectedSeed_ > #PLANTS then selectedSeed_ = 1 end
    RefreshUI(true)
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

local function UpdatePlants(dt)
    CropSystem.UpdatePlants(plots_, dt)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    HandleInput(dt)
    UpdateTouchCameraGesture()
    UpdatePlants(dt)
    Shop.Update(dt)

    if toastTimer_ > 0 then
        toastTimer_ = toastTimer_ - dt
        if toastTimer_ <= 0 and toastLabel_ ~= nil then
            if GetViewMode() == ViewMode.FARM then
                toastLabel_:SetText("当前为查看状态，点击下方开始种植")
            else
                toastLabel_:SetText("种植模式：点击田地播种或收获")
            end
        end
    end
    RefreshUI(false)
end

--- 获取花园等级（基于解锁田地数）
local function GetGardenLevel()
    -- 等级规则：每解锁1块田地 = 1级，初始1级
    return math.max(1, unlockedPlotCount_)
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
    unlockedPlotCount_ = ProgressionSystem.GetUnlockedPlotCount()
    CreateFarm()

    WalletSystem.Init(CONFIG.StartMoney)
    InventorySystem.Init(GameConfig, {
        showToast = ShowToast,
    })

    SeedPackSystem.Init(GameConfig, InventorySystem)

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
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        closePackPanel = function() seedPackPanelOpen_ = false end,
        closeResultPanel = function()
            seedPackResultTitle_ = nil
            seedPackResultItems_ = nil
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    TaskView.Init({
        dailyTaskConfig = DAILY_TASK_CONFIG,
        dailyTaskState = dailyTaskState_,
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

    PlantPanelView.Init({
        plants = PLANTS,
        seedBag = seedBag_,
        harvested = harvested_,
        getSelectedPlot = function() return plots_[selectedPlot_] end,
        getSelectedPlotIndex = function() return selectedPlot_ end,
        getSelectedSeed = function() return selectedSeed_ end,
        setSelectedSeed = function(seedIndex) selectedSeed_ = seedIndex end,
        getPlantTab = function() return plantTab_ end,
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
        harvestNearestMature = HarvestNearestMature,
        openBagItemDetail = OpenBagItemDetail,
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

    MainView.Init({
        isFarmView = function() return GetViewMode() == ViewMode.FARM end,
        isPlantView = function() return GetViewMode() == ViewMode.PLANT end,
        getPlantTab = function() return plantTab_ end,
        setPlantTab = function(tab) plantTab_ = tab end,
        suppressWorldTap = function() suppressNextWorldTap_ = true end,
        enterPlantView = EnterPlantView,
        enterFarmView = EnterFarmView,
        openShop = function() Shop.Open() end,
        openSeedPackHub = OpenSeedPackHub,
        openTaskPanel = OpenTaskPanel,
        countSeedPacks = CountSeedPacks,
        clearSelectedBagItem = function() selectedBagItem_ = nil end,
        clearBagPreview = function()
            if ClearBagPreview ~= nil then ClearBagPreview() end
        end,
        rebuildUI = function()
            if RebuildUI ~= nil then RebuildUI() end
        end,
    })

    CropSystem.Init(GameConfig, {
        InventorySystem = InventorySystem,
        PlantVisual = PlantVisual,
        SeedVisual = SeedVisual,
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
    })

    AddSeedToBag(1, 4, 0)
    AddSeedToBag(2, 2, 0)
    AddSeedToBag(3, 1, 0)
    AddSeedPack("daily_basic", 3)
    AddSeedPack("silver_common", 2)
    AddSeedPack("silver_uncommon", 1)
    AddSeedPack("silver_rare", 1)

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
    print("已赠送胡萝卜x4、番茄x2、草莓x1，以及测试种子包：日常x3、银质普通x2、银质罕见x1、银质稀有x1。")
end

function Stop()
    UI.Shutdown()
end
