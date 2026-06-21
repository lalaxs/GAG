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
local money_ = CONFIG.StartMoney
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
    if money_ < plant.seedPrice then
        print("金币不足，无法购买: " .. plant.name)
        return false
    end
    money_ = money_ - plant.seedPrice
    AddSeedToBag(selectedSeed_, 1, 0)
    print("购买种子: " .. plant.name .. "，剩余金币 " .. money_)
    return true
end

local function SellAllHarvested()
    local total = InventorySystem.SellAllHarvested()
    if total > 0 then
        selectedBagItem_ = nil
        if ClearBagPreview ~= nil then
            ClearBagPreview()
        end
        money_ = money_ + total
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
        money_ = money_ + earned
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
    return InventorySystem.CountPackResults(results)
end

local function CanReceivePackResults(results)
    return InventorySystem.CanReceivePackResults(results)
end

local function BuildSeedPackResults(packCfg, packCount)
    return InventorySystem.BuildSeedPackResults(packCfg, packCount)
end

local function ApplyPackResults(results)
    InventorySystem.ApplyPackResults(results)
end

local function GetFirstAvailablePackId()
    return InventorySystem.GetFirstAvailablePackId()
end

local function BuildResultCards(results)
    local cards = {}
    local counts = CountPackResults(results)
    local sorted = {}
    for seedId, count in pairs(counts) do
        table.insert(sorted, seedId)
    end
    table.sort(sorted, function(a, b)
        local ra = RARITY_ORDER[PLANTS[a].rarity] or 1
        local rb = RARITY_ORDER[PLANTS[b].rarity] or 1
        if ra == rb then return a < b end
        return ra < rb
    end)

    for _, seedId in ipairs(sorted) do
        local plant = PLANTS[seedId]
        local plantName = plant.name
        local rarity = plant.rarity
        local count = counts[seedId] or 0
        local rarityColor = GetUiRarityColor(rarity)
        local newFlag = false
        local silverFlag = false
        for _, result in ipairs(results) do
            if result.seedId == seedId then
                newFlag = newFlag or result.isNew
                silverFlag = silverFlag or result.seedBuff > 0
            end
        end
        table.insert(cards, UI.Panel {
            width = "46%",
            minHeight = 104,
            padding = 8,
            marginBottom = 8,
            alignItems = "center",
            backgroundColor = silverFlag and {245, 248, 255, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = silverFlag and 3 or 2,
            borderColor = silverFlag and {190, 195, 215, 255} or rarityColor,
            children = {
                UI.Panel {
                    width = 50,
                    height = 44,
                    marginBottom = 4,
                    backgroundImage = string.format("image/icons_3d/seed (%d).png", seedId),
                    backgroundFit = "contain",
                },
                UI.Label { text = string.format("%s x%d", plantName, count), fontSize = 12, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center" },
                UI.Label { text = rarity, fontSize = 10, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" },
                newFlag and UI.Label { text = "新品", fontSize = 10, fontWeight = "bold", fontColor = {220, 55, 45, 255}, textAlign = "center" } or UI.Panel { height = 0 },
                silverFlag and UI.Label { text = "银种 +1%", fontSize = 9, fontColor = {90, 100, 130, 255}, textAlign = "center" } or UI.Panel { height = 0 },
            },
        })
    end
    return cards
end

local function OpenSeedPackResultModal(title, results)
    seedPackPanelOpen_ = false
    seedPackResultTitle_ = title
    seedPackResultItems_ = results
    if RebuildUI ~= nil then RebuildUI() end
end

local function OpenSeedPack(packId, packCount)
    local cfg = SEED_PACK_CONFIG[packId]
    if cfg == nil then return end
    local owned = seedPacks_[packId] or 0
    packCount = math.min(packCount or 1, owned)
    local results, err = InventorySystem.OpenSeedPack(packId, packCount)
    if results == nil then
        if err ~= nil then
            ShowToast(err)
        end
        return
    end
    RefreshUI(true)
    OpenSeedPackResultModal(packCount > 1 and (cfg.packName .. " x" .. packCount) or cfg.packName, results)
end

local function BuildSeedPackRows()
    local rows = {}
    for packId, cfg in pairs(SEED_PACK_CONFIG) do
        local owned = seedPacks_[packId] or 0
        if owned > 0 then
            table.insert(rows, UI.Panel {
                flexDirection = "column",
                alignItems = "stretch",
                padding = 8,
                marginBottom = 8,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 14,
                borderWidth = 2,
                borderColor = cfg.themeColor,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Panel {
                                width = 42,
                                height = 42,
                                marginRight = 8,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = cfg.themeColor,
                                borderRadius = 12,
                                children = { UI.Label { text = cfg.seedBuff > 0 and "银" or "袋", fontSize = 18, fontWeight = "bold", fontColor = {255, 255, 255, 255} } },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                gap = 2,
                                children = {
                                    UI.Label { text = cfg.packName .. " x" .. owned, fontSize = 14, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                    UI.Label { text = cfg.getWay .. " | 每包 " .. cfg.onceOpenCount .. " 颗种子", fontSize = 10, fontColor = {120, 100, 80, 220} },
                                },
                            },
                        },
                    },
                    cfg.seedBuff > 0 and UI.Label { text = "银质种子：播种时体型/颜色/特殊变异概率 +1%", fontSize = 10, fontColor = {90, 100, 130, 240}, marginBottom = 6 } or UI.Panel { height = 0 },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button { text = "开1包", flexGrow = 1, height = 32, fontSize = 12, variant = "primary", onClick = function() suppressNextWorldTap_ = true; OpenSeedPack(packId, 1) end },
                            UI.Button { text = "全开", flexGrow = 1, height = 32, fontSize = 12, variant = "secondary", onClick = function() suppressNextWorldTap_ = true; OpenSeedPack(packId, owned) end },
                        },
                    },
                },
            })
        end
    end
    if #rows == 0 then
        table.insert(rows, UI.Label { text = "暂无可开启的种子包", fontSize = 14, fontColor = {120, 100, 80, 220}, textAlign = "center" })
    end
    return rows
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
    if not seedPackPanelOpen_ then
        return UI.Panel { width = 0, height = 0 }
    end
    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 100,
        backgroundColor = {0, 0, 0, 120},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 430,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Label { text = "种子礼包", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                            UI.Button {
                                text = "×",
                                width = 34,
                                height = 30,
                                fontSize = 18,
                                fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 0},
                                fontColor = {120, 90, 70, 255},
                                borderRadius = 12,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    seedPackPanelOpen_ = false
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                    UI.ScrollView {
                        height = 350,
                        scrollY = true,
                        showScrollbar = true,
                        children = BuildSeedPackRows(),
                    },
                },
            },
        },
    }
