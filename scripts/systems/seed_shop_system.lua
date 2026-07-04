-- ============================================================================
-- 种子商店系统 (Seed Shop System)
-- Grow A Garden - 种子商店 & 工具商店逻辑层
-- ============================================================================

local GameConfig = require("config.game_config")

local SeedShopSystem = {}

-- 稀有度排序权重（从低到高）
local RARITY_ORDER = {
    ["普通"] = 1,
    ["罕见"] = 2,
    ["稀有"] = 3,
    ["史诗"] = 4,
    ["传奇"] = 5,
}

-- 品质名称文字色（深底 + 微弱品质色调倾向，不刺眼）
local RARITY_NAME_COLORS = {
    ["普通"] = {72, 62, 45, 255},
    ["罕见"] = {45, 72, 50, 255},
    ["稀有"] = {40, 55, 85, 255},
    ["史诗"] = {68, 42, 82, 255},
    ["传奇"] = {90, 62, 30, 255},
}

local function ColorToRgba(color)
    if color == nil then return {200, 200, 200, 255} end
    if type(color) == "table" and color[1] ~= nil then return color end
    return { math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255), 255 }
end

local function BuildRarityColorsRgb()
    local result = {}
    for rarity, color in pairs(GameConfig.RARITY_COLORS) do
        result[rarity] = ColorToRgba(color)
    end
    return result
end

local RARITY_COLORS = BuildRarityColorsRgb()

-- 种子商店配置
local SEED_SHOP_CONFIG = {
    { name = "胡萝卜", rarity = "普通" },
    { name = "番茄",   rarity = "普通" },
    { name = "玉米",   rarity = "普通" },
    { name = "葡萄",   rarity = "普通" },

    { name = "草莓",   rarity = "罕见" },
    { name = "花椰菜", rarity = "罕见" },
    { name = "南瓜",   rarity = "罕见" },
    { name = "凤梨",   rarity = "罕见" },
    { name = "芒果",   rarity = "罕见" },
    { name = "香蕉",   rarity = "罕见" },

    { name = "郁金香", rarity = "稀有" },
    { name = "西瓜",   rarity = "稀有" },
    { name = "蘑菇",   rarity = "稀有" },
    { name = "仙人掌", rarity = "稀有" },
    { name = "竹子",   rarity = "稀有" },
    { name = "椰子",   rarity = "稀有" },

    { name = "波斯菊", rarity = "史诗" },
    { name = "向日葵", rarity = "史诗" },
    { name = "辣椒",   rarity = "史诗" },
    { name = "百合",   rarity = "史诗" },
    { name = "杜鹃",   rarity = "史诗" },
    { name = "玉兰",   rarity = "史诗" },
}

local SEED_SHOP_REFRESH_RULES = {
    guaranteed = {
        names = { "胡萝卜", "玉米" },
        stock = 50,
    },
    random = {
        ["普通"] = { names = { "番茄", "葡萄" }, chance = 0.80, minStock = 15, maxStock = 30 },
        ["罕见"] = { chance = 0.60, minStock = 8, maxStock = 15 },
        ["稀有"] = { chance = 0.25, minStock = 3, maxStock = 6 },
        ["史诗"] = { chance = 0.08, minStock = 1, maxStock = 3 },
    },
}

-- 工具商店配置（预留）
local TOOL_SHOP_CONFIG = {
    { name = "高级肥料", price = 500, desc = "加速生长50%", unlockLevel = 2, refreshStock = 3 },
    { name = "金色洒水壶", price = 1000, desc = "批量浇水", unlockLevel = 3, refreshStock = 2 },
    { name = "变异催化剂", price = 2000, desc = "提高变异概率", unlockLevel = 4, refreshStock = 1 },
}

-- 刷新时间配置（秒）
local REFRESH_CONFIG = {
    seed = {
        interval = 300,
    },
    tool = {
        interval = 600,
    },
}

local state_ = {
    serverAuthoritative = false,
    seed = {
        stock = {},
        items = {},
        timer = 0,
        lastRefreshRealTime = 0,
        refreshId = 0,
        serverTimeBase = 0,
        localElapsedSinceServerSync = 0,
        nextRefreshAt = 0,
        awaitingServer = false,
    },
    tool = {
        stock = {},
        timer = 0,
        lastRefreshRealTime = 0,
    },
    adTickets = 0,
    isOpen = false,
    activeTab = "seed",
}

local gameRef_ = {
    PLANTS = nil,
    money = nil,
    seedBag = nil,
    gardenLevel = nil,
    showToast = nil,
    onBuy = nil,
    requestSeedShop = nil,
}

