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

local DAILY_STEAL_LIMIT = 5
local DAILY_STEAL_AD_LIMIT = 5
local DAILY_SEED_PACK_AD_LIMIT = 5
local DAILY_MATURE_AD_LIMIT = 5
local AD_STEAL_BONUS = 5
local AD_RARE_PACK_COUNT = 5
local DAILY_GIFT_LIMIT = 5
local MAX_SOCIAL_ROWS = 20
local START_GOLD = 150
local MAX_OPEN_PACK_COUNT = 50
local MAX_GIFT_COUNT = 1
local GLOBAL_SHOP_UID = 858557875
local SEED_SHOP_REFRESH_INTERVAL = 300
local INCOME_RANK_REFRESH_INTERVAL = 7 * 24 * 60 * 60
local ACTIVITY_RANK_REWARD_TOP = 20
local SEED_SHOP_ITEMS = {
    { name = "胡萝卜", rarity = "普通", guaranteed = true, stock = 50 },
    { name = "玉米", rarity = "普通", guaranteed = true, stock = 50 },
    { name = "番茄", rarity = "普通", chance = 0.80, minStock = 15, maxStock = 30 },
    { name = "葡萄", rarity = "普通", chance = 0.80, minStock = 15, maxStock = 30 },
    { name = "草莓", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "花椰菜", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "南瓜", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "凤梨", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "芒果", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "香蕉", rarity = "罕见", chance = 0.60, minStock = 8, maxStock = 15 },
    { name = "郁金香", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "西瓜", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "蘑菇", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "仙人掌", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "竹子", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "椰子", rarity = "稀有", chance = 0.25, minStock = 3, maxStock = 6 },
    { name = "波斯菊", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
    { name = "向日葵", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
    { name = "辣椒", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
    { name = "百合", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
    { name = "杜鹃", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
    { name = "玉兰", rarity = "史诗", chance = 0.08, minStock = 1, maxStock = 3 },
}

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

local function NormalizeUserId(userId)
    if userId == nil or userId == 0 or userId == "" then return nil end
    local text = tostring(userId)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "0" then return nil end
    local integerText = string.match(text, "^(%-?%d+)%.0+$")
    if integerText ~= nil then return integerText end
    local numericId = tonumber(text)
    if numericId ~= nil and numericId == math.floor(numericId) and math.abs(numericId) < 9007199254740992 then
        return string.format("%.0f", numericId)
    end
    return text
end

local function SameUserId(left, right)
    local leftId = NormalizeUserId(left)
    local rightId = NormalizeUserId(right)
    return leftId ~= nil and rightId ~= nil and leftId == rightId
end

local function GetNicknameRows(response)
    if type(response) ~= "table" then return {} end
    if type(response.nicknames) == "table" then return response.nicknames end
    return response
end

local function GetNicknameMap(userIds, done)
    local map = {}
    local clean = {}
    local seen = {}
    for _, uid in ipairs(userIds or {}) do
        local normalized = NormalizeUserId(uid)
        if normalized ~= nil and seen[normalized] ~= true then
            seen[normalized] = true
            clean[#clean + 1] = normalized
        end
    end
    if GetUserNickname == nil or #clean <= 0 then
        done(map)
        return
    end
    GetUserNickname({
        userIds = clean,
        onSuccess = function(response)
            for _, info in ipairs(GetNicknameRows(response)) do
                local normalized = NormalizeUserId(info.userId)
                local nickname = info.nickname or "Tap玩家"
                if normalized ~= nil then map[normalized] = nickname end
                map[info.userId] = nickname
                map[tostring(info.userId)] = nickname
            end
            done(map)
        end,
        onError = function()
            done(map)
        end,
    })
end

local function SeedShopRefreshId(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    return math.floor(now / SEED_SHOP_REFRESH_INTERVAL)
end

local function SeedShopRefreshRemaining(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local elapsed = now % SEED_SHOP_REFRESH_INTERVAL
    local remaining = SEED_SHOP_REFRESH_INTERVAL - elapsed
    if remaining <= 0 then remaining = SEED_SHOP_REFRESH_INTERVAL end
    return remaining
end

local function GetIncomeRankInfo(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local cycleIndex = math.floor(now / INCOME_RANK_REFRESH_INTERVAL)
    local cycleStart = cycleIndex * INCOME_RANK_REFRESH_INTERVAL
    local cycleEnd = cycleStart + INCOME_RANK_REFRESH_INTERVAL
    return {
        key = Shared.KEYS.INCOME_RANK_PREFIX .. tostring(cycleIndex),
        cycleId = "income_" .. tostring(cycleIndex),
        cycleStart = cycleStart,
        cycleEnd = cycleEnd,
        timeLeft = math.max(0, cycleEnd - now),
    }
end

local function GetActivityRankInfo(activityId, cycleInfo)
    cycleInfo = cycleInfo or (GameConfig.GetActivityCycleInfo and GameConfig.GetActivityCycleInfo(Now())) or { activityId = "sweet", cycleId = "sweet_0", timeLeft = 0 }
    activityId = activityId or cycleInfo.activityId or "sweet"
    return {
        key = Shared.KEYS.ACTIVITY_RANK_PREFIX .. tostring(activityId) .. "_" .. tostring(cycleInfo.cycleId or "0"),
        rewardKey = Shared.KEYS.ACTIVITY_RANK_REWARD_PREFIX .. tostring(activityId) .. "_" .. tostring(cycleInfo.cycleId or "0"),
        cycleId = cycleInfo.cycleId or tostring(activityId) .. "_0",
        activityId = activityId,
        cycleStart = cycleInfo.cycleStart,
        cycleEnd = cycleInfo.cycleEnd,
        timeLeft = cycleInfo.timeLeft or 0,
    }
end

local function BuildSeedShopQuotaKey(refreshId, plantIndex)
    return string.format("seed_shop_%d_%d", math.floor(tonumber(refreshId or 0) or 0), math.floor(tonumber(plantIndex or 0) or 0))
end

local function FindPlantIndexByName(name)
    for index, plant in ipairs(GameConfig.PLANTS or {}) do
        if plant.name == name then return index end
    end
    return nil
end

local function NormalizeSeedShopState(shop)
    shop = type(shop) == "table" and shop or {}
    shop.refreshId = math.floor(tonumber(shop.refreshId or -1) or -1)
    shop.stock = type(shop.stock) == "table" and shop.stock or {}
    shop.items = type(shop.items) == "table" and shop.items or {}
    shop.updatedAt = math.max(0, math.floor(tonumber(shop.updatedAt or 0) or 0))
    return shop
end

local function BuildSeedShopState(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local refreshId = SeedShopRefreshId(now)
    local rngSeed = (refreshId + 73129) % 2147483647
    local function NextRandom()
        rngSeed = (rngSeed * 1103515245 + 12345) % 2147483647
        return rngSeed / 2147483647
    end
    local function RandomInt(minValue, maxValue)
        minValue = math.floor(tonumber(minValue or 0) or 0)
        maxValue = math.floor(tonumber(maxValue or minValue) or minValue)
        if maxValue < minValue then maxValue = minValue end
        return minValue + math.floor(NextRandom() * (maxValue - minValue + 1))
    end
    local stock = {}
    local items = {}
    for _, cfg in ipairs(SEED_SHOP_ITEMS) do
        if FindPlantIndexByName(cfg.name) ~= nil then
            local amount = 0
            if cfg.guaranteed == true then
                amount = math.max(0, math.floor(tonumber(cfg.stock or 0) or 0))
            elseif NextRandom() <= (tonumber(cfg.chance or 0) or 0) then
                amount = RandomInt(cfg.minStock, cfg.maxStock)
            end
            stock[cfg.name] = amount
            if amount > 0 then items[#items + 1] = cfg.name end
        end
    end
    return {
        version = 1,
        refreshId = refreshId,
        interval = SEED_SHOP_REFRESH_INTERVAL,
        stock = stock,
        items = items,
        updatedAt = now,
    }
end

local function AddSeedShopResponseFields(shop, now)
    shop = NormalizeSeedShopState(shop)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    shop.serverTime = now
    shop.nextRefreshAt = (shop.refreshId + 1) * SEED_SHOP_REFRESH_INTERVAL
    shop.nextRefreshIn = math.max(0, shop.nextRefreshAt - now)
    return shop
end

local function EnsureSeedShopState(callback)
    local now = Now()
    local currentRefreshId = SeedShopRefreshId(now)
    serverCloud:Get(GLOBAL_SHOP_UID, Shared.KEYS.SHARED_SEED_SHOP, {
        ok = function(scores)
            local shop = NormalizeSeedShopState(scores[Shared.KEYS.SHARED_SEED_SHOP])
            if shop.refreshId ~= currentRefreshId then
                shop = BuildSeedShopState(now)
                serverCloud:Set(GLOBAL_SHOP_UID, Shared.KEYS.SHARED_SEED_SHOP, shop, {
                    ok = function()
                        callback(AddSeedShopResponseFields(shop, now))
                    end,
                    error = function()
                        callback(AddSeedShopResponseFields(shop, now))
                    end,
                })
            else
                callback(AddSeedShopResponseFields(shop, now))
            end
        end,
        error = function()
            local shop = BuildSeedShopState(now)
            serverCloud:Set(GLOBAL_SHOP_UID, Shared.KEYS.SHARED_SEED_SHOP, shop)
            callback(AddSeedShopResponseFields(shop, now))
        end,
    })
end

local DeepCopy

local function RebuildSeedShopItemsFromStock(shop)
    local items = {}
    local seen = {}
    if type(shop.items) == "table" then
        for _, seedName in ipairs(shop.items) do
            seedName = tostring(seedName)
            local stock = math.max(0, math.floor(tonumber(shop.stock and shop.stock[seedName] or 0) or 0))
            if stock > 0 and seen[seedName] ~= true then
                items[#items + 1] = seedName
                seen[seedName] = true
            end
        end
    end
    if type(shop.stock) == "table" then
        for seedName, stock in pairs(shop.stock) do
            seedName = tostring(seedName)
            stock = math.max(0, math.floor(tonumber(stock or 0) or 0))
            if stock > 0 and seen[seedName] ~= true then
                items[#items + 1] = seedName
                seen[seedName] = true
            end
        end
    end
    shop.items = items
end

local function FetchSeedShopAvailableState(shop, callback)
    local responseShop = AddSeedShopResponseFields(DeepCopy(shop), Now())
    responseShop.stock = type(responseShop.stock) == "table" and responseShop.stock or {}

    local pending = 1
    local completed = false
    local function FinishOne()
        pending = pending - 1
        if pending <= 0 and completed ~= true then
            completed = true
            RebuildSeedShopItemsFromStock(responseShop)
            callback(responseShop)
        end
    end

    for seedName, stock in pairs(responseShop.stock) do
        local plantIndex = FindPlantIndexByName(seedName)
        local maxStock = math.max(0, math.floor(tonumber(stock or 0) or 0))
        responseShop.stock[seedName] = maxStock
        if plantIndex ~= nil and maxStock > 0 then
            pending = pending + 1
            local quotaKey = BuildSeedShopQuotaKey(responseShop.refreshId, plantIndex)
            serverCloud.quota:Get(GLOBAL_SHOP_UID, quotaKey, {
                ok = function(rows)
                    local quotaRow = rows and rows[1]
                    local soldCount = math.max(0, math.floor(tonumber(quotaRow and quotaRow.value or 0) or 0))
                    responseShop.stock[seedName] = math.max(0, maxStock - soldCount)
                    FinishOne()
                end,
                error = function()
                    FinishOne()
                end,
            })
        end
    end

    FinishOne()
end

local function Send(connection, eventName, data)
    Shared.SendToClient(connection, eventName, data)
end

local function BroadcastSeedShopState(shop)
    for _, connection in pairs(connections_) do
        Send(connection, Shared.EVENTS.SEED_SHOP_RESPONSE, { success = true, shop = shop })
    end
end

local function SendFullAvailableSeedShop(connection, eventName, baseData)
    EnsureSeedShopState(function(shop)
        FetchSeedShopAvailableState(shop, function(availableShop)
            local data = baseData or {}
            data.success = data.success ~= false
            data.shop = availableShop
            Send(connection, eventName, data)
        end)
    end)
end

local function BroadcastFullAvailableSeedShop()
    EnsureSeedShopState(function(shop)
        FetchSeedShopAvailableState(shop, function(availableShop)
            BroadcastSeedShopState(availableShop)
        end)
    end)
end

local function SendSeedShopState(connection)
    EnsureSeedShopState(function(shop)
        FetchSeedShopAvailableState(shop, function(availableShop)
            Send(connection, Shared.EVENTS.SEED_SHOP_RESPONSE, { success = true, shop = availableShop })
        end)
    end)
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

DeepCopy = function(value)
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

local function RollRareSeedId()
    local pool = GameConfig.RARITY_PLANT_INDICES and GameConfig.RARITY_PLANT_INDICES["稀有"] or {}
    local filtered = {}
    for _, seedId in ipairs(pool) do
        if not IsLimitedSeed(seedId) then filtered[#filtered + 1] = seedId end
    end
    if #filtered == 0 then filtered = pool end
    if #filtered == 0 then return 7 end
    return filtered[math.random(1, #filtered)]
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
    if r < 0.34 then return RandomRange(0.65, 0.9), "Light" end
    if r < 0.94 then return RandomRange(0.9, 1.2), "Normal" end
    if r < 0.99 then return RandomRange(1.2, 2.0), "Large" end
    return RandomRange(2.0, 3.5), "Giant"
end

local function RandItem(list)
    if list == nil or #list <= 0 then return nil end
    return list[math.random(1, #list)]
end

local function IsSpecialAllowedForNormalRoll(special)
    if special == nil then return false end
    return special.exclusiveActivity == nil
end

local function RandNormalSpecialMutation()
    local pool = {}
    for _, special in ipairs(GameConfig.SPECIAL_MUTATIONS or {}) do
        if IsSpecialAllowedForNormalRoll(special) then
            table.insert(pool, special)
        end
    end
    return RandItem(pool)
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
        local special = CloneSpecialMutation(RandNormalSpecialMutation())
        if special ~= nil then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
            mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
        end
    end
    if #mutation.specials == 1 and math.random() <= doubleChance then
        local special = CloneSpecialMutation(RandNormalSpecialMutation())
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

local function CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
    local priceBase = math.max(1, tonumber(plant.seedPrice or plant.fruitPrice or 1) or 1)
    local mutationMultiplier = mutation and mutation.priceMultiplier or 1.0
    return math.floor(math.min(priceBase * (weightMultiplier or 1.0) * mutationMultiplier, priceBase * 200) + 0.5)
end

local function RecalculateAuthoritativeItemPrice(item)
    if type(item) ~= "table" then return end
    local plant = GameConfig.PLANTS[tonumber(item.plantIndex or 0) or 0]
    if plant == nil then return end
    local baseWeight = math.max(0.001, tonumber(item.baseWeight or plant.baseWeight or 1.0) or 1.0)
    local weight = tonumber(item.weight or baseWeight) or baseWeight
    local weightRatio = weight / baseWeight
    local weightMultiplier = math.min(math.max(weightRatio * weightRatio, 0.4), 12.0)
    item.baseWeight = baseWeight
    item.weight = weight
    item.weightMultiplier = weightMultiplier
    item.price = CalculateAuthoritativeCropPrice(plant, weightMultiplier, item.mutation)
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
    local price = CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
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
    for _, plot in pairs(state.plots) do
        plot.plants = type(plot.plants) == "table" and plot.plants or {}
        for _, crop in ipairs(plot.plants) do
            RecalculateAuthoritativeItemPrice(crop)
        end
    end
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
        avatar = snapshot and snapshot.avatar or nil,
        visitablePlotIndex = plotIndex,
        unlockedPlotCount = snapshot and snapshot.unlockedPlotCount or 1,
        tourValue = tourValue,
        bestTourValue = bestTourValue,
        likeCount = 0,
        updatedAt = Now(),
        plot = { plotIndex = plotIndex, plants = plants },
    }
end

local NormalizeTalentState = nil
local NormalizeProgressionState = nil
local NormalizeDailyTaskState = nil
local NormalizeActivityState = nil

local function NormalizeEconomyState(state)
    state = type(state) == "table" and state or {}
    state.gold = math.max(0, math.floor(tonumber(state.gold or START_GOLD) or START_GOLD))
    state.seedBag = CopyNumericKeyMap(state.seedBag)
    state.seedBagBuffs = CopyNumericKeyMap(state.seedBagBuffs)
    state.harvested = type(state.harvested) == "table" and state.harvested or {}
    for _, item in ipairs(state.harvested) do
        RecalculateAuthoritativeItemPrice(item)
    end
    state.seedPacks = type(state.seedPacks) == "table" and state.seedPacks or {}
    state.collectedPlants = CopyNumericKeyMap(state.collectedPlants)
    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
    state.tutorial.plantGuideDone = state.tutorial.plantGuideDone == true
    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
    state.talent = NormalizeTalentState(state.talent)
    state.progression = NormalizeProgressionState(state.progression)
    state.activity = NormalizeActivityState(state.activity)
    state.updatedAt = Now()
    return state
end

local TALENT_LEVEL_EXP_TABLE = {
    [1]  = 30, [2]  = 50, [3]  = 80, [4]  = 120, [5]  = 170,
    [6]  = 230, [7]  = 300, [8]  = 380, [9]  = 470, [10] = 570,
    [11] = 680, [12] = 800, [13] = 940, [14] = 1100, [15] = 1280,
    [16] = 1480, [17] = 1700, [18] = 1950, [19] = 2230, [20] = 2550,
    [21] = 2900, [22] = 3280, [23] = 3700, [24] = 4160, [25] = 4660,
    [26] = 5200, [27] = 5780, [28] = 6400, [29] = 7060,
}
local TALENT_MAX_LEVEL = 30
local RARITY_BASE_EXP = { ["普通"] = 5, ["罕见"] = 10, ["稀有"] = 18, ["史诗"] = 30, ["传奇"] = 50 }
local TALENT_CONFIG = {
    { id = "drop_rate_1", cost = 1, goldCost = 500, requires = nil }, { id = "drop_rate_2", cost = 1, goldCost = 2000, requires = "drop_rate_1" }, { id = "drop_rate_3", cost = 2, goldCost = 8000, requires = "drop_rate_2" }, { id = "drop_rate_4", cost = 2, goldCost = 30000, requires = "drop_rate_3" }, { id = "drop_rate_5", cost = 3, goldCost = 100000, requires = "drop_rate_4" },
    { id = "grow_speed_1", cost = 1, goldCost = 800, requires = nil }, { id = "grow_speed_2", cost = 1, goldCost = 3000, requires = "grow_speed_1" }, { id = "grow_speed_3", cost = 2, goldCost = 12000, requires = "grow_speed_2" }, { id = "grow_speed_4", cost = 2, goldCost = 50000, requires = "grow_speed_3" }, { id = "grow_speed_5", cost = 3, goldCost = 160000, requires = "grow_speed_4" },
    { id = "sell_bonus_1", cost = 1, goldCost = 1000, requires = nil }, { id = "sell_bonus_2", cost = 1, goldCost = 4000, requires = "sell_bonus_1" }, { id = "sell_bonus_3", cost = 2, goldCost = 16000, requires = "sell_bonus_2" }, { id = "sell_bonus_4", cost = 2, goldCost = 70000, requires = "sell_bonus_3" }, { id = "sell_bonus_5", cost = 3, goldCost = 220000, requires = "sell_bonus_4" },
    { id = "mutation_1", cost = 1, goldCost = 1200, requires = nil }, { id = "mutation_2", cost = 1, goldCost = 5000, requires = "mutation_1" }, { id = "mutation_3", cost = 2, goldCost = 20000, requires = "mutation_2" }, { id = "mutation_4", cost = 2, goldCost = 90000, requires = "mutation_3" }, { id = "mutation_5", cost = 3, goldCost = 300000, requires = "mutation_4" },
    { id = "bag_capacity_1", cost = 1, goldCost = 600, requires = nil }, { id = "bag_capacity_2", cost = 1, goldCost = 2500, requires = "bag_capacity_1" }, { id = "bag_capacity_3", cost = 2, goldCost = 10000, requires = "bag_capacity_2" }, { id = "bag_capacity_4", cost = 2, goldCost = 40000, requires = "bag_capacity_3" }, { id = "bag_capacity_5", cost = 3, goldCost = 120000, requires = "bag_capacity_4" },
}
local DAILY_REWARD_PACK_WEIGHTS = {
    { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 32 },
    { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 9 },
    { packId = "pack_legendary", weight = 2 },
}
local SYNTHESIS_MAP = { pack_common = "pack_uncommon", pack_uncommon = "pack_rare", pack_rare = "pack_epic", pack_epic = "pack_legendary" }
local COMMISSION_STATE_KEY = "garden_commission_state_v1"
local COMMISSION_REFRESH_INTERVAL = 30 * 60
local COMMISSION_COUNT = 4
local COMMISSION_CUSTOMERS = { "露露", "阿麦", "青木", "莓莓", "小枫", "云朵商人", "花园旅人", "星屑收藏家" }
local COMMISSION_COLOR_REQUIREMENTS = { "yellow", "blue", "red", "white", "purple", "black" }
local COMMISSION_SPECIAL_REQUIREMENTS = { "wet", "frozen", "cloud", "chocolate", "pollen", "glow", "stardust", "ceramic", "rainbow", "void", "gold" }
local COMMISSION_PACK_DIFFICULTY = {
    pack_common = { mutationKinds = { "basic" }, minWeightScale = { 0.90, 1.20 } },
    pack_uncommon = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.00, 1.40 } },
    pack_rare = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.05, 1.55 } },
    pack_epic = { mutationKinds = { "color", "special" }, minWeightScale = { 1.35, 2.20 } },
    pack_legendary = { mutationKinds = { "special", "giant" }, minWeightScale = { 2.00, 3.60 } },
}
local COMMISSION_REWARD_POOLS = {
    ["普通"] = { { packId = "pack_common", weight = 94 }, { packId = "pack_uncommon", weight = 6 } },
    ["罕见"] = { { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 55 }, { packId = "pack_rare", weight = 10 } },
    ["稀有"] = { { packId = "pack_common", weight = 18 }, { packId = "pack_uncommon", weight = 30 }, { packId = "pack_rare", weight = 45 }, { packId = "pack_epic", weight = 7 } },
    ["史诗"] = { { packId = "pack_common", weight = 8 }, { packId = "pack_uncommon", weight = 18 }, { packId = "pack_rare", weight = 32 }, { packId = "pack_epic", weight = 38 }, { packId = "pack_legendary", weight = 4 } },
    ["传奇"] = { { packId = "pack_common", weight = 3 }, { packId = "pack_uncommon", weight = 10 }, { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 40 }, { packId = "pack_legendary", weight = 25 } },
}

local function BuildInitialEconomyState()
    return NormalizeEconomyState({
        gold = START_GOLD,
        seedBag = { [1] = 6, [21] = 4, [2] = 2 },
        seedBagBuffs = {},
        harvested = {},
        seedPacks = { pack_common = 1 },
        tutorial = { plantGuideDone = false },
        dailyTaskState = { progress = { plant = 0, harvest = 0, sell = 0 }, rewardClaimed = false },
        talent = { unlockedTalents = {}, talentPoints = 1, level = 1, exp = 0 },
        progression = { unlockedPlotCount = 1, gardenLevel = 1, currentTourValue = 0, bestTourValue = 0 },
        activity = nil,
    })
end

NormalizeTalentState = function(talent)
    talent = type(talent) == "table" and talent or {}
    talent.unlockedTalents = type(talent.unlockedTalents) == "table" and talent.unlockedTalents or {}
    talent.talentPoints = math.max(0, math.floor(tonumber(talent.talentPoints or 1) or 1))
    talent.level = Clamp(math.floor(tonumber(talent.level or 1) or 1), 1, TALENT_MAX_LEVEL)
    talent.exp = math.max(0, math.floor(tonumber(talent.exp or 0) or 0))
    return talent
end

local DEFAULT_HARVEST_BAG_CAPACITY = 20
local MAX_HARVEST_BAG_CAPACITY = 100
local BAG_CAPACITY_BONUSES = {
    bag_capacity_1 = 15,
    bag_capacity_2 = 15,
    bag_capacity_3 = 15,
    bag_capacity_4 = 15,
    bag_capacity_5 = 20,
}

local function GetHarvestBagCapacityFromState(state)
    local talent = NormalizeTalentState(state and state.talent)
    local bonus = 0
    for talentId, value in pairs(BAG_CAPACITY_BONUSES) do
        if talent.unlockedTalents[talentId] == true then
            bonus = bonus + value
        end
    end
    return math.min(MAX_HARVEST_BAG_CAPACITY, DEFAULT_HARVEST_BAG_CAPACITY + bonus)
end

NormalizeProgressionState = function(progression)
    progression = type(progression) == "table" and progression or {}
    progression.unlockedPlotCount = Clamp(math.floor(tonumber(progression.unlockedPlotCount or 1) or 1), 1, (GameConfig.CONFIG.GridCols or 1) * (GameConfig.CONFIG.GridRows or 1))
    progression.gardenLevel = math.max(1, math.floor(tonumber(progression.gardenLevel or progression.unlockedPlotCount) or progression.unlockedPlotCount))
    progression.currentTourValue = math.max(0, math.floor(tonumber(progression.currentTourValue or 0) or 0))
    progression.bestTourValue = math.max(tonumber(progression.bestTourValue or 0) or 0, progression.currentTourValue)
    return progression
end

local function SyncProgressionTourValueFromFarm(state, farmState)
    if type(state) ~= "table" then return 0 end
    state.progression = NormalizeProgressionState(state.progression)
    local tourValue = CalculateAuthFarmTourValue(farmState)
    state.progression.currentTourValue = tourValue
    state.progression.bestTourValue = math.max(tonumber(state.progression.bestTourValue or 0) or 0, tourValue)
    return tourValue
end

local function AddTourRankCommit(commit, uid, state)
    local progression = NormalizeProgressionState(state and state.progression)
    local score = math.max(0, math.floor(tonumber(progression.currentTourValue or 0) or 0))
    commit:ScoreSetInt(uid, Shared.KEYS.TOUR_RANK, score)
end

local function GetActivityRankScore(activityId, activity)
    activity = NormalizeActivityState(activity)
    if activityId == "sweet" then
        return math.max(0, math.floor(tonumber(activity.sweet and activity.sweet.submitted or 0) or 0))
    elseif activityId == "alien" then
        return math.max(0, math.floor(tonumber(activity.alien and activity.alien.totalGenes or 0) or 0))
    elseif activityId == "dark" then
        local dark = activity.dark or {}
        return math.max(0, math.floor(tonumber(dark.darkSeedDrops or 0) or 0))
    end
    return 0
end

local function AddActivityRankCommit(commit, uid, state)
    local activity = NormalizeActivityState(state and state.activity)
    local activityId = activity.activeId or (GameConfig.GetActiveActivityId and GameConfig.GetActiveActivityId(Now())) or "sweet"
    local info = GetActivityRankInfo(activityId, { activityId = activityId, cycleId = activity.cycleId, timeLeft = 0 })
    commit:ScoreSetInt(uid, info.key, GetActivityRankScore(activityId, activity))
end

local function AddIncomeRankCommit(commit, uid, amount)
    amount = math.max(0, math.floor(tonumber(amount or 0) or 0))
    if amount <= 0 then return end
    commit:ScoreAddInt(uid, GetIncomeRankInfo().key, amount)
end

NormalizeDailyTaskState = function(daily)
    daily = type(daily) == "table" and daily or {}
    daily.progress = type(daily.progress) == "table" and daily.progress or { plant = 0, harvest = 0, sell = 0 }
    daily.progress.plant = math.max(0, math.floor(tonumber(daily.progress.plant or 0) or 0))
    daily.progress.harvest = math.max(0, math.floor(tonumber(daily.progress.harvest or 0) or 0))
    daily.progress.sell = math.max(0, math.floor(tonumber(daily.progress.sell or 0) or 0))
    daily.rewardClaimed = daily.rewardClaimed == true
    return daily
end

local function NewActivityState(cycleInfo)
    cycleInfo = cycleInfo or (GameConfig.GetActivityCycleInfo and GameConfig.GetActivityCycleInfo(Now())) or {}
    return {
        cycleId = cycleInfo.cycleId or "unknown_0",
        activeId = cycleInfo.activityId or "sweet",
        sweet = { value = 0, submitted = 0, exchanged = {} },
        alien = { genes = 0, totalGenes = 0, drawCount = 0 },
        dark = { devourHarvestCount = 0, darkSeedDrops = 0 },
    }
end

NormalizeActivityState = function(activity)
    local cycleInfo = GameConfig.GetActivityCycleInfo and GameConfig.GetActivityCycleInfo(Now()) or { activityId = "sweet", cycleId = "sweet_0" }
    activity = type(activity) == "table" and activity or {}
    if activity.cycleId ~= cycleInfo.cycleId then
        activity = NewActivityState(cycleInfo)
    end
    activity.cycleId = cycleInfo.cycleId
    activity.activeId = cycleInfo.activityId
    activity.sweet = type(activity.sweet) == "table" and activity.sweet or {}
    activity.sweet.value = math.max(0, math.floor(tonumber(activity.sweet.value or 0) or 0))
    activity.sweet.submitted = math.max(0, math.floor(tonumber(activity.sweet.submitted or 0) or 0))
    activity.sweet.exchanged = type(activity.sweet.exchanged) == "table" and activity.sweet.exchanged or {}
    activity.alien = type(activity.alien) == "table" and activity.alien or {}
    activity.alien.genes = math.max(0, math.floor(tonumber(activity.alien.genes or 0) or 0))
    activity.alien.totalGenes = math.max(0, math.floor(tonumber(activity.alien.totalGenes or 0) or 0))
    activity.alien.drawCount = math.max(0, math.floor(tonumber(activity.alien.drawCount or 0) or 0))
    activity.dark = type(activity.dark) == "table" and activity.dark or {}
    activity.dark.devourHarvestCount = math.max(0, math.floor(tonumber(activity.dark.devourHarvestCount or 0) or 0))
    activity.dark.darkSeedDrops = math.max(0, math.floor(tonumber(activity.dark.darkSeedDrops or 0) or 0))
    return activity
end

local function FindTalentConfig(talentId)
    for _, talent in ipairs(TALENT_CONFIG) do
        if talent.id == talentId then return talent end
    end
    return nil
end

local function GetLevelUpTalentPoints(level)
    return level >= 16 and 2 or 1
end

local function AddServerHarvestExp(state, rarity, priceMultiplier)
    state.talent = NormalizeTalentState(state.talent)
    local talent = state.talent
    if talent.level >= TALENT_MAX_LEVEL then return 0 end
    local baseExp = RARITY_BASE_EXP[rarity] or 5
    local exp = math.max(1, math.floor(baseExp * math.min(priceMultiplier or 1.0, 5.0) + 0.5))
    talent.exp = talent.exp + exp
    while talent.level < TALENT_MAX_LEVEL do
        local needed = TALENT_LEVEL_EXP_TABLE[talent.level]
        if needed == nil or talent.exp < needed then break end
        talent.exp = talent.exp - needed
        talent.level = talent.level + 1
        talent.talentPoints = talent.talentPoints + GetLevelUpTalentPoints(talent.level)
    end
    if talent.level >= TALENT_MAX_LEVEL then talent.exp = 0 end
    state.progression = NormalizeProgressionState(state.progression)
    state.progression.gardenLevel = math.max(state.progression.gardenLevel or 1, talent.level)
    return exp
end

local function GetActiveActivityId()
    return GameConfig.GetActiveActivityId and GameConfig.GetActiveActivityId(Now()) or "sweet"
end

local function GetCurrentActivityCycleInfo()
    if GameConfig.GetActivityCycleInfo then
        return GameConfig.GetActivityCycleInfo(Now())
    end
    return { activityId = GetActiveActivityId(), cycleId = "sweet_0", cycleIndex = 0, timeLeft = 0 }
end

local function GetPreviousActivityCycleInfo()
    local current = GetCurrentActivityCycleInfo()
    local duration = math.max(1, math.floor(tonumber(current.duration or ((GameConfig.ACTIVITY_CONFIG and GameConfig.ACTIVITY_CONFIG.cycleDays or 3) * 86400)) or 1))
    local previousTime = math.max(0, math.floor(tonumber(current.cycleStart or Now()) or Now()) - 1)
    if previousTime <= 0 then return nil end
    if GameConfig.GetActivityCycleInfo then
        return GameConfig.GetActivityCycleInfo(previousTime)
    end
    return { activityId = GetActiveActivityId(previousTime), cycleId = "sweet_0", cycleIndex = 0, timeLeft = duration }
end

local function GetActivityConfig(activityId)
    return ((GameConfig.ACTIVITY_CONFIG or {}).activities or {})[activityId]
end

local function HasSpecialMutation(item, key)
    local specials = item and item.mutation and item.mutation.specials
    if type(specials) ~= "table" then return false end
    for _, special in ipairs(specials) do
        if special.key == key then return true end
    end
    return false
end

local function GetRarityOrder(rarity)
    return (GameConfig.RARITY_ORDER or {})[rarity or "普通"] or 1
end

local function GetSweetSubmitValue(item)
    if item == nil then return 0 end
    if not HasSpecialMutation(item, "candy") and not HasSpecialMutation(item, "honey") then return 0 end
    local rarityOrder = GetRarityOrder(item.rarity)
    local base = 5 + rarityOrder * 4 + math.floor((tonumber(item.price or 0) or 0) / 1300)
    if HasSpecialMutation(item, "honey") then base = math.floor(base * 1.2 + 0.5) end
    if item.weightTier == "Giant" then base = math.floor(base * 1.12 + 0.5) end
    return math.max(3, base)
end

local function FindSweetReward(rewardId)
    local activity = GetActivityConfig("sweet")
    for _, reward in ipairs(activity and activity.exchangeRewards or {}) do
        if reward.id == rewardId then return reward end
    end
    return nil
end

local function GetDarkSeedWeight(plantIndex)
    local plant = GameConfig.PLANTS and GameConfig.PLANTS[plantIndex]
    local weights = { 55, 32, 16, 7, 3 }
    return weights[GetRarityOrder(plant and plant.rarity)] or 1
end

local function RollDarkSeed(activity)
    local pool = activity and activity.darkSeedPool or { 42, 43, 44, 45, 46, 47 }
    local weightedPool = {}
    for _, plantIndex in ipairs(pool) do
        weightedPool[#weightedPool + 1] = { plantIndex = plantIndex, weight = GetDarkSeedWeight(plantIndex) }
    end
    local picked = RollWeighted(weightedPool)
    return picked and picked.plantIndex or pool[1]
end

local function ApplyActivityHarvestReward(state, crop)
    local activityId = GetActiveActivityId()
    local activity = GetActivityConfig(activityId)
    if activity == nil or crop == nil then return nil end
    state.activity = NormalizeActivityState(state.activity)
    local rarityOrder = GetRarityOrder(crop.rarity)
    if activityId == "alien" then
        local chance = ({ 0.30, 0.40, 0.55, 0.70, 1.0 })[rarityOrder] or 0.30
        if math.random() <= chance then
            local minValue = math.max(1, rarityOrder)
            local maxValue = math.max(minValue, rarityOrder + 2)
            local amount = math.random(minValue, maxValue)
            local specials = crop.mutation and crop.mutation.specials
            if type(specials) == "table" and #specials > 0 then amount = amount + 1 end
            state.activity.alien.genes = state.activity.alien.genes + amount
            state.activity.alien.totalGenes = state.activity.alien.totalGenes + amount
            local text = "获得外星基因 x" .. tostring(amount)
            return { type = "alien_gene", amount = amount, activityId = activityId, toastText = text, message = text }
        end
    elseif activityId == "dark" and (HasSpecialMutation(crop, "devour") or HasSpecialMutation(crop, "void")) then
        state.activity.dark.devourHarvestCount = state.activity.dark.devourHarvestCount + 1
        local rates = activity.darkSeedDropRates or { 0.08, 0.12, 0.18, 0.28, 0.45 }
        if math.random() <= (rates[rarityOrder] or 0.08) then
            local plantIndex = RollDarkSeed(activity)
            local current = tonumber(state.seedBag[plantIndex] or 0) or 0
            state.seedBag[plantIndex] = current + 1
            state.collectedPlants[plantIndex] = true
            state.activity.dark.darkSeedDrops = state.activity.dark.darkSeedDrops + 1
            local plant = GameConfig.PLANTS[plantIndex]
            local text = "黑暗来临掉落: " .. (plant and (plant.name .. "种子") or "限定种子")
            return { type = "dark_seed", plantIndex = plantIndex, activityId = activityId, toastText = text, message = text }
        end
    end
    return nil
end

local function BuildExpansionRequirement(plotIndex)
    local requirements = GameConfig.CONFIG and GameConfig.CONFIG.LAND_UNLOCK_REQUIREMENTS or nil
    if requirements ~= nil and requirements[plotIndex] ~= nil then
        return requirements[plotIndex]
    end
    local sightReq = GameConfig.CONFIG and GameConfig.CONFIG.LAND_UNLOCK_SIGHT_REQUIREMENTS or nil
    local tableReq = {
        [2] = { level = 2, gold = 600, tour = sightReq and sightReq[2] or 180 }, [3] = { level = 4, gold = 2200, tour = sightReq and sightReq[3] or 550 },
        [4] = { level = 6, gold = 7500, tour = sightReq and sightReq[4] or 1300 }, [5] = { level = 9, gold = 25000, tour = sightReq and sightReq[5] or 3000 },
        [6] = { level = 12, gold = 85000, tour = sightReq and sightReq[6] or 6500 }, [7] = { level = 16, gold = 260000, tour = sightReq and sightReq[7] or 13000 },
        [8] = { level = 21, gold = 780000, tour = sightReq and sightReq[8] or 25000 }, [9] = { level = 26, gold = 2200000, tour = sightReq and sightReq[9] or 45000 },
    }
    return tableReq[plotIndex] or { level = math.max(1, plotIndex), gold = 3000 * plotIndex * plotIndex, tour = 600 * plotIndex * plotIndex }
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

local function BuySeed(uid, plantIndex, _price, connection, count, requestId, refreshId)
    plantIndex = NormalizePlantIndex(plantIndex)
    count = NormalizePositiveCount(count or 1)
    if plantIndex == nil then
        SendError(connection, Shared.EVENTS.BUY_SEED_RESPONSE, "INVALID_PLANT", "种子配置不存在", { requestId = requestId })
        return
    end
    local plant = GameConfig.PLANTS[plantIndex]
    local price = math.max(0, math.floor(tonumber(plant.seedPrice or 0) or 0))
    EnsureSeedShopState(function(shop)
        if refreshId ~= nil and math.floor(tonumber(refreshId or 0) or 0) ~= shop.refreshId then
            SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "商店已刷新，请重新购买", requestId = requestId })
            return
        end
        local maxStock = math.max(0, math.floor(tonumber(shop.stock[plant.name] or 0) or 0))
        if maxStock <= 0 then
            SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄", requestId = requestId })
            return
        end

        local quotaKey = BuildSeedShopQuotaKey(shop.refreshId, plantIndex)
        serverCloud.quota:Get(GLOBAL_SHOP_UID, quotaKey, {
            ok = function(rows)
                local quotaRow = rows and rows[1]
                local soldCount = math.max(0, math.floor(tonumber(quotaRow and quotaRow.value or 0) or 0))
                local available = math.max(0, maxStock - soldCount)
                if available <= 0 then
                    SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄", requestId = requestId })
                    BroadcastFullAvailableSeedShop()
                    return
                end

                serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                    ok = function(scores)
                        local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                        local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
                        local buyCount = math.min(count, available)
                        if buyCount <= 0 then
                            SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "库存不足", requestId = requestId, state = state })
                            return
                        end
                        local totalPrice = price * buyCount
                        if state.gold < totalPrice then
                            buyCount = math.min(buyCount, math.floor(state.gold / price))
                            totalPrice = price * buyCount
                        end
                        if buyCount <= 0 then
                            SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "金币不足", requestId = requestId, state = state })
                            return
                        end

                        state.gold = state.gold - totalPrice
                        state.seedBag[plantIndex] = owned + buyCount
                        state.updatedAt = Now()
                        NextRevision(state)

                        local c = serverCloud:BatchCommit("全服商店原子购买种子")
                        c:QuotaAdd(GLOBAL_SHOP_UID, quotaKey, buyCount, maxStock)
                        c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                        c:Commit({
                            ok = function()
                                SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = true, message = "购买成功 x" .. tostring(buyCount), requestId = requestId, plantIndex = plantIndex, price = totalPrice, count = buyCount, state = state })
                                BroadcastFullAvailableSeedShop()
                            end,
                            error = function(_, reason)
                                SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄或购买失败: " .. tostring(reason), requestId = requestId, state = state })
                                BroadcastFullAvailableSeedShop()
                            end,
                        })
                    end,
                    error = function(_, reason)
                        SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = requestId })
                    end,
                })
            end,
            error = function(_, reason)
                SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "库存读取失败: " .. tostring(reason), requestId = requestId })
            end,
        })
    end)
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
                    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
                    state.tutorial.plantGuideDone = true
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.plant = math.min(99, (state.dailyTaskState.progress.plant or 0) + 1)
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    SyncProgressionTourValueFromFarm(state, farmState)
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
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
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
                    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
                    state.tutorial.plantGuideDone = true
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.plant = math.min(99, (state.dailyTaskState.progress.plant or 0) + 1)
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    SyncProgressionTourValueFromFarm(state, farmState)
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
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
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
            local function SendHarvestFailure(message, extra)
                local data = extra or {}
                data.success = false
                data.message = message
                data.requestId = payload.requestId
                data.farm = farmState
                print(string.format("[权威收获] 拒绝 requestId=%s cropId=%s plot=%s cropIndex=%s reason=%s", tostring(payload.requestId), tostring(payload.cropId), tostring(payload.plotIndex), tostring(payload.cropIndex), tostring(message)))
                Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, data)
            end
            local crop, plotIndex, cropIndex = FindFarmCropFromHarvestPayload(farmState, payload)
            if crop == nil then
                SendHarvestFailure("作物不存在或已收获")
                return
            end
            RefreshAuthCrop(crop)
            print(string.format("[权威收获] 请求 requestId=%s uid=%s plot=%s cropIndex=%s cropId=%s now=%d plantedAt=%s matureAt=%s elapsed=%.2f growTime=%.2f mature=%s",
                tostring(payload.requestId),
                tostring(uid),
                tostring(plotIndex),
                tostring(cropIndex),
                tostring(crop.cropId or crop.serverCropId),
                Now(),
                tostring(crop.plantedAt),
                tostring(crop.matureAt),
                tonumber(crop.elapsed or 0) or 0,
                tonumber(crop.growTime or 0) or 0,
                tostring(crop.mature)))
            if crop.harvested == true then
                SendHarvestFailure("这株作物已经收获过了", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
                return
            end
            if crop.mature ~= true then
                SendHarvestFailure("作物尚未成熟", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
                return
            end

            serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                ok = function(scores)
                    local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                    state.harvested = state.harvested or {}
                    local harvestBagCapacity = GetHarvestBagCapacityFromState(state)
                    if #(state.harvested) >= harvestBagCapacity then
                        SendHarvestFailure("背包已满，出售作物或点天赋扩容", {
                            state = state,
                            cropId = crop.cropId or crop.serverCropId,
                            plotIndex = plotIndex,
                            cropIndex = cropIndex,
                            bagCount = #state.harvested,
                            bagCapacity = harvestBagCapacity,
                        })
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
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.harvest = math.min(99, (state.dailyTaskState.progress.harvest or 0) + 1)
                    local exp = AddServerHarvestExp(state, crop.rarity, crop.mutation and crop.mutation.priceMultiplier or 1.0)
                    local droppedPack = RollHarvestDropPack(crop.rarity)
                    if droppedPack ~= nil and GameConfig.SEED_PACK_CONFIG[droppedPack] ~= nil then
                        state.seedPacks[droppedPack] = (tonumber(state.seedPacks[droppedPack] or 0) or 0) + 1
                    end
                    local activityReward = ApplyActivityHarvestReward(state, harvestItem)
                    state.collectedPlants = state.collectedPlants or {}
                    if crop.plantIndex ~= nil then state.collectedPlants[crop.plantIndex] = true end
                    state.updatedAt = Now()
                    NextRevision(state)

                    local plot = GetFarmPlot(farmState, plotIndex)
                    table.remove(plot.plants, cropIndex)
                    SyncProgressionTourValueFromFarm(state, farmState)
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
                        activityReward = activityReward,
                        exp = exp,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("权威收获")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
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
            state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
            state.dailyTaskState.progress.sell = math.min(99, (state.dailyTaskState.progress.sell or 0) + 1)
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "出售成功，获得金币 " .. total, requestId = payload and payload.requestId, total = total, count = #sold, state = state }
            local c = serverCloud:BatchCommit("权威出售")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            AddIncomeRankCommit(c, uid, total)
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

local function FindMutationByKey(list, key)
    if list == nil then return nil end
    for _, item in ipairs(list) do
        if item.key == key then return item end
    end
    return nil
end

local function IsCommissionEligiblePlant(plant)
    return plant ~= nil and plant.limited ~= true and plant.activityTag == nil
end

local function PickCommissionPlantIndex(level)
    local rarityPool = { "普通" }
    if level >= 21 then rarityPool = { "普通", "罕见", "稀有", "史诗", "传奇" }
    elseif level >= 16 then rarityPool = { "普通", "罕见", "稀有", "史诗" }
    elseif level >= 11 then rarityPool = { "普通", "罕见", "稀有" }
    elseif level >= 6 then rarityPool = { "普通", "罕见" } end
    local pool = {}
    for _, rarity in ipairs(rarityPool) do
        local indices = GameConfig.RARITY_PLANT_INDICES and GameConfig.RARITY_PLANT_INDICES[rarity] or {}
        for _, plantIndex in ipairs(indices) do
            if IsCommissionEligiblePlant(GameConfig.PLANTS[plantIndex]) then pool[#pool + 1] = plantIndex end
        end
    end
    return pool[math.random(1, math.max(1, #pool))] or 1
end

local function GetCommissionRewardPack(plant)
    local pool = COMMISSION_REWARD_POOLS[plant and plant.rarity or "普通"] or COMMISSION_REWARD_POOLS["普通"]
    local picked = RollWeighted(pool)
    return picked and picked.packId or "pack_common"
end

local function BuildCommissionMutationRequirement(packId)
    local difficulty = COMMISSION_PACK_DIFFICULTY[packId] or COMMISSION_PACK_DIFFICULTY.pack_rare
    local kind = RandItem(difficulty.mutationKinds)
    if kind == "color" then
        local key = RandItem(COMMISSION_COLOR_REQUIREMENTS)
        local mutation = FindMutationByKey(GameConfig.COLOR_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "颜色变异" }
    elseif kind == "special" then
        local key = RandItem(COMMISSION_SPECIAL_REQUIREMENTS)
        local mutation = FindMutationByKey(GameConfig.SPECIAL_MUTATIONS, key)
        return { kind = kind, key = key, name = mutation and mutation.name or "特殊变异" }
    elseif kind == "giant" then
        return { kind = kind, key = "Giant", name = "巨大作物" }
    end
    return { kind = "basic", key = "basic", name = "任意基础变异" }
end

local function BuildCommission(index, level)
    local plantIndex = PickCommissionPlantIndex(level)
    local plant = GameConfig.PLANTS[plantIndex]
    local rewardPackId = GetCommissionRewardPack(plant)
    local difficulty = COMMISSION_PACK_DIFFICULTY[rewardPackId] or COMMISSION_PACK_DIFFICULTY.pack_rare
    local scale = difficulty.minWeightScale
    local minWeight = (plant and plant.baseWeight or 1.0) * RandomRange(scale[1], scale[2])
    local packCfg = GameConfig.SEED_PACK_CONFIG[rewardPackId]
    return {
        id = string.format("commission_%d_%d_%d", Now(), index, math.random(1000, 9999)),
        customer = RandItem(COMMISSION_CUSTOMERS),
        plantIndex = plantIndex,
        plantName = plant and plant.name or "作物",
        plantRarity = plant and plant.rarity or "普通",
        mutation = BuildCommissionMutationRequirement(rewardPackId),
        minWeight = minWeight,
        rewardPackId = rewardPackId,
        rewardPackName = packCfg and packCfg.packName or "普通种子包",
        completed = false,
    }
end

local function NormalizeCommissionState(state, level)
    state = type(state) == "table" and state or {}
    local now = Now()
    local lastRefresh = tonumber(state.lastRefreshRealTime or 0) or 0
    state.commissions = type(state.commissions) == "table" and state.commissions or {}
    if #state.commissions == 0 or now - lastRefresh >= COMMISSION_REFRESH_INTERVAL then
        state.commissions = {}
        for i = 1, COMMISSION_COUNT do state.commissions[#state.commissions + 1] = BuildCommission(i, level or 1) end
        state.lastRefreshRealTime = now
        state.timer = COMMISSION_REFRESH_INTERVAL
    else
        state.timer = math.max(0, COMMISSION_REFRESH_INTERVAL - (now - lastRefresh))
    end
    return state
end

local function HasColorMutation(item, key)
    local colorMutation = item and item.mutation and item.mutation.colorMutation
    return colorMutation ~= nil and colorMutation.key == key
end

local function HasSpecialMutation(item, key)
    local specials = item and item.mutation and item.mutation.specials
    if specials == nil then return false end
    for _, special in ipairs(specials) do if special.key == key then return true end end
    return false
end

local function HasBasicMutation(item)
    local mutation = item and item.mutation
    return mutation ~= nil and (mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil)
end

local function CommissionItemMatches(commission, item)
    if commission == nil or item == nil then return false end
    if item.plantIndex ~= commission.plantIndex then return false end
    if (item.weight or 0) < (commission.minWeight or 0) then return false end
    local req = commission.mutation
    if req == nil then return true end
    if req.kind == "color" then return HasColorMutation(item, req.key) end
    if req.kind == "special" then return HasSpecialMutation(item, req.key) end
    if req.kind == "giant" then return item.weightTier == "Giant" end
    if req.kind == "basic" then return HasBasicMutation(item) end
    return true
end

local function RequestCommissionsAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local economy = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            serverCloud:Get(uid, COMMISSION_STATE_KEY, {
                ok = function(rows)
                    local commissionState = NormalizeCommissionState(rows[COMMISSION_STATE_KEY], economy.talent and economy.talent.level or 1)
                    serverCloud:Set(uid, COMMISSION_STATE_KEY, commissionState)
                    Send(connection, Shared.EVENTS.COMMISSIONS_RESPONSE, { success = true, requestId = payload.requestId, commission = commissionState })
                end,
                error = function()
                    local commissionState = NormalizeCommissionState(nil, economy.talent and economy.talent.level or 1)
                    serverCloud:Set(uid, COMMISSION_STATE_KEY, commissionState)
                    Send(connection, Shared.EVENTS.COMMISSIONS_RESPONSE, { success = true, requestId = payload.requestId, commission = commissionState })
                end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.COMMISSIONS_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function CompleteCommissionAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local economy = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            serverCloud:Get(uid, COMMISSION_STATE_KEY, {
                ok = function(rows)
                    local commissionState = NormalizeCommissionState(rows[COMMISSION_STATE_KEY], economy.talent and economy.talent.level or 1)
                    local commission = nil
                    for _, row in ipairs(commissionState.commissions or {}) do
                        if row.id == payload.commissionId then commission = row; break end
                    end
                    local itemIndex = math.floor(tonumber(payload.itemIndex or 0) or 0)
                    local item = itemIndex > 0 and economy.harvested[itemIndex] or nil
                    if commission == nil then Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "委托不存在", requestId = payload.requestId, state = economy, commission = commissionState }); return end
                    if commission.completed then Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "委托已完成", requestId = payload.requestId, state = economy, commission = commissionState }); return end
                    if item == nil then Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "作物已不存在", requestId = payload.requestId, state = economy, commission = commissionState }); return end
                    if not CommissionItemMatches(commission, item) then Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "作物不满足委托条件", requestId = payload.requestId, state = economy, commission = commissionState }); return end
                    table.remove(economy.harvested, itemIndex)
                    economy.seedPacks[commission.rewardPackId] = (tonumber(economy.seedPacks[commission.rewardPackId] or 0) or 0) + 1
                    commission.completed = true
                    economy.updatedAt = Now()
                    NextRevision(economy)
                    local message = string.format("完成%s的委托，获得%s", commission.customer or "客人", commission.rewardPackName or "种子包")
                    local response = { success = true, message = message, requestId = payload.requestId, state = economy, commission = commissionState }
                    local c = serverCloud:BatchCommit("权威委托")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, economy)
                    c:ScoreSet(uid, COMMISSION_STATE_KEY, commissionState)
                    c:Commit({
                        ok = function() Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, response) end,
                        error = function(_, reason) Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "委托提交失败: " .. tostring(reason), requestId = payload.requestId, state = economy, commission = commissionState }) end,
                    })
                end,
                error = function(_, reason) Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "委托数据读取失败: " .. tostring(reason), requestId = payload.requestId, state = economy }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function SubmitActivityCropAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            if GetActiveActivityId() ~= "sweet" then
                Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "当前不是甜蜜蜜活动", requestId = payload.requestId, state = state })
                return
            end
            local itemIndex = math.floor(tonumber(payload.itemIndex or 0) or 0)
            local item = itemIndex > 0 and state.harvested[itemIndex] or nil
            local value = GetSweetSubmitValue(item)
            if item == nil or value <= 0 then
                Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "请选择糖果或蜂蜜变异作物", requestId = payload.requestId, state = state })
                return
            end
            table.remove(state.harvested, itemIndex)
            state.activity = NormalizeActivityState(state.activity)
            state.activity.sweet.value = state.activity.sweet.value + value
            state.activity.sweet.submitted = state.activity.sweet.submitted + value
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "上交成功，甜蜜值 +" .. value, requestId = payload.requestId, value = value, state = state }
            local c = serverCloud:BatchCommit("活动作物上交")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            AddActivityRankCommit(c, uid, state)
            RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "上交失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function ExchangeActivityRewardAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            if GetActiveActivityId() ~= "sweet" then
                Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "当前不是甜蜜蜜活动", requestId = payload.requestId, state = state })
                return
            end
            local reward = FindSweetReward(tostring(payload.rewardId or ""))
            if reward == nil then
                Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励不存在", requestId = payload.requestId, state = state })
                return
            end
            state.activity = NormalizeActivityState(state.activity)
            local claimed = tonumber(state.activity.sweet.exchanged[reward.id] or 0) or 0
            if reward.limit ~= nil and claimed >= reward.limit then
                Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "已兑换完", requestId = payload.requestId, state = state })
                return
            end
            if state.activity.sweet.value < reward.cost then
                Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "甜蜜值不足", requestId = payload.requestId, state = state })
                return
            end
            state.activity.sweet.value = state.activity.sweet.value - reward.cost
            state.activity.sweet.exchanged[reward.id] = claimed + 1
            if reward.type == "seed" then
                local plantIndex = NormalizePlantIndex(reward.plantIndex)
                if plantIndex == nil then Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励种子不存在", requestId = payload.requestId, state = state }); return end
                local current = tonumber(state.seedBag[plantIndex] or 0) or 0
                state.seedBag[plantIndex] = current + (reward.count or 1)
                state.collectedPlants[plantIndex] = true
            elseif reward.type == "pack" then
                if not IsValidPackId(reward.packId) then Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "奖励种子包不存在", requestId = payload.requestId, state = state }); return end
                state.seedPacks[reward.packId] = (tonumber(state.seedPacks[reward.packId] or 0) or 0) + (reward.count or 1)
            end
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "兑换成功: " .. tostring(reward.name or "奖励"), requestId = payload.requestId, reward = reward, state = state }
            local c = serverCloud:BatchCommit("活动奖励兑换")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "兑换失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function DrawActivityPackAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            if GetActiveActivityId() ~= "alien" then
                Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "当前不是外星基因活动", requestId = payload.requestId, state = state })
                return
            end
            local activity = GetActivityConfig("alien")
            local drawCount = NormalizePositiveCount(payload.count or 1, 10)
            drawCount = drawCount >= 10 and 10 or 1
            local cost = drawCount >= 10 and (activity.drawCostTen or 95) or (activity.drawCost or 10)
            state.activity = NormalizeActivityState(state.activity)
            if state.activity.alien.genes < cost then
                Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "外星基因不足", requestId = payload.requestId, state = state })
                return
            end
            state.activity.alien.genes = state.activity.alien.genes - cost
            state.activity.alien.drawCount = state.activity.alien.drawCount + drawCount
            local rewards = {}
            for _ = 1, drawCount do
                local picked = RollWeighted(activity.drawPool)
                if picked ~= nil then
                    local reward = { type = picked.type, packId = picked.packId, plantIndex = picked.plantIndex, count = picked.count or 1, name = picked.name }
                    if picked.type == "pack" and IsValidPackId(picked.packId) then
                        state.seedPacks[picked.packId] = (tonumber(state.seedPacks[picked.packId] or 0) or 0) + (picked.count or 1)
                        rewards[#rewards + 1] = reward
                    elseif picked.type == "seed" then
                        local plantIndex = NormalizePlantIndex(picked.plantIndex)
                        if plantIndex ~= nil then
                            local current = tonumber(state.seedBag[plantIndex] or 0) or 0
                            local addCount = math.max(0, math.floor(tonumber(picked.count or 1) or 1))
                            state.seedBag[plantIndex] = current + addCount
                            state.collectedPlants[plantIndex] = true
                            reward.count = addCount
                            rewards[#rewards + 1] = reward
                        end
                    end
                end
            end
            if #rewards <= 0 then
                state.activity.alien.genes = state.activity.alien.genes + cost
                state.activity.alien.drawCount = math.max(0, state.activity.alien.drawCount - drawCount)
                Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "未抽中奖励", requestId = payload.requestId, state = state })
                return
            end
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "基因抽取完成", requestId = payload.requestId, rewards = rewards, state = state }
            local c = serverCloud:BatchCommit("活动基因抽取")
            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
            RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function() Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "抽取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function MatureAllCropsInPlot(farmState, plotIndex)
    local plot = GetFarmPlot(farmState, plotIndex)
    local changed = 0
    local now = Now()
    for _, crop in ipairs(plot.plants or {}) do
        if crop.harvested ~= true and crop.mature ~= true then
            crop.elapsed = math.max(tonumber(crop.growTime or 1) or 1, 1)
            crop.mature = true
            crop.matureAt = now
            crop.stealable = crop.stolen ~= true
            changed = changed + 1
        end
    end
    return changed
