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
local friendDetailModal_ = nil
local visitErrorModal_ = nil
local CloseFriendDetailModal = nil
local ShowVisitError = nil
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

local function GetPlantImageIndex(index)
    index = math.floor(tonumber(index or 1) or 1)
    if index >= 1 and index <= 47 then return index end
    return ((index - 1) % 29) + 1
end

local function GetAvatarImagePath(avatar)
    if type(avatar) ~= "table" then return "image/plants/plants (1).png" end
    if avatar.image ~= nil and avatar.image ~= "" then return avatar.image end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    if plantIndex ~= nil then
        return string.format("image/plants/plants (%d).png", GetPlantImageIndex(plantIndex))
    end
    return "image/plants/plants (1).png"
end

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
    CloseFriendDetailModal()
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
    CloseFriendDetailModal()
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
                    if system.VisitPlayer(entry.userId) then
                        SocialView.Close()
                    else
                        ShowVisitError(system.GetRequestError and system.GetRequestError("visit") or nil)
                    end
                end,
            },
        },
    }
end

local function BuildLeaderboardSection()
    local system = GetSystem()
    local loading = system.IsLeaderboardLoading and system.IsLeaderboardLoading() == true
    local rankError = system.GetRequestError and system.GetRequestError("rank") or nil
    local rows = {}
    for _, entry in ipairs(system.GetLeaderboard()) do
        table.insert(rows, BuildLeaderboardRow(entry))
    end
    if loading then
        table.insert(rows, BuildSmallNote("榜单刷新中，请稍候..."))
    elseif rankError ~= nil and rankError ~= "" then
        table.insert(rows, BuildSmallNote(tostring(rankError) .. "，请稍后再试。"))
    elseif #rows == 0 then
        table.insert(rows, BuildSmallNote("暂无排行榜数据，点击刷新同步花园榜单。"))
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
                        text = loading and "刷新中" or "刷新",
                        width = 70,
                        height = 32,
                        fontSize = 12,
                        backgroundColor = loading and {150, 140, 125, 220} or {80, 135, 185, 255},
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

local function BuildTourIcon(size)
    size = size or 22
    local inner = math.max(10, math.floor(size * 0.64))
    return UI.Panel {
        width = size,
        height = size,
        justifyContent = "center",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Panel { width = size, height = size, borderRadius = math.floor(size / 2), backgroundColor = {190, 160, 230, 255} },
            UI.Panel { position = "absolute", width = inner, height = inner, borderRadius = math.floor(inner / 2), backgroundColor = {155, 120, 210, 255} },
            UI.Label { position = "absolute", text = "★", fontSize = math.max(10, math.floor(size * 0.5)), fontColor = {245, 240, 255, 255} },
        },
    }
end

