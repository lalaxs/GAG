-- ============================================================================
-- 社交花园服务端入口
-- ============================================================================
-- 服务端权威处理：花园快照、作物成熟与可偷状态、排行榜、拜访、偷菜日志、种子赠送。
-- 客户端只上传可视快照；作物 ID、种植时间、成熟、被偷状态与奖励发放由服务端合并保存。
-- ============================================================================

local Shared = require("network.shared")
local GameConfig = require("config.game_config")
local InventoryRules = require("systems.inventory_rules")
local RequestGuard = require("server.request_guard")
local GiftServer = require("server.gift_server")
local SocialServer = require("server.social_server")

local scene_ = nil
local connections_ = {}
local connectionUsers_ = {}

local DAILY_STEAL_LIMIT = 10
local DAILY_GIFT_LIMIT = 5
local MAX_SOCIAL_ROWS = 20
local START_GOLD = 150
local SEED_STACK_MAX = 999
local MAX_OPEN_PACK_COUNT = 50
local MAX_GIFT_COUNT = 1
local ALLOW_CLIENT_ECONOMY_SAVE = false

local function Now()
    return os and os.time and os.time() or 0
end

local function GetConnectionKey(connection)
    if connection == nil then return "" end
    return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
end

local function GetConnectionUserId(connection)
    if connection == nil or connection.identity == nil or connection.identity["user_id"] == nil then
        return nil
    end
    return connection.identity["user_id"]:GetInt64()
end

local function Send(connection, eventName, data)
    Shared.SendToClient(connection, eventName, data)
end

local function SendError(connection, eventName, code, message, extra)
    local data = extra or {}
    data.success = false
    data.code = code
    data.message = message
    Send(connection, eventName, data)
end

local function NormalizePlantIndex(value)
    local index = math.floor(tonumber(value or 0) or 0)
    if index < 1 or GameConfig.PLANTS[index] == nil then return nil end
    return index
end

local function NormalizePlotIndex(value)
    local index = math.floor(tonumber(value or 1) or 1)
    if index < 1 then index = 1 end
    return index
end

local function NormalizePositiveCount(value, maxValue)
    local count = math.floor(tonumber(value or 1) or 1)
    if count < 1 then count = 1 end
    if maxValue ~= nil then count = math.min(count, maxValue) end
    return count
end

local function NormalizeLocalPos(value)
    value = type(value) == "table" and value or {}
    local half = GameConfig.CONFIG and GameConfig.CONFIG.PlantableHalf or 0.60
    local x = Clamp(tonumber(value.x or 0) or 0, -half, half)
    local z = Clamp(tonumber(value.z or 0) or 0, -half, half)
    return { x = x, z = z }
end

local function IsValidPackId(packId)
    return type(packId) == "string" and GameConfig.SEED_PACK_CONFIG[packId] ~= nil
end

local function IsValidSellMode(mode)
    return mode == "all" or mode == "index" or mode == "filter"
end

local function NextRevision(state)
    state.revision = (tonumber(state.revision or 0) or 0) + 1
end

local function GetMaxCropsPerPlot()
    return GameConfig.CONFIG and GameConfig.CONFIG.MaxCropsPerPlot or 10
end

local function CheckRequestId(...)
    return RequestGuard.Check(...)
end

local function RecordRequestId(...)
    return RequestGuard.Record(...)
end

local function AddRequestRecordToCommit(...)
    return RequestGuard.AddToCommit(...)
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = DeepCopy(item)
    end
    return result
end

