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

local function GetWeightSightMultiplier(crop)
    local baseWeight = crop.baseWeight or (crop.config and crop.config.baseWeight) or 1.0
    if baseWeight <= 0 then return 1.0 end
    local ratio = (crop.weight or baseWeight) / baseWeight
    local multiplier = 1.0 + math.max(ratio - 1.0, -0.7) * 0.15
    return Clamp(multiplier, 0.9, 1.5)
end

local function GetMutationSightMultiplier(mutation)
    if mutation == nil then return 1.0 end
    local multipliers = {}
    if mutation.colorMutation ~= nil then
        table.insert(multipliers, mutation.colorMutation.sightMultiplier or mutation.colorMutation.multiplier or 1.0)
    end
    if mutation.specials ~= nil then
        for _, special in ipairs(mutation.specials) do
            table.insert(multipliers, special.sightMultiplier or special.multiplier or 1.0)
        end
    end
    if #multipliers == 0 then return 1.0 end
    table.sort(multipliers, function(a, b) return a > b end)
    local total = multipliers[1]
    if multipliers[2] ~= nil then
        total = total + multipliers[2] * 0.35
    end
    if multipliers[3] ~= nil then
        total = total + multipliers[3] * 0.20
    end
    for i = 4, #multipliers do
        total = total + multipliers[i] * 0.10
    end
    return math.max(1.0, total)
end

local function GetGrowthSightMultiplier(crop)
    local growthConfig = cfg_.SIGHT_GROWTH_MULTIPLIERS or {}
    if crop.mature then
        return growthConfig.mature or 1.0
    end
    local progress = 0
    if crop.growTime ~= nil and crop.growTime > 0 then
        progress = Clamp((crop.elapsed or 0) / crop.growTime, 0.0, 1.0)
    end
    if progress < 0.18 then
        return growthConfig.seed or 0.1
    elseif progress < 0.55 then
        return growthConfig.sprout or 0.3
    end
    return growthConfig.growing or 0.6
end

local function CalculateCropBaseSightValue(crop)
    local plant = crop.config or {}
    local baseSight = plant.sightBase or 1
    local sizeMultipliers = cfg_.SIGHT_SIZE_MULTIPLIERS or {}
    local sizeMultiplier = sizeMultipliers[crop.weightTier or "Normal"] or 1.0
    local value = baseSight * GetWeightSightMultiplier(crop) * sizeMultiplier * GetMutationSightMultiplier(crop.mutation)
    return math.max(1, math.floor(value + 0.5))
end

