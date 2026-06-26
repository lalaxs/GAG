-- ============================================================================
-- 作物视觉模块 (Plant Visual)
-- Grow A Garden
-- ============================================================================
-- 管理程序化材质、作物方块模型、成熟特效。
-- 本模块不处理 UI、不处理播种/收获规则，只负责视觉创建。
-- ============================================================================

local PlantMaterials = require("visuals.plant_materials")

local PlantVisual = {
    materials = {},
}

local EFFECT_DETAIL_INTERVAL = 0.045
local EFFECT_AMBIENT_INTERVAL = 0.08

local function ColorKey(color)
    local r = math.floor((color.r or 0) * 255 + 0.5)
    local g = math.floor((color.g or 0) * 255 + 0.5)
    local b = math.floor((color.b or 0) * 255 + 0.5)
    local a = math.floor((color.a or 1) * 255 + 0.5)
    return string.format("%03d_%03d_%03d_%03d", r, g, b, a)
end

local function CountSpecials(mutation)
    if mutation == nil or mutation.specials == nil then
        return 0
    end
    return #mutation.specials
end

local function GetDominantAuraMaterial(mutation)
    if PlantVisual.HasSpecial(mutation, "rainbow") or PlantVisual.HasSpecial(mutation, "stardust") then
        return PlantVisual.materials.star
    end
    if PlantVisual.HasSpecial(mutation, "gold") then
        return PlantVisual.materials.auraGold
    end
    if PlantVisual.HasSpecial(mutation, "frozen") then
        return PlantVisual.materials.iceCrystal
    end
    if PlantVisual.HasSpecial(mutation, "wet") then
        return PlantVisual.materials.waterDrop
    end
    if PlantVisual.HasSpecial(mutation, "void") then
        return PlantVisual.materials.voidSpark
    end
    if PlantVisual.HasSpecial(mutation, "devour") then
        return PlantVisual.materials.devourEdge
    end
    if PlantVisual.HasSpecial(mutation, "honey") then
        return PlantVisual.materials.honeyGlow
    end
    if PlantVisual.HasSpecial(mutation, "candy") then
        return PlantVisual.materials.candyCrystal
    end
    if PlantVisual.HasSpecial(mutation, "glow") then
        return PlantVisual.materials.magicSpark
    end
    if PlantVisual.HasSpecial(mutation, "pollen") then
        return PlantVisual.materials.pollen
    end
    if PlantVisual.HasSpecial(mutation, "cloud") or PlantVisual.HasSpecial(mutation, "ceramic") then
        return PlantVisual.materials.cloud
    end
    if PlantVisual.HasSpecial(mutation, "chocolate") then
        return PlantVisual.materials.chocolateSpark
    end
    return PlantVisual.materials.auraGreen
end

function PlantVisual.HasSpecial(mutation, key)
    for _, item in ipairs(mutation.specials) do
        if item.key == key then
            return true
        end
    end
    return false
end

function PlantVisual.AddModel(parent, name, modelPath, position, scale, material, castShadows)
    local node = parent:CreateChild(name)
    node.position = position
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", modelPath))
    model:SetMaterial(material)
    if castShadows == nil then
        castShadows = true
    end
    model.castShadows = castShadows
    return node
end

PlantMaterials.Bind(PlantVisual, ColorKey)

local function CreateLeaves(parent, count, height, radius)
    for i = 1, count do
        local angle = (i - 1) * (360 / count)
        local rad = math.rad(angle)
        local leaf = PlantVisual.AddModel(parent, "LeafBlock", "Models/Box.mdl", Vector3(math.cos(rad) * radius, height, math.sin(rad) * radius), Vector3(0.16, 0.08, 0.28), PlantVisual.materials.leaf)
        leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(12, Vector3.RIGHT)
    end
    PlantVisual.AddModel(parent, "LeafCoreBlock", "Models/Box.mdl", Vector3(0, height + 0.04, 0), Vector3(0.18, 0.1, 0.18), PlantVisual.materials.leaf)
end

local function CreateBlockStem(parent, height, width)
    PlantVisual.AddModel(parent, "StemBlock", "Models/Box.mdl", Vector3(0, height * 0.5, 0), Vector3(width, height, width), PlantVisual.materials.stem)
end

local function CreateBlockFruit(parent, name, position, scale, material)
    PlantVisual.AddModel(parent, name, "Models/Box.mdl", position, scale, material)
end

local function CreateBlockFlowerHead(parent, material, y, petalCount)
    local centerMat = PlantVisual.CreateMaterial("center" .. tostring(math.random(100000, 999999)), Color(0.32, 0.18, 0.06, 1.0), 0.0, 0.6)
    PlantVisual.AddModel(parent, "FlowerCenterBlock", "Models/Box.mdl", Vector3(0, y, 0), Vector3(0.2, 0.2, 0.12), centerMat)
    for i = 1, petalCount do
        local angle = (i - 1) * (360 / petalCount)
        local rad = math.rad(angle)
        local petal = PlantVisual.AddModel(parent, "PetalBlock", "Models/Box.mdl", Vector3(math.cos(rad) * 0.22, y, math.sin(rad) * 0.22), Vector3(0.16, 0.12, 0.16), material)
        petal.rotation = Quaternion(angle, Vector3.UP)
    end
end

local function AddFiredCeramicPattern(visual)
    local warmSpot = PlantVisual.materials.ceramicBlue
    local darkCrack = PlantVisual.materials.ceramicDeepBlue

    -- Grow a Garden 风格陶瓷：赤陶烧制质感，少量深色裂纹和暖色烧斑，不做外部粒子。
    local crackYs = { 0.32, 0.58 }
    for layer, y in ipairs(crackYs) do
        local radius = 0.31 + layer * 0.006
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72 + layer * 17)
            local crack = PlantVisual.AddModel(visual, "CeramicCrack" .. layer .. "_" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), Vector3(0.058, 0.008, 0.012), darkCrack, false)
            crack.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(8 + i * 3, Vector3.RIGHT)
        end
    end

    for i = 1, 4 do
        local angle = math.rad(i * 91)
        local radius = 0.27 + (i % 2) * 0.035
        local spot = PlantVisual.AddModel(visual, "CeramicFiredSpot" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, 0.26 + i * 0.095, math.sin(angle) * radius), Vector3(0.05, 0.012, 0.034), warmSpot, false)
        spot.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(10, Vector3.RIGHT)
    end
end

local function AddWetWaterPattern(visual)
    local dropMat = PlantVisual.materials.waterDrop
    local rippleMat = PlantVisual.materials.wetRipple

    -- 潮湿变异：用青蓝色水滴和贴身水纹模型表现，避免和烟雾/花粉类粒子混淆。
    for i = 1, 5 do
        local angle = math.rad((i - 1) * 72 + 12)
        local radius = 0.24 + (i % 2) * 0.045
        local drop = PlantVisual.AddModel(visual, "WetDropOverlay" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, 0.38 + (i % 3) * 0.105, math.sin(angle) * radius), Vector3(0.038, 0.07, 0.038), dropMat, false)
        drop.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(10, Vector3.RIGHT)
    end

    for layer = 1, 2 do
        local y = 0.22 + layer * 0.17
        local radius = 0.29 + layer * 0.025
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90 + layer * 22)
            local ripple = PlantVisual.AddModel(visual, "WetRipple" .. layer .. "_" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), Vector3(0.092, 0.009, 0.018), rippleMat, false)
            ripple.rotation = Quaternion(math.deg(angle) + 8, Vector3.UP) * Quaternion(5, Vector3.RIGHT)
        end
    end
end

local function AddPollenClusterPattern(visual)
    local yellowMat = PlantVisual.materials.pollen
    local orangeMat = PlantVisual.materials.pollenOrange

    -- 花粉变异：用黄橙色团簇和小花粉星点做贴身装饰，颜色与潮湿的蓝色明确区分。
    for i = 1, 7 do
        local angle = math.rad(i * 137.5)
        local radius = 0.18 + (i % 3) * 0.045
        local y = 0.3 + (i % 4) * 0.095
        PlantVisual.AddModel(visual, "PollenCluster" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), Vector3(0.03, 0.03, 0.03), (i % 2 == 0) and orangeMat or yellowMat, false)
    end

    for i = 1, 4 do
        local angle = math.rad((i - 1) * 90 + 30)
        local radius = 0.3
        local star = PlantVisual.AddModel(visual, "PollenStar" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, 0.54 + math.sin(i) * 0.035, math.sin(angle) * radius), Vector3(0.048, 0.008, 0.012), orangeMat, false)
        star.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(36, Vector3.RIGHT)
    end
end

local function AddCloudPuffs(visual)
    local root = visual:CreateChild("CloudPuffOverlayRoot")
    for i = 1, 4 do
        local angle = math.rad((i - 1) * 90 + 25)
        local radius = 0.24 + (i % 2) * 0.045
        local puff = PlantVisual.AddModel(root, "CloudPuffOverlay" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, 0.52 + math.sin(i) * 0.045, math.sin(angle) * radius), Vector3(0.12, 0.08, 0.12), PlantVisual.materials.cloud, false)
        puff.rotation = Quaternion(math.deg(angle), Vector3.UP)
    end
    return root
end

local function AddFrozenShell(visual)
    local shell = PlantVisual.AddModel(visual, "FrozenShell", "Models/Box.mdl", Vector3(0, 0.46, 0), Vector3(0.52, 0.62, 0.52), PlantVisual.materials.iceShell, false)
    shell.rotation = Quaternion(8, Vector3.UP) * Quaternion(4, Vector3.RIGHT)
end

local function AddChocolateCoating(visual)
    local mat = PlantVisual.materials.chocolateSpark
    local topY = 0.72
    for i = 1, 4 do
        local angle = math.rad((i - 1) * 90 + 18)
        local radius = 0.2 + (i % 2) * 0.05
        local stripe = PlantVisual.AddModel(visual, "ChocolateStripe" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, topY - i * 0.035, math.sin(angle) * radius), Vector3(0.055, 0.16, 0.028), mat, false)
        stripe.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(8, Vector3.RIGHT)
    end

    for i = 1, 3 do
        local angle = math.rad((i - 1) * 120 + 35)
        local radius = 0.18
        PlantVisual.AddModel(visual, "ChocolateDrop" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, 0.42 - i * 0.035, math.sin(angle) * radius), Vector3(0.045, 0.065, 0.045), mat, false)
    end
end

local function AddThemedLimitedDetails(visual, plant)
    local theme = plant and plant.visualTheme
    if theme == nil then return end

    if theme == "crystal_sweet" then
        for i = 1, 5 do
            local angle = math.rad(i * 72)
            local gem = PlantVisual.AddModel(visual, "CandyCrystal" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.22, 0.78 + (i % 2) * 0.06, math.sin(angle) * 0.22), Vector3(0.055, 0.12, 0.055), PlantVisual.materials.candyCrystal, false)
            gem.rotation = Quaternion(i * 36, Vector3.UP) * Quaternion(28, Vector3.RIGHT)
        end
    elseif theme == "honey_hive" then
        for i = 1, 6 do
            local angle = math.rad(i * 60)
            PlantVisual.AddModel(visual, "HiveCell" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.18, 0.66 + (i % 2) * 0.035, math.sin(angle) * 0.18), Vector3(0.095, 0.08, 0.045), PlantVisual.materials.honeyGlow, false)
        end
        PlantVisual.AddModel(visual, "HoneyDrop", "Models/Sphere.mdl", Vector3(0.0, 0.43, 0.24), Vector3(0.055, 0.09, 0.055), PlantVisual.materials.honeyGlow, false)
    elseif theme == "dream_candy" then
        for i = 1, 4 do
            local angle = math.rad(i * 90 + 35)
            PlantVisual.AddModel(visual, "DreamSugarOrb" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.25, 0.72 + i * 0.035, math.sin(angle) * 0.25), Vector3(0.075, 0.075, 0.075), PlantVisual.materials.candyCrystal, false)
        end
    elseif theme == "alien_pulse" then
        for i = 1, 4 do
            PlantVisual.AddModel(visual, "PulseRing" .. i, "Models/Torus.mdl", Vector3(0, 0.26 + i * 0.13, 0), Vector3(0.20 + i * 0.018, 0.018, 0.20 + i * 0.018), PlantVisual.materials.alienGlow, false)
        end
    elseif theme == "alien_eye" then
        local eye = PlantVisual.AddModel(visual, "AlienEyeCore", "Models/Sphere.mdl", Vector3(0, 0.83, 0.08), Vector3(0.13, 0.09, 0.13), PlantVisual.materials.alienEye, false)
        eye.rotation = Quaternion(15, Vector3.RIGHT)
        PlantVisual.AddModel(visual, "AlienPupil", "Models/Sphere.mdl", Vector3(0, 0.84, 0.17), Vector3(0.045, 0.032, 0.045), PlantVisual.materials.darkCore, false)
    elseif theme == "zero_gravity" then
        PlantVisual.AddModel(visual, "FloatingEmbryo", "Models/Sphere.mdl", Vector3(0, 1.05, 0), Vector3(0.18, 0.18, 0.18), PlantVisual.materials.alienEye, false)
        PlantVisual.AddModel(visual, "GravityHalo", "Models/Torus.mdl", Vector3(0, 1.05, 0), Vector3(0.27, 0.027, 0.27), PlantVisual.materials.alienGlow, false)
    elseif theme == "dark_moss" then
        for i = 1, 7 do
            local angle = math.rad(i * 51)
            PlantVisual.AddModel(visual, "LightEaterMoss" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.22, 0.48 + (i % 3) * 0.035, math.sin(angle) * 0.22), Vector3(0.08, 0.045, 0.08), PlantVisual.materials.darkCore, false)
        end
    elseif theme == "dark_rift" then
        PlantVisual.AddModel(visual, "RiftCore", "Models/Sphere.mdl", Vector3(0, 0.78, 0), Vector3(0.11, 0.11, 0.11), PlantVisual.materials.darkCore, false)
        PlantVisual.AddModel(visual, "RiftEdge", "Models/Torus.mdl", Vector3(0, 0.78, 0), Vector3(0.21, 0.022, 0.21), PlantVisual.materials.devourEdge, false)
    elseif theme == "moon_shadow_lotus" then
        for i = 1, 5 do
            local angle = math.rad(i * 72)
            local petal = PlantVisual.AddModel(visual, "MoonShadowPetal" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.18, 0.62, math.sin(angle) * 0.18), Vector3(0.13, 0.045, 0.20), PlantVisual.materials.voidSpark, false)
            petal.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(20, Vector3.RIGHT)
        end
        PlantVisual.AddModel(visual, "MoonShadowDew", "Models/Sphere.mdl", Vector3(0, 0.72, 0), Vector3(0.075, 0.075, 0.075), PlantVisual.materials.alienEye, false)
    elseif theme == "ghost_lantern" then
        PlantVisual.AddModel(visual, "GhostLanternGlow", "Models/Sphere.mdl", Vector3(0, 0.78, 0), Vector3(0.13, 0.17, 0.13), PlantVisual.materials.alienEye, false)
        PlantVisual.AddModel(visual, "GhostLanternShade", "Models/Torus.mdl", Vector3(0, 0.78, 0), Vector3(0.21, 0.018, 0.21), PlantVisual.materials.voidSpark, false)
        for i = 1, 4 do
            local angle = math.rad(i * 90 + 45)
            PlantVisual.AddModel(visual, "GhostWisp" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.24, 0.66 + (i % 2) * 0.09, math.sin(angle) * 0.24), Vector3(0.05, 0.05, 0.05), PlantVisual.materials.magicSpark, false)
        end
    elseif theme == "eclipse_crown" then
        PlantVisual.AddModel(visual, "EclipseHalo", "Models/Torus.mdl", Vector3(0, 0.94, 0), Vector3(0.30, 0.024, 0.30), PlantVisual.materials.voidSpark, false)
        PlantVisual.AddModel(visual, "EclipseCore", "Models/Sphere.mdl", Vector3(0, 0.94, 0), Vector3(0.11, 0.11, 0.11), PlantVisual.materials.darkCore, false)
        for i = 1, 8 do
            local angle = math.rad(i * 45)
            local ray = PlantVisual.AddModel(visual, "EclipseRay" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.24, 0.94, math.sin(angle) * 0.24), Vector3(0.035, 0.14, 0.035), PlantVisual.materials.voidSpark, false)
            ray.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(34, Vector3.RIGHT)
        end
    end
