-- ============================================================================
-- 限时活动 UI 视图 (Activity View)
-- Grow A Garden
-- ============================================================================
-- 顶部页签切换活动；甜蜜蜜弹窗按原型图重构为简洁活动落地页。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")
local LeaderboardView = require("ui.leaderboard_view")

local ActivityView = {}

local deps_ = {}
local modal_ = nil
local submitModal_ = nil
local alienResultModal_ = nil
local previewActivityId_ = nil
local alienDrawPending_ = false

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

local RARITY_TEXT_COLORS = {
    ["普通"] = {120, 114, 98, 255},
    ["罕见"] = {68, 162, 92, 255},
    ["稀有"] = {68, 118, 220, 255},
    ["史诗"] = {146, 88, 204, 255},
    ["传奇"] = {218, 132, 34, 255},
}

local function GetPlantRarityColor(index)
    local plant = deps_.plants and deps_.plants[index]
    return RARITY_TEXT_COLORS[plant and plant.rarity] or COLORS.text
end

local function GetRarityTextColor(rarity)
    return RARITY_TEXT_COLORS[rarity] or COLORS.text
end

local function GetRewardNameColor(reward)
    if reward.type == "seed" or reward.plantIndex ~= nil then
        return GetPlantRarityColor(reward.plantIndex)
    end
    return COLORS.text
end

local function GetPlantRarityOrder(index)
    local plant = deps_.plants and deps_.plants[index]
    local order = { ["普通"] = 1, ["罕见"] = 2, ["稀有"] = 3, ["史诗"] = 4, ["传奇"] = 5 }
    return order[plant and plant.rarity] or 99
end

local function GetRewardRarityOrder(reward)
    if reward.type == "seed" or reward.plantIndex ~= nil then
        return GetPlantRarityOrder(reward.plantIndex)
    end
    return 100
end

local function SortedCopy(items, compare)
    local result = {}
    for _, item in ipairs(items or {}) do
        table.insert(result, item)
    end
    table.sort(result, compare)
    return result
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

local function GetActivityModalLayout()
    local logicalHeight = graphics:GetHeight() / graphics:GetDPR()
    local fixedHeight = math.min(980, math.floor(logicalHeight * 0.96))
    local contentHeight = math.max(0, fixedHeight - 60)
    return fixedHeight, contentHeight
end

local function ResolveSelectedActivity()
    local activeId, activeActivity, activeState = GetActiveActivity()
    previewActivityId_ = activeId
    return activeId, activeActivity, activeState or {}, true, activeId
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
    local fixedHeight, contentHeight = GetActivityModalLayout()
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

local function BuildActivityRankButton(activityId)
    return LeaderboardView.BuildButton({
        text = "活动排行",
        width = 88,
        height = 34,
        fontSize = 12,
        tab = "activity",
        mode = "activity",
        backgroundColor = GetTheme(activityId).accent,
        fontColor = {255, 255, 255, 255},
        borderRadius = 16,
    })
end

local function BuildHeroTitleRow(title, activityId, theme)
    return UI.Panel {
        width = "100%",
        height = 42,
        flexDirection = "row",
        alignItems = "center",
        children = {
            UI.Panel { width = 88, height = 34, flexShrink = 0 },
            UI.Label {
                text = title,
                flexGrow = 1,
                flexShrink = 1,
                fontSize = 34,
                fontWeight = "bold",
                fontColor = theme.accentDark,
                textAlign = "center",
                maxLines = 1,
            },
            BuildActivityRankButton(activityId),
        },
    }
end

local function BuildSweetHero(activity, state, isActive)
    return UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 9,
        paddingTop = 4,
        children = {
            BuildHeroTitleRow("甜蜜蜜", "sweet", GetTheme("sweet")),
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

local function BuildActivityHero(title, subtitle, statItems, theme, isActive, activityId)
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
            BuildHeroTitleRow(title, activityId or "sweet", theme),
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
    local disabled = not canInteract or limitReached
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
            UI.Label { text = displayName, fontSize = 14, fontWeight = "bold", fontColor = GetRewardNameColor(reward), textAlign = "center", maxLines = 2 },
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
                        ShowActivityFloatingToast(err == nil and "兑换请求已发送" or ("兑换成功: " .. displayName))
                    else
                        ShowActivityFloatingToast(err or "兑换失败")
                    end
                end,
            },
        },
    }
end

