-- ============================================================================
-- 委托 UI 视图 (Commission View)
-- Grow A Garden
-- ============================================================================
-- 展示 30 分钟刷新的作物求购委托。列表页只展示委托摘要；点击卡牌后，
-- 在详情弹窗中选择满足条件的背包作物并提交。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")

local CommissionView = {}

local deps_ = {}
local commissionModal_ = nil
local detailModal_ = nil

local RARITY_COLORS = {
    ["普通"] = {122, 112, 90, 255},
    ["罕见"] = {66, 156, 82, 255},
    ["稀有"] = {62, 124, 210, 255},
    ["史诗"] = {156, 78, 210, 255},
    ["传奇"] = {218, 132, 30, 255},
}

local PACK_COLORS = {
    pack_rare = {205, 225, 255, 255},
    pack_epic = {236, 214, 255, 255},
    pack_legendary = {255, 230, 184, 255},
}

local LABEL_BG = {238, 218, 176, 255}
local LABEL_TITLE = {138, 94, 42, 255}
local LABEL_VALUE = {76, 50, 24, 255}

function CommissionView.Init(deps)
    deps_ = deps or {}
end

function CommissionView.IsOpen()
    return commissionModal_ ~= nil or detailModal_ ~= nil
end

local function FormatWeight(weight)
    return string.format("%.2fkg", weight or 0)
end

local function GetPackCfg(packId)
    local config = deps_.seedPackConfig or {}
    return config[packId] or {}
end

local function GetRarityColor(rarity)
    return RARITY_COLORS[rarity] or RARITY_COLORS["普通"]
end

local function BuildRequirementLabel(title, value)
    return UI.Panel {
        paddingTop = 7,
        paddingBottom = 7,
        paddingLeft = 8,
        paddingRight = 8,
        backgroundColor = LABEL_BG,
        borderRadius = 13,
        borderWidth = 1,
        borderColor = {255, 244, 216, 170},
        children = {
            UI.Label {
                text = title,
                fontSize = 9,
                fontWeight = "bold",
                fontColor = LABEL_TITLE,
                textAlign = "center",
            },
            UI.Label {
                text = value,
                fontSize = 12,
                fontWeight = "bold",
                fontColor = LABEL_VALUE,
                textAlign = "center",
                maxLines = 1,
            },
        },
    }
end

local function BuildRewardPanel(commission)
    local packCfg = GetPackCfg(commission.rewardPackId)
    local packColor = PACK_COLORS[commission.rewardPackId] or {235, 235, 225, 255}
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingTop = 8,
        paddingBottom = 8,
        paddingLeft = 9,
        paddingRight = 9,
        backgroundColor = packColor,
        borderRadius = 15,
        borderWidth = 2,
        borderColor = {255, 250, 235, 255},
        children = {
            UI.Panel {
                width = 31,
                height = 36,
                backgroundImage = packCfg.packIcon or "image/seedpack_icon/seedpack_2.png",
                backgroundFit = "contain",
            },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = "完成奖励",
                        fontSize = 9,
                        fontWeight = "bold",
                        fontColor = {128, 86, 42, 230},
                    },
                    UI.Label {
                        text = commission.rewardPackName or packCfg.packName or "种子包",
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = {92, 60, 28, 255},
                        maxLines = 1,
                    },
                },
            },
        },
    }
end

local function CloseDetailModal()
    if detailModal_ ~= nil then
        detailModal_:Close()
        detailModal_ = nil
    end
end

local function CloseMainModal()
    if commissionModal_ ~= nil then
        commissionModal_:Close()
        commissionModal_ = nil
    end
end

local function SubmitCommission(commission, item)
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
    if item == nil then
        if deps_.showToast then deps_.showToast("请先选择一个满足条件的作物") end
        return
    end
    if deps_.completeCommission and deps_.completeCommission(commission, item) then
        local rewardName = commission.rewardPackName or "种子包"
        FloatingToast.Show("提交成功! 获得" .. rewardName, {
            fontSize = 19,
            duration = 1.7,
            yRatio = 0.38,
            priority = 8,
        })
        CloseDetailModal()
        CloseMainModal()
    end
end

