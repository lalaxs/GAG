-- ============================================================================
-- 限时活动 UI 视图 (Activity View)
-- Grow A Garden
-- ============================================================================
-- 根据当前 3 日循环活动展示活动内容、兑换、抽包和本地排行榜。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")

local ActivityView = {}

local deps_ = {}
local modal_ = nil

function ActivityView.Init(deps)
    deps_ = deps or {}
end

function ActivityView.IsOpen()
    return modal_ ~= nil
end

local function BuildBadge(text, bg, color)
    return UI.Panel {
        paddingTop = 5,
        paddingBottom = 5,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 14,
        backgroundColor = bg or {245, 230, 190, 255},
        children = {
            UI.Label { text = text, fontSize = 12, fontWeight = "bold", fontColor = color or {85, 62, 38, 255} },
        },
    }
end

local function BuildStatCard(title, value, color)
    return UI.Panel {
        flexGrow = 1,
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 12,
        paddingRight = 12,
        borderRadius = 18,
        backgroundColor = color or {255, 248, 230, 255},
        gap = 3,
        children = {
            UI.Label { text = title, fontSize = 12, fontColor = {112, 88, 58, 230}, textAlign = "center" },
            UI.Label { text = tostring(value), fontSize = 20, fontWeight = "bold", fontColor = {68, 48, 32, 255}, textAlign = "center" },
        },
    }
end

local function BuildLeaderboard(activityId)
    local rows = {}
    for index, row in ipairs(deps_.getLeaderboard(activityId)) do
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 7,
            paddingBottom = 7,
            paddingLeft = 10,
            paddingRight = 10,
            marginBottom = 5,
            borderRadius = 14,
            backgroundColor = row.self and {255, 238, 178, 255} or {255, 252, 242, 245},
            children = {
                UI.Label { text = tostring(index), width = 28, fontSize = 14, fontWeight = "bold", fontColor = {120, 85, 44, 255} },
                UI.Label { text = row.name, flexGrow = 1, fontSize = 14, fontWeight = row.self and "bold" or "normal", fontColor = {72, 54, 38, 255} },
                UI.Label { text = tostring(row.score), width = 70, fontSize = 14, fontWeight = "bold", fontColor = {78, 135, 94, 255}, textAlign = "right" },
            },
        })
    end

    return UI.Panel {
        paddingTop = 12,
        paddingBottom = 10,
        paddingLeft = 12,
        paddingRight = 12,
        borderRadius = 22,
        backgroundColor = {246, 240, 224, 245},
        children = {
            UI.Label { text = "活动排行榜", fontSize = 17, fontWeight = "bold", fontColor = {76, 56, 38, 255}, marginBottom = 9 },
            UI.Panel { children = rows },
        },
    }
end

local function BuildLimitedSeeds(activity)
    local chips = {}
    for _, plantIndex in ipairs(activity.limitedSeeds or {}) do
        local plant = deps_.plants[plantIndex]
        if plant ~= nil then
            table.insert(chips, BuildBadge(plant.name, activity.chipColor or {235, 220, 250, 255}, {78, 58, 98, 255}))
        end
    end
    return UI.Panel {
        gap = 8,
        children = {
            UI.Label { text = "限定作物", fontSize = 16, fontWeight = "bold", fontColor = {74, 54, 36, 255} },
            UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 7, children = chips },
        },
    }
end

local function Reopen()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end
    ActivityView.Open()
end

