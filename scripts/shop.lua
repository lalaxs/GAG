-- ============================================================================
-- 商店系统模块 (Shop System Module)
-- Grow A Garden - 种子商店 & 工具商店
-- ============================================================================
-- 功能：
--   1. 种子商店：按稀有度排序展示，花园等级解锁，库存定时刷新
--   2. 工具商店：独立刷新计时（预留，当前为空商店）
--   3. 手动刷新：广告券/激励视频
--   4. 离线计时：记录倒计时但不累计刷新次数
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")
local AudioSystem = require("systems.audio_system")

local Shop = {}

-- 种子图标路径模板（按 PLANTS 表顺序对应 seed (1).png ~ seed (29).png）
local SEED_ICON_PATH = "image/icons_3d/seed (%d).png"

-- ============================================================================
-- § 1. 商店配置
-- ============================================================================

-- 稀有度排序权重（从低到高）
local RARITY_ORDER = {
    ["普通"] = 1,
    ["罕见"] = 2,
    ["稀有"] = 3,
    ["史诗"] = 4,
    ["传奇"] = 5,
}

-- 稀有度颜色
local RARITY_COLORS = {
    ["普通"] = {200, 200, 185, 255},
    ["罕见"] = {65, 210, 90, 255},
    ["稀有"] = {65, 140, 255, 255},
    ["史诗"] = {190, 90, 255, 255},
    ["传奇"] = {255, 148, 20, 255},
}

-- 品质名称文字色（深底 + 微弱品质色调倾向，不刺眼）
local RARITY_NAME_COLORS = {
    ["普通"] = {72, 62, 45, 255},
    ["罕见"] = {45, 72, 50, 255},
    ["稀有"] = {40, 55, 85, 255},
    ["史诗"] = {68, 42, 82, 255},
    ["传奇"] = {90, 62, 30, 255},
}

-- 种子商店配置
-- 刷新规则：
--   1. 参考 Grow a Garden 的全服共享库存：固定 5 分钟一轮，所有玩家看到同一份库存
--   2. 胡萝卜、玉米固定上架，保证新手始终能循环
--   3. 普通到史诗按稀有度概率刷新，最高只到史诗，不在普通商店出售传奇种子
--   4. 商店列表始终展示普通到史诗全部作物，未刷出或售罄显示为“售罄”
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
        interval = 300,     -- 5 分钟刷新一次
    },
    tool = {
        interval = 600,     -- 10 分钟刷新一次
    },
}

-- ============================================================================
-- § 2. 商店状态
-- ============================================================================

---@class ShopState
---@field stock table<string, number>  种子名 -> 当前库存
---@field timer number                 当前倒计时剩余秒数
---@field lastRefreshRealTime number   上次刷新的 os.time()
---@field refreshId number             当前全服刷新批次 ID
---@field serverTimeBase number        最近一次服务端同步时的服务端时间
---@field localElapsedSinceServerSync number 最近一次服务端同步后的本地累计时间
---@field nextRefreshAt number         下一次全服刷新服务端时间戳

local state_ = {
    serverAuthoritative = false,
    seed = {
        stock = {},         -- { [seedName] = quantity }
        items = {},         -- 当前轮上架种子名数组
        timer = 0,          -- 倒计时剩余秒数
        lastRefreshRealTime = 0,
        refreshId = 0,
        serverTimeBase = 0,
        localElapsedSinceServerSync = 0,
        nextRefreshAt = 0,
        awaitingServer = false,
    },
    tool = {
        stock = {},         -- { [toolName] = quantity }
        timer = 0,
        lastRefreshRealTime = 0,
    },
    adTickets = 0,          -- 广告券数量
    isOpen = false,         -- 商店是否打开
    activeTab = "seed",     -- 当前 tab: "seed" | "tool"
}

-- 外部注入的引用（由 Init 设置）
local gameRef_ = {
    PLANTS = nil,           -- 植物配置表引用
    money = nil,            -- 金币 getter/setter
    seedBag = nil,          -- 种子背包引用
    gardenLevel = nil,      -- 花园等级 getter
    showToast = nil,        -- 提示函数
    onBuy = nil,            -- 购买回调
    requestSeedShop = nil,  -- 请求服务器同步全服商店库存
}

