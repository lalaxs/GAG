-- ============================================================================
-- 作物系统 (Crop System)
-- Grow A Garden
-- ============================================================================
-- 管理播种、作物变异、散点位置、生长成熟、成熟特效与收获查询。
-- 预留农田道具加速和产出加成入口：plotModifiers。
-- ============================================================================

local CropSystem = {}

local cfg_ = nil
local deps_ = {}
local gameTime_ = 0
local plotModifiers_ = {}

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

local function GetPlotModifier(plotIndex)
    local modifier = plotModifiers_[plotIndex]
    if modifier == nil then
        modifier = {
            growTimeMultiplier = 1.0,
            yieldMultiplier = 1.0,
            weightBonus = 1.0,
            mutationBonus = 0.0,
        }
        plotModifiers_[plotIndex] = modifier
    end
    return modifier
end

local function GetWeightBonusForPlot(plotIndex)
    return GetPlotModifier(plotIndex).weightBonus or 1.0
end

local function RollMutation(plant, seedBuff, plotIndex)
    seedBuff = seedBuff or 0
    local modifier = GetPlotModifier(plotIndex)
    local mutationBonus = modifier.mutationBonus or 0
    local totalBuff = seedBuff + mutationBonus
    local mutation = {
        sizeScale = 1.0,
        sizePrefix = nil,
        colorMutation = nil,
        specials = {},
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
        seedBuff = seedBuff,
    }

    if math.random() < plant.volumeProb + totalBuff then
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

    if math.random() < plant.colorProb + totalBuff then
        mutation.colorMutation = RandItem(cfg_.COLOR_MUTATIONS)
    end

    for _, special in ipairs(cfg_.SPECIAL_MUTATIONS) do
        if math.random() < plant.specialProb + totalBuff then
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

local function ClampToPlot(localPos)
    local half = 0.46
    return Vector3(Clamp(localPos.x, -half, half), 0, Clamp(localPos.z, -half, half))
end

local function IsSeedPositionUsable(plot, localPos)
    if plot == nil or plot.plants == nil then return false end
    for _, crop in ipairs(plot.plants) do
        local dx = crop.localPos.x - localPos.x
        local dz = crop.localPos.z - localPos.z
        local minDist = math.max(cfg_.CONFIG.SeedMinDistance, ((crop.seedRadius or 0.12) + 0.07) * 0.72)
        if dx * dx + dz * dz < minDist * minDist then
            return false
        end
    end
    return true
end

local function ResolveSeedLocalPosition(plot, centerLocalPos)
    local basePos = ClampToPlot(centerLocalPos)
    if IsSeedPositionUsable(plot, basePos) then
        return basePos
    end

    for i = 1, 10 do
        local angle = (i - 1) * (math.pi * 2.0 / 10.0)
        local radius = cfg_.CONFIG.SeedMinDistance * (0.8 + i * 0.08)
        local candidate = ClampToPlot(basePos + Vector3(math.cos(angle) * radius, 0, math.sin(angle) * radius))
        if IsSeedPositionUsable(plot, candidate) then
            return candidate
        end
    end
    return basePos
end

local function CreateSeedVisual(root, plant, seedRadius)
    local naturalScale = (seedRadius / 0.09)
    return deps_.SeedVisual.Create(root, plant, naturalScale)
end

local function SetVisualScaleByProgress(plantData)
    local progress = plantData.elapsed / plantData.growTime
    progress = Clamp(progress, 0.0, 1.0)
    if progress < 0.18 then
        if plantData.visual ~= nil then
            plantData.visual.enabled = false
        end
        return
    end

    if not plantData.sprouted then
        plantData.sprouted = true
        plantData.visual = deps_.PlantVisual.CreatePlantVisual(plantData.root, plantData.config, plantData.mutation, plantData.material)
        if plantData.seedVisual ~= nil then
            plantData.seedVisual:Remove()
            plantData.seedVisual = nil
        end
        print("种子发芽，切换为作物模型: " .. plantData.name)
    end

    local growProgress = (progress - 0.18) / 0.82
    growProgress = Clamp(growProgress, 0.0, 1.0)
    local scale = (0.18 + 0.82 * growProgress) * plantData.mutation.sizeScale
    if plantData.visual ~= nil then
        plantData.visual.scale = Vector3(scale, scale, scale)
    end
