-- ============================================================================
-- 限时活动 UI 视图 (Activity View)
-- Grow A Garden
-- ============================================================================
-- 顶部页签切换活动；甜蜜蜜弹窗按原型图重构为简洁活动落地页。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")

local ActivityView = {}

local deps_ = {}
local modal_ = nil
local submitModal_ = nil
local previewActivityId_ = nil

local COLORS = {
    text = {74, 53, 36, 255},
    subText = {122, 91, 62, 235},
    softText = {154, 124, 88, 220},
    paper = {255, 247, 226, 250},
    cream = {255, 252, 240, 255},
    line = {232, 204, 162, 220},
    orange = {224, 126, 72, 255},
    orangeDark = {150, 80, 48, 255},
    orangeSoft = {255, 229, 204, 255},
    pinkSoft = {255, 226, 238, 255},
    green = {91, 156, 102, 255},
    disabled = {218, 210, 196, 255},
    shadow = {106, 72, 32, 32},
}

local ACTIVITY_THEMES = {
    sweet = {
        accent = {224, 126, 72, 255},
        accentDark = {150, 80, 48, 255},
        accentSoft = {255, 229, 204, 255},
        panel = {255, 244, 228, 248},
        tab = {255, 236, 214, 255},
    },
    alien = {
        accent = {86, 174, 128, 255},
        accentDark = {54, 112, 84, 255},
        accentSoft = {220, 247, 230, 255},
        panel = {232, 248, 238, 248},
        tab = {226, 255, 228, 255},
    },
    dark = {
        accent = {126, 98, 164, 255},
        accentDark = {76, 56, 104, 255},
        accentSoft = {236, 226, 246, 255},
        panel = {232, 224, 240, 248},
        tab = {232, 224, 246, 255},
    },
}

local function GetTheme(activityId)
    return ACTIVITY_THEMES[activityId] or ACTIVITY_THEMES.sweet
end

local function CardShadow(offset)
    return {
        { x = offset or 3, y = offset or 3, blur = 0, spread = 0, color = COLORS.shadow },
    }
end

local REWARD_CARD_WIDTH = 166
local REWARD_CARD_HEIGHT = 214
local REWARD_CARD_GAP = 14

local function GetFallbackSeedIndex(index)
    if index == nil then return nil end
    return ((index - 1) % 29) + 1
end

local function GetSeedIconPath(index)
    return string.format("image/icons_3d/seed (%d).png", GetFallbackSeedIndex(index) or 1)
end

local function GetRewardIconPath(reward)
    if reward.type == "pack" then
        local packConfig = deps_.seedPackConfig and deps_.seedPackConfig[reward.packId]
        return (packConfig and packConfig.packIcon) or "image/seedpack_icon/seedpack_2.png"
    end
    if reward.type == "seed" or reward.plantIndex ~= nil then
        return GetSeedIconPath(reward.plantIndex)
    end
    return "image/seedpack_icon/seedpack_0.png"
end

local function GetPlantName(index)
    local plant = deps_.plants and deps_.plants[index]
    return (plant and plant.name) or "限定种子"
end

local function BuildDivider()
    return UI.Panel {
        width = "100%",
        height = 1,
        backgroundColor = COLORS.line,
    }
end

local function ShowActivityFloatingToast(text)
    FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.36, priority = 8 })
end

local function FormatPercent(value)
    return string.format("%d%%", math.floor((value or 0) * 100 + 0.5))
end

local function GetActiveActivity()
    if deps_.getActiveActivity == nil then return nil, nil, nil end
    return deps_.getActiveActivity()
end

local function GetActivityIds()
    local config = deps_.activityConfig or {}
    return config.sequence or { "sweet", "alien", "dark" }
end

local function GetActivityConfig(activityId)
    if deps_.getActivityConfig ~= nil then
        return deps_.getActivityConfig(activityId)
    end
    local config = deps_.activityConfig or {}
    return (config.activities or {})[activityId]
end