local function RandItem(list)
    return list[math.random(1, #list)]
end

local function RandomRange(minValue, maxValue)
    return minValue + math.random() * (maxValue - minValue)
end

local function GetCropScaleRules()
    return cfg_.CROP_SCALE_RULES or {}
end

local function ClampCropWeightScale(weightScale)
    local rules = GetCropScaleRules()
    local minScale = rules.WeightScaleMin or 0.20
    local maxScale = rules.WeightScaleMax or 3.50
    return Clamp(weightScale, minScale, maxScale)
end

local function GetWeightMultiplierFromRatio(weightRatio)
    local rules = GetCropScaleRules()
    local minMultiplier = rules.PriceMultiplierMin or 0.04
    local maxMultiplier = rules.PriceMultiplierMax or 12.0
    return math.min(math.max(weightRatio * weightRatio, minMultiplier), maxMultiplier)
end

local function RollCropWeightScale()
    local rules = GetCropScaleRules()
    local minScale = rules.WeightScaleMin or 0.20
    local lightMax = rules.LightWeightScaleMax or 0.90
    local normalMax = rules.NormalWeightScaleMax or 1.20
    local largeMax = rules.LargeWeightScaleMax or 2.00
    local maxScale = rules.WeightScaleMax or 3.50
    local r = math.random()
    if r < 0.34 then
        return RandomRange(minScale, lightMax), "Light"
    elseif r < 0.94 then
        return RandomRange(lightMax, normalMax), "Normal"
    elseif r < 0.99 then
        return RandomRange(normalMax, largeMax), "Large"
    end
    return RandomRange(largeMax, maxScale), "Giant"
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

--- 获取天赋系统加成（如果 TalentSystem 已注入）
local function GetTalentBonus(key)
    if deps_.TalentSystem and deps_.TalentSystem.GetBonus then
        return deps_.TalentSystem.GetBonus(key)
    end
    return 0
end

local function GetWeightBonusForPlot(plotIndex)
    return GetPlotModifier(plotIndex).weightBonus or 1.0
end

local function IsSpecialAllowedForNormalRoll(special)
    if special == nil then return false end
    return special.exclusiveActivity == nil
end

local function RandNormalSpecialMutation()
    local pool = {}
    for _, special in ipairs(cfg_.SPECIAL_MUTATIONS or {}) do
        if IsSpecialAllowedForNormalRoll(special) then
            table.insert(pool, special)
        end
    end
    return RandItem(pool)
end

local function RollMutation(plant, seedBuff, plotIndex)
    seedBuff = seedBuff or 0
    local modifier = GetPlotModifier(plotIndex)
    local mutationBonus = (modifier.mutationBonus or 0) + GetTalentBonus("mutationBonus")
    local totalBuff = seedBuff + mutationBonus
    local chanceMultiplier = 1.0 + totalBuff
    local colorChance = math.min((plant.colorProb or 0.09) * chanceMultiplier, 0.35)
    local specialChance = math.min((plant.specialProb or 0.025) * chanceMultiplier, 0.16)
    local doubleChance = math.min(0.005 * chanceMultiplier, 0.04)
    local mutation = {
        sizeScale = 1.0,
        sizePrefix = nil,
        colorMutation = nil,
        specials = {},
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
        seedBuff = seedBuff,
    }

    if math.random() <= colorChance then
        mutation.colorMutation = RandItem(cfg_.COLOR_MUTATIONS)
        mutation.priceMultiplier = mutation.priceMultiplier * (mutation.colorMutation.multiplier or 1.3)
        mutation.timeMultiplier = mutation.timeMultiplier * (mutation.colorMutation.timeMultiplier or 1.03)
    end

    if math.random() <= specialChance then
        local special = RandNormalSpecialMutation()
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 2.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.05)
        end
    end

    if #mutation.specials == 1 and math.random() <= doubleChance then
        local special = RandNormalSpecialMutation()
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 2.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.05)
        end
    end

    if deps_.ActivitySystem and deps_.ActivitySystem.ApplyPlantingMutation then
        deps_.ActivitySystem.ApplyPlantingMutation(plant, mutation, mutationBonus)
    end

    mutation.priceMultiplier = math.min(mutation.priceMultiplier, 80.0)
    mutation.timeMultiplier = math.min(mutation.timeMultiplier, 2.7)

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

local function CalculateCropPrice(plant, weightMultiplier, mutation, yieldMultiplier, sellBonus)
    local priceBase = math.max(1, tonumber(plant.seedPrice or plant.fruitPrice or 1) or 1)
    local mutationMultiplier = mutation and mutation.priceMultiplier or 1.0
    local rawPrice = priceBase * (yieldMultiplier or 1.0) * (weightMultiplier or 1.0) * mutationMultiplier * (sellBonus or 1.0)
    return math.floor(math.min(rawPrice, priceBase * 200) + 0.5)
end

local function RecalculateCropPrice(plant, weight, baseWeight, mutation, yieldMultiplier, sellBonus)
    local safeBaseWeight = math.max(0.001, tonumber(baseWeight or plant.baseWeight or 1.0) or 1.0)
    local safeWeight = tonumber(weight or safeBaseWeight) or safeBaseWeight
    local weightRatio = safeWeight / safeBaseWeight
    local weightMultiplier = GetWeightMultiplierFromRatio(weightRatio)
    return CalculateCropPrice(plant, weightMultiplier, mutation, yieldMultiplier, sellBonus), weightMultiplier
end

local function ClampToPlot(localPos)
    local half = cfg_.CONFIG.PlantableHalf or 0.60
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
    if not IsSeedPositionUsable(plot, basePos) then
        return nil
    end
    return basePos
end

local function CreateSeedVisual(root, plant, seedRadius)
    local naturalScale = (seedRadius / 0.09)
    return deps_.SeedVisual.Create(root, plant, naturalScale)
end

local SetVisualScaleByProgress

