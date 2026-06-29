-- ============================================================================
-- 主界面 UI 视图 (Main View)
-- Grow A Garden
-- ============================================================================
-- 负责根 UI、顶部 HUD、Toast、底部主操作区、种植模式外壳与收起按钮。
-- 具体内容区和弹窗由子视图传入。
-- ============================================================================

local UI = require("urhox-libs/UI")
local SettingsView = require("ui.settings_view")
local FloatingToast = require("ui.floating_toast")
local ProfileView = require("ui.profile_view")
local SocialView = require("ui.social_view")
local ActivityView = require("ui.activity_view")
local LeaderboardView = require("ui.leaderboard_view")
local ModelPreviewView = require("ui.model_preview_view")
local ModalAnim = require("ui.modal_anim")

local visitablePlotModal_ = nil

local MainView = {}

local deps_ = {}

function MainView.Init(deps)
    deps_ = deps or {}
end

function MainView.CreateLabels()
    local labels = {}
    labels.moneyLabel = UI.Label {
        text = "0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    labels.seedLabel = UI.Label {
        text = "0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    labels.seedPackBadgeLabel = UI.Label {
        text = "0",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
        textAlign = "center",
    }
    labels.seedPackIcon = nil
    labels.plotLabel = UI.Label {
        text = "LV1",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
    }

    labels.actionLabel = UI.Label {
        text = "点击田地播种或收获",
        fontSize = 12,
        fontColor = {255, 250, 235, 220},
    }
    labels.inventoryLabel = UI.Label {
        text = "背包 --",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = {255, 210, 50, 255},
    }
    labels.toastLabel = UI.Label {
        text = "当前为查看状态，点击下方开始种植",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = {38, 90, 45, 255},
        textAlign = "center",
    }
    labels.helpLabel = UI.Label {
        text = "已解锁区域 1/9",
        fontSize = 14,
        fontColor = {80, 80, 80, 255},
        textAlign = "center",
    }
    return labels
end

local function BuildActionButton()
    return UI.Button {
        text = "开始种植",
        variant = "primary",
        height = 90,
        width = 228,
        fontSize = 26,
        fontWeight = "bold",
        borderRadius = 28,
        onClick = function()
            deps_.suppressWorldTap()
            if deps_.isVisitMode and deps_.isVisitMode() then
                if deps_.returnHome then deps_.returnHome() end
            elseif deps_.isFarmView() then
                deps_.enterPlantView()
            else
                deps_.enterFarmView()
            end
        end,
    }
end

local function BuildRoundIcon(text, outerColor, innerColor, textColor, size)
    size = size or 22
    local inner = math.max(10, math.floor(size * 0.64))
    return UI.Panel {
        width = size,
        height = size,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel { width = size, height = size, borderRadius = math.floor(size / 2), backgroundColor = outerColor },
            UI.Panel { position = "absolute", width = inner, height = inner, borderRadius = math.floor(inner / 2), backgroundColor = innerColor },
            UI.Label { position = "absolute", text = text, fontSize = math.max(10, math.floor(size * 0.5)), fontWeight = "bold", fontColor = textColor },
        },
    }
end

local function BuildTourIcon(size)
    return BuildRoundIcon("★", {190, 160, 230, 255}, {155, 120, 210, 255}, {245, 240, 255, 255}, size)
end

local function BuildLikeIcon(size)
    return BuildRoundIcon("♥", {245, 150, 150, 255}, {220, 92, 92, 255}, {255, 240, 240, 255}, size)
end

