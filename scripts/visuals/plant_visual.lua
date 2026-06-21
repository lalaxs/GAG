-- ============================================================================
-- 作物视觉模块 (Plant Visual)
-- Grow A Garden
-- ============================================================================
-- 管理程序化材质、作物方块模型、成熟特效。
-- 本模块不处理 UI、不处理播种/收获规则，只负责视觉创建。
-- ============================================================================

local PlantVisual = {
    materials = {},
}

function PlantVisual.HasSpecial(mutation, key)
    for _, item in ipairs(mutation.specials) do
        if item.key == key then
            return true
        end
    end
    return false
end

function PlantVisual.CreateMaterial(name, color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.55, 0.55, 0.55, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.55))
    if emissive ~= nil then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    PlantVisual.materials[name] = mat
    return mat
end

function PlantVisual.CreateTransparentMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.8, 0.8, 0.8, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    PlantVisual.materials[name] = mat
    return mat
end

function PlantVisual.CreateUnlitMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    PlantVisual.materials[name] = mat
    return mat
end

function PlantVisual.AddModel(parent, name, modelPath, position, scale, material)
    local node = parent:CreateChild(name)
    node.position = position
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", modelPath))
    model:SetMaterial(material)
    model.castShadows = true
    return node
end

function PlantVisual.InitMaterials()
    PlantVisual.CreateMaterial("grass", Color(0.12, 0.42, 0.16, 1.0), 0.0, 0.9)
    PlantVisual.CreateMaterial("grassTop", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.55)
    PlantVisual.CreateMaterial("soilSide", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.78)
    PlantVisual.CreateMaterial("soil", Color(0.45, 0.28, 0.12, 1.0), 0.0, 0.72)
    PlantVisual.CreateMaterial("soilLocked", Color(0.34, 0.37, 0.34, 1.0), 0.0, 0.85)
    PlantVisual.CreateMaterial("soilSelected", Color(0.67, 0.42, 0.2, 1.0), 0.0, 0.58)
    PlantVisual.CreateMaterial("seed", Color(0.32, 0.18, 0.075, 1.0), 0.0, 0.62)
    PlantVisual.CreateMaterial("path", Color(0.48, 0.36, 0.22, 1.0), 0.0, 0.8)
    PlantVisual.CreateMaterial("stem", Color(0.14, 0.55, 0.18, 1.0), 0.0, 0.65)
    PlantVisual.CreateMaterial("leaf", Color(0.08, 0.72, 0.19, 1.0), 0.0, 0.55)
    PlantVisual.CreateMaterial("wood", Color(0.45, 0.25, 0.1, 1.0), 0.0, 0.72)
    PlantVisual.CreateMaterial("gold", Color(1.0, 0.68, 0.12, 1.0), 1.0, 0.18, Color(0.25, 0.15, 0.02, 1.0))
    PlantVisual.CreateMaterial("frozen", Color(0.55, 0.88, 1.0, 1.0), 0.0, 0.08, Color(0.04, 0.16, 0.25, 1.0))
    PlantVisual.CreateMaterial("glow", Color(0.45, 0.15, 1.0, 1.0), 0.0, 0.18, Color(0.55, 0.12, 1.2, 1.0))
    PlantVisual.CreateMaterial("chocolate", Color(0.24, 0.1, 0.035, 1.0), 0.0, 0.38)
    PlantVisual.CreateMaterial("ceramic", Color(0.9, 0.92, 0.86, 1.0), 0.0, 0.08)
    PlantVisual.CreateMaterial("void", Color(0.01, 0.006, 0.02, 1.0), 0.0, 0.4, Color(0.14, 0.02, 0.35, 1.0))
    PlantVisual.CreateUnlitMaterial("select", Color(0.46, 0.82, 0.42, 1.0))
    PlantVisual.CreateTransparentMaterial("waterDrop", Color(0.2, 0.65, 1.0, 0.62))
    PlantVisual.CreateTransparentMaterial("cloud", Color(0.92, 0.95, 1.0, 0.5))
    PlantVisual.CreateUnlitMaterial("star", Color(1.0, 0.9, 0.3, 1.0))
    PlantVisual.CreateUnlitMaterial("pollen", Color(1.0, 0.82, 0.12, 1.0))
