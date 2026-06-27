-- ============================================================================
-- 社交花园 UI
-- ============================================================================
-- 好友、排行榜、拜访花园、偷菜、互送种子、设置可参观地块。
-- ============================================================================

local UI = require("urhox-libs/UI")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local ModalRegistry = require("ui.modal_registry")

local SocialView = {}

local deps_ = {}
local modal_ = nil
local unsubscribeSocialChanged_ = nil
local giftSeedInput_ = "1"
local searchUserInput_ = ""
local showMessages_ = false
local activeView_ = "friends"
local RebuildContent = nil

local FRIEND_LIMIT = 50
local COLORS = {
    surface = {255, 250, 240, 245},
    surfaceRaised = {255, 252, 242, 255},
    surfaceAlt = {232, 245, 233, 235},
    text = {74, 55, 38, 255},
    textMuted = {120, 96, 68, 220},
    border = {212, 169, 106, 150},
    borderStrong = {180, 140, 80, 210},
    primary = {78, 172, 110, 255},
    primaryDeep = {50, 130, 82, 255},
    secondary = {224, 154, 70, 255},
    info = {80, 135, 185, 255},
    badge = {239, 83, 80, 255},
}

function SocialView.Init(deps)
    deps_ = deps or {}
    if unsubscribeSocialChanged_ == nil then
        unsubscribeSocialChanged_ = EventBus.On(UIEvents.SOCIAL_CHANGED, function()
            if modal_ ~= nil then
                RebuildContent()
            end
        end)
    end
end

function SocialView.IsOpen()
    return modal_ ~= nil
end

function SocialView.Close()
    if modal_ ~= nil then
        if modal_.parent ~= nil then
            modal_.parent:RemoveChild(modal_)
        end
        modal_ = nil
        ModalRegistry.NotifyClosed()
        if deps_.onClosed then deps_.onClosed() end
    end
end

function SocialView.Shutdown()
    SocialView.Close()
    if unsubscribeSocialChanged_ ~= nil then
        unsubscribeSocialChanged_()
        unsubscribeSocialChanged_ = nil
    end
end

local function GetSystem()
    return deps_.SocialGardenSystem
end

local function Suppress()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
end

RebuildContent = function()
    if modal_ == nil then return end
    local parent = modal_.parent
    if parent == nil then return end
    parent:RemoveChild(modal_)
    modal_ = SocialView.BuildOverlay()
    parent:AddChild(modal_)
end

function SocialView.RefreshContent()
    RebuildContent()
end

local function BuildSectionTitle(text)
    return UI.Label {
        text = text,
        fontSize = 16,
        fontWeight = "bold",
        fontColor = {74, 55, 38, 255},
    }
end

local function BuildSmallNote(text)
    return UI.Label {
        text = text,
        fontSize = 12,
        fontColor = {120, 96, 68, 220},
    }
end

local function BuildLeaderboardRow(entry)
    local system = GetSystem()
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingTop = 7,
        paddingBottom = 7,
        borderBottomWidth = 1,
        borderColor = {220, 205, 175, 160},
        children = {
            UI.Label { text = "#" .. tostring(entry.rank or "-"), width = 34, fontSize = 13, fontWeight = "bold", fontColor = {118, 86, 48, 255} },
            UI.Label { text = entry.nickname or tostring(entry.userId), flexGrow = 1, flexShrink = 1, fontSize = 13, fontColor = {70, 55, 38, 255} },
            UI.Label { text = tostring(entry.score or 0), width = 54, fontSize = 12, fontColor = {94, 142, 78, 255}, textAlign = "right" },
            UI.Button {
                text = "拜访",
                width = 58,
                height = 32,
                fontSize = 12,
                backgroundColor = {78, 172, 110, 255},
                fontColor = {255, 255, 255, 255},
                borderRadius = 12,
                onClick = function()
                    Suppress()
                    SocialView.Close()
                    system.VisitPlayer(entry.userId)
                end,
            },
        },
    }
end

local function BuildLeaderboardSection()
    local system = GetSystem()
    local rows = {}
    for _, entry in ipairs(system.GetLeaderboard()) do
        table.insert(rows, BuildLeaderboardRow(entry))
    end
    if #rows == 0 then
        table.insert(rows, BuildSmallNote("暂无排行榜数据，先同步一次花园。"))
    end
    return UI.Panel {
        gap = 8,
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 16,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = "观光排行榜", flexGrow = 1, fontSize = 16, fontWeight = "bold", fontColor = {74, 55, 38, 255} },
                    UI.Button {
                        text = "刷新",
                        width = 62,
                        height = 32,
                        fontSize = 12,
                        backgroundColor = {80, 135, 185, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 12,
                        onClick = function()
                            Suppress()
                            system.RequestLeaderboard()
                            RebuildContent()
                        end,
                    },
                },
            },
            UI.Panel { gap = 2, children = rows },
        },
    }
