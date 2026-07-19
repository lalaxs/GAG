-- ============================================================================
-- 商店 UI 视图 (Shop View)
-- Grow A Garden - 种子商店 & 工具商店界面
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")
local SeedShopSystem = require("systems.seed_shop_system")

local ShopView = {}

local system_ = SeedShopSystem
local onRebuild_ = nil
local display_ = nil

local shopContentMinHeight_ = 400
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

local STAGGER_DELAY = 0.12
local STAGGER_FADE = 0.18
local staggerTimer_ = 0
local staggerTotalCount_ = 0
local staggerDone_ = false
local pendingTabSwitch_ = nil

local buyConfirmSeed_ = nil
local buyConfirmModal_ = nil

local function GetDisplay()
    if display_ == nil then
        display_ = system_.GetDisplayConfig()
    end
    return display_
end

local function GetState()
    return system_.GetState()
end

local function GetGameRef()
    return system_.GetGameRef()
end

local function RequestRebuild()
    if onRebuild_ then
        onRebuild_()
    else
        ShopView.RebuildShopContent()
    end
end

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

local function BuildShopStatusPanel(message, buttonText)
    return UI.Panel {
        height = math.max(160, shopContentMinHeight_ - GetDisplay().SHOP_LIST_HEADER_HEIGHT),
        alignItems = "center",
        justifyContent = "center",
        gap = 12,
        paddingLeft = 20,
        paddingRight = 20,
        children = {
            UI.Label {
                text = message,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = {120, 96, 68, 220},
                textAlign = "center",
                whiteSpace = "normal",
            },
            buttonText ~= nil and UI.Button {
                text = buttonText,
                width = 128,
                height = 40,
                fontSize = 14,
                fontWeight = "bold",
                variant = "primary",
                borderRadius = 14,
                onClick = function()
                    local gameRef = GetGameRef()
                    if system_.RequestSeedShopFromServer() then
                        if gameRef.showToast then gameRef.showToast("正在同步全服商店...") end
                    end
                    RequestRebuild()
                end,
            } or nil,
        },
    }
end

local function GetItemAlpha(index)
    if staggerDone_ then return 1.0 end
    local appearStart = (index - 1) * STAGGER_DELAY
    local elapsed = staggerTimer_ - appearStart
    if elapsed <= 0 then return 0.0 end
    if elapsed >= STAGGER_FADE then return 1.0 end
    return elapsed / STAGGER_FADE
end

local function ApplyAlpha(color, alpha)
    if alpha >= 1.0 then return color end
    return {color[1], color[2], color[3], math.floor((color[4] or 255) * alpha)}
end

local RARITY_BG_COLORS = {
    ["普通"] = {242, 238, 225, 255},
    ["罕见"] = {218, 242, 220, 255},
    ["稀有"] = {215, 232, 252, 255},
    ["史诗"] = {235, 218, 252, 255},
    ["传奇"] = {255, 235, 200, 255},
}

local function ShowBuyConfirm(seedData)
    local display = GetDisplay()
    local gameRef = GetGameRef()
    local state = GetState()

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

    local stock = state.seed.stock[seedData.name] or 0
    local price = seedData.price
    local currentMoney = gameRef.money and gameRef.money() or 0
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
                        local bought = system_.BuySeed(seedData.name, count)
                        if bought > 0 then
                            if state.serverAuthoritative then
                                if gameRef.showToast then gameRef.showToast("购买请求已发送，等待服务器确认") end
                            else
                                if gameRef.showToast then gameRef.showToast("已购买 x" .. bought .. "!") end
                            end
                            if buyConfirmModal_ then buyConfirmModal_:Close() end
                            RequestRebuild()
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
                        backgroundImage = string.format(display.SEED_ICON_PATH, seedData.plantIndex),
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

local function ShowSeedDetail(seedData)
    local display = GetDisplay()
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
            UI.Label { text = "稀有度: " .. seedData.rarity, fontSize = 14, fontWeight = "bold", fontColor = display.RARITY_COLORS[seedData.rarity] or {100,100,100,255} },
            UI.Label { text = "成熟时长: " .. plant.growTime .. " 秒", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "收益基准价: " .. plant.seedPrice .. " 金币", fontSize = 13, fontColor = {80, 60, 40, 255} },
            UI.Label { text = "成熟售价会随重量和变异波动", fontSize = 12, fontColor = {120, 100, 80, 200} },
            UI.Label { text = "变异规则: 颜色约9%，特殊约2.5%，天赋可相对提升", fontSize = 12, fontColor = {120, 100, 80, 200} },
        },
    })
    ModalAnim.Apply(detailModal)
    detailModal:Open()