local function BuildRewardRow(activity, state, canInteract)
    local cards = {}
    local rewards = SortedCopy(activity.exchangeRewards or {}, function(a, b)
        local rarityA = GetRewardRarityOrder(a)
        local rarityB = GetRewardRarityOrder(b)
        if rarityA ~= rarityB then return rarityA < rarityB end
        return (a.plantIndex or 9999) < (b.plantIndex or 9999)
    end)
    for _, reward in ipairs(rewards) do
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
            UI.Label { text = item.name or "基因奖励", fontSize = 13, fontWeight = "bold", fontColor = GetRewardNameColor(item), textAlign = "center", maxLines = 2 },
            UI.Label { text = "权重 " .. tostring(item.weight or 0), fontSize = 11, fontColor = COLORS.subText, textAlign = "center", maxLines = 1 },
        },
    }
end

local function BuildDrawPoolRow(activity, theme)
    local cards = {}
    local drawPool = SortedCopy(activity.drawPool or {}, function(a, b)
        local rarityA = GetRewardRarityOrder(a)
        local rarityB = GetRewardRarityOrder(b)
        if rarityA ~= rarityB then return rarityA < rarityB end
        return (a.plantIndex or 9999) < (b.plantIndex or 9999)
    end)
    for _, item in ipairs(drawPool) do
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
            UI.Label { text = GetPlantName(seedIndex), fontSize = 13, fontWeight = "bold", fontColor = GetPlantRarityColor(seedIndex), textAlign = "center", maxLines = 2 },
            UI.Label { text = "限定种子", fontSize = 11, fontColor = COLORS.subText, textAlign = "center" },
        },
    }
end

local function BuildLimitedSeedRow(activity, theme)
    local cards = {}
    local seedIndices = SortedCopy(activity.limitedSeeds or {}, function(a, b)
        local rarityA = GetPlantRarityOrder(a)
        local rarityB = GetPlantRarityOrder(b)
        if rarityA ~= rarityB then return rarityA < rarityB end
        return a < b
    end)
    for _, seedIndex in ipairs(seedIndices) do
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

local function BuildAlienResultCards(rewards)
    local cards = {}
    local counts = {}
    local lookup = {}
    for _, reward in ipairs(rewards or {}) do
        local key = reward.type .. ":" .. tostring(reward.packId or reward.plantIndex or reward.name)
        counts[key] = (counts[key] or 0) + (reward.count or 1)
        lookup[key] = reward
    end
    local keys = {}
    for key in pairs(counts) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        local ra = lookup[a]
        local rb = lookup[b]
        local oa = ra.type == "seed" and GetPlantRarityOrder(ra.plantIndex) or 100
        local ob = rb.type == "seed" and GetPlantRarityOrder(rb.plantIndex) or 100
        if oa ~= ob then return oa < ob end
        return a < b
    end)

    for _, key in ipairs(keys) do
        local reward = lookup[key]
        local count = counts[key]
        local isSeed = reward.type == "seed"
        local packCfg = (not isSeed) and deps_.seedPackConfig and deps_.seedPackConfig[reward.packId] or nil
        local name = tostring(reward.name or (isSeed and GetPlantName(reward.plantIndex) or (packCfg and packCfg.packName) or "种子包"))
        local rarity = isSeed and ((deps_.plants and deps_.plants[reward.plantIndex] and deps_.plants[reward.plantIndex].rarity) or "限定") or ((packCfg and packCfg.packRarity) or "种子包")
        local nameColor = isSeed and GetPlantRarityColor(reward.plantIndex) or GetRarityTextColor(rarity)
        local iconPath = isSeed and GetSeedIconPath(reward.plantIndex) or GetRewardIconPath(reward)
        table.insert(cards, UI.Panel {
            width = "46%",
            minHeight = 150,
            padding = 6,
            marginBottom = 10,
            alignItems = "center",
            backgroundColor = {0, 0, 0, 0},
            children = {
                UI.Panel {
                    width = 96,
                    height = 88,
                    marginBottom = 6,
                    backgroundImage = iconPath,
                    backgroundFit = "contain",
                },
                UI.Label { text = name, width = 150, fontSize = 14, fontWeight = "bold", fontColor = nameColor, textAlign = "center", maxLines = 2 },
                UI.Label { text = "x" .. tostring(count), width = 150, fontSize = 13, fontWeight = "bold", fontColor = COLORS.subText, textAlign = "center", marginTop = 4 },
            },
        })
    end
    return cards
end

function ActivityView.CancelAlienDrawPending()
    alienDrawPending_ = false
    RefreshMainModalContent()