end

local function BuildFriendAvatar(entry)
    local name = tostring(entry.nickname or entry.userId or "友")
    local first = string.sub(name, 1, 3)
    return UI.Panel {
        width = 64,
        height = 64,
        borderRadius = 999,
        borderWidth = 3,
        borderColor = COLORS.border,
        backgroundColor = COLORS.surfaceAlt,
        alignItems = "center",
        justifyContent = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = first,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = COLORS.text,
                textAlign = "center",
                maxLines = 1,
            },
        },
    }
end

local function BuildSourceBadge(source)
    local sourceText = source == "recent_visitor" and "来访" or source == "recent_visit" and "最近" or source == "rank" and "排行" or "推荐"
    return UI.Panel {
        paddingLeft = 8,
        paddingRight = 8,
        height = 24,
        borderRadius = 999,
        backgroundColor = {232, 245, 233, 255},
        borderWidth = 2,
        borderColor = {94, 194, 131, 130},
        alignItems = "center",
        justifyContent = "center",
        children = {
            UI.Label {
                text = sourceText,
                fontSize = 10,
                fontWeight = "bold",
                fontColor = {46, 125, 50, 255},
                maxLines = 1,
            },
        },
    }
end

local function BuildFriendActionButton(text, color, onClick)
    return UI.Button {
        text = text,
        width = 74,
        height = 44,
        fontSize = 13,
        fontWeight = "bold",
        backgroundColor = color,
        fontColor = {255, 255, 255, 255},
        borderRadius = 16,
        onClick = function()
            Suppress()
            onClick()
        end,
    }
end

local function BuildFriendRow(entry)
    local system = GetSystem()
    local playerName = tostring(entry.nickname or entry.userId or "神秘园丁")
    local scoreText = tostring(entry.score or entry.tourValue or 0)
    return UI.Panel {
        width = "100%",
        minHeight = 94,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = COLORS.surfaceRaised,
        borderRadius = 20,
        borderWidth = 3,
        borderColor = COLORS.border,
        children = {
            BuildFriendAvatar(entry),
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 5,
                children = {
                    UI.Label {
                        text = playerName,
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = COLORS.text,
                        maxLines = 1,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            BuildSourceBadge(entry.source),
                            UI.Label {
                                text = scoreText .. " 观光值",
                                fontSize = 11,
                                fontWeight = "bold",
                                fontColor = {94, 142, 78, 255},
                                maxLines = 1,
                            },
                        },
                    },
                    UI.Label {
                        text = "ID " .. tostring(entry.userId or "--"),
                        fontSize = 10,
                        fontColor = COLORS.textMuted,
                        maxLines = 1,
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                flexShrink = 0,
                children = {
                    BuildFriendActionButton("送礼", COLORS.info, function()
                        system.SendSeedGift(entry.userId, tonumber(giftSeedInput_) or 1)
                        RebuildContent()
                    end),
                    BuildFriendActionButton("拜访", COLORS.primary, function()
                        SocialView.Close()
                        system.VisitPlayer(entry.userId)
                    end),
                },
            },
        },
    }
end

