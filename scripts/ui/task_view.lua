-- ============================================================================
-- 每日任务 UI 视图 (Task View)
-- Grow A Garden
-- ============================================================================
-- 只负责每日任务 Modal UI 构建，不持有业务状态。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")

local TaskView = {}

local deps_ = {}

function TaskView.Init(deps)
    deps_ = deps or {}
end

local function BuildRewardIcon(rewardClaimed)
    local seedPackConfig = deps_.seedPackConfig or {}
    local packCfg = seedPackConfig.pack_common or {}
    return UI.Panel {
        alignItems = "center",
        gap = 7,
        children = {
            UI.Panel {
                width = 92,
                height = 100,
                borderRadius = 24,
                backgroundColor = rewardClaimed and {230, 226, 214, 220} or (packCfg.themeColor or {255, 245, 220, 255}),
                borderWidth = 2,
                borderColor = rewardClaimed and {175, 165, 145, 180} or {221, 176, 90, 230},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = 74,
                        height = 84,
                        backgroundImage = packCfg.packIcon or "image/seedpack_icon/seedpack_0.png",
                        backgroundFit = "contain",
                    },
                    UI.Panel {
                        position = "absolute",
                        right = -6,
                        bottom = -6,
                        minWidth = 32,
                        height = 32,
                        paddingLeft = 7,
                        paddingRight = 7,
                        borderRadius = 16,
                        backgroundColor = rewardClaimed and {130, 125, 115, 230} or {78, 172, 110, 255},
                        borderWidth = 3,
                        borderColor = {255, 250, 235, 255},
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "3",
                                fontSize = 16,
                                fontWeight = "bold",
                                fontColor = {255, 255, 255, 255},
                                textAlign = "center",
                            },
                        },
                    },
                },
            },
            UI.Label {
                text = "随机种子包 x3",
                fontSize = 15,
                fontWeight = "bold",
                fontColor = rewardClaimed and {125, 115, 95, 220} or {106, 82, 51, 245},
                textAlign = "center",
            },
        },
    }
end

function TaskView.Open()
    local taskModal = deps_.getTaskModal()
    if taskModal ~= nil then
        taskModal:Close()
    end

    local rows = {}
    local dailyTaskState = deps_.dailyTaskState
    for _, task in ipairs(deps_.dailyTaskConfig) do
        local progress = math.min(dailyTaskState.progress[task.key] or 0, task.target)
        local done = progress >= task.target
        local progressText = progress .. "/" .. task.target
        table.insert(rows, UI.Panel {
            paddingTop = 12,
            paddingBottom = 12,
            paddingLeft = 14,
            paddingRight = 14,
            marginBottom = 10,
            backgroundColor = done and {238, 249, 232, 255} or {255, 252, 238, 255},
            borderRadius = 20,
            borderWidth = 2,
            borderColor = done and {112, 190, 118, 230} or {224, 185, 109, 230},
            gap = 8,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Panel {
                            width = 58,
                            height = 27,
                            borderRadius = 14,
                            backgroundColor = done and {98, 184, 106, 255} or {239, 179, 81, 255},
                            justifyContent = "center",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = done and "完成" or "进行中",
                                    fontSize = 12,
                                    fontWeight = "bold",
                                    fontColor = {255, 255, 245, 255},
                                    textAlign = "center",
                                },
                            },
                        },
                        UI.Panel {
                            flexGrow = 1,
                            flexShrink = 1,
                            children = {
                                UI.Label {
                                    text = task.title,
                                    fontSize = 17,
                                    fontWeight = "bold",
                                    fontColor = {83, 62, 42, 255},
                                },
                            },
                        },
                        UI.Label {
                            text = progressText,
                            width = 46,
                            fontSize = 15,
                            fontWeight = "bold",
                            fontColor = done and {76, 154, 84, 255} or {142, 103, 53, 255},
                            textAlign = "right",
                        },
                    },
                },
                UI.Panel {
                    height = 8,
                    borderRadius = 4,
                    backgroundColor = {232, 220, 185, 180},
                    children = {
                        UI.Panel {
                            width = tostring(math.floor(math.min(1, progress / task.target) * 100)) .. "%",
                            height = 8,
                            borderRadius = 4,
                            backgroundColor = done and {102, 190, 112, 255} or {242, 188, 86, 255},
                        },
                    },
                },
            },
        })
    end

    local canClaim = deps_.areAllDailyTasksCompleted() and not dailyTaskState.rewardClaimed
    local rewardClaimed = dailyTaskState.rewardClaimed
    taskModal = UI.Modal {
        title = "每日任务",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 16, 16},
        onClose = function() deps_.setTaskModal(nil) end,
    }
    deps_.setTaskModal(taskModal)

    taskModal:AddContent(UI.Panel {
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 12,
        paddingRight = 12,
        gap = 12,
        backgroundColor = {255, 248, 226, 245},
        borderRadius = 24,
        children = {
            UI.Panel {
                children = rows,
            },
            UI.Panel {
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 14,
                paddingRight = 14,
                backgroundColor = rewardClaimed and {233, 229, 216, 245} or {255, 240, 184, 255},
                borderRadius = 22,
                borderWidth = 2,
                borderColor = rewardClaimed and {170, 160, 140, 210} or {224, 176, 78, 235},
                alignItems = "center",
                gap = 10,
                children = {
                    BuildRewardIcon(rewardClaimed),
                    rewardClaimed and UI.Label {
                        text = "已领取",
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = {110, 100, 82, 230},
                        textAlign = "center",
                    } or UI.Panel { height = 0 },
                },
            },
            UI.Panel {
                alignItems = "center",
                marginTop = 4,
                marginBottom = 26,
                children = {
                    UI.Button {
                        text = dailyTaskState.rewardClaimed and "已领取" or "领取",
                        width = 116,
                        height = 48,
                        fontSize = 18,
                        fontWeight = "bold",
                        variant = "primary",
                        borderRadius = 20,
                        disabled = not canClaim,
                        disabledBackgroundColor = {214, 205, 186, 255},
                        textColor = canClaim and {255, 255, 255, 255} or {124, 113, 94, 255},
                        onClick = function()
                            deps_.suppressWorldTap()
                            if canClaim and deps_.claimDailyReward() then
                                FloatingToast.Show("领取成功! 获得随机种子包 x3")
                                local currentModal = deps_.getTaskModal()
                                if currentModal ~= nil then
                                    currentModal:Close()
                                    deps_.setTaskModal(nil)
                                end
                                deps_.rebuildUI()
                            end
                        end,
                    },
                },
            },
        },
    })
    ModalAnim.Apply(taskModal, { fixedHeight = 620 })
    taskModal:Open()
end

return TaskView