end

local function GrantAdReward(uid, payload, connection)
    payload = payload or {}
    local rewardType = tostring(payload.rewardType or "")
    if rewardType == "steal_attempts" then
        serverCloud.quota:Get(uid, "daily_steal_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= DAILY_STEAL_AD_LIMIT then
                    Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日偷取次数广告已达上限", requestId = payload.requestId, rewardType = rewardType, daily = { stealAdCount = watched, stealAdLimit = DAILY_STEAL_AD_LIMIT } })
                    return
                end
                local response = { success = true, message = "偷取次数 +" .. tostring(AD_STEAL_BONUS), requestId = payload.requestId, rewardType = rewardType, daily = { stealAdCount = watched + 1, stealAdLimit = DAILY_STEAL_AD_LIMIT, limit = DAILY_STEAL_LIMIT + (watched + 1) * AD_STEAL_BONUS } }
                local c = serverCloud:BatchCommit("广告奖励：偷取次数")
                c:QuotaAdd(uid, "daily_steal_ad", 1, DAILY_STEAL_AD_LIMIT, "day", 1)
                c:QuotaAdd(uid, "daily_steal_ad_bonus", AD_STEAL_BONUS, DAILY_STEAL_AD_LIMIT * AD_STEAL_BONUS, "day", 1)
                RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                c:Commit({
                    ok = function() Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, response); SocialServer.RequestSocialState(uid, connection) end,
                    error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "奖励发放失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "rare_seed_pack" then
        serverCloud.quota:Get(uid, "daily_seed_pack_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= DAILY_SEED_PACK_AD_LIMIT then
                    Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日广告种子包已领取完", requestId = payload.requestId, rewardType = rewardType, daily = { seedPackAdCount = watched, seedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT } })
                    return
                end
                serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                    ok = function(scores)
                        local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                        state.seedPacks.pack_rare = (tonumber(state.seedPacks.pack_rare or 0) or 0) + AD_RARE_PACK_COUNT
                        state.updatedAt = Now()
                        NextRevision(state)
                        local response = { success = true, message = "获得稀有种子包 x" .. tostring(AD_RARE_PACK_COUNT), requestId = payload.requestId, rewardType = rewardType, state = state, rewards = { { packId = "pack_rare", count = AD_RARE_PACK_COUNT } }, daily = { seedPackAdCount = watched + 1, seedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT } }
                        local c = serverCloud:BatchCommit("广告奖励：稀有种子包")
                        c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                        c:QuotaAdd(uid, "daily_seed_pack_ad", 1, DAILY_SEED_PACK_AD_LIMIT, "day", 1)
                        RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                        c:Commit({
                            ok = function() Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, response); SocialServer.RequestSocialState(uid, connection) end,
                            error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "奖励发放失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, state = state }) end,
                        })
                    end,
                    error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "mature_plot" then
        local plotIndex = NormalizePlotIndex(payload.plotIndex)
        serverCloud.quota:Get(uid, "daily_mature_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= DAILY_MATURE_AD_LIMIT then
                    Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日快速成熟广告已达上限", requestId = payload.requestId, rewardType = rewardType, daily = { matureAdCount = watched, matureAdLimit = DAILY_MATURE_AD_LIMIT } })
                    return
                end
                serverCloud:Get(uid, Shared.KEYS.AUTH_FARM_STATE, {
                    ok = function(farmScores)
                        local farmState = NormalizeFarmState(farmScores[Shared.KEYS.AUTH_FARM_STATE])
                        local changed = MatureAllCropsInPlot(farmState, plotIndex)
                        if changed <= 0 then
                            Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "该地块没有可加速成熟的作物", requestId = payload.requestId, rewardType = rewardType, farm = farmState, daily = { matureAdCount = watched, matureAdLimit = DAILY_MATURE_AD_LIMIT } })
                            return
                        end
                        serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                            ok = function(scores)
                                local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                                SyncProgressionTourValueFromFarm(state, farmState)
                                farmState.updatedAt = Now()
                                NextRevision(farmState)
                                state.updatedAt = Now()
                                NextRevision(state)
                                local response = { success = true, message = "地块作物已全部成熟", requestId = payload.requestId, rewardType = rewardType, plotIndex = plotIndex, maturedCount = changed, farm = farmState, state = state, daily = { matureAdCount = watched + 1, matureAdLimit = DAILY_MATURE_AD_LIMIT } }
                                local c = serverCloud:BatchCommit("广告奖励：快速成熟")
                                c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                                c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                                c:QuotaAdd(uid, "daily_mature_ad", 1, DAILY_MATURE_AD_LIMIT, "day", 1)
                                AddTourRankCommit(c, uid, state)
                                RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                                c:Commit({
                                    ok = function() Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, response) end,
                                    error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "快速成熟失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, farm = farmState }) end,
                                })
                            end,
                            error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, farm = farmState }) end,
                        })
                    end,
                    error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "读取农场失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告奖励类型无效", requestId = payload.requestId, rewardType = rewardType })
