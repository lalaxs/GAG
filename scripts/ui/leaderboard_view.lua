-- ============================================================================
-- 排行榜 UI
-- ============================================================================
-- 主页入口：收入 / 观光 / 点赞。
-- 活动入口：只显示当前活动榜，不能切换到其他排行榜。
-- 风格保持主 UI 的动森纸张、圆角、柔和边框和简洁按钮。
-- ============================================================================

local UI = require("urhox-libs/UI")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local ModalAnim = require("ui.modal_anim")

local LeaderboardView = {}

local deps_ = {}
local modal_ = nil
local unsubscribeLeaderboardChanged_ = nil
local activeTab_ = "income"
local sourceMode_ = "home"

local COLORS = {
    cream = {255, 250, 240, 250},
    raised = {255, 252, 242, 255},
    empty = {248, 243, 232, 235},
    text = {74, 55, 38, 255},
    muted = {120, 96, 68, 225},
    border = {224, 196, 150, 170},
    borderStrong = {204, 156, 88, 225},
    green = {78, 172, 110, 255},
    greenDeep = {50, 130, 82, 255},
    greenSoft = {226, 245, 226, 255},
    orange = {224, 126, 72, 255},
    orangeDark = {150, 80, 48, 255},
    orangeSoft = {255, 229, 204, 255},
    pink = {224, 105, 105, 255},
    pinkSoft = {255, 226, 226, 255},
    disabled = {178, 166, 148, 200},
}

local ACTIVITY_COLORS = {
    sweet = { accent = COLORS.orange, soft = COLORS.orangeSoft, title = "甜蜜蜜" },
    alien = { accent = COLORS.green, soft = COLORS.greenSoft, title = "外星基因" },
    dark = { accent = {126, 98, 164, 255}, soft = {236, 226, 246, 255}, title = "黑暗来临" },
}

local HOME_TABS = {
    { id = "income", text = "收入" },
    { id = "tour", text = "观光" },
    { id = "like", text = "点赞" },
}

local function Suppress()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
end

local function GetSystem()
    return deps_.LeaderboardSystem
end

local function GetActiveActivityId()
    if deps_.getActiveActivityId then return deps_.getActiveActivityId() end
    return "sweet"
end

local function GetActivityTheme(activityId)
    return ACTIVITY_COLORS[activityId or "sweet"] or ACTIVITY_COLORS.sweet
end

local function GetAllowedTabs()
    if sourceMode_ == "activity" then
        local theme = GetActivityTheme(GetActiveActivityId())
        return {
            { id = "activity", text = theme.title },
        }
    end
    return HOME_TABS
end

local function IsTabAllowed(tab)
    for _, item in ipairs(GetAllowedTabs()) do
        if item.id == tab then return true end
    end
    return false
end

local function NormalizeActiveTab(tab)
    if sourceMode_ == "activity" then return "activity" end
    if tab == "activity" or not IsTabAllowed(tab) then return "income" end
    return tab or "income"
end

local function GetCurrentList()
    local system = GetSystem()
    if system == nil then return {} end
    if activeTab_ == "activity" then
        return system.GetList("activity", GetActiveActivityId())
    end
    return system.GetList(activeTab_)
end

local function IsCurrentLoading()
    local system = GetSystem()
    if system == nil then return false end
    if activeTab_ == "activity" then
        return system.IsLoading("activity", GetActiveActivityId())
    end
    return system.IsLoading(activeTab_)
end

local function RefreshCurrent()
    local system = GetSystem()
    if system == nil then return false end
    if activeTab_ == "activity" then
        return system.Request("activity", GetActiveActivityId())
    end
    return system.Request(activeTab_)
end

local function FormatScore(value)
    value = math.max(0, math.floor(tonumber(value or 0) or 0))
    if value >= 100000000 then return string.format("%.1f亿", value / 100000000) end
    if value >= 10000 then return string.format("%.1f万", value / 10000) end
    return tostring(value)
end

local function GetScoreLabel()
    if activeTab_ == "income" then return "收入" end
    if activeTab_ == "tour" then return "观光值" end
    if activeTab_ == "like" then return "点赞" end
    return "活动分"
end

local function GetHintText()
    if activeTab_ == "income" then return "每 7 天重置该榜" end
    if activeTab_ == "tour" then return "永久榜，统计当前观光值" end
    if activeTab_ == "like" then return "永久榜，统计花园累计点赞" end
    return "本期活动榜，底部可领取上期排行奖励"
end

