-- ============================================================================
-- 种子程序化模型模块 (Seed Procedural Visual)
-- Grow A Garden - 乐高/Roblox 体素方块风
-- ============================================================================
-- 风格：硬边立方体、低多边形、纯色平涂 + 微弱渐变
-- 基底：统一小型方块主体，适配播种场景
-- 配色：成熟作物主色调
-- 稀有度视觉分层：
--   普通 = 哑光纯色
--   罕见 = 轻微发光
--   稀有 = 明显发光 + 降低粗糙度
--   史诗 = 强发光 + 金属质感
--   传奇 = 棱镜高光 + 流光描边
-- ============================================================================

local SeedVisual = {}

-- 稀有度 → 材质参数映射
local RARITY_PARAMS = {
    ["普通"] = { metallic = 0.0, roughness = 0.75, emissive = 0.0, outline = false },
    ["罕见"] = { metallic = 0.0, roughness = 0.60, emissive = 0.08, outline = false },
    ["稀有"] = { metallic = 0.1, roughness = 0.45, emissive = 0.18, outline = false },
    ["史诗"] = { metallic = 0.4, roughness = 0.28, emissive = 0.35, outline = true },
    ["传奇"] = { metallic = 0.7, roughness = 0.12, emissive = 0.55, outline = true },
}

--- 创建种子材质
---@param color Color 作物主色调
---@param rarity string 稀有度
---@return Material
local function CreateSeedMaterial(color, rarity)
    local params = RARITY_PARAMS[rarity] or RARITY_PARAMS["普通"]
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(params.metallic))
    mat:SetShaderParameter("Roughness", Variant(params.roughness))
    if params.emissive > 0 then
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(
            color.r * params.emissive,
            color.g * params.emissive,
            color.b * params.emissive, 1.0
        )))
    end
    return mat
end

--- 创建高光描边材质（传奇/史诗外框）
---@param color Color
---@return Material
local function CreateOutlineMaterial(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    local bright = Color(
        math.min(1.0, color.r * 1.5 + 0.3),
        math.min(1.0, color.g * 1.5 + 0.3),
        math.min(1.0, color.b * 1.5 + 0.3), 1.0
    )
    mat:SetShaderParameter("MatDiffColor", Variant(bright))
    mat:SetShaderParameter("Metallic", Variant(0.9))
    mat:SetShaderParameter("Roughness", Variant(0.05))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(bright.r * 0.6, bright.g * 0.6, bright.b * 0.6, 1.0)))
    return mat
end

--- 创建深色底座材质
---@param color Color
---@return Material
local function CreateBaseMaterial(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    local dark = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 1.0)
    mat:SetShaderParameter("MatDiffColor", Variant(dark))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.8))
    return mat
end

--- 创建程序化种子模型（方块风）
--- 结构：底座方块 + 主体方块 + 顶部小芽（稀有+）+ 描边框（史诗+）
---@param parentNode Node 父节点
---@param plant table 植物配置（含 color, rarity, name）
---@param scale number 整体缩放因子（默认 1.0）
---@return Node 种子根节点
function SeedVisual.Create(parentNode, plant, scale)
    scale = scale or 1.0
    local color = plant.color
    local rarity = plant.rarity
    local params = RARITY_PARAMS[rarity] or RARITY_PARAMS["普通"]

    local root = parentNode:CreateChild("SeedBlock_" .. plant.name)

    -- 尺寸定义（方块风：正方形截面，略高）
    local baseSize = 0.06 * scale    -- 底座宽度
    local bodySize = 0.055 * scale   -- 主体宽度
    local bodyH = 0.065 * scale      -- 主体高度
    local baseH = 0.02 * scale       -- 底座高度

    -- ① 底座（深色小方块）
    local baseMat = CreateBaseMaterial(color)
    local baseNode = root:CreateChild("Base")
    baseNode.position = Vector3(0, baseH * 0.5, 0)
    baseNode.scale = Vector3(baseSize, baseH, baseSize)
    local baseModel = baseNode:CreateComponent("StaticModel")
    baseModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    baseModel:SetMaterial(baseMat)
    baseModel.castShadows = true

    -- ② 主体方块（作物色，核心体）
    local bodyMat = CreateSeedMaterial(color, rarity)
    local bodyNode = root:CreateChild("Body")
    bodyNode.position = Vector3(0, baseH + bodyH * 0.5, 0)
    bodyNode.scale = Vector3(bodySize, bodyH, bodySize)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bodyModel:SetMaterial(bodyMat)
    bodyModel.castShadows = true

    -- ③ 顶部小芽（罕见及以上才有）
    if rarity ~= "普通" then
        local sproutH = 0.025 * scale
        local sproutW = 0.02 * scale
        local sproutColor = Color(
            math.min(1.0, color.r * 0.6 + 0.3),
            math.min(1.0, color.g * 0.8 + 0.2),
            math.min(1.0, color.b * 0.4 + 0.1), 1.0
        )
        local sproutMat = Material:new()
        sproutMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        sproutMat:SetShaderParameter("MatDiffColor", Variant(sproutColor))
        sproutMat:SetShaderParameter("Roughness", Variant(0.5))

        local sproutNode = root:CreateChild("Sprout")
        sproutNode.position = Vector3(0, baseH + bodyH + sproutH * 0.5, 0)
        sproutNode.scale = Vector3(sproutW, sproutH, sproutW * 0.6)
        local sproutModel = sproutNode:CreateComponent("StaticModel")
        sproutModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        sproutModel:SetMaterial(sproutMat)
    end

    -- ④ 描边框（史诗/传奇才有）
    if params.outline then
        local outlineMat = CreateOutlineMaterial(color)
        local outlineSize = bodySize * 1.15
        local outlineH = bodyH * 1.05
        local outlineNode = root:CreateChild("Outline")
        outlineNode.position = Vector3(0, baseH + bodyH * 0.5, 0)
        outlineNode.scale = Vector3(outlineSize, outlineH, outlineSize)
        local outlineModel = outlineNode:CreateComponent("StaticModel")
        outlineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        outlineModel:SetMaterial(outlineMat)
        outlineModel.castShadows = false
    end

    print(string.format("[SeedVisual] 创建方块种子: %s [%s] scale=%.2f", plant.name, rarity, scale))
    return root
end

return SeedVisual