end

local function ClaimDailyRewardAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local daily = NormalizeDailyTaskState(state.dailyTaskState)
            local completed = (daily.progress.plant or 0) >= 3 and (daily.progress.harvest or 0) >= 3 and (daily.progress.sell or 0) >= 1
            if not completed or daily.rewardClaimed then
                Send(connection, Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = daily.rewardClaimed and "今日奖励已领取" or "每日任务未完成", requestId = payload.requestId, state = state })
                return
            end
            daily.rewardClaimed = true
            local rewards = {}
            for _ = 1, 3 do
                local picked = RollWeighted(DAILY_REWARD_PACK_WEIGHTS)
                state.seedPacks[picked.packId] = (tonumber(state.seedPacks[picked.packId] or 0) or 0) + 1
                rewards[#rewards + 1] = picked.packId
            end
            state.dailyTaskState = daily
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "每日奖励已领取", requestId = payload.requestId, rewards = rewards, state = state }
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = "领取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function SynthesizePackAuthority(uid, payload, connection)
    local packId = tostring(payload.packId or "")
    local targetId = SYNTHESIS_MAP[packId]
    if targetId == nil then
        Send(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "该种子包不可合成", requestId = payload.requestId })
        return
    end
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedPacks[packId] or 0) or 0
            if owned < 3 then
                Send(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "需要 3 个同品级种子包", requestId = payload.requestId, state = state })
                return
            end
            state.seedPacks[packId] = owned - 3
            state.seedPacks[targetId] = (tonumber(state.seedPacks[targetId] or 0) or 0) + 1
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "合成成功", requestId = payload.requestId, packId = packId, targetId = targetId, state = state }
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "合成失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function UnlockTalentAuthority(uid, payload, connection)
    local talentId = tostring(payload.talentId or "")
    local talentCfg = FindTalentConfig(talentId)
    if talentCfg == nil then
        Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋不存在", requestId = payload.requestId })
        return
    end
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local talent = NormalizeTalentState(state.talent)
            if talent.unlockedTalents[talentId] == true then
                Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋已解锁", requestId = payload.requestId, state = state })
                return
            end
            if talentCfg.requires ~= nil and talent.unlockedTalents[talentCfg.requires] ~= true then
                Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "需要先解锁前置天赋", requestId = payload.requestId, state = state })
                return
            end
            if talent.talentPoints < talentCfg.cost then
                Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋点不足", requestId = payload.requestId, state = state })
                return
            end
            if state.gold < (talentCfg.goldCost or 0) then
                Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "金币不足", requestId = payload.requestId, state = state })
                return
            end
            talent.talentPoints = talent.talentPoints - talentCfg.cost
            talent.unlockedTalents[talentId] = true
            state.gold = state.gold - (talentCfg.goldCost or 0)
            state.talent = talent
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "天赋已解锁", requestId = payload.requestId, talentId = talentId, state = state }
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, response) end,
                error = function(_, reason) Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "解锁失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function ExpandPlotAuthority(uid, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local progression = NormalizeProgressionState(state.progression)
            local maxPlots = (GameConfig.CONFIG.GridCols or 1) * (GameConfig.CONFIG.GridRows or 1)
            if progression.unlockedPlotCount >= maxPlots then
                Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "已扩展到最大地块", requestId = payload.requestId, state = state })
                return
            end
            local nextPlot = progression.unlockedPlotCount + 1
            local requirement = BuildExpansionRequirement(nextPlot)
            if (state.talent.level or 1) < requirement.level then
                Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "等级不足", requestId = payload.requestId, state = state })
                return
            end
            if state.gold < requirement.gold then
                Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "金币不足", requestId = payload.requestId, state = state })
                return
            end
            serverCloud:Get(uid, Shared.KEYS.AUTH_FARM_STATE, {
                ok = function(farmScores)
                    local farmState = NormalizeFarmState(farmScores[Shared.KEYS.AUTH_FARM_STATE])
                    SyncProgressionTourValueFromFarm(state, farmState)
                    progression = NormalizeProgressionState(state.progression)
                    if (progression.bestTourValue or progression.currentTourValue or 0) < requirement.tour then
                        Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "观光值不足", requestId = payload.requestId, state = state })
                        return
                    end
                    state.gold = state.gold - requirement.gold
                    progression.unlockedPlotCount = nextPlot
                    progression.gardenLevel = math.max(progression.gardenLevel or 1, nextPlot)
                    state.progression = progression
                    state.updatedAt = Now()
                    NextRevision(state)
                    GetFarmPlot(farmState, nextPlot)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)
                    local response = { success = true, message = "扩地成功", requestId = payload.requestId, plotIndex = nextPlot, state = state, farm = farmState }
                    local c = serverCloud:BatchCommit("权威扩地")
                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    c:ScoreSet(uid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                    c:Commit({
                        ok = function() Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, response) end,
                        error = function(_, reason) Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "扩地失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
                    })
                end,
                error = function(_, reason) Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "农场数据读取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