end

local function CreateLimitedCrystalBellLily(visual, material)
    local stemMat = PlantVisual.materials.stem
    CreateBlockFruit(visual, "CrystalStem", Vector3(0, 0.38, 0), Vector3(0.055, 0.76, 0.055), stemMat)
    for i = 1, 3 do
        local angle = math.rad(i * 120 + 18)
        local branch = PlantVisual.AddModel(visual, "BellBranch" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.09, 0.66 - i * 0.055, math.sin(angle) * 0.09), Vector3(0.04, 0.16, 0.035), stemMat)
        branch.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(45, Vector3.RIGHT)
        local bell = PlantVisual.AddModel(visual, "SugarBell" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.23, 0.62 - i * 0.055, math.sin(angle) * 0.23), Vector3(0.13, 0.16, 0.13), material, false)
        bell.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(15, Vector3.RIGHT)
        PlantVisual.AddModel(visual, "BellClapper" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.23, 0.51 - i * 0.055, math.sin(angle) * 0.23), Vector3(0.038, 0.038, 0.038), PlantVisual.materials.candyCrystal, false)
    end
    CreateLeaves(visual, 4, 0.26, 0.18)
end

local function CreateLimitedHiveMandrake(visual, material)
    local rootMat = PlantVisual.CreateMaterial("hiveRoot" .. tostring(math.random(100000, 999999)), Color(0.62, 0.40, 0.18, 1.0), 0.0, 0.7)
    CreateBlockFruit(visual, "MandrakeRoot", Vector3(0, 0.25, 0), Vector3(0.24, 0.5, 0.22), rootMat)
    CreateBlockFruit(visual, "RootLegL", Vector3(-0.08, -0.05, 0), Vector3(0.075, 0.18, 0.07), rootMat)
    CreateBlockFruit(visual, "RootLegR", Vector3(0.08, -0.05, 0), Vector3(0.075, 0.18, 0.07), rootMat)
    local hiveMat = PlantVisual.materials.honeyGlow or material
    CreateBlockFruit(visual, "HiveCrownCore", Vector3(0, 0.66, 0), Vector3(0.30, 0.22, 0.30), hiveMat)
    for i = 1, 6 do
        local angle = math.rad(i * 60)
        local cell = PlantVisual.AddModel(visual, "HiveCrownCell" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.20, 0.66, math.sin(angle) * 0.20), Vector3(0.11, 0.12, 0.055), hiveMat, false)
        cell.rotation = Quaternion(math.deg(angle), Vector3.UP)
    end
    PlantVisual.AddModel(visual, "HoneyOrb", "Models/Sphere.mdl", Vector3(0, 0.82, 0), Vector3(0.08, 0.08, 0.08), hiveMat, false)
    CreateLeaves(visual, 3, 0.5, 0.12)
end

local function CreateLimitedDreamCandyNightshade(visual, material)
    local vineMat = PlantVisual.materials.stem
    CreateBlockFruit(visual, "DreamVineA", Vector3(-0.06, 0.36, 0), Vector3(0.055, 0.72, 0.055), vineMat)
    CreateBlockFruit(visual, "DreamVineB", Vector3(0.07, 0.43, 0.02), Vector3(0.05, 0.66, 0.05), vineMat)
    for i = 1, 5 do
        local angle = math.rad(i * 72 + 20)
        local y = 0.42 + (i % 3) * 0.12
        PlantVisual.AddModel(visual, "DreamCandyFruit" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.22, y, math.sin(angle) * 0.22), Vector3(0.09, 0.09, 0.09), material, false)
        PlantVisual.AddModel(visual, "DreamCandyHalo" .. i, "Models/Torus.mdl", Vector3(math.cos(angle) * 0.22, y, math.sin(angle) * 0.22), Vector3(0.13, 0.012, 0.13), PlantVisual.materials.candyCrystal, false)
    end
    CreateLeaves(visual, 4, 0.32, 0.16)
end

local function CreateLimitedPulseSporeTower(visual, material)
    local baseMat = PlantVisual.CreateMaterial("sporeBase" .. tostring(math.random(100000, 999999)), Color(0.10, 0.36, 0.26, 1.0), 0.0, 0.58)
    for i = 1, 5 do
        local y = 0.11 + i * 0.13
        local size = 0.24 - i * 0.018
        CreateBlockFruit(visual, "PulseSegment" .. i, Vector3(0, y, 0), Vector3(size, 0.11, size), i % 2 == 0 and material or baseMat)
        PlantVisual.AddModel(visual, "PulseBand" .. i, "Models/Torus.mdl", Vector3(0, y + 0.04, 0), Vector3(size * 0.68, 0.01, size * 0.68), PlantVisual.materials.alienGlow, false)
    end
    PlantVisual.AddModel(visual, "SporeBeacon", "Models/Sphere.mdl", Vector3(0, 0.86, 0), Vector3(0.12, 0.12, 0.12), PlantVisual.materials.alienGlow, false)
end

local function CreateLimitedAlienEyeFern(visual, material)
    CreateBlockStem(visual, 0.46, 0.07)
    for i = 1, 6 do
        local angle = math.rad(i * 60)
        local leaf = PlantVisual.AddModel(visual, "EyeFernFrond" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.18, 0.48 + (i % 2) * 0.05, math.sin(angle) * 0.18), Vector3(0.07, 0.04, 0.28), material, false)
        leaf.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(36, Vector3.RIGHT)
        PlantVisual.AddModel(visual, "FrondEye" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.31, 0.51 + (i % 2) * 0.05, math.sin(angle) * 0.31), Vector3(0.045, 0.045, 0.045), PlantVisual.materials.alienEye, false)
        PlantVisual.AddModel(visual, "FrondPupil" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.34, 0.51 + (i % 2) * 0.05, math.sin(angle) * 0.34), Vector3(0.018, 0.018, 0.018), PlantVisual.materials.darkCore, false)
    end
    PlantVisual.AddModel(visual, "CentralAlienEye", "Models/Sphere.mdl", Vector3(0, 0.72, 0), Vector3(0.10, 0.08, 0.10), PlantVisual.materials.alienEye, false)
end

local function CreateLimitedZeroGravityEmbryo(visual, material)
    local stalkMat = PlantVisual.materials.stem
    CreateBlockFruit(visual, "GravityStem", Vector3(0, 0.28, 0), Vector3(0.055, 0.56, 0.055), stalkMat)
    for i = 1, 3 do
        local angle = math.rad(i * 120)
        local arc = PlantVisual.AddModel(visual, "GravityTendril" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.12, 0.54, math.sin(angle) * 0.12), Vector3(0.04, 0.34, 0.035), stalkMat, false)
        arc.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(-28, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "EmbryoMembrane", "Models/Sphere.mdl", Vector3(0, 0.92, 0), Vector3(0.22, 0.26, 0.22), material, false)
    PlantVisual.AddModel(visual, "EmbryoCore", "Models/Sphere.mdl", Vector3(0.02, 0.92, 0.02), Vector3(0.095, 0.095, 0.095), PlantVisual.materials.alienGlow, false)
    PlantVisual.AddModel(visual, "OrbitRingA", "Models/Torus.mdl", Vector3(0, 0.92, 0), Vector3(0.34, 0.018, 0.34), PlantVisual.materials.alienEye, false)
    local ringB = PlantVisual.AddModel(visual, "OrbitRingB", "Models/Torus.mdl", Vector3(0, 0.92, 0), Vector3(0.28, 0.014, 0.28), PlantVisual.materials.alienGlow, false)
    ringB.rotation = Quaternion(62, Vector3.RIGHT)
end

local function CreateLimitedMoonShadowLotus(visual, material)
    local stemMat = PlantVisual.CreateMaterial("moonLotusStem" .. tostring(math.random(100000, 999999)), Color(0.10, 0.12, 0.26, 1.0), 0.0, 0.58, Color(0.02, 0.02, 0.08, 1.0))
    CreateBlockFruit(visual, "MoonLotusStem", Vector3(0, 0.34, 0), Vector3(0.06, 0.68, 0.06), stemMat)
    for i = 1, 6 do
        local angle = math.rad(i * 60)
        local petal = PlantVisual.AddModel(visual, "MoonLotusPetal" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.18, 0.64, math.sin(angle) * 0.18), Vector3(0.16, 0.055, 0.26), material, false)
        petal.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(18, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "MoonLotusCore", "Models/Sphere.mdl", Vector3(0, 0.68, 0), Vector3(0.09, 0.09, 0.09), PlantVisual.materials.alienEye, false)
    local crescent = PlantVisual.AddModel(visual, "MoonCrescent", "Models/Torus.mdl", Vector3(0, 0.78, 0), Vector3(0.18, 0.014, 0.18), PlantVisual.materials.voidSpark, false)
    crescent.rotation = Quaternion(36, Vector3.RIGHT)
    CreateLeaves(visual, 4, 0.28, 0.18)
end

local function CreateLimitedGhostLanternGentian(visual, material)
    local stemMat = PlantVisual.CreateMaterial("ghostLanternStem" .. tostring(math.random(100000, 999999)), Color(0.05, 0.24, 0.24, 1.0), 0.0, 0.52, Color(0.01, 0.05, 0.05, 1.0))
    CreateBlockStem(visual, 0.62, 0.065)
    for i = 1, 3 do
        local angle = math.rad(i * 120 + 25)
        local branch = PlantVisual.AddModel(visual, "LanternBranch" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.11, 0.54 + i * 0.055, math.sin(angle) * 0.11), Vector3(0.04, 0.18, 0.035), stemMat, false)
        branch.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(42, Vector3.RIGHT)
        PlantVisual.AddModel(visual, "GhostLantern" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.28, 0.48 + i * 0.055, math.sin(angle) * 0.28), Vector3(0.10, 0.135, 0.10), material, false)
        PlantVisual.AddModel(visual, "LanternFlame" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.28, 0.48 + i * 0.055, math.sin(angle) * 0.28), Vector3(0.045, 0.06, 0.045), PlantVisual.materials.alienEye, false)
    end
    for i = 1, 4 do
        local angle = math.rad(i * 90 + 45)
        PlantVisual.AddModel(visual, "LanternWisp" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.23, 0.74 + (i % 2) * 0.06, math.sin(angle) * 0.23), Vector3(0.038, 0.038, 0.038), PlantVisual.materials.magicSpark, false)
    end
    CreateLeaves(visual, 3, 0.32, 0.13)
end

local function CreateLimitedEclipseCrown(visual, material)
    local darkMat = PlantVisual.materials.darkCore or material
    CreateBlockFruit(visual, "EclipseStem", Vector3(0, 0.32, 0), Vector3(0.085, 0.64, 0.085), darkMat)
    PlantVisual.AddModel(visual, "EclipseCrownRing", "Models/Torus.mdl", Vector3(0, 0.70, 0), Vector3(0.32, 0.024, 0.32), material, false)
    for i = 1, 8 do
        local angle = math.rad(i * 45)
        local ray = PlantVisual.AddModel(visual, "EclipseCrownRay" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.23, 0.84, math.sin(angle) * 0.23), Vector3(0.05, 0.28, 0.05), material, false)
        ray.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(-16, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "EclipseDarkMoon", "Models/Sphere.mdl", Vector3(0, 0.84, 0), Vector3(0.13, 0.13, 0.13), darkMat, false)
    PlantVisual.AddModel(visual, "EclipseOuterHalo", "Models/Torus.mdl", Vector3(0, 0.84, 0), Vector3(0.24, 0.018, 0.24), PlantVisual.materials.voidSpark, false)
    PlantVisual.AddModel(visual, "EclipseStar", "Models/Sphere.mdl", Vector3(0, 1.04, 0), Vector3(0.045, 0.045, 0.045), PlantVisual.materials.alienEye, false)
end

local function CreateLimitedCottonBerryTower(visual, material)
    local stemMat = PlantVisual.materials.stem
    CreateBlockFruit(visual, "CottonBerryStem", Vector3(0, 0.24, 0), Vector3(0.06, 0.48, 0.06), stemMat)
    for i = 1, 5 do
        local angle = math.rad(i * 72)
        local radius = 0.05 + (i % 3) * 0.045
        PlantVisual.AddModel(visual, "CottonBerryPuff" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, 0.46 + i * 0.055, math.sin(angle) * radius), Vector3(0.11, 0.085, 0.11), material, false)
    end
    PlantVisual.AddModel(visual, "CottonSugarTop", "Models/Sphere.mdl", Vector3(0, 0.78, 0), Vector3(0.13, 0.10, 0.13), PlantVisual.materials.cloud, false)
    PlantVisual.AddModel(visual, "BerryCandyRing", "Models/Torus.mdl", Vector3(0, 0.58, 0), Vector3(0.22, 0.014, 0.22), PlantVisual.materials.candyCrystal, false)
    CreateLeaves(visual, 3, 0.28, 0.16)