local function CreateCropFromSave(plot, data)
    if plot == nil or type(data) ~= "table" then return nil end
    local plantIndex = tonumber(data.plantIndex or 0)
    local plant = cfg_.PLANTS[plantIndex]
    if plant == nil then return nil end

    local localPosData = data.localPos or {}
    local localPos = Vector3(tonumber(localPosData.x or 0) or 0, 0, tonumber(localPosData.z or 0) or 0)
    local mutation = data.mutation or {
        sizeScale = 1.0,
        sizePrefix = nil,
        colorMutation = nil,
        specials = {},
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
        seedBuff = 0,
    }
    mutation.specials = mutation.specials or {}
    mutation.priceMultiplier = mutation.priceMultiplier or 1.0
    mutation.timeMultiplier = mutation.timeMultiplier or 1.0
    mutation.sizeScale = mutation.sizeScale or 1.0

    local cropPrice, cropWeightMultiplier = RecalculateCropPrice(
        plant,
        tonumber(data.weight or plant.baseWeight or 1.0) or 1.0,
        tonumber(data.baseWeight or plant.baseWeight or 1.0) or 1.0,
        mutation,
        1.0,
        1.0
    )

    local root = plot.node:CreateChild("PlantRoot")
    root.position = Vector3(localPos.x, cfg_.CONFIG.SeedVisualY, localPos.z)
    root.rotation = Quaternion(tonumber(data.rotationYaw or 0) or 0, Vector3.UP)

    local material = deps_.PlantVisual.ResolvePlantMaterial(plant, mutation)
    local crop = {
        config = plant,
        cropId = data.cropId,
        serverCropId = data.serverCropId or data.cropId,
        plantedAt = data.plantedAt,
        matureAt = data.matureAt,
        stolen = data.stolen == true,
        harvested = data.harvested == true,
        plantIndex = plantIndex,
        root = root,
        seedVisual = nil,
        visual = nil,
        material = material,
        mutation = mutation,
        effectNodes = {},
        name = data.name or BuildCropName(plant, mutation),
        price = cropPrice,
        sightValue = tonumber(data.sightValue or 0) or 0,
        weight = tonumber(data.weight or plant.baseWeight or 1.0) or 1.0,
        baseWeight = tonumber(data.baseWeight or plant.baseWeight or 1.0) or 1.0,
        weightScale = tonumber(data.weightScale or 1.0) or 1.0,
        weightTier = data.weightTier or "Normal",
        weightBonus = tonumber(data.weightBonus or 1.0) or 1.0,
        weightMultiplier = cropWeightMultiplier,
        elapsed = tonumber(data.elapsed or 0) or 0,
        growTime = math.max(0.1, tonumber(data.growTime or plant.growTime or 1.0) or 1.0),
        mature = data.mature == true,
        sprouted = data.sprouted == true,
        localPos = localPos,
        seedRadius = tonumber(data.seedRadius or 0.09) or 0.09,
        seedHeight = tonumber(data.seedHeight or 0.015) or 0.015,
        pickRadius = tonumber(data.pickRadius or 0.55) or 0.55,
    }
    if crop.sightValue <= 0 then
        crop.sightValue = CalculateCropBaseSightValue(crop)
    end

    if crop.mature or crop.sprouted or crop.elapsed >= crop.growTime * 0.18 then
        crop.sprouted = true
        crop.visual = deps_.PlantVisual.CreatePlantVisual(root, plant, mutation, material)
        SetVisualScaleByProgress(crop)
        if crop.mature then
            crop.elapsed = crop.growTime
            deps_.PlantVisual.CreateSpecialEffects(crop)
        end
    else
        crop.seedVisual = CreateSeedVisual(root, plant, crop.seedRadius)
    end

    return crop
end

SetVisualScaleByProgress = function(plantData)
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

function CropSystem.ClearPlots(plots)
    if plots == nil then return end
    for _, plot in ipairs(plots) do
        if plot.plants ~= nil then
            for _, crop in ipairs(plot.plants) do
                if crop.root ~= nil then crop.root:Remove() end
            end
        end
        plot.plants = {}
    end
end

function CropSystem.RestorePlotsFromSave(plots, data)
    if plots == nil or type(data) ~= "table" then return end
    local restoredCount = 0
    for plotKey, plotData in pairs(data) do
        local plotIndex = tonumber(plotKey) or tonumber(plotData and plotData.plotIndex)
        if plotIndex ~= nil then plotIndex = math.max(1, math.floor(plotIndex)) end
        local plot = plotIndex ~= nil and plots[plotIndex] or nil
        if plot ~= nil then
            if plot.plants ~= nil then
                for _, crop in ipairs(plot.plants) do
                    if crop.root ~= nil then crop.root:Remove() end
                end
            end
            plot.plants = {}
            local savedPlants = plotData.plants or {}
            for _, cropData in ipairs(savedPlants) do
                local crop = CreateCropFromSave(plot, cropData)
                if crop ~= nil then
                    table.insert(plot.plants, crop)
                    restoredCount = restoredCount + 1
                end
            end
        else
            print(string.format("[存档恢复] 忽略无法匹配的地块 plotKey=%s plotIndex=%s", tostring(plotKey), tostring(plotIndex)))
        end
    end
    print(string.format("[存档恢复] 已恢复作物数量=%d", restoredCount))
