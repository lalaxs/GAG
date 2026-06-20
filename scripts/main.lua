require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")

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
local seedButtons_ = {}

local CONFIG = {
    Title = "Grow A Garden 核心玩法原型",
    GridCols = 2,
    GridRows = 2,
    VisiblePlots = 4,
    InitialUnlockedPlots = 1,
    PlotSpacing = 1.28,
    PlotSize = 1.0,
    StartMoney = 150,
    FarmViewDistance = 10.5,
    FarmViewMinDistance = 6.8,
    FarmViewMaxDistance = 16.0,
    FarmViewYaw = -28.0,
    FarmViewPitch = 38.0,
    PlantViewDistance = 8.0,
    PlantViewYaw = 0.0,
    PlantViewPitch = 60.0,
}

local RARITY_COLORS = {
    ["普通"] = Color(0.92, 0.92, 0.88, 1.0),
    ["罕见"] = Color(0.25, 0.95, 0.35, 1.0),
    ["稀有"] = Color(0.25, 0.55, 1.0, 1.0),
    ["史诗"] = Color(0.75, 0.35, 1.0, 1.0),
    ["传奇"] = Color(1.0, 0.58, 0.08, 1.0),
}

local PLANTS = {
    { name = "胡萝卜", rarity = "普通", seedPrice = 10, fruitPrice = 20, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 8, visual = "root", color = Color(1.0, 0.42, 0.08, 1.0) },
    { name = "番茄", rarity = "普通", seedPrice = 20, fruitPrice = 40, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 10, visual = "vine", color = Color(0.95, 0.08, 0.05, 1.0) },
    { name = "草莓", rarity = "罕见", seedPrice = 50, fruitPrice = 100, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 12, visual = "berry", color = Color(0.9, 0.05, 0.12, 1.0) },
    { name = "花椰菜", rarity = "罕见", seedPrice = 100, fruitPrice = 200, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 14, visual = "cluster", color = Color(0.86, 0.93, 0.72, 1.0) },
    { name = "南瓜", rarity = "罕见", seedPrice = 200, fruitPrice = 400, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 16, visual = "gourd", color = Color(1.0, 0.45, 0.02, 1.0) },
    { name = "凤梨", rarity = "罕见", seedPrice = 500, fruitPrice = 1000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 18, visual = "pineapple", color = Color(0.95, 0.75, 0.18, 1.0) },
    { name = "郁金香", rarity = "稀有", seedPrice = 500, fruitPrice = 1000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 18, visual = "flower", color = Color(0.9, 0.18, 0.45, 1.0) },
    { name = "西瓜", rarity = "稀有", seedPrice = 800, fruitPrice = 1600, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 20, visual = "melon", color = Color(0.08, 0.55, 0.16, 1.0) },
    { name = "蘑菇", rarity = "稀有", seedPrice = 1000, fruitPrice = 2000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 21, visual = "mushroom", color = Color(0.82, 0.18, 0.16, 1.0) },
    { name = "仙人掌", rarity = "稀有", seedPrice = 1200, fruitPrice = 2400, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 22, visual = "cactus", color = Color(0.12, 0.58, 0.22, 1.0) },
    { name = "波斯菊", rarity = "史诗", seedPrice = 1500, fruitPrice = 3000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 24, visual = "flower", color = Color(1.0, 0.35, 0.75, 1.0) },
    { name = "向日葵", rarity = "史诗", seedPrice = 1800, fruitPrice = 3600, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 25, visual = "sunflower", color = Color(1.0, 0.82, 0.08, 1.0) },
    { name = "辣椒", rarity = "史诗", seedPrice = 2000, fruitPrice = 4000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 26, visual = "pepper", color = Color(0.95, 0.03, 0.03, 1.0) },
    { name = "百合", rarity = "史诗", seedPrice = 2500, fruitPrice = 5000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 28, visual = "flower", color = Color(0.95, 0.88, 1.0, 1.0) },
    { name = "三色堇", rarity = "传奇", seedPrice = 3000, fruitPrice = 6000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 30, visual = "flower", color = Color(0.45, 0.2, 0.95, 1.0) },
    { name = "玫瑰", rarity = "传奇", seedPrice = 3500, fruitPrice = 7000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 32, visual = "rose", color = Color(0.9, 0.02, 0.12, 1.0) },
    { name = "蒲公英", rarity = "传奇", seedPrice = 3500, fruitPrice = 7000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 32, visual = "dandelion", color = Color(1.0, 0.93, 0.18, 1.0) },
    { name = "风信子", rarity = "传奇", seedPrice = 5000, fruitPrice = 10000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 35, visual = "cluster", color = Color(0.38, 0.35, 1.0, 1.0) },
    { name = "绣球花", rarity = "传奇", seedPrice = 5000, fruitPrice = 10000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 35, visual = "hydrangea", color = Color(0.35, 0.65, 1.0, 1.0) },
    { name = "杨桃", rarity = "传奇", seedPrice = 10000, fruitPrice = 20000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 40, visual = "starfruit", color = Color(1.0, 0.9, 0.12, 1.0) },
}

local COLOR_MUTATIONS = {
    { key = "yellow", name = "黄色", color = Color(1.0, 0.88, 0.08, 1.0), prefixes = { "琥珀", "日耀", "鎏金", "圣辉", "光铸" } },
    { key = "red", name = "红色", color = Color(1.0, 0.05, 0.02, 1.0), prefixes = { "熔岩", "猩红", "朱砂", "血怒", "赤狱" } },
    { key = "purple", name = "紫色", color = Color(0.58, 0.18, 1.0, 1.0), prefixes = { "暮光", "水晶", "幽影", "虚空", "暗裔" } },
    { key = "blue", name = "蓝色", color = Color(0.12, 0.45, 1.0, 1.0), prefixes = { "冰海", "钴蓝", "苍穹", "霜魂", "星穹" } },
    { key = "white", name = "白色", color = Color(0.96, 0.96, 1.0, 1.0), prefixes = { "骨白", "月霜", "珍珠", "圣洁", "灵魄" } },
    { key = "black", name = "黑色", color = Color(0.02, 0.02, 0.035, 1.0), prefixes = { "暗烬", "墨玉", "永夜", "湮灭", "影噬" } },
}