local function GetAccentColor()
    if activeTab_ == "income" then return COLORS.orange end
    if activeTab_ == "tour" then return COLORS.green end
    if activeTab_ == "like" then return COLORS.pink end
    return GetActivityTheme(GetActiveActivityId()).accent
end

local function GetAccentSoftColor()
    if activeTab_ == "income" then return COLORS.orangeSoft end
    if activeTab_ == "tour" then return COLORS.greenSoft end
    if activeTab_ == "like" then return COLORS.pinkSoft end
    return GetActivityTheme(GetActiveActivityId()).soft
end

local RebuildContent

local function BuildTabButton(tab)
    local selected = activeTab_ == tab.id
    return UI.Button {
        text = tab.text,
        flexGrow = 1,
        flexBasis = 0,
        height = 44,
        fontSize = 16,
        fontWeight = "bold",
        backgroundColor = selected and COLORS.orange or {255, 250, 240, 245},
        hoverBackgroundColor = selected and COLORS.orange or {255, 252, 242, 255},
        pressedBackgroundColor = selected and COLORS.orangeDark or {245, 238, 220, 255},
        textColor = selected and {255, 255, 255, 255} or COLORS.greenDeep,
        fontColor = selected and {255, 255, 255, 255} or COLORS.greenDeep,
        borderWidth = selected and 0 or 2,
        borderColor = COLORS.border,
        borderRadius = 12,
        onClick = function()
            Suppress()
            activeTab_ = tab.id
            RefreshCurrent()
            RebuildContent()
        end,
    }
end

local function BuildTabBar()
    local children = {}
    for _, tab in ipairs(GetAllowedTabs()) do
        children[#children + 1] = BuildTabButton(tab)
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 10,
        children = children,
    }
end

local function GetAvatarImagePath(avatar)
    if type(avatar) ~= "table" then return nil end
    if avatar.image ~= nil and avatar.image ~= "" then return avatar.image end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    if plantIndex ~= nil then
        return string.format("image/plants/plants (%d).png", math.floor(plantIndex))
    end
    return nil
end

local function ResolveAvatar(entry)
    if entry ~= nil and entry.isMe == true and deps_.getMyAvatar ~= nil then
        return deps_.getMyAvatar() or entry.avatar
    end
    return entry and entry.avatar or nil
end

local function BuildAvatar(entry, size)
    size = size or 72
    local avatar = ResolveAvatar(entry)
    local avatarImage = GetAvatarImagePath(avatar)
    local bgColor = type(avatar) == "table" and avatar.color or COLORS.greenSoft
    local children = {}
    if avatarImage ~= nil and avatarImage ~= "" then
        children[#children + 1] = UI.Panel {
            width = math.floor(size * 0.76),
            height = math.floor(size * 0.76),
            backgroundImage = avatarImage,
            backgroundFit = "contain",
        }
    else
        children[#children + 1] = UI.Label {
            text = "头像",
            fontSize = math.max(12, math.floor(size * 0.18)),
            fontColor = COLORS.text,
            textAlign = "center",
            maxLines = 1,
        }
    end
    return UI.Panel {
        width = size,
        height = size,
        borderRadius = 999,
        borderWidth = 3,
        borderColor = {255, 252, 235, 255},
        backgroundColor = bgColor,
        alignItems = "center",
        justifyContent = "center",
        flexShrink = 0,
        boxShadow = { { x = 0, y = 2, blur = 0, spread = 0, color = {106, 72, 32, 45} } },
        children = children,
    }
end

local function VisitPlayer(userId)
    if userId == nil then return false end
    local ok = false
    if deps_.visitPlayer ~= nil then
        ok = deps_.visitPlayer(userId) == true
    elseif deps_.SocialGardenSystem ~= nil and deps_.SocialGardenSystem.VisitPlayer ~= nil then
        ok = deps_.SocialGardenSystem.VisitPlayer(userId) == true
    end
    if ok then LeaderboardView.Close() end
    return ok
end

local function BuildVisitButton(entry)
    if entry == nil or entry.userId == nil or entry.isMe == true then
        return UI.Panel { width = 72, height = 40 }
    end
    return UI.Button {
        text = "拜访",
        width = 72,
        height = 40,
        fontSize = 14,
        fontWeight = "bold",
        backgroundColor = COLORS.green,
        hoverBackgroundColor = {94, 194, 131, 255},
        pressedBackgroundColor = COLORS.greenDeep,
        textColor = {255, 255, 255, 255},
        fontColor = {255, 255, 255, 255},
        borderRadius = 14,
        onClick = function()
            Suppress()
            VisitPlayer(entry.userId)
        end,
    }
end