-- UI 引用
local SHOP_MODAL_CHROME_HEIGHT = 130
local SHOP_BODY_MIN_HEIGHT = 280
local SHOP_LIST_HEADER_HEIGHT = 46
local SHOP_LIST_MIN_HEIGHT = 180
local shopContentMinHeight_ = 400  -- 会在 Open 时根据屏幕高度重新计算，作为商店内容区固定高度
local shopModal_ = nil
local seedListPanel_ = nil
local toolListPanel_ = nil
local seedTimerLabel_ = nil
local toolTimerLabel_ = nil
local refreshBtnSeed_ = nil
local refreshBtnTool_ = nil
local shopScrollState_ = {
    seed = { x = 0, y = 0 },
    tool = { x = 0, y = 0 },
}

local function SaveShopScrollState(shopType)
    local listPanel = shopType == "seed" and seedListPanel_ or toolListPanel_
    if listPanel == nil or listPanel.GetScroll == nil then return end
    local scrollX, scrollY = listPanel:GetScroll()
    local scrollState = shopScrollState_[shopType]
    if scrollState ~= nil then
        scrollState.x = math.max(0, scrollX or 0)
        scrollState.y = math.max(0, scrollY or 0)
    end
end

local function RestoreShopScrollState(shopType, listPanel)
    local scrollState = shopScrollState_[shopType]
    if listPanel == nil or scrollState == nil then return end
    if listPanel.SetScrollDirect then
        listPanel:SetScrollDirect(scrollState.x or 0, scrollState.y or 0)
    elseif listPanel.SetScroll then
        listPanel:SetScroll(scrollState.x or 0, scrollState.y or 0)
    end
end

local function TrackShopScroll(shopType, scrollX, scrollY)
    local scrollState = shopScrollState_[shopType]
    if scrollState == nil then return end
    scrollState.x = math.max(0, scrollX or 0)
    scrollState.y = math.max(0, scrollY or 0)
end

-- 条目逐条渐显动画
local STAGGER_DELAY = 0.12         -- 每个条目开始出现的间隔（秒）
local STAGGER_FADE = 0.18          -- 每个条目从透明到不透明的时长（秒）
local staggerTimer_ = 0            -- 打开商店后经过的时间
local staggerTotalCount_ = 0       -- 条目总数
local staggerDone_ = false         -- 动画是否完成
local pendingTabSwitch_ = nil      -- 延迟切换 tab（避免在回调中销毁自身）

-- ============================================================================
-- § 3. 核心逻辑
-- ============================================================================

--- 计算第 index 个条目当前的透明度 (0~1)
local function GetItemAlpha(index)
    if staggerDone_ then return 1.0 end
    local appearStart = (index - 1) * STAGGER_DELAY
    local elapsed = staggerTimer_ - appearStart
    if elapsed <= 0 then return 0.0 end
    if elapsed >= STAGGER_FADE then return 1.0 end
    return elapsed / STAGGER_FADE
end

--- 将颜色表乘以 alpha 系数
local function ApplyAlpha(color, alpha)
    if alpha >= 1.0 then return color end
    return {color[1], color[2], color[3], math.floor((color[4] or 255) * alpha)}
end

--- 根据名字在 PLANTS 表中找到对应索引
local function FindPlantIndex(name)
    if gameRef_.PLANTS == nil then return nil end
    for i, plant in ipairs(gameRef_.PLANTS) do
        if plant.name == name then
            return i
        end
    end
    return nil
end

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

local function RequestSeedShopFromServer()
    if not state_.serverAuthoritative or gameRef_.requestSeedShop == nil then return false end
    state_.seed.awaitingServer = true
    local ok = gameRef_.requestSeedShop()
    if not ok then
        state_.seed.awaitingServer = false
    end
    return ok
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

--- 执行一次种子商店刷新
--- 规则：胡萝卜、玉米必定上架；其他普通到史诗作物按概率独立随机上架
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

--- 执行一次工具商店刷新
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

--- 处理离线时间：只刷新一次（不累计）
local function HandleOfflineTime(shopType)
    local shopState = state_[shopType]
    local config = REFRESH_CONFIG[shopType]
    if shopState.lastRefreshRealTime <= 0 then return end

    local now = os.time()
    local elapsed = now - shopState.lastRefreshRealTime

    if elapsed >= shopState.timer then
        -- 离线期间到期了，执行一次刷新（不累计多次）
        if shopType == "seed" then
            RefreshSeedStock()
        else
            RefreshToolStock()
        end
        print(string.format("[Shop] %s商店离线刷新（离线%d秒，仅刷新1次）", shopType, elapsed))
    else
        -- 还没到期，扣除已过时间
        shopState.timer = shopState.timer - elapsed
    end
    shopState.lastRefreshRealTime = now