end

local function RainbowColor(t)
    local r = 0.5 + 0.5 * math.sin(t)
    local g = 0.5 + 0.5 * math.sin(t + 2.094)
    local b = 0.5 + 0.5 * math.sin(t + 4.188)
    return Color(r, g, b, 1.0)
end

local function UpdatePlantEffects(plantData, dt)
    local mutation = plantData.mutation
    if deps_.PlantVisual.HasSpecial(mutation, "rainbow") then
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

function CropSystem.Init(config, deps)
    cfg_ = config
    deps_ = deps or {}
end

function CropSystem.SetPlotModifier(plotIndex, modifier)
    plotModifiers_[plotIndex] = modifier
end

function CropSystem.GetPlotModifier(plotIndex)
    return GetPlotModifier(plotIndex)
end

function CropSystem.ClampToPlot(localPos)
    return ClampToPlot(localPos)
end

function CropSystem.FindPlantAtLocalPosition(plot, localPos, matureOnly)
    if plot == nil or plot.plants == nil then return nil, nil end
    local bestIndex = nil
    local bestCrop = nil
    local bestDist = 9999
    for i, crop in ipairs(plot.plants) do
        if (not matureOnly) or crop.mature then
            local dx = crop.localPos.x - localPos.x
            local dz = crop.localPos.z - localPos.z
            local dist = dx * dx + dz * dz
            local radius = math.max(0.55, crop.pickRadius or 0.55)
            if dist <= radius * radius and dist < bestDist then
                bestDist = dist
                bestIndex = i
                bestCrop = crop
            end
        end
    end
    return bestCrop, bestIndex
end

function CropSystem.PlantSeedAt(plots, plotIndex, plantIndex, centerLocalPos)
    local plot = plots[plotIndex]
    if plot == nil or not plot.unlocked then return false end
    if plot.plants == nil then plot.plants = {} end
    if #plot.plants >= cfg_.CONFIG.MaxCropsPerPlot then
        if deps_.showToast then deps_.showToast("这块田地已经很满了") end
        return false
    end

    local plant = cfg_.PLANTS[plantIndex]
    local seedBag = deps_.InventorySystem.GetSeedBag()
    if seedBag[plantIndex] == nil or seedBag[plantIndex] <= 0 then
        return false
    end

    local localPos = ResolveSeedLocalPosition(plot, centerLocalPos)
    local seedBuff = deps_.InventorySystem.RemoveSeedFromBag(plantIndex)
    local mutation = RollMutation(plant, seedBuff, plotIndex)
    local naturalScale = 0.78 + math.random() * 0.62
    local weightScale, weightTier = RollCropWeightScale()
    local weightBonus = GetWeightBonusForPlot(plotIndex)
    local baseWeight = plant.baseWeight or 1.0
    local weight = baseWeight * weightScale * weightBonus
    local visualWeightScale = (weightScale * weightBonus) ^ 0.35
    mutation.sizeScale = mutation.sizeScale * naturalScale * visualWeightScale
    local seedRadius = (0.09 + math.random() * 0.055) * naturalScale
    local seedHeight = 0.010 + math.random() * 0.008
    local cropName = BuildCropName(plant, mutation)
    local root = plot.node:CreateChild("PlantRoot")
    root.position = Vector3(localPos.x, cfg_.CONFIG.SeedVisualY, localPos.z)
    root.rotation = Quaternion(math.random() * 360.0, Vector3.UP)

    local seedVisual = CreateSeedVisual(root, plant, seedRadius)
    local material = deps_.PlantVisual.ResolvePlantMaterial(plant, mutation)

    local weightRatio = weight / baseWeight
    local weightMultiplier = weightRatio * weightRatio
    local yieldMultiplier = GetPlotModifier(plotIndex).yieldMultiplier or 1.0
    local price = math.floor(plant.fruitPrice * yieldMultiplier * weightMultiplier * mutation.priceMultiplier + 0.5)
    local growTimeMultiplier = GetPlotModifier(plotIndex).growTimeMultiplier or 1.0
    local growTime = plant.growTime * mutation.timeMultiplier * growTimeMultiplier
    local crop = {
        config = plant,
        plantIndex = plantIndex,
        root = root,
        seedVisual = seedVisual,
        visual = nil,
        material = material,
        mutation = mutation,
        effectNodes = {},
        name = cropName,
        price = price,
        weight = weight,
        baseWeight = baseWeight,
        weightScale = weightScale,
        weightTier = weightTier,
        weightBonus = weightBonus,
        weightMultiplier = weightMultiplier,
        elapsed = 0,
        growTime = growTime,
        mature = false,
        sprouted = false,
        localPos = localPos,
        seedRadius = seedRadius,
        seedHeight = seedHeight,
        pickRadius = math.max(0.55, 0.42 * mutation.sizeScale),
    }
    table.insert(plot.plants, crop)
    deps_.InventorySystem.AddDailyProgress("plant", 1)
    print(string.format("散点播种: 田地%d %s 位置(%.2f, %.2f)，重量 %.2fkg[%s]，成熟时间 %.1fs，预估售价 %d", plotIndex, cropName, localPos.x, localPos.z, weight, weightTier, growTime, price))
    return true