end

local function CreateLimitedCaramelStarfruit(visual, material)
    CreateBlockStem(visual, 0.50, 0.06)
    PlantVisual.AddModel(visual, "CaramelStarCore", "Models/Sphere.mdl", Vector3(0, 0.72, 0), Vector3(0.14, 0.14, 0.14), material, false)
    for i = 1, 5 do
        local angle = math.rad(i * 72)
        local ray = PlantVisual.AddModel(visual, "CaramelStarRay" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.18, 0.72, math.sin(angle) * 0.18), Vector3(0.075, 0.18, 0.055), material, false)
        ray.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(28, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "CaramelDrip", "Models/Sphere.mdl", Vector3(0.08, 0.56, 0.10), Vector3(0.045, 0.08, 0.045), PlantVisual.materials.honeyGlow, false)
    PlantVisual.AddModel(visual, "CaramelHalo", "Models/Torus.mdl", Vector3(0, 0.74, 0), Vector3(0.25, 0.014, 0.25), PlantVisual.materials.honeyGlow, false)
end

local function CreateLimitedSundaeHydrangea(visual, material)
    local stemMat = PlantVisual.materials.stem
    CreateBlockFruit(visual, "SundaeStem", Vector3(0, 0.30, 0), Vector3(0.08, 0.60, 0.08), stemMat)
    for i = 1, 9 do
        local angle = math.rad(i * 137.5)
        local radius = 0.05 + (i % 4) * 0.045
        local y = 0.62 + (i % 3) * 0.055
        local mat = (i % 3 == 0) and PlantVisual.materials.honeyGlow or material
        PlantVisual.AddModel(visual, "SundaeBloom" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), Vector3(0.08, 0.07, 0.08), mat, false)
    end
    PlantVisual.AddModel(visual, "SundaeCherry", "Models/Sphere.mdl", Vector3(0, 0.86, 0), Vector3(0.055, 0.055, 0.055), PlantVisual.materials.candyCrystal, false)
    PlantVisual.AddModel(visual, "SundaeGlassRing", "Models/Torus.mdl", Vector3(0, 0.60, 0), Vector3(0.26, 0.012, 0.26), PlantVisual.materials.cloud, false)
    CreateLeaves(visual, 4, 0.34, 0.18)
end

local function CreateLimitedQuantumBamboo(visual, material)
    for i = 1, 5 do
        local y = 0.10 + i * 0.13
        CreateBlockFruit(visual, "QuantumBambooSegment" .. i, Vector3(0, y, 0), Vector3(0.11, 0.12, 0.11), material)
        PlantVisual.AddModel(visual, "QuantumRing" .. i, "Models/Torus.mdl", Vector3(0, y + 0.04, 0), Vector3(0.16, 0.012, 0.16), PlantVisual.materials.alienGlow, false)
    end
    for i = 1, 3 do
        local angle = math.rad(i * 120)
        local leaf = PlantVisual.AddModel(visual, "QuantumLeaf" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.17, 0.64 + i * 0.035, math.sin(angle) * 0.17), Vector3(0.055, 0.035, 0.24), PlantVisual.materials.alienEye, false)
        leaf.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(32, Vector3.RIGHT)
    end
end

local function CreateLimitedPrismBrainMushroom(visual, material)
    local stemMat = PlantVisual.CreateMaterial("prismBrainStem" .. tostring(math.random(100000, 999999)), Color(0.18, 0.12, 0.38, 1.0), 0.0, 0.5, Color(0.02, 0.01, 0.08, 1.0))
    CreateBlockFruit(visual, "PrismBrainStem", Vector3(0, 0.28, 0), Vector3(0.13, 0.56, 0.13), stemMat)
    PlantVisual.AddModel(visual, "PrismBrainCore", "Models/Sphere.mdl", Vector3(0, 0.70, 0), Vector3(0.22, 0.14, 0.22), material, false)
    for i = 1, 6 do
        local angle = math.rad(i * 60)
        PlantVisual.AddModel(visual, "PrismLobe" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.16, 0.72 + (i % 2) * 0.035, math.sin(angle) * 0.16), Vector3(0.075, 0.06, 0.075), PlantVisual.materials.alienEye, false)
    end
    PlantVisual.AddModel(visual, "PrismSignalHalo", "Models/Torus.mdl", Vector3(0, 0.86, 0), Vector3(0.26, 0.014, 0.26), PlantVisual.materials.alienGlow, false)
end

local function CreateLimitedStarshipCoconut(visual, material)
    local trunkMat = PlantVisual.materials.wood
    CreateBlockFruit(visual, "StarshipTrunk", Vector3(0, 0.28, 0), Vector3(0.09, 0.56, 0.09), trunkMat)
    PlantVisual.AddModel(visual, "StarshipHull", "Models/Sphere.mdl", Vector3(0, 0.78, 0), Vector3(0.22, 0.14, 0.22), material, false)
    PlantVisual.AddModel(visual, "StarshipOrbit", "Models/Torus.mdl", Vector3(0, 0.78, 0), Vector3(0.34, 0.018, 0.34), PlantVisual.materials.alienGlow, false)
    for i = 1, 4 do
        local angle = math.rad(i * 90)
        PlantVisual.AddModel(visual, "StarshipEngine" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.24, 0.70, math.sin(angle) * 0.24), Vector3(0.045, 0.045, 0.045), PlantVisual.materials.alienEye, false)
    end
    CreateLeaves(visual, 5, 0.58, 0.20)
end

local function CreateLimitedNightDewHyacinth(visual, material)
    local stemMat = PlantVisual.CreateMaterial("nightDewStem" .. tostring(math.random(100000, 999999)), Color(0.05, 0.10, 0.25, 1.0), 0.0, 0.58, Color(0.01, 0.02, 0.07, 1.0))
    CreateBlockFruit(visual, "NightDewStem", Vector3(0, 0.34, 0), Vector3(0.06, 0.68, 0.06), stemMat)
    for i = 1, 7 do
        local angle = math.rad(i * 51)
        PlantVisual.AddModel(visual, "NightDewBell" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.14, 0.38 + i * 0.065, math.sin(angle) * 0.14), Vector3(0.055, 0.07, 0.055), material, false)
        PlantVisual.AddModel(visual, "NightDewDrop" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * 0.20, 0.38 + i * 0.065, math.sin(angle) * 0.20), Vector3(0.025, 0.035, 0.025), PlantVisual.materials.alienEye, false)
    end
    CreateLeaves(visual, 3, 0.26, 0.14)
end

local function CreateLimitedShadowVeilRose(visual, material)
    local stemMat = PlantVisual.materials.darkCore or material
    CreateBlockFruit(visual, "ShadowRoseStem", Vector3(0, 0.34, 0), Vector3(0.07, 0.68, 0.07), stemMat)
    for i = 1, 7 do
        local angle = math.rad(i * 360 / 7)
        local petal = PlantVisual.AddModel(visual, "ShadowRosePetal" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.14, 0.72, math.sin(angle) * 0.14), Vector3(0.09, 0.15, 0.05), material, false)
        petal.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(-20, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "ShadowVeil", "Models/Torus.mdl", Vector3(0, 0.74, 0), Vector3(0.25, 0.012, 0.25), PlantVisual.materials.voidSpark, false)
    PlantVisual.AddModel(visual, "ShadowRoseCore", "Models/Sphere.mdl", Vector3(0, 0.72, 0), Vector3(0.06, 0.06, 0.06), PlantVisual.materials.darkCore, false)
    CreateLeaves(visual, 4, 0.34, 0.16)
end

local function CreateLimitedStyxStarfruit(visual, material)
    local stemMat = PlantVisual.materials.darkCore or material
    CreateBlockFruit(visual, "StyxStem", Vector3(0, 0.32, 0), Vector3(0.08, 0.64, 0.08), stemMat)
    PlantVisual.AddModel(visual, "StyxStarCore", "Models/Sphere.mdl", Vector3(0, 0.78, 0), Vector3(0.13, 0.13, 0.13), material, false)
    for i = 1, 5 do
        local angle = math.rad(i * 72)
        local blade = PlantVisual.AddModel(visual, "StyxStarBlade" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.19, 0.78, math.sin(angle) * 0.19), Vector3(0.07, 0.22, 0.05), material, false)
        blade.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(30, Vector3.RIGHT)
    end
    PlantVisual.AddModel(visual, "StyxRiverRing", "Models/Torus.mdl", Vector3(0, 0.58, 0), Vector3(0.30, 0.014, 0.30), PlantVisual.materials.alienEye, false)
    PlantVisual.AddModel(visual, "StyxVoidPearl", "Models/Sphere.mdl", Vector3(0, 0.94, 0), Vector3(0.055, 0.055, 0.055), PlantVisual.materials.voidSpark, false)
end

local function CreateLimitedPlantVisual(visual, plant, material)
    if plant.visualTheme == "crystal_sweet" then
        CreateLimitedCrystalBellLily(visual, material)
        return true
    elseif plant.visualTheme == "honey_hive" then
        CreateLimitedHiveMandrake(visual, material)
        return true
    elseif plant.visualTheme == "dream_candy" then
        CreateLimitedDreamCandyNightshade(visual, material)
        return true
    elseif plant.visualTheme == "cotton_berry" then
        CreateLimitedCottonBerryTower(visual, material)
        return true
    elseif plant.visualTheme == "caramel_star" then
        CreateLimitedCaramelStarfruit(visual, material)
        return true
    elseif plant.visualTheme == "sundae_hydrangea" then
        CreateLimitedSundaeHydrangea(visual, material)
        return true
    elseif plant.visualTheme == "quantum_bamboo" then
        CreateLimitedQuantumBamboo(visual, material)
        return true
    elseif plant.visualTheme == "prism_brain" then
        CreateLimitedPrismBrainMushroom(visual, material)
        return true
    elseif plant.visualTheme == "starship_coconut" then
        CreateLimitedStarshipCoconut(visual, material)
        return true
    elseif plant.visualTheme == "night_dew_hyacinth" then
        CreateLimitedNightDewHyacinth(visual, material)
        return true
    elseif plant.visualTheme == "shadow_veil_rose" then
        CreateLimitedShadowVeilRose(visual, material)
        return true
    elseif plant.visualTheme == "styx_starfruit" then
        CreateLimitedStyxStarfruit(visual, material)
        return true
    elseif plant.visualTheme == "alien_pulse" then
        CreateLimitedPulseSporeTower(visual, material)
        return true
    elseif plant.visualTheme == "alien_eye" then
        CreateLimitedAlienEyeFern(visual, material)
        return true
    elseif plant.visualTheme == "zero_gravity" then
        CreateLimitedZeroGravityEmbryo(visual, material)
        return true
    elseif plant.visualTheme == "moon_shadow_lotus" then
        CreateLimitedMoonShadowLotus(visual, material)
        return true
    elseif plant.visualTheme == "ghost_lantern" then
        CreateLimitedGhostLanternGentian(visual, material)
        return true
    elseif plant.visualTheme == "eclipse_crown" then
        CreateLimitedEclipseCrown(visual, material)
        return true
    end
    return false
end