local function BuildVisitTopHud()
    return UI.Panel {
        position = "absolute",
        top = 50,
        left = 16,
        right = 16,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        gap = 8,
        pointerEvents = "none",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                paddingTop = 7, paddingBottom = 7,
                paddingLeft = 10, paddingRight = 14,
                backgroundColor = {255, 250, 240, 240},
                borderRadius = 14,
                children = {
                    BuildTourIcon(22),
                    UI.Label { text = tostring(deps_.getVisitTourValue and deps_.getVisitTourValue() or 0), fontSize = 15, fontWeight = "bold", fontColor = {95, 75, 55, 255} },
                },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                paddingTop = 7, paddingBottom = 7,
                paddingLeft = 10, paddingRight = 14,
                backgroundColor = {255, 250, 240, 240},
                borderRadius = 14,
                children = {
                    BuildLikeIcon(22),
                    UI.Label { text = tostring(deps_.getVisitLikeCount and deps_.getVisitLikeCount() or 0), fontSize = 15, fontWeight = "bold", fontColor = {95, 75, 55, 255} },
                },
            },
        },
    }
end

local function BuildTopHud(labels)
    return UI.Panel {
        position = "absolute",
        top = 50,
        left = 12,
        right = 12,
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 8,
        pointerEvents = "box-none",
        children = {
            (deps_.isFarmView() and (not deps_.isVisitMode or not deps_.isVisitMode())) and ProfileView.BuildHudAvatar() or UI.Panel { width = 0, height = 0 },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                paddingTop = 7, paddingBottom = 7,
                paddingLeft = 10, paddingRight = 14,
                backgroundColor = {255, 250, 240, 240},
                borderRadius = 14,
                children = {
                    BuildTourIcon(22),
                    labels.seedLabel,
                },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                paddingTop = 7, paddingBottom = 7,
                paddingLeft = 10, paddingRight = 14,
                backgroundColor = {255, 250, 240, 240},
                borderRadius = 14,
                children = {
                    UI.Panel {
                        width = 22, height = 22,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {255, 205, 60, 255} },
                            UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {230, 175, 30, 255} },
                            UI.Label { position = "absolute", text = "$", fontSize = 11, fontWeight = "bold", fontColor = {255, 245, 200, 255} },
                        },
                    },
                    labels.moneyLabel,
                },
            },
        },
    }
end

local function BuildToast(labels)
    return UI.Panel {
        position = "absolute",
        top = 180,
        left = 28,
        right = 28,
        zIndex = 999,
        alignItems = "center",
        pointerEvents = "none",
        children = {
            UI.Panel {
                paddingTop = 12,
                paddingBottom = 12,
                paddingLeft = 20,
                paddingRight = 20,
                backgroundColor = {228, 243, 230, 242},
                borderColor = {70, 170, 100, 210},
                borderWidth = 3,
                borderRadius = 16,
                children = { labels.toastLabel },
            },
        },
    }
end

local function BuildFarmControls(labels, actionButton)
    return UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = 60,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "flex-end",
        gap = 16,
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = 90,
                height = 190,
                alignItems = "center",
                justifyContent = "flex-end",
                children = {
                    UI.Button {
                        text = "委托",
                        width = 90,
                        height = 90,
                        marginBottom = 14,
                        fontSize = 22,
                        fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 245},
                        fontColor = {195, 125, 45, 255},
                        borderRadius = 28,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if deps_.openCommission then
                                deps_.openCommission()
                            end
                        end,
                    },
                    UI.Button {
                        text = "商店",
                        width = 90,
                        height = 90,
                        fontSize = 22,
                        fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 245},
                        fontColor = {78, 155, 100, 255},
                        borderRadius = 28,
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.openShop()
                        end,
                    },
                },
            },
            actionButton,
            UI.Panel {
                width = 90,
                height = 190,
                alignItems = "center",
                justifyContent = "flex-end",
                children = {
                    (function()
                        local icon = UI.Panel {
                            width = 71,
                            height = 82,
                            marginBottom = 14,
                            backgroundImage = deps_.getHighestPackIcon(),
                            backgroundFit = "contain",
                            onClick = function()
                                deps_.suppressWorldTap()
                                deps_.openSeedPackHub()
                            end,
                        }
                        labels.seedPackIcon = icon
                        return UI.Panel {
                            alignItems = "center",
                            overflow = "visible",
                            children = {
                                icon,
                                UI.Panel {
                                    position = "absolute",
                                    top = -4,
                                    right = -2,
                                    minWidth = 22,
                                    height = 22,
                                    paddingLeft = 5,
                                    paddingRight = 5,
                                    borderRadius = 11,
                                    backgroundColor = {225, 55, 45, 255},
                                    borderWidth = 2,
                                    borderColor = {255, 255, 255, 255},
                                    justifyContent = "center",
                                    alignItems = "center",
                                    children = { labels.seedPackBadgeLabel },
                                },
                            },
                        }
                    end)(),
                    UI.Button {
                        text = "任务",
                        width = 90,
                        height = 90,
                        fontSize = 22,
                        fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 245},
                        fontColor = {78, 155, 100, 255},
                        borderRadius = 28,
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.openTaskPanel()
                        end,
                    },
                },
            },
        },
    }