local function BuildRankLabel(rank)
    return UI.Label {
        text = tostring(rank or "-"),
        width = 42,
        fontSize = 20,
        fontWeight = "bold",
        fontColor = COLORS.text,
        textAlign = "center",
        maxLines = 1,
        flexShrink = 0,
    }
end

local function BuildLeaderboardRow(entry)
    local accent = GetAccentColor()
    return UI.Panel {
        width = "100%",
        height = 88,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingLeft = 14,
        paddingRight = 12,
        backgroundColor = entry.isMe and {255, 248, 222, 255} or {255, 252, 242, 248},
        borderRadius = 18,
        borderWidth = entry.isMe and 3 or 2,
        borderColor = entry.isMe and COLORS.borderStrong or COLORS.border,
        children = {
            BuildRankLabel(entry.rank),
            BuildAvatar(entry, 68),
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 5,
                children = {
                    UI.Label {
                        text = entry.isMe and ((entry.nickname or "你") .. "  我") or (entry.nickname or tostring(entry.userId or "Tap玩家")),
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = COLORS.text,
                        maxLines = 1,
                    },
                    UI.Label {
                        text = GetScoreLabel() .. " " .. FormatScore(entry.score),
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = accent,
                        maxLines = 1,
                    },
                },
            },
            BuildVisitButton(entry),
        },
    }
end

local function BuildEmptyPanel()
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 380,
        backgroundColor = COLORS.empty,
        borderRadius = 18,
        alignItems = "center",
        justifyContent = "center",
        children = {
            UI.Label {
                text = IsCurrentLoading() and "排行榜加载中..." or "暂无排行榜数据",
                fontSize = 16,
                fontWeight = "bold",
                fontColor = COLORS.muted,
                textAlign = "center",
            },
        },
    }
end

local function BuildListPanel(data)
    local rows = {}
    for _, entry in ipairs(data.list or {}) do
        rows[#rows + 1] = BuildLeaderboardRow(entry)
    end
    if #rows == 0 then
        return BuildEmptyPanel()
    end
    return UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 380,
        scrollY = true,
        showScrollbar = false,
        backgroundColor = COLORS.empty,
        borderRadius = 18,
        children = {
            UI.Panel {
                width = "100%",
                gap = 8,
                paddingTop = 8,
                paddingBottom = 8,
                paddingLeft = 8,
                paddingRight = 8,
                children = rows,
            },
        },
    }
end

local function GetPreviousRewardButtonState(data)
    if data.previousCycleId == nil then
        return "暂无上期", true, "暂无已结算的上期活动奖励"
    end
    if data.previousRewardClaimed == true then
        return "上期已领", true, string.format("上期排名 #%s，奖励已领取", tostring(data.previousRank or "--"))
    end
    if data.previousRewardEligible == true then
        return "领取上期奖励", false, string.format("上期排名 #%s，可领取头像奖励", tostring(data.previousRank or "--"))
    end
    return "未达成", true, "上期未进入前20，暂无奖励"
end

local function BuildMyRankCard(data)
    local accent = GetAccentColor()
    local rank = data.myRank or data.userRank
    local rankText = rank ~= nil and tostring(rank) or "--"
    local score = data.myScore or 0
    local name = deps_.getMyNickname and deps_.getMyNickname() or "我的昵称"
    local children = {
        BuildRankLabel(rankText),
        BuildAvatar({ isMe = true }, 70),
        UI.Panel {
            flexGrow = 1,
            flexShrink = 1,
            gap = 5,
            children = {
                UI.Label { text = name, fontSize = 14, fontWeight = "bold", fontColor = COLORS.text, maxLines = 1 },
                UI.Label { text = GetScoreLabel() .. " " .. FormatScore(score), fontSize = 12, fontWeight = "bold", fontColor = accent, maxLines = 1 },
            },
        },
    }

    if activeTab_ == "activity" then
        local buttonText, disabled, rewardHint = GetPreviousRewardButtonState(data)
        children[#children + 1] = UI.Panel {
            width = 138,
            flexShrink = 0,
            gap = 5,
            children = {
                UI.Button {
                    text = buttonText,
                    width = 138,
                    height = 40,
                    fontSize = 13,
                    fontWeight = "bold",
                    disabled = disabled,
                    backgroundColor = disabled and COLORS.disabled or accent,
                    textColor = {255, 255, 255, 255},
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 14,
                    onClick = function()
                        Suppress()
                        if disabled then return end
                        local system = GetSystem()
                        if system ~= nil and system.ClaimPreviousActivityRankReward ~= nil then
                            system.ClaimPreviousActivityRankReward()
                        elseif system ~= nil and system.ClaimActivityRankReward ~= nil then
                            system.ClaimActivityRankReward()
                        end
                    end,
                },
                UI.Label {
                    text = rewardHint,
                    width = 138,
                    fontSize = 10,
                    fontColor = COLORS.muted,
                    textAlign = "center",
                    maxLines = 2,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        height = activeTab_ == "activity" and 104 or 92,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingLeft = 14,
        paddingRight = 14,
        backgroundColor = COLORS.raised,
        borderRadius = 18,
        borderWidth = 3,
        borderColor = COLORS.borderStrong,
        children = children,
    }
end

local function BuildContentPanel()
    local data = GetCurrentList()
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        gap = 10,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text = GetHintText(),
                        flexGrow = 1,
                        flexShrink = 1,
                        fontSize = 17,
                        fontWeight = "bold",
                        fontColor = COLORS.text,
                        maxLines = 1,
                    },
                    UI.Button {
                        text = IsCurrentLoading() and "刷新中" or "刷新",
                        width = 86,
                        height = 34,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = COLORS.green,
                        hoverBackgroundColor = {94, 194, 131, 255},
                        pressedBackgroundColor = COLORS.greenDeep,
                        textColor = {255, 255, 255, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 14,
                        onClick = function()
                            Suppress()
                            RefreshCurrent()
                            RebuildContent()
                        end,
                    },
                },
            },
            BuildListPanel(data),
            BuildMyRankCard(data),
        },
    }