local function GetActivityState(activityId)
    if deps_.getActivityState ~= nil then
        return deps_.getActivityState(activityId) or {}
    end
    local activeId, _, state = GetActiveActivity()
    if activeId == activityId then return state or {} end
    return {}
end

local BuildMainContent

local function ResolveSelectedActivity()
    local activeId, activeActivity, activeState = GetActiveActivity()
    if previewActivityId_ == nil then previewActivityId_ = activeId end

    local selectedId = previewActivityId_ or activeId
    local activity = GetActivityConfig(selectedId)
    local state = GetActivityState(selectedId)
    if activity == nil then
        selectedId = activeId
        activity = activeActivity
        state = activeState or {}
    end
    return selectedId, activity, state or {}, selectedId == activeId, activeId
end

local function Reopen()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
    ActivityView.Open()
end

local function RefreshMainModalContent()
    if modal_ == nil then return end
    local activityId, activity, state, isActive, activeId = ResolveSelectedActivity()
    if activity == nil then return end
    local logicalHeight = graphics:GetHeight() / graphics:GetDPR()
    local fixedHeight = math.min(980, math.floor(logicalHeight * 0.99))
    local contentHeight = math.max(850, fixedHeight - 28)
    modal_:ClearContent()
    modal_:AddContent(BuildMainContent(activityId, activity, state, isActive, activeId, contentHeight))
end

local function RefreshSubmitModalContent()
    if submitModal_ == nil then return end
    submitModal_:Close()
    submitModal_ = nil
    ActivityView.OpenSubmitPicker()
end

local function EnableHorizontalDrag(scrollView)
    scrollView.OnPanStart = function(self, event)
        if not self.props.scrollX then return false end
        if self.CancelSnap_ then self:CancelSnap_() end
        if UI.CancelPointer then
            UI.CancelPointer(event.pointerId or 0, event.pointerType)
        end
        self.state.isDragging = true
        self.dragStartScrollX_ = self.state.scrollX
        self.dragStartScrollY_ = self.state.scrollY
        self.state.velocityX = 0
        self.state.velocityY = 0
        return true
    end
    return scrollView
end