end


function PlantVisual.ResolvePlantMaterial(plant, mutation)
    if PlantVisual.HasSpecial(mutation, "gold") then
        return PlantVisual.materials.gold
    end
    if PlantVisual.HasSpecial(mutation, "frozen") then
        return PlantVisual.materials.frozen
    end
    if PlantVisual.HasSpecial(mutation, "glow") then
        return PlantVisual.materials.glow
    end
    if PlantVisual.HasSpecial(mutation, "chocolate") then
        return PlantVisual.materials.chocolate
    end
    if PlantVisual.HasSpecial(mutation, "ceramic") then
        return PlantVisual.materials.ceramic
    end
    if PlantVisual.HasSpecial(mutation, "void") then
        return PlantVisual.materials.void
    end

    local color = plant.color
    if mutation.colorMutation ~= nil then
        color = mutation.colorMutation.color
    end
    local key = "plant_" .. plant.name .. tostring(math.random(100000, 999999))
    return PlantVisual.CreateMaterial(key, color, 0.0, 0.42)
end

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

function PlantVisual.CreatePlantVisual(parent, plant, mutation, material)
    local visual = parent:CreateChild("Visual")
    local stageScale = 0.42
    visual.scale = Vector3(stageScale, stageScale, stageScale) * mutation.sizeScale

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
        CreateBlockFruit(visual, "CornCob", Vector3(0, 0.6, 0.1), Vector3(0.18, 0.4, 0.18), material)
        -- 苞叶包裹下半部分
        local huskMat = PlantVisual.CreateMaterial("husk" .. tostring(math.random(100000, 999999)), Color(0.3, 0.6, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "HuskL", Vector3(-0.08, 0.52, 0.1), Vector3(0.04, 0.3, 0.16), huskMat)
        CreateBlockFruit(visual, "HuskR", Vector3(0.08, 0.52, 0.1), Vector3(0.04, 0.3, 0.16), huskMat)
        CreateBlockFruit(visual, "HuskB", Vector3(0, 0.52, 0.18), Vector3(0.14, 0.26, 0.04), huskMat)

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

    return visual
end

local function CreateOrbitEffect(parent, name, material, count, radius, y, scale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = math.rad((i - 1) * (360 / count))
        PlantVisual.AddModel(root, name .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), scale, material)
    end
    return root
end

function PlantVisual.CreateSpecialEffects(plantData)
    local root = plantData.root
    plantData.effectNodes = {}
    local mutation = plantData.mutation

    if PlantVisual.HasSpecial(mutation, "wet") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "WaterDrops", PlantVisual.materials.waterDrop, 8, 0.55 * mutation.sizeScale, 0.8, Vector3(0.055, 0.11, 0.055)))
    end
    if PlantVisual.HasSpecial(mutation, "stardust") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Stars", PlantVisual.materials.star, 10, 0.75 * mutation.sizeScale, 1.2, Vector3(0.06, 0.06, 0.06)))
    end
    if PlantVisual.HasSpecial(mutation, "cloud") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Clouds", PlantVisual.materials.cloud, 5, 0.5 * mutation.sizeScale, 0.95, Vector3(0.2, 0.12, 0.14)))
    end
    if PlantVisual.HasSpecial(mutation, "pollen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Pollen", PlantVisual.materials.pollen, 12, 0.65 * mutation.sizeScale, 0.9, Vector3(0.035, 0.035, 0.035)))
    end
    if PlantVisual.HasSpecial(mutation, "void") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "VoidRing", PlantVisual.materials.void, 14, 0.8 * mutation.sizeScale, 0.9, Vector3(0.045, 0.045, 0.045)))
    end
    if PlantVisual.HasSpecial(mutation, "frozen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "ColdMist", PlantVisual.materials.cloud, 6, 0.42 * mutation.sizeScale, 0.35, Vector3(0.12, 0.05, 0.12)))
    end
end


return PlantVisual
