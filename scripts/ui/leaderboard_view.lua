-- ============================================================================
-- 排行榜 UI
-- ============================================================================
-- 延续现有动物森友会风格：柔和纸张底色、圆角卡片、粗边框与轻阴影。
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

local COLORS = {
    paper = {255, 250, 240, 250},
    raised = {255, 252, 242, 255},
    soft = {232, 245, 233, 245},
    text = {74, 55, 38, 255},
    muted = {120, 96, 68, 225},
    border = {212, 169, 106, 160},
    borderStrong = {180, 140, 80, 220},
    green = {78, 172, 110, 255},
    greenDeep = {50, 130, 82, 255},
    blue = {80, 135, 185, 255},
    orange = {224, 154, 70, 255},
    purple = {126, 98, 164, 255},
    disabled = {178, 166, 148, 200},
}

local ACTIVITY_COLORS = {
    sweet = { accent = COLORS.orange, soft = {255, 229, 204, 255}, title = "甜蜜蜜" },
    alien = { accent = COLORS.green, soft = {220, 247, 230, 255}, title = "外星基因" },
    dark = { accent = COLORS.purple, soft = {236, 226, 246, 255}, title = "黑暗来临" },
}

local function Suppress()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
end

local function GetSystem()
    return deps_.LeaderboardSystem
end

local function CardShadow()
    return {
        { x = 0, y = 5, blur = 0, spread = 0, color = {106, 72, 32, 38} },
    }
end

local function FormatScore(value)
    value = math.max(0, math.floor(tonumber(value or 0) or 0))
    if value >= 100000000 then return string.format("%.1f亿", value / 100000000) end
    if value >= 10000 then return string.format("%.1f万", value / 10000) end
    return tostring(value)
end

local function GetActiveActivityId()
    if deps_.getActiveActivityId then return deps_.getActiveActivityId() end
    return "sweet"
end

local function GetActivityTitle(activityId)
    local theme = ACTIVITY_COLORS[activityId or "sweet"] or ACTIVITY_COLORS.sweet
    return theme.title
end

local function GetActivityTheme(activityId)
    return ACTIVITY_COLORS[activityId or "sweet"] or ACTIVITY_COLORS.sweet
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

local RebuildContent

local function BuildTabButton(tab, text, color)
    local selected = activeTab_ == tab
    return UI.Panel {
        width = 132,
        height = 46,
        borderRadius = 18,
        borderWidth = 3,
        borderColor = selected and color or COLORS.border,
        backgroundColor = selected and color or COLORS.raised,
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            Suppress()
            activeTab_ = tab
            RefreshCurrent()
            RebuildContent()
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = selected and {255, 255, 255, 255} or COLORS.text,
                maxLines = 1,
            },
        },
    }
end

local function BuildRankBadge(rank)
    local color = COLORS.soft
    local textColor = COLORS.text
    if rank == 1 then color = {255, 225, 140, 255}; textColor = {138, 91, 24, 255}
    elseif rank == 2 then color = {224, 232, 238, 255}; textColor = {92, 106, 116, 255}
    elseif rank == 3 then color = {232, 188, 146, 255}; textColor = {128, 72, 36, 255} end
    return UI.Panel {
        width = 48,
        height = 48,
        borderRadius = 999,
        backgroundColor = color,
        borderWidth = 3,
        borderColor = {255, 252, 242, 255},
        alignItems = "center",
        justifyContent = "center",
        flexShrink = 0,
        children = {
            UI.Label { text = "#" .. tostring(rank or "-"), fontSize = 14, fontWeight = "bold", fontColor = textColor },
        },
    }
end

local function BuildLeaderboardRow(entry)
    local accent = activeTab_ == "income" and COLORS.orange or activeTab_ == "tour" and COLORS.green or GetActivityTheme(GetActiveActivityId()).accent
    return UI.Panel {
        width = "100%",
        minHeight = 66,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingTop = 8,
        paddingBottom = 8,
        paddingLeft = 10,
        paddingRight = 12,
        borderRadius = 18,
        borderWidth = entry.isMe and 3 or 2,
        borderColor = entry.isMe and accent or COLORS.border,
        backgroundColor = entry.isMe and {255, 248, 222, 255} or COLORS.raised,
        children = {
            BuildRankBadge(entry.rank),
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 4,
                children = {
                    UI.Label {
                        text = entry.isMe and ((entry.nickname or "你") .. "  我") or (entry.nickname or tostring(entry.userId or "Tap玩家")),
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = COLORS.text,
                        maxLines = 1,
                    },
                    UI.Label {
                        text = "ID " .. tostring(entry.userId or "--"),
                        fontSize = 10,
                        fontColor = COLORS.muted,
                        maxLines = 1,
                    },
                },
            },
            UI.Panel {
                alignItems = "flex-end",
                gap = 2,
                flexShrink = 0,
                children = {
                    UI.Label { text = FormatScore(entry.score), fontSize = 18, fontWeight = "bold", fontColor = accent, textAlign = "right" },
                    UI.Label { text = activeTab_ == "income" and "收入" or activeTab_ == "tour" and "观光值" or "活动分", fontSize = 10, fontColor = COLORS.muted, textAlign = "right" },
                },
            },
        },
    }
end

local function BuildMyRankCard(data)
    local rank = data.myRank or data.userRank
    local score = data.myScore or 0
    local text = rank ~= nil and ("我的排名 #" .. tostring(rank)) or "我的排名 暂未上榜"
    return UI.Panel {
        width = "100%",
        minHeight = 58,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingLeft = 16,
        paddingRight = 16,
        borderRadius = 20,
        borderWidth = 3,
        borderColor = COLORS.borderStrong,
        backgroundColor = {255, 248, 222, 255},
        children = {
            UI.Label { text = text, flexGrow = 1, flexShrink = 1, fontSize = 15, fontWeight = "bold", fontColor = COLORS.text, maxLines = 1 },
            UI.Label { text = FormatScore(score), fontSize = 18, fontWeight = "bold", fontColor = COLORS.greenDeep, maxLines = 1 },
        },
    }