end

function CropSystem.PlantCropFromServer(plots, plotIndex, cropData)
    local plot = plots[plotIndex]
    if plot == nil or not plot.unlocked then return false end
    if plot.plants == nil then plot.plants = {} end
    if #plot.plants >= cfg_.CONFIG.MaxCropsPerPlot then return false end
    local crop = CreateCropFromSave(plot, cropData)
    if crop == nil then return false end
    table.insert(plot.plants, crop)
    print(string.format("服务端播种: 田地%d %s cropId=%s", plotIndex, tostring(crop.name), tostring(crop.cropId)))
    return true
end

function CropSystem.GetPlotsSaveData(plots)
    local result = {}
    if plots == nil then return result end
    for plotIndex, plot in ipairs(plots) do
        local savedPlants = {}
        for _, crop in ipairs(plot.plants or {}) do
            table.insert(savedPlants, {
                plantIndex = crop.plantIndex,
                cropId = crop.cropId,
                serverCropId = crop.serverCropId,
                plantedAt = crop.plantedAt,
                matureAt = crop.matureAt,
                stolen = crop.stolen,
                harvested = crop.harvested,
                name = crop.name,
                price = crop.price,
                sightValue = crop.sightValue,
                weight = crop.weight,
                baseWeight = crop.baseWeight,
                weightScale = crop.weightScale,
                weightTier = crop.weightTier,
                weightBonus = crop.weightBonus,
                weightMultiplier = crop.weightMultiplier,
                elapsed = crop.elapsed,
                growTime = crop.growTime,
                mature = crop.mature,
                sprouted = crop.sprouted,
                localPos = crop.localPos and { x = crop.localPos.x, z = crop.localPos.z } or { x = 0, z = 0 },
                seedRadius = crop.seedRadius,
                seedHeight = crop.seedHeight,
                pickRadius = crop.pickRadius,
                mutation = crop.mutation,
            })
        end
        result[plotIndex] = {
            plants = savedPlants,
        }
    end
    return result
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
        local node = effect.node or effect
        local interval = effect.updateInterval or 0.045
        effect.updateTimer = (effect.updateTimer or 0) + dt
        if effect.updateTimer >= interval then
            local step = effect.updateTimer
            effect.updateTimer = effect.updateTimer - interval
            local particles = effect.particles
            if particles ~= nil then
                node.position = Vector3(0, 0, 0)
                for _, particle in ipairs(particles) do
                    local t = gameTime_ + particle.phase
                    if particle.kind == "billboardSmoke" or particle.kind == "billboardSpark" then
                        local billboard = particle.billboardSet:GetBillboard(particle.index)
                        local progress = (t * particle.riseSpeed) % 1.0
                        local sway = math.sin(t * particle.swaySpeed) * particle.swayAmp
                        local drift = particle.drift * progress
                        local sizePulse = 1.0 + math.sin(t * particle.pulseSpeed) * particle.pulseAmp
                        local alphaScale = 1.0
                        local offset = Vector3(sway, progress * particle.riseHeight, -sway * 0.5)
                        local mode = particle.mode or "rise"
                        if particle.kind == "billboardSmoke" then
                            sizePulse = (0.65 + progress * 0.75) * sizePulse
                            alphaScale = math.max(0.0, 1.0 - progress * 0.72)
                        elseif mode == "fall" then
                            offset = Vector3(sway * 0.35, (1.0 - progress) * particle.riseHeight * 0.35, -sway * 0.2)
                            alphaScale = 0.38 + math.sin(progress * math.pi) * 0.52
                            sizePulse = sizePulse * (0.86 + progress * 0.2)
                        elseif mode == "twinkle" then
                            local flash = math.max(0.0, math.sin(t * particle.pulseSpeed * 3.2))
                            offset = Vector3(sway * 0.18, flash * 0.045, -sway * 0.12)
                            alphaScale = 0.18 + flash * 0.82
                            sizePulse = 0.72 + flash * 0.72
                        elseif mode == "cloudDrift" then
                            local slowT = t * 0.5
                            local driftX = math.sin(slowT * particle.swaySpeed + particle.phase) * particle.swayAmp * 2.8
                            local driftZ = math.cos(slowT * (particle.swaySpeed * 0.82) + particle.phase * 0.7) * particle.swayAmp * 2.1
                            local floatY = math.sin(slowT * particle.pulseSpeed * 0.9 + particle.phase) * 0.055
                            local breathe = 0.5 + 0.5 * math.sin(slowT * particle.pulseSpeed * 1.25 + particle.phase * 0.6)
                            offset = Vector3(driftX, floatY, driftZ)
                            alphaScale = 0.34 + breathe * 0.42
                            sizePulse = 0.72 + breathe * 0.56
                        elseif mode == "steam" then
                            local fade = math.max(0.0, 1.0 - progress)
                            local curl = math.sin(t * particle.swaySpeed * 1.7 + progress * 4.0) * particle.swayAmp * 1.4
                            offset = Vector3(sway * 0.42 + curl, progress * particle.riseHeight * 1.22, -sway * 0.24 + curl * 0.35)
                            alphaScale = fade * fade
                            sizePulse = 0.16 + fade * 0.92
                        elseif mode == "suck" then
                            local inward = 1.0 - progress * 0.72
                            billboard.position = Vector3(particle.basePosition.x * inward, particle.basePosition.y + sway * 0.18, particle.basePosition.z * inward)
                            alphaScale = math.max(0.18, 0.78 - progress * 0.45)
                            sizePulse = sizePulse * (1.0 - progress * 0.35)
                        elseif mode == "orbit" then
                            local angle = particle.angle + gameTime_ * 0.75
                            local radius = particle.orbitRadius * (0.9 + math.sin(t * 1.2) * 0.06)
                            local jump = math.sin(t * particle.swaySpeed * 1.8) * particle.swayAmp * 2.4
                            billboard.position = Vector3(math.cos(angle) * radius, particle.basePosition.y + jump, math.sin(angle) * radius)
                            alphaScale = 0.42 + math.max(0.0, math.sin(t * particle.pulseSpeed)) * 0.46
                            sizePulse = sizePulse * (0.9 + math.max(0.0, math.sin(t * particle.pulseSpeed * 1.35)) * 0.32)
                        else
                            alphaScale = 0.38 + math.sin(progress * math.pi) * 0.48
                        end
                        if mode ~= "suck" and mode ~= "orbit" then
                            if mode == "cloudDrift" then
                                billboard.position = particle.basePosition + particle.drift * (math.sin(t * 0.18 + particle.phase) * 0.5 + 0.5) + offset
                            else
                                billboard.position = particle.basePosition + drift + offset
                            end
                        end
                        billboard.size = Vector2(particle.baseSize * sizePulse, particle.baseSize * sizePulse)
                        local spinScale = mode == "cloudDrift" and 0.25 or 1.0
                        billboard.rotation = billboard.rotation + particle.spinSpeed * spinScale * step
                        billboard.color = Color(particle.baseColor.r, particle.baseColor.g, particle.baseColor.b, particle.baseColor.a * alphaScale)
                    elseif particle.kind == "smoke" then
                        local progress = (t * particle.riseSpeed) % 1.0
                        local fadeScale = 0.72 + progress * 0.62
                        local sway = math.sin(t * particle.swaySpeed) * particle.swayAmp
                        local drift = particle.drift * progress
                        particle.node.position = particle.basePosition + drift + Vector3(sway, progress * particle.riseHeight, -sway * 0.6)
                        particle.node.scale = particle.baseScale * (fadeScale + math.sin(t * particle.pulseSpeed) * particle.pulseAmp)
                        particle.node:Rotate(Quaternion(particle.spinSpeed * step, Vector3.UP))
                    else
                        local bob = math.sin(t * particle.bobSpeed) * particle.bobAmp
                        local sway = math.sin(t * particle.swaySpeed) * particle.swayAmp
                        local pulse = 1.0 + math.sin(t * particle.pulseSpeed) * particle.pulseAmp
                        local mode = particle.mode or "float"

                        if mode == "orbit" or mode == "pollenOrbit" then
                            local angle = particle.angle + gameTime_ * 0.75
                            local radius = particle.orbitRadius * (0.92 + math.sin(t * 1.4) * 0.06)
                            local jump = math.sin(t * particle.bobSpeed * 1.45) * particle.bobAmp * 1.35
                            if mode == "pollenOrbit" then
                                jump = jump + math.max(0.0, math.sin(t * particle.bobSpeed * 1.9)) * particle.bobAmp * 1.85
                                pulse = pulse * (0.86 + math.max(0.0, math.sin(t * particle.pulseSpeed * 1.45)) * 0.34)
                            else
                                pulse = pulse * (0.9 + math.max(0.0, math.sin(t * particle.pulseSpeed * 1.25)) * 0.22)
                            end
                            particle.node.position = Vector3(math.cos(angle) * radius, particle.baseY + jump, math.sin(angle) * radius)
                        elseif mode == "rise" then
                            local progress = (t * particle.riseSpeed) % 1.0
                            local fadePulse = 0.72 + math.sin(progress * math.pi) * 0.42
                            local side = math.sin(t * particle.swaySpeed) * particle.swayAmp * 1.6
                            particle.node.position = particle.basePosition + Vector3(side, progress * particle.riseHeight, -side * 0.35)
                            pulse = pulse * fadePulse
                        elseif mode == "fall" then
                            local progress = (t * particle.riseSpeed) % 1.0
                            local side = math.sin(t * particle.swaySpeed) * particle.swayAmp * 0.8
                            particle.node.position = particle.basePosition + Vector3(side, (1.0 - progress) * particle.riseHeight * 0.42, -side * 0.25)
                            pulse = pulse * (0.78 + progress * 0.25)
                        elseif mode == "suck" then
                            local progress = (t * particle.riseSpeed) % 1.0
                            local inward = 1.0 - progress * 0.72
                            particle.node.position = Vector3(particle.basePosition.x * inward, particle.basePosition.y + bob * 0.6, particle.basePosition.z * inward)
                            pulse = pulse * (1.18 - progress * 0.42)
                        elseif mode == "twinkle" then
                            local snap = math.sin(t * particle.pulseSpeed * 2.6)
                            local jump = math.max(0.0, snap) * 0.055
                            particle.node.position = particle.basePosition + Vector3(sway * 0.35, jump + bob * 0.35, -sway * 0.2)
                            pulse = 0.62 + math.max(0.0, snap) * 0.92
                        elseif mode == "stream" then
                            local progress = (t * particle.riseSpeed * 0.72) % 1.0
                            local side = math.sin(t * particle.swaySpeed) * particle.swayAmp
                            particle.node.position = particle.basePosition + Vector3(side + progress * 0.08, progress * particle.riseHeight * 0.38, -side * 0.55)
                            pulse = pulse * (0.86 + progress * 0.18)
                        elseif mode == "drift" then
                            local driftX = math.sin(t * 0.55) * particle.swayAmp * 3.0
                            local driftZ = math.cos(t * 0.48) * particle.swayAmp * 2.4
                            particle.node.position = particle.basePosition + Vector3(driftX, bob * 0.45, driftZ)
                            pulse = pulse * 0.82
                        elseif mode == "drip" then
                            local progress = (t * particle.riseSpeed * 0.82) % 1.0
                            local drop = -progress * particle.riseHeight * 0.38
                            particle.node.position = particle.basePosition + Vector3(sway * 0.3, drop, -sway * 0.2)
                            pulse = pulse * (0.9 + progress * 0.32)
                        elseif mode == "pulse" then
                            particle.node.position = particle.basePosition + Vector3(sway * 0.25, bob * 0.45, -sway * 0.2)
                            pulse = 0.82 + math.max(0.0, math.sin(t * particle.pulseSpeed)) * 0.46
                        elseif mode == "burst" then
                            local progress = (t * particle.burstSpeed) % 1.0
                            local burst = math.sin(progress * math.pi)
                            local outward = 0.55 + burst * 0.72
                            particle.node.position = Vector3(particle.basePosition.x * outward, particle.basePosition.y + burst * 0.12, particle.basePosition.z * outward)
                            pulse = 0.55 + burst * 1.05
                        elseif mode == "spiral" then
                            local progress = (t * particle.riseSpeed) % 1.0
                            local angle = particle.angle + gameTime_ * particle.spiralSpeed + progress * 2.4
                            local radius = particle.orbitRadius * (0.45 + progress * 0.95)
                            particle.node.position = Vector3(math.cos(angle) * radius, particle.baseY + progress * particle.riseHeight * 0.85, math.sin(angle) * radius)
                            pulse = pulse * (0.75 + progress * 0.38)
                        elseif mode == "snap" then
                            local snap = math.max(0.0, math.sin(t * particle.pulseSpeed * 3.8 + particle.snapOffset))
                            local side = snap * 0.08
                            particle.node.position = particle.basePosition + Vector3(sway + side, bob * 0.25 + snap * 0.08, -sway * 0.25)
                            pulse = 0.45 + snap * 1.25
                        elseif mode == "beam" then
                            local progress = (t * particle.riseSpeed * 0.56) % 1.0
                            particle.node.position = particle.basePosition + Vector3(0, progress * particle.riseHeight * 1.15, 0)
                            pulse = 0.65 + math.sin(progress * math.pi) * 0.7
                        else
                            particle.node.position = particle.basePosition + Vector3(sway, bob, -sway * 0.55)
                        end

                        particle.node.scale = particle.baseScale * pulse
                        particle.node:Rotate(Quaternion(particle.spinSpeed * step, Vector3.UP))
                    end
                end
                if particles[1] ~= nil and particles[1].billboardSet ~= nil then
                    particles[1].billboardSet:Commit()
                end
            else
                local spinSpeed = effect.spinSpeed or (25 + i * 18)
                local bobSpeed = effect.bobSpeed or (1.4 + i * 0.17)
                local bobAmp = effect.bobAmp or 0.035
                node:Rotate(Quaternion(spinSpeed * step, Vector3.UP))
                local bob = math.sin(gameTime_ * bobSpeed + i * 0.6) * bobAmp
                local basePosition = effect.basePosition or Vector3(0, 0, 0)
                node.position = basePosition + Vector3(0, bob, 0)
                if effect.baseScale ~= nil and effect.pulseSpeed ~= nil and effect.pulseSpeed > 0 then
                    local pulse = 1.0 + math.sin(gameTime_ * effect.pulseSpeed + i * 0.9) * (effect.pulseAmp or 0.0)
                    node.scale = effect.baseScale * pulse
                end
            end
        end
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