end

local function BuildModalContent()
    return UI.Panel {
        width = "100%",
        height = 700,
        paddingTop = 4,
        paddingBottom = 8,
        paddingLeft = 10,
        paddingRight = 10,
        gap = 12,
        children = {
            UI.Label {
                text = "排行榜",
                width = "100%",
                fontSize = 24,
                fontWeight = "bold",
                fontColor = COLORS.text,
                textAlign = "center",
                marginBottom = 0,
            },
            BuildTabBar(),
            BuildContentPanel(),
        },
    }
end

RebuildContent = function()
    if modal_ == nil then return end
    modal_:ClearContent()
    modal_:AddContent(BuildModalContent())
end

function LeaderboardView.Init(deps)
    deps_ = deps or {}
    if unsubscribeLeaderboardChanged_ == nil then
        unsubscribeLeaderboardChanged_ = EventBus.On(UIEvents.LEADERBOARD_CHANGED, function()
            RebuildContent()
        end)
    end
end

function LeaderboardView.IsOpen()
    return modal_ ~= nil
end

function LeaderboardView.Open(tabOrOptions, mode)
    local tab = tabOrOptions
    if type(tabOrOptions) == "table" then
        tab = tabOrOptions.tab
        mode = tabOrOptions.mode or mode
    end
    if mode == nil and tab == "activity" then mode = "activity" end
    sourceMode_ = mode == "activity" and "activity" or "home"
    activeTab_ = NormalizeActiveTab(tab)

    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
    modal_ = UI.Modal {
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {6, 10, 10, 10},
        borderRadius = 24,
        borderWidth = 3,
        borderColor = COLORS.borderStrong,
        onClose = function() modal_ = nil end,
    }
    modal_:AddContent(BuildModalContent())
    ModalAnim.Apply(modal_, { fixedHeight = 770, widthRatio = 0.92, maxWidthRatio = 0.98, maxHeightRatio = 0.98, offsetY = -42 })
    modal_:Open()
    RefreshCurrent()
end

function LeaderboardView.Close()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
end

function LeaderboardView.BuildButton(options)
    options = options or {}
    return UI.Button {
        text = options.text or "排行",
        width = options.width or 69,
        height = options.height or 66,
        paddingTop = 0,
        paddingRight = 16,
        paddingBottom = 5,
        paddingLeft = 16,
        fontSize = options.fontSize or 15,
        fontWeight = "bold",
        backgroundColor = options.backgroundColor or {255, 250, 240, 245},
        textColor = options.fontColor or COLORS.greenDeep,
        fontColor = options.fontColor or COLORS.greenDeep,
        borderRadius = options.borderRadius or 14,
        onClick = function()
            Suppress()
            local mode = options.mode or (options.tab == "activity" and "activity" or "home")
            LeaderboardView.Open({ tab = options.tab or (mode == "activity" and "activity" or "income"), mode = mode })
        end,
    }
end

function LeaderboardView.Shutdown()
    LeaderboardView.Close()
    if unsubscribeLeaderboardChanged_ ~= nil then
        unsubscribeLeaderboardChanged_()
        unsubscribeLeaderboardChanged_ = nil
    end
end

return LeaderboardView