local function ReadRequest(eventData)
    return Shared.ReadEventData(eventData)
end

local function ResolveLeaderboardInfo(kind, activityId)
    kind = tostring(kind or "income")
    if kind == "tour" then
        return { kind = "tour", key = Shared.KEYS.TOUR_RANK, title = "观光排行榜", resetMode = "never" }
    elseif kind == "like" then
        return { kind = "like", key = Shared.KEYS.LIKE_COUNT, title = "点赞排行榜", resetMode = "never" }
    elseif kind == "activity" then
        local cycleInfo = GetCurrentActivityCycleInfo()
        local info = GetActivityRankInfo(activityId or cycleInfo.activityId, cycleInfo)
        info.kind = "activity"
        info.title = ((GetActivityConfig(info.activityId) or {}).name or "活动") .. "排行榜"
        info.resetMode = "activity_cycle"
        return info
    end
    local info = GetIncomeRankInfo()
    info.kind = "income"
    info.title = "收入排行榜"
    info.resetMode = "7d"
    return info
end

local function GetRankItemScore(item, key)
    if item == nil then return 0 end
    if type(item.iscore) == "table" then
        return math.max(0, math.floor(tonumber(item.iscore[key] or 0) or 0))
    end
    return math.max(0, math.floor(tonumber(item.score or item.value or 0) or 0))