local function BuildMessageButton()
    local system = GetSystem()
    local count = #system.GetGifts() + #system.GetRecentVisitors() + #system.GetStealLogs()
    return UI.Panel {
        width = 76,
        height = 56,
        borderRadius = 22,
        backgroundColor = activeView_ == "messages" and {232, 245, 233, 255} or COLORS.surfaceRaised,
        borderWidth = 3,
        borderColor = activeView_ == "messages" and {94, 194, 131, 210} or COLORS.border,
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            Suppress()
            activeView_ = "messages"
            RebuildContent()
        end,
        children = {
            UI.Label { text = "消息", fontSize = 13, fontWeight = "bold", fontColor = COLORS.text },
            UI.Panel {
                display = count > 0 and "flex" or "none",
                position = "absolute",
                top = 0,
                right = 0,
                width = 22,
                height = 22,
                borderRadius = 999,
                backgroundColor = COLORS.badge,
                borderWidth = 2,
                borderColor = {255, 252, 242, 255},
                alignItems = "center",
                justifyContent = "center",
                children = {
                    UI.Label { text = tostring(math.min(count, 9)), fontSize = 10, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
                },
            },
        },
    }
end

local function BuildQuickActionPanel()
    local system = GetSystem()
    local state = system.GetState and system.GetState() or {}
    local daily = state.daily or {}
    local stealLeft = math.max(0, 10 - (daily.stealCount or 0))
    local giftLeft = math.max(0, 5 - (daily.giftSentCount or 0))
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        height = 36,
                        paddingLeft = 12,
                        paddingRight = 10,
                        borderRadius = 18,
                        backgroundColor = COLORS.surfaceRaised,
                        borderWidth = 2,
                        borderColor = COLORS.border,
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label { text = "可偷", fontSize = 12, fontWeight = "bold", fontColor = COLORS.text },
                            UI.Label { text = tostring(stealLeft), fontSize = 13, fontWeight = "bold", fontColor = COLORS.text },
                            UI.Button {
                                text = "+",
                                width = 24,
                                height = 24,
                                fontSize = 14,
                                fontWeight = "bold",
                                backgroundColor = {255, 255, 255, 245},
                                fontColor = COLORS.text,
                                borderRadius = 12,
                                borderWidth = 1,
                                borderColor = COLORS.border,
                                onClick = function()
                                    Suppress()
                                    local friends = system.GetFriends()
                                    local first = friends and friends[1]
                                    if first ~= nil and first.userId ~= nil then
                                        SocialView.Close()
                                        system.VisitPlayer(first.userId)
                                    elseif deps_.showToast then
                                        deps_.showToast("暂无可拜访好友，点击刷新获取推荐玩家")
                                    end
                                end,
                            },
                        },
                    },
                    UI.Panel {
                        height = 36,
                        paddingLeft = 12,
                        paddingRight = 12,
                        borderRadius = 18,
                        backgroundColor = COLORS.surfaceRaised,
                        borderWidth = 2,
                        borderColor = COLORS.border,
                        justifyContent = "center",
                        children = {
                            UI.Label { text = "赠礼  " .. tostring(giftLeft), fontSize = 12, fontWeight = "bold", fontColor = COLORS.text },
                        },
                    },
                },
            },
        },
    }
end

local function HandleAddFriendByInput()
    local userId = tonumber(searchUserInput_ or "")
    if userId == nil or userId <= 0 then
        if deps_.showToast then deps_.showToast("请输入有效玩家 ID") end
        return false
    end
    if deps_.showToast then deps_.showToast("好友请求已发送") end
    return true
end

local function BuildSearchFriendPanel()
    local system = GetSystem()
    return UI.Panel {
        width = "100%",
        gap = 10,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = COLORS.surfaceRaised,
        borderRadius = 20,
        borderWidth = 3,
        borderColor = COLORS.border,
        children = {
            UI.Label { text = "搜索玩家", fontSize = 15, fontWeight = "bold", fontColor = COLORS.text },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.TextField {
                        value = searchUserInput_,
                        placeholder = "输入玩家ID",
                        height = 42,
                        flexGrow = 1,
                        fontSize = 12,
                        borderRadius = 16,
                        onChange = function(_, value) searchUserInput_ = value or "" end,
                    },
                    UI.Button {
                        text = "拜访",
                        width = 64,
                        height = 42,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = COLORS.primary,
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            Suppress()
                            SocialView.Close()
                            system.VisitByInput(searchUserInput_)
                        end,
                    },
                    UI.Button {
                        text = "加好友",
                        width = 76,
                        height = 42,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = COLORS.info,
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            Suppress()
                            HandleAddFriendByInput()
                        end,
                    },
                },
            },
        },
    }
end

local function BuildFriendsSection()
    local system = GetSystem()
    local friends = system.GetFriends()
    local rows = {}
    for _, entry in ipairs(friends) do
        table.insert(rows, BuildFriendRow(entry))
    end
    if #rows == 0 then
        table.insert(rows, UI.Panel {
            height = 160,
            alignItems = "center",
            justifyContent = "center",
            backgroundColor = COLORS.surfaceRaised,
            borderRadius = 20,
            borderWidth = 3,
            borderColor = COLORS.border,
            children = {
                UI.Label { text = "暂无好友数据", fontSize = 15, fontWeight = "bold", fontColor = COLORS.text },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        gap = 12,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "好友",
                                fontSize = 24,
                                fontWeight = "bold",
                                fontColor = COLORS.text,
                                textAlign = "left",
                            },
                            UI.Label {
                                text = string.format("好友上限：%d/%d", #friends, FRIEND_LIMIT),
                                fontSize = 14,
                                fontWeight = "bold",
                                fontColor = COLORS.text,
                            },
                        },
                    },
                    BuildMessageButton(),
                },
            },
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = false,
                children = {
                    UI.Panel {
                        gap = 10,
                        children = rows,
                    },
                },
            },
            BuildSearchFriendPanel(),
        },
    }