function CropSystem.PlantSeedAt(plots, plotIndex, plantIndex, centerLocalPos, options)
    options = options or {}
    local plot = plots[plotIndex]
    if plot == nil or not plot.unlocked then return false end
    if plot.plants == nil then plot.plants = {} end
    if #plot.plants >= cfg_.CONFIG.MaxCropsPerPlot then
        if deps_.showToast then deps_.showToast("这块田地已经很满了") end
        return false
    end

    local plant = cfg_.PLANTS[plantIndex]
    local seedBag = deps_.InventorySystem.GetSeedBag()
    if options.skipSeedConsume ~= true and (seedBag[plantIndex] == nil or seedBag[plantIndex] <= 0) then
        return false
    end

    local localPos = ResolveSeedLocalPosition(plot, centerLocalPos)
    if localPos == nil then
        return false, "occupied"
    end

    local seedBuff = options.skipSeedConsume == true and (tonumber(options.seedBuff or 0) or 0) or deps_.InventorySystem.RemoveSeedFromBag(plantIndex)
    local mutation = RollMutation(plant, seedBuff, plotIndex)
    local scaleRules = GetCropScaleRules()
    local naturalMin = scaleRules.NaturalScaleMin or 0.54
    local naturalMax = scaleRules.NaturalScaleMax or 1.38
    local naturalScale = RandomRange(naturalMin, naturalMax)
    local weightScale, weightTier = RollCropWeightScale()
    local weightBonus = GetWeightBonusForPlot(plotIndex)
    local baseWeight = plant.baseWeight or 1.0
    local weightRatio = ClampCropWeightScale(weightScale * weightBonus)
    local weight = baseWeight * weightRatio
    local visualWeightScale = weightRatio ^ (scaleRules.VisualWeightExponent or 0.62)
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
    local weightMultiplier = GetWeightMultiplierFromRatio(weightRatio)
    local yieldMultiplier = GetPlotModifier(plotIndex).yieldMultiplier or 1.0
    local sellBonus = 1.0 + GetTalentBonus("sellBonus")
    local price = CalculateCropPrice(plant, weightMultiplier, mutation, yieldMultiplier, sellBonus)
    local growTimeMultiplier = GetPlotModifier(plotIndex).growTimeMultiplier or 1.0
    local growSpeedReduction = 1.0 - math.min(GetTalentBonus("growSpeed"), 0.75)
    local growTime = plant.growTime * mutation.timeMultiplier * growTimeMultiplier * growSpeedReduction
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
        sightValue = 0,
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
    crop.sightValue = CalculateCropBaseSightValue(crop)
    table.insert(plot.plants, crop)
    deps_.InventorySystem.AddDailyProgress("plant", 1)
    print(string.format("精确播种: 田地%d %s 位置(%.2f, %.2f)，重量 %.2fkg[%s]，成熟时间 %.1fs，预估售价 %d，成熟观光值 %d", plotIndex, cropName, localPos.x, localPos.z, weight, weightTier, growTime, price, crop.sightValue))
    return true