local SPECIAL_MUTATIONS = {
    { key = "rainbow", name = "彩虹变异", multiplier = 8, timeMultiplier = 1.35, prefixes = { "虹霓", "幻光", "棱镜", "虹彩", "神谕" } },
    { key = "glow", name = "荧光变异", multiplier = 5, timeMultiplier = 1.2, prefixes = { "磷光", "夜辉", "萤火", "鬼火", "邪光" } },
    { key = "wet", name = "潮湿变异", multiplier = 2, timeMultiplier = 1.08, prefixes = { "露浸", "泽地", "潮涌", "海裔", "深渊" } },
    { key = "stardust", name = "星尘变异", multiplier = 5, timeMultiplier = 1.25, prefixes = { "星屑", "彗尾", "银河", "星轨", "天坠" } },
    { key = "gold", name = "黄金变异", multiplier = 10, timeMultiplier = 1.45, prefixes = { "镀金", "钱袋", "耀金", "神铸", "王权" } },
    { key = "frozen", name = "冷冻变异", multiplier = 2, timeMultiplier = 1.1, prefixes = { "寒霜", "冰棱", "凛冬", "霜脉", "永冻" } },
    { key = "cloud", name = "云朵变异", multiplier = 2, timeMultiplier = 1.08, prefixes = { "积云", "羽絮", "棉糖", "天穹" } },
    { key = "chocolate", name = "巧克力变异", multiplier = 2, timeMultiplier = 1.05, prefixes = { "可可", "熔浆", "糖壳", "丝滑" } },
    { key = "ceramic", name = "陶瓷变异", multiplier = 2, timeMultiplier = 1.1, prefixes = { "青瓷", "素烧", "裂纹", "珐琅" } },
    { key = "pollen", name = "花粉变异", multiplier = 2, timeMultiplier = 1.05, prefixes = { "粉雾", "授粉", "蜜腺", "蝶吻" } },
    { key = "void", name = "虚空变异", multiplier = 8, timeMultiplier = 1.35, prefixes = { "裂隙", "以太", "吞噬", "低语" } },
}

local materials_ = {}
local plots_ = {}
local selectedPlot_ = 1
local selectedSeed_ = 1
local money_ = CONFIG.StartMoney
local seedBag_ = {}
local harvested_ = {}
local ViewMode = {
    FARM = 1,
    PLANT = 2,
}
local viewMode_ = ViewMode.FARM
local cameraYaw_ = CONFIG.FarmViewYaw
local cameraPitch_ = CONFIG.FarmViewPitch
local cameraDistance_ = CONFIG.FarmViewDistance
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local uiRefreshTimer_ = 0
local uiInitialized_ = false
local gameTime_ = 0
local toastTimer_ = 0
local suppressNextWorldTap_ = false
local touchGestureActive_ = false
local lastPinchDistance_ = 0
local RefreshUI = nil
local ShowToast = nil
local RebuildUI = nil

local function RandItem(list)
    return list[math.random(1, #list)]
end

local function HasSpecial(mutation, key)
    for _, item in ipairs(mutation.specials) do
        if item.key == key then
            return true
        end
    end
    return false
end

local function CreateMaterial(name, color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.55, 0.55, 0.55, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.55))
    if emissive ~= nil then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    materials_[name] = mat
    return mat
end

local function CreateTransparentMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.8, 0.8, 0.8, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    materials_[name] = mat
    return mat
end

local function CreateUnlitMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    materials_[name] = mat
    return mat
end

local function AddModel(parent, name, modelPath, position, scale, material)
    local node = parent:CreateChild(name)
    node.position = position
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", modelPath))
    model:SetMaterial(material)
    model.castShadows = true
    return node
end

local function InitMaterials()
    CreateMaterial("grass", Color(0.12, 0.42, 0.16, 1.0), 0.0, 0.9)
    CreateMaterial("grassTop", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.55)
    CreateMaterial("soilSide", Color(0.58, 0.34, 0.12, 1.0), 0.0, 0.78)
    CreateMaterial("soil", Color(0.55, 0.34, 0.16, 1.0), 0.0, 0.72)
    CreateMaterial("soilLocked", Color(0.34, 0.37, 0.34, 1.0), 0.0, 0.85)
    CreateMaterial("soilSelected", Color(0.67, 0.42, 0.2, 1.0), 0.0, 0.58)
    CreateMaterial("path", Color(0.48, 0.36, 0.22, 1.0), 0.0, 0.8)
    CreateMaterial("stem", Color(0.14, 0.55, 0.18, 1.0), 0.0, 0.65)
    CreateMaterial("leaf", Color(0.08, 0.72, 0.19, 1.0), 0.0, 0.55)
    CreateMaterial("wood", Color(0.45, 0.25, 0.1, 1.0), 0.0, 0.72)
    CreateMaterial("gold", Color(1.0, 0.68, 0.12, 1.0), 1.0, 0.18, Color(0.25, 0.15, 0.02, 1.0))
    CreateMaterial("frozen", Color(0.55, 0.88, 1.0, 1.0), 0.0, 0.08, Color(0.04, 0.16, 0.25, 1.0))
    CreateMaterial("glow", Color(0.45, 0.15, 1.0, 1.0), 0.0, 0.18, Color(0.55, 0.12, 1.2, 1.0))
    CreateMaterial("chocolate", Color(0.24, 0.1, 0.035, 1.0), 0.0, 0.38)
    CreateMaterial("ceramic", Color(0.9, 0.92, 0.86, 1.0), 0.0, 0.08)
    CreateMaterial("void", Color(0.01, 0.006, 0.02, 1.0), 0.0, 0.4, Color(0.14, 0.02, 0.35, 1.0))
    CreateUnlitMaterial("select", Color(0.46, 0.82, 0.42, 1.0))
    CreateTransparentMaterial("waterDrop", Color(0.2, 0.65, 1.0, 0.62))
    CreateTransparentMaterial("cloud", Color(0.92, 0.95, 1.0, 0.5))
    CreateUnlitMaterial("star", Color(1.0, 0.9, 0.3, 1.0))
    CreateUnlitMaterial("pollen", Color(1.0, 0.82, 0.12, 1.0))
end

local function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.48, 0.52, 0.48)
    zone.fogColor = Color(0.66, 0.78, 0.92)
    zone.fogStart = 55.0
    zone.fogEnd = 120.0

    local lightNode = scene_:CreateChild("Sun")
    lightNode.direction = Vector3(0.45, -1.0, 0.55)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.94, 0.82)
    light.castShadows = true
    light.shadowBias = BiasParameters(0.00025, 0.5)
    light.shadowCascade = CascadeParameters(10.0, 30.0, 90.0, 0.0, 0.8)

    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.1
    camera_.farClip = 300.0
    camera_.fov = 45.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))
    renderer.hdrRendering = true