local function CopyNumericKeyMap(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        local numericKey = tonumber(key)
        if numericKey ~= nil then
            result[math.floor(numericKey)] = value
        else
            result[key] = value
        end
    end
    return result
end

local function RollWeighted(pool)
    local total = 0
    for _, item in ipairs(pool or {}) do
        total = total + math.max(0, tonumber(item.weight or 0) or 0)
    end
    if total <= 0 then return nil end
    local r = math.random() * total
    local acc = 0
    for _, item in ipairs(pool or {}) do
        acc = acc + math.max(0, tonumber(item.weight or 0) or 0)
        if r <= acc then return item end
    end
    return pool[#pool]
end

local function IsLimitedSeed(seedId)
    local plant = GameConfig.PLANTS[seedId]
    return plant ~= nil and (plant.limited == true or plant.activityTag ~= nil)
end

local function GetPackRollPool(packCfg)
    if packCfg.allowLimitedSeeds == true then return packCfg.weightPool end
    local filtered = {}
    for _, item in ipairs(packCfg.weightPool or {}) do
        if not IsLimitedSeed(item.seedId) then filtered[#filtered + 1] = item end
    end
    if #filtered == 0 then return packCfg.weightPool end
    return filtered
end

local function RollSeedFromPack(packCfg)
    local item = RollWeighted(GetPackRollPool(packCfg))
    return item and item.seedId or 1
end

local function RollHarvestDropPack(rarity)
    rarity = rarity or "普通"
    local baseRate = InventoryRules.HARVEST_DROP_RATES_BY_RARITY[rarity] or 0.01
    if math.random() > baseRate then return nil end
    local pool = InventoryRules.HARVEST_DROP_PACK_WEIGHTS_BY_RARITY[rarity] or InventoryRules.HARVEST_DROP_PACK_WEIGHTS
    local picked = RollWeighted(pool)
    return picked and picked.packId or nil
end

local function RandomRange(minValue, maxValue)
    return minValue + math.random() * (maxValue - minValue)
end

local function RollCropWeightScale()
    local r = math.random()
    if r < 0.25 then return RandomRange(0.65, 0.9), "Light" end
    if r < 0.80 then return RandomRange(0.9, 1.2), "Normal" end
    if r < 0.97 then return RandomRange(1.2, 2.0), "Large" end
    return RandomRange(2.0, 3.5), "Giant"
end

local function RandItem(list)
    if list == nil or #list <= 0 then return nil end
    return list[math.random(1, #list)]
end

local function SerializeColor(color)
    if color == nil then return nil end
    return { r = color.r or 1, g = color.g or 1, b = color.b or 1, a = color.a or 1 }
end

local function CloneColorMutation(item)
    if item == nil then return nil end
    return {
        key = item.key,
        name = item.name,
        color = SerializeColor(item.color),
        multiplier = item.multiplier,
        sightMultiplier = item.sightMultiplier,
        timeMultiplier = item.timeMultiplier,
        prefixes = item.prefixes,
    }
end

local function CloneSpecialMutation(item)
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

local function RollServerMutation(plant, seedBuff)
    seedBuff = seedBuff or 0
    local chanceMultiplier = 1.0 + seedBuff
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
        mutation.colorMutation = CloneColorMutation(RandItem(GameConfig.COLOR_MUTATIONS))
        if mutation.colorMutation ~= nil then
            mutation.priceMultiplier = mutation.priceMultiplier * (mutation.colorMutation.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (mutation.colorMutation.timeMultiplier or 1.0)
        end
    end
    if math.random() <= specialChance then
        local special = CloneSpecialMutation(RandItem(GameConfig.SPECIAL_MUTATIONS))
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
        end
    end
    if #mutation.specials == 1 and math.random() <= doubleChance then
        local special = CloneSpecialMutation(RandItem(GameConfig.SPECIAL_MUTATIONS))
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
        end
    end
    mutation.priceMultiplier = math.min(mutation.priceMultiplier, 80.0)
    mutation.timeMultiplier = math.min(mutation.timeMultiplier, 2.7)
    return mutation
end

local function BuildAuthCropName(plant, mutation)
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

local function BuildAuthoritativeCrop(uid, payload, seedBuff)
    local now = Now()
    local plantIndex = NormalizePlantIndex(payload.plantIndex)
    if plantIndex == nil then return nil end
    local plant = GameConfig.PLANTS[plantIndex]
    local weightScale, weightTier = RollCropWeightScale()
    local mutation = RollServerMutation(plant, seedBuff)
    local naturalScale = 0.78 + math.random() * 0.62
    local baseWeight = plant.baseWeight or 1.0
    local weight = baseWeight * weightScale
    local weightRatio = weight / baseWeight
    local weightMultiplier = math.min(math.max(weightRatio * weightRatio, 0.4), 12.0)
    mutation.sizeScale = mutation.sizeScale * naturalScale * (weightScale ^ 0.35)
    local price = math.floor(math.min((plant.fruitPrice or 1) * weightMultiplier * mutation.priceMultiplier, (plant.fruitPrice or 1) * 200) + 0.5)
    local growTime = math.max(1, (tonumber(plant.growTime or 1) or 1) * mutation.timeMultiplier)
    local localPos = NormalizeLocalPos(payload.localPos)
    local plotIndex = NormalizePlotIndex(payload.plotIndex)
    local cropId = string.format("u%s_p%s_%d_%d", tostring(uid), tostring(plotIndex), now, math.random(100000, 999999))
    return {
        cropId = cropId,
        serverCropId = cropId,
        plantIndex = plantIndex,
        name = BuildAuthCropName(plant, mutation),
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

local function NormalizeFarmState(state)
    state = type(state) == "table" and state or {}
    state.version = 1
    state.plots = type(state.plots) == "table" and state.plots or {}
    state.updatedAt = Now()
    return state
end

local function GetFarmPlot(state, plotIndex)
    plotIndex = math.max(1, tonumber(plotIndex or 1) or 1)
    state.plots[plotIndex] = state.plots[plotIndex] or { plants = {} }
    state.plots[plotIndex].plants = state.plots[plotIndex].plants or {}
    return state.plots[plotIndex]
end

local function FindFarmCrop(state, cropId)
    if cropId == nil then return nil, nil, nil end
    for plotIndex, plot in pairs(state.plots or {}) do
        for cropIndex, crop in ipairs(plot.plants or {}) do
            if crop.cropId == cropId or crop.serverCropId == cropId then
                return crop, tonumber(plotIndex), cropIndex
            end
        end
    end
    return nil, nil, nil
end

local function FindFarmCropFromHarvestPayload(state, payload)
    payload = payload or {}
    local requestedCropId = payload.cropId
    if requestedCropId ~= nil and requestedCropId ~= "" then
        local crop, plotIndex, cropIndex = FindFarmCrop(state, requestedCropId)
        if crop ~= nil then return crop, plotIndex, cropIndex end
    end

    local plotIndex = NormalizePlotIndex(payload.plotIndex)
    local plot = GetFarmPlot(state, plotIndex)
    local cropIndex = math.floor(tonumber(payload.cropIndex or 0) or 0)
    if cropIndex >= 1 and plot.plants[cropIndex] ~= nil then
        return plot.plants[cropIndex], plotIndex, cropIndex
    end

    local posSource = payload.localPos or (payload.crop and payload.crop.localPos)
    if type(posSource) == "table" then
        local localPos = NormalizeLocalPos(posSource)
        local bestCrop, bestIndex, bestDist = nil, nil, 999999
        for index, crop in ipairs(plot.plants or {}) do
            local cropPos = crop.localPos or {}
            local dx = (tonumber(cropPos.x or 0) or 0) - localPos.x
            local dz = (tonumber(cropPos.z or 0) or 0) - localPos.z
            local dist = dx * dx + dz * dz
            local radius = math.max(0.55, tonumber(crop.pickRadius or 0.55) or 0.55)
            if dist <= radius * radius and dist < bestDist then
                bestCrop = crop
                bestIndex = index
                bestDist = dist
            end
        end
        if bestCrop ~= nil then return bestCrop, plotIndex, bestIndex end
    end

    return nil, nil, nil
end

local function RefreshAuthCrop(crop)
    local now = Now()
    crop.growTime = math.max(1, tonumber(crop.growTime or 1) or 1)
    crop.plantedAt = tonumber(crop.plantedAt or now) or now
    crop.matureAt = tonumber(crop.matureAt or (crop.plantedAt + crop.growTime)) or (crop.plantedAt + crop.growTime)
    crop.elapsed = math.max(0, math.min(crop.growTime, now - crop.plantedAt))
    crop.mature = now >= crop.matureAt
    crop.stealable = crop.mature == true and crop.stolen ~= true and crop.harvested ~= true
end

local function CalculateAuthCropSightValue(crop)
    if type(crop) ~= "table" or crop.harvested == true then return 0 end
    RefreshAuthCrop(crop)
    local plant = GameConfig.PLANTS[tonumber(crop.plantIndex or 0) or 0] or {}
    local baseValue = tonumber(crop.sightValue or plant.sightBase or plant.fruitPrice or 1) or 1
    local growthMultiplier = 1.0
    if crop.mature ~= true then
        local progress = 0
        if crop.growTime ~= nil and crop.growTime > 0 then
            progress = Clamp((crop.elapsed or 0) / crop.growTime, 0.0, 1.0)
        end
        if progress < 0.18 then
            growthMultiplier = 0.1
        elseif progress < 0.55 then
            growthMultiplier = 0.3
        else
            growthMultiplier = 0.6
        end
    end
    return math.max(0, math.floor(baseValue * growthMultiplier + 0.5))
end

local function CalculateAuthFarmTourValue(farmState)
    farmState = NormalizeFarmState(farmState)
    local total = 0
    for _, plot in pairs(farmState.plots or {}) do
        for _, crop in ipairs(plot.plants or {}) do
            total = total + CalculateAuthCropSightValue(crop)
        end
    end
    return total
end

local function BuildVisitGardenFromAuthFarm(uid, nickname, farmState, snapshot)
    farmState = NormalizeFarmState(farmState)
    local plotIndex = tonumber(snapshot and snapshot.visitablePlotIndex or 1) or 1
    local plot = GetFarmPlot(farmState, plotIndex)
    local plants = {}
    for _, crop in ipairs(plot.plants or {}) do
        if crop.harvested ~= true then
            RefreshAuthCrop(crop)
            plants[#plants + 1] = crop
        end
    end
    local tourValue = CalculateAuthFarmTourValue(farmState)
    local bestTourValue = tourValue
    return {
        version = 3,
        source = "auth_farm",
        userId = uid,
        nickname = nickname or snapshot and snapshot.nickname or "Tap玩家",
        visitablePlotIndex = plotIndex,
        unlockedPlotCount = snapshot and snapshot.unlockedPlotCount or 1,
        tourValue = tourValue,
        bestTourValue = bestTourValue,
        likeCount = 0,
        updatedAt = Now(),
        plot = { plotIndex = plotIndex, plants = plants },
    }
end

local function NormalizeEconomyState(state)
    state = type(state) == "table" and state or {}
    state.gold = math.max(0, math.floor(tonumber(state.gold or START_GOLD) or START_GOLD))
    state.seedBag = CopyNumericKeyMap(state.seedBag)
    state.seedBagBuffs = CopyNumericKeyMap(state.seedBagBuffs)
    state.harvested = type(state.harvested) == "table" and state.harvested or {}
    state.seedPacks = type(state.seedPacks) == "table" and state.seedPacks or {}
    state.collectedPlants = CopyNumericKeyMap(state.collectedPlants)
    state.updatedAt = Now()
    return state
end

local function BuildInitialEconomyState()
    return NormalizeEconomyState({
        gold = START_GOLD,
        seedBag = { [1] = 6, [21] = 4, [2] = 2 },
        seedBagBuffs = {},
        harvested = {},
        seedPacks = { pack_common = 1 },
    })
end

local function RequestAuthFarmState(uid, connection)
    serverCloud:Get(uid, Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(scores)
            local farmState = NormalizeFarmState(scores[Shared.KEYS.AUTH_FARM_STATE])
            for _, plot in pairs(farmState.plots or {}) do
                for _, crop in ipairs(plot.plants or {}) do
                    RefreshAuthCrop(crop)
                end
            end
            Send(connection, Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = farmState })
        end,
        error = function()
            Send(connection, Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = NormalizeFarmState(nil) })
        end,
    })
end

local function RequestEconomyState(uid, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = scores[Shared.KEYS.ECONOMY_STATE]
            if type(state) ~= "table" then
                state = BuildInitialEconomyState()
                serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state)
            else
                state = NormalizeEconomyState(state)
            end
            Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
        error = function()
            local state = BuildInitialEconomyState()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state)
            Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
    })
end

local function SaveEconomyState(uid, state, connection)
    if ALLOW_CLIENT_ECONOMY_SAVE ~= true then
        RequestEconomyState(uid, connection)
        return
    end
    local nextState = NormalizeEconomyState(state)
    NextRevision(nextState)
    serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, nextState, {
        ok = function()
            Send(connection, Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, { success = true, state = nextState })
        end,
        error = function(_, reason)
            print("[经济] 客户端经济状态保存失败: " .. tostring(reason))
            SendError(connection, Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, "ECONOMY_SAVE_FAILED", "经济数据同步失败")
        end,
    })
end

local function BuySeed(uid, plantIndex, _price, connection, count)
    plantIndex = NormalizePlantIndex(plantIndex)
    count = NormalizePositiveCount(count or 1, 10)
    if plantIndex == nil then
        SendError(connection, Shared.EVENTS.BUY_SEED_RESPONSE, "INVALID_PLANT", "种子配置不存在")
        return
    end
    local plant = GameConfig.PLANTS[plantIndex]
    local price = math.max(0, math.floor(tonumber(plant.seedPrice or 0) or 0))
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
            local buyCount = math.min(count, SEED_STACK_MAX - owned)
            if buyCount <= 0 then
                Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "种子背包已满", state = state })
                return
            end
            local totalPrice = price * buyCount
            if state.gold < totalPrice then
                buyCount = math.min(buyCount, math.floor(state.gold / price))
                totalPrice = price * buyCount
            end
            if buyCount <= 0 then
                Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "金币不足", state = state })
                return
            end
            state.gold = state.gold - totalPrice
            state.seedBag[plantIndex] = owned + buyCount
            state.updatedAt = Now()
            NextRevision(state)
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function()
                    Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = true, message = "购买成功 x" .. tostring(buyCount), plantIndex = plantIndex, price = totalPrice, count = buyCount, state = state })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "购买失败: " .. tostring(reason), state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason) })
        end,
    })
