-- ============================================================================
-- 社交花园 UI
-- ============================================================================
-- 好友、排行榜、拜访花园、偷菜、互送种子、设置可参观地块。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")

local SocialView = {}

local deps_ = {}
local modal_ = nil
local visitInput_ = ""
local giftTargetInput_ = ""
local giftSeedInput_ = "1"

function SocialView.Init(deps)
    deps_ = deps or {}
end

function SocialView.IsOpen()
    return modal_ ~= nil
end

local function GetSystem()
    return deps_.SocialGardenSystem
end

local function Suppress()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
end

local function RebuildContent()
    if modal_ == nil then return end
    modal_:ClearContent()
    modal_:AddContent(SocialView.BuildContent())
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

local function BuildRowButton(text, color, onClick)
    return UI.Button {
        text = text,
        height = 38,
        flexGrow = 1,
        fontSize = 13,
        fontWeight = "bold",
        backgroundColor = color or {78, 172, 110, 255},
        fontColor = {255, 255, 255, 255},
        borderRadius = 14,
        onClick = function()
            Suppress()
            onClick()
            RebuildContent()
        end,
    }
end

local function BuildVisitPlotSection()
    local system = GetSystem()
    local selectedPlot = deps_.getSelectedPlotIndex and deps_.getSelectedPlotIndex() or 1
    local visitablePlot = system.GetVisitablePlotIndex()
    return UI.Panel {
        gap = 8,
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 16,
        children = {
            BuildSectionTitle("我的可参观地块"),
            BuildSmallNote(string.format("当前开放第 %d 块地。好友拜访时只会看到这一块。", visitablePlot)),
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    BuildRowButton("把当前地块设为可参观", {78, 172, 110, 255}, function()
                        system.SetVisitablePlotIndex(selectedPlot)
                    end),
                    BuildRowButton("同步花园", {80, 135, 185, 255}, function()
                        system.UploadSnapshot()
                    end),
                },
            },
        },
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
                    if modal_ ~= nil then modal_:Close(); modal_ = nil end
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

local function BuildFriendRow(entry)
    local system = GetSystem()
    local sourceText = entry.source == "recent_visitor" and "来访" or entry.source == "recent_visit" and "最近" or entry.source == "rank" and "排行" or "推荐"
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Label { text = string.format("[%s] %s", sourceText, entry.nickname or tostring(entry.userId)), flexGrow = 1, flexShrink = 1, fontSize = 13, fontColor = {70, 55, 38, 255} },
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
                    if modal_ ~= nil then modal_:Close(); modal_ = nil end
                    system.VisitPlayer(entry.userId)
                end,
            },
            UI.Button {
                text = "送种",
                width = 58,
                height = 32,
                fontSize = 12,
                backgroundColor = {224, 154, 70, 255},
                fontColor = {255, 255, 255, 255},
                borderRadius = 12,
                onClick = function()
                    Suppress()
                    system.SendSeedGift(entry.userId, tonumber(giftSeedInput_) or 1)
                end,
            },
        },
    }
end

local function BuildFriendsSection()
    local system = GetSystem()
    local rows = {}
    for _, entry in ipairs(system.GetFriends()) do
        table.insert(rows, BuildFriendRow(entry))
    end
    if #rows == 0 then table.insert(rows, BuildSmallNote("暂无好友数据。可以输入玩家 ID 直接拜访。")) end
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
                    UI.Label { text = "真实好友 / 推荐玩家", flexGrow = 1, fontSize = 16, fontWeight = "bold", fontColor = {74, 55, 38, 255} },
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
                            system.RequestSocialState()
                            RebuildContent()
                        end,
                    },
                },
            },
            UI.Panel { gap = 6, children = rows },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    UI.TextField {
                        value = visitInput_,
                        placeholder = "输入玩家ID拜访",
                        height = 40,
                        flexGrow = 1,
                        fontSize = 13,
                        borderRadius = 14,
                        onChange = function(_, value) visitInput_ = value or "" end,
                    },
                    UI.Button {
                        text = "拜访",
                        width = 68,
                        height = 40,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = {78, 172, 110, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 14,
                        onClick = function()
                            Suppress()
                            if modal_ ~= nil then modal_:Close(); modal_ = nil end
                            system.VisitByInput(visitInput_)
                        end,
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    UI.TextField {
                        value = giftTargetInput_,
                        placeholder = "好友ID",
                        height = 40,
                        flexGrow = 1,
                        fontSize = 13,
                        borderRadius = 14,
                        onChange = function(_, value) giftTargetInput_ = value or "" end,
                    },
                    UI.TextField {
                        value = giftSeedInput_,
                        placeholder = "种子ID",
                        height = 40,
                        width = 82,
                        fontSize = 13,
                        borderRadius = 14,
                        onChange = function(_, value) giftSeedInput_ = value or "1" end,
                    },
                    UI.Button {
                        text = "赠送",
                        width = 68,
                        height = 40,
                        fontSize = 13,
                        fontWeight = "bold",
                        backgroundColor = {224, 154, 70, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 14,
                        onClick = function()
                            Suppress()
                            system.SendSeedGift(giftTargetInput_, tonumber(giftSeedInput_) or 1)
                            RebuildContent()
                        end,
                    },
                },
            },
            BuildSmallNote(system.GetDailyText()),
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
                        if modal_ ~= nil then modal_:Close(); modal_ = nil end
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
                            if modal_ ~= nil then modal_:Close(); modal_ = nil end
                        end,
                    },
                },
            },
        },
    }
end

function SocialView.BuildContent()
    return UI.ScrollView {
        height = 550,
        scrollY = true,
        showScrollbar = false,
        children = {
            UI.Panel {
                gap = 12,
                children = {
                    BuildVisitPlotSection(),
                    BuildLeaderboardSection(),
                    BuildFriendsSection(),
                    BuildSocialLogSection(),
                    BuildGiftSection(),
                },
            },
        },
    }
end

function SocialView.Open()
    Suppress()
    local system = GetSystem()
    system.RequestLeaderboard()
    system.RequestGifts()
    if modal_ ~= nil then modal_:Close() end
    modal_ = UI.Modal {
        title = "好友花园",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 18, 16},
        onClose = function()
            modal_ = nil
        end,
    }
    modal_:AddContent(SocialView.BuildContent())
    ModalAnim.Apply(modal_, { fixedHeight = 640 })
    modal_:Open()
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