end

--- 格式化倒计时文本
local function FormatTimer(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

--- 获取当前种子商店列表（始终显示普通到史诗全部作物）
local function GetCurrentSeedShopItems()
    local result = {}

    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        local seedName = cfg.name
        local plantIdx = FindPlantIndex(seedName)
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

--- 购买种子
local function BuySeed(seedName, count)
    count = math.max(1, math.floor(tonumber(count or 1) or 1))
    local stock = state_.seed.stock[seedName] or 0
    if stock <= 0 then
        if gameRef_.showToast then gameRef_.showToast("该种子已售罄") end
        return 0
    end

    local plantIdx = FindPlantIndex(seedName)
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

--- 购买工具（预留）
local function BuyTool(toolName)
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

    -- 扣钱（通过 onBuy 回调，plantIdx = nil 表示工具）
    if gameRef_.onBuy then
        gameRef_.onBuy(cfg.price, nil)
    end

    state_.tool.stock[toolName] = stock - 1
    if gameRef_.showToast then gameRef_.showToast("购买 " .. toolName .. " 成功") end
    print(string.format("[Shop] 购买工具: %s, 花费 %d", toolName, cfg.price))
    return true
end

--- 手动刷新商店（广告券或看广告）
local function ManualRefresh(shopType)
    if state_.serverAuthoritative then
        if gameRef_.showToast then gameRef_.showToast("商店刷新由服务器控制") end
        return false
    end
    if state_.adTickets > 0 then
        state_.adTickets = state_.adTickets - 1
        print(string.format("[Shop] 使用广告券刷新%s商店，剩余券 %d", shopType, state_.adTickets))
    else
        -- 模拟播放激励视频（实际接入广告SDK时替换）
        print(string.format("[Shop] 播放激励视频刷新%s商店", shopType))
    end

    if shopType == "seed" then
        RefreshSeedStock()
    else
        RefreshToolStock()
    end

    if gameRef_.showToast then gameRef_.showToast("商店已刷新") end
end

-- ============================================================================
-- § 4. UI 构建
-- ============================================================================

-- 购买确认弹窗状态
local buyConfirmSeed_ = nil   -- 当前弹出购买确认的种子数据
local buyConfirmModal_ = nil

--- 显示购买确认弹窗（x1 / x10）
local function ShowBuyConfirm(seedData)
    buyConfirmSeed_ = seedData
    buyConfirmModal_ = UI.Modal {
        title = "购买 " .. seedData.name .. "种子",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        onClose = function()
            buyConfirmModal_ = nil
            buyConfirmSeed_ = nil
        end,
    }

    local stock = state_.seed.stock[seedData.name] or 0
    local price = seedData.price
    local currentMoney = gameRef_.money and gameRef_.money() or 0
    local buyOneCount = 1
    local buyTenCount = 10
    local maxAffordableCount = math.min(stock, math.floor(currentMoney / math.max(1, price)))

    local function BuildBuyOption(count, width)
        local totalPrice = price * count
        return UI.Panel {
            alignItems = "center", gap = 5,
            children = {
                UI.Label {
                    text = tostring(totalPrice) .. " 金币",
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = currentMoney >= totalPrice and {92, 74, 45, 255} or {170, 90, 70, 255},
                },
                UI.Button {
                    text = "购买 x" .. count,
                    width = width or 82,
                    height = 36,
                    fontSize = 12,
                    fontWeight = "bold",
                    variant = "primary",
                    borderRadius = 10,
                    disabled = count <= 0 or stock < count or currentMoney < totalPrice,
                    onClick = function()
                        local bought = BuySeed(seedData.name, count)
                        if bought > 0 then
                            if state_.serverAuthoritative then
                                if gameRef_.showToast then gameRef_.showToast("购买请求已发送，等待服务器确认") end
                            else
                                if gameRef_.showToast then gameRef_.showToast("已购买 x" .. bought .. "!") end
                            end
                            if buyConfirmModal_ then buyConfirmModal_:Close() end
                            Shop.RebuildShopContent()
                        end
                    end,
                },
            },
        }
    end

    buyConfirmModal_:AddContent(UI.Panel {
        alignItems = "center", gap = 10, padding = 12,
        children = {
            UI.Panel {
                width = 78,
                height = 78,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {244, 238, 218, 255},
                borderRadius = 18,
                borderWidth = 1,
                borderColor = {214, 188, 130, 150},
                children = {
                    UI.Panel {
                        width = 58,
                        height = 58,
                        backgroundImage = string.format(SEED_ICON_PATH, seedData.plantIndex),
                        backgroundSize = "contain",
                    },
                },
            },
            UI.Label { text = "种子单价: " .. price .. " 金币", fontSize = 14, fontWeight = "bold", fontColor = {80, 60, 40, 255} },
            UI.Label { text = "收益基准价: " .. price .. " 金币", fontSize = 13, fontColor = {95, 75, 45, 255} },
            UI.Label { text = "库存: " .. stock .. "  |  持有: " .. currentMoney .. " 金币", fontSize = 12, fontColor = {120, 100, 80, 200} },
            UI.Panel {
                flexDirection = "row", gap = 8, marginTop = 4,
                children = {
                    BuildBuyOption(buyOneCount, 78),
                    BuildBuyOption(buyTenCount, 78),
                    BuildBuyOption(maxAffordableCount, 88),
                },
            },
        },
    })
    ModalAnim.Apply(buyConfirmModal_)
    buyConfirmModal_:Open()
end

--- 显示种子详情弹窗
local function ShowSeedDetail(seedData)
    local detailModal = UI.Modal {
        title = seedData.name .. " 详情",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        onClose = function() end,
    }
    local plant = seedData.plant
    detailModal:AddContent(UI.Panel {
        gap = 8, padding = 12,
        children = {
            UI.Label { text = "稀有度: " .. seedData.rarity, fontSize = 14, fontWeight = "bold", fontColor = RARITY_COLORS[seedData.rarity] or {100,100,100,255} },
            UI.Label { text = "成熟时长: " .. plant.growTime .. " 秒", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "收益基准价: " .. plant.seedPrice .. " 金币", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "成熟售价会随重量和变异波动", fontSize = 12, fontColor = {120, 100, 80, 200} },
            UI.Label { text = "变异规则: 颜色约9%，特殊约2.5%，天赋可相对提升", fontSize = 12, fontColor = {120, 100, 80, 200} },
        },
    })
    ModalAnim.Apply(detailModal)
    detailModal:Open()
end

--- 品质底色（动森风柔和色调）
local RARITY_BG_COLORS = {
    ["普通"] = {242, 238, 225, 255},
    ["罕见"] = {218, 242, 220, 255},
    ["稀有"] = {215, 232, 252, 255},
    ["史诗"] = {235, 218, 252, 255},
    ["传奇"] = {255, 235, 200, 255},
}

local function BuildSeedGridItem(seedData, itemAlpha)
    itemAlpha = itemAlpha or 1.0
    local hasStock = seedData.stock > 0
    local bgColor = RARITY_BG_COLORS[seedData.rarity] or {240, 238, 230, 255}
    local a = itemAlpha

    -- 售罄时略降低背景饱和度
    if not hasStock then
        bgColor = {
            math.floor(bgColor[1] * 0.88 + 235 * 0.12),
            math.floor(bgColor[2] * 0.88 + 232 * 0.12),
            math.floor(bgColor[3] * 0.88 + 228 * 0.12),
            210
        }
    end

    return UI.Panel {
        width = "30%",
        alignItems = "center",
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 3,
        paddingRight = 3,
        marginBottom = 10,
        backgroundColor = ApplyAlpha(bgColor, a),
        borderRadius = 14,
        onClick = function()
            if hasStock then
                ShowBuyConfirm(seedData)
            else
                if gameRef_.showToast then gameRef_.showToast("已售罄，等待刷新") end
            end
        end,
        children = {
            -- 种子图标
            UI.Panel {
                width = 46, height = 46,
                marginBottom = 5,
                children = {
                    UI.Panel {
                        width = 46, height = 46,
                        backgroundImage = string.format(SEED_ICON_PATH, seedData.plantIndex),
                        backgroundSize = "contain",
                    },
                },
            },
            -- 名称（带品质色调倾向）
            UI.Label {
                text = seedData.name .. "种子",
                fontSize = 13, fontWeight = "bold",
                fontColor = ApplyAlpha(seedData.nameColor, a),
                marginBottom = 3,
            },
            -- 库存数量
            UI.Label {
                text = "库存 " .. seedData.stock,
                fontSize = 11,
                fontColor = ApplyAlpha(hasStock and {95, 130, 100, 255} or {160, 140, 115, 255}, a),
                marginBottom = 6,
            },
            -- 按钮：有库存显示金币+价格，售罄仅显示文本
            hasStock and UI.Panel {
                width = "94%", height = 30,
                flexDirection = "row",
                justifyContent = "center", alignItems = "center",
                gap = 4,
                backgroundColor = ApplyAlpha({218, 208, 182, 255}, a),
                borderRadius = 10,
                children = {
                    UI.Panel {
                        width = 14, height = 14,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Panel { width = 14, height = 14, borderRadius = 7, backgroundColor = ApplyAlpha({255, 220, 80, 255}, a) },
                            UI.Label { position = "absolute", text = "$", fontSize = 8, fontWeight = "bold", fontColor = ApplyAlpha({140, 100, 10, 255}, a) },
                        },
                    },
                    UI.Label {
                        text = tostring(seedData.price),
                        fontSize = 13, fontWeight = "bold",
                        fontColor = ApplyAlpha({55, 42, 20, 255}, a),
                    },
                },
            } or UI.Label {
                text = "售罄",
                fontSize = 12,
                fontColor = ApplyAlpha({160, 140, 115, 255}, a),
                marginTop = 2,
            },
        },
    }