end

local function AddPreviousActivityRewardStatus(uid, data, done)
    if data.kind ~= "activity" then
        done(data)
        return
    end
    local previousCycleInfo = GetPreviousActivityCycleInfo()
    if previousCycleInfo == nil then
        data.previousRewardEligible = false
        data.previousRewardClaimed = false
        done(data)
        return
    end
    local previousInfo = GetActivityRankInfo(previousCycleInfo.activityId, previousCycleInfo)
    data.previousActivityId = previousInfo.activityId
    data.previousCycleId = previousInfo.cycleId
    data.previousCycleStart = previousInfo.cycleStart
    data.previousCycleEnd = previousInfo.cycleEnd
    serverCloud:GetUserRank(uid, previousInfo.key, {
        ok = function(previousRank, previousScore)
            previousScore = math.max(0, math.floor(tonumber(previousScore or 0) or 0))
            data.previousRank = previousRank
            data.previousScore = previousScore
            data.previousRewardEligible = previousRank ~= nil and previousRank <= ACTIVITY_RANK_REWARD_TOP and previousScore > 0
            serverCloud:Get(uid, previousInfo.rewardKey, {
                ok = function(scores)
                    data.previousRewardClaimed = type(scores[previousInfo.rewardKey]) == "table"
                    done(data)
                end,
                error = function()
                    data.previousRewardClaimed = false
                    done(data)
                end,
            })
        end,
        error = function()
            data.previousRank = nil
            data.previousScore = 0
            data.previousRewardEligible = false
            data.previousRewardClaimed = false
            done(data)
        end,
    })