local function BuildItemRow(commission, item, selectedItem)
    local selected = item == selectedItem
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 9,
        paddingTop = 9,
        paddingBottom = 9,
        paddingLeft = 10,
        paddingRight = 10,
        marginBottom = 8,
        backgroundColor = selected and {226, 248, 218, 255} or {255, 253, 245, 255},
        borderRadius = 16,
        borderWidth = selected and 3 or 2,
        borderColor = selected and {82, 188, 98, 245} or {218, 195, 154, 210},
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            CloseDetailModal()
            CommissionView.ShowDetail(commission, item)
        end,
        children = {
            UI.Panel {
                width = 42,
                height = 42,
                backgroundImage = item.plantIndex and string.format("image/plants/plants (%d).png", item.plantIndex) or nil,
                backgroundFit = "contain",
            },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = item.name or "作物",
                        fontSize = 13,
                        fontWeight = "bold",
                        fontColor = {76, 50, 24, 255},
                        maxLines = 1,
                    },
                    UI.Label {
                        text = string.format("重量 %s  售价 %d", FormatWeight(item.weight), item.price or 0),
                        fontSize = 11,
                        fontColor = {126, 94, 58, 235},
                    },
                },
            },
            UI.Label {
                text = selected and "已选" or "选择",
                width = 34,
                fontSize = 11,
                fontWeight = "bold",
                fontColor = selected and {58, 150, 70, 255} or {150, 112, 72, 230},
                textAlign = "right",
            },
        },
    }
end