end

function CropSystem.HarvestNearestMature(plots, plotIndex, localPos, options)
    options = options or {}
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
    if options.skipAddHarvested ~= true and not deps_.InventorySystem.AddHarvestedCrop(crop) then
        return false
    end
    crop.root:Remove()
    table.remove(plot.plants, cropIndex)
    print("收获: " .. crop.name .. " 价值 " .. crop.price)

    local gainedExp = 0
    local rarity = (crop.config and crop.config.rarity) or crop.rarity or "普通"
    -- 天赋系统：收获获得经验值
    if deps_.TalentSystem and deps_.TalentSystem.AddHarvestExp then
        local priceMult = crop.mutation and crop.mutation.priceMultiplier or 1.0
        gainedExp = deps_.TalentSystem.AddHarvestExp(rarity, priceMult) or 0
    end

    if options.skipAddHarvested ~= true then
        -- 天赋系统：收获掉落种子包
        local dropRateBonus = GetTalentBonus("dropRate")
        local packQuality = GetTalentBonus("packQuality")
        local droppedPack = deps_.InventorySystem.RollHarvestDrop(rarity, dropRateBonus, packQuality)
        if droppedPack ~= nil and deps_.showToast then
            local packCfg = cfg_.SEED_PACK_CONFIG[droppedPack]
            local packName = packCfg and packCfg.packName or droppedPack
            deps_.showToast("掉落: " .. packName)
        end
    end

    if deps_.ActivitySystem and deps_.ActivitySystem.OnCropHarvested then
        deps_.ActivitySystem.OnCropHarvested(crop)
    end

    if options.skipAddHarvested ~= true then
        -- 收藏成就检查（只发放种子包奖励）
        deps_.InventorySystem.CheckSilverPackRewardsEnhanced()
    end

    return true, {
        name = crop.name,
        exp = gainedExp,
    }
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