end

local function UpdateCamera()
    if cameraNode_ == nil then return end
    local yaw = math.rad(cameraYaw_)
    local pitch = math.rad(cameraPitch_)
    local target = Vector3(0, 0.2, 0)
    local x = math.sin(yaw) * math.cos(pitch) * cameraDistance_
    local y = math.sin(pitch) * cameraDistance_
    local z = -math.cos(yaw) * math.cos(pitch) * cameraDistance_
    cameraNode_.position = target + Vector3(x, y, z)
    cameraNode_:LookAt(target)
end

local function EnterPlantView()
    viewMode_ = ViewMode.PLANT
    cameraYaw_ = CONFIG.PlantViewYaw
    cameraPitch_ = CONFIG.PlantViewPitch
    cameraDistance_ = CONFIG.PlantViewDistance
    UpdateCamera()
    ShowToast("进入种植模式，点击田地播种或收获")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function EnterFarmView()
    viewMode_ = ViewMode.FARM
    cameraYaw_ = CONFIG.FarmViewYaw
    cameraPitch_ = CONFIG.FarmViewPitch
    cameraDistance_ = CONFIG.FarmViewDistance
    UpdateCamera()
    ShowToast("自由查看农场")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function PlotWorldPosition(index)
    local col = ((index - 1) % CONFIG.GridCols) + 1
    local row = math.floor((index - 1) / CONFIG.GridCols) + 1
    local startX = -((CONFIG.GridCols - 1) * CONFIG.PlotSpacing) * 0.5
    local startZ = -((CONFIG.GridRows - 1) * CONFIG.PlotSpacing) * 0.5
    return Vector3(startX + (col - 1) * CONFIG.PlotSpacing, 0.08, startZ + (row - 1) * CONFIG.PlotSpacing)
end

local function CreateSelectionFrame(plot)
    local root = plot.node:CreateChild("SelectionFrame")
    root.enabled = false
    plot.selection = root
end