function PlantVisual.CreatePlantVisual(parent, plant, mutation, material)
    local visual = parent:CreateChild("Visual")
    local stageScale = 0.42
    visual.scale = Vector3(stageScale, stageScale, stageScale) * mutation.sizeScale

    if CreateLimitedPlantVisual(visual, plant, material) then
        AddThemedLimitedDetails(visual, plant)
        return visual
    end

    if plant.visual == "root" then
        -- 胡萝卜：锥形橙色身体 + 绿叶冠
        CreateBlockFruit(visual, "RootBlock", Vector3(0, 0.24, 0), Vector3(0.28, 0.46, 0.28), material)
        CreateBlockFruit(visual, "RootMid", Vector3(0, 0.02, 0), Vector3(0.22, 0.12, 0.22), material)
        CreateBlockFruit(visual, "RootTip", Vector3(0, -0.08, 0), Vector3(0.14, 0.12, 0.14), material)
        CreateLeaves(visual, 5, 0.55, 0.15)

    elseif plant.visual == "vine" then
        -- 番茄：竹竿支架 + 圆润红果实挂在藤上
        CreateBlockStem(visual, 0.72, 0.08)
        CreateLeaves(visual, 4, 0.55, 0.2)
        CreateBlockFruit(visual, "TomatoA", Vector3(0.2, 0.62, 0.06), Vector3(0.26, 0.26, 0.26), material)
        CreateBlockFruit(visual, "TomatoB", Vector3(-0.18, 0.46, -0.1), Vector3(0.22, 0.22, 0.22), material)
        -- 番茄顶部绿色蒂
        local tomatoCapMat = PlantVisual.CreateMaterial("tCap" .. tostring(math.random(100000, 999999)), Color(0.2, 0.5, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "CapA", Vector3(0.2, 0.77, 0.06), Vector3(0.12, 0.04, 0.12), tomatoCapMat)
        CreateBlockFruit(visual, "CapB", Vector3(-0.18, 0.59, -0.1), Vector3(0.1, 0.04, 0.1), tomatoCapMat)

    elseif plant.visual == "berry" then
        -- 草莓：低矮匍匐 + 三角形红果 + 绿叶铺地
        CreateBlockStem(visual, 0.3, 0.06)
        CreateLeaves(visual, 5, 0.28, 0.26)
        -- 草莓果实：上宽下窄
        CreateBlockFruit(visual, "BerryTop", Vector3(0.18, 0.38, 0.05), Vector3(0.18, 0.12, 0.18), material)
        CreateBlockFruit(visual, "BerryBot", Vector3(0.18, 0.28, 0.05), Vector3(0.12, 0.1, 0.12), material)
        CreateBlockFruit(visual, "BerryB", Vector3(-0.14, 0.34, -0.08), Vector3(0.16, 0.1, 0.16), material)
        CreateBlockFruit(visual, "BerryBBot", Vector3(-0.14, 0.26, -0.08), Vector3(0.1, 0.08, 0.1), material)
        -- 草莓顶部小绿叶
        local berryCapMat = PlantVisual.CreateMaterial("bCap" .. tostring(math.random(100000, 999999)), Color(0.2, 0.55, 0.12, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "BerryCapA", Vector3(0.18, 0.45, 0.05), Vector3(0.1, 0.03, 0.1), berryCapMat)

    elseif plant.visual == "cluster" then
        -- 花椰菜：粗短茎 + 半球形白绿花球（多层堆叠）
        local stemMat = PlantVisual.CreateMaterial("cfStem" .. tostring(math.random(100000, 999999)), Color(0.6, 0.72, 0.4, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "ThickStem", Vector3(0, 0.18, 0), Vector3(0.18, 0.36, 0.18), stemMat)
        -- 外围大叶包裹
        CreateLeaves(visual, 6, 0.38, 0.3)
        -- 花球：密集堆叠的方块
        CreateBlockFruit(visual, "HeadCenter", Vector3(0, 0.52, 0), Vector3(0.32, 0.22, 0.32), material)
        CreateBlockFruit(visual, "HeadTop", Vector3(0, 0.66, 0), Vector3(0.22, 0.14, 0.22), material)
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90 + 45)
            CreateBlockFruit(visual, "HeadSide" .. i, Vector3(math.cos(angle) * 0.18, 0.52, math.sin(angle) * 0.18), Vector3(0.14, 0.18, 0.14), material)
        end

    elseif plant.visual == "gourd" then
        -- 南瓜：扁圆橙色体 + 竖向瓣状条纹 + 顶部绿蒂
        CreateBlockFruit(visual, "PumpkinCore", Vector3(0, 0.3, 0), Vector3(0.5, 0.38, 0.5), material)
        -- 两侧凸起的瓣
        local darkMat = PlantVisual.CreateMaterial("pDark" .. tostring(math.random(100000, 999999)), Color(0.85, 0.35, 0.02, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "RibL", Vector3(-0.22, 0.3, 0), Vector3(0.1, 0.32, 0.36), darkMat)
        CreateBlockFruit(visual, "RibR", Vector3(0.22, 0.3, 0), Vector3(0.1, 0.32, 0.36), darkMat)
        CreateBlockFruit(visual, "RibF", Vector3(0, 0.3, -0.22), Vector3(0.36, 0.32, 0.1), darkMat)
        CreateBlockFruit(visual, "RibB", Vector3(0, 0.3, 0.22), Vector3(0.36, 0.32, 0.1), darkMat)
        -- 顶部绿蒂+卷叶
        local stemGreen = PlantVisual.CreateMaterial("pStem" .. tostring(math.random(100000, 999999)), Color(0.25, 0.5, 0.1, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "PumpStem", Vector3(0, 0.54, 0), Vector3(0.08, 0.14, 0.08), stemGreen)
        CreateBlockFruit(visual, "PumpLeaf", Vector3(0.1, 0.52, 0), Vector3(0.14, 0.04, 0.08), stemGreen)

    elseif plant.visual == "melon" then
        -- 西瓜：椭圆绿体 + 深绿色条纹
        CreateBlockFruit(visual, "MelonCore", Vector3(0, 0.32, 0), Vector3(0.52, 0.44, 0.44), material)
        -- 深绿条纹
        local stripeMat = PlantVisual.CreateMaterial("mStripe" .. tostring(math.random(100000, 999999)), Color(0.02, 0.35, 0.08, 1.0), 0.0, 0.45)
        CreateBlockFruit(visual, "Stripe1", Vector3(0, 0.32, -0.23), Vector3(0.44, 0.38, 0.04), stripeMat)
        CreateBlockFruit(visual, "Stripe2", Vector3(0, 0.32, 0.23), Vector3(0.44, 0.38, 0.04), stripeMat)
        CreateBlockFruit(visual, "Stripe3", Vector3(-0.27, 0.32, 0), Vector3(0.04, 0.38, 0.36), stripeMat)
        CreateBlockFruit(visual, "Stripe4", Vector3(0.27, 0.32, 0), Vector3(0.04, 0.38, 0.36), stripeMat)
        -- 顶部小卷蔓
        local vineMat = PlantVisual.CreateMaterial("mVine" .. tostring(math.random(100000, 999999)), Color(0.3, 0.6, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "MelonVine", Vector3(0.06, 0.56, 0), Vector3(0.12, 0.04, 0.04), vineMat)

    elseif plant.visual == "pineapple" then
        -- 凤梨：菱形纹路身体（多层交错方块）+ 皇冠状叶
        -- 身体：三层交错堆叠，暗色格子纹
        local darkGold = PlantVisual.CreateMaterial("paDark" .. tostring(math.random(100000, 999999)), Color(0.7, 0.5, 0.05, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "PineBot", Vector3(0, 0.16, 0), Vector3(0.3, 0.22, 0.3), material)
        CreateBlockFruit(visual, "PineMid", Vector3(0, 0.36, 0), Vector3(0.34, 0.22, 0.34), material)
        CreateBlockFruit(visual, "PineTop", Vector3(0, 0.56, 0), Vector3(0.28, 0.2, 0.28), material)
        -- 菱形格纹（交错小块）
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90)
            CreateBlockFruit(visual, "Grid" .. i, Vector3(math.cos(angle) * 0.14, 0.36, math.sin(angle) * 0.14), Vector3(0.08, 0.08, 0.08), darkGold)
        end
        -- 皇冠叶：向上散开的硬叶
        local crownMat = PlantVisual.CreateMaterial("paCrown" .. tostring(math.random(100000, 999999)), Color(0.2, 0.6, 0.1, 1.0), 0.0, 0.4)
        for i = 1, 5 do
            local angle = (i - 1) * 72
            local rad = math.rad(angle)
            local leaf = PlantVisual.AddModel(visual, "CrownLeaf" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.08, 0.74, math.sin(rad) * 0.08), Vector3(0.06, 0.22, 0.14), crownMat)
            leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(-20, Vector3.RIGHT)
        end

    elseif plant.visual == "flower" then
        -- 郁金香：单茎 + 杯状花苞（花瓣内收）
        CreateBlockStem(visual, 0.7, 0.07)
        CreateLeaves(visual, 2, 0.35, 0.12)
        -- 杯状花苞：中心柱 + 内收花瓣
        CreateBlockFruit(visual, "BudCore", Vector3(0, 0.78, 0), Vector3(0.12, 0.24, 0.12), material)
        for i = 1, 4 do
            local angle = (i - 1) * 90
            local rad = math.rad(angle)
            local petal = PlantVisual.AddModel(visual, "TulipPetal" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.1, 0.78, math.sin(rad) * 0.1), Vector3(0.14, 0.26, 0.06), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(10, Vector3.RIGHT)
        end

    elseif plant.visual == "cosmos" then
        -- 波斯菊：茎 + 紧凑花头（花瓣紧贴中心）
        CreateBlockStem(visual, 0.65, 0.07)
        CreateLeaves(visual, 2, 0.38, 0.14)
        -- 黄色花盘中心
        local centerMat = PlantVisual.CreateMaterial("cosCenter" .. tostring(math.random(100000, 999999)), Color(0.95, 0.85, 0.15, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "CosCenter", Vector3(0, 0.74, 0), Vector3(0.14, 0.12, 0.14), centerMat)
        -- 8 片花瓣紧贴中心排列
        for i = 1, 8 do
            local angle = (i - 1) * 45
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "CosPetal" .. i, Vector3(math.cos(rad) * 0.12, 0.74, math.sin(rad) * 0.12), Vector3(0.1, 0.04, 0.1), material)
        end

    elseif plant.visual == "lily" then
        -- 百合：优雅长茎 + 喇叭形大花（花瓣长而优雅向外卷曲 + 突出花蕊）
        CreateBlockStem(visual, 0.75, 0.07)
        CreateLeaves(visual, 2, 0.35, 0.14)
        -- 花蕊（中心几根细长黄色柱体）
        local stamenMat = PlantVisual.CreateMaterial("lilyS" .. tostring(math.random(100000, 999999)), Color(0.85, 0.7, 0.15, 1.0), 0.0, 0.4)
        for i = 1, 3 do
            local angle = (i - 1) * 120
            local rad = math.rad(angle)
            PlantVisual.AddModel(visual, "Stamen" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.04, 0.86, math.sin(rad) * 0.04), Vector3(0.025, 0.16, 0.025), stamenMat)
        end
        -- 6 片长花瓣（交替两层，外层更展开）
        for i = 1, 3 do
            local angle = (i - 1) * 120
            local rad = math.rad(angle)
            local petal = PlantVisual.AddModel(visual, "LilyInner" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.14, 0.78, math.sin(rad) * 0.14), Vector3(0.1, 0.05, 0.26), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
        end
        for i = 1, 3 do
            local angle = (i - 1) * 120 + 60
            local rad = math.rad(angle)
            local petal = PlantVisual.AddModel(visual, "LilyOuter" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.2, 0.74, math.sin(rad) * 0.2), Vector3(0.1, 0.05, 0.28), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(50, Vector3.RIGHT)
        end

    elseif plant.visual == "pansy" then
        -- 三色堇：矮茎 + 扁平正面朝前的大脸花
        CreateBlockStem(visual, 0.4, 0.06)
        CreateLeaves(visual, 4, 0.3, 0.18)
        -- 大平面花脸（上2下3花瓣）
        local darkCenter = PlantVisual.CreateMaterial("pansyC" .. tostring(math.random(100000, 999999)), Color(0.15, 0.05, 0.25, 1.0), 0.0, 0.5)
        PlantVisual.AddModel(visual, "PansyCenter", "Models/Box.mdl", Vector3(0, 0.52, 0), Vector3(0.1, 0.1, 0.06), darkCenter)
        -- 上部两片
        CreateBlockFruit(visual, "PansyTopL", Vector3(-0.1, 0.6, 0), Vector3(0.14, 0.12, 0.06), material)
        CreateBlockFruit(visual, "PansyTopR", Vector3(0.1, 0.6, 0), Vector3(0.14, 0.12, 0.06), material)
        -- 下部三片（稍大）
        CreateBlockFruit(visual, "PansyBotL", Vector3(-0.12, 0.46, 0), Vector3(0.12, 0.1, 0.06), material)
        CreateBlockFruit(visual, "PansyBotR", Vector3(0.12, 0.46, 0), Vector3(0.12, 0.1, 0.06), material)
        CreateBlockFruit(visual, "PansyBotM", Vector3(0, 0.42, 0), Vector3(0.14, 0.12, 0.06), material)

    elseif plant.visual == "mushroom" then
        -- 蘑菇：白色粗茎 + 红色宽帽 + 白色斑点块
        local stemMat = PlantVisual.CreateMaterial("mushStem" .. tostring(math.random(100000, 999999)), Color(0.92, 0.88, 0.8, 1.0), 0.0, 0.55)
        CreateBlockFruit(visual, "MushStem", Vector3(0, 0.22, 0), Vector3(0.18, 0.44, 0.18), stemMat)
        CreateBlockFruit(visual, "MushCap", Vector3(0, 0.52, 0), Vector3(0.52, 0.16, 0.52), material)
        -- 白色斑点
        local spotMat = PlantVisual.CreateMaterial("mushSpot" .. tostring(math.random(100000, 999999)), Color(0.98, 0.98, 0.95, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "Spot1", Vector3(0.12, 0.62, 0.08), Vector3(0.08, 0.04, 0.08), spotMat)
        CreateBlockFruit(visual, "Spot2", Vector3(-0.1, 0.62, -0.1), Vector3(0.07, 0.04, 0.07), spotMat)
        CreateBlockFruit(visual, "Spot3", Vector3(0.04, 0.62, -0.14), Vector3(0.06, 0.04, 0.06), spotMat)

    elseif plant.visual == "cactus" then
        -- 仙人掌：粗柱体 + 两臂 + 小花
        CreateBlockFruit(visual, "CactusBody", Vector3(0, 0.5, 0), Vector3(0.24, 0.9, 0.24), material)
        CreateBlockFruit(visual, "CactusArmL", Vector3(-0.26, 0.55, 0), Vector3(0.14, 0.38, 0.14), material)
        CreateBlockFruit(visual, "ArmLUp", Vector3(-0.26, 0.78, 0), Vector3(0.14, 0.14, 0.14), material)
        CreateBlockFruit(visual, "CactusArmR", Vector3(0.26, 0.72, 0), Vector3(0.14, 0.3, 0.14), material)
        CreateBlockFruit(visual, "ArmRUp", Vector3(0.26, 0.9, 0), Vector3(0.14, 0.14, 0.14), material)
        -- 顶部小花
        local flowerMat = PlantVisual.CreateMaterial("cacFlower" .. tostring(math.random(100000, 999999)), Color(1.0, 0.4, 0.6, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "CacFlower", Vector3(0, 0.98, 0), Vector3(0.1, 0.08, 0.1), flowerMat)

    elseif plant.visual == "sunflower" then
        -- 向日葵：粗壮高茎 + 大叶 + 实心花头（中心棕块 + 周围紧贴花瓣块）
        CreateBlockStem(visual, 0.9, 0.1)
        CreateLeaves(visual, 3, 0.45, 0.22)
        -- 棕色中心种子区
        local diskMat = PlantVisual.CreateMaterial("sfDisk" .. tostring(math.random(100000, 999999)), Color(0.35, 0.2, 0.05, 1.0), 0.0, 0.6)
        CreateBlockFruit(visual, "SunDisk", Vector3(0, 1.0, 0), Vector3(0.22, 0.22, 0.12), diskMat)
        -- 内圈花瓣（4 片，紧贴中心）
        for i = 1, 4 do
            local angle = (i - 1) * 90
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "SunIn" .. i, Vector3(math.cos(rad) * 0.16, 1.0, math.sin(rad) * 0.16), Vector3(0.16, 0.18, 0.1), material)
        end
        -- 外圈花瓣（8 片，紧贴内圈）
        for i = 1, 8 do
            local angle = (i - 1) * 45 + 22
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "SunOut" .. i, Vector3(math.cos(rad) * 0.28, 1.0, math.sin(rad) * 0.28), Vector3(0.14, 0.14, 0.08), material)
        end

    elseif plant.visual == "pepper" then
        -- 辣椒：茎 + 向下悬挂的细长尖椒
        CreateBlockStem(visual, 0.58, 0.07)
        CreateLeaves(visual, 4, 0.48, 0.18)
        -- 辣椒果实：上粗下细，向下挂
        CreateBlockFruit(visual, "PepperTop", Vector3(0.14, 0.48, 0.04), Vector3(0.12, 0.14, 0.12), material)
        CreateBlockFruit(visual, "PepperMid", Vector3(0.14, 0.36, 0.04), Vector3(0.1, 0.14, 0.1), material)
        CreateBlockFruit(visual, "PepperTip", Vector3(0.14, 0.26, 0.04), Vector3(0.06, 0.1, 0.06), material)
        -- 第二根辣椒
        CreateBlockFruit(visual, "Pepper2Top", Vector3(-0.12, 0.44, -0.06), Vector3(0.1, 0.12, 0.1), material)
        CreateBlockFruit(visual, "Pepper2Tip", Vector3(-0.12, 0.34, -0.06), Vector3(0.06, 0.1, 0.06), material)

    elseif plant.visual == "rose" then
        -- 玫瑰：茎 + 紧密层叠花苞（三层由内向外渐大，模拟玫瑰卷瓣）
        CreateBlockStem(visual, 0.68, 0.08)
        CreateLeaves(visual, 3, 0.42, 0.18)
        -- 花苞核心
        CreateBlockFruit(visual, "RoseCore", Vector3(0, 0.78, 0), Vector3(0.12, 0.16, 0.12), material)
        -- 内层花瓣（4片，紧贴核心，略高）
        for i = 1, 4 do
            local angle = (i - 1) * 90 + 20
            local rad = math.rad(angle)
            local p = PlantVisual.AddModel(visual, "RoseIn" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.1, 0.8, math.sin(rad) * 0.1), Vector3(0.1, 0.14, 0.05), material)
            p.rotation = Quaternion(angle, Vector3.UP) * Quaternion(15, Vector3.RIGHT)
        end
        -- 外层花瓣（5片，稍大稍低，微微外翻）
        for i = 1, 5 do
            local angle = (i - 1) * 72 + 10
            local rad = math.rad(angle)
            local p = PlantVisual.AddModel(visual, "RoseOut" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.18, 0.75, math.sin(rad) * 0.18), Vector3(0.12, 0.12, 0.05), material)
            p.rotation = Quaternion(angle, Vector3.UP) * Quaternion(-10, Vector3.RIGHT)
        end

    elseif plant.visual == "dandelion" then
        -- 蒲公英：细茎 + 饱满球形绒球（核心+中层+外层，整体感强）
        CreateBlockStem(visual, 0.6, 0.05)
        local seedMat = PlantVisual.CreateMaterial("dandSeed" .. tostring(math.random(100000, 999999)), Color(0.98, 0.98, 0.95, 1.0), 0.0, 0.3)
        local ballY = 0.72
        -- 核心大块（填充球心）
        CreateBlockFruit(visual, "DandCore", Vector3(0, ballY, 0), Vector3(0.18, 0.18, 0.18), seedMat)
        -- 中层（6 方向填充）
        local midDirs = {
            Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0),
            Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)
        }
        for i, d in ipairs(midDirs) do
            CreateBlockFruit(visual, "DandMid" .. i, Vector3(d.x * 0.12, ballY + d.y * 0.12, d.z * 0.12), Vector3(0.12, 0.12, 0.12), seedMat)
        end
        -- 外层（8 角方向，略小）
        for i = 1, 8 do
            local phi = math.acos(1 - 2 * (i - 0.5) / 8)
            local theta = math.pi * (1 + math.sqrt(5)) * i
            local r = 0.2
            local x = r * math.sin(phi) * math.cos(theta)
            local y = r * math.cos(phi)
            local z = r * math.sin(phi) * math.sin(theta)
            CreateBlockFruit(visual, "DandOut" .. i, Vector3(x, ballY + y, z), Vector3(0.08, 0.08, 0.08), seedMat)
        end
        -- 茎顶部小黄点
        CreateBlockFruit(visual, "DandCenter", Vector3(0, ballY - 0.12, 0), Vector3(0.06, 0.06, 0.06), material)

    elseif plant.visual == "hyacinth" then
        -- 风信子：粗茎 + 沿茎垂直排列的多层小花
        CreateBlockStem(visual, 0.8, 0.1)
        CreateLeaves(visual, 3, 0.25, 0.16)
        -- 沿茎堆叠 4 层小花
        for layer = 1, 4 do
            local ly = 0.45 + (layer - 1) * 0.14
            for i = 1, 4 do
                local angle = math.rad((i - 1) * 90 + layer * 45)
                CreateBlockFruit(visual, "HyaFlower" .. layer .. i, Vector3(math.cos(angle) * 0.12, ly, math.sin(angle) * 0.12), Vector3(0.1, 0.1, 0.1), material)
            end
        end

    elseif plant.visual == "hydrangea" then
        -- 绣球花：粗茎 + 大叶 + 饱满球形花簇（密集排列，外层大内层小）
        CreateBlockStem(visual, 0.55, 0.1)
        CreateLeaves(visual, 4, 0.42, 0.3)
        -- 球形花簇核心（大块填充中心）
        local ballY = 0.75
        CreateBlockFruit(visual, "HydCore", Vector3(0, ballY, 0), Vector3(0.22, 0.22, 0.22), material)
        -- 中层（6个方向）
        local dirs = {
            Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0),
            Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)
        }
        for i, d in ipairs(dirs) do
            CreateBlockFruit(visual, "HydMid" .. i, Vector3(d.x * 0.16, ballY + d.y * 0.16, d.z * 0.16), Vector3(0.14, 0.14, 0.14), material)
        end
        -- 外层（12个方块，均匀分布球面）
        for i = 1, 12 do
            local phi = math.acos(1 - 2 * (i - 0.5) / 12)
            local theta = math.pi * (1 + math.sqrt(5)) * i
            local r = 0.26
            local x = r * math.sin(phi) * math.cos(theta)
            local y = r * math.cos(phi)
            local z = r * math.sin(phi) * math.sin(theta)
            CreateBlockFruit(visual, "HydOut" .. i, Vector3(x, ballY + y, z), Vector3(0.1, 0.1, 0.1), material)
        end

    elseif plant.visual == "starfruit" then
        -- 杨桃：茎 + 五角星截面的果实（5 个方块辐射排列）
        CreateBlockStem(visual, 0.55, 0.07)
        CreateLeaves(visual, 4, 0.44, 0.18)
        -- 五角星果实
        local fruitY = 0.6
        CreateBlockFruit(visual, "StarCore", Vector3(0, fruitY, 0), Vector3(0.14, 0.28, 0.14), material)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local wing = PlantVisual.AddModel(visual, "StarWing" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.12, fruitY, math.sin(angle) * 0.12), Vector3(0.12, 0.24, 0.05), material)
            wing.rotation = Quaternion((i - 1) * 72, Vector3.UP)
        end

    elseif plant.visual == "corn" then
        -- 玉米：粗茎居中 + 大玉米棒贴茎（棒身黄色 + 底部绿色苞叶包裹）
        CreateBlockStem(visual, 0.8, 0.1)
        CreateLeaves(visual, 2, 0.35, 0.18)
        -- 玉米棒（大而醒目，贴着茎）
        CreateBlockFruit(visual, "CornCob", Vector3(0, 0.68, 0.02), Vector3(0.16, 0.38, 0.16), material)
        -- 苞叶包裹下半部分
        local huskMat = PlantVisual.CreateMaterial("husk" .. tostring(math.random(100000, 999999)), Color(0.3, 0.6, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "HuskL", Vector3(-0.12, 0.5, 0.08), Vector3(0.035, 0.24, 0.12), huskMat)
        CreateBlockFruit(visual, "HuskR", Vector3(0.12, 0.5, 0.08), Vector3(0.035, 0.24, 0.12), huskMat)
        CreateBlockFruit(visual, "HuskB", Vector3(0, 0.49, 0.2), Vector3(0.12, 0.22, 0.035), huskMat)

    elseif plant.visual == "grape" then
        -- 葡萄：藤蔓茎 + 叶子 + 一串紫色圆果（倒三角形排列）
        CreateBlockStem(visual, 0.55, 0.07)
        CreateLeaves(visual, 2, 0.5, 0.18)
        -- 葡萄串（倒三角形：上宽下窄）
        -- 第一排（3 颗）
        CreateBlockFruit(visual, "Grape1", Vector3(-0.1, 0.46, 0), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape2", Vector3(0.02, 0.46, 0.08), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape3", Vector3(0.1, 0.46, -0.04), Vector3(0.1, 0.1, 0.1), material)
        -- 第二排（2 颗）
        CreateBlockFruit(visual, "Grape4", Vector3(-0.04, 0.36, 0.04), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape5", Vector3(0.08, 0.36, -0.02), Vector3(0.1, 0.1, 0.1), material)
        -- 第三排（1 颗，底部）
        CreateBlockFruit(visual, "Grape6", Vector3(0.02, 0.27, 0.02), Vector3(0.09, 0.09, 0.09), material)

    elseif plant.visual == "mango" then
        -- 芒果：短枝 + 大叶 + 肾形大芒果（上宽下窄，侧面有弧度）
        CreateBlockStem(visual, 0.45, 0.08)
        CreateLeaves(visual, 3, 0.42, 0.18)
        -- 芒果主体（3 段组成肾形：上圆中宽下尖）
        CreateBlockFruit(visual, "MangoWide", Vector3(0.02, 0.46, 0), Vector3(0.26, 0.16, 0.2), material)
        CreateBlockFruit(visual, "MangoMid", Vector3(0, 0.36, 0), Vector3(0.22, 0.12, 0.18), material)
        CreateBlockFruit(visual, "MangoTip", Vector3(-0.02, 0.28, 0), Vector3(0.14, 0.1, 0.12), material)
        -- 顶部微红晕（芒果特征：顶部偏红）
        local blushMat = PlantVisual.CreateMaterial("mBlush" .. tostring(math.random(100000, 999999)), Color(0.9, 0.35, 0.1, 1.0), 0.0, 0.42)
        CreateBlockFruit(visual, "MangoBlush", Vector3(0.06, 0.52, 0), Vector3(0.12, 0.08, 0.12), blushMat)

    elseif plant.visual == "banana" then
        -- 香蕉：粗茎 + 大叶 + 一挂弯曲香蕉（向上弯曲的月牙形，从中心柄放射）
        CreateBlockStem(visual, 0.55, 0.12)
        CreateLeaves(visual, 2, 0.48, 0.26)
        -- 中心果柄
        local stalkMat = PlantVisual.CreateMaterial("bStalk" .. tostring(math.random(100000, 999999)), Color(0.5, 0.38, 0.12, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "BananaStalk", Vector3(0, 0.6, 0), Vector3(0.08, 0.1, 0.08), stalkMat)
        -- 5 根香蕉从果柄向外弯曲展开（月牙形：用两段方块模拟弧度）
        for i = 1, 5 do
            local angle = (i - 1) * 72
            local rad = math.rad(angle)
            -- 内段（靠近柄，竖直）
            local bx = math.cos(rad) * 0.08
            local bz = math.sin(rad) * 0.08
            CreateBlockFruit(visual, "BanIn" .. i, Vector3(bx, 0.54, bz), Vector3(0.07, 0.16, 0.07), material)
            -- 外段（远离柄，向外倾斜）
            local ox = math.cos(rad) * 0.14
            local oz = math.sin(rad) * 0.14
            CreateBlockFruit(visual, "BanOut" .. i, Vector3(ox, 0.46, oz), Vector3(0.06, 0.14, 0.06), material)
        end

    elseif plant.visual == "bamboo" then
        -- 竹子：分节绿色方柱（多段叠加）+ 顶部小叶
        -- 竹竿（3 段分节）
        CreateBlockFruit(visual, "Seg1", Vector3(0, 0.2, 0), Vector3(0.12, 0.36, 0.12), material)
        CreateBlockFruit(visual, "Seg2", Vector3(0, 0.55, 0), Vector3(0.11, 0.32, 0.11), material)
        CreateBlockFruit(visual, "Seg3", Vector3(0, 0.86, 0), Vector3(0.1, 0.28, 0.1), material)
        -- 节环（深色）
        local nodeMat = PlantVisual.CreateMaterial("bNode" .. tostring(math.random(100000, 999999)), Color(0.2, 0.5, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "Node1", Vector3(0, 0.38, 0), Vector3(0.14, 0.04, 0.14), nodeMat)
        CreateBlockFruit(visual, "Node2", Vector3(0, 0.7, 0), Vector3(0.13, 0.04, 0.13), nodeMat)
        -- 顶部竹叶
        CreateLeaves(visual, 3, 0.98, 0.12)

    elseif plant.visual == "coconut" then
        -- 椰子：弯曲棕色树干 + 棕色椰果 + 绿色棕榈叶
        local trunkMat = PlantVisual.CreateMaterial("cTrunk" .. tostring(math.random(100000, 999999)), Color(0.5, 0.35, 0.18, 1.0), 0.0, 0.6)
        CreateBlockFruit(visual, "Trunk1", Vector3(0, 0.25, 0), Vector3(0.14, 0.45, 0.14), trunkMat)
        CreateBlockFruit(visual, "Trunk2", Vector3(0.04, 0.62, 0), Vector3(0.12, 0.3, 0.12), trunkMat)
        -- 椰果（2-3 颗棕色圆果）
        CreateBlockFruit(visual, "Coco1", Vector3(0.06, 0.78, 0.06), Vector3(0.12, 0.12, 0.12), material)
        CreateBlockFruit(visual, "Coco2", Vector3(-0.04, 0.78, -0.04), Vector3(0.1, 0.1, 0.1), material)
        -- 棕榈叶（向外展开）
        for i = 1, 4 do
            local angle = (i - 1) * 90 + 45
            local rad = math.rad(angle)
            local leaf = PlantVisual.AddModel(visual, "PalmLeaf" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.14, 0.86, math.sin(rad) * 0.14), Vector3(0.08, 0.04, 0.24), PlantVisual.materials.leaf)
            leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
        end

    elseif plant.visual == "azalea" then
        -- 杜鹃：短茎 + 大团花簇（几乎全是花，少量绿叶点缀）
        CreateBlockStem(visual, 0.28, 0.09)
        -- 花团主体（多个花块紧密排列，覆盖整个顶部）
        CreateBlockFruit(visual, "FlowerCore", Vector3(0, 0.5, 0), Vector3(0.26, 0.22, 0.26), material)
        CreateBlockFruit(visual, "FlowerL", Vector3(-0.16, 0.48, 0.06), Vector3(0.16, 0.18, 0.16), material)
        CreateBlockFruit(visual, "FlowerR", Vector3(0.14, 0.5, -0.04), Vector3(0.16, 0.18, 0.16), material)
        CreateBlockFruit(visual, "FlowerF", Vector3(0.02, 0.52, 0.16), Vector3(0.14, 0.16, 0.14), material)
        CreateBlockFruit(visual, "FlowerTop", Vector3(0, 0.66, 0), Vector3(0.18, 0.14, 0.18), material)
        -- 少量绿叶从底部露出
        local bushMat = PlantVisual.CreateMaterial("bush" .. tostring(math.random(100000, 999999)), Color(0.2, 0.55, 0.18, 1.0), 0.0, 0.45)
        CreateBlockFruit(visual, "LeafL", Vector3(-0.2, 0.38, 0), Vector3(0.1, 0.08, 0.14), bushMat)
        CreateBlockFruit(visual, "LeafR", Vector3(0.18, 0.36, 0.08), Vector3(0.1, 0.08, 0.12), bushMat)

    elseif plant.visual == "magnolia" then
        -- 玉兰：粗枝 + 大杯状白花（花瓣厚实微张）
        CreateBlockStem(visual, 0.65, 0.1)
        CreateLeaves(visual, 2, 0.38, 0.16)
        -- 花苞核心
        local centerMat = PlantVisual.CreateMaterial("magC" .. tostring(math.random(100000, 999999)), Color(0.9, 0.85, 0.3, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "MagCore", Vector3(0, 0.76, 0), Vector3(0.1, 0.14, 0.1), centerMat)
        -- 6 片厚实白色花瓣（杯状微张）
        for i = 1, 6 do
            local angle = (i - 1) * 60
            local rad = math.rad(angle)
            local petal = PlantVisual.AddModel(visual, "MagPetal" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.12, 0.76, math.sin(rad) * 0.12), Vector3(0.12, 0.18, 0.06), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(12, Vector3.RIGHT)
        end

    elseif plant.visual == "peony" then
        -- 牡丹：粗茎 + 超大密集层叠花球（比玫瑰更大更蓬松）
        CreateBlockStem(visual, 0.6, 0.1)
        CreateLeaves(visual, 3, 0.4, 0.22)
        -- 花球核心
        CreateBlockFruit(visual, "PeonyCore", Vector3(0, 0.74, 0), Vector3(0.18, 0.18, 0.18), material)
        -- 内层花瓣（6 片紧贴）
        for i = 1, 6 do
            local angle = (i - 1) * 60
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "PeonyIn" .. i, Vector3(math.cos(rad) * 0.12, 0.75, math.sin(rad) * 0.12), Vector3(0.12, 0.14, 0.06), material)
        end
        -- 外层花瓣（8 片稍大）
        for i = 1, 8 do
            local angle = (i - 1) * 45 + 22
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "PeonyOut" .. i, Vector3(math.cos(rad) * 0.22, 0.72, math.sin(rad) * 0.22), Vector3(0.12, 0.12, 0.06), material)
        end

    else
        -- 通用花卉 fallback
        CreateBlockStem(visual, 0.74, 0.08)
        CreateLeaves(visual, 4, 0.5, 0.18)
        CreateBlockFlowerHead(visual, material, 0.84, 6)
    end

    if PlantVisual.HasSpecial(mutation, "ceramic") then
        AddFiredCeramicPattern(visual)
    end
    if PlantVisual.HasSpecial(mutation, "frozen") then
        AddFrozenShell(visual)
    end
    if PlantVisual.HasSpecial(mutation, "chocolate") then
        AddChocolateCoating(visual)
    end
    AddThemedLimitedDetails(visual, plant)

    return visual
end

local function RegisterEffect(plantData, node, spinSpeed, bobSpeed, bobAmp, pulseSpeed, pulseAmp, updateInterval, particles)
    table.insert(plantData.effectNodes, {
        node = node,
        particles = particles,
        spinSpeed = spinSpeed or 28.0,
        bobSpeed = bobSpeed or 1.5,
        bobAmp = bobAmp or 0.03,
        pulseSpeed = pulseSpeed or 0.0,
        pulseAmp = pulseAmp or 0.0,
        baseScale = node.scale,
        basePosition = node.position,
        updateInterval = updateInterval or EFFECT_DETAIL_INTERVAL,
        updateTimer = math.random() * 0.05,
    })
    return node
end

local function AddGlowLightEffect(plantData, effectScale, baseY, height)
    local root = plantData.root:CreateChild("GlowLightEffect")
    root.position = Vector3(0, baseY + height * 0.55, 0)

    local light = root:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(0.48, 0.14, 0.68, 1.0)
    light.brightness = 2.25
    light.range = 1.75 * effectScale
    light.castShadows = false

    PlantVisual.AddModel(root, "GlowCore", "Models/Sphere.mdl", Vector3(0, 0.02 * effectScale, 0), Vector3(0.052, 0.052, 0.052) * effectScale, PlantVisual.materials.magicSpark, false)

    RegisterEffect(plantData, root, 0.0, 0.45, 0.003 * effectScale, 0.55, 0.018, EFFECT_AMBIENT_INTERVAL)
end

local function AddCloudPuffEffect(plantData, effectScale, baseY, height)
    local root = plantData.root:CreateChild("CloudPuffEffect")
    root.position = Vector3(0, 0, 0)
    local particles = {}
    for i = 1, 6 do
        local angle = math.rad(i * 137.5 + 18)
        local radius = (0.1 + ((i * 29) % 7) * 0.018) * effectScale
        local y = baseY + height * (0.24 + ((i * 17) % 9) * 0.055)
        local sx = (0.09 + ((i * 11) % 5) * 0.014) * effectScale
        local sy = (0.062 + ((i * 7) % 4) * 0.01) * effectScale
        local sz = (0.1 + ((i * 13) % 5) * 0.015) * effectScale
        local basePosition = Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius)
        local baseScale = Vector3(sx, sy, sz)
        local puff = PlantVisual.AddModel(root, "CloudPuff" .. i, "Models/Sphere.mdl", basePosition, baseScale, PlantVisual.materials.cloud, false)
        puff.rotation = Quaternion(math.deg(angle), Vector3.UP)
        table.insert(particles, {
            kind = "fleck",
            mode = "drift",
            node = puff,
            basePosition = basePosition,
            baseScale = baseScale,
            angle = angle,
            orbitRadius = radius,
            baseY = y,
            phase = i * 0.83,
            riseSpeed = 0.12 + i * 0.015,
            riseHeight = height * (0.2 + (i % 3) * 0.05),
            bobSpeed = 0.65 + i * 0.21,
            bobAmp = (0.012 + (i % 3) * 0.008) * effectScale,
            swaySpeed = 0.4 + i * 0.13,
            swayAmp = (0.006 + (i % 4) * 0.004) * effectScale,
            pulseSpeed = 0.72 + i * 0.27,
            pulseAmp = 0.09 + (i % 4) * 0.035,
            spinSpeed = 1.2 + i * 1.4,
            burstSpeed = 0.4,
            spiralSpeed = 0.6,
            snapOffset = i * 0.31,
        })
    end
    RegisterEffect(plantData, root, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_AMBIENT_INTERVAL, particles)
end

local function AddWetOrbitEffect(plantData, effectScale, baseY, height)
    local root = plantData.root:CreateChild("WetOrbitEffect")
    root.position = Vector3(0, 0, 0)
    local particles = {}

    for i = 1, 6 do
        local angle = math.rad(i * 137.5 + 12)
        local radius = (0.34 + (i % 3) * 0.035) * effectScale
        local y = baseY + height * (0.28 + (i % 4) * 0.11)
        local basePosition = Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius)
        local baseScale = Vector3(0.032, 0.06, 0.032) * effectScale
        local drop = PlantVisual.AddModel(root, "WetOrbitDrop" .. i, "Models/Sphere.mdl", basePosition, baseScale, PlantVisual.materials.waterDrop, false)
        drop.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(10, Vector3.RIGHT)
        table.insert(particles, {
            kind = "fleck",
            mode = "pollenOrbit",
            node = drop,
            basePosition = basePosition,
            baseScale = baseScale,
            angle = angle,
            orbitRadius = radius,
            baseY = y,
            phase = i * 0.61,
            riseSpeed = 0.12 + i * 0.01,
            riseHeight = height * 0.18,
            bobSpeed = 0.9 + i * 0.17,
            bobAmp = (0.018 + (i % 3) * 0.008) * effectScale,
            swaySpeed = 0.52 + i * 0.12,
            swayAmp = (0.008 + (i % 4) * 0.003) * effectScale,
            pulseSpeed = 0.9 + i * 0.21,
            pulseAmp = 0.08 + (i % 3) * 0.035,
            spinSpeed = 2.0 + i * 1.6,
            burstSpeed = 0.42,
            spiralSpeed = 0.7,
            snapOffset = i * 0.27,
        })
    end

    for i = 1, 5 do
        local angle = math.rad((i - 1) * 72 + 28)
        local radius = (0.39 + (i % 2) * 0.025) * effectScale
        local y = baseY + height * (0.2 + (i % 3) * 0.12)
        local basePosition = Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius)
        local baseScale = Vector3(0.07, 0.008, 0.016) * effectScale
        local ripple = PlantVisual.AddModel(root, "WetOrbitRipple" .. i, "Models/Box.mdl", basePosition, baseScale, PlantVisual.materials.wetRipple, false)
        ripple.rotation = Quaternion(math.deg(angle) + 8, Vector3.UP) * Quaternion(5, Vector3.RIGHT)
        table.insert(particles, {
            kind = "fleck",
            mode = "pollenOrbit",
            node = ripple,
            basePosition = basePosition,
            baseScale = baseScale,
            angle = angle,
            orbitRadius = radius,
            baseY = y,
            phase = i * 0.77 + 0.35,
            riseSpeed = 0.11 + i * 0.012,
            riseHeight = height * 0.16,
            bobSpeed = 0.76 + i * 0.19,
            bobAmp = (0.014 + (i % 3) * 0.007) * effectScale,
            swaySpeed = 0.48 + i * 0.11,
            swayAmp = (0.006 + (i % 4) * 0.003) * effectScale,
            pulseSpeed = 0.82 + i * 0.24,
            pulseAmp = 0.07 + (i % 3) * 0.03,
            spinSpeed = 1.5 + i * 1.2,
            burstSpeed = 0.38,
            spiralSpeed = 0.62,
            snapOffset = i * 0.33,
        })
    end

    RegisterEffect(plantData, root, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_AMBIENT_INTERVAL, particles)
