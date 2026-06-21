-- ============================================================================
-- 每日任务 UI 视图 (Task View)
-- Grow A Garden
-- ============================================================================
-- 只负责每日任务 Modal UI 构建，不持有业务状态。
-- ============================================================================

local UI = require("urhox-libs/UI")

local TaskView = {}

local deps_ = {}

function TaskView.Init(deps)
    deps_ = deps or {}
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
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            padding = 10,
            marginBottom = 6,
            backgroundColor = done and {232, 246, 232, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = 1,
            borderColor = done and {94, 194, 131, 255} or {195, 180, 150, 180},
            children = {
                UI.Label { text = done and "完成" or "进行中", width = 54, fontSize = 12, fontWeight = "bold", fontColor = done and {70, 160, 90, 255} or {130, 110, 85, 255} },
                UI.Label { text = task.title, flexGrow = 1, fontSize = 13, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                UI.Label { text = progress .. "/" .. task.target, width = 48, fontSize = 13, fontWeight = "bold", fontColor = {90, 150, 100, 255}, textAlign = "right" },
            },
        })
    end

    local canClaim = deps_.areAllDailyTasksCompleted() and not dailyTaskState.rewardClaimed
    taskModal = UI.Modal {
        title = "每日任务",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        onClose = function() deps_.setTaskModal(nil) end,
    }
    deps_.setTaskModal(taskModal)

    taskModal:AddContent(UI.Panel {
        padding = 10,
        gap = 10,
        children = {
            UI.Panel { children = rows },
            UI.Label { text = dailyTaskState.rewardClaimed and "今日奖励已领取" or "全部完成可领取日常普通种子礼包 x1", fontSize = 12, fontColor = {120, 100, 80, 220}, textAlign = "center" },
            UI.Button {
                text = dailyTaskState.rewardClaimed and "已领取" or "领取礼包",
                height = 40,
                fontSize = 14,
                variant = "primary",
                disabled = not canClaim,
                onClick = function()
                    deps_.suppressWorldTap()
                    if canClaim and deps_.claimDailyReward() then
                        deps_.showToast("获得日常普通种子礼包")
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
    })
    taskModal:Open()
end

return TaskView