end

local function BuildToolItemRow(toolCfg)
    local stock = state_.tool.stock[toolCfg.name] or 0
    local hasStock = stock > 0
    local level = gameRef_.gardenLevel and gameRef_.gardenLevel() or 1
    local unlocked = toolCfg.unlockLevel <= level

    if not unlocked then return nil end

    local stockText = hasStock and ("x" .. stock) or "售罄"
    local stockColor = hasStock and {50, 160, 80, 255} or {180, 120, 80, 180}

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        paddingLeft = 12,
        paddingRight = 12,
        marginBottom = 4,
        backgroundColor = hasStock and {255, 252, 240, 255} or {245, 242, 230, 200},
        borderRadius = 10,
        borderWidth = 1,
        borderColor = {180, 155, 100, 100},
        children = {
            -- 工具图标区域
            UI.Panel {
                width = 42,
                height = 22,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {100, 180, 220, 255},
                borderRadius = 6,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = "工具",
                        fontSize = 9,
                        fontWeight = "bold",
                        fontColor = {255, 255, 255, 255},
                    },
                },
            },
            -- 名称和描述
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = toolCfg.name,
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = {75, 50, 40, 255},
                    },
                    UI.Label {
                        text = toolCfg.desc .. " | " .. toolCfg.price .. " 金币",
                        fontSize = 11,
                        fontColor = {160, 130, 80, 255},
                    },
                },
            },
            -- 库存标签
            UI.Label {
                text = stockText,
                fontSize = 12,
                fontWeight = "bold",
                fontColor = stockColor,
                marginRight = 8,
            },
            -- 购买按钮
            UI.Button {
                text = "购买",
                height = 32,
                width = 56,
                fontSize = 12,
                variant = "primary",
                disabled = not hasStock,
                onClick = function()
                    if BuyTool(toolCfg.name) then
                        Shop.RebuildShopContent()
                    end
                end,
            },
        },
    }