end

local function BuildSeedPackResultOverlay()
    if seedPackResultItems_ == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    local results = seedPackResultItems_
    local newNames = {}
    for _, result in ipairs(results) do
        if result.isNew then
            local name = PLANTS[result.seedId].name
            local exists = false
            for _, item in ipairs(newNames) do
                if item == name then exists = true; break end
            end
            if not exists then table.insert(newNames, name) end
        end
    end

    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 110,
        backgroundColor = {0, 0, 0, 130},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 500,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Label { text = seedPackResultTitle_ or "开包结果", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center", marginBottom = 8 },
                    #newNames > 0 and UI.Panel {
                        padding = 7,
                        marginBottom = 8,
                        backgroundColor = {255, 235, 232, 255},
                        borderRadius = 10,
                        borderWidth = 2,
                        borderColor = {220, 70, 60, 255},
                        children = { UI.Label { text = "解锁新品种：" .. table.concat(newNames, "、"), fontSize = 12, fontWeight = "bold", fontColor = {210, 55, 45, 255}, textAlign = "center" } },
                    } or UI.Panel { height = 0 },
                    UI.ScrollView {
                        height = 300,
                        scrollY = true,
                        showScrollbar = true,
                        children = {
                            UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 8, children = BuildResultCards(results) },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 10,
                        children = {
                            CountSeedPacks() > 0 and UI.Button {
                                text = "下一包",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "primary",
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    local packId = GetFirstAvailablePackId()
                                    if packId ~= nil then
                                        local cfg = SEED_PACK_CONFIG[packId]
                                        local nextResults, err = InventorySystem.OpenSeedPack(packId, 1)
                                        if nextResults ~= nil then
                                            OpenSeedPackResultModal(cfg.packName, nextResults)
                                        elseif err ~= nil then
                                            ShowToast(err)
                                        end
                                    end
                                end,
                            } or UI.Panel { width = 0, height = 0 },
                            UI.Button {
                                text = "关闭",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "secondary",
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    seedPackResultTitle_ = nil
                                    seedPackResultItems_ = nil
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

OpenTaskPanel = function()
    if taskModal_ ~= nil then
        taskModal_:Close()
    end
    local rows = {}
    for _, task in ipairs(DAILY_TASK_CONFIG) do
        local progress = math.min(dailyTaskState_.progress[task.key] or 0, task.target)
        local done = progress >= task.target
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            padding = 10,
            marginBottom = 6,
            backgroundColor = done and {232, 246, 232, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = 1,
            borderColor = done and {94, 194, 131, 255} or {195, 180, 150, 180},
            children = {
                UI.Label { text = done and "完成" or "进行中", width = 54, fontSize = 12, fontWeight = "bold", fontColor = done and {70, 160, 90, 255} or {130, 110, 85, 255} },
                UI.Label { text = task.title, flexGrow = 1, fontSize = 13, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                UI.Label { text = progress .. "/" .. task.target, width = 48, fontSize = 13, fontWeight = "bold", fontColor = {90, 150, 100, 255}, textAlign = "right" },
            },
        })
    end

    local canClaim = AreAllDailyTasksCompleted() and not dailyTaskState_.rewardClaimed
    taskModal_ = UI.Modal {
        title = "每日任务",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        onClose = function() taskModal_ = nil end,
    }
    taskModal_:AddContent(UI.Panel {
        padding = 10,
        gap = 10,
        children = {
            UI.Panel { children = rows },
            UI.Label { text = dailyTaskState_.rewardClaimed and "今日奖励已领取" or "全部完成可领取日常普通种子礼包 x1", fontSize = 12, fontColor = {120, 100, 80, 220}, textAlign = "center" },
            UI.Button {
                text = dailyTaskState_.rewardClaimed and "已领取" or "领取礼包",
                height = 40,
                fontSize = 14,
                variant = "primary",
                disabled = not canClaim,
                onClick = function()
                    suppressNextWorldTap_ = true
                    if canClaim and InventorySystem.ClaimDailyReward() then
                        ShowToast("获得日常普通种子礼包")
                        if taskModal_ ~= nil then taskModal_:Close(); taskModal_ = nil end
                        RebuildUI()
                    end
                end,
            },
        },
    })
    taskModal_:Open()
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
        moneyLabel_:SetText("金币 " .. money_)
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

--- 获取拥有种子的索引列表
local function GetOwnedSeedIndices()
    local list = {}
    for i = 1, #PLANTS do
        if (seedBag_[i] or 0) > 0 then
            table.insert(list, i)
        end
    end
    return list
end

--- 构建种植模式 Tab 内容（动森配色）
local function BuildPlantTabContent()
    local plot = plots_[selectedPlot_]
    local COL_TXT = {75, 55, 40, 255}      -- 深棕文字
    local COL_SUB = {130, 110, 85, 220}    -- 次要提示文字
    local CONTENT_H = 200                   -- 统一内容区高度

    if plantTab_ == "seed" then
        -- 播种 Tab：中间放大选中，两侧缩小（显示3张）
        local ownedList = GetOwnedSeedIndices()

        if #ownedList == 0 then
            return UI.Panel {
                height = CONTENT_H,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "暂无种子，前往商店购买", fontSize = 14, fontColor = COL_SUB },
                },
            }
        end

        -- 找到当前选中在列表中的位置
        local curIdx = 1
        for i, v in ipairs(ownedList) do
            if v == selectedSeed_ then curIdx = i; break end
        end

        -- 构建卡片：1 个种子显示 1 张，2 个显示 2 张，3 个及以上显示左/中/右 3 张
        local cards = {}
        local positions = {}
        if #ownedList == 1 then
            positions = { curIdx }
        elseif #ownedList == 2 then
            positions = { curIdx, curIdx == 1 and 2 or 1 }
        else
            positions = { curIdx - 1, curIdx, curIdx + 1 }
        end

        for _, pos in ipairs(positions) do
            local actualIdx = pos
            if actualIdx < 1 then actualIdx = #ownedList end
            if actualIdx > #ownedList then actualIdx = 1 end
            local isCenter = (actualIdx == curIdx)

            local plantIndex = ownedList[actualIdx]
            local plant = PLANTS[plantIndex]
            local owned = seedBag_[plantIndex] or 0
            local iconPath = string.format("image/icons_3d/seed (%d).png", plantIndex)
            local cardW = isCenter and 137 or 107
            local cardH = isCenter and 137 or 107
            local iconW = isCenter and 102 or 78
            local iconH = isCenter and 88 or 68

            table.insert(cards, UI.Panel {
                width = cardW, height = cardH,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 12,
                borderWidth = isCenter and 3 or 1,
                borderColor = isCenter and {94, 194, 131, 255} or {195, 180, 150, 200},
                overflow = "visible",
                onClick = function()
                    suppressNextWorldTap_ = true
                    selectedSeed_ = plantIndex
                    RebuildUI()
                end,
                children = {
                    UI.Panel {
                        width = iconW,
                        height = iconH,
                        marginBottom = 2,
                        backgroundImage = iconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = plant.name .. "种子", fontSize = isCenter and 12 or 10, fontColor = COL_TXT, textAlign = "center" },
                    UI.Panel {
                        position = "absolute",
                        right = -4, bottom = -4,
                        width = 30, height = 30,
                        borderRadius = 15,
                        zIndex = 2,
                        backgroundColor = {94, 194, 131, 255},
                        borderWidth = 2,
                        borderColor = {255, 253, 245, 255},
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label { text = tostring(owned), fontSize = owned >= 100 and 9 or 12, fontWeight = "bold", fontColor = {255, 255, 255, 255}, textAlign = "center" },
                        },
                    },
                },
            })
        end

        -- 左右切换按钮
        local function switchSeed(delta)
            local newIdx = curIdx + delta
            if newIdx < 1 then newIdx = #ownedList end
            if newIdx > #ownedList then newIdx = 1 end
            selectedSeed_ = ownedList[newIdx]
            RebuildUI()
        end

        return UI.Panel {
            height = CONTENT_H,
            gap = 6,
            children = {
                UI.Label { text = "选择种子后点击上方土地进行播种", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT, textAlign = "center" },
                UI.Panel {
                    justifyContent = "center",
                    alignItems = "center",
                    flexGrow = 1,
                    children = {
                        -- 卡片居中
                        UI.Panel {
                            flexDirection = "row",
                            justifyContent = "center",
                            alignItems = "center",
                            gap = 15,
                            flexGrow = 1,
                            children = { cards[1], cards[2], cards[3] },
                        },
                        -- 左箭头（悬浮靠左）
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            left = 0,
                            text = "<", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() suppressNextWorldTap_ = true; switchSeed(-1) end,
                        } or UI.Panel { width = 0, height = 0 },
                        -- 右箭头（悬浮靠右）
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            right = 0,
                            text = ">", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() suppressNextWorldTap_ = true; switchSeed(1) end,
                        } or UI.Panel { width = 0, height = 0 },
                    },
                },
            },
        }

    elseif plantTab_ == "harvest" then
        -- 收获 Tab：成熟作物卡片
        local harvestCards = {}
        if plot ~= nil and plot.plants ~= nil then
            for _, crop in ipairs(plot.plants) do
                if crop.mature then
                    local tags = {}
                    if crop.mutation and crop.mutation.specials then
                        for _, sp in ipairs(crop.mutation.specials) do
                            table.insert(tags, UI.Panel {
                                paddingTop = 2, paddingBottom = 2, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = {94, 194, 131, 255}, borderRadius = 4,
                                children = { UI.Label { text = sp.name or sp.key, fontSize = 9, fontColor = {255, 255, 255, 255} } },
                            })
                        end
                    end
                    table.insert(harvestCards, UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        padding = 10,
                        marginBottom = 6,
                        backgroundColor = {255, 253, 245, 255},
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = {195, 180, 150, 200},
                        children = {
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1, gap = 4,
                                children = {
                                    UI.Label { text = crop.name, fontSize = 13, fontWeight = "bold", fontColor = COL_TXT },
                                    #tags > 0 and UI.Panel { flexDirection = "row", gap = 4, flexWrap = "wrap", children = tags } or UI.Panel { height = 0 },
                                },
                            },
                            UI.Button {
                                text = "收获", width = 52, height = 30, fontSize = 12,
                                backgroundColor = {94, 194, 131, 255}, fontColor = {255, 255, 255, 255}, borderRadius = 8,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    HarvestNearestMature(selectedPlot_, crop.localPos)
                                    RebuildUI()
                                end,
                            },
                        },
                    })
                end
            end
        end

        if #harvestCards > 0 then
            return UI.Panel {
                height = CONTENT_H,
                gap = 6,
                children = {
                    UI.Label { text = "点击土地中成熟的作物收获", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT },
                    UI.ScrollView {
                        scrollY = true, flexGrow = 1, flexBasis = 0,
                        children = harvestCards,
                    },
                },
            }
        else
            return UI.Panel {
                height = CONTENT_H,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "当前地块暂无成熟作物", fontSize = 14, fontColor = COL_SUB },
                },
            }
        end

    else
        -- 背包 Tab：更大的 2行×4列物品卡片
        local slots = {}
        for i = 1, 10 do
            local item = harvested_[i]
            local itemIconPath = item and item.plantIndex and string.format("image/plants/plants (%d).png", item.plantIndex) or nil
            local weightText = item and item.weight and string.format("%.2fkg", item.weight) or ""
            local isGiant = item ~= nil and item.weightTier == "Giant"
            table.insert(slots, UI.Panel {
                width = "18%",
                height = 98,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 8,
                borderWidth = 1,
                borderColor = {195, 180, 150, 200},
                onClick = function()
                    suppressNextWorldTap_ = true
                    if item ~= nil then
                        OpenBagItemDetail(item)
                    end
                end,
                children = item and {
                    UI.Panel {
                        width = 56,
                        height = 46,
                        marginBottom = 3,
                        backgroundImage = itemIconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = item.name, fontSize = 10, fontWeight = "bold", fontColor = COL_TXT, textAlign = "center" },
                    UI.Label { text = weightText, fontSize = 10, fontWeight = "bold", fontColor = isGiant and {220, 80, 70, 255} or {94, 160, 100, 255}, textAlign = "center" },
                    isGiant and UI.Panel {
                        position = "absolute",
                        top = 2,
                        right = 2,
                        paddingLeft = 3,
                        paddingRight = 3,
                        paddingTop = 1,
                        paddingBottom = 1,
                        borderRadius = 4,
                        backgroundColor = {220, 80, 70, 235},
                        children = {
                            UI.Label { text = "G", fontSize = 7, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
                        },
                    } or UI.Panel { width = 0, height = 0 },
                } or {},
            })
        end

        return UI.Panel {
            height = CONTENT_H + 110,
            children = {
                UI.ScrollView {
                    scrollY = true,
                    showScrollbar = false,
                    flexGrow = 1,
                    flexBasis = 0,
                    children = {
                        UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 8, justifyContent = "flex-start", children = slots },
                    },
                },
            },
        }
    end
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

    -- === 颜色常量（动物森友会风格 v2） ===
    local COL_CREAM      = {255, 253, 245, 255}     -- 奶油白正文
    local COL_MONEY      = {255, 210, 50, 255}      -- 日光黄金币（饱和度更高）
    local COL_BROWN      = {75, 50, 40, 255}        -- 深棕主文字（更深更实）
    local COL_BROWN_SOFT = {115, 85, 65, 255}       -- 柔棕次文字
    local COL_GREEN_DARK = {38, 90, 45, 255}        -- 暗绿辅助
    local COL_LEAF       = {80, 185, 120, 255}      -- 叶子绿
    local COL_SAND       = {195, 155, 90, 255}      -- 暖沙棕（更饱和）

    -- === Labels ===
    moneyLabel_ = UI.Label {
        text = "金币 0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    seedLabel_ = UI.Label {
        text = "观光 0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    seedPackBadgeLabel_ = UI.Label {
        text = "0",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
        textAlign = "center",
    }
    plotLabel_ = UI.Label {
        text = "LV1",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
    }
    actionLabel_ = UI.Label {
        text = "点击田地播种或收获",
        fontSize = 12,
        fontColor = {255, 250, 235, 220},
    }
    inventoryLabel_ = UI.Label {
        text = "背包 --",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COL_MONEY,
    }
    toastLabel_ = UI.Label {
        text = "当前为查看状态，点击下方开始种植",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COL_GREEN_DARK,
        textAlign = "center",
    }
    helpLabel_ = UI.Label {
        text = "已解锁区域 1/9",
        fontSize = 14,
        fontColor = {80, 80, 80, 255},
        textAlign = "center",
    }

    -- === 主操作按钮 ===
    actionButton_ = UI.Button {
        text = "开始种植",
        variant = "primary",
        height = 90,
        width = 228,
        fontSize = 26,
        fontWeight = "bold",
        borderRadius = 28,
        onClick = function()
            suppressNextWorldTap_ = true
            if GetViewMode() == ViewMode.FARM then
                EnterPlantView()
            else
                EnterFarmView()
            end
        end,
    }

    -- === 种子切换按钮（暖沙棕次按钮） ===
    local prevSeedButton = UI.Button {
        text = "上一种",
        variant = "secondary",
        height = 46,
        fontSize = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ - 1
            if selectedSeed_ < 1 then selectedSeed_ = #PLANTS end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    local nextSeedButton = UI.Button {
        text = "下一种",
        variant = "secondary",
        height = 46,
        fontSize = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ + 1
            if selectedSeed_ > #PLANTS then selectedSeed_ = 1 end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    -- === 购买/出售按钮 ===
    local buyButton = UI.Button {
        text = "购买种子",
        variant = "primary",
        height = 50,
        fontSize = 15,
        onClick = function()
            suppressNextWorldTap_ = true
            if BuySelectedSeed() then
                ShowToast("购买 " .. PLANTS[selectedSeed_].name)
            else
                ShowToast("金币不足")
            end
            RefreshUI(true)
        end,
    }

    local sellButton = UI.Button {
        text = "出售背包",
        variant = "secondary",
        height = 50,
        fontSize = 15,
        onClick = function()
            suppressNextWorldTap_ = true
            local earned = SellAllHarvested()
            if earned > 0 then
                ShowToast("出售获得 " .. earned .. " 金币")
            else
                ShowToast("背包为空")
            end
            RefreshUI(true)
        end,
    }

    -- === 视角控制按钮（轮廓风格） ===
    local rotateLeftButton = UI.Button {
        text = "左转",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            CameraSystem.RotateYaw(-22.5)
        end,
    }

    local rotateRightButton = UI.Button {
        text = "右转",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            CameraSystem.RotateYaw(22.5)
        end,
    }

    local zoomInButton = UI.Button {
        text = "放大",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            CameraSystem.AdjustDistance(-1.0, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
        end,
    }

    local zoomOutButton = UI.Button {
        text = "缩小",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            CameraSystem.AdjustDistance(1.0, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
        end,
    }

    -- === 根面板布局 ===
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- ▼ 顶部信息栏（动森风格：奶油底 + 柔绿描边）
            UI.Panel {
                position = "absolute",
                top = 14,
                left = 12,
                right = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                pointerEvents = "box-none",
                children = {
                    -- 等级标签（叶子绿底）
                    UI.Panel {
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 14, paddingRight = 14,
                        backgroundColor = {78, 172, 110, 255},
                        borderRadius = 14,
                        children = {
                            plotLabel_,
                        },
                    },
                    -- 观光值（奶油底无描边 + 紫色宝石图标）
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 7,
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 10, paddingRight = 14,
                        backgroundColor = {255, 250, 240, 240},
                        borderRadius = 14,
                        children = {
                            -- 观光图标（淡紫色圆底 + 白色星星）
                            UI.Panel {
                                width = 22, height = 22,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {190, 160, 230, 255} },
                                    UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {155, 120, 210, 255} },
                                    UI.Label { position = "absolute", text = "★", fontSize = 11, fontColor = {245, 240, 255, 255} },
                                },
                            },
                            seedLabel_,
                        },
                    },
                    -- 金币（奶油底无描边 + 金币$图标）
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 7,
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 10, paddingRight = 14,
                        backgroundColor = {255, 250, 240, 240},
                        borderRadius = 14,
                        children = {
                            -- 金币图标（金圆 + $符号）
                            UI.Panel {
                                width = 22, height = 22,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {255, 205, 60, 255} },
                                    UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {230, 175, 30, 255} },
                                    UI.Label { position = "absolute", text = "$", fontSize = 11, fontWeight = "bold", fontColor = {255, 245, 200, 255} },
                                },
                            },
                            moneyLabel_,
                        },
                    },
                },
            },

            -- ▼ Toast 提示条（浅绿底 + 粗叶子绿边框）
            UI.Panel {
                position = "absolute",
                top = 145,
                left = 28,
                right = 28,
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        paddingTop = 12,
                        paddingBottom = 12,
                        paddingLeft = 20,
                        paddingRight = 20,
                        backgroundColor = {228, 243, 230, 242},
                        borderColor = {70, 170, 100, 210},
                        borderWidth = 3,
                        borderRadius = 16,
                        children = { toastLabel_ },
                    },
                },
            },

            -- ▼ 底部操作面板
            GetViewMode() == ViewMode.FARM and UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 60,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "flex-end",
                gap = 16,
                pointerEvents = "box-none",
                children = {
                    -- 商店按钮（白底+绿字）
                    UI.Button {
                        text = "商店",
                        width = 90,
                        height = 90,
                        fontSize = 22,
                        fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 245},
                        fontColor = {78, 155, 100, 255},
                        borderRadius = 28,
                        onClick = function()
                            suppressNextWorldTap_ = true
                            Shop.Open()
                        end,
                    },
                    -- 开始种植
                    actionButton_,
                    -- 任务按钮与种子包入口
                    UI.Panel {
                        width = 90,
                        height = 142,
                        alignItems = "center",
                        justifyContent = "flex-end",
                        overflow = "visible",
                        children = {
                            CountSeedPacks() > 0 and UI.Button {
                                position = "absolute",
                                top = 0,
                                text = "礼包",
                                width = 68,
                                height = 42,
                                fontSize = 15,
                                fontWeight = "bold",
                                backgroundColor = {245, 232, 198, 250},
                                fontColor = {125, 88, 45, 255},
                                borderRadius = 18,
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 240},
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    OpenSeedPackHub()
                                end,
                            } or UI.Panel { width = 0, height = 0 },
                            CountSeedPacks() > 0 and UI.Panel {
                                position = "absolute",
                                top = -6,
                                right = 4,
                                width = 24,
                                height = 24,
                                borderRadius = 12,
                                backgroundColor = {225, 55, 45, 255},
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 255},
                                justifyContent = "center",
                                alignItems = "center",
                                children = { seedPackBadgeLabel_ },
                            } or UI.Panel { width = 0, height = 0 },
                            UI.Button {
                                text = "任务",
                                width = 90,
                                height = 90,
                                fontSize = 22,
                                fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 245},
                                fontColor = {78, 155, 100, 255},
                                borderRadius = 28,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    OpenTaskPanel()
                                end,
                            },
                        },
                    },
                },
            } or UI.Panel {
                -- 种植模式：三Tab面板（动森风格）
                position = "absolute",
                left = 0, right = 0, bottom = 0,
                paddingTop = 12, paddingBottom = 125,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = {250, 245, 235, 252},
                borderRadius = {22, 22, 0, 0},
                children = {
                    -- Tab 按钮行（等高、动森配色）
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginBottom = 10,
                        children = {
                            UI.Button {
                                text = "播种", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "seed" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "seed" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; selectedBagItem_ = nil; if ClearBagPreview ~= nil then ClearBagPreview() end; plantTab_ = "seed"; RebuildUI() end,
                            },
                            UI.Button {
                                text = "收获", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "harvest" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "harvest" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; selectedBagItem_ = nil; if ClearBagPreview ~= nil then ClearBagPreview() end; plantTab_ = "harvest"; RebuildUI() end,
                            },
                            UI.Button {
                                text = "背包", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "bag" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "bag" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; plantTab_ = "bag"; RebuildUI() end,
                            },
                        },
                    },
                    -- Tab 内容区
                    BuildPlantTabContent(),
                },
            },

            -- ▼ 收起按钮（种植模式，右下角独立）
            GetViewMode() == ViewMode.PLANT and UI.Panel {
                position = "absolute",
                bottom = plantTab_ == "bag" and 520 or 410,
                right = 12,
                children = {
                    UI.Button {
                        text = "▼ 收起", width = 90, height = 34, fontSize = 12, fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 240}, fontColor = {120, 100, 75, 255},
                        borderRadius = 16, borderWidth = 2, borderColor = {185, 165, 130, 220},
                        onClick = function()
                            suppressNextWorldTap_ = true
                            EnterFarmView()
                        end,
                    },
                },
            } or UI.Panel { width = 0, height = 0 },
            -- ▼ 背包详情弹窗
            selectedBagItem_ ~= nil and UI.Panel {
                position = "absolute",
                left = 0,
                right = 0,
                top = 0,
                bottom = 0,
                backgroundColor = {0, 0, 0, 120},
                justifyContent = "center",
                alignItems = "center",
                paddingLeft = 20,
                paddingRight = 20,
                paddingTop = 90,
                paddingBottom = GetViewMode() == ViewMode.PLANT and 330 or 90,
                children = {
                    UI.Panel {
                        width = "100%",
                        maxWidth = 340,
                        paddingTop = 18,
                        paddingBottom = 18,
                        paddingLeft = 16,
                        paddingRight = 16,
                        backgroundColor = {255, 253, 245, 248},
                        borderRadius = 24,
                        borderWidth = 3,
                        borderColor = {94, 194, 131, 235},
                        boxShadow = { { x = 0, y = 8, blur = 20, spread = 0, color = {0, 0, 0, 70} } },
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                marginBottom = 12,
                                children = {
                                    UI.Panel {
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        children = {
                                            UI.Label { text = selectedBagItem_.name or "作物", fontSize = 24, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                            UI.Label { text = "作物详情", fontSize = 12, fontColor = {130, 110, 85, 230} },
                                        },
                                    },
                                    UI.Button {
                                        text = "×", width = 38, height = 34, fontSize = 20, fontWeight = "bold",
                                        backgroundColor = {255, 250, 240, 0}, fontColor = {120, 90, 70, 255}, borderRadius = 14,
                                        onClick = function()
                                            suppressNextWorldTap_ = true
                                            CloseBagItemDetail()
                                        end,
                                    },
                                },
                            },
                            UI.Panel {
                                height = 218,
                                width = "100%",
                                marginBottom = 14,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = {255, 253, 245, 255},
                                borderRadius = 22,
                                borderWidth = 2,
                                borderColor = {132, 202, 150, 225},
                                overflow = "hidden",
                                children = {
                                    UI.Panel { position = "absolute", left = 26, right = 26, bottom = 28, height = 28, borderRadius = 14, backgroundColor = {90, 160, 100, 36} },
                                    UI.Panel {
                                        width = 176,
                                        height = 176,
                                        backgroundImage = selectedBagItem_.plantIndex and string.format("image/plants/plants (%d).png", selectedBagItem_.plantIndex) or nil,
                                        backgroundFit = "contain",
                                    },
                                },
                            },
                            UI.Panel {
                                gap = 8,
                                marginBottom = 14,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        paddingTop = 10,
                                        paddingBottom = 10,
                                        paddingLeft = 14,
                                        paddingRight = 14,
                                        backgroundColor = {255, 250, 240, 220},
                                        borderRadius = 12,
                                        children = {
                                            UI.Label { text = "重量", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                            UI.Label { text = string.format("%.2fkg", selectedBagItem_.weight or 0), fontSize = 19, fontWeight = "bold", fontColor = selectedBagItem_.weightTier == "Giant" and {220, 80, 70, 255} or {94, 160, 100, 255} },
                                        },
                                    },
                                    UI.Panel {
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        paddingTop = 10,
                                        paddingBottom = 10,
                                        paddingLeft = 14,
                                        paddingRight = 14,
                                        backgroundColor = {255, 250, 240, 220},
                                        borderRadius = 12,
                                        children = {
                                            UI.Label { text = "售价", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                            UI.Label { text = string.format("%d 金币", selectedBagItem_.price or 0), fontSize = 19, fontWeight = "bold", fontColor = {190, 130, 40, 255} },
                                        },
                                    },
                                },
                            },
                            UI.Button {
                                text = "出售",
                                width = "100%",
                                height = 48,
                                fontSize = 18,
                                fontWeight = "bold",
                                backgroundColor = {94, 194, 131, 255},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 16,
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 230},
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    local item = selectedBagItem_
                                    local earned = SellBagItem(item)
                                    if earned > 0 then
                                        ShowToast("出售获得 " .. earned .. " 金币")
                                    end
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                },
            } or UI.Panel { width = 0, height = 0 },
            BuildSeedPackOverlay(),
            BuildSeedPackResultOverlay(),

        }
    }
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

    InventorySystem.Init(GameConfig, {
        showToast = ShowToast,
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
        getMoney = function() return money_ end,
        getGardenLevel = GetGardenLevel,
        onBuy = function(cost, plantIndex)
            money_ = money_ - cost
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