end

local function BuildVisitControls()
    local stealing = deps_.isStealingMode and deps_.isStealingMode()
    local liked = deps_.hasLikedVisitGarden and deps_.hasLikedVisitGarden()
    local garden = deps_.getVisitGarden and deps_.getVisitGarden() or {}
    local canAddFriend = garden.userId ~= nil and deps_.sendFriendRequestToVisitGarden ~= nil
    return UI.Panel {
        position = "absolute",
        left = 16, right = 16, bottom = 60,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "flex-end",
        pointerEvents = "box-none",
        children = {
            UI.Button {
                text = "返回",
                width = 80,
                height = 64,
                fontSize = 20,
                fontWeight = "bold",
                backgroundColor = {78, 172, 110, 255},
                fontColor = {92, 62, 62, 255},
                borderRadius = 20,
                onClick = function()
                    deps_.suppressWorldTap()
                    if deps_.returnHome then deps_.returnHome() end
                end,
            },
            UI.Panel {
                flexDirection = "row",
                gap = 10,
                marginRight = 18,
                children = {
                    UI.Button {
                        text = "加好友",
                        width = 116,
                        height = 64,
                        fontSize = 20,
                        fontWeight = "bold",
                        disabled = not canAddFriend,
                        backgroundColor = canAddFriend and {80, 135, 185, 255} or {190, 170, 150, 255},
                        fontColor = {92, 62, 62, 255},
                        borderRadius = 20,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if canAddFriend then deps_.sendFriendRequestToVisitGarden() end
                        end,
                    },
                    UI.Button {
                        text = stealing and "退出" or "偷取",
                        width = 116,
                        height = 64,
                        fontSize = 20,
                        fontWeight = "bold",
                        backgroundColor = stealing and {150, 120, 90, 255} or {224, 154, 70, 255},
                        fontColor = {92, 62, 62, 255},
                        borderRadius = 20,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if stealing then
                                if deps_.endStealingMode then deps_.endStealingMode() end
                            else
                                if deps_.beginStealingMode then deps_.beginStealingMode() end
                            end
                        end,
                    },
                    UI.Button {
                        text = liked and "已赞" or "点赞",
                        width = 116,
                        height = 64,
                        fontSize = 20,
                        fontWeight = "bold",
                        backgroundColor = liked and {190, 170, 150, 255} or {238, 105, 105, 255},
                        fontColor = {92, 62, 62, 255},
                        borderRadius = 20,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if deps_.likeVisitGarden then deps_.likeVisitGarden() end
                        end,
                    },
                },
            },
        },
    }
end