end

--- 构建种子商店内容
local function BuildSeedShopContent()
    local seeds = GetCurrentSeedShopItems()
    local listItems = {}

    -- 倒计时 + 黄色刷新按钮固定在列表上方，不参与滚动，避免撑高商店底图
    local timerSec = math.max(0, math.floor(state_.seed.timer))
    local m = math.floor(timerSec / 60)
    local s = timerSec % 60

    seedTimerLabel_ = UI.Label {
        text = string.format("全服刷新倒计时 %d:%02d", m, s),
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {100, 80, 60, 220},
    }

    refreshBtnSeed_ = UI.Button {
        text = state_.serverAuthoritative and "同步" or "▶ 刷新",
        height = 30,
        width = 86,
        fontSize = 11,
        fontWeight = "bold",
        backgroundColor = {245, 195, 50, 255},
        fontColor = {60, 40, 10, 255},
        borderRadius = 8,
        onClick = function()
            if state_.serverAuthoritative then
                if RequestSeedShopFromServer() and gameRef_.showToast then gameRef_.showToast("正在同步全服商店...") end
            else
                ManualRefresh("seed")
                Shop.RebuildShopContent()
            end
        end,
    }

    local header = UI.Panel {
        height = SHOP_LIST_HEADER_HEIGHT,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        children = {
            seedTimerLabel_,
            refreshBtnSeed_,
        },
    }

    -- 种子网格
    for i, seedData in ipairs(seeds) do
        table.insert(listItems, BuildSeedGridItem(seedData, 1.0))
    end

    if #seeds == 0 then
        table.insert(listItems, UI.Panel {
            height = 80,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "提升花园等级解锁更多种子",
                    fontSize = 14,
                    fontColor = {150, 130, 100, 200},
                },
            },
        })
    end

    local listHeight = math.max(SHOP_LIST_MIN_HEIGHT, shopContentMinHeight_ - SHOP_LIST_HEADER_HEIGHT)

    local gridContainer = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "flex-start",
        gap = 4,
        paddingLeft = 4,
        paddingRight = 4,
        children = listItems,
    }

    seedListPanel_ = UI.ScrollView {
        height = listHeight,
        scrollY = true,
        showScrollbar = false,
        bounces = false,
        onScroll = function(self, scrollX, scrollY)
            TrackShopScroll("seed", scrollX, scrollY)
        end,
        children = { gridContainer },
    }
    RestoreShopScrollState("seed", seedListPanel_)

    return UI.Panel {
        height = shopContentMinHeight_,
        children = {
            header,
            seedListPanel_,
        },
    }
