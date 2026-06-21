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

-- 种子商店配置
-- showInShop: 是否会在商店中出现（刷新时是否可能出现库存）
-- unlockLevel: 花园等级达到多少时解锁显示
-- refreshStock: 每次刷新时补充的库存数量
local SEED_SHOP_CONFIG = {
    -- 普通
    { name = "胡萝卜",  showInShop = true,  unlockLevel = 1, refreshStock = 5 },
    { name = "番茄",    showInShop = true,  unlockLevel = 1, refreshStock = 4 },
    { name = "玉米",    showInShop = true,  unlockLevel = 1, refreshStock = 5 },
    { name = "葡萄",    showInShop = true,  unlockLevel = 1, refreshStock = 4 },
    -- 罕见
    { name = "草莓",    showInShop = true,  unlockLevel = 2, refreshStock = 3 },
    { name = "花椰菜",  showInShop = true,  unlockLevel = 2, refreshStock = 3 },
    { name = "南瓜",    showInShop = true,  unlockLevel = 2, refreshStock = 2 },
    { name = "凤梨",    showInShop = true,  unlockLevel = 3, refreshStock = 2 },
    { name = "芒果",    showInShop = true,  unlockLevel = 2, refreshStock = 3 },
    { name = "香蕉",    showInShop = true,  unlockLevel = 3, refreshStock = 2 },
    -- 稀有
    { name = "郁金香",  showInShop = true,  unlockLevel = 3, refreshStock = 2 },
    { name = "西瓜",    showInShop = true,  unlockLevel = 3, refreshStock = 2 },
    { name = "蘑菇",    showInShop = true,  unlockLevel = 4, refreshStock = 1 },
    { name = "仙人掌",  showInShop = true,  unlockLevel = 4, refreshStock = 1 },
    { name = "竹子",    showInShop = true,  unlockLevel = 4, refreshStock = 2 },
    { name = "椰子",    showInShop = true,  unlockLevel = 4, refreshStock = 1 },
    -- 史诗
    { name = "波斯菊",  showInShop = true,  unlockLevel = 5, refreshStock = 1 },
    { name = "向日葵",  showInShop = true,  unlockLevel = 5, refreshStock = 1 },
    { name = "辣椒",    showInShop = true,  unlockLevel = 5, refreshStock = 1 },
    { name = "百合",    showInShop = true,  unlockLevel = 6, refreshStock = 1 },
    { name = "杜鹃",    showInShop = true,  unlockLevel = 5, refreshStock = 1 },
    { name = "玉兰",    showInShop = true,  unlockLevel = 6, refreshStock = 1 },
    -- 传奇
    { name = "三色堇",  showInShop = false, unlockLevel = 7, refreshStock = 0 },
    { name = "玫瑰",    showInShop = true,  unlockLevel = 7, refreshStock = 1 },
    { name = "蒲公英",  showInShop = true,  unlockLevel = 7, refreshStock = 1 },
    { name = "风信子",  showInShop = false, unlockLevel = 8, refreshStock = 0 },
    { name = "绣球花",  showInShop = false, unlockLevel = 8, refreshStock = 0 },
    { name = "杨桃",    showInShop = false, unlockLevel = 9, refreshStock = 0 },
    { name = "牡丹",    showInShop = false, unlockLevel = 8, refreshStock = 0 },
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

local state_ = {
    seed = {
        stock = {},         -- { [seedName] = quantity }
        timer = 0,          -- 倒计时剩余秒数
        lastRefreshRealTime = 0,
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
}

-- UI 引用
local shopContentMinHeight_ = 400  -- 会在 Open 时根据屏幕高度重新计算
local shopModal_ = nil
local seedListPanel_ = nil
local toolListPanel_ = nil
local seedTimerLabel_ = nil
local toolTimerLabel_ = nil
local refreshBtnSeed_ = nil
local refreshBtnTool_ = nil

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

--- 获取种子在商店配置中的信息
local function GetSeedShopInfo(seedName)
    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        if cfg.name == seedName then
            return cfg
        end
    end
    return nil
end

--- 执行一次种子商店刷新
--- 规则：刷新后库存不叠加，但未购买的库存也不归零
local function RefreshSeedStock()
    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        if cfg.showInShop and cfg.refreshStock > 0 then
            local currentStock = state_.seed.stock[cfg.name] or 0
            -- 设置为刷新数量（不叠加，但不归零已有的）
            -- 即: new_stock = max(currentStock, refreshStock)
            local newStock = math.max(currentStock, cfg.refreshStock)
            state_.seed.stock[cfg.name] = newStock
        end
    end
    state_.seed.timer = REFRESH_CONFIG.seed.interval
    state_.seed.lastRefreshRealTime = os.time()
    print("[Shop] 种子商店已刷新")
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

--- 获取已解锁的种子列表（按稀有度排序）
local function GetUnlockedSeeds()
    local level = gameRef_.gardenLevel and gameRef_.gardenLevel() or 1
    local result = {}

    for _, cfg in ipairs(SEED_SHOP_CONFIG) do
        if cfg.unlockLevel <= level then
            local plantIdx = FindPlantIndex(cfg.name)
            if plantIdx ~= nil then
                local plant = gameRef_.PLANTS[plantIdx]
                table.insert(result, {
                    name = cfg.name,
                    plantIndex = plantIdx,
                    plant = plant,
                    shopCfg = cfg,
                    stock = state_.seed.stock[cfg.name] or 0,
                    rarity = plant.rarity,
                    rarityOrder = RARITY_ORDER[plant.rarity] or 0,
                    price = plant.seedPrice,
                })
            end
        end
    end

    -- 按稀有度从低到高排序
    table.sort(result, function(a, b)
        if a.rarityOrder ~= b.rarityOrder then
            return a.rarityOrder < b.rarityOrder
        end
        return a.price < b.price
    end)

    return result
end

--- 购买种子
local function BuySeed(seedName)
    local stock = state_.seed.stock[seedName] or 0
    if stock <= 0 then
        if gameRef_.showToast then gameRef_.showToast("该种子暂无库存") end
        return false
    end

    local plantIdx = FindPlantIndex(seedName)
    if plantIdx == nil then return false end

    local plant = gameRef_.PLANTS[plantIdx]
    local currentMoney = gameRef_.money and gameRef_.money() or 0

    if currentMoney < plant.seedPrice then
        if gameRef_.showToast then gameRef_.showToast("金币不足") end
        return false
    end

    -- 扣钱
    if gameRef_.onBuy then
        gameRef_.onBuy(plant.seedPrice, plantIdx)
    end

    -- 扣库存
    state_.seed.stock[seedName] = stock - 1
    print(string.format("[Shop] 购买种子: %s, 花费 %d, 剩余库存 %d", seedName, plant.seedPrice, stock - 1))
    return true
end

--- 购买工具（预留）
local function BuyTool(toolName)
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

    buyConfirmModal_:AddContent(UI.Panel {
        alignItems = "center", gap = 12, padding = 12,
        children = {
            UI.Label { text = "单价: " .. price .. " 金币", fontSize = 14, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "库存: " .. stock .. "  |  持有: " .. currentMoney .. " 金币", fontSize = 12, fontColor = {120, 100, 80, 200} },
            -- 按钮行
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8,
                children = {
                    UI.Button {
                        text = "购买 x1", width = 100, height = 38, fontSize = 13, fontWeight = "bold",
                        variant = "primary", borderRadius = 10,
                        disabled = stock < 1 or currentMoney < price,
                        onClick = function()
                            if BuySeed(seedData.name) then
                                if gameRef_.showToast then gameRef_.showToast("已购买!") end
                            end
                            if buyConfirmModal_ then buyConfirmModal_:Close() end
                            Shop.RebuildShopContent()
                        end,
                    },
                    UI.Button {
                        text = "购买 x10", width = 100, height = 38, fontSize = 13, fontWeight = "bold",
                        variant = "primary", borderRadius = 10,
                        disabled = stock < 1 or currentMoney < price,
                        onClick = function()
                            local bought = 0
                            for _ = 1, 10 do
                                if BuySeed(seedData.name) then
                                    bought = bought + 1
                                else
                                    break
                                end
                            end
                            if bought > 0 then
                                if gameRef_.showToast then gameRef_.showToast("已购买 x" .. bought .. "!") end
                            end
                            if buyConfirmModal_ then buyConfirmModal_:Close() end
                            Shop.RebuildShopContent()
                        end,
                    },
                },
            },
        },
    })
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
            UI.Label { text = "基础售价: " .. plant.fruitPrice .. " 金币", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "种子价格: " .. plant.seedPrice .. " 金币", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = string.format("变异概率: 颜色%.0f%% 特殊%.0f%%", plant.colorProb * 100, plant.specialProb * 100), fontSize = 12, fontColor = {120, 100, 80, 200} },
        },
    })
    detailModal:Open()