end

local function BuildSeedGridItem(seedData, itemAlpha)
    local display = GetDisplay()
    local gameRef = GetGameRef()

    itemAlpha = itemAlpha or 1.0
    local hasStock = seedData.stock > 0
    local bgColor = RARITY_BG_COLORS[seedData.rarity] or {240, 238, 230, 255}
    local a = itemAlpha

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
                if gameRef.showToast then gameRef.showToast("已售罄，等待刷新") end
            end
        end,
        children = {
            UI.Panel {
                width = 46, height = 46,
                marginBottom = 5,
                children = {
                    UI.Panel {
                        width = 46, height = 46,
                        backgroundImage = string.format(display.SEED_ICON_PATH, seedData.plantIndex),
                        backgroundSize = "contain",
                    },
                },
            },
            UI.Label {
                text = seedData.name .. "种子",
                fontSize = 13, fontWeight = "bold",
                fontColor = ApplyAlpha(seedData.nameColor, a),
                marginBottom = 3,
            },
            UI.Label {
                text = "库存 " .. seedData.stock,
                fontSize = 11,
                fontColor = ApplyAlpha(hasStock and {95, 130, 100, 255} or {160, 140, 115, 255}, a),
                marginBottom = 6,
            },
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
    local gameRef = GetGameRef()
    local state = GetState()
    local stock = state.tool.stock[toolCfg.name] or 0
    local hasStock = stock > 0
    local level = gameRef.gardenLevel and gameRef.gardenLevel() or 1
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
            UI.Label {
                text = stockText,
                fontSize = 12,
                fontWeight = "bold",
                fontColor = stockColor,
                marginRight = 8,
            },
            UI.Button {
                text = "购买",
                height = 32,
                width = 56,
                fontSize = 12,
                variant = "primary",
                disabled = not hasStock,
                onClick = function()
                    if system_.BuyTool(toolCfg.name) then
                        RequestRebuild()
                    end
                end,
            },
        },
    }
end