end

function CropSystem.HarvestNearestMature(plots, plotIndex, localPos)
    local plot = plots[plotIndex]
    if plot == nil or plot.plants == nil then return false end
    local crop, cropIndex = nil, nil
    if localPos ~= nil then
        crop, cropIndex = CropSystem.FindPlantAtLocalPosition(plot, localPos, true)
    end
    if crop == nil then
        for i, item in ipairs(plot.plants) do
            if item.mature then
                crop = item
                cropIndex = i
                break
            end
        end
    end
    if crop == nil or cropIndex == nil then return false end
    deps_.InventorySystem.AddHarvestedCrop(crop)
    crop.root:Remove()
    table.remove(plot.plants, cropIndex)
    print("收获: " .. crop.name .. " 价值 " .. crop.price)
    return true
end

function CropSystem.CountPlotPlants(plot)
    if plot == nil or plot.plants == nil then return 0 end
    return #plot.plants
end

function CropSystem.CountMaturePlants(plot)
    if plot == nil or plot.plants == nil then return 0 end
    local count = 0
    for _, crop in ipairs(plot.plants) do
        if crop.mature then
            count = count + 1
        end
    end
    return count
end

function CropSystem.GetPlotText(plot)
    if plot == nil then
        return "未知田地"
    end
    if not plot.unlocked then
        return "未解锁"
    end
    local cropCount = CropSystem.CountPlotPlants(plot)
    if cropCount == 0 then
        return "空田地，可自由散点播种"
    end
    local matureCount = CropSystem.CountMaturePlants(plot)
    if matureCount > 0 then
        return string.format("%d株作物，%d株已成熟 | 点击成熟作物附近收获", cropCount, matureCount)
    end
    local minRemain = 9999
    for _, crop in ipairs(plot.plants) do
        minRemain = math.min(minRemain, math.max(0, crop.growTime - crop.elapsed))
    end
    return string.format("%d株生长中 | 最近 %.1fs 成熟", cropCount, minRemain)
end

function CropSystem.UpdatePlants(plots, dt)
    gameTime_ = gameTime_ + dt
    for _, plot in ipairs(plots) do
        if plot.plants ~= nil then
            for _, plantData in ipairs(plot.plants) do
                if not plantData.mature then
                    plantData.elapsed = plantData.elapsed + dt
                    SetVisualScaleByProgress(plantData)
                    if plantData.elapsed >= plantData.growTime then
                        plantData.mature = true
                        plantData.elapsed = plantData.growTime
                        if plantData.visual == nil then
                            plantData.visual = deps_.PlantVisual.CreatePlantVisual(plantData.root, plantData.config, plantData.mutation, plantData.material)
                        end
                        if plantData.seedVisual ~= nil then
                            plantData.seedVisual:Remove()
                            plantData.seedVisual = nil
                        end
                        plantData.root:Translate(Vector3(0, 0.06, 0))
                        deps_.PlantVisual.CreateSpecialEffects(plantData)
                        print("成熟: " .. plantData.name .. "，可收获")
                    end
                else
                    plantData.root:Rotate(Quaternion(12.0 * dt, Vector3.UP))
                end
                if plantData.sprouted or plantData.mature then
                    UpdatePlantEffects(plantData, dt)
                end
            end
        end
    end
end

return CropSystem