end

local function ClearPlayerSave(uid, connection)
    local economyState = BuildInitialEconomyState()
    local farmState = NormalizeFarmState(nil)
    local c = serverCloud:BatchCommit("清除游戏存档")
    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, economyState)
    c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
    c:Commit({
        ok = function()
            Send(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, { success = true, message = "游戏存档已清除", state = economyState, farm = farmState })
        end,
        error = function(_, reason)
            print("[存档] 云端清档失败: " .. tostring(reason))
            SendError(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, "CLEAR_SAVE_FAILED", "清除存档失败")
        end,
    })
end

local function PlantSeedAuthority(uid, payload, connection)
    payload = payload or {}
    local plantIndex = NormalizePlantIndex(payload.plantIndex)
    if plantIndex == nil then
        SendError(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, "INVALID_PLANT", "作物配置不存在", { requestId = payload.requestId })
        return
    end
    payload.plantIndex = plantIndex
    payload.plotIndex = NormalizePlotIndex(payload.plotIndex)
    payload.localPos = NormalizeLocalPos(payload.localPos)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
            if owned <= 0 then
                Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "没有该种子", state = state })
                return
            end
            local buffCount = tonumber(state.seedBagBuffs[plantIndex] or 0) or 0
            local seedBuff = 0
            if buffCount > 0 then seedBuff = 0.01 end

            serverCloud:Get(uid, Shared.KEYS.AUTH_FARM_STATE, {
                ok = function(farmScores)
                    local farmState = NormalizeFarmState(farmScores[Shared.KEYS.AUTH_FARM_STATE])
                    local plot = GetFarmPlot(farmState, payload.plotIndex)
                    if #plot.plants >= GetMaxCropsPerPlot() then
                        Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "这块田地已满", requestId = payload.requestId, state = state })
                        return
                    end

                    local crop = BuildAuthoritativeCrop(uid, payload, seedBuff)
                    if crop == nil then
                        Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "作物配置不存在", requestId = payload.requestId, state = state })
                        return
                    end

                    state.seedBag[plantIndex] = owned - 1
                    if buffCount > 0 then state.seedBagBuffs[plantIndex] = buffCount - 1 end
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)

                    local response = {
                        success = true,
                        message = "播种确认",
                        requestId = payload.requestId,
                        plantIndex = plantIndex,
                        plotIndex = payload.plotIndex,
                        localPos = payload.localPos,
                        seedBuff = seedBuff,
                        crop = crop,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("权威播种")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                    c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                    RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "播种失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
                error = function()
                    local farmState = NormalizeFarmState(nil)
                    local plot = GetFarmPlot(farmState, payload.plotIndex)
                    local crop = BuildAuthoritativeCrop(uid, payload, seedBuff)
                    if crop == nil then
                        Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "作物配置不存在", requestId = payload.requestId, state = state })
                        return
                    end
                    state.seedBag[plantIndex] = owned - 1
                    if buffCount > 0 then state.seedBagBuffs[plantIndex] = buffCount - 1 end
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)
                    local response = {
                        success = true,
                        message = "播种确认",
                        requestId = payload.requestId,
                        plantIndex = plantIndex,
                        plotIndex = payload.plotIndex,
                        localPos = payload.localPos,
                        seedBuff = seedBuff,
                        crop = crop,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("首次权威播种")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                    c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                    RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "播种失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

local function HarvestCropAuthority(uid, payload, connection)
    payload = payload or {}

    serverCloud:Get(uid, Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(farmScores)
            local farmState = NormalizeFarmState(farmScores[Shared.KEYS.AUTH_FARM_STATE])
            local crop, plotIndex, cropIndex = FindFarmCropFromHarvestPayload(farmState, payload)
            if crop == nil then
                Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "作物不存在或已收获", requestId = payload.requestId })
                return
            end
            RefreshAuthCrop(crop)
            if crop.harvested == true then
                Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "这株作物已经收获过了", requestId = payload.requestId })
                return
            end
            if crop.mature ~= true then
                Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "作物尚未成熟", requestId = payload.requestId })
                return
            end

            serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                ok = function(scores)
                    local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                    state.harvested = state.harvested or {}
                    if #(state.harvested) >= 100 then
                        Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "背包已满", requestId = payload.requestId, state = state })
                        return
                    end

                    local harvestItem = {
                        name = crop.name,
                        price = crop.price,
                        sightValue = crop.sightValue,
                        rarity = crop.rarity,
                        plantIndex = crop.plantIndex,
                        weight = crop.weight,
                        baseWeight = crop.baseWeight,
                        weightTier = crop.weightTier,
                        weightMultiplier = crop.weightMultiplier,
                        mutation = crop.mutation,
                        localPos = crop.localPos,
                        cropId = crop.cropId,
                    }
                    table.insert(state.harvested, harvestItem)
                    local droppedPack = RollHarvestDropPack(crop.rarity)
                    if droppedPack ~= nil and GameConfig.SEED_PACK_CONFIG[droppedPack] ~= nil then
                        state.seedPacks[droppedPack] = (tonumber(state.seedPacks[droppedPack] or 0) or 0) + 1
                    end
                    state.collectedPlants = state.collectedPlants or {}
                    if crop.plantIndex ~= nil then state.collectedPlants[crop.plantIndex] = true end
                    state.updatedAt = Now()
                    NextRevision(state)

                    local plot = GetFarmPlot(farmState, plotIndex)
                    table.remove(plot.plants, cropIndex)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)

                    local response = {
                        success = true,
                        message = "收获确认",
                        requestId = payload.requestId,
                        plotIndex = plotIndex,
                        cropIndex = cropIndex,
                        cropId = crop.cropId or crop.serverCropId or payload.cropId,
                        crop = harvestItem,
                        droppedPack = droppedPack,
                        droppedPackName = droppedPack ~= nil and GameConfig.SEED_PACK_CONFIG[droppedPack] and GameConfig.SEED_PACK_CONFIG[droppedPack].packName or nil,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("权威收获")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                    c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                    RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "收获失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "农场数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

local function OpenSeedPackAuthority(uid, payload, connection)
    payload = payload or {}
    local packId = tostring(payload.packId or "")
    local requestedCount = NormalizePositiveCount(payload.count or 1, MAX_OPEN_PACK_COUNT)
    local openAll = payload.openAll == true
    if not IsValidPackId(packId) then
        SendError(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, "INVALID_PACK", "种子包不存在", { requestId = payload.requestId })
        return
    end
    local packCfg = GameConfig.SEED_PACK_CONFIG[packId]

    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedPacks[packId] or 0) or 0
            local openCount = openAll and owned or math.min(requestedCount, owned)
            if openCount <= 0 then
                Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "暂无可开启的种子包", requestId = payload.requestId, state = state })
                return
            end

            local results = {}
            local seedCounts = {}
            for _ = 1, openCount do
                for _ = 1, math.max(1, tonumber(packCfg.onceOpenCount or 1) or 1) do
                    local seedId = RollSeedFromPack(packCfg)
                    results[#results + 1] = {
                        seedId = seedId,
                        packId = packId,
                        rollPackId = packId,
                        seedBuff = packCfg.seedBuff or 0,
                        isNew = state.collectedPlants[seedId] ~= true,
                        isPity = false,
                    }
                    seedCounts[seedId] = (seedCounts[seedId] or 0) + 1
                end
            end

            for seedId, addCount in pairs(seedCounts) do
                local current = tonumber(state.seedBag[seedId] or 0) or 0
                if current + addCount > SEED_STACK_MAX then
                    Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "种子背包空间不足，无法开启礼包", requestId = payload.requestId, state = state })
                    return
                end
            end

            state.seedPacks[packId] = owned - openCount
            for _, result in ipairs(results) do
                local seedId = result.seedId
                state.seedBag[seedId] = (tonumber(state.seedBag[seedId] or 0) or 0) + 1
                if result.seedBuff ~= nil and result.seedBuff > 0 then
                    state.seedBagBuffs[seedId] = (tonumber(state.seedBagBuffs[seedId] or 0) or 0) + 1
                end
            end
            state.updatedAt = Now()
            NextRevision(state)

            local title = openCount > 1 and (packCfg.packName .. " x" .. openCount) or packCfg.packName
            local response = {
                success = true,
                message = "开包成功",
                requestId = payload.requestId,
                packId = packId,
                title = title,
                results = results,
                openedCount = openCount,
                openAll = openAll,
                state = state,
            }
            local c = serverCloud:BatchCommit("权威开包")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function()
                    Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, response)
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "开包失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