function CropSystem.GetCropSightValue(crop, includeGrowth)
    if crop == nil then return 0 end
    local matureSightValue = crop.sightValue or CalculateCropBaseSightValue(crop)
    if includeGrowth == false then
        return matureSightValue
    end
    return math.max(1, math.floor(matureSightValue * GetGrowthSightMultiplier(crop) + 0.5))
end

function CropSystem.CalculateTotalSightValue(plots)
    local total = 0
    if plots == nil then return 0 end
    for _, plot in ipairs(plots) do
        if plot.unlocked and plot.plants ~= nil then
            for _, crop in ipairs(plot.plants) do
                total = total + CropSystem.GetCropSightValue(crop, true)
            end
        end
    end
    return total
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

function CropSystem.UpdatePlants(plots, dt, rotateMaturePlants)
    local maturedThisFrame = false
    gameTime_ = gameTime_ + dt
    for _, plot in ipairs(plots) do
        if plot.plants ~= nil then
            for _, plantData in ipairs(plot.plants) do
                if not plantData.mature then
                    plantData.elapsed = plantData.elapsed + dt
                    SetVisualScaleByProgress(plantData)
                    if plantData.elapsed >= plantData.growTime then
                        plantData.mature = true
                        maturedThisFrame = true
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
                elseif rotateMaturePlants == true then
                    plantData.root:Rotate(Quaternion(12.0 * dt, Vector3.UP))
                end
                if plantData.sprouted or plantData.mature then
                    UpdatePlantEffects(plantData, dt)
                end
            end
        end
    end
    return maturedThisFrame
end

return CropSystem