local function GetSeedNamesByRarity(rarity)
    local result = {}
    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        if cfg.rarity == rarity then
            table.insert(result, cfg.name)
        end
    end
    return result
end

local function AddSeedShopItem(items, seedName, stock)
    state_.seed.stock[seedName] = stock
    table.insert(items, seedName)
end

local function GetSeedRefreshId(now)
    now = math.max(0, math.floor(tonumber(now or os.time()) or 0))
    return math.floor(now / REFRESH_CONFIG.seed.interval)
end

local function GetSeedRefreshRemaining(now)
    now = math.max(0, math.floor(tonumber(now or os.time()) or 0))
    local elapsedInCycle = now % REFRESH_CONFIG.seed.interval
    local remaining = REFRESH_CONFIG.seed.interval - elapsedInCycle
    if remaining <= 0 then remaining = REFRESH_CONFIG.seed.interval end
    return remaining
end

local function UpdateSeedTimerFromServerClock()
    if state_.seed.serverTimeBase <= 0 or state_.seed.nextRefreshAt <= 0 then
        state_.seed.timer = GetSeedRefreshRemaining()
        return state_.seed.timer
    end
    local estimatedServerNow = state_.seed.serverTimeBase + state_.seed.localElapsedSinceServerSync
    state_.seed.timer = math.max(0, state_.seed.nextRefreshAt - estimatedServerNow)
    return state_.seed.timer
end

