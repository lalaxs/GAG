-- ============================================================================
-- 模型预览 UI (Model Preview View)
-- Grow A Garden
-- ============================================================================
-- 提供测试预览入口与切换控件，用于逐个查看作物/种子包模型并截图。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ModelPreviewView = {}

local deps_ = {}

function ModelPreviewView.Init(deps)
    deps_ = deps or {}
end

function ModelPreviewView.IsOpen()
    return deps_.isOpen ~= nil and deps_.isOpen()
end

local function CurrentText()
    local item, index, total = deps_.getCurrentItem()
    if item == nil then
        return "暂无可预览模型", "0/0"
    end
    return item.name .. "  ·  " .. item.subtitle, tostring(index) .. "/" .. tostring(total)
end

function ModelPreviewView.BuildButton()
    return UI.Button {
        text = "预览",
        width = 69,
        height = 66,
        paddingTop = 0,
        paddingRight = 16,
        paddingBottom = 5,
        paddingLeft = 16,
        fontSize = 15,
        fontWeight = "bold",
        backgroundColor = {236, 246, 255, 245},
        fontColor = {70, 122, 188, 255},
        borderRadius = 14,
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            deps_.openPreview()
            deps_.rebuildUI()
        end,
    }
end

function ModelPreviewView.BuildOverlay()
    if not deps_.isOpen() then
        return UI.Panel { width = 0, height = 0 }
    end

    local item = deps_.getCurrentItem()
    local title, counter = CurrentText()
    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 1200,
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute",
                top = 104,
                left = 0,
                right = 0,
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        paddingTop = 8,
                        paddingBottom = 8,
                        paddingLeft = 10,
                        paddingRight = 10,
                        borderRadius = 20,
                        backgroundColor = {255, 250, 235, 220},
                        borderWidth = 2,
                        borderColor = {205, 178, 128, 205},
                        children = {
                            UI.Button {
                                text = "作物",
                                width = 86,
                                height = 38,
                                fontSize = 15,
                                fontWeight = "bold",
                                borderRadius = 15,
                                backgroundColor = item and item.kind == "plant" and {82, 190, 122, 255} or {230, 226, 214, 255},
                                fontColor = item and item.kind == "plant" and {255, 255, 255, 255} or {86, 72, 54, 255},
                                onClick = function()
                                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                                    deps_.showKind("plant")
                                    deps_.rebuildUI()
                                end,
                            },
                            UI.Button {
                                text = "种子包",
                                width = 100,
                                height = 38,
                                fontSize = 15,
                                fontWeight = "bold",
                                borderRadius = 15,
                                backgroundColor = item and item.kind == "pack" and {82, 190, 122, 255} or {230, 226, 214, 255},
                                fontColor = item and item.kind == "pack" and {255, 255, 255, 255} or {86, 72, 54, 255},
                                onClick = function()
                                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                                    deps_.showKind("pack")
                                    deps_.rebuildUI()
                                end,
                            },
                        },
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                top = 36,
                left = 18,
                right = 18,
                paddingTop = 12,
                paddingBottom = 12,
                paddingLeft = 16,
                paddingRight = 16,
                borderRadius = 22,
                backgroundColor = {255, 250, 235, 235},
                borderWidth = 2,
                borderColor = {205, 178, 128, 220},
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 3,
                        children = {
                            UI.Label { text = "模型截图预览", fontSize = 13, fontWeight = "bold", fontColor = {96, 72, 44, 230} },
                            UI.Label { text = title, fontSize = 18, fontWeight = "bold", fontColor = {48, 42, 34, 255} },
                        },
                    },
                    UI.Label { text = counter, width = 58, fontSize = 15, fontWeight = "bold", fontColor = {80, 120, 185, 255}, textAlign = "right" },
                },
            },
            UI.Panel {
                position = "absolute",
                left = 0,
                right = 0,
                bottom = 42,
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 12,
                        paddingTop = 12,
                        paddingBottom = 12,
                        paddingLeft = 14,
                        paddingRight = 14,
                        borderRadius = 24,
                        backgroundColor = {255, 250, 235, 238},
                        borderWidth = 2,
                        borderColor = {205, 178, 128, 220},
                        children = {
                            UI.Button {
                                text = "上一个",
                                width = 112,
                                height = 48,
                                fontSize = 17,
                                fontWeight = "bold",
                                borderRadius = 18,
                                onClick = function()
                                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                                    deps_.prevPreview()
                                    deps_.rebuildUI()
                                end,
                            },
                            UI.Button {
                                text = "关闭",
                                width = 100,
                                height = 48,
                                fontSize = 17,
                                fontWeight = "bold",
                                borderRadius = 18,
                                backgroundColor = {230, 226, 214, 255},
                                fontColor = {96, 80, 58, 255},
                                onClick = function()
                                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                                    deps_.closePreview()
                                    deps_.rebuildUI()
                                end,
                            },
                            UI.Button {
                                text = "下一个",
                                width = 112,
                                height = 48,
                                fontSize = 17,
                                fontWeight = "bold",
                                borderRadius = 18,
                                variant = "primary",
                                onClick = function()
                                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                                    deps_.nextPreview()
                                    deps_.rebuildUI()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

return ModelPreviewView