local function CreateRoundedPlotSurface(plotNode, material)
    local moundModels = {}

    local function addPiece(name, modelPath, position, scale, pieceMaterial, collect)
        local node = plotNode:CreateChild(name)
        node.position = position
        node.scale = scale
        local model = node:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", modelPath))
        model:SetMaterial(pieceMaterial)
        model.castShadows = false
        if collect then
            table.insert(moundModels, model)
        end
    end

    local function addRoundedRect(prefix, y, h, w, d, r, pieceMaterial, collect)
        local ox = w * 0.5 - r
        local oz = d * 0.5 - r
        addPiece(prefix .. "CoreLong", "Models/Box.mdl", Vector3(0, y, 0), Vector3(w - r * 2.0, h, d), pieceMaterial, collect)
        addPiece(prefix .. "CoreWide", "Models/Box.mdl", Vector3(0, y, 0), Vector3(w, h, d - r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerNE", "Models/Cylinder.mdl", Vector3(ox, y, oz), Vector3(r * 2.0, h * 1.02, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerNW", "Models/Cylinder.mdl", Vector3(-ox, y, oz), Vector3(r * 2.0, h * 1.02, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSE", "Models/Cylinder.mdl", Vector3(ox, y, -oz), Vector3(r * 2.0, h * 1.02, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSW", "Models/Cylinder.mdl", Vector3(-ox, y, -oz), Vector3(r * 2.0, h * 1.02, r * 2.0), pieceMaterial, collect)
    end

    addRoundedRect("Base", -0.08, 0.24, 1.22, 1.22, 0.18, materials_.soilSide, false)
    addRoundedRect("GrassTop", 0.08, 0.12, 1.32, 1.32, 0.18, materials_.grassTop, false)
    addRoundedRect("DirtMound", 0.2, 0.12, 1.02, 1.02, 0.16, material, true)

    return moundModels
end

local function SetPlotMaterial(plot, material)
    if plot.soilModels ~= nil then
        for _, model in ipairs(plot.soilModels) do
            model:SetMaterial(material)
        end
    elseif plot.soilModel ~= nil then
        plot.soilModel:SetMaterial(material)
    end
end

local function CreateFarm()
    for i = 1, CONFIG.GridCols * CONFIG.GridRows do
        local plotNode = scene_:CreateChild("Plot" .. i)
        plotNode.position = PlotWorldPosition(i)
        plotNode.scale = Vector3(CONFIG.PlotSize, 1.0, CONFIG.PlotSize)
        local unlocked = i <= unlockedPlotCount_
        local baseMaterial = materials_.soilLocked
        if unlocked then
            baseMaterial = materials_.soil
        end
        local models = CreateRoundedPlotSurface(plotNode, baseMaterial)

        local plot = {
            node = plotNode,
            soilModel = nil,
            soilModels = models,
            plant = nil,
            selection = nil,
            unlocked = unlocked,
            lockNode = nil,
        }
        if not unlocked then
            plot.lockNode = nil
        end
        plots_[i] = plot
        CreateSelectionFrame(plot)
    end

end

local function RefreshSelection()
    for i, plot in ipairs(plots_) do
        if plot.selection ~= nil then
            plot.selection.enabled = (i == selectedPlot_)
        end
        if not plot.unlocked then
            SetPlotMaterial(plot, materials_.soilLocked)
        elseif i == selectedPlot_ then
            SetPlotMaterial(plot, materials_.soilSelected)
        else
            SetPlotMaterial(plot, materials_.soil)
        end
    end
end

local function RollMutation(plant)
    local mutation = {
        sizeScale = 1.0,
        sizePrefix = nil,
        colorMutation = nil,
        specials = {},
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
    }

    if math.random() < plant.volumeProb then
        mutation.sizeScale = 1.5 + math.random() * 1.5
        mutation.priceMultiplier = mutation.priceMultiplier * mutation.sizeScale * 2.0
        mutation.timeMultiplier = mutation.timeMultiplier * 1.15
        if mutation.sizeScale < 2.0 then
            mutation.sizePrefix = RandItem({ "丰硕的", "敦实的", "饱满的" })
        elseif mutation.sizeScale < 2.5 then
            mutation.sizePrefix = RandItem({ "巨型的", "膨胀的", "山峦般的" })
        else
            mutation.sizePrefix = RandItem({ "泰坦", "巨神", "穹顶" })
        end
    end

    if math.random() < plant.colorProb then
        mutation.colorMutation = RandItem(COLOR_MUTATIONS)
    end

    for _, special in ipairs(SPECIAL_MUTATIONS) do
        if math.random() < plant.specialProb then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * special.multiplier
            mutation.timeMultiplier = mutation.timeMultiplier * special.timeMultiplier
        end
    end

    return mutation
end

local function BuildCropName(plant, mutation)
    local prefixes = {}
    if mutation.sizePrefix ~= nil then
        table.insert(prefixes, mutation.sizePrefix)
    end
    if mutation.colorMutation ~= nil then
        table.insert(prefixes, RandItem(mutation.colorMutation.prefixes))
    end
    for _, special in ipairs(mutation.specials) do
        table.insert(prefixes, RandItem(special.prefixes))
    end
    if #prefixes == 0 then
        return plant.name
    end
    return table.concat(prefixes, "") .. plant.name
end

local function ResolvePlantMaterial(plant, mutation)
    if HasSpecial(mutation, "gold") then
        return materials_.gold
    end
    if HasSpecial(mutation, "frozen") then
        return materials_.frozen
    end
    if HasSpecial(mutation, "glow") then
        return materials_.glow
    end
    if HasSpecial(mutation, "chocolate") then
        return materials_.chocolate
    end
    if HasSpecial(mutation, "ceramic") then
        return materials_.ceramic
    end
    if HasSpecial(mutation, "void") then
        return materials_.void
    end

    local color = plant.color
    if mutation.colorMutation ~= nil then
        color = mutation.colorMutation.color
    end
    local key = "plant_" .. plant.name .. tostring(math.random(100000, 999999))
    return CreateMaterial(key, color, 0.0, 0.42)
end

local function CreateLeaves(parent, count, height, radius)
    for i = 1, count do
        local angle = (i - 1) * (360 / count)
        local rad = math.rad(angle)
        local leaf = AddModel(parent, "LeafBlock", "Models/Box.mdl", Vector3(math.cos(rad) * radius, height, math.sin(rad) * radius), Vector3(0.16, 0.08, 0.28), materials_.leaf)
        leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(12, Vector3.RIGHT)
    end
    AddModel(parent, "LeafCoreBlock", "Models/Box.mdl", Vector3(0, height + 0.04, 0), Vector3(0.18, 0.1, 0.18), materials_.leaf)
end

local function CreateBlockStem(parent, height, width)
    AddModel(parent, "StemBlock", "Models/Box.mdl", Vector3(0, height * 0.5, 0), Vector3(width, height, width), materials_.stem)
end

local function CreateBlockFruit(parent, name, position, scale, material)
    AddModel(parent, name, "Models/Box.mdl", position, scale, material)
end

local function CreateBlockFlowerHead(parent, material, y, petalCount)
    local centerMat = CreateMaterial("center" .. tostring(math.random(100000, 999999)), Color(0.32, 0.18, 0.06, 1.0), 0.0, 0.6)
    AddModel(parent, "FlowerCenterBlock", "Models/Box.mdl", Vector3(0, y, 0), Vector3(0.2, 0.2, 0.12), centerMat)
    for i = 1, petalCount do
        local angle = (i - 1) * (360 / petalCount)
        local rad = math.rad(angle)
        local petal = AddModel(parent, "PetalBlock", "Models/Box.mdl", Vector3(math.cos(rad) * 0.22, y, math.sin(rad) * 0.22), Vector3(0.16, 0.12, 0.16), material)
        petal.rotation = Quaternion(angle, Vector3.UP)
    end
end

local function CreatePlantVisual(parent, plant, mutation, material)
    local visual = parent:CreateChild("Visual")
    local stageScale = 0.42
    visual.scale = Vector3(stageScale, stageScale, stageScale) * mutation.sizeScale

    if plant.visual == "root" then
        CreateBlockFruit(visual, "RootBlock", Vector3(0, 0.24, 0), Vector3(0.28, 0.46, 0.28), material)
        CreateBlockFruit(visual, "RootTipBlock", Vector3(0, -0.04, 0), Vector3(0.18, 0.16, 0.18), material)
        CreateLeaves(visual, 5, 0.55, 0.15)
    elseif plant.visual == "vine" then
        CreateBlockStem(visual, 0.72, 0.08)
        CreateLeaves(visual, 5, 0.58, 0.22)
        CreateBlockFruit(visual, "FruitBlockA", Vector3(0.22, 0.62, 0.04), Vector3(0.24, 0.24, 0.24), material)
        CreateBlockFruit(visual, "FruitBlockB", Vector3(-0.2, 0.44, -0.08), Vector3(0.2, 0.2, 0.2), material)
    elseif plant.visual == "berry" then
        CreateBlockStem(visual, 0.48, 0.08)
        CreateLeaves(visual, 5, 0.42, 0.24)
        CreateBlockFruit(visual, "BerryBlockA", Vector3(0.2, 0.44, 0.06), Vector3(0.16, 0.18, 0.16), material)
        CreateBlockFruit(visual, "BerryBlockB", Vector3(-0.16, 0.38, -0.08), Vector3(0.14, 0.16, 0.14), material)
    elseif plant.visual == "cluster" or plant.visual == "hydrangea" then
        CreateBlockStem(visual, 0.68, 0.1)
        CreateLeaves(visual, 5, 0.52, 0.24)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local r = 0.16
            CreateBlockFruit(visual, "ClusterBlock", Vector3(math.cos(angle) * r, 0.78, math.sin(angle) * r), Vector3(0.18, 0.18, 0.18), material)
        end
    elseif plant.visual == "gourd" or plant.visual == "melon" then
        CreateLeaves(visual, 6, 0.34, 0.34)
        CreateBlockFruit(visual, "BigFruitBlock", Vector3(0, 0.38, 0), Vector3(0.56, 0.42, 0.56), material)
    elseif plant.visual == "pineapple" then
        CreateBlockFruit(visual, "TallFruitBlock", Vector3(0, 0.42, 0), Vector3(0.34, 0.64, 0.34), material)
        CreateLeaves(visual, 6, 0.8, 0.12)
    elseif plant.visual == "mushroom" then
        local stemMat = CreateMaterial("mushStem" .. tostring(math.random(100000, 999999)), Color(0.86, 0.76, 0.58, 1.0), 0.0, 0.55)
        CreateBlockFruit(visual, "MushStemBlock", Vector3(0, 0.26, 0), Vector3(0.2, 0.48, 0.2), stemMat)
        CreateBlockFruit(visual, "MushCapBlock", Vector3(0, 0.58, 0), Vector3(0.5, 0.18, 0.5), material)
    elseif plant.visual == "cactus" then
        CreateBlockFruit(visual, "CactusBody", Vector3(0, 0.55, 0), Vector3(0.24, 1.0, 0.24), material)
        CreateBlockFruit(visual, "CactusArmL", Vector3(-0.28, 0.62, 0), Vector3(0.16, 0.42, 0.16), material)
        CreateBlockFruit(visual, "CactusArmR", Vector3(0.28, 0.78, 0), Vector3(0.16, 0.34, 0.16), material)
    elseif plant.visual == "sunflower" then
        CreateBlockStem(visual, 0.9, 0.08)
        CreateLeaves(visual, 4, 0.5, 0.2)
        CreateBlockFlowerHead(visual, material, 0.98, 8)
    elseif plant.visual == "rose" then
        CreateBlockStem(visual, 0.78, 0.08)
        CreateLeaves(visual, 4, 0.48, 0.18)
        CreateBlockFlowerHead(visual, material, 0.86, 6)
    elseif plant.visual == "dandelion" then
        CreateBlockStem(visual, 0.72, 0.06)
        CreateBlockFlowerHead(visual, material, 0.8, 8)
    elseif plant.visual == "pepper" or plant.visual == "starfruit" then
        CreateBlockStem(visual, 0.6, 0.08)
        CreateLeaves(visual, 5, 0.5, 0.22)
        CreateBlockFruit(visual, "FruitBlock", Vector3(0.18, 0.58, 0.08), Vector3(0.18, 0.3, 0.18), material)
        CreateBlockFruit(visual, "FruitBlock2", Vector3(-0.18, 0.44, -0.06), Vector3(0.16, 0.24, 0.16), material)
    else
        CreateBlockStem(visual, 0.74, 0.08)
        CreateLeaves(visual, 4, 0.5, 0.18)
        CreateBlockFlowerHead(visual, material, 0.84, 6)
    end

    return visual
end

local function CreateOrbitEffect(parent, name, material, count, radius, y, scale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = math.rad((i - 1) * (360 / count))
        AddModel(root, name .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), scale, material)
    end
    return root
end

local function CreateSpecialEffects(plantData)
    local root = plantData.root
    plantData.effectNodes = {}
    local mutation = plantData.mutation

    if HasSpecial(mutation, "wet") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "WaterDrops", materials_.waterDrop, 8, 0.55 * mutation.sizeScale, 0.8, Vector3(0.055, 0.11, 0.055)))
    end
    if HasSpecial(mutation, "stardust") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Stars", materials_.star, 10, 0.75 * mutation.sizeScale, 1.2, Vector3(0.06, 0.06, 0.06)))
    end
    if HasSpecial(mutation, "cloud") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Clouds", materials_.cloud, 5, 0.5 * mutation.sizeScale, 0.95, Vector3(0.2, 0.12, 0.14)))
    end
    if HasSpecial(mutation, "pollen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Pollen", materials_.pollen, 12, 0.65 * mutation.sizeScale, 0.9, Vector3(0.035, 0.035, 0.035)))
    end
    if HasSpecial(mutation, "void") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "VoidRing", materials_.void, 14, 0.8 * mutation.sizeScale, 0.9, Vector3(0.045, 0.045, 0.045)))
    end
    if HasSpecial(mutation, "frozen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "ColdMist", materials_.cloud, 6, 0.42 * mutation.sizeScale, 0.35, Vector3(0.12, 0.05, 0.12)))
    end
end

local function PlantSeed(plotIndex, plantIndex)
    local plot = plots_[plotIndex]
    if plot == nil or not plot.unlocked or plot.plant ~= nil then return false end
    local plant = PLANTS[plantIndex]
    if seedBag_[plantIndex] == nil or seedBag_[plantIndex] <= 0 then
        return false
    end

    seedBag_[plantIndex] = seedBag_[plantIndex] - 1
    local mutation = RollMutation(plant)
    local cropName = BuildCropName(plant, mutation)
    local root = plot.node:CreateChild("PlantRoot")
    root.position = Vector3(0, 0.28, 0)
    local material = ResolvePlantMaterial(plant, mutation)
    local visual = CreatePlantVisual(root, plant, mutation, material)

    local price = math.floor(plant.fruitPrice * mutation.priceMultiplier + 0.5)
    local growTime = plant.growTime * mutation.timeMultiplier
    plot.plant = {
        config = plant,
        root = root,
        visual = visual,
        material = material,
        mutation = mutation,
        effectNodes = {},
        name = cropName,
        price = price,
        elapsed = 0,
        growTime = growTime,
        mature = false,
    }
    CreateSpecialEffects(plot.plant)
    print(string.format("播种: 田地%d %s，成熟时间 %.1fs，预估售价 %d", plotIndex, cropName, growTime, price))
    return true
end

local function HarvestPlot(plotIndex)
    local plot = plots_[plotIndex]
    if plot == nil or plot.plant == nil or not plot.plant.mature then return false end
    local crop = plot.plant
    table.insert(harvested_, { name = crop.name, price = crop.price, rarity = crop.config.rarity })
    crop.root:Remove()
    plot.plant = nil
    print("收获: " .. crop.name .. " 价值 " .. crop.price)
    return true
end

local function BuySelectedSeed()
    local plant = PLANTS[selectedSeed_]
    if money_ < plant.seedPrice then
        print("金币不足，无法购买: " .. plant.name)
        return false
    end
    money_ = money_ - plant.seedPrice
    seedBag_[selectedSeed_] = (seedBag_[selectedSeed_] or 0) + 1
    print("购买种子: " .. plant.name .. "，剩余金币 " .. money_)
    return true
end

local function SellAllHarvested()
    if #harvested_ == 0 then
        print("背包没有可出售作物")
        return 0
    end
    local total = 0
    for _, item in ipairs(harvested_) do
        total = total + item.price
    end
    harvested_ = {}
    money_ = money_ + total
    print("出售全部作物，获得金币 " .. total)
    return total
end

local function GetPlotText(plot)
    if plot == nil then
        return "未知田地"
    end
    if not plot.unlocked then
        return "未解锁"
    end
    if plot.plant == nil then
        return "空田地"
    end
    local crop = plot.plant
    if crop.mature then
        return string.format("%s 已成熟 | 售价 %d", crop.name, crop.price)
    end
    local progress = math.floor((crop.elapsed / crop.growTime) * 100)
    return string.format("%s 生长中 %d%% | %.1fs", crop.name, progress, math.max(0, crop.growTime - crop.elapsed))
end

local function CountHarvestedValue()
    local value = 0
    for _, item in ipairs(harvested_) do
        value = value + item.price
    end
    return value
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


local function PerformPlotAction(plotIndex)
    selectedPlot_ = plotIndex
    RefreshSelection()
    local plot = plots_[selectedPlot_]
    if plot == nil then return end

    if not plot.unlocked then
        ShowToast("这块田地尚未解锁")
        RefreshUI(true)
        return
    end

    if viewMode_ ~= ViewMode.PLANT then
        ShowToast("当前是查看状态，请先点击下方“开始种植”")
        RefreshUI(true)
        return
    end

    if plot.plant == nil then
        if PlantSeed(selectedPlot_, selectedSeed_) then
            ShowToast("已播种 " .. PLANTS[selectedSeed_].name)
        else
            ShowToast("没有该种子，先点击购买")
        end
    elseif plot.plant.mature then
        local cropName = plot.plant.name
        if HarvestPlot(selectedPlot_) then
            ShowToast("收获 " .. cropName)
        end
    else
        local remain = math.max(0, plot.plant.growTime - plot.plant.elapsed)
        ShowToast(string.format("%s 还需 %.1fs", plot.plant.name, remain))
    end
    RefreshUI(true)
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
    if viewMode_ == ViewMode.FARM then
        actionText = "查看状态: 点击田地查看状态；点击下方“开始种植”后才能播种/收获"
    elseif selectedPlot ~= nil and selectedPlot.plant ~= nil and selectedPlot.plant.mature then
        actionText = "种植模式: 点击田地收获成熟作物"
    elseif selectedPlot ~= nil and selectedPlot.plant == nil then
        actionText = "种植模式: 点击已解锁空田播种"
    else
        actionText = "种植模式: 查看生长进度"
    end

    if moneyLabel_ ~= nil then
        moneyLabel_:SetText("金币 " .. money_)
    end
    if seedLabel_ ~= nil then
        seedLabel_:SetText(string.format("当前种子: %s  %s  %d金  拥有%d", seed.name, seed.rarity, seed.seedPrice, owned))
    end
    if plotLabel_ ~= nil then
        plotLabel_:SetText(string.format("田地 %d/%d  解锁%d/%d  %s", selectedPlot_, #plots_, unlockedPlotCount_, #plots_, GetPlotText(selectedPlot)))
    end
    if actionLabel_ ~= nil then
        actionLabel_:SetText(actionText)
    end
    if inventoryLabel_ ~= nil then
        inventoryLabel_:SetText(string.format("背包 %d件 / %d金", #harvested_, CountHarvestedValue()))
    end
    if actionButton_ ~= nil then
        if viewMode_ == ViewMode.FARM then
            actionButton_:SetText("开始种植")
        else
            actionButton_:SetText("返回查看花园")
        end
    end
    RefreshSeedButtons()
end

RebuildUI = function()
    if not uiInitialized_ then
        UI.Init({
            theme = "dark",
            fonts = {
                { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } },
                { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
            },
            scale = UI.Scale.DEFAULT,
        })
        uiInitialized_ = true
    end

    moneyLabel_ = UI.Label { text = "金币 --", fontSize = 18, fontColor = { 255, 235, 135, 255 } }
    seedLabel_ = UI.Label { text = "当前种子 --", fontSize = 13, fontColor = { 220, 255, 220, 255 } }
    plotLabel_ = UI.Label { text = "点击田地查看状态", fontSize = 13, fontColor = { 235, 240, 255, 255 } }
    actionLabel_ = UI.Label { text = "点击田地播种或收获", fontSize = 13, fontColor = { 255, 255, 255, 255 } }
    inventoryLabel_ = UI.Label { text = "背包 --", fontSize = 13, fontColor = { 255, 220, 160, 255 } }
    toastLabel_ = UI.Label {
        text = "当前为查看状态，点击下方开始种植",
        fontSize = 14,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
    }
    helpLabel_ = UI.Label {
        text = "默认查看花园状态：点击田地查看，拖动旋转，滚轮/双指缩放",
        fontSize = 12,
        fontColor = { 210, 220, 230, 230 },
        textAlign = "center",
    }

    actionButton_ = UI.Button {
        text = "开始种植",
        variant = "primary",
        height = 44,
        onClick = function()
            suppressNextWorldTap_ = true
            if viewMode_ == ViewMode.FARM then
                EnterPlantView()
            else
                EnterFarmView()
            end
        end,
    }

    local prevSeedButton = UI.Button {
        text = "上一种",
        height = 40,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ - 1
            if selectedSeed_ < 1 then selectedSeed_ = #PLANTS end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    local nextSeedButton = UI.Button {
        text = "下一种",
        height = 40,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ + 1
            if selectedSeed_ > #PLANTS then selectedSeed_ = 1 end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    local buyButton = UI.Button {
        text = "购买种子",
        variant = "primary",
        height = 44,
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
        height = 44,
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

    local rotateLeftButton = UI.Button {
        text = "左转",
        height = 38,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraYaw_ = cameraYaw_ - 22.5
            UpdateCamera()
        end,
    }

    local rotateRightButton = UI.Button {
        text = "右转",
        height = 38,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraYaw_ = cameraYaw_ + 22.5
            UpdateCamera()
        end,
    }

    local zoomInButton = UI.Button {
        text = "放大",
        height = 38,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraDistance_ = math.max(CONFIG.FarmViewMinDistance, cameraDistance_ - 1.0)
            UpdateCamera()
        end,
    }

    local zoomOutButton = UI.Button {
        text = "缩小",
        height = 38,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraDistance_ = math.min(CONFIG.FarmViewMaxDistance, cameraDistance_ + 1.0)
            UpdateCamera()
        end,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute",
                top = 10,
                left = 10,
                right = 10,
                padding = 10,
                gap = 4,
                backgroundColor = { 18, 24, 22, 170 },
                borderColor = { 120, 220, 130, 120 },
                borderWidth = 1,
                borderRadius = 12,
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label { text = "我的花园", fontSize = 18, fontColor = { 150, 255, 165, 255 } },
                            moneyLabel_,
                        },
                    },
                    plotLabel_,
                    actionLabel_,
                    inventoryLabel_,
                },
            },
            UI.Panel {
                position = "absolute",
                top = 132,
                left = 28,
                right = 28,
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        padding = 8,
                        backgroundColor = { 12, 18, 16, 150 },
                        borderRadius = 12,
                        children = { toastLabel_ },
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                left = 10,
                right = 10,
                bottom = 10,
                padding = 10,
                gap = 8,
                backgroundColor = { 12, 15, 18, 220 },
                borderColor = { 255, 255, 255, 35 },
                borderWidth = 1,
                borderRadius = 16,
                children = viewMode_ == ViewMode.FARM and {
                    actionButton_,
                } or {
                    helpLabel_,
                    actionButton_,
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        children = {
                            UI.Panel { flexGrow = 1, children = { rotateLeftButton } },
                            UI.Panel { flexGrow = 1, children = { rotateRightButton } },
                            UI.Panel { flexGrow = 1, children = { zoomInButton } },
                            UI.Panel { flexGrow = 1, children = { zoomOutButton } },
                        },
                    },
                    seedLabel_,
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Panel { flexGrow = 1, children = { prevSeedButton } },
                            UI.Panel { flexGrow = 1, children = { nextSeedButton } },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Panel { flexGrow = 1, children = { buyButton } },
                            UI.Panel { flexGrow = 1, children = { sellButton } },
                        },
                    },
                },
            },
        }
    }
    UI.SetRoot(root)
    RefreshUI(true)
