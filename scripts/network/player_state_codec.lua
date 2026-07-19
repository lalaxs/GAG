-- ============================================================================
-- 玩家状态紧凑编解码
-- ============================================================================
-- 运行时继续使用完整作物结构；仅在云存档和网络传输边界压缩重复静态字段。
-- 旧版完整结构可直接 hydrate，新版紧凑结构通过 _psc 标记识别。
-- ============================================================================

local GameConfig = require("config.game_config")

local PlayerStateCodec = {}

PlayerStateCodec.VERSION = 2

local MARK_MUTATION = "m"
local MARK_CROP = "c"
local MARK_HARVEST = "h"

local colorByKey_ = {}
local specialByKey_ = {}
for _, item in ipairs(GameConfig.COLOR_MUTATIONS or {}) do
    colorByKey_[item.key] = item
end
for _, item in ipairs(GameConfig.SPECIAL_MUTATIONS or {}) do
    specialByKey_[item.key] = item
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = DeepCopy(item)
    end
    return result
end

local function SerializeColor(color)
    if color == nil then return nil end
    return {
        r = tonumber(color.r or 1) or 1,
        g = tonumber(color.g or 1) or 1,
        b = tonumber(color.b or 1) or 1,
        a = tonumber(color.a or 1) or 1,
    }
end

local function HydrateColorConfig(key)
    local item = colorByKey_[key]
    if item == nil then return nil end
    return {
        key = item.key,
        name = item.name,
        color = SerializeColor(item.color),
        multiplier = item.multiplier,
        sightMultiplier = item.sightMultiplier,
        timeMultiplier = item.timeMultiplier,
        prefixes = DeepCopy(item.prefixes or {}),
    }
end

local function HydrateSpecialConfig(key)
    local item = specialByKey_[key]
    if item == nil then
        return { key = key, name = tostring(key), multiplier = 1, sightMultiplier = 1, timeMultiplier = 1, prefixes = {} }
    end
    return {
        key = item.key,
        name = item.name,
        multiplier = item.multiplier,
        sightMultiplier = item.sightMultiplier,
        timeMultiplier = item.timeMultiplier,
        prefixes = DeepCopy(item.prefixes or {}),
    }
end