local function RefreshSeedStock()
    state_.seed.stock = {}
    local items = {}

    for _, seedName in ipairs(SEED_SHOP_REFRESH_RULES.guaranteed.names) do
        AddSeedShopItem(items, seedName, SEED_SHOP_REFRESH_RULES.guaranteed.stock)
    end

    for _, rarity in ipairs({ "普通", "罕见", "稀有", "史诗" }) do
        local rule = SEED_SHOP_REFRESH_RULES.random[rarity]
        if rule ~= nil then
            local pool = rule.names or GetSeedNamesByRarity(rarity)
            for _, seedName in ipairs(pool) do
                if state_.seed.stock[seedName] == nil and math.random() <= rule.chance then
                    AddSeedShopItem(items, seedName, math.random(rule.minStock, rule.maxStock))
                end
            end
        end
    end

    state_.seed.items = items
    state_.seed.refreshId = GetSeedRefreshId()
    state_.seed.timer = REFRESH_CONFIG.seed.interval
    state_.seed.lastRefreshRealTime = os.time()
    print(string.format("[Shop] 种子商店已刷新：必出%d种，随机上架%d种，总库存条目%d；最高品质史诗，未上架作物显示售罄", #SEED_SHOP_REFRESH_RULES.guaranteed.names, math.max(0, #items - #SEED_SHOP_REFRESH_RULES.guaranteed.names), #items))
end

local function RefreshToolStock()
    for _, cfg in ipairs(TOOL_SHOP_CONFIG) do
        if cfg.refreshStock > 0 then
            local currentStock = state_.tool.stock[cfg.name] or 0
            local newStock = math.max(currentStock, cfg.refreshStock)
            state_.tool.stock[cfg.name] = newStock
        end
    end
    state_.tool.timer = REFRESH_CONFIG.tool.interval
    state_.tool.lastRefreshRealTime = os.time()
    print("[Shop] 工具商店已刷新")
end

local function SyncSeedShopFromData(data)
    if type(data) ~= "table" then return false end
    state_.seed.stock = {}
    state_.seed.items = {}

    if type(data.stock) == "table" then
        for seedName, stock in pairs(data.stock) do
            local numericStock = math.max(0, math.floor(tonumber(stock or 0) or 0))
            state_.seed.stock[tostring(seedName)] = numericStock
            if numericStock > 0 then
                table.insert(state_.seed.items, tostring(seedName))
            end
        end
    end

    if type(data.items) == "table" then
        state_.seed.items = {}
        for _, seedName in ipairs(data.items) do
            if state_.seed.stock[tostring(seedName)] ~= nil then
                table.insert(state_.seed.items, tostring(seedName))
            end
        end
    end

    state_.seed.refreshId = math.floor(tonumber(data.refreshId or GetSeedRefreshId()) or 0)
    local serverTime = math.max(0, tonumber(data.serverTime or os.time()) or 0)
    local nextRefreshIn = math.max(0, tonumber(data.nextRefreshIn or data.timer or GetSeedRefreshRemaining(serverTime)) or 0)
    state_.seed.serverTimeBase = serverTime
    state_.seed.localElapsedSinceServerSync = 0
    state_.seed.nextRefreshAt = math.max(serverTime, tonumber(data.nextRefreshAt or (serverTime + nextRefreshIn)) or (serverTime + nextRefreshIn))
    state_.seed.timer = math.max(0, state_.seed.nextRefreshAt - state_.seed.serverTimeBase)
    state_.seed.lastRefreshRealTime = math.floor(serverTime)
    state_.seed.awaitingServer = false
    print(string.format("[Shop] 已同步全服种子商店：批次%d，上架%d种，%.1f秒后刷新", state_.seed.refreshId, #state_.seed.items, state_.seed.timer))
    return true
end

function SeedShopSystem.FindPlantIndex(name)
    if gameRef_.PLANTS == nil then return nil end
    for i, plant in ipairs(gameRef_.PLANTS) do
        if plant.name == name then
            return i
        end
    end
    return nil
end

function SeedShopSystem.FormatTimer(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

function SeedShopSystem.GetCurrentSeedShopItems()
    local result = {}

    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        local seedName = cfg.name
        local plantIdx = SeedShopSystem.FindPlantIndex(seedName)
        if plantIdx ~= nil then
            local plant = gameRef_.PLANTS[plantIdx]
            table.insert(result, {
                name = seedName,
                plantIndex = plantIdx,
                plant = plant,
                shopCfg = cfg,
                stock = state_.seed.stock[seedName] or 0,
                rarity = plant.rarity,
                rarityOrder = RARITY_ORDER[plant.rarity] or 0,
                price = plant.seedPrice,
                nameColor = RARITY_NAME_COLORS[plant.rarity] or {62, 48, 32, 255},
            })
        end
    end

    table.sort(result, function(a, b)
        if a.rarityOrder ~= b.rarityOrder then
            return a.rarityOrder < b.rarityOrder
        end
        return a.price < b.price
    end)

    return result
end

function SeedShopSystem.BuySeed(seedName, count)
    count = math.max(1, math.floor(tonumber(count or 1) or 1))
    local stock = state_.seed.stock[seedName] or 0
    if stock <= 0 then
        if gameRef_.showToast then gameRef_.showToast("该种子已售罄") end
        return 0
    end

    local plantIdx = SeedShopSystem.FindPlantIndex(seedName)
    if plantIdx == nil then return 0 end

    local plant = gameRef_.PLANTS[plantIdx]
    local currentMoney = gameRef_.money and gameRef_.money() or 0
    local buyCount = math.min(count, stock, math.floor(currentMoney / plant.seedPrice))

    if buyCount <= 0 then
        if gameRef_.showToast then gameRef_.showToast("金币不足") end
        return 0
    end

    local totalCost = plant.seedPrice * buyCount
    if gameRef_.onBuy and gameRef_.onBuy(totalCost, plantIdx, buyCount, seedName, state_.seed.refreshId) == false then
        return 0
    end

    if state_.serverAuthoritative then
        print(string.format("[Shop] 已请求服务器购买全服库存种子: %s x%d, 批次%d, 预计花费 %d", seedName, buyCount, state_.seed.refreshId, totalCost))
        return buyCount
    end

    state_.seed.stock[seedName] = stock - buyCount
    print(string.format("[Shop] 购买种子: %s x%d, 花费 %d, 剩余库存 %d", seedName, buyCount, totalCost, state_.seed.stock[seedName]))
    return buyCount
end

function SeedShopSystem.BuyTool(toolName)
    if state_.serverAuthoritative then
        if gameRef_.showToast then gameRef_.showToast("工具商店需要服务端开放后才能购买") end
        return false
    end
    local stock = state_.tool.stock[toolName] or 0
    if stock <= 0 then
        if gameRef_.showToast then gameRef_.showToast("该工具暂无库存") end
        return false
    end

    local cfg = nil
    for _, t in ipairs(TOOL_SHOP_CONFIG) do
        if t.name == toolName then cfg = t; break end
    end
    if cfg == nil then return false end

    local currentMoney = gameRef_.money and gameRef_.money() or 0
    if currentMoney < cfg.price then
        if gameRef_.showToast then gameRef_.showToast("金币不足") end
        return false
    end

    if gameRef_.onBuy then
        gameRef_.onBuy(cfg.price, nil)
    end

    state_.tool.stock[toolName] = stock - 1
    if gameRef_.showToast then gameRef_.showToast("购买 " .. toolName .. " 成功") end
    print(string.format("[Shop] 购买工具: %s, 花费 %d", toolName, cfg.price))
    return true
end

function SeedShopSystem.ManualRefresh(shopType)
    if state_.serverAuthoritative then
        if gameRef_.showToast then gameRef_.showToast("商店刷新由服务器控制") end
        return false
    end
    if state_.adTickets > 0 then
        state_.adTickets = state_.adTickets - 1
        print(string.format("[Shop] 使用广告券刷新%s商店，剩余券 %d", shopType, state_.adTickets))
    else
        print(string.format("[Shop] 播放激励视频刷新%s商店", shopType))
    end

    if shopType == "seed" then
        RefreshSeedStock()
    else
        RefreshToolStock()
    end

    if gameRef_.showToast then gameRef_.showToast("商店已刷新") end
    return true
end

function SeedShopSystem.RequestSeedShopFromServer()
    if not state_.serverAuthoritative or gameRef_.requestSeedShop == nil then return false end
    state_.seed.awaitingServer = true
    local ok = gameRef_.requestSeedShop()
    if not ok then
        state_.seed.awaitingServer = false
    end
    return ok
end

function SeedShopSystem.GetDisplayConfig()
    return {
        SEED_ICON_PATH = "image/icons_3d/seed (%d).png",
        RARITY_COLORS = RARITY_COLORS,
        RARITY_NAME_COLORS = RARITY_NAME_COLORS,
        RARITY_ORDER = RARITY_ORDER,
        SEED_SHOP_CONFIG = SEED_SHOP_CONFIG,
        TOOL_SHOP_CONFIG = TOOL_SHOP_CONFIG,
        REFRESH_CONFIG = REFRESH_CONFIG,
        SHOP_MODAL_CHROME_HEIGHT = 130,
        SHOP_BODY_MIN_HEIGHT = 280,
        SHOP_LIST_HEADER_HEIGHT = 46,
        SHOP_LIST_MIN_HEIGHT = 180,
    }
end

function SeedShopSystem.Init(opts)
    gameRef_.PLANTS = opts.PLANTS
    gameRef_.money = opts.getMoney
    gameRef_.gardenLevel = opts.getGardenLevel
    gameRef_.onBuy = opts.onBuy
    gameRef_.requestSeedShop = opts.requestSeedShop
    gameRef_.showToast = opts.showToast
    state_.serverAuthoritative = opts.serverAuthoritative == true

    if state_.serverAuthoritative then
        local serverTime = os.time()
        state_.seed.serverTimeBase = serverTime
        state_.seed.localElapsedSinceServerSync = 0
        state_.seed.nextRefreshAt = serverTime + GetSeedRefreshRemaining(serverTime)
        state_.seed.timer = state_.seed.nextRefreshAt - state_.seed.serverTimeBase
        state_.seed.refreshId = GetSeedRefreshId(serverTime)
        state_.seed.lastRefreshRealTime = serverTime
    else
        RefreshSeedStock()
    end
    RefreshToolStock()

    print("[Shop] 商店系统初始化完成")
end

---@return table seedRefreshed, table toolRefreshed flags
function SeedShopSystem.UpdateLogic(dt)
    local seedRefreshed = false
    local toolRefreshed = false

    if state_.serverAuthoritative then
        state_.seed.localElapsedSinceServerSync = state_.seed.localElapsedSinceServerSync + dt
        UpdateSeedTimerFromServerClock()
        if state_.seed.timer <= 0 and state_.seed.awaitingServer ~= true then
            if SeedShopSystem.RequestSeedShopFromServer() then
                seedRefreshed = true
            end
        end
    elseif state_.seed.timer > 0 then
        state_.seed.timer = state_.seed.timer - dt
        if state_.seed.timer <= 0 then
            RefreshSeedStock()
            seedRefreshed = true
        end
    end

    if state_.tool.timer > 0 then
        state_.tool.timer = state_.tool.timer - dt
        if state_.tool.timer <= 0 then
            RefreshToolStock()
            toolRefreshed = true
        end
    end

    return { seedRefreshed = seedRefreshed, toolRefreshed = toolRefreshed }
end

function SeedShopSystem.ApplyServerSeedShop(data)
    if SyncSeedShopFromData(data) then
        return true
    end
    state_.seed.awaitingServer = false
    return false
end

function SeedShopSystem.IsOpen()
    return state_.isOpen
end

function SeedShopSystem.SetOpen(open)
    state_.isOpen = open == true
end

function SeedShopSystem.GetState()
    return state_
end

function SeedShopSystem.SetActiveTab(tabId)
    state_.activeTab = tabId
end

function SeedShopSystem.GetActiveTab()
    return state_.activeTab
end

function SeedShopSystem.SetAdTickets(count)
    state_.adTickets = count
end

function SeedShopSystem.GetAdTickets()
    return state_.adTickets
end

function SeedShopSystem.GetGameRef()
    return gameRef_
end

return SeedShopSystem