end

local function SendLeaderboardWithMyRank(uid, connection, requestId, info, list)
    serverCloud:GetUserRank(uid, info.key, {
        ok = function(myRank, myScore)
            local function SendWithRewardStatus(rewardClaimed)
                local data = {
                    success = true,
                    requestId = requestId,
                    kind = info.kind,
                    activityId = info.activityId,
                    cycleId = info.cycleId,
                    cycleStart = info.cycleStart,
                    cycleEnd = info.cycleEnd,
                    timeLeft = info.timeLeft,
                    resetMode = info.resetMode,
                    title = info.title,
                    list = list,
                    myRank = myRank,
                    myScore = math.max(0, math.floor(tonumber(myScore or 0) or 0)),
                    rewardEligible = info.kind == "activity" and myRank ~= nil and myRank <= ACTIVITY_RANK_REWARD_TOP,
                    rewardClaimed = rewardClaimed == true,
                }
                AddPreviousActivityRewardStatus(uid, data, function(response)
                    Send(connection, Shared.EVENTS.LEADERBOARD_RESPONSE, response)
                end)
            end
            if info.kind ~= "activity" then
                SendWithRewardStatus(false)
                return
            end
            serverCloud:Get(uid, info.rewardKey, {
                ok = function(scores)
                    SendWithRewardStatus(type(scores[info.rewardKey]) == "table")
                end,
                error = function()
                    SendWithRewardStatus(false)
                end,
            })
        end,
        error = function()
            local data = { success = true, requestId = requestId, kind = info.kind, activityId = info.activityId, cycleId = info.cycleId, resetMode = info.resetMode, title = info.title, list = list, myRank = nil, myScore = 0 }
            AddPreviousActivityRewardStatus(uid, data, function(response)
                Send(connection, Shared.EVENTS.LEADERBOARD_RESPONSE, response)
            end)
        end,
    })
