-- ============================================================================
-- 主界面 UI 视图 (Main View)
-- Grow A Garden
-- ============================================================================
-- 负责根 UI、顶部 HUD、Toast、底部主操作区、种植模式外壳与收起按钮。
-- 具体内容区和弹窗由子视图传入。
-- ============================================================================

local UI = require("urhox-libs/UI")

local MainView = {}

local deps_ = {}

function MainView.Init(deps)
    deps_ = deps or {}
end

function MainView.CreateLabels()
    local labels = {}
    labels.moneyLabel = UI.Label {
        text = "金币 0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    labels.seedLabel = UI.Label {
        text = "观光 0",
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
            if deps_.isFarmView() then
                deps_.enterPlantView()
            else
                deps_.enterFarmView()
            end
        end,
    }
end

local function BuildTopHud(labels)
    return UI.Panel {
        position = "absolute",
        top = 14,
        left = 12,
        right = 12,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                paddingTop = 7, paddingBottom = 7,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = {78, 172, 110, 255},
                borderRadius = 14,
                children = {
                    labels.plotLabel,
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
                            UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {190, 160, 230, 255} },
                            UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {155, 120, 210, 255} },
                            UI.Label { position = "absolute", text = "★", fontSize = 11, fontColor = {245, 240, 255, 255} },
                        },
                    },
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
        top = 145,
        left = 28,
        right = 28,
        alignItems = "center",
        pointerEvents = "box-none",
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
            actionButton,
            UI.Panel {
                width = 90,
                height = 142,
                alignItems = "center",
                justifyContent = "flex-end",
                overflow = "visible",
                children = {
                    deps_.countSeedPacks() > 0 and UI.Button {
                        position = "absolute",
                        top = 0,
                        text = "礼包",
                        width = 68,
                        height = 42,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = {245, 232, 198, 250},
                        fontColor = {125, 88, 45, 255},
                        borderRadius = 18,
                        borderWidth = 2,
                        borderColor = {255, 255, 255, 240},
                        onClick = function()
                            deps_.suppressWorldTap()
                            deps_.openSeedPackHub()
                        end,
                    } or UI.Panel { width = 0, height = 0 },
                    deps_.countSeedPacks() > 0 and UI.Panel {
                        position = "absolute",
                        top = -6,
                        right = 4,
                        width = 24,
                        height = 24,
                        borderRadius = 12,
                        backgroundColor = {225, 55, 45, 255},
                        borderWidth = 2,
                        borderColor = {255, 255, 255, 255},
                        justifyContent = "center",
                        alignItems = "center",
                        children = { labels.seedPackBadgeLabel },
                    } or UI.Panel { width = 0, height = 0 },
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

local function BuildPlantShell(plantContent)
    local plantTab = deps_.getPlantTab()
    return UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = 0,
        paddingTop = 12, paddingBottom = 125,
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
            plantContent,
        },
    }
end

local function BuildCollapseButton()
    if not deps_.isPlantView() then
        return UI.Panel { width = 0, height = 0 }
    end
    return UI.Panel {
        position = "absolute",
        bottom = deps_.getPlantTab() == "bag" and 520 or 410,
        right = 12,
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

function MainView.BuildRoot(labels, children)
    local actionButton = BuildActionButton()
    labels.actionButton = actionButton

    return UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            BuildTopHud(labels),
            BuildToast(labels),
            deps_.isFarmView() and BuildFarmControls(labels, actionButton) or BuildPlantShell(children.plantContent),
            BuildCollapseButton(),
            children.bagDetail,
            children.seedPackOverlay,
            children.seedPackResultOverlay,
        },
    }
end

return MainView