end

local function BuildMessageActionButton(text, color, onClick)
    return UI.Button {
        text = text,
        height = 38,
        flexGrow = 1,
        fontSize = 13,
        fontWeight = "bold",
        backgroundColor = color,
        fontColor = {255, 255, 255, 255},
        borderRadius = 16,
        onClick = function()
            Suppress()
            if onClick then onClick() end
            RebuildContent()
        end,
    }
end

local function BuildMessageRow(text, actions)
    local children = {}
    children[#children + 1] = UI.Label {
        text = text,
        fontSize = 15,
        fontWeight = "bold",
        fontColor = COLORS.text,
        flexShrink = 1,
    }
    if actions ~= nil then
        children[#children + 1] = UI.Panel {
            flexDirection = "row",
            gap = 18,
            paddingTop = 12,
            children = actions,
        }
    end
    return UI.Panel {
        width = "100%",
        minHeight = actions and 98 or 70,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        borderWidth = 3,
        borderColor = COLORS.border,
        borderRadius = 20,
        backgroundColor = COLORS.surfaceRaised,
        gap = 4,
        children = children,
    }
end

local function BuildMessagesSection()
    local system = GetSystem()
    local rows = {}
    local friends = system.GetFriends()
    local friendCount = #friends

    for _, visitor in ipairs(system.GetRecentVisitors()) do
        rows[#rows + 1] = BuildMessageRow(
            tostring(visitor.nickname or visitor.userId or "玩家") .. "请求添加你为好友",
            {
                BuildMessageActionButton("拒绝", COLORS.info, function() end),
                BuildMessageActionButton("同意", COLORS.info, function() end),
            }
        )
    end

    for _, log in ipairs(system.GetStealLogs()) do
        rows[#rows + 1] = BuildMessageRow(string.format("%s从你的花园里偷走了%s的种子", tostring(log.thiefNickname or log.thiefUserId or "玩家"), tostring(log.cropName or "作物")))
    end

    for _, gift in ipairs(system.GetGifts()) do
        rows[#rows + 1] = BuildMessageRow(string.format("%s给你送来了种子礼物", tostring(gift.fromUserId or "好友")), {
            BuildMessageActionButton("领取", COLORS.info, function()
                system.ClaimGift(gift)
            end),
        })
    end

    if #rows == 0 then
        rows[#rows + 1] = BuildMessageRow("暂无新消息")
    end

    return UI.Panel {
        gap = 16,
        children = {
            UI.Label { text = "消息列表", fontSize = 24, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center" },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label { text = string.format("好友上限：%d/%d", friendCount, FRIEND_LIMIT), flexGrow = 1, fontSize = 14, fontWeight = "bold", fontColor = COLORS.text },
                    UI.Button {
                        text = "关闭",
                        width = 76,
                        height = 42,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = COLORS.surfaceRaised,
                        fontColor = COLORS.text,
                        borderWidth = 3,
                        borderColor = COLORS.border,
                        borderRadius = 22,
                        onClick = function()
                            Suppress()
                            activeView_ = "friends"
                            RebuildContent()
                        end,
                    },
                },
            },
            UI.ScrollView {
                height = 540,
                scrollY = true,
                showScrollbar = false,
                children = {
                    UI.Panel { gap = 16, children = rows },
                },
            },
        },
    }
end

local function FormatTimeText(value)
    if value == nil then return "刚刚" end
    return tostring(value)
end