local function BuildSweet(activity, state)
    local submitRows = {}
    local submitItems = deps_.getSweetSubmitItems()
    if #submitItems == 0 then
        table.insert(submitRows, UI.Label {
            text = "背包中暂无糖果/蜂蜜变异作物。活动期间播种更容易出现这两类变异。",
            fontSize = 13,
            fontColor = {118, 92, 62, 230},
        })
    else
        for index, entry in ipairs(submitItems) do
            if index <= 4 then
                local item = entry.item
                table.insert(submitRows, UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    paddingTop = 8,
                    paddingBottom = 8,
                    paddingLeft = 10,
                    paddingRight = 10,
                    marginBottom = 6,
                    borderRadius = 16,
                    backgroundColor = {255, 250, 238, 255},
                    children = {
                        UI.Label { text = item.name, flexGrow = 1, flexShrink = 1, fontSize = 13, fontWeight = "bold", fontColor = {76, 52, 38, 255} },
                        UI.Label { text = "+" .. entry.value, width = 42, fontSize = 13, fontWeight = "bold", fontColor = {224, 118, 68, 255}, textAlign = "right" },
                        UI.Button {
                            text = "上交",
                            width = 62,
                            height = 32,
                            fontSize = 12,
                            borderRadius = 13,
                            variant = "primary",
                            onClick = function()
                                deps_.suppressWorldTap()
                                local ok, err = deps_.submitSweetCrop(item)
                                if not ok and deps_.showToast then deps_.showToast(err or "上交失败") end
                                deps_.rebuildUI()
                                Reopen()
                            end,
                        },
                    },
                })
            end
        end
    end

    local rewardRows = {}
    for _, reward in ipairs(activity.exchangeRewards or {}) do
        local claimed = (state.exchanged[reward.id] or 0)
        local limitText = reward.limit and string.format("%d/%d", claimed, reward.limit) or "不限"
        table.insert(rewardRows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            paddingTop = 8,
            paddingBottom = 8,
            paddingLeft = 10,
            paddingRight = 10,
            marginBottom = 6,
            borderRadius = 16,
            backgroundColor = {255, 244, 220, 255},
            children = {
                UI.Label { text = reward.name, flexGrow = 1, flexShrink = 1, fontSize = 13, fontWeight = "bold", fontColor = {78, 52, 35, 255} },
                UI.Label { text = reward.cost .. "甜蜜", width = 74, fontSize = 12, fontWeight = "bold", fontColor = {205, 105, 58, 255}, textAlign = "right" },
                UI.Label { text = limitText, width = 42, fontSize = 12, fontColor = {110, 86, 62, 210}, textAlign = "center" },
                UI.Button {
                    text = "兑换",
                    width = 62,
                    height = 32,
                    fontSize = 12,
                    borderRadius = 13,
                    disabled = state.value < reward.cost or (reward.limit ~= nil and claimed >= reward.limit),
                    onClick = function()
                        deps_.suppressWorldTap()
                        local ok, err = deps_.exchangeSweetReward(reward.id)
                        if not ok and deps_.showToast then deps_.showToast(err or "兑换失败") end
                        deps_.rebuildUI()
                        Reopen()
                    end,
                },
            },
        })
    end

    return UI.Panel {
        gap = 12,
        children = {
            UI.Panel { flexDirection = "row", gap = 8, children = {
                BuildStatCard("当前甜蜜值", state.value, {255, 236, 214, 255}),
                BuildStatCard("累计上交", state.submitted, {255, 242, 224, 255}),
            } },
            BuildLimitedSeeds(activity),
            UI.Panel {
                paddingTop = 12,
                paddingBottom = 10,
                paddingLeft = 12,
                paddingRight = 12,
                borderRadius = 22,
                backgroundColor = {255, 244, 228, 245},
                children = {
                    UI.Label { text = "上交糖果/蜂蜜变异作物", fontSize = 16, fontWeight = "bold", fontColor = {82, 55, 38, 255}, marginBottom = 8 },
                    UI.Panel { children = submitRows },
                },
            },
            UI.Panel {
                paddingTop = 12,
                paddingBottom = 10,
                paddingLeft = 12,
                paddingRight = 12,
                borderRadius = 22,
                backgroundColor = {255, 238, 208, 245},
                children = {
                    UI.Label { text = "甜蜜兑换", fontSize = 16, fontWeight = "bold", fontColor = {82, 55, 38, 255}, marginBottom = 8 },
                    UI.Panel { children = rewardRows },
                },
            },
            BuildLeaderboard("sweet"),
        },
    }
end

