-- ============================================================================
-- 地块弹出动画模块
-- Grow A Garden
-- ============================================================================
-- 只管理地块 scale 弹出动画，不改变地块显示逻辑和视觉参数。
-- ============================================================================

local PlotBounceAnimator = {}

local anims_ = {}           -- { plotIndex, timer, duration, done }
local delay_ = 0.12         -- 每个地块间隔时间
local duration_ = 0.4       -- 单个地块弹出动画时长
local active_ = false
local initDelay_ = 0.8      -- 进入游戏后等待时间再开始弹出

--- 弹性缓动函数 (overshoot回弹)
local function EaseOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function PlotBounceAnimator.IsActive()
    return active_
end

function PlotBounceAnimator.StartAll(plots)
    anims_ = {}
    active_ = true
    for i = 1, #plots do
        local plot = plots[i]
        if plot ~= nil and plot.unlocked then
            table.insert(anims_, {
                plotIndex = i,
                delay = (i - 1) * delay_,
                timer = 0,
                duration = duration_,
                started = false,
                done = false,
            })
        end
    end
end

function PlotBounceAnimator.StartSingle(plots, plotIndex)
    local plot = plots[plotIndex]
    if plot == nil or plot.node == nil or not plot.unlocked then return end
    plot.node.scale = Vector3(0, 0, 0)
    initDelay_ = 0
    anims_ = {{
        plotIndex = plotIndex,
        delay = 0,
        timer = 0,
        duration = duration_,
        started = false,
        done = false,
    }}
    active_ = true
end

function PlotBounceAnimator.Update(plots, dt)
    if not active_ then return end
    -- 初始等待
    if initDelay_ > 0 then
        initDelay_ = initDelay_ - dt
        return
    end
    local allDone = true
    for _, anim in ipairs(anims_) do
        if not anim.done then
            anim.delay = anim.delay - dt
            if anim.delay <= 0 then
                if not anim.started then
                    anim.started = true
                    anim.timer = 0
                end
                anim.timer = anim.timer + dt
                local t = math.min(anim.timer / anim.duration, 1.0)
                local progress = EaseOutBack(t)
                local plot = plots[anim.plotIndex]
                if plot ~= nil and plot.node ~= nil then
                    local target = plot.targetScale
                    plot.node.scale = Vector3(
                        target.x * progress,
                        target.y * progress,
                        target.z * progress
                    )
                end
                if t >= 1.0 then
                    anim.done = true
                end
            end
            allDone = false
        end
    end
    if allDone then
        active_ = false
    end
end

return PlotBounceAnimator