end

local function BuildSeedItemRow(seedData, itemAlpha)
    itemAlpha = itemAlpha or 1.0
    local hasStock = seedData.stock > 0
    local canAppear = seedData.shopCfg.showInShop
    local rarityColor = RARITY_COLORS[seedData.rarity] or {200, 200, 200, 255}
    local plantColor = seedData.plant.color
    local a = itemAlpha

    -- 种子图标色块（取作物主色）
    local iconBg = ApplyAlpha({
        math.floor(plantColor.r * 255),
        math.floor(plantColor.g * 255),
        math.floor(plantColor.b * 255), 255
    }, a)

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        marginBottom = 6,
        backgroundColor = ApplyAlpha(hasStock and {255, 253, 245, 255} or {240, 238, 230, 200}, a),
        borderRadius = 12,
        borderWidth = 1,
        borderColor = ApplyAlpha(hasStock and {195, 180, 150, 150} or {180, 175, 165, 80}, a),
        onClick = function()
            if hasStock then
                ShowBuyConfirm(seedData)
            else
                if gameRef_.showToast then gameRef_.showToast("库存不足，等待刷新") end
            end
        end,
        children = {
            -- 左：种子3D图标（无圆角裁剪）
            UI.Panel {
                width = 48, height = 48,
                marginRight = 12,
                children = {
                    UI.Panel {
                        width = 48, height = 48,
                        backgroundImage = string.format(SEED_ICON_PATH, seedData.plantIndex),
                        backgroundSize = "contain",
                    },
                },
            },
            -- 中：名称 + 库存 + 价格
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 3,
                children = {
                    UI.Label {
                        text = seedData.name .. "种子",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = ApplyAlpha({70, 50, 35, 255}, a),
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 12,
                        children = {
                            UI.Label {
                                text = hasStock and ("x" .. seedData.stock .. " 库存") or "无库存",
                                fontSize = 13,
                                fontColor = ApplyAlpha(hasStock and {90, 150, 100, 255} or {180, 100, 80, 255}, a),
                            },
                            -- 金币图标 + 价格
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 3,
                                children = {
                                    UI.Panel {
                                        width = 14, height = 14,
                                        justifyContent = "center", alignItems = "center",
                                        children = {
                                            UI.Panel { width = 14, height = 14, borderRadius = 7, backgroundColor = ApplyAlpha({255, 205, 60, 255}, a) },
                                            UI.Label { position = "absolute", text = "$", fontSize = 8, fontWeight = "bold", fontColor = ApplyAlpha({180, 130, 20, 255}, a) },
                                        },
                                    },
                                    UI.Label {
                                        text = tostring(seedData.price),
                                        fontSize = 13, fontWeight = "bold",
                                        fontColor = ApplyAlpha({80, 160, 60, 255}, a),
                                    },
                                },
                            },
                            -- 限量标识（稀有度≥史诗）
                            (seedData.rarityOrder >= 4 and not hasStock) and UI.Label {
                                text = "限量!",
                                fontSize = 10, fontWeight = "bold",
                                fontColor = ApplyAlpha({220, 60, 50, 255}, a),
                            } or nil,
                        },
                    },
                },
            },
            -- 右：稀有度标签（可点击查看详情）
            UI.Button {
                text = seedData.rarity,
                height = 30, fontSize = 12, fontWeight = "bold",
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = ApplyAlpha(rarityColor, a),
                fontColor = ApplyAlpha({255, 255, 255, 255}, a),
                borderRadius = 8,
                onClick = function()
                    ShowSeedDetail(seedData)
                end,
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
    local seeds = GetUnlockedSeeds()
    local items = {}

    -- 倒计时 + 黄色刷新按钮
    local timerSec = math.max(0, math.floor(state_.seed.timer))
    local m = math.floor(timerSec / 60)
    local s = timerSec % 60

    seedTimerLabel_ = UI.Label {
        text = string.format("刷新倒计时 %d:%02d", m, s),
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {100, 80, 60, 220},
    }

    refreshBtnSeed_ = UI.Button {
        text = "▶ 刷新",
        height = 30,
        width = 86,
        fontSize = 11,
        fontWeight = "bold",
        backgroundColor = {245, 195, 50, 255},
        fontColor = {60, 40, 10, 255},
        borderRadius = 8,
        onClick = function()
            ManualRefresh("seed")
            Shop.RebuildShopContent()
        end,
    }

    table.insert(items, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 8,
        paddingLeft = 4,
        paddingRight = 4,
        children = {
            seedTimerLabel_,
            refreshBtnSeed_,
        },
    })

    -- 种子列表（逐条渐显）
    staggerTotalCount_ = #seeds
    for i, seedData in ipairs(seeds) do
        local alpha = GetItemAlpha(i)
        if alpha > 0 then
            table.insert(items, BuildSeedItemRow(seedData, alpha))
        end
    end

    if #seeds == 0 then
        table.insert(items, UI.Panel {
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

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        minHeight = shopContentMinHeight_,
        scrollY = true,
        padding = 8,
        children = items,
    }
end

--- 构建工具商店内容
local function BuildToolShopContent()
    local items = {}
    local level = gameRef_.gardenLevel and gameRef_.gardenLevel() or 1

    -- 倒计时 + 刷新按钮行
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

    table.insert(items, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 8,
        paddingLeft = 4,
        paddingRight = 4,
        children = {
            toolTimerLabel_,
            refreshBtnTool_,
        },
    })

    -- 工具列表（逐条渐显）
    local hasAny = false
    local toolIndex = 0
    for _, cfg in ipairs(TOOL_SHOP_CONFIG) do
        if cfg.unlockLevel <= level then
            hasAny = true
            toolIndex = toolIndex + 1
            local alpha = GetItemAlpha(toolIndex)
            if alpha > 0 then
                local row = BuildToolItemRow(cfg)
                if row then table.insert(items, row) end
            end
        end
    end
    staggerTotalCount_ = toolIndex

    if not hasAny then
        table.insert(items, UI.Panel {
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

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        minHeight = shopContentMinHeight_,
        scrollY = true,
        padding = 8,
        children = items,
    }
end

--- 构建商店弹窗内容
function Shop.RebuildShopContent()
    if shopModal_ == nil then return end

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
    gameRef_.showToast = opts.showToast

    -- 初始化商店状态（第一次刷新）
    RefreshSeedStock()
    RefreshToolStock()

    print("[Shop] 商店系统初始化完成")
end

--- 打开商店弹窗
function Shop.Open()
    state_.isOpen = true

    -- 计算目标高度（屏幕70%）用于 ScrollView minHeight
    local screenH = graphics:GetHeight() / graphics:GetDPR()
    shopContentMinHeight_ = math.floor(screenH * 0.70) - 120  -- 减去标题+tabs+padding

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
        onClose = function()
            state_.isOpen = false
            shopModal_ = nil
        end,
    }

    Shop.RebuildShopContent()
    shopModal_:Open()

    -- 减慢动画速度（默认 speed=8 太快，改为 3）
    local origUpdate = shopModal_.Update
    shopModal_.Update = function(self, dt)
        local speed = 3
        if self.animProgress_ < self.targetAnimProgress_ then
            self.animProgress_ = math.min(self.targetAnimProgress_, self.animProgress_ + dt * speed)
        elseif self.animProgress_ > self.targetAnimProgress_ then
            self.animProgress_ = math.max(self.targetAnimProgress_, self.animProgress_ - dt * speed)
        end
        -- 仍需更新子组件树
        local function updateTree(widget)
            if widget.Update then widget:Update(dt) end
            for _, child in ipairs(widget.children or {}) do updateTree(child) end
        end
        if #self.contentContainer_.children > 0 then updateTree(self.contentContainer_) end
        if self.footerWidget_ then updateTree(self.footerWidget_) end
    end

    -- 重写渲染：去掉缩放动画，只保留透明度 0→1 渐变
    shopModal_.RenderModalContent = function(self, nvg)
        local UI_mod = require("urhox-libs/UI/Core/UI")
        local Theme = require("urhox-libs/UI/Core/Theme")
        local Widget = require("urhox-libs/UI/Core/Widget")
        local screenWidth = UI_mod.GetWidth() or 800
        local screenHeight = UI_mod.GetHeight() or 600
        local borderRadius = self.borderRadius_
        local title = self.title_
        local showCloseButton = self.showCloseButton_

        local headerHeight = 56
        local cp = self.props.contentPadding or 16
        local cpTop, cpRight, cpBottom, cpLeft
        if type(cp) == "table" then
            cpTop, cpRight, cpBottom, cpLeft = cp[1], cp[2], cp[3], cp[4]
        else
            cpTop, cpRight, cpBottom, cpLeft = cp, cp, cp, cp
        end

        -- 90% 宽, 90% 高（会被 minHeight 撑到约 70%）
        local modalWidth = screenWidth * 0.90
        local modalMaxHeight = screenHeight * 0.90

        local footerHeight = 64
        if self.footerWidget_ then
            local fp = self.props.footerPadding
            local fpTop, fpRight, fpBottom, fpLeft = fp[1], fp[2], fp[3], fp[4]
            local footerContentWidth = modalWidth - fpLeft - fpRight
            YGNodeCalculateLayout(self.footerWidget_.node, footerContentWidth, YGUndefined, YGDirectionLTR)
            local measuredFooter = YGNodeLayoutGetHeight(self.footerWidget_.node)
            footerHeight = math.max(64, measuredFooter + fpTop + fpBottom)
        end

        -- 关键：alpha 控制遮罩/背景渐显，内容始终满透明度，无缩放
        local alpha = self.animProgress_

        -- 遮罩（平方缓入，前半段几乎透明，后半段才变暗）
        local overlayAlpha = math.floor(alpha * alpha * 160)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, screenWidth, screenHeight)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, overlayAlpha))
        nvgFill(nvg)

        local contentAreaWidth = modalWidth - cpLeft - cpRight
        local modalHeight = self:CalculateContentHeight(contentAreaWidth) + cpTop + cpBottom + (title and headerHeight or 0) + (self.footerWidget_ and footerHeight or 0)
        modalHeight = math.min(modalHeight, modalMaxHeight)

        local modalX = (screenWidth - modalWidth) / 2
        local modalY = (screenHeight - modalHeight) / 2

        -- 无缩放变换
        nvgSave(nvg)

        -- 阴影（带 alpha）
        local boxShadow = self.props.boxShadow
        if boxShadow == false then
        elseif boxShadow then
            nvgSave(nvg)
            nvgGlobalAlpha(nvg, alpha)
            local geom = self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius)
            self:RenderBoxShadows(nvg, geom, boxShadow)
            nvgRestore(nvg)
        else
            nvgBeginPath(nvg)
            self:CreateShapePath(nvg, self:GetShapeGeometry(
                { x = modalX - 4, y = modalY - 2, w = modalWidth + 8, h = modalHeight + 12 },
                nil,
                Widget.OffsetRadius(borderRadius, 4)
            ))
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(60 * alpha)))
            nvgFill(nvg)
        end

        -- 背景（带 alpha 渐显）
        local bgColor = Theme.Color("surface")
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius))
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], math.floor(255 * alpha)))
        nvgFill(nvg)

        -- 边框（带 alpha）
        local borderColor = self.props.borderColor or Theme.Color("border")
        local borderAlpha = self.props.borderColor and (borderColor[4] or 255) or 100
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], math.floor(borderAlpha * alpha)))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)

        self.modalLayout_ = { x = modalX, y = modalY, w = modalWidth, h = modalHeight }

        local contentY = modalY
        if title then
            contentY = self:RenderHeader(nvg, modalX, modalY, modalWidth, title, showCloseButton, alpha)
        elseif showCloseButton then
            self:RenderCloseButton(nvg, modalX + modalWidth - 44, modalY + 8, alpha)
            contentY = modalY + 16
        end

        -- 内容区域裁剪和渲染（等背景渐显完成后再显示内容）
        local footerHeightActual = self.footerWidget_ and footerHeight or 0
        local clipY = contentY
        local clipHeight = math.max(0, modalHeight - (contentY - modalY) - footerHeightActual)

        if #self.contentContainer_.children > 0 and alpha >= 0.8 then
            YGNodeCalculateLayout(self.contentContainer_.node, contentAreaWidth, clipHeight, YGDirectionLTR)

            self.contentContainer_.renderOffsetX_ = modalX + cpLeft
            self.contentContainer_.renderOffsetY_ = contentY
            self.contentContainer_.renderWidth_ = contentAreaWidth
            self.contentContainer_.renderHeight_ = clipHeight

            nvgSave(nvg)
            nvgIntersectScissor(nvg, modalX, clipY, modalWidth, clipHeight)
            UI_mod.RenderWidgetSubtree(self.contentContainer_, nvg)
            nvgRestore(nvg)
        end

        -- Footer
        if self.footerWidget_ then
            self:RenderFooter(nvg, modalX, modalY + modalHeight - footerHeight, modalWidth, footerHeight, alpha)
        end

        nvgRestore(nvg)
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
    -- 更新种子商店倒计时
    if state_.seed.timer > 0 then
        state_.seed.timer = state_.seed.timer - dt
        if state_.seed.timer <= 0 then
            RefreshSeedStock()
        end
    end

    -- 更新工具商店倒计时
    if state_.tool.timer > 0 then
        state_.tool.timer = state_.tool.timer - dt
        if state_.tool.timer <= 0 then
            RefreshToolStock()
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
            seedTimerLabel_:SetText(string.format("刷新倒计时 %d:%02d", math.floor(ts / 60), ts % 60))
        elseif state_.activeTab == "tool" and toolTimerLabel_ ~= nil then
            toolTimerLabel_:SetText("下次刷新: " .. FormatTimer(state_.tool.timer))
        end

        -- 逐条渐显动画（等背景显示完毕后再开始）
        if not staggerDone_ then
            -- 等待弹窗背景基本就绪（animProgress >= 0.8）才开始计时
            if shopModal_.animProgress_ >= 0.8 then
                staggerTimer_ = staggerTimer_ + dt
                -- 检查是否所有条目都已完全显示（无条目时立即完成）
                if staggerTotalCount_ <= 0 then
                    staggerDone_ = true
                elseif staggerTimer_ >= (staggerTotalCount_ - 1) * STAGGER_DELAY + STAGGER_FADE then
                    staggerDone_ = true
                end
            end
            Shop.RebuildShopContent()
        end
    end
end

--- 处理离线恢复
function Shop.HandleOffline()
    HandleOfflineTime("seed")
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
            timer = state_.seed.timer,
            lastRefreshRealTime = state_.seed.lastRefreshRealTime,
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
        state_.seed.timer = data.seed.timer or 0
        state_.seed.lastRefreshRealTime = data.seed.lastRefreshRealTime or 0
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

return Shop