local function BuildAlien(activity, state)
    return UI.Panel {
        gap = 12,
        children = {
            UI.Panel { flexDirection = "row", gap = 8, children = {
                BuildStatCard("外星基因", state.genes, {226, 255, 228, 255}),
                BuildStatCard("累计基因", state.totalGenes, {232, 244, 255, 255}),
                BuildStatCard("抽取次数", state.drawCount, {240, 232, 255, 255}),
            } },
            BuildLimitedSeeds(activity),
            UI.Panel {
                paddingTop = 13,
                paddingBottom = 13,
                paddingLeft = 14,
                paddingRight = 14,
                borderRadius = 22,
                backgroundColor = {236, 250, 238, 245},
                gap = 10,
                children = {
                    UI.Label { text = "收获任意作物都有概率获得外星基因，稀有作物与变异作物获得更多。", fontSize = 13, fontColor = {60, 92, 72, 235} },
                    UI.Panel { flexDirection = "row", gap = 10, children = {
                        UI.Button {
                            text = "单抽 10基因", flexGrow = 1, height = 42, fontSize = 15, fontWeight = "bold", borderRadius = 16, variant = "primary",
                            disabled = state.genes < (activity.drawCost or 10),
                            onClick = function()
                                deps_.suppressWorldTap()
                                local ok, err = deps_.drawAlienPack(1)
                                if not ok and deps_.showToast then deps_.showToast(err or "抽取失败") end
                                deps_.rebuildUI()
                                Reopen()
                            end,
                        },
                        UI.Button {
                            text = "十连 95基因", flexGrow = 1, height = 42, fontSize = 15, fontWeight = "bold", borderRadius = 16,
                            disabled = state.genes < (activity.drawCostTen or 95),
                            onClick = function()
                                deps_.suppressWorldTap()
                                local ok, err = deps_.drawAlienPack(10)
                                if not ok and deps_.showToast then deps_.showToast(err or "抽取失败") end
                                deps_.rebuildUI()
                                Reopen()
                            end,
                        },
                    } },
                },
            },
            BuildLeaderboard("alien"),
        },
    }
end

local function BuildDark(activity, state)
    return UI.Panel {
        gap = 12,
        children = {
            UI.Panel { flexDirection = "row", gap = 8, children = {
                BuildStatCard("吞噬收获", state.devourHarvestCount, {232, 224, 246, 255}),
                BuildStatCard("黑暗种子", state.darkSeedDrops, {222, 216, 232, 255}),
            } },
            BuildLimitedSeeds(activity),
            UI.Panel {
                paddingTop = 13,
                paddingBottom = 13,
                paddingLeft = 14,
                paddingRight = 14,
                borderRadius = 22,
                backgroundColor = {234, 226, 240, 245},
                gap = 8,
                children = {
                    UI.Label { text = "活动期间可能出现吞噬变异，虚空变异概率也会提高。", fontSize = 14, fontWeight = "bold", fontColor = {68, 48, 82, 255} },
                    UI.Label { text = "收获吞噬变异作物时，有概率掉落噬光苔冠、裂隙肉芽、终夜王冠种子。", fontSize = 13, fontColor = {88, 70, 104, 235} },
                },
            },
            BuildLeaderboard("dark"),
        },
    }
end

function ActivityView.Open()
    if modal_ ~= nil then
        modal_:Close()
        modal_ = nil
    end

    local activityId, activity, state = deps_.getActiveActivity()
    if activity == nil then return end

    modal_ = UI.Modal {
        title = activity.name,
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 18, 16},
        onClose = function() modal_ = nil end,
    }

    local content = nil
    if activityId == "sweet" then
        content = BuildSweet(activity, state)
    elseif activityId == "alien" then
        content = BuildAlien(activity, state)
    else
        content = BuildDark(activity, state)
    end

    modal_:AddContent(UI.Panel {
        paddingTop = 12,
        paddingBottom = 14,
        paddingLeft = 12,
        paddingRight = 12,
        gap = 12,
        borderRadius = 26,
        backgroundColor = activity.backgroundColor or {255, 248, 232, 245},
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    BuildBadge(activity.badge or "限时", activity.badgeColor or {255, 218, 150, 255}),
                    UI.Label { text = deps_.getTimeLeftText(), flexGrow = 1, fontSize = 14, fontWeight = "bold", fontColor = {94, 68, 42, 255}, textAlign = "right" },
                },
            },
            UI.Label { text = activity.desc or "", fontSize = 13, fontColor = {88, 68, 50, 230} },
            content,
        },
    })

    ModalAnim.Apply(modal_, { fixedHeight = 680 })
    modal_:Open()
end

function ActivityView.BuildButton()
    return UI.Button {
        text = "活动",
        width = 69,
        height = 66,
        paddingTop = 0,
        paddingRight = 16,
        paddingBottom = 5,
        paddingLeft = 16,
        fontSize = 15,
        fontWeight = "bold",
        backgroundColor = {255, 244, 218, 245},
        fontColor = {190, 92, 72, 255},
        borderRadius = 14,
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            ActivityView.Open()
        end,
    }
end

return ActivityView