end

local function RequestLeaderboardAuthority(uid, payload, connection)
    payload = payload or {}
    local info = ResolveLeaderboardInfo(payload.kind, payload.activityId)
    local count = NormalizePositiveCount(payload.count or 20, 50)
    serverCloud:GetRankList(info.key, 1, count, {
        ok = function(rankList)
            local userIds = {}
            local result = {}
            for i, item in ipairs(rankList or {}) do
                local userId = item.userId or item.player
                if userId ~= nil then
                    userIds[#userIds + 1] = userId
                    result[#result + 1] = {
                        rank = i,
                        userId = userId,
                        nickname = "Tap玩家",
                        score = GetRankItemScore(item, info.key),
                        isMe = tostring(userId) == tostring(uid),
                    }
                end
            end
            GetNicknameMap(userIds, function(nickMap)
                SocialServer.FetchGardenProfiles(userIds, function(profileMap)
                    for _, entry in ipairs(result) do
                        local profile = profileMap[tostring(entry.userId)] or {}
                        entry.nickname = profile.nickname or nickMap[entry.userId] or nickMap[tostring(entry.userId)] or entry.nickname
                        entry.avatar = profile.avatar
                    end
                    SendLeaderboardWithMyRank(uid, connection, payload.requestId, info, result)
                end)
            end)
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.LEADERBOARD_RESPONSE, { success = false, requestId = payload.requestId, kind = payload.kind, activityId = payload.activityId, message = "排行榜读取失败: " .. tostring(reason) })
        end,
    })
end

local function PickLockedAvatar(unlocked)
    unlocked = type(unlocked) == "table" and unlocked or {}
    local locked = {}
    for index, _ in ipairs(GameConfig.PLANTS or {}) do
        local avatarId = "plant_" .. tostring(index)
        if unlocked[avatarId] ~= true and unlocked[tostring(index)] ~= true and unlocked[index] ~= true then
            locked[#locked + 1] = index
        end
    end
    if #locked <= 0 then return nil end
    return locked[math.random(1, #locked)]
end

local function ClaimActivityRankRewardAuthority(uid, payload, connection)
    payload = payload or {}
    local cycleInfo = GetPreviousActivityCycleInfo()
    if cycleInfo == nil then
        Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, message = "没有上期活动奖励可领" })
        return
    end
    local info = GetActivityRankInfo(cycleInfo.activityId, cycleInfo)
    serverCloud:GetUserRank(uid, info.key, {
        ok = function(rank, score)
            score = math.max(0, math.floor(tonumber(score or 0) or 0))
            if rank == nil or rank > ACTIVITY_RANK_REWARD_TOP or score <= 0 then
                Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期没有进入活动榜前20，没有奖励可领" })
                return
            end
            serverCloud:Get(uid, info.rewardKey, {
                ok = function(rewardRows)
                    if type(rewardRows[info.rewardKey]) == "table" then
                        Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期活动排行奖励已领取" })
                        return
                    end
                    local avatarIndex = PickLockedAvatar(payload.unlockedAvatars)
                    local reward = avatarIndex ~= nil and { type = "avatar", avatarIndex = avatarIndex, avatarId = "plant_" .. tostring(avatarIndex) } or { type = "none" }
                    local message = avatarIndex ~= nil and "上期活动排行奖励：解锁头像" or "已拥有全部头像，本次不发放头像奖励"
                    serverCloud:Set(uid, info.rewardKey, { claimedAt = Now(), rank = rank, score = score, reward = reward }, {
                        ok = function()
                            local response = { success = true, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, rank = rank, score = score, reward = reward, message = message }
                            RequestGuard.Record(uid, payload._requestRecordKey, response)
                            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "奖励领取失败: " .. tostring(reason) })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "奖励状态读取失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期排名读取失败: " .. tostring(reason) })
        end,
    })
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

local function RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
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
                            serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                                ok = function(economyRows)
                                    local economy = NormalizeEconomyState(economyRows[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                                    if reward.type == "seed" then
                                        local seedId = NormalizePlantIndex(reward.seedId or crop.plantIndex or 1) or 1
                                        local current = tonumber(economy.seedBag[seedId] or 0) or 0
                                        economy.seedBag[seedId] = current + 1
                                        economy.collectedPlants[seedId] = true
                                        reward.seedId = seedId
                                    end

                                    local now = Now()
                                    crop.stolen = true
                                    crop.stolenBy = uid
                                    crop.stolenAt = now
                                    crop.stealable = false
                                    crop.stealReward = reward
                                    farmState.updatedAt = now
                                    NextRevision(farmState)
                                    economy.updatedAt = now
                                    NextRevision(economy)

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

                                    local message = "偷菜成功，但没有获得种子"
                                    if reward.type == "seed" then
                                        message = "偷菜成功，奖励已发放"
                                    end
                                    local response = {
                                        success = true,
                                        message = message,
                                        requestId = requestId,
                                        reward = reward,
                                        cropId = actualCropId,
                                        cropIndex = actualIndex,
                                        daily = { stealCountDelta = 1, limit = stealLimit or DAILY_STEAL_LIMIT },
                                        state = economy,
                                    }
                                    local c = serverCloud:BatchCommit("权威偷菜")
                                    c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, economy)
                                    c:ScoreSet(targetUid, Shared.KEYS.AUTH_FARM_STATE, farmState)
                                    c:ListAdd(uid, recordKey, { targetUserId = targetUid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, cropClaimKey, { thiefUserId = uid, cropId = actualCropId, stolenAt = now })
                                    c:ListAdd(targetUid, Shared.KEYS.STEAL_LOGS, log)
                                    c:QuotaAdd(uid, "daily_steal", 1, DAILY_STEAL_LIMIT, "day", 1)
                                    RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                                    c:Commit({
                                        ok = function()
                                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, response)
                                        end,
                                        error = function(_, reason)
                                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜失败: " .. tostring(reason), requestId = requestId, state = economy })
                                        end,
                                    })
                                end,
                                error = function(_, reason)
                                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = requestId })
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
end