local function BuildVisitStealList()
    if not (deps_.isVisitMode and deps_.isVisitMode()) or not (deps_.isStealingMode and deps_.isStealingMode()) then
        return UI.Panel { width = 0, height = 0 }
    end
    ---@type table
    local rows = {}
    local crops = deps_.getMatureVisitCrops and deps_.getMatureVisitCrops() or {}
    for _, item in ipairs(crops) do
        local crop = item.crop
        local stolen = crop.stolen == true
        rows[#rows + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            paddingTop = 6,
            paddingBottom = 6,
            borderBottomWidth = 1,
            borderColor = {220, 205, 175, 150},
            children = {
                UI.Label {
                    text = string.format("%s · 种子率%s%s", crop.name or "作物", deps_.getStealChanceText and deps_.getStealChanceText(crop) or "--", stolen and " · 已偷" or ""),
                    flexGrow = 1,
                    flexShrink = 1,
                    fontSize = 13,
                    fontColor = stolen and {150, 120, 95, 210} or {70, 55, 38, 255},
                },
                UI.Button {
                    text = stolen and "已偷" or "偷",
                    width = 58,
                    height = 34,
                    fontSize = 13,
                    fontWeight = "bold",
                    backgroundColor = stolen and {190, 180, 165, 180} or {224, 154, 70, 255},
                    fontColor = {255, 255, 255, 255},
                    borderRadius = 13,
                    onClick = function()
                        deps_.suppressWorldTap()
                        if not stolen and deps_.stealVisitCrop then
                            deps_.stealVisitCrop(item.index, crop.cropId)
                        end
                    end,
                },
            },
        }
    end
    if #rows == 0 then
        rows[1] = UI.Panel {
            paddingTop = 12,
            paddingBottom = 12,
            children = {
                UI.Label { text = "暂无成熟作物可偷", fontSize = 14, fontColor = {120, 96, 68, 220}, textAlign = "center" },
            },
        }
    end
    return UI.Panel {
        position = "absolute",
        left = 14,
        right = 14,
        bottom = 144,
        maxHeight = 210,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 14,
        paddingRight = 14,
        backgroundColor = {255, 250, 240, 246},
        borderRadius = 18,
        borderWidth = 2,
        borderColor = {224, 154, 70, 190},
        children = {
            UI.Label { text = "成熟作物", fontSize = 15, fontWeight = "bold", fontColor = {74, 55, 38, 255}, marginBottom = 6 },
            UI.ScrollView {
                height = 150,
                scrollY = true,
                showScrollbar = false,
                children = {
                    UI.Panel { gap = 2, children = rows },
                },
            },
        },
    }
end

local function BuildPlantShell(plantContent)
    local plantTab = deps_.getPlantTab()
    return UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = 0,
        pointerEvents = "auto",
        paddingTop = 12, paddingBottom = plantTab == "harvest" and 16 or 125,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = {250, 245, 235, 252},
        borderRadius = {22, 22, 0, 0},
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                marginBottom = 10,
                children = {
                    UI.Button {
                        text = "播种", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                        backgroundColor = plantTab == "seed" and {94, 194, 131, 255} or {195, 230, 205, 255},
                        fontColor = plantTab == "seed" and {255, 255, 255, 255} or {70, 130, 85, 255},
                        borderRadius = 12,
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.clearSelectedBagItem()
                            deps_.clearBagPreview()
                            deps_.setPlantTab("seed")
                            deps_.rebuildUI()
                        end,
                    },
                    UI.Button {
                        text = "收获", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                        backgroundColor = plantTab == "harvest" and {94, 194, 131, 255} or {195, 230, 205, 255},
                        fontColor = plantTab == "harvest" and {255, 255, 255, 255} or {70, 130, 85, 255},
                        borderRadius = 12,
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.clearSelectedBagItem()
                            deps_.clearBagPreview()
                            deps_.setPlantTab("harvest")
                            deps_.rebuildUI()
                        end,
                    },
                    UI.Button {
                        text = "背包", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                        backgroundColor = plantTab == "bag" and {94, 194, 131, 255} or {195, 230, 205, 255},
                        fontColor = plantTab == "bag" and {255, 255, 255, 255} or {70, 130, 85, 255},
                        borderRadius = 12,
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.setPlantTab("bag")
                            deps_.rebuildUI()
                        end,
                    },
                },
            },
            UI.Panel {
                id = "plantContentHost",
                width = "100%",
                children = { plantContent },
            },
        },
    }
end