local function CompactMutation(mutation)
    mutation = type(mutation) == "table" and mutation or {}
    local specialKeys = {}
    for _, special in ipairs(type(mutation.specials) == "table" and mutation.specials or {}) do
        if type(special) == "table" and special.key ~= nil then
            specialKeys[#specialKeys + 1] = tostring(special.key)
        end
    end
    return {
        _psc = MARK_MUTATION,
        z = tonumber(mutation.sizeScale or 1) or 1,
        p = mutation.sizePrefix,
        c = type(mutation.colorMutation) == "table" and mutation.colorMutation.key or nil,
        s = specialKeys,
        v = tonumber(mutation.priceMultiplier or 1) or 1,
        t = tonumber(mutation.timeMultiplier or 1) or 1,
        b = tonumber(mutation.seedBuff or 0) or 0,
    }
end

local function HydrateMutation(value)
    if type(value) ~= "table" then
        return {
            sizeScale = 1,
            sizePrefix = nil,
            colorMutation = nil,
            specials = {},
            priceMultiplier = 1,
            timeMultiplier = 1,
            seedBuff = 0,
        }
    end
    if value._psc ~= MARK_MUTATION then
        return DeepCopy(value)
    end
    local specials = {}
    for _, key in ipairs(type(value.s) == "table" and value.s or {}) do
        specials[#specials + 1] = HydrateSpecialConfig(tostring(key))
    end
    return {
        sizeScale = tonumber(value.z or 1) or 1,
        sizePrefix = value.p,
        colorMutation = value.c ~= nil and HydrateColorConfig(tostring(value.c)) or nil,
        specials = specials,
        priceMultiplier = tonumber(value.v or 1) or 1,
        timeMultiplier = tonumber(value.t or 1) or 1,
        seedBuff = tonumber(value.b or 0) or 0,
    }
end

local function GetPlant(plantIndex)
    return (GameConfig.PLANTS or {})[math.floor(tonumber(plantIndex or 0) or 0)] or {}
end

local function GetWeightMultiplier(weight, baseWeight)
    local base = math.max(0.001, tonumber(baseWeight or 1) or 1)
    local ratio = (tonumber(weight or base) or base) / base
    return math.min(math.max(ratio * ratio, 0.04), 12)
end

local function CompactCrop(crop)
    local pos = type(crop.localPos) == "table" and crop.localPos or {}
    return {
        _psc = MARK_CROP,
        i = crop.cropId or crop.serverCropId,
        p = crop.plantIndex,
        n = crop.name,
        v = crop.price,
        o = crop.sightValue,
        w = crop.weight,
        b = crop.baseWeight,
        q = crop.weightScale,
        t = crop.weightTier,
        g = crop.growTime,
        a = crop.plantedAt,
        x = pos.x,
        y = pos.z,
        r = crop.seedRadius,
        h = crop.seedHeight,
        u = CompactMutation(crop.mutation),
        d = crop.stolen == true or nil,
        e = crop.harvested == true or nil,
    }
end

local function HydrateCrop(value)
    if type(value) ~= "table" or value._psc ~= MARK_CROP then return DeepCopy(value) end
    local plantIndex = math.floor(tonumber(value.p or 1) or 1)
    local plant = GetPlant(plantIndex)
    local mutation = HydrateMutation(value.u)
    local baseWeight = math.max(0.001, tonumber(value.b or plant.baseWeight or 1) or 1)
    local weight = tonumber(value.w or baseWeight) or baseWeight
    local weightMultiplier = GetWeightMultiplier(weight, baseWeight)
    local now = os and os.time and os.time() or 0
    local growTime = math.max(1, tonumber(value.g or plant.growTime or 1) or 1)
    local plantedAt = tonumber(value.a or now) or now
    local matureAt = plantedAt + growTime
    local elapsed = math.max(0, math.min(growTime, now - plantedAt))
    local mature = now >= matureAt
    local stolen = value.d == true
    local harvested = value.e == true
    local cropId = value.i
    return {
        cropId = cropId,
        serverCropId = cropId,
        plantIndex = plantIndex,
        name = value.n or plant.name,
        price = tonumber(value.v or 0) or 0,
        sightValue = tonumber(value.o or plant.sightBase or plant.fruitPrice or 1) or 1,
        rarity = plant.rarity,
        weight = weight,
        baseWeight = baseWeight,
        weightScale = tonumber(value.q or (weight / baseWeight)) or (weight / baseWeight),
        weightTier = value.t or "Normal",
        weightBonus = 1,
        weightMultiplier = weightMultiplier,
        elapsed = elapsed,
        growTime = growTime,
        mature = mature,
        sprouted = mature or elapsed >= growTime * 0.18,
        plantedAt = plantedAt,
        matureAt = matureAt,
        localPos = { x = tonumber(value.x or 0) or 0, z = tonumber(value.y or 0) or 0 },
        seedRadius = tonumber(value.r or 0.09) or 0.09,
        seedHeight = tonumber(value.h or 0.01) or 0.01,
        pickRadius = math.max(0.55, 0.42 * (tonumber(mutation.sizeScale or 1) or 1)),
        mutation = mutation,
        stolen = stolen,
        harvested = harvested,
        stealable = mature and not stolen and not harvested,
    }
end

local function CompactHarvest(item)
    return {
        _psc = MARK_HARVEST,
        i = item.cropId,
        p = item.plantIndex,
        n = item.name,
        v = item.price,
        o = item.sightValue,
        w = item.weight,
        b = item.baseWeight,
        t = item.weightTier,
        u = CompactMutation(item.mutation),
    }
end

local function HydrateHarvest(value)
    if type(value) ~= "table" or value._psc ~= MARK_HARVEST then return DeepCopy(value) end
    local plantIndex = math.floor(tonumber(value.p or 1) or 1)
    local plant = GetPlant(plantIndex)
    local baseWeight = math.max(0.001, tonumber(value.b or plant.baseWeight or 1) or 1)
    local weight = tonumber(value.w or baseWeight) or baseWeight
    return {
        cropId = value.i,
        plantIndex = plantIndex,
        name = value.n or plant.name,
        price = tonumber(value.v or 0) or 0,
        sightValue = tonumber(value.o or plant.sightBase or plant.fruitPrice or 1) or 1,
        rarity = plant.rarity,
        weight = weight,
        baseWeight = baseWeight,
        weightTier = value.t or "Normal",
        weightMultiplier = GetWeightMultiplier(weight, baseWeight),
        mutation = HydrateMutation(value.u),
    }
end

function PlayerStateCodec.SanitizeEconomyForClient(economy)
    if type(economy) ~= "table" then return economy end
    local result = {}
    for key, value in pairs(economy) do
        if key ~= "adRewardReceipts"
            and key ~= "adRewardReceiptOrder"
            and key ~= "adRewardDaily" then
            result[key] = DeepCopy(value)
        end
    end
    return result
end

function PlayerStateCodec.CompactEconomy(economy)
    if type(economy) ~= "table" then return economy end
    local result = {}
    for key, value in pairs(economy) do
        if key ~= "harvested" then result[key] = DeepCopy(value) end
    end
    result.harvested = {}
    for _, item in ipairs(type(economy.harvested) == "table" and economy.harvested or {}) do
        result.harvested[#result.harvested + 1] = CompactHarvest(item)
    end
    return result
end

function PlayerStateCodec.HydrateEconomy(economy)
    if type(economy) ~= "table" then return economy end
    local result = {}
    for key, value in pairs(economy) do
        if key ~= "harvested" then result[key] = DeepCopy(value) end
    end
    result.harvested = {}
    for _, item in ipairs(type(economy.harvested) == "table" and economy.harvested or {}) do
        result.harvested[#result.harvested + 1] = HydrateHarvest(item)
    end
    return result
end

function PlayerStateCodec.CompactFarm(farm)
    if type(farm) ~= "table" then return farm end
    local result = {}
    for key, value in pairs(farm) do
        if key ~= "plots" then result[key] = DeepCopy(value) end
    end
    result.plots = {}
    for plotKey, plot in pairs(type(farm.plots) == "table" and farm.plots or {}) do
        local compactPlot = {}
        for key, value in pairs(type(plot) == "table" and plot or {}) do
            if key ~= "plants" then compactPlot[key] = DeepCopy(value) end
        end
        compactPlot.plants = {}
        for _, crop in ipairs(type(plot) == "table" and type(plot.plants) == "table" and plot.plants or {}) do
            compactPlot.plants[#compactPlot.plants + 1] = CompactCrop(crop)
        end
        result.plots[plotKey] = compactPlot
    end
    return result
end

function PlayerStateCodec.HydrateFarm(farm)
    if type(farm) ~= "table" then return farm end
    local result = {}
    for key, value in pairs(farm) do
        if key ~= "plots" then result[key] = DeepCopy(value) end
    end
    result.plots = {}
    for plotKey, plot in pairs(type(farm.plots) == "table" and farm.plots or {}) do
        local hydratedPlot = {}
        for key, value in pairs(type(plot) == "table" and plot or {}) do
            if key ~= "plants" then hydratedPlot[key] = DeepCopy(value) end
        end
        hydratedPlot.plants = {}
        for _, crop in ipairs(type(plot) == "table" and type(plot.plants) == "table" and plot.plants or {}) do
            hydratedPlot.plants[#hydratedPlot.plants + 1] = HydrateCrop(crop)
        end
        result.plots[plotKey] = hydratedPlot
    end
    return result
end

local function LooksLikeEconomy(value)
    return type(value) == "table"
        and type(value.harvested) == "table"
        and (type(value.seedBag) == "table" or value.gold ~= nil)
end

local function LooksLikeFarm(value)
    return type(value) == "table" and type(value.plots) == "table" and value.revision ~= nil
end

local function TransformNetwork(value, compact)
    if type(value) ~= "table" then return value end
    if compact then
        if value._psc ~= nil then return DeepCopy(value) end
        if LooksLikeEconomy(value) then
            return PlayerStateCodec.CompactEconomy(
                PlayerStateCodec.SanitizeEconomyForClient(value)
            )
        end
        if LooksLikeFarm(value) then return PlayerStateCodec.CompactFarm(value) end
        if value.cropId ~= nil and value.plantIndex ~= nil and value.mutation ~= nil then
            if value.growTime ~= nil or value.plantedAt ~= nil then return CompactCrop(value) end
            return CompactHarvest(value)
        end
    else
        if value._psc == MARK_CROP then return HydrateCrop(value) end
        if value._psc == MARK_HARVEST then return HydrateHarvest(value) end
        if value._psc == MARK_MUTATION then return HydrateMutation(value) end
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = TransformNetwork(item, compact)
    end
    return result
end

function PlayerStateCodec.CompactNetwork(value)
    return TransformNetwork(value, true)
end

function PlayerStateCodec.HydrateNetwork(value)
    return TransformNetwork(value, false)
end

function PlayerStateCodec.NeedsCompaction(doc)
    return type(doc) == "table" and math.floor(tonumber(doc.codecVersion or 0) or 0) < PlayerStateCodec.VERSION
end

return PlayerStateCodec