end

local function AddGoldGlowEffect(plantData, effectScale, baseY, height)
    local root = plantData.root:CreateChild("GoldGlowEffect")
    root.position = Vector3(0, baseY + height * 0.55, 0)

    local light = root:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(1.0, 0.72, 0.22, 1.0)
    light.brightness = 2.15
    light.range = 1.65 * effectScale
    light.castShadows = false

    RegisterEffect(plantData, root, 0.0, 0.35, 0.003 * effectScale, 0.65, 0.018, EFFECT_AMBIENT_INTERVAL)
end

local function AddVoidGlowEffect(plantData, effectScale, baseY, height)
    local root = plantData.root:CreateChild("VoidGlowEffect")
    root.position = Vector3(0, baseY + height * 0.55, 0)

    local light = root:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(0.22, 0.02, 0.55, 1.0)
    light.brightness = 1.65
    light.range = 1.55 * effectScale
    light.castShadows = false

    RegisterEffect(plantData, root, 0.0, 0.35, 0.003 * effectScale, 0.65, 0.018, EFFECT_AMBIENT_INTERVAL)
end

local function CreateOrbitEffect(parent, name, material, count, radius, y, scale, modelPath, verticalJitter)
    local root = parent:CreateChild(name)
    modelPath = modelPath or "Models/Box.mdl"
    verticalJitter = verticalJitter or 0.0
    for i = 1, count do
        local angle = math.rad((i - 1) * (360 / count))
        local waveY = y + math.sin(angle * 2.0) * verticalJitter
        local particle = PlantVisual.AddModel(root, name .. i, modelPath, Vector3(math.cos(angle) * radius, waveY, math.sin(angle) * radius), scale * 1.25, material, false)
        particle.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(28 + i * 11, Vector3.RIGHT)
    end
    return root
