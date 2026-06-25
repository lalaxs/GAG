-- ============================================================================
-- 模型预览系统 (Model Preview System)
-- Grow A Garden
-- ============================================================================
-- 创建独立 3D 展台，依次展示所有作物模型与种子包模型，便于截图制作图标。
-- ============================================================================

local ModelPreviewSystem = {}

local cfg_ = nil
local deps_ = {}
local scene_ = nil
local cameraNode_ = nil
local previewRoot_ = nil
local previewItemRoot_ = nil
local sunNode_ = nil
local sunEnabledBeforePreview_ = true
local items_ = {}
local index_ = 1
local open_ = false

local function MakeMutation()
    return {
        sizeScale = 1.0,
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
        color = nil,
        colorName = nil,
        specials = {},
    }
end

local function ColorFromBytes(color)
    if color == nil then return Color(0.8, 0.7, 0.45, 1.0) end
    return Color((color[1] or 220) / 255, (color[2] or 200) / 255, (color[3] or 150) / 255, (color[4] or 255) / 255)
end

local function CreateMaterial(name, color, roughness)
    return deps_.PlantVisual.CreateMaterial(name .. tostring(math.random(100000, 999999)), color, 0.0, roughness or 0.45)
end

local function ClearPreviewItem()
    if previewItemRoot_ ~= nil then
        previewItemRoot_:Remove()
        previewItemRoot_ = nil
    end
end

local function CreateSeedPackModel(parent, packCfg)
    local theme = ColorFromBytes(packCfg.themeColor)
    local mat = CreateMaterial("previewPack", theme, 0.34)
    local darkMat = CreateMaterial("previewPackDark", Color(theme.r * 0.55, theme.g * 0.55, theme.b * 0.55, 1.0), 0.55)
    local lightMat = CreateMaterial("previewPackLight", Color(math.min(theme.r * 1.25, 1.0), math.min(theme.g * 1.25, 1.0), math.min(theme.b * 1.25, 1.0), 1.0), 0.25)

    deps_.PlantVisual.AddModel(parent, "PackBody", "Models/Box.mdl", Vector3(0, 0.54, 0), Vector3(0.54, 0.72, 0.18), mat, false)
    deps_.PlantVisual.AddModel(parent, "PackTopFold", "Models/Box.mdl", Vector3(0, 0.96, -0.015), Vector3(0.58, 0.12, 0.20), darkMat, false)
    deps_.PlantVisual.AddModel(parent, "PackBottomFold", "Models/Box.mdl", Vector3(0, 0.12, -0.015), Vector3(0.58, 0.12, 0.20), darkMat, false)
    deps_.PlantVisual.AddModel(parent, "PackLabel", "Models/Box.mdl", Vector3(0, 0.56, -0.105), Vector3(0.34, 0.28, 0.018), lightMat, false)
    deps_.PlantVisual.AddModel(parent, "PackSeedIcon", "Models/Sphere.mdl", Vector3(0, 0.57, -0.125), Vector3(0.10, 0.14, 0.04), darkMat, false)
    deps_.PlantVisual.AddModel(parent, "PackGlowRing", "Models/Torus.mdl", Vector3(0, 0.56, -0.14), Vector3(0.22, 0.018, 0.22), lightMat, false)
end

local function BuildItems()
    items_ = {}
    for plantIndex, plant in ipairs(cfg_.PLANTS or {}) do
        table.insert(items_, {
            kind = "plant",
            id = plantIndex,
            name = plant.name,
            subtitle = string.format("作物 %02d / %s", plantIndex, plant.rarity or "普通"),
        })
    end
    for _, packCfg in pairs(cfg_.SEED_PACK_CONFIG or {}) do
        table.insert(items_, {
            kind = "pack",
            id = packCfg.packId,
            name = packCfg.packName,
            subtitle = "种子包 / " .. (packCfg.packRarity or "普通"),
        })
    end
    table.sort(items_, function(a, b)
        if a.kind ~= b.kind then return a.kind == "plant" end
        return tostring(a.id) < tostring(b.id)
    end)
end

