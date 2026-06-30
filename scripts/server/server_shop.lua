-- ============================================================================
-- 服务端全服种子商店
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的全服种子商店刷新、库存、广播和响应逻辑。
-- 只承接原有实现，不改变刷新算法、库存扣减和响应字段。
-- ============================================================================

local ServerShop = {}

local deps_ = {}

local SEED_SHOP_ITEMS = {
    { name = "胡萝卜", rarity = "普通", guaranteed = true, stock = 99 },
    { name = "玉米", rarity = "普通", chance = 0.80, minStock = 15, maxStock = 30 },
    { name = "番茄", rarity = "普通", guaranteed = true, stock = 99 },
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

function ServerShop.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.now()
end

local function Send(connection, eventName, data)
    deps_.send(connection, eventName, data)
end

function ServerShop.SeedShopRefreshId(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    return math.floor(now / deps_.refreshInterval)
end

function ServerShop.SeedShopRefreshRemaining(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local elapsed = now % deps_.refreshInterval
    local remaining = deps_.refreshInterval - elapsed
    if remaining <= 0 then remaining = deps_.refreshInterval end
    return remaining
end

function ServerShop.BuildSeedShopQuotaKey(refreshId, plantIndex)
    return string.format("seed_shop_%d_%d", math.floor(tonumber(refreshId or 0) or 0), math.floor(tonumber(plantIndex or 0) or 0))
end

function ServerShop.FindPlantIndexByName(name)
    for index, plant in ipairs(deps_.GameConfig.PLANTS or {}) do
        if plant.name == name then return index end
    end
    return nil
end

function ServerShop.NormalizeSeedShopState(shop)
    shop = type(shop) == "table" and shop or {}
    shop.refreshId = math.floor(tonumber(shop.refreshId or -1) or -1)
    shop.stock = type(shop.stock) == "table" and shop.stock or {}
    shop.items = type(shop.items) == "table" and shop.items or {}
    shop.updatedAt = math.max(0, math.floor(tonumber(shop.updatedAt or 0) or 0))
    return shop
end

function ServerShop.BuildSeedShopState(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local refreshId = ServerShop.SeedShopRefreshId(now)
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
        if ServerShop.FindPlantIndexByName(cfg.name) ~= nil then
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
        interval = deps_.refreshInterval,
        stock = stock,
        items = items,
        updatedAt = now,
    }
end

function ServerShop.AddSeedShopResponseFields(shop, now)
    shop = ServerShop.NormalizeSeedShopState(shop)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    shop.serverTime = now
    shop.nextRefreshAt = (shop.refreshId + 1) * deps_.refreshInterval
    shop.nextRefreshIn = math.max(0, shop.nextRefreshAt - now)
    return shop
end

function ServerShop.EnsureSeedShopState(callback)
    local now = Now()
    local currentRefreshId = ServerShop.SeedShopRefreshId(now)
    serverCloud:Get(deps_.globalShopUid, deps_.Shared.KEYS.SHARED_SEED_SHOP, {
        ok = function(scores)
            local shop = ServerShop.NormalizeSeedShopState(scores[deps_.Shared.KEYS.SHARED_SEED_SHOP])
            if shop.refreshId ~= currentRefreshId then
                shop = ServerShop.BuildSeedShopState(now)
                serverCloud:Set(deps_.globalShopUid, deps_.Shared.KEYS.SHARED_SEED_SHOP, shop, {
                    ok = function()
                        callback(ServerShop.AddSeedShopResponseFields(shop, now))
                    end,
                    error = function()
                        callback(ServerShop.AddSeedShopResponseFields(shop, now))
                    end,
                })
            else
                callback(ServerShop.AddSeedShopResponseFields(shop, now))
            end
        end,
        error = function()
            local shop = ServerShop.BuildSeedShopState(now)
            serverCloud:Set(deps_.globalShopUid, deps_.Shared.KEYS.SHARED_SEED_SHOP, shop)
            callback(ServerShop.AddSeedShopResponseFields(shop, now))
        end,
    })
end

function ServerShop.RebuildSeedShopItemsFromStock(shop)
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

function ServerShop.FetchSeedShopAvailableState(shop, callback)
    local responseShop = ServerShop.AddSeedShopResponseFields(deps_.deepCopy(shop), Now())
    responseShop.stock = type(responseShop.stock) == "table" and responseShop.stock or {}

    local pending = 1
    local completed = false
    local function FinishOne()
        pending = pending - 1
        if pending <= 0 and completed ~= true then
            completed = true
            ServerShop.RebuildSeedShopItemsFromStock(responseShop)
            callback(responseShop)
        end
    end

    for seedName, stock in pairs(responseShop.stock) do
        local plantIndex = ServerShop.FindPlantIndexByName(seedName)
        local maxStock = math.max(0, math.floor(tonumber(stock or 0) or 0))
        responseShop.stock[seedName] = maxStock
        if plantIndex ~= nil and maxStock > 0 then
            pending = pending + 1
            local quotaKey = ServerShop.BuildSeedShopQuotaKey(responseShop.refreshId, plantIndex)
            serverCloud.quota:Get(deps_.globalShopUid, quotaKey, {
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

function ServerShop.BroadcastSeedShopState(shop)
    for _, connection in pairs(deps_.getConnections()) do
        Send(connection, deps_.Shared.EVENTS.SEED_SHOP_RESPONSE, { success = true, shop = shop })
    end
end

function ServerShop.SendFullAvailableSeedShop(connection, eventName, baseData)
    ServerShop.EnsureSeedShopState(function(shop)
        ServerShop.FetchSeedShopAvailableState(shop, function(availableShop)
            local data = baseData or {}
            data.success = data.success ~= false
            data.shop = availableShop
            Send(connection, eventName, data)
        end)
    end)
end

function ServerShop.BroadcastFullAvailableSeedShop()
    ServerShop.EnsureSeedShopState(function(shop)
        ServerShop.FetchSeedShopAvailableState(shop, function(availableShop)
            ServerShop.BroadcastSeedShopState(availableShop)
        end)
    end)
end

function ServerShop.SendSeedShopState(connection)
    ServerShop.EnsureSeedShopState(function(shop)
        ServerShop.FetchSeedShopAvailableState(shop, function(availableShop)
            Send(connection, deps_.Shared.EVENTS.SEED_SHOP_RESPONSE, { success = true, shop = availableShop })
        end)
    end)
end

return ServerShop