end

--- 构建工具商店内容
local function BuildToolShopContent()
    local listItems = {}
    local level = gameRef_.gardenLevel and gameRef_.gardenLevel() or 1

    -- 倒计时 + 刷新按钮行固定在列表上方，不参与滚动，避免撑高商店底图
    local refreshText = state_.adTickets > 0
        and ("刷新 (券x" .. state_.adTickets .. ")")
        or "刷新 (看广告)"

    toolTimerLabel_ = UI.Label {
        text = "下次刷新: " .. FormatTimer(state_.tool.timer),
        fontSize = 12,
        fontColor = {100, 80, 60, 200},
    }

    refreshBtnTool_ = UI.Button {
        text = refreshText,
        height = 30,
        width = 100,
        fontSize = 11,
        variant = "secondary",
        onClick = function()
            ManualRefresh("tool")
            Shop.RebuildShopContent()
        end,
    }

    local header = UI.Panel {
        height = SHOP_LIST_HEADER_HEIGHT,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        children = {
            toolTimerLabel_,
            refreshBtnTool_,
        },
    }

    -- 工具列表
    local hasAny = false
    for _, cfg in ipairs(TOOL_SHOP_CONFIG) do
        if cfg.unlockLevel <= level then
            hasAny = true
            local row = BuildToolItemRow(cfg)
            if row then table.insert(listItems, row) end
        end
    end

    if not hasAny then
        table.insert(listItems, UI.Panel {
            height = 80,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "提升花园等级解锁工具",
                    fontSize = 14,
                    fontColor = {150, 130, 100, 200},
                },
            },
        })
    end

    local listHeight = math.max(SHOP_LIST_MIN_HEIGHT, shopContentMinHeight_ - SHOP_LIST_HEADER_HEIGHT)
    toolListPanel_ = UI.ScrollView {
        height = listHeight,
        scrollY = true,
        showScrollbar = true,
        bounces = false,
        padding = 8,
        onScroll = function(self, scrollX, scrollY)
            TrackShopScroll("tool", scrollX, scrollY)
        end,
        children = listItems,
    }
    RestoreShopScrollState("tool", toolListPanel_)

    return UI.Panel {
        height = shopContentMinHeight_,
        children = {
            header,
            toolListPanel_,
        },
    }
end

--- 构建商店弹窗内容
function Shop.RebuildShopContent()
    if shopModal_ == nil then return end

    SaveShopScrollState(state_.activeTab)

    local content
    if state_.activeTab == "seed" then
        content = BuildSeedShopContent()
    else
        content = BuildToolShopContent()
    end

    -- 重建 Modal 内部内容
    shopModal_:ClearContent()
    shopModal_:AddContent(UI.Tabs {
        height = 44,
        variant = "pills",
        fontSize = 13,
        tabs = {
            { id = "seed", label = "种子商店" },
            { id = "tool", label = "工具商店" },
        },
        activeTab = state_.activeTab,
        onChange = function(self, tabId)
            if tostring(tabId) == "tool" then
                FloatingToast.Show("工具商店暂未开放", { fontSize = 19, duration = 1.4, yRatio = 0.42, priority = 8 })
                pendingTabSwitch_ = "seed"
                return
            end
            -- 延迟到下一帧处理，避免在回调中销毁自身
            pendingTabSwitch_ = tostring(tabId)
        end,
    })
    shopModal_:AddContent(content)
