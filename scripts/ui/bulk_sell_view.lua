-- ============================================================================
-- 批量出售背包作物弹窗 (Bulk Sell View)
-- Grow A Garden
-- ============================================================================

local UI = require("urhox-libs/UI")
local FloatingToast = require("ui.floating_toast")
local Format = require("utils.format")

local BulkSellView = {}

local deps_ = {}
local modal_ = nil
local contentPanel_ = nil
local filter_ = {
    basicMutation = false,
    specialMutation = false,
    giant = false,
}

function BulkSellView.Init(deps)
    deps_ = deps or {}
end

local function HasAnyFilter()
    return filter_.basicMutation or filter_.specialMutation or filter_.giant
end

local function GetFilterTitle()
    if not HasAnyFilter() then
        return "普通作物"
    end
    local names = {}
    if filter_.basicMutation then table.insert(names, "变异") end
    if filter_.specialMutation then table.insert(names, "特殊") end
    if filter_.giant then table.insert(names, "巨大") end
    return table.concat(names, "、")
end

local function CurrentPreview()
    if deps_.previewSellHarvestedByFilter == nil then
        return 0, 0
    end
    return deps_.previewSellHarvestedByFilter(filter_)
end

local RefreshContent = nil

local function BuildChip(key, title)
    local selected = filter_[key] == true
    return UI.Panel {
        height = 34,
        paddingLeft = 9,
        paddingRight = 12,
        borderRadius = 17,
        borderWidth = 2,
        borderColor = selected and {94, 194, 131, 255} or {205, 190, 160, 220},
        backgroundColor = selected and {232, 248, 235, 255} or {255, 253, 245, 255},
        flexDirection = "row",
        alignItems = "center",
        gap = 5,
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            filter_[key] = not filter_[key]
            RefreshContent()
        end,
        children = {
            UI.Panel {
                width = 18,
                height = 18,
                borderRadius = 9,
                backgroundColor = selected and {94, 194, 131, 255} or {225, 216, 196, 255},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = selected and "✓" or "",
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = {255, 255, 255, 255},
                        textAlign = "center",
                    },
                },
            },
            UI.Label {
                text = title,
                fontSize = 14,
                fontWeight = "bold",
                fontColor = selected and {55, 130, 75, 255} or {95, 75, 55, 255},
            },
        },
    }
end

RefreshContent = function()
    if contentPanel_ == nil then return end
    contentPanel_:RemoveAllChildren()

    local count, total = CurrentPreview()
    local canSell = count > 0
    local filterTitle = GetFilterTitle()

    contentPanel_:AddChild(UI.Label {
        text = "选择要出售的类型",
        fontSize = 18,
        fontWeight = "bold",
        fontColor = {75, 55, 40, 255},
        textAlign = "center",
    })

    contentPanel_:AddChild(UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        gap = 8,
        marginTop = 4,
        children = {
            BuildChip("basicMutation", "变异"),
            BuildChip("specialMutation", "特殊"),
            BuildChip("giant", "巨大"),
        },
    })

    contentPanel_:AddChild(UI.Panel {
        marginTop = 8,
        paddingTop = 12,
        paddingBottom = 12,
        paddingLeft = 14,
        paddingRight = 14,
        backgroundColor = {255, 250, 238, 245},
        borderRadius = 18,
        borderWidth = 1,
        borderColor = {220, 205, 175, 230},
        gap = 4,
        children = {
            UI.Label {
                text = "当前: " .. filterTitle,
                fontSize = 14,
                fontWeight = "bold",
                fontColor = {95, 75, 55, 255},
                textAlign = "center",
            },
            UI.Label {
                text = string.format("%d 个 / %s 金币", count, Format.Gold(total)),
                fontSize = 17,
                fontWeight = "bold",
                fontColor = canSell and {80, 150, 88, 255} or {150, 120, 90, 255},
                textAlign = "center",
            },
        },
    })

    contentPanel_:AddChild(UI.Panel {
        flexDirection = "row",
        gap = 10,
        marginTop = 6,
        children = {
            UI.Button {
                text = "取消",
                flexGrow = 1,
                height = 46,
                fontSize = 16,
                fontWeight = "bold",
                borderRadius = 16,
                backgroundColor = {235, 225, 205, 255},
                fontColor = {95, 75, 55, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    if modal_ ~= nil then modal_:Close() end
                end,
            },
            UI.Button {
                text = "出售",
                flexGrow = 1,
                height = 46,
                fontSize = 17,
                fontWeight = "bold",
                borderRadius = 16,
                disabled = not canSell,
                backgroundColor = {94, 194, 131, 255},
                disabledBackgroundColor = {205, 198, 180, 255},
                fontColor = {255, 255, 255, 255},
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    if not canSell then return end
                    local soldCount, earned = deps_.sellHarvestedByFilter(filter_)
                    if soldCount == true then
                        if deps_.showToast then deps_.showToast("正在请求服务器出售作物...") end
                    elseif (soldCount or 0) > 0 then
                        local text = string.format("卖出%d个作物，获得%s金币", soldCount, Format.Gold(earned or 0))
                        if deps_.showToast then deps_.showToast(text) end
                        FloatingToast.Show(text, { fontSize = 20, duration = 1.8, yRatio = 0.36, priority = 6 })
                    end
                    if modal_ ~= nil then modal_:Close() end
                end,
            },
        },
    })
end

function BulkSellView.Show()
    if modal_ ~= nil then
        modal_:Close()
    end
    filter_ = {
        basicMutation = false,
        specialMutation = false,
        giant = false,
    }
    contentPanel_ = UI.Panel {
        width = "100%",
        gap = 8,
        paddingTop = 8,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 248, 226, 245},
        borderRadius = 24,
    }
    modal_ = UI.Modal {
        title = "一键出售",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 16, 16},
        onClose = function()
            modal_ = nil
            contentPanel_ = nil
        end,
    }
    modal_:AddContent(contentPanel_)
    RefreshContent()
    modal_:Open()
end

function BulkSellView.Hide()
    if modal_ ~= nil then
        modal_:Close()
    end
end

function BulkSellView.IsOpen()
    return modal_ ~= nil
end

return BulkSellView
