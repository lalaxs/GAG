-- ============================================================================
-- 天赋面板 UI (Talent View) - 竖版横向链 + 选中确认交互
-- Grow A Garden
-- ============================================================================

local UI = require("urhox-libs/UI")
local TalentSystem = require("systems.talent_system")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")
local Format = require("utils.format")
local AudioSystem = require("systems.audio_system")

local TalentView = {}

local modal_ = nil
local selectedTalentId_ = nil
local detailPanel_ = nil
local pointsLabel_ = nil
local pointsBadge_ = nil
local nodeRefs_ = {}  -- { [talentId] = { button = Widget, defaultBorder = color } }
local lineRefs_ = {}  -- { [prevTalentId] = Widget }
local deps_ = {}

function TalentView.Init(deps)
    deps_ = deps or {}
end

-- 天赋链定义
local TALENT_CHAINS = {
    { label = "收获", color = {80, 180, 100, 255}, talents = { "drop_rate_1", "drop_rate_2", "drop_rate_3", "drop_rate_4", "drop_rate_5" } },
    { label = "生长", color = {60, 160, 200, 255}, talents = { "grow_speed_1", "grow_speed_2", "grow_speed_3", "grow_speed_4", "grow_speed_5" } },
    { label = "经济", color = {220, 175, 40, 255}, talents = { "sell_bonus_1", "sell_bonus_2", "sell_bonus_3", "sell_bonus_4", "sell_bonus_5" } },
    { label = "变异", color = {170, 90, 210, 255}, talents = { "mutation_1", "mutation_2", "mutation_3", "mutation_4", "mutation_5" } },
    { label = "背包", color = {190, 130, 70, 255}, talents = { "bag_capacity_1", "bag_capacity_2", "bag_capacity_3", "bag_capacity_4", "bag_capacity_5" } },
}

local NODE_SIZE = 52
local SELECTED_BORDER = {255, 90, 50, 255}
local RefreshDetailPanel = nil

-- 高亮选中节点，重置其他节点
local function HighlightSelected(talentId)
    for id, ref in pairs(nodeRefs_) do
        if id == talentId then
            ref.button:SetBorderColor(SELECTED_BORDER)
            ref.button:SetBorderWidth(3)
        else
            ref.button:SetBorderColor(ref.defaultBorder)
            ref.button:SetBorderWidth(2)
        end
    end
end

local function GetTalentVisualState(talentId, chainColor, tierIndex)
    local unlocked = TalentSystem.IsTalentUnlocked(talentId)
    local canUnlock = TalentSystem.CanUnlockTalent(talentId)

    local bgColor
    if unlocked then
        bgColor = chainColor
    elseif canUnlock then
        bgColor = {255, 235, 150, 255}
    else
        bgColor = {230, 230, 230, 255}
    end

    local borderColor
    if unlocked then
        borderColor = {255, 255, 255, 200}
    elseif canUnlock then
        borderColor = {220, 175, 40, 255}
    else
        borderColor = {200, 200, 200, 255}
    end

    return {
        bgColor = bgColor,
        borderColor = borderColor,
        fontSize = unlocked and 18 or 15,
        fontColor = unlocked and {255, 255, 255, 255} or {70, 70, 70, 255},
        text = unlocked and "✓" or tostring(tierIndex),
    }
end

local function RefreshTalentNodes()
    for _, chain in ipairs(TALENT_CHAINS) do
        for tierIndex, talentId in ipairs(chain.talents) do
            local ref = nodeRefs_[talentId]
            if ref ~= nil then
                local visual = GetTalentVisualState(talentId, chain.color, tierIndex)
                ref.defaultBorder = visual.borderColor
                ref.button:SetBackgroundColor(visual.bgColor)
                ref.button:SetBorderColor(talentId == selectedTalentId_ and SELECTED_BORDER or visual.borderColor)
                ref.button:SetBorderWidth(talentId == selectedTalentId_ and 3 or 2)
                ref.button:SetText(visual.text)
            end
        end
    end
