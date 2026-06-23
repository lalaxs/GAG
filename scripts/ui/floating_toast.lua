-- ============================================================================
-- 浮动飘字模块 (Floating Toast)
-- 注册为 UI 全局组件，在所有 Modal 之上渲染（使用 UI 系统的 NanoVG 上下文）
-- 效果：屏幕中央出现文字，向上漂浮并逐渐淡出消失
-- ============================================================================

local UI = require("urhox-libs/UI")

local FloatingToast = {}

-- 活跃的飘字列表
local activeToasts_ = {}
local registered_ = false
local fontCreated_ = false

-- 配置
local FLOAT_DURATION = 1.2    -- 总持续时间（秒）
local FLOAT_DISTANCE = 55     -- 向上漂浮的像素距离
local FADE_START = 0.45       -- 从总时间的 45% 处开始淡出

-- 全局组件实例（提供 Update 和 Render 方法给 UI 系统调用）
local component_ = {}

function component_:Update(dt)
    if #activeToasts_ == 0 then return end

    local i = 1
    while i <= #activeToasts_ do
        local toast = activeToasts_[i]
        toast.timer = toast.timer + dt
        if toast.timer >= toast.duration then
            table.remove(activeToasts_, i)
        else
            i = i + 1
        end
    end
end

function component_:Render(nvg)
    if #activeToasts_ == 0 then return end
    if nvg == nil then return end

    -- 使用 UI 系统已注册的 "sans" 字体（MiSans-Regular）

    local screenW = UI.GetWidth() or 400
    local screenH = UI.GetHeight() or 800

    for _, toast in ipairs(activeToasts_) do
        local progress = toast.timer / toast.duration

        -- 向上漂浮偏移（缓出曲线，开始快后来慢）
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        local offsetY = -FLOAT_DISTANCE * easedProgress

        -- 淡出
        local alpha = 1.0
        if progress > FADE_START then
            alpha = 1.0 - (progress - FADE_START) / (1.0 - FADE_START)
        end
        -- 入场：前 10% 时间渐入
        if progress < 0.1 then
            alpha = alpha * (progress / 0.1)
        end

        if alpha <= 0.01 then goto continue end

        local centerX = screenW / 2
        local centerY = screenH * 0.35 + offsetY

        -- 测量文字宽度（使用 UI 系统的 sans 字体）
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, toast.fontSize)
        local textW = nvgTextBounds(nvg, 0, 0, toast.text)

        local padH = 22
        local padV = 13
        local boxW = textW + padH * 2
        local boxH = toast.fontSize + padV * 2
        local boxX = centerX - boxW / 2
        local boxY = centerY - boxH / 2
        local radius = boxH / 2  -- 胶囊形圆角
        local border = 3.5      -- 粗描边

        -- 动森风：奶油色背景 + 粗暖棕描边
        -- 外描边
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, boxX - border, boxY - border, boxW + border * 2, boxH + border * 2, radius + border)
        nvgFillColor(nvg, nvgRGBA(95, 75, 45, math.floor(220 * alpha)))
        nvgFill(nvg)

        -- 内背景（温暖奶油色）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, boxX, boxY, boxW, boxH, radius)
        nvgFillColor(nvg, nvgRGBA(255, 252, 238, math.floor(250 * alpha)))
        nvgFill(nvg)

        -- 文字（深暖棕色）
        nvgFillColor(nvg, nvgRGBA(68, 52, 30, math.floor(255 * alpha)))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg, centerX, centerY, toast.text)

        ::continue::
    end
end

--- 确保组件已注册
local function EnsureRegistered()
    if not registered_ then
        UI.RegisterGlobalComponent("FloatingToast", component_)
        registered_ = true
    end
end

--- 显示一条浮动飘字
---@param text string 显示文本
---@param opts table|nil 可选配置 { fontSize, duration }
function FloatingToast.Show(text, opts)
    EnsureRegistered()
    opts = opts or {}
    local toast = {
        text = text,
        fontSize = opts.fontSize or 18,
        timer = 0,
        duration = opts.duration or FLOAT_DURATION,
    }
    table.insert(activeToasts_, toast)
end

--- 每帧更新（兼容旧接口，实际由全局组件自动更新）
function FloatingToast.Update(dt)
    -- 由 UI 全局组件机制自动调用 component_:Update，这里保持空以兼容旧调用
end

--- 获取飘字容器控件（兼容旧接口，返回空面板）
function FloatingToast.GetContainer()
    return UI.Panel { width = 0, height = 0 }
end

return FloatingToast