end

local function SelectPlotByDelta(dx, dz)
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

local function IsWorldTapArea(x, y)
    local h = graphics:GetHeight()
    local bottomReserved = 86
    if viewMode_ == ViewMode.PLANT then
        bottomReserved = 260
    end
    return y > 170 and y < h - bottomReserved
end

local function PlotIndexFromScreen(x, y)
    if camera_ == nil then return nil end
    if not IsWorldTapArea(x, y) then return nil end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local ray = camera_:GetScreenRay(x / w, y / h)
    if math.abs(ray.direction.y) < 0.001 then return nil end

    local t = (0.08 - ray.origin.y) / ray.direction.y
    if t <= 0 then return nil end
    local hit = ray.origin + ray.direction * t

    local bestIndex = nil
    local bestDist = 9999
    for i = 1, #plots_ do
        local pos = PlotWorldPosition(i)
        local dx = hit.x - pos.x
        local dz = hit.z - pos.z
        local dist = dx * dx + dz * dz
        if dist < bestDist then
            bestDist = dist
            bestIndex = i
        end
    end

    local halfSize = CONFIG.PlotSize * 0.72
    if bestIndex ~= nil and bestDist <= halfSize * halfSize then
        return bestIndex
    end
    return nil
end

local function HandleWorldTap(x, y)
    if suppressNextWorldTap_ then
        suppressNextWorldTap_ = false
        return
    end
    local plotIndex = PlotIndexFromScreen(x, y)
    if plotIndex ~= nil then
        if viewMode_ == ViewMode.FARM then
            selectedPlot_ = plotIndex
            RefreshSelection()
            ShowToast("已选中田地，可查看状态；点击下方开始种植后操作")
            RefreshUI(true)
        else
            PerformPlotAction(plotIndex)
        end
    end