local function SellHarvested(uid, sellMode, payload, connection)
    if not IsValidSellMode(sellMode) then
        SendError(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, "INVALID_SELL_MODE", "出售方式无效", { requestId = payload and payload.requestId })
        return
    end
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local harvested = state.harvested or {}
            local sold = {}
            local remain = {}
            local total = 0
            local targetIndex = tonumber(payload and payload.index or 0) or 0
            local filter = payload and payload.filter or {}

            local function IsBasicMutated(item)
                local mutation = item and item.mutation
                return mutation ~= nil and (mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil)
            end
            local function IsSpecialMutated(item)
                local specials = item and item.mutation and item.mutation.specials
                return specials ~= nil and #specials > 0
            end
            local function MatchesFilter(item)
                local hasFilter = filter.basicMutation or filter.specialMutation or filter.giant
                if not hasFilter then return not IsBasicMutated(item) and not IsSpecialMutated(item) and item.weightTier ~= "Giant" end
                if filter.basicMutation and IsBasicMutated(item) then return true end
                if filter.specialMutation and IsSpecialMutated(item) then return true end
                if filter.giant and item.weightTier == "Giant" then return true end
                return false
            end

            for index, item in ipairs(harvested) do
                local shouldSell = false
                if sellMode == "all" then
                    shouldSell = true
                elseif sellMode == "index" then
                    shouldSell = index == targetIndex
                elseif sellMode == "filter" then
                    shouldSell = MatchesFilter(item)
                end
                if shouldSell then
                    sold[#sold + 1] = item
                    total = total + math.max(0, math.floor(tonumber(item.price or 0) or 0))
                else
                    remain[#remain + 1] = item
                end
            end

            if #sold <= 0 then
                Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "没有可出售作物", state = state })
                return
            end

            state.harvested = remain
            state.gold = state.gold + total
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "出售成功，获得金币 " .. total, requestId = payload and payload.requestId, total = total, count = #sold, state = state }
            local c = serverCloud:BatchCommit("权威出售")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            RequestGuard.AddToCommit(c, uid, payload and payload._requestRecordKey, response)
            c:Commit({
                ok = function()
                    Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, response)
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "出售失败: " .. tostring(reason), state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason) })
        end,
    })