local function BuildFriendAvatar(entry)
    local avatar = entry and entry.avatar or nil
    local name = tostring(entry.nickname or entry.userId or "友")
    local first = string.sub(name, 1, 3)
    local avatarImage = GetAvatarImagePath(avatar)
    local avatarColor = avatar and avatar.color or COLORS.surfaceAlt
    local children = {}
    if avatarImage ~= nil and avatarImage ~= "" then
        children[#children + 1] = UI.Panel {
            width = 48,
            height = 48,
            backgroundImage = avatarImage,
            backgroundFit = "contain",
        }
    else
        children[#children + 1] = UI.Label {
            text = first,
            fontSize = 15,
            fontWeight = "bold",
            fontColor = COLORS.text,
            textAlign = "center",
            maxLines = 1,
        }
    end
    return UI.Panel {
        width = 64,
        height = 64,
        borderRadius = 999,
        borderWidth = 3,
        borderColor = COLORS.border,
        backgroundColor = avatarColor,
        alignItems = "center",
        justifyContent = "center",
        flexShrink = 0,
        children = children,
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

ShowVisitError = function(message)
    local root = UI.GetRoot()
    if root == nil then return end
    if visitErrorModal_ ~= nil and visitErrorModal_.parent ~= nil then
        visitErrorModal_.parent:RemoveChild(visitErrorModal_)
    end
    visitErrorModal_ = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        zIndex = 1250,
        backgroundColor = {0, 0, 0, 120},
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            Suppress()
            if visitErrorModal_ ~= nil and visitErrorModal_.parent ~= nil then
                visitErrorModal_.parent:RemoveChild(visitErrorModal_)
            end
            visitErrorModal_ = nil
        end,
        children = {
            UI.Panel {
                width = 380,
                backgroundColor = COLORS.surfaceRaised,
                borderRadius = 24,
                borderWidth = 4,
                borderColor = COLORS.borderStrong,
                paddingTop = 24,
                paddingLeft = 22,
                paddingRight = 22,
                paddingBottom = 22,
                gap = 14,
                onTap = function(event)
                    if event and event.StopPropagation then event:StopPropagation() end
                    Suppress()
                end,
                children = {
                    UI.Label { text = "网络连接失败", fontSize = 22, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center" },
                    UI.Label { text = message or "无法拜访该花园，请检查网络后重试", fontSize = 15, fontColor = COLORS.textMuted, textAlign = "center", whiteSpace = "normal" },
                    UI.Button {
                        text = "知道了",
                        height = 42,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = COLORS.primary,
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            if visitErrorModal_ ~= nil and visitErrorModal_.parent ~= nil then
                                visitErrorModal_.parent:RemoveChild(visitErrorModal_)
                            end
                            visitErrorModal_ = nil
                        end,
                    },
                },
            },
        },
    }
    root:AddChild(visitErrorModal_)
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

CloseFriendDetailModal = function()
    if friendDetailModal_ ~= nil then
        if friendDetailModal_.parent ~= nil then
            friendDetailModal_.parent:RemoveChild(friendDetailModal_)
        end
        friendDetailModal_ = nil
    end
    if visitErrorModal_ ~= nil then
        if visitErrorModal_.parent ~= nil then
            visitErrorModal_.parent:RemoveChild(visitErrorModal_)
        end
        visitErrorModal_ = nil
    end
end

local function OpenStealAdConfirmModal()
    CloseFriendDetailModal()
    local root = UI.GetRoot()
    if root == nil then return end
    local system = GetSystem()
    local state = system.GetState and system.GetState() or {}
    local daily = state.daily or {}
    local stealAdCount = math.max(0, math.floor(tonumber(daily.stealAdCount or 0) or 0))
    local stealAdLimit = math.max(5, math.floor(tonumber(daily.stealAdLimit or 5) or 5))
    local canWatchStealAd = stealAdCount < stealAdLimit
    friendDetailModal_ = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        zIndex = 1300,
        backgroundColor = {0, 0, 0, 135},
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            Suppress()
            CloseFriendDetailModal()
        end,
        children = {
            UI.Panel {
                width = 390,
                backgroundColor = COLORS.surfaceRaised,
                borderRadius = 24,
                borderWidth = 4,
                borderColor = COLORS.borderStrong,
                paddingTop = 24,
                paddingLeft = 22,
                paddingRight = 22,
                paddingBottom = 22,
                gap = 16,
                onTap = function(event)
                    if event and event.StopPropagation then event:StopPropagation() end
                    Suppress()
                end,
                children = {
                    UI.Label { text = "增加偷取次数", fontSize = 22, fontWeight = "bold", fontColor = COLORS.text, textAlign = "center" },
                    UI.Label { text = "观看广告后获得 5 次偷取次数。", fontSize = 15, fontColor = COLORS.textMuted, textAlign = "center", whiteSpace = "normal" },
                    UI.Label { text = string.format("今日广告次数：%d/%d", stealAdCount, stealAdLimit), fontSize = 14, fontWeight = "bold", fontColor = COLORS.secondary, textAlign = "center" },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        children = {
                            UI.Button {
                                text = "取消",
                                height = 42,
                                flexGrow = 1,
                                fontSize = 15,
                                fontWeight = "bold",
                                backgroundColor = {245, 238, 220, 255},
                                fontColor = {92, 72, 48, 255},
                                borderRadius = 16,
                                onClick = function(self, event)
                                    if event and event.StopPropagation then event:StopPropagation() end
                                    CloseFriendDetailModal()
                                end,
                            },
                            UI.Button {
                                text = canWatchStealAd and "看广告" or "已达上限",
                                height = 42,
                                flexGrow = 1,
                                fontSize = 15,
                                fontWeight = "bold",
                                disabled = not canWatchStealAd,
                                backgroundColor = canWatchStealAd and {94, 194, 131, 255} or {180, 170, 155, 200},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 16,
                                onClick = function(self, event)
                                    if event and event.StopPropagation then event:StopPropagation() end
                                    if not canWatchStealAd then
                                        if deps_.showToast then deps_.showToast("今日偷取次数广告已达上限") end
                                        return
                                    end
                                    CloseFriendDetailModal()
                                    if deps_.requestStealAttemptsAdReward then
                                        deps_.requestStealAttemptsAdReward()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    root:AddChild(friendDetailModal_)
end

local function OpenFriendDetailModal(entry)
    local system = GetSystem()
    CloseFriendDetailModal()
    local root = UI.GetRoot()
    if root == nil or entry == nil then return end
    local playerName = tostring(entry.nickname or entry.userId or "玩家名字")
    local scoreText = tostring(entry.score or entry.tourValue or 0)
    friendDetailModal_ = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        zIndex = 1200,
        backgroundColor = {0, 0, 0, 120},
        alignItems = "center",
        justifyContent = "center",
        onTap = function()
            Suppress()
            CloseFriendDetailModal()
        end,
        children = {
            UI.Panel {
                width = 440,
                minHeight = 260,
                backgroundColor = COLORS.surfaceRaised,
                borderRadius = 28,
                borderWidth = 4,
                borderColor = COLORS.borderStrong,
                paddingTop = 24,
                paddingLeft = 22,
                paddingRight = 22,
                paddingBottom = 22,
                boxShadow = {
                    { x = 0, y = 7, blur = 0, spread = 0, color = {30, 30, 30, 95} },
                },
                onTap = function(event)
                    if event and event.StopPropagation then event:StopPropagation() end
                    Suppress()
                end,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 18,
                        children = {
                            UI.Panel {
                                width = 92,
                                height = 92,
                                borderRadius = 999,
                                borderWidth = 4,
                                borderColor = {255, 252, 235, 255},
                                backgroundColor = entry.avatar and entry.avatar.color or COLORS.surfaceAlt,
                                alignItems = "center",
                                justifyContent = "center",
                                boxShadow = {
                                    { x = 0, y = 3, blur = 0, spread = 0, color = {125, 92, 45, 80} },
                                },
                                children = {
                                    UI.Panel {
                                        width = 66,
                                        height = 66,
                                        backgroundImage = GetAvatarImagePath(entry.avatar),
                                        backgroundFit = "contain",
                                    },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                gap = 10,
                                children = {
                                    UI.Label { text = playerName, fontSize = 24, fontWeight = "bold", fontColor = {70, 50, 34, 255}, maxLines = 1 },
                                    UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 10,
                                        children = {
                                            BuildTourIcon(34),
                                            UI.Label { text = scoreText, fontSize = 22, fontWeight = "bold", fontColor = {94, 142, 78, 255} },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        height = 62,
                    },
                    UI.Panel {
                        alignItems = "center",
                        children = {
                            UI.Button {
                                text = "删除好友",
                                width = 172,
                                height = 48,
                                fontSize = 17,
                                fontWeight = "bold",
                                backgroundColor = COLORS.secondary,
                                hoverBackgroundColor = {205, 130, 54, 255},
                                pressedBackgroundColor = {176, 105, 42, 255},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 18,
                                onClick = function(self, event)
                                    if event and event.StopPropagation then event:StopPropagation() end
                                    Suppress()
                                    if system.RemoveFriend and system.RemoveFriend(entry.userId) then
                                        CloseFriendDetailModal()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    root:AddChild(friendDetailModal_)
end

local function BuildFriendRow(entry)
    local system = GetSystem()
    local playerName = tostring(entry.nickname or entry.userId or "神秘园丁")
    local scoreText = tostring(entry.score or entry.tourValue or 0)
    local giftSent = system.HasGiftedToday and system.HasGiftedToday(entry.userId) or false
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
        onTap = function(event)
            if event and event.StopPropagation then event:StopPropagation() end
            Suppress()
            OpenFriendDetailModal(entry)
        end,
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
                            BuildTourIcon(20),
                            UI.Label {
                                text = scoreText,
                                fontSize = 12,
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
                onTap = function(event)
                    if event and event.StopPropagation then event:StopPropagation() end
                    Suppress()
                end,
                children = {
                    UI.Button {
                        text = giftSent and "已送" or "送种子",
                        width = 78,
                        height = 44,
                        fontSize = 13,
                        fontWeight = "bold",
                        disabled = giftSent,
                        backgroundColor = giftSent and {170, 160, 145, 200} or COLORS.info,
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            Suppress()
                            if not (system.HasGiftedToday and system.HasGiftedToday(entry.userId)) then
                                if system.SendSeedGift(entry.userId, tonumber(giftSeedInput_) or 1) then
                                    RebuildContent()
                                end
                            end
                        end,
                    },
                    BuildFriendActionButton("拜访", COLORS.primary, function()
                        if system.VisitPlayer(entry.userId) then
                            SocialView.Close()
                        else
                            ShowVisitError(system.GetRequestError and system.GetRequestError("visit") or nil)
                        end
                    end),
                },
            },
        },
    }
end

local function BuildMessageButton()
    local system = GetSystem()
    local requestCount = system.GetFriendRequests and #system.GetFriendRequests() or 0
    local noticeCount = system.GetSocialNotices and #system.GetSocialNotices() or 0
    local count = #system.GetGifts() + #system.GetRecentVisitors() + #system.GetStealLogs() + requestCount + noticeCount
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
    local stealLimit = math.max(5, math.floor(tonumber(daily.stealLimit or 5) or 5))
    local stealLeft = math.max(0, stealLimit - (tonumber(daily.stealCount or 0) or 0))
    local stealAdCount = math.max(0, math.floor(tonumber(daily.stealAdCount or 0) or 0))
    local stealAdLimit = math.max(5, math.floor(tonumber(daily.stealAdLimit or 5) or 5))
    local canWatchStealAd = stealAdCount < stealAdLimit
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
                                backgroundColor = canWatchStealAd and {255, 255, 255, 245} or {190, 180, 165, 180},
                                fontColor = COLORS.text,
                                borderRadius = 12,
                                borderWidth = 1,
                                borderColor = COLORS.border,
                                onClick = function()
                                    Suppress()
                                    if not canWatchStealAd then
                                        if deps_.showToast then deps_.showToast("今日偷取次数广告已达上限") end
                                        return
                                    end
                                    OpenStealAdConfirmModal()
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
    local system = GetSystem()
    return system.SendFriendRequest(userId)
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
                            if system.VisitByInput(searchUserInput_) then
                                SocialView.Close()
                            else
                                ShowVisitError(system.GetRequestError and system.GetRequestError("visit") or nil)
                            end
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

local function BuildNetworkErrorPanel(message, buttonText, onRetry)
    return UI.Panel {
        height = 160,
        alignItems = "center",
        justifyContent = "center",
        gap = 12,
        backgroundColor = COLORS.surfaceRaised,
        borderRadius = 20,
        borderWidth = 3,
        borderColor = COLORS.border,
        paddingLeft = 20,
        paddingRight = 20,
        children = {
            UI.Label {
                text = message,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = COLORS.textMuted,
                textAlign = "center",
                whiteSpace = "normal",
            },
            UI.Button {
                text = buttonText or "重试",
                width = 120,
                height = 40,
                fontSize = 14,
                fontWeight = "bold",
                backgroundColor = COLORS.primary,
                fontColor = {255, 255, 255, 255},
                borderRadius = 16,
                onClick = function()
                    Suppress()
                    if onRetry then onRetry() end
                    RebuildContent()
                end,
            },
        },
    }
end

local function BuildFriendsSection()
    local system = GetSystem()
    local friends = system.GetFriends()
    local rows = {}
    local waitingFirstSync = system.IsSocialStateLoading
        and system.IsSocialStateLoading()
        and system.HasSocialStateSynced
        and not system.HasSocialStateSynced()
    local socialError = system.GetRequestError and system.GetRequestError("socialState") or nil

    if socialError ~= nil and socialError ~= "" then
        table.insert(rows, BuildNetworkErrorPanel(socialError, "重试同步", function()
            system.RequestSocialState({ force = true, reason = "ui_retry", interactive = true })
            system.RequestGifts()
        end))
    elseif waitingFirstSync then
        table.insert(rows, UI.Panel {
            height = 160,
            alignItems = "center",
            justifyContent = "center",
            backgroundColor = COLORS.surfaceRaised,
            borderRadius = 20,
            borderWidth = 3,
            borderColor = COLORS.border,
            children = {
                UI.Label { text = "正在同步好友资料...", fontSize = 15, fontWeight = "bold", fontColor = COLORS.text },
            },
        })
    else
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

local function BuildSocialNoticeText(notice)
    if notice.type == "friend_request_sent" then
        local name = tostring(notice.targetNickname or notice.targetUserId or "玩家")
        return "已向 " .. name .. " 发送好友申请"
    end
    local name = tostring(notice.fromNickname or notice.fromUserId or "玩家")
    if notice.type == "friend_request_accepted" then
        return name .. " 已同意你的好友申请"
    elseif notice.type == "friend_request_rejected" then
        return name .. " 已拒绝你的好友申请"
    end
    return name .. " 有一条新消息"
end

local function GetGiftDescription(gift)
    if type(gift) ~= "table" then return "种子礼物" end
    local reward = gift.reward
    if type(reward) == "table" and reward.description ~= nil and reward.description ~= "" then
        return tostring(reward.description)
    end
    if type(reward) == "table" and reward.name ~= nil and reward.name ~= "" then
        return tostring(reward.name) .. " x" .. tostring(reward.count or gift.count or 1)
    end
    if gift.seedId ~= nil then
        return "种子" .. tostring(gift.seedId) .. " x" .. tostring(gift.count or 1)
    end
    return "种子礼物"
end

local function BuildMessagesSection()
    local system = GetSystem()
    local rows = {}
    local friends = system.GetFriends()
    local friendCount = #friends
    local messageError = nil
    if system.GetRequestError ~= nil then
        messageError = system.GetRequestError("gifts") or system.GetRequestError("socialState")
    end

    if messageError ~= nil and messageError ~= "" then
        rows[#rows + 1] = BuildNetworkErrorPanel(messageError, "重试", function()
            system.RequestSocialState({ force = true, reason = "ui_retry_messages", interactive = true })
            system.RequestGifts()
        end)
    else
        if system.GetFriendRequests ~= nil then
            for _, request in ipairs(system.GetFriendRequests()) do
                rows[#rows + 1] = BuildMessageRow(
                    tostring(request.fromNickname or request.fromUserId or "玩家") .. " 请求添加你为好友",
                    {
                        BuildMessageActionButton("同意", COLORS.primary, function()
                            system.RespondFriendRequest(request, true)
                        end),
                        BuildMessageActionButton("拒绝", COLORS.secondary, function()
                            system.RespondFriendRequest(request, false)
                        end),
                    }
                )
            end
        end

        if system.GetSocialNotices ~= nil then
            for _, notice in ipairs(system.GetSocialNotices()) do
                rows[#rows + 1] = BuildMessageRow(BuildSocialNoticeText(notice))
            end
        end

        for _, visitor in ipairs(system.GetRecentVisitors()) do
            rows[#rows + 1] = BuildMessageRow(
                tostring(visitor.nickname or visitor.userId or "玩家") .. "拜访了你的花园",
                {
                    BuildMessageActionButton("回访", COLORS.primary, function()
                        if system.VisitPlayer(visitor.userId) then
                            SocialView.Close()
                        else
                            ShowVisitError(system.GetRequestError and system.GetRequestError("visit") or nil)
                        end
                    end),
                }
            )
        end

        for _, log in ipairs(system.GetStealLogs()) do
            rows[#rows + 1] = BuildMessageRow(string.format("%s从你的花园里偷走了%s的种子", tostring(log.thiefNickname or log.thiefUserId or "玩家"), tostring(log.cropName or "作物")))
        end

        for _, gift in ipairs(system.GetGifts()) do
            local fromName = tostring(gift.fromNickname or gift.fromUserId or "好友")
            rows[#rows + 1] = BuildMessageRow(string.format("%s给你送来了%s", fromName, GetGiftDescription(gift)), {
                BuildMessageActionButton("领取", COLORS.info, function()
                    system.ClaimGift(gift)
                end),
            })
        end
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
                        text = "清除消息",
                        width = 96,
                        height = 42,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = COLORS.secondary,
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 22,
                        onClick = function()
                            Suppress()
                            if system.ClearSocialMessages then system.ClearSocialMessages() end
                        end,
                    },
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
                        if system.VisitPlayer(visitor.userId) then
                            SocialView.Close()
                        else
                            ShowVisitError(system.GetRequestError and system.GetRequestError("visit") or nil)
                        end
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
                UI.Label { text = string.format("来自 %s 的%s", tostring(gift.fromNickname or gift.fromUserId or "好友"), GetGiftDescription(gift)), flexGrow = 1, fontSize = 12, fontColor = {70, 55, 38, 255} },
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
        system.RequestSocialState()
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