end

function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function HandleMouseMove(eventType, eventData)
    if viewMode_ ~= ViewMode.FARM then return end
    if not input:GetMouseButtonDown(MOUSEB_LEFT) then return end
    local y = eventData["Y"]:GetInt()
    if not IsWorldTapArea(eventData["X"]:GetInt(), y) then return end

    local dx = eventData["DX"]:GetInt()
    local dy = eventData["DY"]:GetInt()
    if math.abs(dx) > 0 or math.abs(dy) > 0 then
        cameraYaw_ = cameraYaw_ + dx * 0.16
        cameraPitch_ = Clamp(cameraPitch_ + dy * 0.08, 24.0, 68.0)
        UpdateCamera()
    end
end

function HandleMouseWheel(eventType, eventData)
    if viewMode_ ~= ViewMode.FARM then return end
    local wheel = eventData["Wheel"]:GetInt()
    if wheel == 0 then return end
    cameraDistance_ = Clamp(cameraDistance_ - wheel * 0.8, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
    UpdateCamera()
end

function HandleTouchBegin(eventType, eventData)
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function HandleTouchMove(eventType, eventData)
    touchGestureActive_ = true
end

local function UpdateTouchCameraGesture()
    if viewMode_ ~= ViewMode.FARM then
        lastPinchDistance_ = 0
        return
    end

    local touchCount = input.numTouches
    if touchCount == 1 then
        lastPinchDistance_ = 0
        local touch = input:GetTouch(0)
        if touch ~= nil and not touch.touchedElement then
            local dx = touch.delta.x
            local dy = touch.delta.y
            if math.abs(dx) > 0 or math.abs(dy) > 0 then
                touchGestureActive_ = true
                cameraYaw_ = cameraYaw_ + dx * 0.16
                cameraPitch_ = Clamp(cameraPitch_ + dy * 0.08, 24.0, 68.0)
                UpdateCamera()
            end
        end
    elseif touchCount >= 2 then
        local touch1 = input:GetTouch(0)
        local touch2 = input:GetTouch(1)
        if touch1 ~= nil and touch2 ~= nil and not touch1.touchedElement and not touch2.touchedElement then
            local dx = touch1.position.x - touch2.position.x
            local dy = touch1.position.y - touch2.position.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if lastPinchDistance_ > 0 then
                local delta = dist - lastPinchDistance_
                if math.abs(delta) > 0.5 then
                    touchGestureActive_ = true
                    cameraDistance_ = Clamp(cameraDistance_ - delta * 0.018, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
                    UpdateCamera()
                end
            end
            lastPinchDistance_ = dist
        end
    else
        lastPinchDistance_ = 0
        touchGestureActive_ = false
    end
end

local function HandleInput(dt)
    if input:GetKeyPress(KEY_LEFT) then SelectPlotByDelta(-1, 0) end
    if input:GetKeyPress(KEY_RIGHT) then SelectPlotByDelta(1, 0) end
    if input:GetKeyPress(KEY_UP) then SelectPlotByDelta(0, -1) end
    if input:GetKeyPress(KEY_DOWN) then SelectPlotByDelta(0, 1) end
    if input:GetKeyPress(KEY_Q) then CycleSeed(-1) end
    if input:GetKeyPress(KEY_E) then CycleSeed(1) end
    if input:GetKeyPress(KEY_B) then BuySelectedSeed(); RefreshUI(true) end
    if input:GetKeyPress(KEY_G) then SellAllHarvested(); RefreshUI(true) end

    if input:GetKeyPress(KEY_SPACE) then
        if viewMode_ == ViewMode.FARM then
            EnterPlantView()
        else
            local plot = plots_[selectedPlot_]
            if plot ~= nil and plot.plant ~= nil and plot.plant.mature then
                HarvestPlot(selectedPlot_)
            elseif plot ~= nil and plot.plant == nil then
                PlantSeed(selectedPlot_, selectedSeed_)
            end
            RefreshUI(true)
        end
    end

    if input:GetKeyDown(KEY_A) then
        cameraYaw_ = cameraYaw_ - 70.0 * dt
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_D) then
        cameraYaw_ = cameraYaw_ + 70.0 * dt
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_W) then
        cameraDistance_ = math.max(CONFIG.FarmViewMinDistance, cameraDistance_ - 8.0 * dt)
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_S) then
        cameraDistance_ = math.min(CONFIG.FarmViewMaxDistance, cameraDistance_ + 8.0 * dt)
        UpdateCamera()
    end