end

local function ReadRequest(eventData)
    return Shared.ReadEventData(eventData)
end

local function GetStealChance(crop)
    local rarity = crop and crop.rarity or crop and crop.config and crop.config.rarity or "普通"
    local chances = {
        ["普通"] = 0.80,
        ["罕见"] = 0.65,
        ["稀有"] = 0.48,
        ["史诗"] = 0.32,
        ["传奇"] = 0.18,
        ["神话"] = 0.10,
    }
    return chances[rarity] or 0.45
end

local function RollStealReward(crop)
    local seedId = crop and crop.plantIndex or 1
    local chance = GetStealChance(crop)
    if math.random() <= chance then
        return { type = "seed", seedId = seedId, count = 1, chance = chance }
    end
    return { type = "none", chance = chance }
end

local function BuildStealRecordKey(targetUid, cropId)
    return "steal_record_" .. tostring(targetUid) .. "_" .. tostring(cropId or "unknown")
end

local function BuildStealCropClaimKey(cropId)
    return "steal_crop_claim_" .. tostring(cropId or "unknown")
end

local function RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    cropIndex = NormalizePositiveCount(cropIndex or 1, GetMaxCropsPerPlot())
    cropId = tostring(cropId or "")
    if targetUid == nil or targetUid <= 0 then
        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "目标花园无效" })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "不能偷自己的菜" })
        return
    end

    serverCloud.quota:Add(uid, "daily_steal", 1, DAILY_STEAL_LIMIT, "day", 1, {
        ok = function()
            serverCloud:Get(targetUid, Shared.KEYS.AUTH_FARM_STATE, {
                ok = function(scores)
                    local farmState = NormalizeFarmState(scores[Shared.KEYS.AUTH_FARM_STATE])
                    local crop, actualPlotIndex, actualIndex = FindFarmCrop(farmState, cropId)
                    if crop == nil and cropId == "" then
                        local plot = GetFarmPlot(farmState, 1)
                        crop = plot.plants[cropIndex]
                        actualPlotIndex = 1
                        actualIndex = cropIndex
                    end
                    if crop == nil then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "没有找到这株作物" })
                        return
                    end
                    RefreshAuthCrop(crop)
                    local actualCropId = tostring(crop.serverCropId or crop.cropId or cropId)
                    if crop.mature ~= true then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物还没成熟" })
                        return
                    end
                    if crop.stolen == true then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了" })
                        return
                    end

                    local recordKey = BuildStealRecordKey(targetUid, actualCropId)
                    local cropClaimKey = BuildStealCropClaimKey(actualCropId)
                    serverCloud.list:Get(uid, recordKey, {
                        ok = function(records)
                            if records ~= nil and #records > 0 then
                                Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物你已经偷过了", requestId = requestId })
                                return
                            end
                            serverCloud.list:Get(targetUid, cropClaimKey, {
                                ok = function(claimRows)
                                    if claimRows ~= nil and #claimRows > 0 then
                                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了", requestId = requestId })
                                        return
                                    end

                                    local reward = RollStealReward(crop)
                                    local now = Now()
                                    crop.stolen = true
                                    crop.stolenBy = uid
                                    crop.stolenAt = now
                                    crop.stealable = false
                                    crop.stealReward = reward
                                    farmState.updatedAt = now
                                    NextRevision(farmState)

                                    local log = {
                                        thiefUserId = uid,
                                        targetUserId = targetUid,
                                        cropId = actualCropId,
                                        cropIndex = actualIndex,
                                        cropName = crop.name or "作物",
                                        seedId = crop.plantIndex or reward.seedId or 1,
                                        gotSeed = reward.type == "seed",
                                        reward = reward,
                                        stolenAt = now,
                                        time = now,
                                    }

                                    local message = reward.type == "none" and "偷菜成功，但没有获得种子" or "偷菜成功，奖励已发放"
                                    local response = {
                                        success = true,
                                        message = message,
                                        requestId = requestId,
                                        reward = reward,
                                        cropId = actualCropId,
                                        cropIndex = actualIndex,
                                        daily = { limit = DAILY_STEAL_LIMIT },
                                    }
                                    local c = serverCloud:BatchCommit("权威偷菜")
                                    c:ScoreSet(targetUid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                                    c:ListAdd(uid, recordKey, { targetUserId = targetUid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, cropClaimKey, { thiefUserId = uid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, Shared.KEYS.STEAL_LOGS, log)
                                    c:ListAdd(targetUid, Shared.KEYS.RECENT_VISITORS, { userId = uid, visitedAt = now, time = now, action = "steal" })
                                    RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                                    if reward.type == "seed" then
                                        c:ListAdd(uid, Shared.KEYS.SEED_REWARDS, reward)
                                        c:ListAdd(uid, "seed_rewards", reward)
                                    end
                                    c:Commit({
                                        ok = function()
                                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, response)
                                        end,
                                        error = function(_, reason)
                                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜提交失败: " .. tostring(reason), requestId = requestId })
                                        end,
                                    })
                                end,
                                error = function(_, reason)
                                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "作物偷取记录读取失败: " .. tostring(reason), requestId = requestId })
                                end,
                            })
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜记录读取失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "读取目标花园失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function()
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "今日偷菜次数已用完" })
        end,
    })