function CommissionView.ShowDetail(commission, selectedItem)
    CloseDetailModal()

    local matches = deps_.getMatchingItems and deps_.getMatchingItems(commission) or {}
    if selectedItem == nil and #matches > 0 then
        selectedItem = matches[1]
    end

    detailModal_ = UI.Modal {
        title = "委托详情",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 16, 16},
        contentGap = 10,
        onClose = function()
            detailModal_ = nil
        end,
    }

    local listChildren = {}
    if #matches == 0 then
        table.insert(listChildren, UI.Panel {
            height = 92,
            justifyContent = "center",
            alignItems = "center",
            padding = 12,
            backgroundColor = {246, 238, 222, 255},
            borderRadius = 16,
            borderWidth = 2,
            borderColor = {210, 190, 155, 180},
            children = {
                UI.Label {
                    text = "背包中暂无满足条件的作物",
                    fontSize = 13,
                    fontWeight = "bold",
                    fontColor = {145, 112, 78, 235},
                    textAlign = "center",
                },
            },
        })
    else
        for _, item in ipairs(matches) do
            table.insert(listChildren, BuildItemRow(commission, item, selectedItem))
        end
    end

    detailModal_:AddContent(UI.Panel {
        gap = 10,
        children = {
            UI.Panel {
                alignItems = "center",
                paddingTop = 10,
                paddingBottom = 10,
                backgroundColor = {255, 248, 226, 252},
                borderRadius = 20,
                borderWidth = 2,
                borderColor = {224, 176, 78, 210},
                children = {
                    UI.Panel {
                        width = 76,
                        height = 76,
                        marginBottom = 6,
                        backgroundImage = commission.plantIndex and string.format("image/plants/plants (%d).png", commission.plantIndex) or nil,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        text = commission.plantName or "作物",
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = GetRarityColor(commission.plantRarity),
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    UI.Panel { flexGrow = 1, flexShrink = 1, children = { BuildRequirementLabel("变异条件", commission.mutation and commission.mutation.name or "任意变异") } },
                    UI.Panel { flexGrow = 1, flexShrink = 1, children = { BuildRequirementLabel("最低重量", "≥ " .. FormatWeight(commission.minWeight)) } },
                },
            },
            BuildRewardPanel(commission),
            UI.Label {
                text = "选择可提交作物",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = {96, 62, 32, 255},
                marginTop = 4,
            },
            UI.ScrollView {
                height = 188,
                scrollY = true,
                showScrollbar = false,
                bounces = true,
                children = listChildren,
            },
            UI.Button {
                text = selectedItem ~= nil and "提交委托" or "没有可提交作物",
                width = "100%",
                height = 48,
                fontSize = 17,
                fontWeight = "bold",
                variant = "primary",
                borderRadius = 18,
                disabled = selectedItem == nil,
                onClick = function()
                    SubmitCommission(commission, selectedItem)
                end,
            },
        },
    })

    ModalAnim.Apply(detailModal_, { fixedHeight = 640 })
    detailModal_:Open()
end

local function BuildCommissionCard(commission)
    local matches = deps_.getMatchingItems and deps_.getMatchingItems(commission) or {}
    local completed = commission.completed
    local canComplete = (not completed) and #matches > 0
    local borderColor = completed and {164, 152, 124, 200} or (canComplete and {82, 188, 98, 245} or {222, 174, 95, 235})
    local backgroundColor = completed and {232, 226, 210, 245} or (canComplete and {246, 255, 238, 252} or {255, 248, 226, 252})

    return UI.Panel {
        width = "48%",
        height = 356,
        marginBottom = 14,
        paddingTop = 14,
        paddingBottom = 14,
        paddingLeft = 11,
        paddingRight = 11,
        backgroundColor = backgroundColor,
        borderRadius = 16,
        borderWidth = 3,
        borderColor = borderColor,
        boxShadow = canComplete and { { x = 0, y = 5, blur = 14, spread = 0, color = {70, 170, 80, 70} } }
            or { { x = 0, y = 4, blur = 12, spread = 0, color = {0, 0, 0, 36} } },
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            CommissionView.ShowDetail(commission, nil)
        end,
        children = {
            UI.Label {
                text = "求购作物",
                fontSize = 18,
                fontWeight = "bold",
                fontColor = {96, 62, 32, 255},
                textAlign = "center",
                marginBottom = 9,
            },
            UI.Panel {
                height = 92,
                justifyContent = "center",
                alignItems = "center",
                marginBottom = 9,
                children = {
                    UI.Panel {
                        position = "absolute",
                        width = 90,
                        height = 40,
                        borderRadius = 20,
                        backgroundColor = {116, 82, 42, 28},
                    },
                    UI.Panel {
                        width = 62,
                        height = 62,
                        marginBottom = 24,
                        backgroundImage = commission.plantIndex and string.format("image/plants/plants (%d).png", commission.plantIndex) or nil,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        position = "absolute",
                        bottom = 0,
                        text = commission.plantName or "作物",
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = GetRarityColor(commission.plantRarity),
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                gap = 6,
                marginBottom = 9,
                children = {
                    BuildRequirementLabel("变异条件", commission.mutation and commission.mutation.name or "任意变异"),
                    BuildRequirementLabel("最低重量", "≥ " .. FormatWeight(commission.minWeight)),
                },
            },
            BuildRewardPanel(commission),
            (completed or canComplete) and UI.Panel {
                height = 38,
                justifyContent = "center",
                alignItems = "center",
                marginTop = 8,
                backgroundColor = canComplete and {232, 250, 225, 255} or {244, 236, 222, 255},
                borderRadius = 14,
                children = {
                    UI.Label {
                        text = completed and "已完成" or ("可提交 x" .. tostring(#matches)),
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = canComplete and {54, 142, 66, 255} or {145, 112, 78, 235},
                        textAlign = "center",
                    },
                },
            } or UI.Panel { height = 0 },
        },
    }
end

local function BuildContent()
    local commissions = deps_.getCommissions and deps_.getCommissions() or {}
    local cards = {}
    for _, commission in ipairs(commissions) do
        table.insert(cards, BuildCommissionCard(commission))
    end

    if #cards == 0 then
        table.insert(cards, UI.Panel {
            width = "100%",
            height = 160,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label { text = "暂无委托", fontSize = 16, fontColor = {120, 100, 80, 230} },
            },
        })
    end

    return UI.Panel {
        gap = 8,
        children = {
            UI.Panel {
                height = 34,
                flexDirection = "row",
                justifyContent = "flex-end",
                alignItems = "center",
                paddingRight = 4,
                children = {
                    UI.Label {
                        text = "刷新倒计时 " .. (deps_.getTimeLeftText and deps_.getTimeLeftText() or "--:--"),
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = {100, 80, 60, 220},
                    },
                },
            },
            UI.ScrollView {
                height = 595,
                scrollY = true,
                showScrollbar = false,
                bounces = true,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "space-between",
                        alignItems = "flex-start",
                        children = cards,
                    },
                },
            },
        },
    }
end

function CommissionView.RefreshContent()
    if commissionModal_ ~= nil then
        commissionModal_:ClearContent()
        commissionModal_:AddContent(BuildContent())
    end
end

function CommissionView.Show()
    if commissionModal_ ~= nil then
        commissionModal_:Close()
        commissionModal_ = nil
    end

    commissionModal_ = UI.Modal {
        title = "委托",
        size = "fullscreen",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {10, 14, 12, 14},
        contentGap = 8,
        onClose = function()
            commissionModal_ = nil
        end,
    }

    commissionModal_:AddContent(BuildContent())
    ModalAnim.Apply(commissionModal_, { fixedHeight = math.floor((graphics:GetHeight() / graphics:GetDPR()) * 0.96) })
    commissionModal_:Open()
end

return CommissionView