end

local function CreateRingEffect(parent, name, material, count, radius, y, width, height)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = (i - 1) * (360 / count)
        local rad = math.rad(angle)
        local segment = PlantVisual.AddModel(root, name .. i, "Models/Box.mdl", Vector3(math.cos(rad) * radius, y, math.sin(rad) * radius), Vector3(width * 1.18, height * 1.35, 0.032), material, false)
        segment.rotation = Quaternion(-angle, Vector3.UP)
    end
    return root
end

local function CreateVoxelCloud(parent, name, material, count, radius, centerY, height, minScale, maxScale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local t = (i - 1) / math.max(1, count - 1)
        local angle = math.rad(i * 137.5)
        local ring = radius * (0.35 + 0.65 * ((i * 17) % 9) / 8)
        local y = centerY + (t - 0.5) * height + math.sin(i * 1.73) * height * 0.14
        local s = (minScale + (maxScale - minScale) * (((i * 23) % 11) / 10)) * 1.35
        local particle = PlantVisual.AddModel(root, name .. i, "Models/Box.mdl", Vector3(math.cos(angle) * ring, y, math.sin(angle) * ring), Vector3(s, s, s), material, false)
        particle.rotation = Quaternion(i * 31, Vector3.UP) * Quaternion(18 + i * 7, Vector3.RIGHT)
    end
    return root
end

local function CreateVoxelBurst(parent, name, material, count, radius, centerY, scale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = math.rad(i * 137.5)
        local tier = (i % 3) - 1
        local r = radius * (0.45 + 0.55 * ((i * 13) % 7) / 6)
        local particle = PlantVisual.AddModel(root, name .. i, "Models/Box.mdl", Vector3(math.cos(angle) * r, centerY + tier * 0.11, math.sin(angle) * r), scale * 1.25, material, false)
        particle.rotation = Quaternion(i * 41, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
    end
    return root
end

local function CreateSparkColumn(parent, name, material, count, radius, minY, maxY, scale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local t = (i - 1) / math.max(1, count - 1)
        local angle = math.rad(i * 137.5)
        local y = minY + (maxY - minY) * t
        local spark = PlantVisual.AddModel(root, name .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), scale * 1.25, material, false)
        spark.rotation = Quaternion(i * 37, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
    end
    return root
end

local function CreateBillboardParticles(parent, name, material, count, spread, baseY, height, minSize, maxSize, color, kind, mode)
    local root = parent:CreateChild(name)
    local billboardSet = root:CreateComponent("BillboardSet")
    billboardSet:SetMaterial(material)
    billboardSet:SetNumBillboards(count)
    billboardSet:SetRelative(true)
    billboardSet:SetScaled(true)
    billboardSet:SetSorted(true)
    billboardSet:SetFaceCameraMode(FC_LOOKAT_XYZ)

    local particles = {}
    for i = 1, count do
        local angle = math.random() * math.pi * 2.0
        local distance = spread * (0.12 + math.random() * 0.9)
        local y = baseY + height * math.random()
        local size = minSize + (maxSize - minSize) * math.random()
        local basePosition = Vector3(math.cos(angle) * distance, y, math.sin(angle) * distance)
        local billboard = billboardSet:GetBillboard(i - 1)
        billboard.position = basePosition
        billboard.size = Vector2(size, size)
        billboard.color = color
        billboard.rotation = math.random() * 360.0
        billboard.enabled = true
        table.insert(particles, {
            kind = kind,
            mode = mode or "rise",
            billboardSet = billboardSet,
            index = i - 1,
            basePosition = basePosition,
            baseSize = size,
            baseColor = color,
            angle = angle,
            orbitRadius = distance,
            phase = math.random() * 6.0,
            riseSpeed = 0.1 + math.random() * 0.18,
            riseHeight = height * (0.32 + math.random() * 0.42),
            drift = Vector3((math.random() - 0.5) * 0.12, 0, (math.random() - 0.5) * 0.12),
            swaySpeed = 0.45 + math.random() * 1.1,
            swayAmp = 0.008 + math.random() * 0.022,
            pulseSpeed = 0.8 + math.random() * 1.4,
            pulseAmp = 0.06 + math.random() * 0.1,
            spinSpeed = -14.0 + math.random() * 28.0,
        })
    end
    billboardSet:Commit()
    return root, particles
end

local function CreateMutationFlecks(parent, name, materials, count, spread, baseY, height, minScale, maxScale, motionMode, modelPaths, shapeMode)
    local root = parent:CreateChild(name)
    local particles = {}
    motionMode = motionMode or "float"
    modelPaths = modelPaths or { "Models/Sphere.mdl" }
    shapeMode = shapeMode or "spark"

    for i = 1, count do
        local mat = materials[math.random(1, #materials)]
        local modelPath = modelPaths[math.random(1, #modelPaths)]
        local angle = math.random() * math.pi * 2.0
        local distance = spread * (0.22 + math.random() * 0.9)
        local y = baseY + height * (0.14 + math.random() * 0.92)
        local sx = minScale + (maxScale - minScale) * math.random()
        local sy = sx
        local sz = sx
        if shapeMode == "orb" then
            sy = sx
            sz = sx
        elseif shapeMode == "drop" then
            sy = sx * (1.65 + math.random() * 0.55)
            sz = sx * 0.92
        elseif shapeMode == "coin" then
            sy = sx * 0.42
            sz = sx * 1.08
        elseif shapeMode == "shard" then
            sy = sx * (1.55 + math.random() * 0.7)
            sz = sx * 0.58
        elseif shapeMode == "pollen" then
            sy = sx * 0.95
            sz = sx * 0.95
        elseif shapeMode == "star" then
            sy = sx * 0.38
            sz = sx * 0.38
        elseif shapeMode == "icicle" then
            sy = sx * (2.45 + math.random() * 0.65)
            sz = sx * 0.42
        elseif shapeMode == "voidShard" then
            sy = sx * (1.1 + math.random() * 0.55)
            sz = sx * 0.34
        elseif shapeMode == "mist" then
            sy = sx * 0.8
            sz = sx * 1.35
        else
            sy = sx * (0.78 + math.random() * 0.35)
            sz = sx * (0.6 + math.random() * 0.4)
        end
        local basePosition = Vector3(math.cos(angle) * distance, y, math.sin(angle) * distance)
        local baseScale = Vector3(sx, sy, sz)
        local fleck = PlantVisual.AddModel(root, name .. "Fleck" .. i, modelPath, basePosition, baseScale, mat, false)
        fleck.rotation = Quaternion(math.random(0, 359), Vector3.UP) * Quaternion(10 + math.random() * 55, Vector3.RIGHT)
        table.insert(particles, {
            kind = "fleck",
            mode = motionMode,
            node = fleck,
            basePosition = basePosition,
            baseScale = baseScale,
            angle = angle,
            orbitRadius = distance,
            baseY = y,
            phase = math.random() * 6.0,
            riseSpeed = 0.18 + math.random() * 0.22,
            riseHeight = height * (0.45 + math.random() * 0.55),
            bobSpeed = 1.05 + math.random() * 1.25,
            bobAmp = (motionMode == "pollenOrbit") and (0.028 + math.random() * 0.026) or (0.012 + math.random() * 0.03),
            swaySpeed = 0.65 + math.random() * 1.0,
            swayAmp = 0.006 + math.random() * 0.018,
            pulseSpeed = 1.25 + math.random() * 1.45,
            pulseAmp = 0.035 + math.random() * 0.075,
            spinSpeed = 3.0 + math.random() * 14.0,
            burstSpeed = 0.55 + math.random() * 0.6,
            spiralSpeed = 1.2 + math.random() * 0.9,
            snapOffset = 0.25 + math.random() * 0.45,
        })
    end
    return root, particles
end

local function AddMutationEmitterEffects(plantData, mutation, effectScale, baseY, height)
    local root = plantData.root
    local spread = 0.46 * effectScale
    local particleBaseY = baseY + height * 0.12
    local particleHeight = math.max(0.16, height * 0.74)

    local function addEmitter(name, material, count, color, sizeMin, sizeMax, mode, spreadScale, baseOffsetScale, heightScale)
        local emitterBaseY = particleBaseY + height * (baseOffsetScale or 0.0)
        local emitterHeight = particleHeight * (heightScale or 1.0)
        local emitterRoot, particles = CreateBillboardParticles(root, name, material, count, spread * (spreadScale or 1.0), emitterBaseY, emitterHeight, sizeMin * effectScale, sizeMax * effectScale, color, "billboardSpark", mode)
        RegisterEffect(plantData, emitterRoot, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_DETAIL_INTERVAL, particles)
    end

    if PlantVisual.HasSpecial(mutation, "wet") then
        addEmitter("WetStarEmitter", PlantVisual.materials.wetStarBillboard, 8, Color(1.0, 1.0, 1.0, 0.2), 0.09, 0.195, "steam", 1.75)
    elseif PlantVisual.HasSpecial(mutation, "stardust") then
        addEmitter("StarDustEmitter", PlantVisual.materials.starSparkBillboard, 8, Color(1.0, 0.94, 0.42, 0.86), 0.09, 0.19, "twinkle", 1.95)
    elseif PlantVisual.HasSpecial(mutation, "cloud") then
        addEmitter("CloudStarEmitter", PlantVisual.materials.cloudStarBillboard, 14, Color(1.0, 1.0, 1.0, 0.25), 0.23, 0.46, "cloudDrift", 1.3, -0.28, 0.46)
    elseif PlantVisual.HasSpecial(mutation, "pollen") then
        addEmitter("PollenPetalEmitter", PlantVisual.materials.pollenStarBillboard, 8, Color(1.0, 1.0, 1.0, 0.25), 0.05, 0.105, "orbit", 1.75)
    end
end

local function CreateCrystalCrown(parent, name, material, count, radius, y, height)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = (i - 1) * (360 / count)
        local rad = math.rad(angle)
        local crystal = PlantVisual.AddModel(root, name .. i, "Models/Box.mdl", Vector3(math.cos(rad) * radius, y, math.sin(rad) * radius), Vector3(0.045, height, 0.045), material, false)
        crystal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(24, Vector3.RIGHT)
    end
    return root
end

local function CreateColorAuraMaterial(mutation)
    if mutation.colorMutation == nil then
        return nil
    end
    local c = mutation.colorMutation.color
    local key = "colorAura_" .. ColorKey(c)
    if PlantVisual.materials[key] ~= nil then
        return PlantVisual.materials[key]
    end
    return PlantVisual.CreateUnlitMaterial(key, Color(math.min(1.0, c.r * 1.25 + 0.1), math.min(1.0, c.g * 1.25 + 0.1), math.min(1.0, c.b * 1.25 + 0.1), 1.0))
end

local function CreateMutationBeacon(parent, name, material, size, tier)
    local root = parent:CreateChild(name)
    local height = 1.18 + tier * 0.1
    PlantVisual.AddModel(root, name .. "Core", "Models/Box.mdl", Vector3(0, height, 0), Vector3(0.13, 0.13, 0.13) * size, material, false)
    for i = 1, 4 do
        local angle = math.rad((i - 1) * 90 + 45)
        local shard = PlantVisual.AddModel(root, name .. "Shard" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.24 * size, height - 0.08, math.sin(angle) * 0.24 * size), Vector3(0.045, 0.2, 0.045) * size, material, false)
        shard.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(28, Vector3.RIGHT)
    end
    return root
end

local function CreateSignatureStructure(parent, name, mutation, materials, spread, baseY, height)
    local root = parent:CreateChild(name)
    local accent = materials[1]
    local topY = baseY + height * 0.82

    if PlantVisual.HasSpecial(mutation, "gold") then
        PlantVisual.AddModel(root, "GoldCore", "Models/Sphere.mdl", Vector3(0, topY + 0.04, 0), Vector3(0.1, 0.1, 0.1), PlantVisual.materials.auraGold, false)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local halo = PlantVisual.AddModel(root, "GoldGlowDot" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * spread * 0.36, topY + math.sin(i) * 0.018, math.sin(angle) * spread * 0.36), Vector3(0.034, 0.034, 0.034), PlantVisual.materials.auraGold, false)
            halo.rotation = Quaternion(math.deg(angle), Vector3.UP)
        end
    elseif PlantVisual.HasSpecial(mutation, "frozen") then
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90)
            local crystal = PlantVisual.AddModel(root, "IceSpike" .. i, "Models/Cone.mdl", Vector3(math.cos(angle) * spread * 0.42, topY - 0.05, math.sin(angle) * spread * 0.42), Vector3(0.045, 0.13, 0.045), PlantVisual.materials.iceCrystal, false)
            crystal.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(18, Vector3.RIGHT)
        end
        PlantVisual.AddModel(root, "IceCore", "Models/Sphere.mdl", Vector3(0, topY + 0.02, 0), Vector3(0.09, 0.09, 0.09), PlantVisual.materials.auraBlue, false)
    elseif PlantVisual.HasSpecial(mutation, "wet") then
        for i = 1, 3 do
            local angle = math.rad((i - 1) * 120 + 18)
            local drop = PlantVisual.AddModel(root, "WaterDrop" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * spread * 0.4, topY - 0.02, math.sin(angle) * spread * 0.4), Vector3(0.045, 0.075, 0.045), PlantVisual.materials.waterDrop, false)
            drop.rotation = Quaternion(math.deg(angle), Vector3.UP)
        end
    elseif PlantVisual.HasSpecial(mutation, "cloud") then
        for i = 1, 3 do
            local angle = math.rad((i - 1) * 120)
            local radius = spread * (0.16 + (i % 2) * 0.12)
            PlantVisual.AddModel(root, "CloudPuff" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, topY + math.sin(i) * 0.025, math.sin(angle) * radius), Vector3(0.06, 0.048, 0.06), PlantVisual.materials.cloud, false)
        end
    elseif PlantVisual.HasSpecial(mutation, "ceramic") then
        PlantVisual.AddModel(root, "CeramicPearl", "Models/Sphere.mdl", Vector3(0, topY + 0.01, 0), Vector3(0.055, 0.055, 0.055), PlantVisual.materials.ceramic, false)
        for i = 1, 2 do
            local angle = math.rad((i - 1) * 180 + 35)
            local chip = PlantVisual.AddModel(root, "CeramicBlueInlay" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * spread * 0.26, topY - 0.01, math.sin(angle) * spread * 0.26), Vector3(0.04, 0.012, 0.026), PlantVisual.materials.ceramicBlue, false)
            chip.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(12, Vector3.RIGHT)
        end
    elseif PlantVisual.HasSpecial(mutation, "pollen") then
        for i = 1, 4 do
            local angle = math.rad(i * 137.5)
            local radius = spread * (0.18 + (i % 2) * 0.12)
            PlantVisual.AddModel(root, "PollenOrb" .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, baseY + height * (0.36 + (i % 3) * 0.16), math.sin(angle) * radius), Vector3(0.032, 0.032, 0.032), PlantVisual.materials.pollen, false)
        end
    elseif PlantVisual.HasSpecial(mutation, "void") then
        for i = 1, 6 do
            local angle = math.rad((i - 1) * 60 + 18)
            local radius = spread * (0.32 + (i % 2) * 0.16)
            local spike = PlantVisual.AddModel(root, "VoidShard" .. i, "Models/Cone.mdl", Vector3(math.cos(angle) * radius, topY - 0.04 + math.sin(i) * 0.025, math.sin(angle) * radius), Vector3(0.026, 0.16, 0.026), PlantVisual.materials.voidSpark, false)
            spike.rotation = Quaternion(math.deg(angle) + 180, Vector3.UP) * Quaternion(72, Vector3.RIGHT)
        end
        PlantVisual.AddModel(root, "VoidCore", "Models/Sphere.mdl", Vector3(0, topY - 0.02, 0), Vector3(0.062, 0.062, 0.062), PlantVisual.materials.void, false)
    elseif PlantVisual.HasSpecial(mutation, "chocolate") then
        PlantVisual.AddModel(root, "ChocoAccent", "Models/Sphere.mdl", Vector3(0, topY - 0.02, 0), Vector3(0.04, 0.05, 0.04), PlantVisual.materials.chocolateSpark, false)
    elseif PlantVisual.HasSpecial(mutation, "glow") then
        PlantVisual.AddModel(root, "GlowCore", "Models/Sphere.mdl", Vector3(0, topY + 0.02, 0), Vector3(0.09, 0.09, 0.09), PlantVisual.materials.magicSpark, false)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local ray = PlantVisual.AddModel(root, "GlowShard" .. i, "Models/Cone.mdl", Vector3(math.cos(angle) * spread * 0.42, topY, math.sin(angle) * spread * 0.42), Vector3(0.035, 0.15, 0.035), PlantVisual.materials.auraPurple, false)
            ray.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(68, Vector3.RIGHT)
        end
    elseif PlantVisual.HasSpecial(mutation, "stardust") then
        PlantVisual.AddModel(root, "StarCore", "Models/Sphere.mdl", Vector3(0, topY + 0.02, 0), Vector3(0.05, 0.05, 0.05), PlantVisual.materials.star, false)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local radius = spread * (0.22 + (i % 2) * 0.1)
            local star = PlantVisual.AddModel(root, "StarPoint" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * radius, topY + math.sin(i) * 0.026, math.sin(angle) * radius), Vector3(0.055, 0.012, 0.012), (i % 2 == 0) and PlantVisual.materials.star or PlantVisual.materials.auraBlue, false)
            star.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(45, Vector3.RIGHT)
        end
    elseif PlantVisual.HasSpecial(mutation, "rainbow") then
        for i = 1, 3 do
            local angle = math.rad((i - 1) * 120)
            local mat = materials[((i - 1) % #materials) + 1]
            local prism = PlantVisual.AddModel(root, "Prism" .. i, "Models/Cone.mdl", Vector3(math.cos(angle) * spread * 0.42, topY + 0.02, math.sin(angle) * spread * 0.42), Vector3(0.04, 0.12, 0.04), mat, false)
            prism.rotation = Quaternion(math.deg(angle), Vector3.UP) * Quaternion(34, Vector3.RIGHT)
        end
    end

    return root
end

local function UsesEmitterStyle(mutation)
    return PlantVisual.HasSpecial(mutation, "wet")
        or PlantVisual.HasSpecial(mutation, "stardust")
        or PlantVisual.HasSpecial(mutation, "cloud")
        or PlantVisual.HasSpecial(mutation, "pollen")
end

function PlantVisual.CreateSpecialEffects(plantData)
    local root = plantData.root
    plantData.effectNodes = {}
    local mutation = plantData.mutation
    local size = mutation.sizeScale
    local specialCount = CountSpecials(mutation)
    if specialCount <= 0 then
        return
    end

    local accent = GetDominantAuraMaterial(mutation)
    local fleckMaterials = { accent }
    if mutation.colorMutation ~= nil then
        table.insert(fleckMaterials, CreateColorAuraMaterial(mutation))
    end
    if PlantVisual.HasSpecial(mutation, "stardust") then
        fleckMaterials = { PlantVisual.materials.star, PlantVisual.materials.auraBlue }
    elseif PlantVisual.HasSpecial(mutation, "rainbow") then
        fleckMaterials = { PlantVisual.materials.rainbowRed, PlantVisual.materials.rainbowGreen, PlantVisual.materials.rainbowBlue, PlantVisual.materials.star }
    elseif PlantVisual.HasSpecial(mutation, "gold") then
        fleckMaterials = { PlantVisual.materials.auraGold, PlantVisual.materials.gold }
    elseif PlantVisual.HasSpecial(mutation, "wet") then
        fleckMaterials = { PlantVisual.materials.waterDrop, PlantVisual.materials.auraBlue }
    elseif PlantVisual.HasSpecial(mutation, "frozen") then
        fleckMaterials = { PlantVisual.materials.iceCrystal, PlantVisual.materials.auraBlue }
    elseif PlantVisual.HasSpecial(mutation, "cloud") then
        fleckMaterials = { PlantVisual.materials.cloud }
    elseif PlantVisual.HasSpecial(mutation, "ceramic") then
        fleckMaterials = { PlantVisual.materials.ceramicBlue, PlantVisual.materials.ceramicDeepBlue }
    elseif PlantVisual.HasSpecial(mutation, "pollen") then
        fleckMaterials = { PlantVisual.materials.pollen, PlantVisual.materials.pollenOrange }
    elseif PlantVisual.HasSpecial(mutation, "void") then
        fleckMaterials = { PlantVisual.materials.voidSpark, PlantVisual.materials.auraPurple, PlantVisual.materials.void }
    elseif PlantVisual.HasSpecial(mutation, "glow") then
        fleckMaterials = { PlantVisual.materials.magicSpark, PlantVisual.materials.auraPurple }
    elseif PlantVisual.HasSpecial(mutation, "chocolate") then
        fleckMaterials = { PlantVisual.materials.chocolateSpark, PlantVisual.materials.chocolate }
    end

    local visualScale = 0.42 * size
    local effectScale = math.max(0.38, visualScale)
    local fleckCount = 4
    local spread = 0.72 * effectScale
    local baseY = 1.05 * effectScale
    local height = 0.78 * effectScale
    if UsesEmitterStyle(mutation) then
        AddMutationEmitterEffects(plantData, mutation, effectScale, baseY, height)
    end
    local minScale = 0.066 * effectScale
    local maxScale = 0.124 * effectScale
    local primaryMotion = "float"
    local secondaryMotion = "rise"
    local primaryModels = { "Models/Sphere.mdl" }
    local secondaryModels = { "Models/Cone.mdl", "Models/Sphere.mdl" }
    local signatureModels = { "Models/Cone.mdl" }
    local primaryShape = "orb"
    local secondaryShape = "shard"
    local signatureShape = "shard"
    local signatureMotion = "burst"
    local signatureCount = 3
    local signatureScale = 1.0

    if PlantVisual.HasSpecial(mutation, "gold") or PlantVisual.HasSpecial(mutation, "void") then
        fleckCount = 4
        height = height * 0.58
    end

    if PlantVisual.HasSpecial(mutation, "stardust") then
        fleckCount = 3
        primaryMotion = "twinkle"
        secondaryMotion = "snap"
        signatureMotion = "snap"
        primaryModels = { "Models/Sphere.mdl", "Models/Box.mdl" }
        secondaryModels = { "Models/Box.mdl", "Models/Box.mdl" }
        signatureModels = { "Models/Box.mdl", "Models/Sphere.mdl" }
        primaryShape = "star"
        secondaryShape = "star"
        signatureShape = "star"
        signatureCount = 2
        signatureScale = 0.58
        spread = spread * 0.46
        height = height * 0.28
        minScale = minScale * 0.58
        maxScale = maxScale * 0.68
    elseif PlantVisual.HasSpecial(mutation, "glow") then
        fleckCount = 0
        primaryMotion = "pulse"
        secondaryMotion = "pulse"
        signatureMotion = "pulse"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "orb"
        secondaryShape = "orb"
        signatureShape = "orb"
        signatureCount = 0
        signatureScale = 0.0
        spread = spread * 0.45
        height = height * 0.45
    elseif PlantVisual.HasSpecial(mutation, "rainbow") then
        fleckCount = 0
        signatureCount = 0
        signatureScale = 0.0
    elseif PlantVisual.HasSpecial(mutation, "gold") then
        fleckCount = 0
        primaryMotion = "pulse"
        secondaryMotion = "pulse"
        signatureMotion = "pulse"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "orb"
        secondaryShape = "orb"
        signatureShape = "orb"
        signatureCount = 0
        signatureScale = 0.0
        spread = spread * 0.48
        height = height * 0.38
        minScale = minScale * 0.58
        maxScale = maxScale * 0.68
    elseif PlantVisual.HasSpecial(mutation, "wet") then
        fleckCount = 4
        primaryMotion = "pollenOrbit"
        secondaryMotion = "pollenOrbit"
        signatureMotion = "pollenOrbit"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "drop"
        secondaryShape = "drop"
        signatureShape = "drop"
        signatureCount = 2
        signatureScale = 0.72
        spread = spread * 0.58
        height = height * 0.52
        minScale = minScale * 0.48
        maxScale = maxScale * 0.62
    elseif PlantVisual.HasSpecial(mutation, "frozen") then
        fleckCount = 3
        primaryMotion = "snap"
        secondaryMotion = "twinkle"
        signatureMotion = "beam"
        primaryModels = { "Models/Cone.mdl", "Models/Box.mdl" }
        secondaryModels = { "Models/Box.mdl", "Models/Cone.mdl" }
        signatureModels = { "Models/Cone.mdl", "Models/Cone.mdl" }
        primaryShape = "icicle"
        secondaryShape = "shard"
        signatureShape = "icicle"
        signatureCount = 2
        signatureScale = 0.95
        spread = spread * 0.52
        height = height * 0.52
        minScale = minScale * 0.62
        maxScale = maxScale * 0.72
    elseif PlantVisual.HasSpecial(mutation, "cloud") then
        primaryMotion = "drift"
        secondaryMotion = "rise"
        signatureMotion = "drift"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Cylinder.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "mist"
        secondaryShape = "mist"
        signatureShape = "mist"
        signatureCount = 3
        signatureScale = 1.7
    elseif PlantVisual.HasSpecial(mutation, "ceramic") then
        fleckCount = 0
        primaryMotion = "orbit"
        secondaryMotion = "orbit"
        signatureMotion = "orbit"
        primaryModels = { "Models/Box.mdl", "Models/Box.mdl" }
        secondaryModels = { "Models/Box.mdl", "Models/Box.mdl" }
        signatureModels = { "Models/Box.mdl", "Models/Box.mdl" }
        primaryShape = "star"
        secondaryShape = "star"
        signatureShape = "star"
        signatureCount = 0
        signatureScale = 0.0
    elseif PlantVisual.HasSpecial(mutation, "pollen") then
        fleckCount = 3
        primaryMotion = "pollenOrbit"
        secondaryMotion = "pollenOrbit"
        signatureMotion = "pollenOrbit"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "pollen"
        secondaryShape = "pollen"
        signatureShape = "pollen"
        signatureCount = 2
        signatureScale = 0.72
        spread = spread * 0.62
        height = height * 0.45
        minScale = minScale * 0.42
        maxScale = maxScale * 0.52
    elseif PlantVisual.HasSpecial(mutation, "void") then
        fleckCount = 0
        primaryMotion = "pulse"
        secondaryMotion = "pulse"
        signatureMotion = "pulse"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "orb"
        secondaryShape = "orb"
        signatureShape = "orb"
        signatureCount = 0
        signatureScale = 0.0
        spread = spread * 0.48
        height = height * 0.38
        minScale = minScale * 0.48
        maxScale = maxScale * 0.62
    elseif PlantVisual.HasSpecial(mutation, "chocolate") then
        fleckCount = 4
        height = height * 0.45
        spread = spread * 0.58
        primaryMotion = "pollenOrbit"
        secondaryMotion = "pollenOrbit"
        signatureMotion = "pollenOrbit"
        primaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        secondaryModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        signatureModels = { "Models/Sphere.mdl", "Models/Sphere.mdl" }
        primaryShape = "drop"
        secondaryShape = "drop"
        signatureShape = "drop"
        signatureCount = 2
        signatureScale = 0.68
    end

    local closeFleckCount = math.max(2, math.floor(fleckCount * 0.45))
    local highFleckCount = math.max(1, math.floor(fleckCount * 0.2))
    local signatureFleckCount = math.max(1, signatureCount)
    if PlantVisual.HasSpecial(mutation, "chocolate") then
        closeFleckCount = 3
        highFleckCount = 1
        signatureFleckCount = 1
    elseif PlantVisual.HasSpecial(mutation, "rainbow") then
        closeFleckCount = 0
        highFleckCount = 0
        signatureFleckCount = 0
    elseif PlantVisual.HasSpecial(mutation, "wet") then
        closeFleckCount = 0
        highFleckCount = 0
        signatureFleckCount = 0
    elseif PlantVisual.HasSpecial(mutation, "glow") or PlantVisual.HasSpecial(mutation, "ceramic") or PlantVisual.HasSpecial(mutation, "frozen") or PlantVisual.HasSpecial(mutation, "gold") or PlantVisual.HasSpecial(mutation, "void") or UsesEmitterStyle(mutation) then
        closeFleckCount = 0
        highFleckCount = 0
        signatureFleckCount = 0
    elseif PlantVisual.HasSpecial(mutation, "pollen") then
        closeFleckCount = 3
        highFleckCount = 1
        signatureFleckCount = 1
    end

    if closeFleckCount > 0 then
        local closeFleckRoot, closeFleckParticles = CreateMutationFlecks(root, "MutationFlecks", fleckMaterials, closeFleckCount, spread * 0.82, baseY + 0.08 * effectScale, height * 0.78, minScale * 0.72, maxScale * 0.78, primaryMotion, primaryModels, primaryShape)
        RegisterEffect(plantData, closeFleckRoot, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_AMBIENT_INTERVAL, closeFleckParticles)
    end

    if highFleckCount > 0 then
        local highFleckRoot, highFleckParticles = CreateMutationFlecks(root, "MutationGlints", fleckMaterials, highFleckCount, spread * 1.04, baseY + 0.16 * effectScale, height * 0.72, minScale * 0.48, maxScale * 0.58, secondaryMotion, secondaryModels, secondaryShape)
        RegisterEffect(plantData, highFleckRoot, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_DETAIL_INTERVAL, highFleckParticles)
    end

    if signatureFleckCount > 0 then
        local signatureRoot, signatureParticles = CreateMutationFlecks(root, "MutationSignature", fleckMaterials, signatureFleckCount, spread * 0.98, baseY + 0.1 * effectScale, height * 0.66, minScale * 0.9 * signatureScale, maxScale * 1.1 * signatureScale, signatureMotion, signatureModels, signatureShape)
        RegisterEffect(plantData, signatureRoot, 0.0, 0.0, 0.0, 0.0, 0.0, EFFECT_DETAIL_INTERVAL, signatureParticles)
    end

    if PlantVisual.HasSpecial(mutation, "gold") then
        AddGoldGlowEffect(plantData, effectScale, baseY, height)
    end

    if PlantVisual.HasSpecial(mutation, "void") then
        AddVoidGlowEffect(plantData, effectScale, baseY, height)
    end

    if PlantVisual.HasSpecial(mutation, "devour") then
        AddVoidGlowEffect(plantData, effectScale, baseY, height)
    end

    if PlantVisual.HasSpecial(mutation, "glow") then
        AddGlowLightEffect(plantData, effectScale, baseY, height)
    end

    if not PlantVisual.HasSpecial(mutation, "glow") and not PlantVisual.HasSpecial(mutation, "ceramic") and not PlantVisual.HasSpecial(mutation, "wet") and not PlantVisual.HasSpecial(mutation, "pollen") and not PlantVisual.HasSpecial(mutation, "rainbow") and not PlantVisual.HasSpecial(mutation, "frozen") and not PlantVisual.HasSpecial(mutation, "gold") and not PlantVisual.HasSpecial(mutation, "void") and not PlantVisual.HasSpecial(mutation, "devour") and not UsesEmitterStyle(mutation) then
        local structureRoot = CreateSignatureStructure(root, "MutationStructure", mutation, fleckMaterials, spread, baseY, height)
        RegisterEffect(plantData, structureRoot, 10.0, 0.75, 0.018, 1.2, 0.08, EFFECT_AMBIENT_INTERVAL)
    end
end


return PlantVisual