end

local function SendPlayerProfile(uid, connection)
    if uid == nil then return end
    if GetUserNickname == nil then
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = uid, nickname = "Tap玩家" })
        return
    end
    GetUserNickname({
        userIds = { uid },
        onSuccess = function(nicknames)
            local nickname = "Tap玩家"
            for _, info in ipairs(nicknames or {}) do
                if tostring(info.userId) == tostring(uid) and info.nickname ~= nil and info.nickname ~= "" then
                    nickname = info.nickname
                    break
                end
            end
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = uid, nickname = nickname })
        end,
        onError = function(errorCode)
            print("[玩家资料] 服务端昵称查询失败: " .. tostring(errorCode))
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = uid, nickname = "Tap玩家" })
        end,
    })
end

function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    connections_[GetConnectionKey(connection)] = connection
end

function HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then
        connectionUsers_[GetConnectionKey(connection)] = uid
    end
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local key = GetConnectionKey(connection)
    connections_[key] = nil
    connectionUsers_[key] = nil
end

function HandleGardenClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    connection.scene = scene_
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then SendPlayerProfile(uid, connection) end
    if uid ~= nil then SocialServer.RequestSocialState(uid, connection) end
    if uid ~= nil then RequestEconomyState(uid, connection) end
    if uid ~= nil then RequestAuthFarmState(uid, connection) end