end

local function BuildActivityRewardPanel(data)
    if activeTab_ ~= "activity" then return nil end
    local eligible = data.rewardEligible == true
    local claimed = data.rewardClaimed == true
    local rewardText = claimed and "本期头像奖励已领取" or eligible and "前20名可领取随机未解锁头像" or "活动榜前20名可获得随机头像解锁"
    return UI.Panel {
        width = "100%",
        minHeight = 76,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingLeft = 16,
        paddingRight = 16,
        borderRadius = 22,
        borderWidth = 3,
        borderColor = GetActivityTheme(data.activityId).accent,
        backgroundColor = GetActivityTheme(data.activityId).soft,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 4,
                children = {
                    UI.Label { text = "活动排行奖励", fontSize = 16, fontWeight = "bold", fontColor = COLORS.text, maxLines = 1 },
                    UI.Label { text = rewardText, fontSize = 12, fontColor = COLORS.muted, maxLines = 2 },
                },
            },
            UI.Button {
                text = claimed and "已领取" or "领取",
                width = 92,
                height = 42,
                fontSize = 14,
                fontWeight = "bold",
                disabled = (not eligible) or claimed,
                backgroundColor = eligible and (not claimed) and GetActivityTheme(data.activityId).accent or COLORS.disabled,
                fontColor = {255, 255, 255, 255},
                borderRadius = 16,
                onClick = function()
                    Suppress()
                    local system = GetSystem()
                    if system ~= nil then system.ClaimActivityRankReward(data.activityId) end
                end,
            },
        },
    }
end

local function BuildContentPanel()
    local data = GetCurrentList()
    local rows = {}
    for _, entry in ipairs(data.list or {}) do
        rows[#rows + 1] = BuildLeaderboardRow(entry)
    end
    if #rows == 0 then
        rows[#rows + 1] = UI.Panel {
            height = 160,
            alignItems = "center",
            justifyContent = "center",
            borderRadius = 22,
            borderWidth = 3,
            borderColor = COLORS.border,
            backgroundColor = COLORS.raised,
            children = {
                UI.Label { text = IsCurrentLoading() and "排行榜加载中..." or "暂无排行榜数据", fontSize = 16, fontWeight = "bold", fontColor = COLORS.text },
            },
        }
    end

    local title = activeTab_ == "income" and "收入排行榜" or activeTab_ == "tour" and "观光排行榜" or (GetActivityTitle(GetActiveActivityId()) .. "排行榜")
    local subtitle = activeTab_ == "income" and "每7天刷新一次，统计本周累计出售收入"
        or activeTab_ == "tour" and "永久榜，不刷新，统计历史最佳观光值"
        or "统计本期活动累计成绩，前20名可领取头像奖励"
    local rewardPanel = BuildActivityRewardPanel(data)
    local scrollPanel = UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = false,
        children = {
            UI.Panel { width = "100%", gap = 8, paddingBottom = 8, children = rows },
        },
    }
    local children = {
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 5,
                    children = {
                        UI.Label { text = title, fontSize = 22, fontWeight = "bold", fontColor = COLORS.text, maxLines = 1 },
                        UI.Label { text = subtitle, fontSize = 12, fontColor = COLORS.muted, maxLines = 2 },
                    },
                },
                UI.Button {
                    text = IsCurrentLoading() and "读取中" or "刷新",
                    width = 82,
                    height = 40,
                    fontSize = 13,
                    fontWeight = "bold",
                    backgroundColor = COLORS.blue,
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 16,
                    onClick = function()
                        Suppress()
                        RefreshCurrent()
                        RebuildContent()
                    end,
                },
            },
        },
        BuildMyRankCard(data),
        scrollPanel,
    }
    if rewardPanel ~= nil then children[#children + 1] = rewardPanel end
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        gap = 12,
        paddingTop = 14,
        paddingBottom = 14,
        paddingLeft = 14,
        paddingRight = 14,
        borderRadius = 24,
        borderWidth = 3,
        borderColor = COLORS.border,
        backgroundColor = COLORS.paper,
        children = children,
    }
end

local function BuildModalContent()
    return UI.Panel {
        width = "100%",
        height = 610,
        paddingTop = 18,
        paddingBottom = 12,
        paddingLeft = 16,
        paddingRight = 16,
        gap = 12,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Label { text = "花园排行榜", flexGrow = 1, fontSize = 26, fontWeight = "bold", fontColor = COLORS.text },
                },
            },
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                gap = 10,
                children = {
                    BuildTabButton("income", "收入榜", COLORS.orange),
                    BuildTabButton("tour", "观光榜", COLORS.green),
                    BuildTabButton("activity", "活动榜", GetActivityTheme(GetActiveActivityId()).accent),
                },
            },
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

function LeaderboardView.Open(tab)
    if tab ~= nil then activeTab_ = tab end
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
    modal_ = UI.Modal {
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {4, 8, 8, 8},
        onClose = function() modal_ = nil end,
    }
    modal_:AddContent(BuildModalContent())
    ModalAnim.Apply(modal_, { fixedHeight = 675, widthRatio = 0.94, maxWidthRatio = 0.98, maxHeightRatio = 0.98 })
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
        fontColor = options.fontColor or COLORS.greenDeep,
        borderRadius = options.borderRadius or 14,
        onClick = function()
            Suppress()
            LeaderboardView.Open(options.tab or "income")
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