local function BuildSocialLogSection()
    local system = GetSystem()
    local rows = {}
    for _, log in ipairs(system.GetStealLogs()) do
        local resultText = log.gotSeed and "偷到种子" or "没偷到种子"
        rows[#rows + 1] = UI.Panel {
            gap = 2,
            paddingTop = 5,
            paddingBottom = 5,
            borderBottomWidth = 1,
            borderColor = {220, 205, 175, 130},
            children = {
                UI.Label { text = string.format("%s 偷了 %s · %s", tostring(log.thiefNickname or log.thiefUserId or "玩家"), tostring(log.cropName or "作物"), resultText), fontSize = 12, fontColor = {70, 55, 38, 255} },
                UI.Label { text = "时间 " .. FormatTimeText(log.stolenAt or log.time), fontSize = 10, fontColor = {130, 105, 80, 210} },
            },
        }
    end
    if #rows == 0 then rows[#rows + 1] = BuildSmallNote("暂无偷菜记录。") end

    local visitorRows = {}
    for _, visitor in ipairs(system.GetRecentVisitors()) do
        visitorRows[#visitorRows + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Label { text = tostring(visitor.nickname or visitor.userId or "玩家"), flexGrow = 1, flexShrink = 1, fontSize = 12, fontColor = {70, 55, 38, 255} },
                UI.Button {
                    text = "回访",
                    width = 58,
                    height = 30,
                    fontSize = 11,
                    backgroundColor = {78, 172, 110, 255},
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 12,
                    onClick = function()
                        Suppress()
                        SocialView.Close()
                        system.VisitPlayer(visitor.userId)
                    end,
                },
            },
        }
    end
    if #visitorRows == 0 then visitorRows[#visitorRows + 1] = BuildSmallNote("暂无最近来访。") end

    return UI.Panel {
        gap = 8,
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 16,
        children = {
            BuildSectionTitle("偷菜记录"),
            UI.Panel { gap = 2, children = rows },
            BuildSectionTitle("最近来访"),
            UI.Panel { gap = 6, children = visitorRows },
        },
    }
end

local function BuildGiftSection()
    local system = GetSystem()
    local rows = {}
    for _, gift in ipairs(system.GetGifts()) do
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Label { text = string.format("来自 %s 的种子%d x%d", tostring(gift.fromUserId or "好友"), gift.seedId or 1, gift.count or 1), flexGrow = 1, fontSize = 12, fontColor = {70, 55, 38, 255} },
                UI.Button {
                    text = "领取",
                    width = 58,
                    height = 32,
                    fontSize = 12,
                    backgroundColor = {78, 172, 110, 255},
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 12,
                    onClick = function()
                        Suppress()
                        system.ClaimGift(gift)
                        RebuildContent()
                    end,
                },
            },
        })
    end
    if #rows == 0 then table.insert(rows, BuildSmallNote("暂无未领取礼物。")) end
    return UI.Panel {
        gap = 8,
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 16,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label { text = "好友礼物", flexGrow = 1, fontSize = 16, fontWeight = "bold", fontColor = {74, 55, 38, 255} },
                    UI.Button {
                        text = "刷新",
                        width = 62,
                        height = 32,
                        fontSize = 12,
                        backgroundColor = {80, 135, 185, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 12,
                        onClick = function()
                            Suppress()
                            system.RequestGifts()
                            RebuildContent()
                        end,
                    },
                },
            },
            UI.Panel { gap = 6, children = rows },
        },
    }
end

local function BuildVisitCropRows()
    local system = GetSystem()
    if not system.IsVisitMode() then return {} end
    local rows = {}
    for index, crop in ipairs(system.GetVisitCrops()) do
        local stealable = crop.mature == true and crop.stolen ~= true
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            paddingTop = 5,
            paddingBottom = 5,
            children = {
                UI.Label {
                    text = string.format("%s%s · 种子率%s", crop.name or "作物", crop.stolen and "（已偷）" or "", system.GetStealChanceText(crop)),
                    flexGrow = 1,
                    flexShrink = 1,
                    fontSize = 12,
                    fontColor = crop.stolen and {150, 120, 95, 200} or {70, 55, 38, 255},
                },
                UI.Label {
                    text = crop.mature and "成熟" or "生长中",
                    width = 50,
                    fontSize = 11,
                    fontColor = crop.mature and {78, 150, 84, 255} or {150, 120, 82, 220},
                    textAlign = "right",
                },
                UI.Button {
                    text = stealable and "偷取" or "不可偷",
                    width = 60,
                    height = 30,
                    fontSize = 11,
                    backgroundColor = stealable and {224, 154, 70, 255} or {190, 180, 165, 180},
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 12,
                    onClick = function()
                        Suppress()
                        if stealable then
                            if not system.IsStealingMode() then system.BeginStealingMode() end
                            system.RequestSteal(index, crop.cropId)
                            RebuildContent()
                        end
                    end,
                },
            },
        })
    end
    if #rows == 0 then
        table.insert(rows, BuildSmallNote("这个可参观地块暂无作物。"))
    end
    return rows
end