end

function HandleGardenSaveSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SocialServer.SaveGardenSnapshot(uid, data.snapshot, connection) end
end

function HandleGardenRequestSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    SocialServer.RequestGardenSnapshot(uid, tonumber(data.targetUserId or 0) or 0, connection)
end

function HandleGardenRequestRank(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    SocialServer.RequestRank(data.count, connection, uid)
end

function HandleGardenRequestSteal(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "steal", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            RequestSteal(uid, tonumber(data.targetUserId or 0) or 0, data.cropIndex, data.cropId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenRequestSocialState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then SocialServer.RequestSocialState(uid, connection) end
end

function HandleGardenRequestEconomyState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestEconomyState(uid, connection) end
end

function HandleGardenRequestAuthFarm(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestAuthFarmState(uid, connection) end
end

function HandleGardenSaveEconomyState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SaveEconomyState(uid, data.state, connection) end
end

function HandleGardenBuySeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then BuySeed(uid, data.plantIndex, data.price, connection, data.count) end
end

function HandleGardenClearSave(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then ClearPlayerSave(uid, connection) end
end

function HandleGardenPlantSeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "plant", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            PlantSeedAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenHarvestCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "harvest", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            HarvestCropAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenOpenSeedPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "open_pack", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            OpenSeedPackAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenSellHarvested(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "sell", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SellHarvested(uid, data.mode or "all", data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenSendSeedGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "gift", data.requestId, function(recordKey)
            GiftServer.SendSeedGift(uid, data.targetUserId, data.seedId, data.count, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenLikeGarden(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "like", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SocialServer.LikeGarden(uid, data.targetUserId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenRequestGifts(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then GiftServer.RequestGifts(uid, connection) end
end

function HandleGardenClaimGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "claim_gift", data.requestId, function(recordKey)
            GiftServer.ClaimGift(uid, data.giftId, data.seedId, data.count, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function Start()
    math.randomseed(os.time())
    scene_ = Scene()
    GiftServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        dailyGiftLimit = DAILY_GIFT_LIMIT,
        maxGiftCount = MAX_GIFT_COUNT,
        seedStackMax = SEED_STACK_MAX,
        normalizePlantIndex = NormalizePlantIndex,
        normalizeEconomyState = NormalizeEconomyState,
        buildInitialEconomyState = BuildInitialEconomyState,
        nextRevision = NextRevision,
    })
    SocialServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        maxSocialRows = MAX_SOCIAL_ROWS,
        normalizePositiveCount = NormalizePositiveCount,
        buildVisitGardenFromAuthFarm = BuildVisitGardenFromAuthFarm,
    })
    Shared.RegisterServerEvents()
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleGardenClientReady")
    SubscribeToEvent(Shared.EVENTS.SAVE_GARDEN, "HandleGardenSaveSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GARDEN, "HandleGardenRequestSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_RANK, "HandleGardenRequestRank")
    SubscribeToEvent(Shared.EVENTS.REQUEST_STEAL, "HandleGardenRequestSteal")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SOCIAL_STATE, "HandleGardenRequestSocialState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_ECONOMY_STATE, "HandleGardenRequestEconomyState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_AUTH_FARM, "HandleGardenRequestAuthFarm")
    SubscribeToEvent(Shared.EVENTS.SAVE_ECONOMY_STATE, "HandleGardenSaveEconomyState")
    SubscribeToEvent(Shared.EVENTS.BUY_SEED, "HandleGardenBuySeed")
    SubscribeToEvent(Shared.EVENTS.CLEAR_SAVE, "HandleGardenClearSave")
    SubscribeToEvent(Shared.EVENTS.PLANT_SEED, "HandleGardenPlantSeed")
    SubscribeToEvent(Shared.EVENTS.HARVEST_CROP, "HandleGardenHarvestCrop")
    SubscribeToEvent(Shared.EVENTS.OPEN_SEED_PACK, "HandleGardenOpenSeedPack")
    SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED, "HandleGardenSellHarvested")
    SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT, "HandleGardenSendSeedGift")
    SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN, "HandleGardenLikeGarden")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GIFTS, "HandleGardenRequestGifts")
    SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT, "HandleGardenClaimGift")
    print("[社交花园服务端] 权威农场服务已启动")
end