end

function ActivityView.ShowAlienDrawResult(rewards)
    alienDrawPending_ = false
    if rewards == nil or #rewards == 0 then return end
    if alienResultModal_ ~= nil then
        alienResultModal_:Close()
        alienResultModal_ = nil
    end

    alienResultModal_ = UI.Modal {
        size = "fullscreen",
        closeOnOverlay = false,
        showCloseButton = false,
        contentPadding = {8, 14, 8, 14},
        onClose = function()
            alienResultModal_ = nil
            RefreshMainModalContent()
        end,
    }

    alienResultModal_:AddContent(UI.Panel {
        height = 560,
        paddingTop = 20,
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "基因抽取结算",
                width = "100%",
                fontSize = 19,
                fontWeight = "bold",
                fontColor = {75, 55, 40, 255},
                textAlign = "center",
                marginBottom = 18,
            },
            UI.ScrollView {
                height = 410,
                scrollY = true,
                showScrollbar = true,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "flex-start",
                        gap = 2,
                        paddingTop = 2,
                        paddingBottom = 4,
                        children = BuildAlienResultCards(rewards),
                    },
                },
            },
            UI.Panel {
                height = 58,
                justifyContent = "center",
                alignItems = "center",
                marginTop = 4,
                children = {
                    UI.Button {
                        text = "确认",
                        width = 120,
                        height = 42,
                        fontSize = 16,
                        fontWeight = "bold",
                        backgroundColor = {95, 165, 105, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 12,
                        onClick = function()
                            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                            if alienResultModal_ ~= nil then
                                alienResultModal_:Close()
                            end
                        end,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(alienResultModal_, { fixedHeight = 610 })
    alienResultModal_:Open()
    alienResultModal_.animProgress_ = 1
    alienResultModal_.targetAnimProgress_ = 1
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
    local theme = GetTheme("alien")
    local function BuildDrawButton(text, cost, count)
        return UI.Panel {
            alignItems = "center",
            gap = 5,
            children = {
                UI.Button {
                    text = text,
                    width = 150,
                    height = 44,
                    fontSize = 15,
                    fontWeight = "bold",
                    borderRadius = 20,
                    variant = "primary",
                    disabled = not isActive or alienDrawPending_,
                    backgroundColor = theme.accent,
                    textColor = {255, 255, 255, 255},
                    onClick = function()
                        if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                        if alienDrawPending_ then
                            ShowActivityFloatingToast("抽取请求处理中")
                            return
                        end
                        if (state.genes or 0) < cost then
                            ShowActivityFloatingToast("外星基因不足")
                            return
                        end
                        alienDrawPending_ = true
                        local ok, errOrRewards = deps_.drawAlienPack(count)
                        if ok then
                            if errOrRewards ~= nil and #errOrRewards > 0 then
                                alienDrawPending_ = false
                                ShowActivityFloatingToast("抽取成功")
                                ActivityView.ShowAlienDrawResult(errOrRewards)
                            else
                                ShowActivityFloatingToast("抽取请求已发送")
                            end
                        else
                            alienDrawPending_ = false
                            ShowActivityFloatingToast(errOrRewards or "抽取失败")
                        end
                    end,
                },
                UI.Label {
                    text = "消耗 " .. tostring(cost) .. " 基因",
                    fontSize = 12,
                    fontWeight = "bold",
                    fontColor = theme.accentDark,
                    textAlign = "center",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 14,
        children = {
            BuildDrawButton("抽取一次", activity.drawCost or 10, 1),
            BuildDrawButton("抽取十次", activity.drawCostTen or 95, 10),
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
            }, theme, isActive, "alien"),
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
            }, theme, isActive, "dark"),
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
                    UI.Label { text = "活动期间自动生效，收获吞噬或虚空变异作物即可获得掉落机会", fontSize = 14, fontWeight = "bold", fontColor = theme.accentDark, textAlign = "center", maxLines = 2 },
                },
            },
        },
    }
end

