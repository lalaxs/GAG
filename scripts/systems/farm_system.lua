-- ============================================================================
-- 农田系统 (Farm System)
-- Grow A Garden
-- ============================================================================
-- 管理地块创建、地块世界坐标、选中状态刷新、地块材质更新。
-- 后续等级解锁更多地块时，通过 ApplyUnlockedPlotCount 更新地块解锁状态。
-- ============================================================================

local FarmSystem = {}

local config_ = nil
local materials_ = nil

local function SetPlotMaterial(plot, material)
    if plot.soilModels ~= nil then
        for _, model in ipairs(plot.soilModels) do
            model:SetMaterial(material)
        end
    elseif plot.soilModel ~= nil then
        plot.soilModel:SetMaterial(material)
    end
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
        addPiece(prefix .. "CornerNE", "Models/Cylinder.mdl", Vector3(ox, y, oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerNW", "Models/Cylinder.mdl", Vector3(-ox, y, oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSE", "Models/Cylinder.mdl", Vector3(ox, y, -oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSW", "Models/Cylinder.mdl", Vector3(-ox, y, -oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
    end

    addRoundedRect("Base", -0.18, 0.48, 1.30, 1.30, 0.20, materials_.soilSide, false)
    addRoundedRect("GrassTop", 0.18, 0.24, 1.42, 1.42, 0.20, materials_.grassTop, false)
    addRoundedRect("DirtMound", 0.40, 0.20, 1.20, 1.20, 0.18, material, true)

    return moundModels
end

function FarmSystem.Init(config, materials)
    config_ = config
    materials_ = materials
end

function FarmSystem.PlotWorldPosition(index)
    local col = ((index - 1) % config_.GridCols) + 1
    local row = math.floor((index - 1) / config_.GridCols) + 1
    local startX = -((config_.GridCols - 1) * config_.PlotSpacing) * 0.5
    local startZ = -((config_.GridRows - 1) * config_.PlotSpacing) * 0.5
    return Vector3(startX + (col - 1) * config_.PlotSpacing, 0.42, startZ + (row - 1) * config_.PlotSpacing)
end

function FarmSystem.CreateFarm(scene, unlockedPlotCount)
    local plots = {}
    for i = 1, config_.GridCols * config_.GridRows do
        local plotNode = scene:CreateChild("Plot" .. i)
        plotNode.position = FarmSystem.PlotWorldPosition(i)
        plotNode.scale = Vector3(config_.PlotSize, 1.0, config_.PlotSize)
        local unlocked = i <= unlockedPlotCount
        local baseMaterial = unlocked and materials_.soil or materials_.soilLocked
        local models = CreateRoundedPlotSurface(plotNode, baseMaterial)

        local plot = {
            node = plotNode,
            soilModel = nil,
            soilModels = models,
            plants = {},
            plant = nil,
            selection = nil,
            unlocked = unlocked,
            lockNode = nil,
        }
        if not unlocked then
            plot.lockNode = nil
        end
        plots[i] = plot
        CreateSelectionFrame(plot)
    end
    return plots
end

function FarmSystem.RefreshSelection(plots, selectedPlot)
    for i, plot in ipairs(plots) do
        if plot.selection ~= nil then
            plot.selection.enabled = (i == selectedPlot)
        end
        if not plot.unlocked then
            SetPlotMaterial(plot, materials_.soilLocked)
        elseif i == selectedPlot then
            SetPlotMaterial(plot, materials_.soilSelected)
        else
            SetPlotMaterial(plot, materials_.soil)
        end
    end
end

function FarmSystem.ApplyUnlockedPlotCount(plots, unlockedPlotCount)
    for i, plot in ipairs(plots) do
        plot.unlocked = i <= unlockedPlotCount
    end
end

return FarmSystem