local function ApplyVisitablePlot(plotIndex)
    if deps_.setVisitablePlotIndex == nil then return false end
    local ok = deps_.setVisitablePlotIndex(plotIndex)
    if ok and deps_.rebuildUI ~= nil then deps_.rebuildUI() end
    return ok
end

local function CloseVisitablePlotModal()
    if visitablePlotModal_ ~= nil then
        visitablePlotModal_:Close()
        visitablePlotModal_ = nil
    end
end

local function OpenVisitablePlotConfirm(currentIndex, targetIndex)
    CloseVisitablePlotModal()
    visitablePlotModal_ = UI.Modal {
        title = "设置可观光地块",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {16, 20, 18, 20},
        contentGap = 14,
        onClose = function()
            visitablePlotModal_ = nil
        end,
    }

    visitablePlotModal_:AddContent(UI.Panel {
        gap = 16,
        children = {
            UI.Label {
                text = string.format("当前可观光地块为第 %d 块，确认改为第 %d 块吗？", currentIndex, targetIndex),
                fontSize = 14,
                fontColor = {92, 70, 48, 255},
                textAlign = "center",
                whiteSpace = "normal",
            },
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
                        onClick = function()
                            CloseVisitablePlotModal()
                        end,
                    },
                    UI.Button {
                        text = "确认设置",
                        height = 42,
                        flexGrow = 1,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = {94, 194, 131, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            CloseVisitablePlotModal()
                            ApplyVisitablePlot(targetIndex)
                        end,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(visitablePlotModal_, { fixedHeight = 218 })
    visitablePlotModal_:Open()
end

local function BuildVisitablePlotButton()
    local isPlant = deps_.isPlantView and deps_.isPlantView() or false
    if (deps_.isVisitMode and deps_.isVisitMode()) or not isPlant then
        return UI.Panel { width = 0, height = 0 }
    end
    if deps_.getVisitablePlotIndex == nil or deps_.setVisitablePlotIndex == nil or deps_.getSelectedPlotIndex == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    if deps_.getUnlockedPlotCount ~= nil and deps_.getUnlockedPlotCount() <= 1 then
        return UI.Panel { width = 0, height = 0 }
    end

    local selectedPlotIndex = deps_.getSelectedPlotIndex()
    local currentIndex = deps_.getVisitablePlotIndex() or 1
    local bottom = deps_.getPlantTab() == "bag" and 520 or 410
    if selectedPlotIndex == currentIndex then
        return UI.Panel {
            position = "absolute",
            bottom = bottom,
            left = 16,
            pointerEvents = "auto",
            children = {
                UI.Panel {
                    width = 132,
                    height = 34,
                    justifyContent = "center",
                    alignItems = "center",
                    backgroundColor = {230, 248, 235, 245},
                    borderRadius = 16,
                    borderWidth = 2,
                    borderColor = {94, 194, 131, 230},
                    children = {
                        UI.Label {
                            text = "当前可观光",
                            fontSize = 12,
                            fontWeight = "bold",
                            fontColor = {52, 135, 76, 255},
                            textAlign = "center",
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        position = "absolute",
        bottom = bottom,
        left = 16,
        pointerEvents = "auto",
        children = {
            UI.Button {
                text = "设为可观光地块",
                width = 132,
                height = 34,
                fontSize = 12,
                fontWeight = "bold",
                backgroundColor = {255, 238, 190, 255},
                fontColor = {115, 82, 45, 255},
                borderRadius = 16,
                borderWidth = 2,
                borderColor = {220, 175, 90, 230},
                onClick = function()
                    deps_.suppressWorldTap()
                    OpenVisitablePlotConfirm(currentIndex, selectedPlotIndex)
                end,
            },
        },
    }
end

local function BuildCollapseButton()
    local isPlant = deps_.isPlantView and deps_.isPlantView() or false
    if (deps_.isVisitMode and deps_.isVisitMode()) or not isPlant then
        return UI.Panel { width = 0, height = 0 }
    end
    return UI.Panel {
        position = "absolute",
        bottom = deps_.getPlantTab() == "bag" and 520 or 410,
        right = 12,
        pointerEvents = "auto",
        children = {
            UI.Button {
                text = "▼ 收起", width = 90, height = 34, fontSize = 12, fontWeight = "bold",
                backgroundColor = {255, 250, 240, 240}, fontColor = {120, 100, 75, 255},
                borderRadius = 16, borderWidth = 2, borderColor = {185, 165, 130, 220},
                onClick = function()
                    deps_.suppressWorldTap()
                    deps_.enterFarmView()
                end,
            },
        },
    }
end

local function BuildTalentButton(labels)
    labels.talentBadge = UI.Panel {
        position = "absolute",
        top = 18,
        right = -4,
        minWidth = 18,
        height = 18,
        paddingLeft = 4,
        paddingRight = 4,
        borderRadius = 9,
        backgroundColor = {225, 55, 45, 255},
        borderWidth = 2,
        borderColor = {255, 255, 255, 255},
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        display = "none",
        children = {
            UI.Label { text = "!", fontSize = 10, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
        },
    }

    return UI.Panel {
        position = "absolute",
        top = 152,
        left = 12,
        overflow = "visible",
        gap = 8,
        children = {
            UI.Button {
                text = "天赋",
                width = 69,
                height = 66,
                paddingTop = 0,
                paddingRight = 16,
                paddingBottom = 5,
                paddingLeft = 16,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 250, 240, 245},
                fontColor = {78, 155, 100, 255},
                borderRadius = 14,
                onClick = function()
                    if deps_.onTalentOpen then
                        deps_.onTalentOpen()
                    end
                end,
            },
            (not deps_.isExpansionMaxed or not deps_.isExpansionMaxed()) and UI.Button {
                text = "扩展",
                width = 69,
                height = 66,
                paddingTop = 0,
                paddingRight = 16,
                paddingBottom = 5,
                paddingLeft = 16,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 250, 240, 245},
                fontColor = {80, 135, 185, 255},
                borderRadius = 14,
                onClick = function()
                    if deps_.onExpansionOpen then
                        deps_.onExpansionOpen()
                    end
                end,
            } or nil,
            SocialView.BuildButton(),
            LeaderboardView.BuildButton(),
            UI.Button {
                text = "图鉴",
                width = 69,
                height = 66,
                paddingTop = 0,
                paddingRight = 16,
                paddingBottom = 5,
                paddingLeft = 16,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 250, 240, 245},
                fontColor = {160, 112, 62, 255},
                borderRadius = 14,
                onClick = function()
                    if deps_.onCodexOpen then
                        deps_.onCodexOpen()
                    end
                end,
            },
            labels.talentBadge,
        },
    }
end

local function BuildActivityTopEntry()
    if not deps_.isFarmView or not deps_.isFarmView() then
        return UI.Panel { width = 0, height = 0 }
    end
    if deps_.isVisitMode and deps_.isVisitMode() then
        return UI.Panel { width = 0, height = 0 }
    end

    return UI.Panel {
        position = "absolute",
        top = 152,
        left = 0,
        right = 0,
        height = 66,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            ActivityView.BuildButton({ width = 300, height = 66 }),
        },
    }
end

local function BuildGuideBubble(text, subText, style)
    style = style or {}
    return UI.Panel {
        position = "absolute",
        top = style.top,
        bottom = style.bottom,
        left = style.left or 18,
        right = style.right or 18,
        zIndex = 950,
        pointerEvents = "none",
        alignItems = "center",
        children = {
            UI.Panel {
                width = style.width or 315,
                maxWidth = style.maxWidth or 330,
                minHeight = style.minHeight,
                paddingTop = style.paddingTop or 14,
                paddingBottom = style.paddingBottom or 14,
                paddingLeft = style.paddingLeft or 18,
                paddingRight = style.paddingRight or 18,
                backgroundColor = {255, 252, 240, 248},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {255, 202, 82, 245},
                boxShadow = { { x = 0, y = 6, blur = 18, spread = 0, color = {65, 46, 28, 70} } },
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = text,
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = {86, 57, 31, 255},
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = subText,
                        fontSize = 13,
                        fontColor = {116, 92, 58, 235},
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                },
            },
        },
    }
end

local function BuildPlantGuideOverlay()
    if deps_.getPlantGuideStep == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    local step = deps_.getPlantGuideStep()
    if step == "done" then
        return UI.Panel { width = 0, height = 0 }
    end

    if step == "start" then
        return UI.Panel {
            position = "absolute",
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
            zIndex = 940,
            pointerEvents = "none",
            children = {
                BuildGuideBubble("第一步：点击开始种植", "进入种植模式后，就能把种子播到土地上。", { bottom = 178 }),
                UI.Panel {
                    position = "absolute",
                    left = 0,
                    right = 0,
                    bottom = 48,
                    alignItems = "center",
                    pointerEvents = "none",
                    children = {
                        UI.Panel {
                            width = 250,
                            height = 114,
                            borderRadius = 34,
                            borderWidth = 5,
                            borderColor = {255, 215, 86, 245},
                            backgroundColor = {255, 215, 86, 28},
                        },
                    },
                },
            },
        }
    end

    if step == "seed_tab" then
        return UI.Panel {
            position = "absolute",
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
            zIndex = 940,
            pointerEvents = "none",
            children = {
                BuildGuideBubble("切回播种页签", "选择“播种”后，点击土地空位即可种下种子。", { bottom = 370 }),
            },
        }
    end

    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 940,
        pointerEvents = "none",
        children = {
            BuildGuideBubble("第二步：点击土地播种", "把种子点到土地空位上，播种后等待成熟即可收获。", { top = 205, width = 360, maxWidth = 370, minHeight = 104, paddingTop = 18, paddingBottom = 18, paddingLeft = 24, paddingRight = 24 }),
            UI.Panel {
                position = "absolute",
                left = 24,
                right = 24,
                top = 275,
                height = 245,
                borderRadius = 30,
                borderWidth = 4,
                borderColor = {255, 215, 86, 210},
                backgroundColor = {255, 215, 86, 22},
                pointerEvents = "none",
            },
        },
    }
end

function MainView.BuildRoot(labels, children)
    local actionButton = BuildActionButton()
    labels.actionButton = actionButton

    if ModelPreviewView.IsOpen and ModelPreviewView.IsOpen() then
        return UI.Panel {
            width = "100%",
            height = "100%",
            pointerEvents = "box-none",
            children = {
                ModelPreviewView.BuildOverlay(),
            },
        }
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            (deps_.isVisitMode and deps_.isVisitMode()) and BuildVisitTopHud() or BuildTopHud(labels),
            SocialView.BuildVisitBanner(),
            BuildActivityTopEntry(),
            (deps_.isFarmView() and (not deps_.isVisitMode or not deps_.isVisitMode())) and BuildTalentButton(labels) or UI.Panel { width = 0, height = 0 },
            (deps_.isVisitMode and deps_.isVisitMode()) and BuildVisitControls(actionButton) or (deps_.isFarmView() and BuildFarmControls(labels, actionButton) or BuildPlantShell(children.plantContent)),
            BuildVisitStealList(),
            BuildVisitablePlotButton(),
            BuildCollapseButton(),
            (deps_.isFarmView() or deps_.isPlantView()) and (not deps_.isVisitMode or not deps_.isVisitMode()) and SettingsView.BuildPlotDisplayButtons() or UI.Panel { width = 0, height = 0 },
            BuildPlantGuideOverlay(),
            UI.Panel { id = "bagDetailHost", position = "absolute", left = 0, right = 0, top = 0, bottom = 0, pointerEvents = "box-none", children = { children.bagDetail } },
            children.seedPackOverlay,
            children.seedPackOpeningOverlay,
            ModelPreviewView.BuildOverlay(),
            SettingsView.BuildOverlay(),
            FloatingToast.GetContainer(),
        },
    }
end

return MainView
