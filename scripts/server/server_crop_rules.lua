-- ============================================================================
-- 服务端作物权威规则
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的种子包随机、收获掉落、作物权重/变异/价格/权威作物构建逻辑。
-- 必须保持 math.random() 调用顺序不变。
-- ============================================================================

local ServerCropRules = {}

local deps_ = {}

function ServerCropRules.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function NormalizePlantIndex(value)
    return deps_.NormalizePlantIndex(value)
end

local function NormalizePlotIndex(value)
    return deps_.NormalizePlotIndex(value)
end

local function NormalizeLocalPos(value)
    return deps_.NormalizeLocalPos(value)
end

local function RollWeighted(pool)
    return deps_.RollWeighted(pool)
end

local function RandomRange(minValue, maxValue)
    return deps_.RandomRange(minValue, maxValue)
end

local function RandItem(list)
    return deps_.RandItem(list)
end

local function ClampValue(value, minValue, maxValue)
    return deps_.ClampValue(value, minValue, maxValue)
end

function ServerCropRules.IsLimitedSeed(seedId)
    local plant = deps_.GameConfig.PLANTS[seedId]
    return plant ~= nil and (plant.limited == true or plant.activityTag ~= nil)
end

function ServerCropRules.GetPackRollPool(packCfg)
    if packCfg.allowLimitedSeeds == true then return packCfg.weightPool end
    local filtered = {}
    for _, item in ipairs(packCfg.weightPool or {}) do
        if not ServerCropRules.IsLimitedSeed(item.seedId) then filtered[#filtered + 1] = item end
    end
    if #filtered == 0 then return packCfg.weightPool end
    return filtered
end

function ServerCropRules.RollSeedFromPack(packCfg)
    local item = RollWeighted(ServerCropRules.GetPackRollPool(packCfg))
    return item and item.seedId or 1
end

function ServerCropRules.RollRareSeedId()
    local pool = deps_.GameConfig.RARITY_PLANT_INDICES and deps_.GameConfig.RARITY_PLANT_INDICES["稀有"] or {}
    local filtered = {}
    for _, seedId in ipairs(pool) do
        if not ServerCropRules.IsLimitedSeed(seedId) then filtered[#filtered + 1] = seedId end
    end
    if #filtered == 0 then filtered = pool end
    if #filtered == 0 then return 7 end
    return filtered[math.random(1, #filtered)]
end

function ServerCropRules.RollHarvestDropPack(rarity)
    rarity = rarity or "普通"
    local baseRate = deps_.InventoryRules.HARVEST_DROP_RATES_BY_RARITY[rarity] or 0.01
    if math.random() > baseRate then return nil end
    local pool = deps_.InventoryRules.HARVEST_DROP_PACK_WEIGHTS_BY_RARITY[rarity] or deps_.InventoryRules.HARVEST_DROP_PACK_WEIGHTS
    local picked = RollWeighted(pool)
    return picked and picked.packId or nil
end

function ServerCropRules.GetCropScaleRules()
    return deps_.GameConfig.CROP_SCALE_RULES or {}
end

function ServerCropRules.ClampCropWeightScale(weightScale)
    local rules = ServerCropRules.GetCropScaleRules()
    local minScale = rules.WeightScaleMin or 0.20
    local maxScale = rules.WeightScaleMax or 3.50
    return ClampValue(weightScale, minScale, maxScale)
end

function ServerCropRules.GetWeightMultiplierFromRatio(weightRatio)
    local rules = ServerCropRules.GetCropScaleRules()
    local minMultiplier = rules.PriceMultiplierMin or 0.04
    local maxMultiplier = rules.PriceMultiplierMax or 12.0
    return math.min(math.max(weightRatio * weightRatio, minMultiplier), maxMultiplier)
end

function ServerCropRules.RollCropWeightScale()
    local rules = ServerCropRules.GetCropScaleRules()
    local minScale = rules.WeightScaleMin or 0.20
    local lightMax = rules.LightWeightScaleMax or 0.90
    local normalMax = rules.NormalWeightScaleMax or 1.20
    local largeMax = rules.LargeWeightScaleMax or 2.00
    local maxScale = rules.WeightScaleMax or 3.50
    local r = math.random()
    if r < 0.34 then return RandomRange(minScale, lightMax), "Light" end
    if r < 0.94 then return RandomRange(lightMax, normalMax), "Normal" end
    if r < 0.99 then return RandomRange(normalMax, largeMax), "Large" end
    return RandomRange(largeMax, maxScale), "Giant"
end

function ServerCropRules.SerializeColor(color)
    if color == nil then return nil end
    return { r = color.r or 1, g = color.g or 1, b = color.b or 1, a = color.a or 1 }
end

function ServerCropRules.CloneColorMutation(item)
    if item == nil then return nil end
    return {
        key = item.key,
        name = item.name,
        color = ServerCropRules.SerializeColor(item.color),
        multiplier = item.multiplier,
        sightMultiplier = item.sightMultiplier,
        timeMultiplier = item.timeMultiplier,
        prefixes = item.prefixes,
    }
end

function ServerCropRules.CloneSpecialMutation(item)
    if item == nil then return nil end
    return {
        key = item.key,
        name = item.name,
        multiplier = item.multiplier,
        sightMultiplier = item.sightMultiplier,
        timeMultiplier = item.timeMultiplier,
        prefixes = item.prefixes,
    }
end

function ServerCropRules.FindSpecialMutationConfig(key)
    for _, special in ipairs(deps_.GameConfig.SPECIAL_MUTATIONS or {}) do
        if special.key == key then return special end
    end
    return nil
end

function ServerCropRules.HasMutationSpecial(mutation, key)
    if mutation == nil or type(mutation.specials) ~= "table" then return false end
    for _, special in ipairs(mutation.specials) do
        if special.key == key then return true end
    end
    return false
end

function ServerCropRules.AddServerSpecialMutation(mutation, key)
    if mutation == nil or ServerCropRules.HasMutationSpecial(mutation, key) then return false end
    local special = ServerCropRules.CloneSpecialMutation(ServerCropRules.FindSpecialMutationConfig(key))
    if special == nil then return false end
    table.insert(mutation.specials, special)
    mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
    mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
    return true
end

function ServerCropRules.ApplyServerActivityPlantingMutation(mutation, mutationBonus)
    local activityId = deps_.GameConfig.GetActiveActivityId and deps_.GameConfig.GetActiveActivityId(Now()) or nil
    if activityId ~= "dark" then return end
    local activity = (((deps_.GameConfig.ACTIVITY_CONFIG or {}).activities or {})[activityId])
    if activity == nil then return end
    local devourMultiplier = 1.0 + math.max(0, tonumber(mutationBonus or 0) or 0)
    local devourChance = math.min((activity.devourChance or 0.04) * devourMultiplier, activity.devourChanceMax or 0.12)
    if math.random() <= devourChance then
        ServerCropRules.AddServerSpecialMutation(mutation, "devour")
    end
    if math.random() <= (activity.extraVoidChance or 0.05) then
        ServerCropRules.AddServerSpecialMutation(mutation, "void")
    end
end

local function IsSpecialAllowedForNormalRoll(special)
    if special == nil then return false end
    return special.exclusiveActivity == nil
end

local function RandNormalSpecialMutation()
    local pool = {}
    for _, special in ipairs(deps_.GameConfig.SPECIAL_MUTATIONS or {}) do
        if IsSpecialAllowedForNormalRoll(special) then
            table.insert(pool, special)
        end
    end
    return RandItem(pool)
end

function ServerCropRules.RollServerMutation(plant, seedBuff, mutationBonus)
    seedBuff = seedBuff or 0
    mutationBonus = mutationBonus or 0
    local chanceMultiplier = 1.0 + seedBuff + mutationBonus
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
        mutation.colorMutation = ServerCropRules.CloneColorMutation(RandItem(deps_.GameConfig.COLOR_MUTATIONS))
        if mutation.colorMutation ~= nil then
            mutation.priceMultiplier = mutation.priceMultiplier * (mutation.colorMutation.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (mutation.colorMutation.timeMultiplier or 1.0)
        end
    end
    if math.random() <= specialChance then
        local special = ServerCropRules.CloneSpecialMutation(RandNormalSpecialMutation())
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
        end
    end
    if #mutation.specials == 1 and math.random() <= doubleChance then
        local special = ServerCropRules.CloneSpecialMutation(RandNormalSpecialMutation())
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
        end
    end
    ServerCropRules.ApplyServerActivityPlantingMutation(mutation, mutationBonus)
    mutation.priceMultiplier = math.min(mutation.priceMultiplier, 80.0)
    mutation.timeMultiplier = math.min(mutation.timeMultiplier, 2.7)
    return mutation
end

function ServerCropRules.BuildAuthCropName(plant, mutation)
    local prefixes = {}
    if mutation ~= nil and mutation.sizePrefix ~= nil then table.insert(prefixes, mutation.sizePrefix) end
    if mutation ~= nil and mutation.colorMutation ~= nil then
        local prefix = RandItem(mutation.colorMutation.prefixes)
        if prefix ~= nil then table.insert(prefixes, prefix) end
    end
    if mutation ~= nil and mutation.specials ~= nil then
        for _, special in ipairs(mutation.specials) do
            local prefix = RandItem(special.prefixes)
            if prefix ~= nil then table.insert(prefixes, prefix) end
        end
    end
    if #prefixes <= 0 then return plant.name end
    return table.concat(prefixes, "") .. plant.name
end

function ServerCropRules.CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
    local priceBase = math.max(1, tonumber(plant.seedPrice or plant.fruitPrice or 1) or 1)
    local mutationMultiplier = mutation and mutation.priceMultiplier or 1.0
    return math.floor(math.min(priceBase * (weightMultiplier or 1.0) * mutationMultiplier, priceBase * 200) + 0.5)
end

function ServerCropRules.RecalculateAuthoritativeItemPrice(item)
    if type(item) ~= "table" then return end
    local plant = deps_.GameConfig.PLANTS[tonumber(item.plantIndex or 0) or 0]
    if plant == nil then return end
    local baseWeight = math.max(0.001, tonumber(item.baseWeight or plant.baseWeight or 1.0) or 1.0)
    local weight = tonumber(item.weight or baseWeight) or baseWeight
    local weightRatio = weight / baseWeight
    local weightMultiplier = ServerCropRules.GetWeightMultiplierFromRatio(weightRatio)
    item.baseWeight = baseWeight
    item.weight = weight
    item.weightMultiplier = weightMultiplier
    item.price = ServerCropRules.CalculateAuthoritativeCropPrice(plant, weightMultiplier, item.mutation)
end

function ServerCropRules.BuildAuthoritativeCrop(uid, payload, seedBuff, mutationBonus)
    local now = Now()
    local plantIndex = NormalizePlantIndex(payload.plantIndex)
    if plantIndex == nil then return nil end
    local plant = deps_.GameConfig.PLANTS[plantIndex]
    local weightScale, weightTier = ServerCropRules.RollCropWeightScale()
    local mutation = ServerCropRules.RollServerMutation(plant, seedBuff, mutationBonus)
    local scaleRules = ServerCropRules.GetCropScaleRules()
    local naturalMin = scaleRules.NaturalScaleMin or 0.54
    local naturalMax = scaleRules.NaturalScaleMax or 1.38
    local naturalScale = RandomRange(naturalMin, naturalMax)
    local baseWeight = plant.baseWeight or 1.0
    local weightRatio = ServerCropRules.ClampCropWeightScale(weightScale)
    local weight = baseWeight * weightRatio
    local weightMultiplier = ServerCropRules.GetWeightMultiplierFromRatio(weightRatio)
    mutation.sizeScale = mutation.sizeScale * naturalScale * (weightRatio ^ (scaleRules.VisualWeightExponent or 0.62))
    local price = ServerCropRules.CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
    local growTime = math.max(1, (tonumber(plant.growTime or 1) or 1) * mutation.timeMultiplier)
    local localPos = NormalizeLocalPos(payload.localPos)
    local plotIndex = NormalizePlotIndex(payload.plotIndex)
    local cropId = string.format("u%s_p%s_%d_%d", tostring(uid), tostring(plotIndex), now, math.random(100000, 999999))
    return {
        cropId = cropId,
        serverCropId = cropId,
        plantIndex = plantIndex,
        name = ServerCropRules.BuildAuthCropName(plant, mutation),
        price = price,
        sightValue = math.max(1, math.floor((plant.sightBase or plant.fruitPrice or 1) * weightMultiplier * math.max(1.0, mutation.priceMultiplier * 0.45) + 0.5)),
        rarity = plant.rarity,
        weight = weight,
        baseWeight = baseWeight,
        weightScale = weightScale,
        weightTier = weightTier,
        weightBonus = 1.0,
        weightMultiplier = weightMultiplier,
        elapsed = 0,
        growTime = growTime,
        mature = false,
        sprouted = false,
        plantedAt = now,
        matureAt = now + growTime,
        localPos = { x = tonumber(localPos.x or 0) or 0, z = tonumber(localPos.z or 0) or 0 },
        seedRadius = (0.09 + math.random() * 0.055) * naturalScale,
        seedHeight = 0.010 + math.random() * 0.008,
        pickRadius = math.max(0.55, 0.42 * mutation.sizeScale),
        mutation = mutation,
        stolen = false,
        harvested = false,
        stealable = false,
    }
end

return ServerCropRules