local function BuildVisitStealSection()
    local system = GetSystem()
    if not system.IsVisitMode() then return UI.Panel { width = 0, height = 0 } end
    local stealing = system.IsStealingMode()
    local garden = system.GetVisitGarden() or {}
    return UI.Panel {
        gap = 8,
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 16,
        borderWidth = 2,
        borderColor = {224, 154, 70, 160},
        children = {
            BuildSectionTitle("拜访中：" .. tostring(garden.nickname or "好友")),
            BuildSmallNote(stealing and "偷菜中：点击地块上的成熟作物，有概率获得该作物种子。" or "默认是观光状态。点击偷菜后进入聚焦视角，再点击成熟作物。"),
            UI.Panel { gap = 3, children = BuildVisitCropRows() },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    UI.Button {
                        text = stealing and "退出偷菜" or "开始偷菜",
                        height = 38,
                        flexGrow = 1,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = stealing and {150, 120, 90, 255} or {224, 154, 70, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 14,
                        onClick = function()
                            Suppress()
                            if stealing then
                                system.EndStealingMode()
                            else
                                system.BeginStealingMode()
                            end
                            RebuildContent()
                        end,
                    },
                    UI.Button {
                        text = "返回我的花园",
                        height = 38,
                        flexGrow = 1,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = {78, 172, 110, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 14,
                        onClick = function()
                            Suppress()
                            system.ReturnHome()
                            SocialView.Close()
                        end,
                    },
                },
            },
        },
    }
end

function SocialView.BuildContent()
    if activeView_ == "messages" then
        return BuildMessagesSection()
    end
    return BuildFriendsSection()
end

function SocialView.BuildOverlay()
    return UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        zIndex = 1000,
        backgroundColor = {0, 0, 0, 150},
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            SocialView.Close()
        end,
        children = {
            UI.Panel {
                width = 500,
                height = 720,
                position = "relative",
                backgroundColor = COLORS.surfaceRaised,
                borderWidth = 4,
                borderColor = COLORS.borderStrong,
                borderRadius = 26,
                paddingTop = 42,
                paddingLeft = 18,
                paddingRight = 18,
                paddingBottom = 18,
                boxShadow = {
                    { x = 0, y = 6, blur = 0, spread = 0, color = {30, 30, 30, 90} },
                },
                onTap = function(event)
                    if event and event.StopPropagation then event:StopPropagation() end
                    Suppress()
                end,
                children = {
                    activeView_ == "friends" and UI.Panel {
                        position = "absolute",
                        top = -24,
                        left = 16,
                        zIndex = 2,
                        children = { BuildQuickActionPanel() },
                    } or UI.Panel { width = 0, height = 0 },
                    SocialView.BuildContent(),
                },
            },
        },
    }
end

function SocialView.Open(skipRequests)
    Suppress()
    activeView_ = "friends"
    local system = GetSystem()
    if skipRequests ~= true then
        system.RequestGifts()
    end
    if modal_ ~= nil then SocialView.Close() end
    local root = UI.GetRoot()
    if root == nil then return end
    modal_ = SocialView.BuildOverlay()
    root:AddChild(modal_)
end

function SocialView.BuildButton()
    return UI.Button {
        text = "好友",
        width = 69,
        height = 66,
        paddingTop = 0,
        paddingRight = 16,
        paddingBottom = 5,
        paddingLeft = 16,
        fontSize = 15,
        fontWeight = "bold",
        backgroundColor = {255, 250, 240, 245},
        fontColor = {62, 138, 172, 255},
        borderRadius = 14,
        onClick = function()
            SocialView.Open()
        end,
    }
end

function SocialView.BuildVisitBanner()
    local system = GetSystem()
    if not system.IsVisitMode() then return UI.Panel { width = 0, height = 0 } end
    local garden = system.GetVisitGarden() or {}
    local stealing = system.IsStealingMode()
    return UI.Panel {
        position = "absolute",
        top = 102,
        left = 24,
        right = 24,
        zIndex = 50,
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 14,
        paddingRight = 14,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 18,
        borderWidth = 2,
        borderColor = stealing and {224, 154, 70, 210} or {78, 172, 110, 210},
        children = {
            UI.Label {
                text = stealing and "偷菜中：点击成熟作物，有概率获得该作物种子" or ("正在拜访 " .. tostring(garden.nickname or "好友") .. " 的花园"),
                fontSize = 14,
                fontWeight = "bold",
                fontColor = {70, 55, 38, 255},
                textAlign = "center",
            },
        },
    }
end

return SocialView