local function BuildTabBar(selectedId, activeId)
    local tabs = {}
    for _, activityId in ipairs(GetActivityIds()) do
        local activity = GetActivityConfig(activityId)
        if activity ~= nil then
            local theme = GetTheme(activityId)
            local selected = activityId == selectedId
            local active = activityId == activeId
            table.insert(tabs, UI.Panel {
                width = 150,
                height = selected and 48 or 42,
                marginTop = selected and 0 or 6,
                borderRadius = 20,
                borderWidth = selected and 2 or 1,
                borderColor = selected and theme.accent or {232, 207, 172, 190},
                backgroundColor = selected and theme.tab or {255, 255, 255, 150},
                boxShadow = selected and CardShadow(2) or nil,
                justifyContent = "center",
                alignItems = "center",
                onTap = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    previewActivityId_ = activityId
                    Reopen()
                end,
                children = {
                    UI.Label {
                        text = active and (activity.name .. " 进行中") or activity.name,
                        fontSize = selected and 15 or 13,
                        fontWeight = "bold",
                        fontColor = selected and theme.accentDark or COLORS.subText,
                        textAlign = "center",
                        maxLines = 1,
                    },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%",
        height = 56,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "flex-start",
        gap = 10,
        children = tabs,
    }
end

local function BuildSweetHero(activity, state, isActive)
    return UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 9,
        paddingTop = 4,
        children = {
            UI.Label {
                text = "甜蜜蜜",
                fontSize = 34,
                fontWeight = "bold",
                fontColor = COLORS.orangeDark,
                textAlign = "center",
            },
            UI.Label {
                text = "收集糖果/蜂蜜变异作物，兑换限定甜蜜种子",
                fontSize = 15,
                fontWeight = "bold",
                fontColor = COLORS.subText,
                textAlign = "center",
            },
            UI.Panel {
                paddingTop = 4,
                paddingBottom = 4,
                paddingLeft = 12,
                paddingRight = 12,
                borderRadius = 14,
                backgroundColor = {255, 255, 255, 95},
                alignItems = "center",
                children = {
                    UI.Label {
                        text = isActive and (deps_.getTimeLeftText and deps_.getTimeLeftText() or "活动进行中") or "预览中",
                        fontSize = 12,
                        fontWeight = "normal",
                        fontColor = COLORS.softText,
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                gap = 12,
                marginTop = 4,
                children = {
                    UI.Label { text = "当前甜蜜值 " .. tostring(state.value or 0), fontSize = 14, fontWeight = "bold", fontColor = COLORS.text },
                    UI.Label { text = "累计上交 " .. tostring(state.submitted or 0), fontSize = 14, fontWeight = "bold", fontColor = COLORS.text },
                },
            },
        },
    }
end

local function BuildActivityHero(title, subtitle, statItems, theme, isActive)
    local stats = {}
    for _, item in ipairs(statItems or {}) do
        table.insert(stats, UI.Label {
            text = item,
            fontSize = 14,
            fontWeight = "bold",
            fontColor = COLORS.text,
            maxLines = 1,
        })
    end

    return UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 9,
        paddingTop = 4,
        children = {
            UI.Label {
                text = title,
                fontSize = 34,
                fontWeight = "bold",
                fontColor = theme.accentDark,
                textAlign = "center",
            },
            UI.Label {
                text = subtitle,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = COLORS.subText,
                textAlign = "center",
                maxLines = 2,
            },
            UI.Panel {
                paddingTop = 4,
                paddingBottom = 4,
                paddingLeft = 12,
                paddingRight = 12,
                borderRadius = 14,
                backgroundColor = {255, 255, 255, 95},
                alignItems = "center",
                children = {
                    UI.Label {
                        text = isActive and (deps_.getTimeLeftText and deps_.getTimeLeftText() or "活动进行中") or "预览中",
                        fontSize = 12,
                        fontWeight = "normal",
                        fontColor = COLORS.softText,
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                gap = 12,
                marginTop = 4,
                children = stats,
            },
        },
    }
end

local function BuildInfoCards(items, theme, highlightIndex)
    local cards = {}
    for index, item in ipairs(items) do
        table.insert(cards, UI.Panel {
            flexGrow = 1,
            flexBasis = 0,
            minHeight = 76,
            paddingTop = 10,
            paddingBottom = 10,
            paddingLeft = 12,
            paddingRight = 12,
            borderRadius = 18,
            backgroundColor = index == highlightIndex and theme.accentSoft or {255, 255, 255, 145},
            borderWidth = 1,
            borderColor = COLORS.line,
            alignItems = "center",
            gap = 4,
            children = {
                UI.Label { text = item.title, fontSize = 15, fontWeight = "bold", fontColor = theme.accentDark, textAlign = "center" },
                UI.Label { text = item.desc, fontSize = 11, fontColor = COLORS.subText, textAlign = "center", whiteSpace = "normal" },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 10,
        children = cards,
    }
end

local function BuildInstructionRow()
    local items = {
        { title = "播种作物", desc = "活动期间更容易出现糖果、蜂蜜变异" },
        { title = "上交变异", desc = "背包内符合条件的作物可兑换甜蜜值" },
        { title = "兑换奖励", desc = "甜蜜值用于领取限定作物种子" },
    }
    return BuildInfoCards(items, GetTheme("sweet"), 2)
end

local function BuildSubmitRow(canInteract)
    return UI.Panel {
        width = "100%",
        height = 64,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Button {
                text = "上交作物",
                width = 180,
                height = 46,
                fontSize = 16,
                fontWeight = "bold",
                borderRadius = 20,
                variant = "primary",
                disabled = not canInteract,
                backgroundColor = COLORS.orange,
                textColor = {255, 255, 255, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    ActivityView.OpenSubmitPicker()
                end,
            },
        },
    }
end

local function BuildRewardCard(reward, state, canInteract)
    local claimed = (state.exchanged and state.exchanged[reward.id] or 0)
    local limitReached = reward.limit ~= nil and claimed >= reward.limit
    local disabled = (not canInteract) or (state.value or 0) < reward.cost or limitReached
    local limitText = reward.limit and string.format("%d/%d", claimed, reward.limit) or "不限"
    local displayName = (reward.name or "奖励"):gsub("%s*x1$", "")

    return UI.Panel {
        width = REWARD_CARD_WIDTH,
        height = REWARD_CARD_HEIGHT,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        borderRadius = 22,
        backgroundColor = {255, 251, 238, 255},
        borderWidth = 2,
        borderColor = COLORS.line,
        boxShadow = CardShadow(3),
        alignItems = "center",
        gap = 7,
        children = {
            UI.Panel {
                width = 76,
                height = 76,
                borderRadius = 28,
                backgroundColor = COLORS.orangeSoft,
                backgroundImage = GetRewardIconPath(reward),
                backgroundFit = "contain",
                justifyContent = "center",
                alignItems = "center",
                children = {},
            },
            UI.Label { text = displayName, fontSize = 14, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center", maxLines = 2 },
            UI.Label { text = reward.cost .. " 甜蜜值 · " .. limitText, fontSize = 12, fontColor = COLORS.subText, textAlign = "center", maxLines = 1 },
            UI.Button {
                text = limitReached and "售罄" or "兑换",
                width = 112,
                height = 38,
                fontSize = 14,
                fontWeight = "bold",
                borderRadius = 16,
                disabled = disabled,
                backgroundColor = COLORS.orange,
                textColor = {255, 255, 255, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    local ok, err = deps_.exchangeSweetReward(reward.id)
                    if ok then
                        ShowActivityFloatingToast("兑换成功: " .. displayName)
                    elseif deps_.showToast then
                        deps_.showToast(err or "兑换失败")
                    end
                    RefreshMainModalContent()
                end,
            },
        },
    }
end

local function BuildRewardRow(activity, state, canInteract)
    local cards = {}
    for _, reward in ipairs(activity.exchangeRewards or {}) do
        table.insert(cards, BuildRewardCard(reward, state, canInteract))
    end

    local contentWidth = (#cards * REWARD_CARD_WIDTH) + (math.max(0, #cards - 1) * REWARD_CARD_GAP) + 24
    return EnableHorizontalDrag(UI.ScrollView {
        width = "100%",
        height = 232,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        scrollbarInteractive = true,
        bounces = true,
        children = {
            UI.Panel {
                width = contentWidth,
                minWidth = contentWidth,
                height = REWARD_CARD_HEIGHT + 12,
                flexShrink = 0,
                flexDirection = "row",
                gap = REWARD_CARD_GAP,
                paddingLeft = 6,
                paddingRight = 18,
                paddingTop = 4,
                children = cards,
            },
        },
    })
end

local function BuildDrawPoolCard(item, theme)
    return UI.Panel {
        width = 148,
        height = 178,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 22,
        backgroundColor = {255, 255, 255, 160},
        borderWidth = 2,
        borderColor = {190, 228, 202, 230},
        boxShadow = CardShadow(3),
        alignItems = "center",
        gap = 7,
        children = {
            UI.Panel {
                width = 72,
                height = 72,
                borderRadius = 28,
                backgroundColor = theme.accentSoft,
                backgroundImage = GetRewardIconPath(item),
                backgroundFit = "contain",
                children = {},
            },
            UI.Label { text = item.name or "基因奖励", fontSize = 13, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center", maxLines = 2 },
            UI.Label { text = "权重 " .. tostring(item.weight or 0), fontSize = 11, fontColor = COLORS.subText, textAlign = "center", maxLines = 1 },
        },
    }
end

local function BuildDrawPoolRow(activity, theme)
    local cards = {}
    for _, item in ipairs(activity.drawPool or {}) do
        table.insert(cards, BuildDrawPoolCard(item, theme))
    end
    local cardWidth = 148
    local gap = 12
    local contentWidth = (#cards * cardWidth) + (math.max(0, #cards - 1) * gap) + 24
    return EnableHorizontalDrag(UI.ScrollView {
        width = "100%",
        height = 194,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        scrollbarInteractive = true,
        bounces = true,
        children = {
            UI.Panel {
                width = contentWidth,
                minWidth = contentWidth,
                height = 186,
                flexShrink = 0,
                flexDirection = "row",
                gap = gap,
                paddingLeft = 6,
                paddingRight = 18,
                paddingTop = 4,
                children = cards,
            },
        },
    })
end

local function BuildLimitedSeedCard(seedIndex, theme)
    return UI.Panel {
        width = 148,
        height = 168,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 22,
        backgroundColor = {255, 255, 255, 150},
        borderWidth = 2,
        borderColor = theme.accent,
        boxShadow = CardShadow(3),
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                width = 72,
                height = 72,
                borderRadius = 28,
                backgroundColor = theme.accentSoft,
                backgroundImage = GetSeedIconPath(seedIndex),
                backgroundFit = "contain",
                children = {},
            },
            UI.Label { text = GetPlantName(seedIndex), fontSize = 13, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center", maxLines = 2 },
            UI.Label { text = "限定种子", fontSize = 11, fontColor = COLORS.subText, textAlign = "center" },
        },
    }
end

local function BuildLimitedSeedRow(activity, theme)
    local cards = {}
    for _, seedIndex in ipairs(activity.limitedSeeds or {}) do
        table.insert(cards, BuildLimitedSeedCard(seedIndex, theme))
    end
    local cardWidth = 148
    local gap = 12
    local contentWidth = (#cards * cardWidth) + (math.max(0, #cards - 1) * gap) + 24
    return EnableHorizontalDrag(UI.ScrollView {
        width = "100%",
        height = 184,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        scrollbarInteractive = true,
        bounces = true,
        children = {
            UI.Panel {
                width = contentWidth,
                minWidth = contentWidth,
                height = 176,
                flexShrink = 0,
                flexDirection = "row",
                gap = gap,
                paddingLeft = 6,
                paddingRight = 18,
                paddingTop = 4,
                children = cards,
            },
        },
    })
end

local function BuildSweetPrototype(activity, state, isActive)
    state.value = state.value or 0
    state.submitted = state.submitted or 0
    state.exchanged = state.exchanged or {}

    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        paddingTop = 12,
        paddingBottom = 14,
        paddingLeft = 18,
        paddingRight = 18,
        borderRadius = 28,
        backgroundColor = COLORS.paper,
        borderWidth = 2,
        borderColor = COLORS.line,
        gap = 14,
        children = {
            BuildSweetHero(activity, state, isActive),
            BuildDivider(),
            UI.Panel {
                width = "100%",
                alignItems = "center",
                gap = 6,
                children = {
                    BuildInstructionRow(),
                },
            },
            UI.Panel {
                width = "100%",
                alignItems = "center",
                gap = 8,
                children = {
                    BuildRewardRow(activity, state, isActive),
                },
            },
            BuildSubmitRow(isActive),
        },
    }
end

local function BuildAlienActions(activity, state, isActive)
    local canDrawOne = isActive and (state.genes or 0) >= (activity.drawCost or 10)
    local canDrawTen = isActive and (state.genes or 0) >= (activity.drawCostTen or 95)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 14,
        children = {
            UI.Button {
                text = "抽取一次",
                width = 150,
                height = 44,
                fontSize = 15,
                fontWeight = "bold",
                borderRadius = 20,
                variant = "primary",
                disabled = not canDrawOne,
                backgroundColor = GetTheme("alien").accent,
                textColor = {255, 255, 255, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    local ok, errOrRewards = deps_.drawAlienPack(1)
                    if ok then
                        ShowActivityFloatingToast("抽取成功")
                    elseif deps_.showToast then
                        deps_.showToast(errOrRewards or "抽取失败")
                    end
                    RefreshMainModalContent()
                end,
            },
            UI.Button {
                text = "抽取十次",
                width = 150,
                height = 44,
                fontSize = 15,
                fontWeight = "bold",
                borderRadius = 20,
                variant = "primary",
                disabled = not canDrawTen,
                backgroundColor = GetTheme("alien").accent,
                textColor = {255, 255, 255, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    local ok, errOrRewards = deps_.drawAlienPack(10)
                    if ok then
                        ShowActivityFloatingToast("抽取成功")
                    elseif deps_.showToast then
                        deps_.showToast(errOrRewards or "抽取失败")
                    end
                    RefreshMainModalContent()
                end,
            },
        },
    }
end

local function BuildAlienPrototype(activity, state, isActive)
    local theme = GetTheme("alien")
    state.genes = state.genes or 0
    state.totalGenes = state.totalGenes or 0
    state.drawCount = state.drawCount or 0
    local infoItems = {
        { title = "收获作物", desc = "收获时按稀有度获得外星基因" },
        { title = "基因抽取", desc = "消耗基因抽取异星种子包" },
        { title = "异星奖励", desc = "获得外星限定作物与种子包" },
    }

    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        paddingTop = 12,
        paddingBottom = 14,
        paddingLeft = 18,
        paddingRight = 18,
        borderRadius = 28,
        backgroundColor = theme.panel,
        borderWidth = 2,
        borderColor = theme.accent,
        gap = 13,
        children = {
            BuildActivityHero("外星基因", "收获作物积累外星基因，抽取异星限定奖励", {
                "可用基因 " .. tostring(state.genes),
                "累计基因 " .. tostring(state.totalGenes),
                "抽取次数 " .. tostring(state.drawCount),
            }, theme, isActive),
            BuildDivider(),
            BuildInfoCards(infoItems, theme, 2),
            BuildDrawPoolRow(activity, theme),
            BuildAlienActions(activity, state, isActive),
        },
    }
end

local function BuildDarkPrototype(activity, state, isActive)
    local theme = GetTheme("dark")
    state.devourHarvestCount = state.devourHarvestCount or 0
    state.darkSeedDrops = state.darkSeedDrops or 0
    local infoItems = {
        { title = "夜幕播种", desc = "活动期间作物可出现吞噬异变" },
        { title = "收获吞噬", desc = "收获吞噬作物有概率掉落种子" },
        { title = "暗影种子", desc = "收集月影、幽灯与星蚀限定作物" },
    }

    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        paddingTop = 12,
        paddingBottom = 14,
        paddingLeft = 18,
        paddingRight = 18,
        borderRadius = 28,
        backgroundColor = theme.panel,
        borderWidth = 2,
        borderColor = theme.accent,
        gap = 13,
        children = {
            BuildActivityHero("黑暗来临", "吞噬变异与虚空异变增强，收集暗影限定种子", {
                "吞噬收获 " .. tostring(state.devourHarvestCount),
                "种子掉落 " .. tostring(state.darkSeedDrops),
                "虚空加成 " .. FormatPercent(activity.extraVoidChance),
            }, theme, isActive),
            BuildDivider(),
            BuildInfoCards(infoItems, theme, 2),
            BuildLimitedSeedRow(activity, theme),
            UI.Panel {
                width = "100%",
                height = 56,
                borderRadius = 22,
                backgroundColor = {255, 255, 255, 130},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "活动期间自动生效，收获吞噬变异作物即可获得掉落机会", fontSize = 14, fontWeight = "bold", fontColor = theme.accentDark, textAlign = "center", maxLines = 2 },
                },
            },
        },
    }
end

BuildMainContent = function(activityId, activity, state, isActive, activeId, contentHeight)
    return UI.Panel {
        width = "100%",
        height = contentHeight,
        gap = 8,
        children = {
            BuildTabBar(activityId, activeId),
            activityId == "sweet" and BuildSweetPrototype(activity, state, isActive)
                or activityId == "alien" and BuildAlienPrototype(activity, state, isActive)
                or BuildDarkPrototype(activity, state, isActive),
        },
    }
end

function ActivityView.OpenSubmitPicker()
    if submitModal_ ~= nil then
        submitModal_:Close()
        submitModal_ = nil
    end

    local rows = {}
    local submitItems = deps_.getSweetSubmitItems and deps_.getSweetSubmitItems() or {}
    for _, entry in ipairs(submitItems) do
        local item = entry.item
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 62,
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            paddingLeft = 12,
            paddingRight = 12,
            borderRadius = 18,
            backgroundColor = {255, 251, 238, 255},
            borderWidth = 1,
            borderColor = COLORS.line,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label { text = item.name, fontSize = 15, fontWeight = "bold", fontColor = COLORS.text, maxLines = 1 },
                        UI.Label { text = "上交可获得甜蜜值 +" .. entry.value, fontSize = 12, fontColor = COLORS.subText, maxLines = 1 },
                    },
                },
                UI.Button {
                    text = "上交",
                    width = 78,
                    height = 36,
                    fontSize = 13,
                    fontWeight = "bold",
                    borderRadius = 16,
                    variant = "primary",
                    backgroundColor = COLORS.orange,
                    textColor = {255, 255, 255, 255},
                    onClick = function()
                        if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                        local ok, errOrValue = deps_.submitSweetCrop(item)
                        if ok then
                            ShowActivityFloatingToast("上交成功，甜蜜值 +" .. tostring(errOrValue or entry.value))
                        elseif deps_.showToast then
                            deps_.showToast(errOrValue or "上交失败")
                        end
                        RefreshMainModalContent()
                        RefreshSubmitModalContent()
                    end,
                },
            },
        })
    end

    if #rows == 0 then
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 120,
            justifyContent = "center",
            alignItems = "center",
            paddingLeft = 18,
            paddingRight = 18,
            children = {
                UI.Label {
                    text = "暂无可上交作物。获得糖果/蜂蜜变异作物后会显示在这里。",
                    fontSize = 14,
                    fontColor = COLORS.subText,
                    textAlign = "center",
                    whiteSpace = "normal",
                },
            },
        })
    end

    submitModal_ = UI.Modal {
        title = "选择上交作物",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 14, 14, 14},
        onClose = function() submitModal_ = nil end,
    }

    submitModal_:AddContent(UI.Panel {
        width = "100%",
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 24,
        backgroundColor = COLORS.paper,
        borderWidth = 1,
        borderColor = COLORS.line,
        children = {
            UI.ScrollView {
                width = "100%",
                height = 320,
                scrollY = true,
                showScrollbar = false,
                bounces = true,
                children = {
                    UI.Panel { width = "100%", gap = 8, children = rows },
                },
            },
        },
    })

    ModalAnim.Apply(submitModal_, { fixedHeight = 460, widthRatio = 0.86, maxHeightRatio = 0.92 })
    submitModal_:Open()