BuildMainContent = function(activityId, activity, state, isActive, activeId, contentHeight)
    return UI.Panel {
        width = "100%",
        height = contentHeight,
        paddingTop = 34,
        paddingLeft = 4,
        paddingRight = 4,
        paddingBottom = 4,
        gap = 8,
        children = {
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
                            if errOrValue ~= nil then
                                ShowActivityFloatingToast("上交成功，甜蜜值 +" .. tostring(errOrValue or entry.value))
                            else
                                ShowActivityFloatingToast("上交请求已发送")
                            end
                        elseif deps_.showToast then
                            deps_.showToast(errOrValue or "上交失败")
                        end
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
    return modal_ ~= nil or submitModal_ ~= nil or alienResultModal_ ~= nil
end

function ActivityView.Close()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
    if submitModal_ ~= nil then
        submitModal_:Close()
        submitModal_ = nil
    end
    if alienResultModal_ ~= nil then
        alienResultModal_:Close()
        alienResultModal_ = nil
    end
end

function ActivityView.RefreshContent()
    RefreshMainModalContent()
    RefreshSubmitModalContent()
end

function ActivityView.Open()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end

    local activityId, activity, state, isActive, activeId = ResolveSelectedActivity()
    if activity == nil then return end

    local fixedHeight, contentHeight = GetActivityModalLayout()

    modal_ = UI.Modal {
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {4, 8, 8, 8},
        onClose = function() modal_ = nil end,
    }

    modal_:AddContent(BuildMainContent(activityId, activity, state, isActive, activeId, contentHeight))

    ModalAnim.Apply(modal_, { fixedHeight = fixedHeight, widthRatio = 0.96, maxWidthRatio = 0.98, maxHeightRatio = 0.99 })
    modal_:Open()
end

local function GetActivityButtonText()
    local _, activity = GetActiveActivity()
    return (activity and activity.name) or "活动"
end

local function GetActivityButtonTheme()
    local activityId = nil
    activityId = GetActiveActivity()
    local theme = GetTheme(activityId)
    return {
        backgroundColor = theme.accent,
        titleColor = {255, 255, 255, 255},
        subtitleColor = {255, 255, 255, 230},
        tagBackgroundColor = theme.accentDark,
        tagTextColor = {255, 255, 255, 255},
        borderColor = theme.accentDark,
    }
end

local function GetActivityTimeLeftText()
    local activityConfig = deps_.activityConfig or {}
    local cycleDays = activityConfig.cycleDays or 3
    local duration = cycleDays * 24 * 60 * 60
    local now = os and os.time and os.time() or 0
    local left = duration - (now % duration)
    local hours = math.floor(left / 3600)
    local minutes = math.floor((left % 3600) / 60)
    if hours <= 0 and minutes <= 0 then
        minutes = 1
    end
    return string.format("%d小时%d分钟", hours, minutes)
end

function ActivityView.GetButtonText()
    return GetActivityButtonText()
end

function ActivityView.BuildButton(options)
    options = options or {}
    local width = options.width or 69
    local height = options.height or 66
    local theme = GetActivityButtonTheme()
    return UI.Panel {
        width = width,
        height = height,
        paddingTop = 7,
        paddingBottom = 7,
        paddingLeft = 16,
        paddingRight = 16,
        borderRadius = options.borderRadius or 16,
        borderWidth = options.borderWidth or 2,
        borderColor = options.borderColor or theme.borderColor,
        backgroundColor = options.backgroundColor or theme.backgroundColor,
        overflow = "visible",
        justifyContent = "center",
        alignItems = "center",
        onTapStart = function(event, widget)
            widget:SetStyle({ scale = 0.97 })
        end,
        onTapEnd = function(event, widget)
            widget:SetStyle({ scale = 1.0 })
        end,
        onTap = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            ActivityView.Open()
        end,
        children = {
            UI.Label {
                text = options.text or GetActivityButtonText(),
                fontSize = options.fontSize or 19,
                fontWeight = "bold",
                fontColor = options.titleColor or theme.titleColor,
                textAlign = "center",
                maxLines = 1,
            },
            UI.Label {
                text = "活动进行中",
                fontSize = 11,
                fontWeight = "bold",
                fontColor = options.subtitleColor or theme.subtitleColor,
                textAlign = "center",
                maxLines = 1,
                marginTop = 1,
            },
            UI.Panel {
                position = "absolute",
                right = -5,
                bottom = -8,
                paddingTop = 3,
                paddingBottom = 3,
                paddingLeft = 8,
                paddingRight = 8,
                borderRadius = 10,
                borderWidth = 2,
                borderColor = {255, 255, 255, 255},
                backgroundColor = options.tagBackgroundColor or theme.tagBackgroundColor,
                children = {
                    UI.Label {
                        text = GetActivityTimeLeftText(),
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = options.tagTextColor or theme.tagTextColor,
                        maxLines = 1,
                    },
                },
            },
        },
    }
end

return ActivityView