end

local function RefreshTalentLines()
    for talentId, line in pairs(lineRefs_) do
        line:SetBackgroundColor(TalentSystem.IsTalentUnlocked(talentId) and {100, 200, 120, 255} or {210, 210, 210, 255})
    end
end

local function RefreshTalentPointsHeader()
    local points = TalentSystem.GetTalentPoints()
    if pointsLabel_ ~= nil then
        pointsLabel_:SetText(tostring(points))
    end
    if pointsBadge_ ~= nil then
        pointsBadge_:SetBackgroundColor(points > 0 and {78, 172, 110, 255} or {180, 180, 180, 255})
    end
end

local function RefreshTalentState(successText)
    RefreshTalentNodes()
    RefreshTalentLines()
    RefreshTalentPointsHeader()
    RefreshDetailPanel(successText)
end

-- 刷新底部详情面板
RefreshDetailPanel = function(successText)
    if detailPanel_ == nil then return end
    detailPanel_:RemoveAllChildren()

    if selectedTalentId_ == nil then
        detailPanel_:AddChild(UI.Label {
            text = "点击节点查看详情",
            fontSize = 14, fontColor = {150, 150, 150, 255},
            textAlign = "center",
        })
        return
    end

    local talent = TalentSystem.FindTalent(selectedTalentId_)
    if talent == nil then return end

    local unlocked = TalentSystem.IsTalentUnlocked(selectedTalentId_)
    local canUnlock = TalentSystem.CanUnlockTalent(selectedTalentId_)
    local hasReq = talent.requires == nil or TalentSystem.IsTalentUnlocked(talent.requires)

    local goldCost = talent.goldCost or 0
    local statusText
    local statusColor
    if unlocked then
        statusText = "已点亮"
        statusColor = {80, 160, 80, 255}
    elseif canUnlock then
        statusText = "可解锁"
        statusColor = {180, 140, 20, 255}
    elseif not hasReq then
        statusText = "需要先解锁前置天赋"
        statusColor = {210, 70, 55, 255}
    else
        statusText = "条件不足"
        statusColor = {210, 70, 55, 255}
    end

    detailPanel_:AddChild(UI.Label {
        text = talent.name,
        fontSize = 18, fontWeight = "bold", fontColor = {50, 50, 50, 255},
    })
    detailPanel_:AddChild(UI.Label {
        text = talent.desc,
        fontSize = 15, fontColor = {80, 80, 80, 255}, marginTop = 4,
    })
    detailPanel_:AddChild(UI.Label {
        text = statusText,
        fontSize = 14, fontColor = statusColor, marginTop = 6,
    })

    if successText ~= nil then
        detailPanel_:AddChild(UI.Panel {
            marginTop = 8,
            paddingTop = 7,
            paddingBottom = 7,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = {78, 172, 110, 255},
            borderRadius = 8,
            children = {
                UI.Label {
                    text = successText,
                    fontSize = 14,
                    fontWeight = "bold",
                    fontColor = {255, 255, 255, 255},
                    textAlign = "center",
                },
            },
        })
    end

    -- 显示解锁消耗
    if not unlocked then
        detailPanel_:AddChild(UI.Panel {
            marginTop = 6,
            gap = 4,
            children = {
                UI.Label {
                    text = "消耗:",
                    fontSize = 13, fontWeight = "bold", fontColor = {90, 80, 60, 255},
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        -- 天赋点
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 3,
                            children = {
                                UI.Panel {
                                    width = 16, height = 16, borderRadius = 8,
                                    backgroundColor = {78, 172, 110, 255},
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label { text = "◆", fontSize = 8, fontColor = {255, 255, 255, 255} },
                                    },
                                },
                                UI.Label { text = talent.cost .. " 天赋点", fontSize = 13, fontColor = {60, 130, 80, 255} },
                            },
                        },
                        -- 金币
                        goldCost > 0 and UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 3,
                            children = {
                                UI.Panel {
                                    width = 16, height = 16, borderRadius = 8,
                                    backgroundColor = {230, 175, 30, 255},
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label { text = "$", fontSize = 9, fontWeight = "bold", fontColor = {255, 245, 200, 255} },
                                    },
                                },
                                UI.Label { text = Format.Gold(goldCost), fontSize = 13, fontColor = {160, 120, 20, 255} },
                            },
                        } or UI.Panel { width = 0, height = 0 },
                    },
                },
            },
        })
    end

    if canUnlock then
        detailPanel_:AddChild(UI.Button {
            text = "确认解锁",
            variant = "primary",
            width = "100%",
            height = 42,
            fontSize = 16,
            fontWeight = "bold",
            borderRadius = 10,
            marginTop = 8,
            marginBottom = 4,
            onClick = function()
                if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                local unlockedTalentId = selectedTalentId_
                if deps_.unlockTalent and deps_.unlockTalent(unlockedTalentId) then
                    FloatingToast.Show("正在请求服务器解锁天赋")
                elseif deps_.showToast then
                    deps_.showToast("服务器尚未就绪，无法解锁天赋")
                end
            end,
        })
    end
