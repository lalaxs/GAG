-- ============================================================================
-- 地块扩展弹窗 (Expansion View) — Animal Crossing Style
-- Grow A Garden
-- ============================================================================

local UI = require("urhox-libs/UI")
local ProgressionSystem = require("systems.progression_system")
local ModalAnim = require("ui.modal_anim")
local Format = require("utils.format")

local ExpansionView = {}

local modal_ = nil
local deps_ = {}

-- 动森配色
local COLORS = {
    -- 背景 & 容器
    cardBg        = {253, 251, 240, 255},  -- 暖奶油白
    cardBorder    = {210, 195, 160, 255},  -- 柔和卡其边框
    headerBg      = {240, 248, 235, 255},  -- 淡薄荷绿底
    headerBorder  = {180, 216, 168, 255},  -- 清新绿边框
    rowDivider    = {228, 222, 208, 180},  -- 柔和分隔线
    -- 文本
    titleText     = {62, 122, 72, 255},    -- 森林绿标题
    bodyText      = {82, 72, 55, 255},     -- 温暖深棕正文
    subtitleText  = {135, 120, 95, 255},   -- 柔灰棕副标题
    -- 状态
    satisfied     = {68, 160, 90, 255},    -- 叶绿色（满足）
    unsatisfied   = {195, 88, 72, 255},    -- 柔红色（不满足）
    unsatisfiedBg = {255, 240, 237, 255},  -- 浅红底
    -- 图标
    goldOuter     = {255, 210, 70, 255},
    goldInner     = {235, 180, 30, 255},
    tourOuter     = {180, 155, 225, 255},
    tourInner     = {145, 115, 200, 255},
    levelBg       = {98, 182, 125, 255},
    -- 按钮
    btnActive     = {98, 190, 120, 255},
    btnText       = {255, 255, 255, 255},
}

function ExpansionView.Init(deps)
    deps_ = deps or {}
end

--- 构建圆形图标（动森风格，柔和圆润）
---@param iconType string "gold"|"tour"|"level"
local function BuildIcon(iconType)
    if iconType == "gold" then
        return UI.Panel {
            width = 28, height = 28,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel { width = 28, height = 28, borderRadius = 14, backgroundColor = COLORS.goldOuter },
                UI.Panel { position = "absolute", width = 18, height = 18, borderRadius = 9, backgroundColor = COLORS.goldInner },
                UI.Label { position = "absolute", text = "$", fontSize = 13, fontWeight = "bold", fontColor = {255, 248, 210, 255} },
            },
        }
    elseif iconType == "tour" then
        return UI.Panel {
            width = 28, height = 28,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel { width = 28, height = 28, borderRadius = 14, backgroundColor = COLORS.tourOuter },
                UI.Panel { position = "absolute", width = 18, height = 18, borderRadius = 9, backgroundColor = COLORS.tourInner },
                UI.Label { position = "absolute", text = "★", fontSize = 13, fontColor = {240, 235, 255, 255} },
            },
        }
    else
        return UI.Panel {
            width = 28, height = 28,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel { width = 28, height = 28, borderRadius = 14, backgroundColor = COLORS.levelBg },
                UI.Label { position = "absolute", text = "Lv", fontSize = 12, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
            },
        }
    end
end

--- 构建需求行（动森风格，圆润温暖）
local function BuildRequirementRow(label, icon, currentText, requiredText, satisfied, isLast)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 14,
        paddingBottom = 14,
        paddingLeft = 4,
        paddingRight = 4,
        borderBottomWidth = isLast and 0 or 1,
        borderColor = COLORS.rowDivider,
        children = {
            -- 左侧：图标 + 标题 + 未满足标签
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    icon,
                    UI.Label {
                        text = label,
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = COLORS.bodyText,
                    },
                    not satisfied and UI.Panel {
                        paddingTop = 3, paddingBottom = 3,
                        paddingLeft = 8, paddingRight = 8,
                        borderRadius = 10,
                        backgroundColor = COLORS.unsatisfiedBg,
                        children = {
                            UI.Label {
                                text = "未满足",
                                fontSize = 11,
                                fontWeight = "bold",
                                fontColor = COLORS.unsatisfied,
                            },
                        },
                    } or nil,
                },
            },
            -- 右侧：数值
            UI.Label {
                text = currentText .. " / " .. requiredText,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = satisfied and COLORS.satisfied or COLORS.unsatisfied,
            },
        },
    }