local function RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    serverCloud.quota:Get(uid, "daily_steal_ad_bonus", {
        ok = function(bonusRows)
            local bonusRow = bonusRows and bonusRows[1]
            local bonus = math.max(0, math.floor(tonumber(bonusRow and bonusRow.value or 0) or 0))
            local stealLimit = DAILY_STEAL_LIMIT + bonus
            serverCloud.quota:Get(uid, "daily_steal", {
                ok = function(quotaRows)
                    local row = quotaRows and quotaRows[1]
                    local stealCount = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                    if stealCount >= stealLimit then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, {
                            success = false,
                            code = "STEAL_LIMIT_REACHED",
                            message = "偷取次数不足",
                            requestId = requestId,
                            daily = { stealCount = stealCount, limit = stealLimit },
                        })
                        return
                    end
                    RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜次数上限读取失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

local function SendPlayerProfile(uid, connection)
    if uid == nil then return end
    if GetUserNickname == nil then
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = "Tap玩家" })
        return
    end
    GetUserNickname({
        userIds = { uid },
        onSuccess = function(response)
            local nickname = "Tap玩家"
            for _, info in ipairs(GetNicknameRows(response)) do
                if SameUserId(info.userId, uid) and info.nickname ~= nil and info.nickname ~= "" then
                    nickname = info.nickname
                    break
                end
            end
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = nickname })
        end,
        onError = function(errorCode)
            print("[玩家资料] 服务端昵称查询失败: " .. tostring(errorCode))
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = "Tap玩家" })
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
    SendSeedShopState(connection)
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
    if uid ~= nil then
        RequestGuard.Check(uid, "visit", data.requestId, function(recordKey)
            SocialServer.RequestGardenSnapshot(uid, tonumber(data.targetUserId or 0) or 0, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.GARDEN_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenRequestRank(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    SocialServer.RequestRank(data.count, connection, uid)
end

function HandleGardenRequestLeaderboard(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestLeaderboardAuthority(uid, data, connection)
    end
end

function HandleGardenClaimActivityRankReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "activity_rank_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            ClaimActivityRankRewardAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
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

function HandleGardenRequestSeedShop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    SendSeedShopState(connection)
end

function HandleGardenRequestAuthFarm(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestAuthFarmState(uid, connection) end
end

function HandleGardenRequestAdReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "ad_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            GrantAdReward(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenBuySeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then BuySeed(uid, data.plantIndex, data.price, connection, data.count, data.requestId, data.refreshId) end
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

function HandleGardenRequestCommissions(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then RequestCommissionsAuthority(uid, data, connection) end
end

function HandleGardenCompleteCommission(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then CompleteCommissionAuthority(uid, data, connection) end
end

function HandleGardenSubmitActivityCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "submit_activity_crop", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SubmitActivityCropAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenExchangeActivityReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "exchange_activity_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            ExchangeActivityRewardAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenDrawActivityPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "draw_activity_pack", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            DrawActivityPackAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenClaimDailyReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then ClaimDailyRewardAuthority(uid, data, connection) end
end

function HandleGardenSynthesizePack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SynthesizePackAuthority(uid, data, connection) end
end

function HandleGardenUnlockTalent(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then UnlockTalentAuthority(uid, data, connection) end
end

function HandleGardenExpandPlot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then ExpandPlotAuthority(uid, data, connection) end
end

function HandleGardenSendSeedGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "gift", data.requestId, function(recordKey)
            GiftServer.SendSeedGift(uid, data.targetUserId, data.seedId, data.count, connection, data.requestId, recordKey, data.profile)
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

function HandleGardenSendFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "friend_request", data.requestId, function(recordKey)
            SocialServer.SendFriendRequest(uid, data.targetUserId, connection, data.requestId, recordKey, data.profile)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenRespondFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "friend_respond", data.requestId, function(recordKey)
            SocialServer.RespondFriendRequest(uid, data.requestIdValue, data.fromUserId, data.accepted == true, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function HandleGardenRemoveFriend(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "remove_friend", data.requestId, function(recordKey)
            SocialServer.RemoveFriend(uid, data.friendUserId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId, friendUserId = data.friendUserId })
        end)
    end
end

function HandleGardenClearSocialMessages(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "clear_social_messages", data.requestId, function(recordKey)
            SocialServer.ClearSocialMessages(uid, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
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

local function PickGiftSeedId()
    local pool = {}
    local allowed = { ["普通"] = true, ["罕见"] = true, ["稀有"] = true, ["史诗"] = true }
    for seedId, plant in ipairs(GameConfig.PLANTS or {}) do
        if plant ~= nil and allowed[plant.rarity] == true then
            pool[#pool + 1] = seedId
        end
    end
    if #pool <= 0 then return 1 end
    return pool[math.random(1, #pool)]
end

function Start()
    math.randomseed(os.time())
    scene_ = Scene()
    GiftServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        dailyGiftLimit = DAILY_GIFT_LIMIT,
        dailyStealLimit = DAILY_STEAL_LIMIT,
        dailySeedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT,
        dailyMatureAdLimit = DAILY_MATURE_AD_LIMIT,
        maxGiftCount = MAX_GIFT_COUNT,
        normalizePlantIndex = NormalizePlantIndex,
        normalizeEconomyState = NormalizeEconomyState,
        buildInitialEconomyState = BuildInitialEconomyState,
        nextRevision = NextRevision,
        pickGiftSeedId = PickGiftSeedId,
        getSeedName = function(seedId)
            local plant = GameConfig.PLANTS[tonumber(seedId or 0) or 0]
            return plant and plant.name or "神秘"
        end,
    })
    SocialServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        maxSocialRows = MAX_SOCIAL_ROWS,
        dailyStealLimit = DAILY_STEAL_LIMIT,
        dailySeedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT,
        dailyMatureAdLimit = DAILY_MATURE_AD_LIMIT,
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
    SubscribeToEvent(Shared.EVENTS.REQUEST_LEADERBOARD, "HandleGardenRequestLeaderboard")
    SubscribeToEvent(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD, "HandleGardenClaimActivityRankReward")
    SubscribeToEvent(Shared.EVENTS.REQUEST_STEAL, "HandleGardenRequestSteal")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SOCIAL_STATE, "HandleGardenRequestSocialState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_ECONOMY_STATE, "HandleGardenRequestEconomyState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SEED_SHOP, "HandleGardenRequestSeedShop")
    SubscribeToEvent(Shared.EVENTS.REQUEST_AUTH_FARM, "HandleGardenRequestAuthFarm")
    SubscribeToEvent(Shared.EVENTS.REQUEST_AD_REWARD, "HandleGardenRequestAdReward")
    SubscribeToEvent(Shared.EVENTS.BUY_SEED, "HandleGardenBuySeed")
    SubscribeToEvent(Shared.EVENTS.CLEAR_SAVE, "HandleGardenClearSave")
    SubscribeToEvent(Shared.EVENTS.PLANT_SEED, "HandleGardenPlantSeed")
    SubscribeToEvent(Shared.EVENTS.HARVEST_CROP, "HandleGardenHarvestCrop")
    SubscribeToEvent(Shared.EVENTS.OPEN_SEED_PACK, "HandleGardenOpenSeedPack")
    SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED, "HandleGardenSellHarvested")
    SubscribeToEvent(Shared.EVENTS.CLAIM_DAILY_REWARD, "HandleGardenClaimDailyReward")
    SubscribeToEvent(Shared.EVENTS.SYNTHESIZE_PACK, "HandleGardenSynthesizePack")
    SubscribeToEvent(Shared.EVENTS.UNLOCK_TALENT, "HandleGardenUnlockTalent")
    SubscribeToEvent(Shared.EVENTS.EXPAND_PLOT, "HandleGardenExpandPlot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_COMMISSIONS, "HandleGardenRequestCommissions")
    SubscribeToEvent(Shared.EVENTS.COMPLETE_COMMISSION, "HandleGardenCompleteCommission")
    SubscribeToEvent(Shared.EVENTS.SUBMIT_ACTIVITY_CROP, "HandleGardenSubmitActivityCrop")
    SubscribeToEvent(Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD, "HandleGardenExchangeActivityReward")
    SubscribeToEvent(Shared.EVENTS.DRAW_ACTIVITY_PACK, "HandleGardenDrawActivityPack")
    SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT, "HandleGardenSendSeedGift")
    SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN, "HandleGardenLikeGarden")
    SubscribeToEvent(Shared.EVENTS.SEND_FRIEND_REQUEST, "HandleGardenSendFriendRequest")
    SubscribeToEvent(Shared.EVENTS.RESPOND_FRIEND_REQUEST, "HandleGardenRespondFriendRequest")
    SubscribeToEvent(Shared.EVENTS.REMOVE_FRIEND, "HandleGardenRemoveFriend")
    SubscribeToEvent(Shared.EVENTS.CLEAR_SOCIAL_MESSAGES, "HandleGardenClearSocialMessages")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GIFTS, "HandleGardenRequestGifts")
    SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT, "HandleGardenClaimGift")
    print("[社交花园服务端] 权威农场服务已启动")
end