end

local function OnNodeClick(talentId)
    selectedTalentId_ = talentId
    HighlightSelected(talentId)
    RefreshDetailPanel()
end

local function BuildHLine(unlocked, prevTalentId)
    local line = UI.Panel {
        width = 8, height = 3,
        backgroundColor = unlocked and {100, 200, 120, 255} or {210, 210, 210, 255},
        borderRadius = 1,
        alignSelf = "center",
    }
    if prevTalentId ~= nil then
        lineRefs_[prevTalentId] = line
    end
    return line
end

local function BuildTalentNode(talentId, chainColor, tierIndex)
    local talent = TalentSystem.FindTalent(talentId)
    if talent == nil then return UI.Panel { width = 0, height = 0 } end

    local unlocked = TalentSystem.IsTalentUnlocked(talentId)
    local canUnlock = TalentSystem.CanUnlockTalent(talentId)

    local bgColor
    if unlocked then
        bgColor = chainColor
    elseif canUnlock then
        bgColor = {255, 235, 150, 255}
    else
        bgColor = {230, 230, 230, 255}
    end

    local borderColor
    if unlocked then
        borderColor = {255, 255, 255, 200}
    elseif canUnlock then
        borderColor = {220, 175, 40, 255}
    else
        borderColor = {200, 200, 200, 255}
    end

    local btn = UI.Button {
        width = NODE_SIZE,
        height = NODE_SIZE,
        borderRadius = NODE_SIZE / 2,
        backgroundColor = bgColor,
        borderWidth = 2,
        borderColor = borderColor,
        fontSize = unlocked and 18 or 15,
        fontWeight = "bold",
        fontColor = unlocked and {255, 255, 255, 255} or {70, 70, 70, 255},
        text = unlocked and "✓" or tostring(tierIndex),
        onClick = function()
            OnNodeClick(talentId)
        end,
    }

    -- 存储引用
    nodeRefs_[talentId] = { button = btn, defaultBorder = borderColor }

    return btn
end

local function BuildChainRow(chain)
    local rowChildren = {}

    -- 分类标题
    table.insert(rowChildren, UI.Panel {
        width = 46, alignItems = "center", justifyContent = "center",
        marginRight = 6,
        children = {
            UI.Label { text = chain.label, fontSize = 17, fontWeight = "bold", fontColor = {50, 50, 50, 255} },
        },
    })

    -- 节点 + 连线
    for i, talentId in ipairs(chain.talents) do
        if i > 1 then
            local prevTalentId = chain.talents[i - 1]
            local prevUnlocked = TalentSystem.IsTalentUnlocked(prevTalentId)
            table.insert(rowChildren, BuildHLine(prevUnlocked, prevTalentId))
        end
        table.insert(rowChildren, BuildTalentNode(talentId, chain.color, i))
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 2,
        paddingTop = 7,
        paddingBottom = 7,
        children = rowChildren,
    }