local function BuildSeedShopContent()
    local display = GetDisplay()
    local state = GetState()
    local gameRef = GetGameRef()
    local seeds = system_.GetCurrentSeedShopItems()
    local listItems = {}

    local timerSec = math.max(0, math.floor(state.seed.timer))
    local m = math.floor(timerSec / 60)
    local s = timerSec % 60

    seedTimerLabel_ = UI.Label {
        text = string.format("全服刷新倒计时 %d:%02d", m, s),
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {100, 80, 60, 220},
    }

    refreshBtnSeed_ = UI.Button {
        text = state.serverAuthoritative and "同步" or "▶ 刷新",
        height = 30,
        width = 86,
        fontSize = 11,
        fontWeight = "bold",
        backgroundColor = {245, 195, 50, 255},
        fontColor = {60, 40, 10, 255},
        borderRadius = 8,
        onClick = function()
            if state.serverAuthoritative then
                if system_.RequestSeedShopFromServer() and gameRef.showToast then gameRef.showToast("正在同步全服商店...") end
            else
                system_.ManualRefresh("seed")
                RequestRebuild()
            end
        end,
    }

    local header = UI.Panel {
        height = display.SHOP_LIST_HEADER_HEIGHT,
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

    local listHeight = math.max(display.SHOP_LIST_MIN_HEIGHT, shopContentMinHeight_ - display.SHOP_LIST_HEADER_HEIGHT)

    local bodyContent
    if state.serverAuthoritative and state.seed.lastError ~= nil and state.seed.lastError ~= "" then
        bodyContent = BuildShopStatusPanel(state.seed.lastError, "重试同步")
    elseif state.serverAuthoritative and state.seed.awaitingServer == true and #seeds == 0 then
        bodyContent = BuildShopStatusPanel("正在同步全服商店...", nil)
    else
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
        bodyContent = seedListPanel_
    end

    return UI.Panel {
        height = shopContentMinHeight_,
        children = {
            header,
            bodyContent,
        },
    }
end

local function BuildToolShopContent()
    local display = GetDisplay()
    local state = GetState()
    local listItems = {}
    local level = GetGameRef().gardenLevel and GetGameRef().gardenLevel() or 1

    local refreshText = state.adTickets > 0
        and ("刷新 (券x" .. state.adTickets .. ")")
        or "刷新 (看广告)"

    toolTimerLabel_ = UI.Label {
        text = "下次刷新: " .. system_.FormatTimer(state.tool.timer),
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
            system_.ManualRefresh("tool")
            RequestRebuild()
        end,
    }

    local header = UI.Panel {
        height = display.SHOP_LIST_HEADER_HEIGHT,
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

    local hasAny = false
    for _, cfg in ipairs(display.TOOL_SHOP_CONFIG) do
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

    local listHeight = math.max(display.SHOP_LIST_MIN_HEIGHT, shopContentMinHeight_ - display.SHOP_LIST_HEADER_HEIGHT)
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

function ShopView.Init(opts)
    opts = opts or {}
    if opts.system ~= nil then
        system_ = opts.system
    end
    onRebuild_ = opts.onRebuild
    display_ = nil
end

function ShopView.IsOpen()
    if shopModal_ ~= nil or buyConfirmModal_ ~= nil then return true end
    return system_.IsOpen()
end

function ShopView.RebuildShopContent()
    if shopModal_ == nil then return end

    local state = GetState()
    SaveShopScrollState(state.activeTab)

    local content
    if state.activeTab == "seed" then
        content = BuildSeedShopContent()
    else
        content = BuildToolShopContent()
    end

    shopModal_:ClearContent()
    shopModal_:AddContent(UI.Tabs {
        height = 44,
        variant = "pills",
        fontSize = 13,
        tabs = {
            { id = "seed", label = "种子商店" },
            { id = "tool", label = "工具商店" },
        },
        activeTab = state.activeTab,
        onChange = function(self, tabId)
            if tostring(tabId) == "tool" then
                FloatingToast.Show("工具商店暂未开放", { fontSize = 19, duration = 1.4, yRatio = 0.42, priority = 8 })
                pendingTabSwitch_ = "seed"
                return
            end
            pendingTabSwitch_ = tostring(tabId)
        end,
    })
    shopModal_:AddContent(content)
end

function ShopView.RefreshAfterServerSync()
    local state = GetState()
    if state.isOpen and shopModal_ ~= nil and state.activeTab == "seed" then
        ShopView.RebuildShopContent()
    end
end

function ShopView.Open()
    if shopModal_ ~= nil then return end

    local display = GetDisplay()
    system_.SetOpen(true)
    system_.SetActiveTab("seed")
    shopScrollState_.seed.x = 0
    shopScrollState_.seed.y = 0
    shopScrollState_.tool.x = 0
    shopScrollState_.tool.y = 0

    local screenH = graphics:GetHeight() / graphics:GetDPR()
    local modalFixedHeight = math.max(display.SHOP_BODY_MIN_HEIGHT + display.SHOP_MODAL_CHROME_HEIGHT, math.floor(screenH * 0.88))
    shopContentMinHeight_ = modalFixedHeight - display.SHOP_MODAL_CHROME_HEIGHT

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
            system_.SetOpen(false)
            shopModal_ = nil
        end,
    }

    ShopView.RebuildShopContent()
    ModalAnim.Apply(shopModal_, { fixedHeight = modalFixedHeight })
    shopModal_:Open()

    local state = GetState()
    if state.serverAuthoritative then
        if system_.RequestSeedShopFromServer() ~= true then
            ShopView.RebuildShopContent()
        end
    end

    print("[Shop] 商店已打开")
end

function ShopView.Close()
    if shopModal_ ~= nil then
        shopModal_:Close()
        shopModal_ = nil
    end
    system_.SetOpen(false)
end

function ShopView.HandlePendingTabSwitch()
    if pendingTabSwitch_ == nil then return false end
    system_.SetActiveTab(pendingTabSwitch_)
    pendingTabSwitch_ = nil
    staggerTimer_ = 0
    staggerDone_ = false
    ShopView.RebuildShopContent()
    return true
end

function ShopView.UpdatePresentation(dt, refreshFlags)
    refreshFlags = refreshFlags or {}
    local state = GetState()

    if state.isOpen and shopModal_ ~= nil then
        if (state.activeTab == "seed" and refreshFlags.seedRefreshed) or (state.activeTab == "tool" and refreshFlags.toolRefreshed) then
            staggerTimer_ = 0
            staggerDone_ = false
            ShopView.RebuildShopContent()
        end
    end

    ShopView.HandlePendingTabSwitch()

    if state.isOpen and shopModal_ ~= nil then
        if state.activeTab == "seed" and seedTimerLabel_ ~= nil then
            local ts = math.max(0, math.floor(state.seed.timer))
            seedTimerLabel_:SetText(string.format("全服刷新倒计时 %d:%02d", math.floor(ts / 60), ts % 60))
        elseif state.activeTab == "tool" and toolTimerLabel_ ~= nil then
            toolTimerLabel_:SetText("下次刷新: " .. system_.FormatTimer(state.tool.timer))
        end
    end
end

function ShopView.CreateEntryButton(opts)
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
            ShopView.Open()
        end,
    }
end

return ShopView