end

function ExpansionView.Show()
    if modal_ ~= nil then
        modal_:Close()
    end

    local unlocked = ProgressionSystem.GetUnlockedPlotCount()
    local maxPlots = ProgressionSystem.GetMaxPlotCount()
    local nextPlot = ProgressionSystem.GetNextPlotIndex()
    local level = deps_.getLevel and deps_.getLevel() or ProgressionSystem.GetGardenLevel()
    local gold = deps_.getGold and deps_.getGold() or 0
    local tourValue = deps_.getTourValue and deps_.getTourValue() or ProgressionSystem.GetTourValue()
    local requirement = ProgressionSystem.GetExpansionRequirement(nextPlot)
    local canExpand, reason = ProgressionSystem.CanAffordNextPlot(level, gold, tourValue)
    local isMax = nextPlot == nil or requirement == nil

    modal_ = UI.Modal {
        title = "扩展地块",
        size = "medium",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {22, 22, 22, 22},
        contentGap = 16,
        onClose = function()
            modal_ = nil
        end,
    }

    local children = {
        isMax and UI.Label {
            text = string.format("当前解锁地块：%d（已满）", unlocked),
            fontSize = 16,
            fontWeight = "bold",
            fontColor = COLORS.titleText,
            marginBottom = 2,
        } or UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            marginBottom = 2,
            children = {
                UI.Label {
                    text = string.format("当前解锁地块 %d", unlocked),
                    fontSize = 16,
                    fontWeight = "bold",
                    fontColor = COLORS.bodyText,
                },
                UI.Label {
                    text = "→",
                    fontSize = 16,
                    fontColor = COLORS.subtitleText,
                },
                UI.Label {
                    text = string.format("扩展地块 %d", nextPlot),
                    fontSize = 16,
                    fontWeight = "bold",
                    fontColor = COLORS.titleText,
                },
            },
        },
    }

    if not isMax then
        -- 条件卡片
        table.insert(children, UI.Panel {
            width = "100%",
            padding = 16,
            backgroundColor = COLORS.cardBg,
            borderRadius = 16,
            borderWidth = 2,
            borderColor = COLORS.cardBorder,
            gap = 0,
            children = {
                UI.Label {
                    text = "解锁条件",
                    fontSize = 13,
                    fontColor = COLORS.subtitleText,
                    marginBottom = 4,
                },
                BuildRequirementRow(
                    "玩家等级", BuildIcon("level"),
                    "LV" .. level, "LV" .. requirement.level,
                    level >= requirement.level, false
                ),
                BuildRequirementRow(
                    "金币消耗", BuildIcon("gold"),
                    Format.Gold(gold), Format.Gold(requirement.gold),
                    gold >= requirement.gold, false
                ),
                BuildRequirementRow(
                    "观光值", BuildIcon("tour"),
                    Format.Gold(tourValue), Format.Gold(requirement.tour),
                    tourValue >= requirement.tour, true
                ),
            },
        })

        -- 确认按钮（动森风格圆润大按钮）
        table.insert(children, UI.Button {
            text = canExpand and "确认扩展" or "条件不足",
            width = "100%",
            height = 54,
            fontSize = 18,
            fontWeight = "bold",
            borderRadius = 27,
            backgroundColor = canExpand and COLORS.btnActive or {190, 185, 172, 255},
            fontColor = COLORS.btnText,
            disabled = not canExpand,
            onClick = function()
                if deps_.expandNextPlot and deps_.expandNextPlot() then
                    if modal_ ~= nil then
                        modal_:Close()
                    end
                end
            end,
        })
    end

    modal_:AddContent(UI.Panel {
        width = "100%",
        gap = 16,
        children = children,
    })
    ModalAnim.Apply(modal_, { fixedHeight = 480 })
    modal_:Open()
end

function ExpansionView.Hide()
    if modal_ ~= nil then
        modal_:Close()
    end
end

function ExpansionView.IsOpen()
    return modal_ ~= nil
end

return ExpansionView