end

local function SetVisualScaleByProgress(plantData)
    local progress = plantData.elapsed / plantData.growTime
    progress = Clamp(progress, 0.0, 1.0)
    local scale = (0.28 + 0.72 * progress) * plantData.mutation.sizeScale
    plantData.visual.scale = Vector3(scale, scale, scale)
end

local function RainbowColor(t)
    local r = 0.5 + 0.5 * math.sin(t)
    local g = 0.5 + 0.5 * math.sin(t + 2.094)
    local b = 0.5 + 0.5 * math.sin(t + 4.188)
    return Color(r, g, b, 1.0)
end

local function UpdatePlantEffects(plantData, dt)
    local mutation = plantData.mutation
    if HasSpecial(mutation, "rainbow") then
        local rainbow = RainbowColor(gameTime_ * 2.5)
        plantData.material:SetShaderParameter("MatDiffColor", Variant(rainbow))
        plantData.material:SetShaderParameter("MatEmissiveColor", Variant(Color(rainbow.r * 0.35, rainbow.g * 0.35, rainbow.b * 0.35, 1.0)))
    end

    for i, effect in ipairs(plantData.effectNodes) do
        effect:Rotate(Quaternion((25 + i * 18) * dt, Vector3.UP))
        local bob = math.sin(gameTime_ * (1.4 + i * 0.17)) * 0.035
        effect.position = Vector3(0, bob, 0)
    end