local function EnsurePreviewRoot()
    if previewRoot_ ~= nil then return end
    previewRoot_ = scene_:CreateChild("ModelPreviewRoot")
    previewRoot_.position = Vector3(0, 0, -6)

    local bgMat = CreateMaterial("previewWhiteBackground", Color(1.0, 1.0, 1.0, 1.0), 0.85)
    deps_.PlantVisual.AddModel(previewRoot_, "PreviewWhiteBack", "Models/Box.mdl", Vector3(0, 2.25, 0.72), Vector3(5.2, 4.8, 0.05), bgMat, false)
end

local function SetScenePreviewLight(enabled)
    if scene_ == nil then return end
    if sunNode_ == nil and scene_.GetChild ~= nil then
        sunNode_ = scene_:GetChild("Sun", true)
    end
    if sunNode_ == nil then return end
    if not enabled then
        sunEnabledBeforePreview_ = sunNode_.enabled
        sunNode_.enabled = false
    else
        sunNode_.enabled = sunEnabledBeforePreview_
    end
end

local function ShowCurrentItem()
    ClearPreviewItem()
    if not open_ or #items_ == 0 then return end
    EnsurePreviewRoot()

    local item = items_[index_]
    previewItemRoot_ = previewRoot_:CreateChild("PreviewItem")
    previewItemRoot_.position = Vector3(0, 2.05, 0)
    previewItemRoot_.rotation = Quaternion(0, Vector3.UP)

    if item.kind == "plant" then
        local plant = cfg_.PLANTS[item.id]
        local mutation = MakeMutation()
        local material = deps_.PlantVisual.ResolvePlantMaterial(plant, mutation)
        deps_.PlantVisual.CreatePlantVisual(previewItemRoot_, plant, mutation, material)
    else
        local packCfg = cfg_.SEED_PACK_CONFIG[item.id]
        CreateSeedPackModel(previewItemRoot_, packCfg)
    end
end

local function ApplyPreviewCamera()
    if cameraNode_ == nil then return end
    cameraNode_.position = Vector3(0, 2.42, -8.05)
    cameraNode_:LookAt(Vector3(0, 2.18, -6.0))
end

function ModelPreviewSystem.Init(config, deps)
    cfg_ = config
    deps_ = deps or {}
    scene_ = deps_.scene
    cameraNode_ = deps_.cameraNode
    BuildItems()
end

function ModelPreviewSystem.Open()
    if scene_ == nil then return end
    open_ = true
    index_ = math.max(1, math.min(index_, #items_))
    EnsurePreviewRoot()
    if previewRoot_ ~= nil then previewRoot_.enabled = true end
    SetScenePreviewLight(false)
    ShowCurrentItem()
    ApplyPreviewCamera()
end

function ModelPreviewSystem.Close()
    open_ = false
    ClearPreviewItem()
    if previewRoot_ ~= nil then previewRoot_.enabled = false end
    SetScenePreviewLight(true)
end

function ModelPreviewSystem.IsOpen()
    return open_
end

function ModelPreviewSystem.Next()
    if #items_ == 0 then return end
    index_ = index_ + 1
    if index_ > #items_ then index_ = 1 end
    ShowCurrentItem()
    ApplyPreviewCamera()
end

function ModelPreviewSystem.Prev()
    if #items_ == 0 then return end
    index_ = index_ - 1
    if index_ < 1 then index_ = #items_ end
    ShowCurrentItem()
    ApplyPreviewCamera()
end

function ModelPreviewSystem.GetCurrentItem()
    if #items_ == 0 then return nil, 0, 0 end
    return items_[index_], index_, #items_
end

function ModelPreviewSystem.ShowKind(kind)
    for i, item in ipairs(items_) do
        if item.kind == kind then
            index_ = i
            ShowCurrentItem()
            ApplyPreviewCamera()
            return true
        end
    end
    return false
end

function ModelPreviewSystem.Update(dt)
    if not open_ then return end
    ApplyPreviewCamera()
    if previewItemRoot_ ~= nil then
        previewItemRoot_.rotation = Quaternion(0, Vector3.UP)
    end
end

return ModelPreviewSystem