end

-- ============================================================================
-- § 5. 公开接口
-- ============================================================================

--- 初始化商店系统
---@param opts table 配置项
---  opts.PLANTS: 植物配置表
---  opts.getMoney: function() -> number
---  opts.getGardenLevel: function() -> number
---  opts.onBuy: function(cost, plantIndex|nil)  扣钱 + 加背包
---  opts.showToast: function(text)
function Shop.Init(opts)
    gameRef_.PLANTS = opts.PLANTS
    gameRef_.money = opts.getMoney
    gameRef_.gardenLevel = opts.getGardenLevel
    gameRef_.onBuy = opts.onBuy
    gameRef_.requestSeedShop = opts.requestSeedShop
    gameRef_.showToast = opts.showToast
    state_.serverAuthoritative = opts.serverAuthoritative == true

    -- 初始化商店状态（第一次刷新）
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

--- 打开商店弹窗
function Shop.Open()
    state_.isOpen = true
    state_.activeTab = "seed"
    shopScrollState_.seed.x = 0
    shopScrollState_.seed.y = 0
    shopScrollState_.tool.x = 0
    shopScrollState_.tool.y = 0

    -- 计算固定商店高度：弹窗高度固定在屏幕 88%，列表超出时只在列表区域内滚动
    local screenH = graphics:GetHeight() / graphics:GetDPR()
    local modalFixedHeight = math.max(SHOP_BODY_MIN_HEIGHT + SHOP_MODAL_CHROME_HEIGHT, math.floor(screenH * 0.88))
    shopContentMinHeight_ = modalFixedHeight - SHOP_MODAL_CHROME_HEIGHT

    -- 重置逐条渐显动画
    staggerTimer_ = 0
    staggerTotalCount_ = 0
    staggerDone_ = false

    shopModal_ = UI.Modal {
        title = "商店",
        size = "fullscreen",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {8, 12, 8, 12},
        contentGap = 6,
        headerContentGap = 8,
        onClose = function()
            state_.isOpen = false
            shopModal_ = nil
        end,
    }

    Shop.RebuildShopContent()
    ModalAnim.Apply(shopModal_, { fixedHeight = modalFixedHeight })
    shopModal_:Open()

    if state_.serverAuthoritative then
        RequestSeedShopFromServer()
    end

    print("[Shop] 商店已打开")
end

--- 关闭商店弹窗
function Shop.Close()
    if shopModal_ ~= nil then
        shopModal_:Close()
        shopModal_ = nil
    end
    state_.isOpen = false
end

--- 每帧更新（由主循环调用）
---@param dt number 帧间隔
function Shop.Update(dt)
    local seedRefreshed = false
    local toolRefreshed = false

    -- 更新种子商店倒计时
    if state_.serverAuthoritative then
        state_.seed.localElapsedSinceServerSync = state_.seed.localElapsedSinceServerSync + dt
        UpdateSeedTimerFromServerClock()
        if state_.seed.timer <= 0 and state_.seed.awaitingServer ~= true then
            if RequestSeedShopFromServer() then
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

    -- 更新工具商店倒计时
    if state_.tool.timer > 0 then
        state_.tool.timer = state_.tool.timer - dt
        if state_.tool.timer <= 0 then
            RefreshToolStock()
            toolRefreshed = true
        end
    end

    if state_.isOpen and shopModal_ ~= nil then
        if (state_.activeTab == "seed" and seedRefreshed) or (state_.activeTab == "tool" and toolRefreshed) then
            staggerTimer_ = 0
            staggerDone_ = false
            Shop.RebuildShopContent()
        end
    end

    -- 处理延迟 tab 切换
    if pendingTabSwitch_ ~= nil then
        state_.activeTab = pendingTabSwitch_
        pendingTabSwitch_ = nil
        staggerTimer_ = 0
        staggerDone_ = false
        Shop.RebuildShopContent()
    end

    -- 更新 UI 上的计时器显示（仅商店打开时）
    if state_.isOpen and shopModal_ ~= nil then
        if state_.activeTab == "seed" and seedTimerLabel_ ~= nil then
            local ts = math.max(0, math.floor(state_.seed.timer))
            seedTimerLabel_:SetText(string.format("全服刷新倒计时 %d:%02d", math.floor(ts / 60), ts % 60))
        elseif state_.activeTab == "tool" and toolTimerLabel_ ~= nil then
            toolTimerLabel_:SetText("下次刷新: " .. FormatTimer(state_.tool.timer))
        end


    end