end

function ActivityView.Init(deps)
    deps_ = deps or {}
end

function ActivityView.IsOpen()
    return modal_ ~= nil
end

function ActivityView.Open()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end

    local activityId, activity, state, isActive, activeId = ResolveSelectedActivity()
    if activity == nil then return end

    local logicalHeight = graphics:GetHeight() / graphics:GetDPR()
    local fixedHeight = math.min(980, math.floor(logicalHeight * 0.99))
    local contentHeight = math.max(850, fixedHeight - 28)

    modal_ = UI.Modal {
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {8, 12, 12, 12},
        onClose = function() modal_ = nil end,
    }

    modal_:AddContent(BuildMainContent(activityId, activity, state, isActive, activeId, contentHeight))

    ModalAnim.Apply(modal_, { fixedHeight = fixedHeight, widthRatio = 0.96, maxWidthRatio = 0.98, maxHeightRatio = 0.99 })
    modal_:Open()
end

function ActivityView.BuildButton()
    return UI.Button {
        text = "活动",
        width = 69,
        height = 66,
        paddingTop = 0,
        paddingRight = 16,
        paddingBottom = 5,
        paddingLeft = 16,
        fontSize = 15,
        fontWeight = "bold",
        backgroundColor = {255, 244, 218, 245},
        fontColor = {190, 92, 72, 255},
        borderRadius = 14,
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            ActivityView.Open()
        end,
    }
end

return ActivityView