end

local function UpdatePlants(dt)
    gameTime_ = gameTime_ + dt
    for _, plot in ipairs(plots_) do
        local plantData = plot.plant
        if plantData ~= nil then
            if not plantData.mature then
                plantData.elapsed = plantData.elapsed + dt
                SetVisualScaleByProgress(plantData)
                if plantData.elapsed >= plantData.growTime then
                    plantData.mature = true
                    plantData.elapsed = plantData.growTime
                    plantData.root:Translate(Vector3(0, 0.06, 0))
                    print("成熟: " .. plantData.name .. "，可收获")
                end
            else
                plantData.root:Rotate(Quaternion(12.0 * dt, Vector3.UP))
            end
            UpdatePlantEffects(plantData, dt)
        end
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    HandleInput(dt)
    UpdateTouchCameraGesture()
    UpdatePlants(dt)
    if toastTimer_ > 0 then
        toastTimer_ = toastTimer_ - dt
        if toastTimer_ <= 0 and toastLabel_ ~= nil then
            if viewMode_ == ViewMode.FARM then
                toastLabel_:SetText("当前为查看状态，点击下方开始种植")
            else
                toastLabel_:SetText("种植模式：点击田地播种或收获")
            end
        end
    end
    RefreshUI(false)
end

function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title
    math.randomseed(os.time())

    InitMaterials()
    CreateScene()
    CreateFarm()
    RebuildUI()

    for i = 1, #PLANTS do
        seedBag_[i] = 0
    end
    seedBag_[1] = 4
    seedBag_[2] = 2
    seedBag_[3] = 1
    RefreshUI(true)

    RefreshSelection()
    UpdateCamera()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SampleInitMouseMode(MM_FREE)

    print("=== Grow A Garden 核心玩法原型启动 ===")
    print("已赠送胡萝卜x4、番茄x2、草莓x1，可先播种体验变异与成熟循环。")
end

function Stop()
    UI.Shutdown()
end
