-- ============================================================================
-- 背包详情 UI 视图 (Bag Detail View)
-- Grow A Garden
-- ============================================================================
-- 负责背包作物详情弹窗构建。
-- ============================================================================

local UI = require("urhox-libs/UI")

local BagDetailView = {}

local deps_ = {}

function BagDetailView.Init(deps)
    deps_ = deps or {}
end

function BagDetailView.Build(item, isPlantView)
    if item == nil then
        return UI.Panel { width = 0, height = 0 }
    end

    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        backgroundColor = {0, 0, 0, 120},
        justifyContent = "center",
        alignItems = "center",
        paddingLeft = 20,
        paddingRight = 20,
        paddingTop = 90,
        paddingBottom = isPlantView and 330 or 90,
        children = {
            UI.Panel {
                width = "100%",
                maxWidth = 340,
                paddingTop = 18,
                paddingBottom = 18,
                paddingLeft = 16,
                paddingRight = 16,
                backgroundColor = {255, 253, 245, 248},
                borderRadius = 24,
                borderWidth = 3,
                borderColor = {94, 194, 131, 235},
                boxShadow = { { x = 0, y = 8, blur = 20, spread = 0, color = {0, 0, 0, 70} } },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 12,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                children = {
                                    UI.Label { text = item.name or "作物", fontSize = 24, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                    UI.Label { text = "作物详情", fontSize = 12, fontColor = {130, 110, 85, 230} },
                                },
                            },
                            UI.Button {
                                text = "×", width = 38, height = 34, fontSize = 20, fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 0}, fontColor = {120, 90, 70, 255}, borderRadius = 14,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    deps_.closeBagItemDetail()
                                end,
                            },
                        },
                    },
                    UI.Panel {
                        height = 218,
                        width = "100%",
                        marginBottom = 14,
                        justifyContent = "center",
                        alignItems = "center",
                        backgroundColor = {255, 253, 245, 255},
                        borderRadius = 22,
                        borderWidth = 2,
                        borderColor = {132, 202, 150, 225},
                        overflow = "hidden",
                        children = {
                            UI.Panel { position = "absolute", left = 26, right = 26, bottom = 28, height = 28, borderRadius = 14, backgroundColor = {90, 160, 100, 36} },
                            UI.Panel {
                                width = 176,
                                height = 176,
                                backgroundImage = item.plantIndex and string.format("image/plants/plants (%d).png", item.plantIndex) or nil,
                                backgroundFit = "contain",
                            },
                        },
                    },
                    UI.Panel {
                        gap = 8,
                        marginBottom = 14,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                paddingTop = 10,
                                paddingBottom = 10,
                                paddingLeft = 14,
                                paddingRight = 14,
                                backgroundColor = {255, 250, 240, 220},
                                borderRadius = 12,
                                children = {
                                    UI.Label { text = "重量", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                    UI.Label { text = string.format("%.2fkg", item.weight or 0), fontSize = 19, fontWeight = "bold", fontColor = item.weightTier == "Giant" and {220, 80, 70, 255} or {94, 160, 100, 255} },
                                },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                paddingTop = 10,
                                paddingBottom = 10,
                                paddingLeft = 14,
                                paddingRight = 14,
                                backgroundColor = {255, 250, 240, 220},
                                borderRadius = 12,
                                children = {
                                    UI.Label { text = "售价", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                    UI.Label { text = string.format("%d 金币", item.price or 0), fontSize = 19, fontWeight = "bold", fontColor = {190, 130, 40, 255} },
                                },
                            },
                        },
                    },
                    UI.Button {
                        text = "出售",
                        width = "100%",
                        height = 48,
                        fontSize = 18,
                        fontWeight = "bold",
                        backgroundColor = {94, 194, 131, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        borderWidth = 2,
                        borderColor = {255, 255, 255, 230},
                        onClick = function()
                            deps_.suppressWorldTap()
                            local earned = deps_.sellBagItem(item)
                            if earned > 0 then
                                deps_.showToast("出售获得 " .. earned .. " 金币")
                            end
                            deps_.rebuildUI()
                        end,
                    },
                },
            },
        },
    }
end

return BagDetailView