end

--- 处理离线恢复
function Shop.HandleOffline()
    if state_.serverAuthoritative then
        local serverTime = os.time()
        state_.seed.serverTimeBase = serverTime
        state_.seed.localElapsedSinceServerSync = 0
        state_.seed.nextRefreshAt = serverTime + GetSeedRefreshRemaining(serverTime)
        state_.seed.timer = state_.seed.nextRefreshAt - state_.seed.serverTimeBase
        state_.seed.refreshId = GetSeedRefreshId(serverTime)
        state_.seed.lastRefreshRealTime = serverTime
        RequestSeedShopFromServer()
    else
        HandleOfflineTime("seed")
    end
    HandleOfflineTime("tool")
end

--- 获取当前商店是否打开
function Shop.IsOpen()
    return state_.isOpen
end

--- 设置广告券数量
function Shop.SetAdTickets(count)
    state_.adTickets = count
end

--- 获取广告券数量
function Shop.GetAdTickets()
    return state_.adTickets
end

--- 创建商店入口按钮（左上角）
---@param opts table|nil  可选样式覆盖
---@return Widget
function Shop.CreateEntryButton(opts)
    opts = opts or {}
    return UI.Button {
        text = opts.text or "商店",
        width = opts.width or 60,
        height = opts.height or 36,
        fontSize = opts.fontSize or 13,
        fontWeight = "bold",
        variant = "primary",
        borderRadius = 12,
        onClick = function()
            Shop.Open()
        end,
    }
end

--- 获取商店状态（用于存档）
function Shop.GetSaveData()
    return {
        seed = {
            stock = state_.seed.stock,
            items = state_.seed.items,
            timer = state_.seed.timer,
            lastRefreshRealTime = state_.seed.lastRefreshRealTime,
            refreshId = state_.seed.refreshId,
            serverTimeBase = state_.seed.serverTimeBase,
            localElapsedSinceServerSync = state_.seed.localElapsedSinceServerSync,
            nextRefreshAt = state_.seed.nextRefreshAt,
        },
        tool = {
            stock = state_.tool.stock,
            timer = state_.tool.timer,
            lastRefreshRealTime = state_.tool.lastRefreshRealTime,
        },
        adTickets = state_.adTickets,
    }
end

--- 从存档加载商店状态
function Shop.LoadSaveData(data)
    if data == nil then return end
    if data.seed then
        state_.seed.stock = data.seed.stock or {}
        state_.seed.items = data.seed.items or {}
        state_.seed.timer = data.seed.timer or 0
        state_.seed.lastRefreshRealTime = data.seed.lastRefreshRealTime or 0
        state_.seed.refreshId = data.seed.refreshId or 0
        state_.seed.serverTimeBase = data.seed.serverTimeBase or state_.seed.lastRefreshRealTime or 0
        state_.seed.localElapsedSinceServerSync = data.seed.localElapsedSinceServerSync or 0
        state_.seed.nextRefreshAt = data.seed.nextRefreshAt or 0
        if #state_.seed.items == 0 and not state_.serverAuthoritative then
            RefreshSeedStock()
        end
    end
    if data.tool then
        state_.tool.stock = data.tool.stock or {}
        state_.tool.timer = data.tool.timer or 0
        state_.tool.lastRefreshRealTime = data.tool.lastRefreshRealTime or 0
    end
    state_.adTickets = data.adTickets or 0

    -- 处理离线刷新
    Shop.HandleOffline()
end

--- 应用服务器下发的全服种子商店状态
function Shop.ApplyServerSeedShop(data)
    if SyncSeedShopFromData(data) then
        if state_.isOpen and shopModal_ ~= nil and state_.activeTab == "seed" then
            Shop.RebuildShopContent()
        end
        return true
    end
    state_.seed.awaitingServer = false
    return false
end

return Shop