end

function TalentView.Show()
    if modal_ ~= nil then
        modal_:Close()
    end
    nodeRefs_ = {}
    lineRefs_ = {}

    local level = TalentSystem.GetLevel()
    local exp = TalentSystem.GetExp()
    local expNeeded = TalentSystem.GetExpToNextLevel()
    local points = TalentSystem.GetTalentPoints()
    pointsLabel_ = nil
    pointsBadge_ = nil
    local isMax = TalentSystem.IsMaxLevel()
    local expProgress = isMax and 1.0 or (exp / expNeeded)

    -- 底部详情面板（固定高度避免可解锁按钮被裁剪）
    detailPanel_ = UI.Panel {
        width = "100%",
        padding = 12,
        backgroundColor = {255, 252, 240, 255},
        borderRadius = 10,
        borderWidth = 1,
        borderColor = {218, 208, 182, 255},
        minHeight = 176,
        flexShrink = 0,
    }

    pointsLabel_ = UI.Label { text = tostring(points), fontSize = 16, fontWeight = "bold", fontColor = {255, 255, 255, 255} }
    pointsBadge_ = UI.Panel {
        width = 32, height = 32, borderRadius = 16,
        backgroundColor = points > 0 and {78, 172, 110, 255} or {180, 180, 180, 255},
        justifyContent = "center", alignItems = "center",
        children = { pointsLabel_ },
    }

    modal_ = UI.Modal {
        title = "天赋",
        size = "fullscreen",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {14, 16, 14, 16},
        contentGap = 8,
        onClose = function()
            modal_ = nil
            detailPanel_ = nil
            pointsLabel_ = nil
            pointsBadge_ = nil
            selectedTalentId_ = nil
            nodeRefs_ = {}
            lineRefs_ = {}
        end,
    }

    local chainRows = {}
    for _, chain in ipairs(TALENT_CHAINS) do
        table.insert(chainRows, BuildChainRow(chain))
    end

    local contentChildren = {
        -- 顶部信息
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingBottom = 8,
            borderBottomWidth = 1,
            borderColor = {235, 235, 235, 255},
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        UI.Panel {
                            paddingTop = 4, paddingBottom = 4,
                            paddingLeft = 10, paddingRight = 10,
                            backgroundColor = {78, 172, 110, 255},
                            borderRadius = 10,
                            children = {
                                UI.Label { text = "LV" .. level, fontSize = 18, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
                            },
                        },
                        UI.Panel {
                            gap = 2,
                            children = {
                                UI.Panel {
                                    width = 120, height = 10, borderRadius = 5,
                                    backgroundColor = {225, 228, 235, 255},
                                    overflow = "hidden",
                                    children = {
                                        UI.Panel {
                                            width = tostring(math.floor(expProgress * 100)) .. "%",
                                            height = "100%", borderRadius = 5,
                                            backgroundColor = {100, 180, 240, 255},
                                        },
                                    },
                                },
                                UI.Label { text = isMax and "MAX" or (exp .. "/" .. expNeeded), fontSize = 14, fontColor = {120, 120, 120, 255} },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label { text = "天赋点", fontSize = 15, fontColor = {100, 100, 100, 255} },
                        pointsBadge_,
                    },
                },
            },
        },
    }
    for _, row in ipairs(chainRows) do
        table.insert(contentChildren, row)
    end
    table.insert(contentChildren, UI.Panel { width = "100%", height = 1, backgroundColor = {235, 235, 235, 255}, marginTop = 4 })
    table.insert(contentChildren, detailPanel_)

    modal_:AddContent(UI.Panel {
        width = "100%",
        gap = 4,
        children = contentChildren,
    })

    RefreshDetailPanel()
    ModalAnim.Apply(modal_, { fixedHeight = 760 })
    modal_:Open()
end

function TalentView.Hide()
    if modal_ ~= nil then
        modal_:Close()
    end
end

function TalentView.IsOpen()
    return modal_ ~= nil
end

return TalentView
