-- ============================================================================
-- 统一 Modal 动画工具 (Modal Animation Utility)
-- Grow A Garden
-- ============================================================================
-- 为所有 Modal 弹窗提供一致的动画效果：
--   1. 无缩放/弹跳，纯透明度渐显
--   2. 背景面板先出现，内容延迟显示（alpha >= 阈值后才渲染内容）
--   3. 动画速度统一可调
--
-- 用法：
--   local ModalAnim = require("ui.modal_anim")
--   local modal = UI.Modal { ... }
--   ModalAnim.Apply(modal)        -- 应用统一动画
--   modal:Open()
-- ============================================================================

local ModalAnim = {}

--- 默认配置
local DEFAULT_SPEED = 3.0           -- 动画速度（越大越快）
local CONTENT_SHOW_THRESHOLD = 0.7  -- alpha 达到此值后才显示内容

--- 将统一的透明度渐显动画应用到一个 Modal 实例上
---@param modal table UI.Modal 实例
---@param opts table|nil 可选配置 { speed = number, contentThreshold = number, fixedHeight = number }
function ModalAnim.Apply(modal, opts)
    if modal == nil then return end
    opts = opts or {}
    local speed = opts.speed or DEFAULT_SPEED
    local contentThreshold = opts.contentThreshold or CONTENT_SHOW_THRESHOLD
    local fixedHeight = opts.fixedHeight

    -- 重写 Update：去掉默认弹簧/缓动，改为线性 alpha 过渡
    modal.Update = function(self, dt)
        if self.animProgress_ < self.targetAnimProgress_ then
            self.animProgress_ = math.min(self.targetAnimProgress_, self.animProgress_ + dt * speed)
        elseif self.animProgress_ > self.targetAnimProgress_ then
            self.animProgress_ = math.max(self.targetAnimProgress_, self.animProgress_ - dt * speed)
        end
        -- 更新子组件树
        local function updateTree(widget)
            if widget.Update then widget:Update(dt) end
            for _, child in ipairs(widget.children or {}) do updateTree(child) end
        end
        if self.contentContainer_ and #self.contentContainer_.children > 0 then
            updateTree(self.contentContainer_)
        end
        if self.footerWidget_ then updateTree(self.footerWidget_) end
    end

    -- 重写渲染：去掉缩放动画，只保留透明度渐变
    modal.RenderModalContent = function(self, nvg)
        local UI_mod = require("urhox-libs/UI/Core/UI")
        local Theme = require("urhox-libs/UI/Core/Theme")
        local Widget = require("urhox-libs/UI/Core/Widget")
        local screenWidth = UI_mod.GetWidth() or 800
        local screenHeight = UI_mod.GetHeight() or 600
        local borderRadius = self.borderRadius_
        local title = self.title_
        local showCloseButton = self.showCloseButton_

        local headerHeight = 56
        local cp = self.props.contentPadding or 16
        local cpTop, cpRight, cpBottom, cpLeft
        if type(cp) == "table" then
            cpTop, cpRight, cpBottom, cpLeft = cp[1], cp[2], cp[3], cp[4]
        else
            cpTop, cpRight, cpBottom, cpLeft = cp, cp, cp, cp
        end

        -- 尺寸计算
        local modalWidth = opts.fixedWidth or (screenWidth * (opts.widthRatio or 0.90))
        modalWidth = math.min(modalWidth, screenWidth * (opts.maxWidthRatio or 0.96))
        local modalMaxHeight = screenHeight * (opts.maxHeightRatio or 0.90)

        local footerHeight = 0
        if self.footerWidget_ then
            local fp = self.props.footerPadding or {12, 16, 12, 16}
            local fpTop, fpRight, fpBottom, fpLeft = fp[1], fp[2], fp[3], fp[4]
            local footerContentWidth = modalWidth - fpLeft - fpRight
            YGNodeCalculateLayout(self.footerWidget_.node, footerContentWidth, YGUndefined, YGDirectionLTR)
            local measuredFooter = YGNodeLayoutGetHeight(self.footerWidget_.node)
            footerHeight = math.max(64, measuredFooter + fpTop + fpBottom)
        end

        -- 核心：alpha 控制所有渐显，无缩放
        local alpha = self.animProgress_

        -- 遮罩（平方缓入）
        local overlayAlpha = math.floor(alpha * alpha * 160)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, screenWidth, screenHeight)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, overlayAlpha))
        nvgFill(nvg)

        -- 计算 Modal 尺寸和位置
        local contentAreaWidth = modalWidth - cpLeft - cpRight
        local modalHeight
        if fixedHeight ~= nil then
            modalHeight = math.min(fixedHeight, modalMaxHeight)
        else
            modalHeight = self:CalculateContentHeight(contentAreaWidth)
                + cpTop + cpBottom
                + (title and headerHeight or 0)
                + (self.footerWidget_ and footerHeight or 0)
            modalHeight = math.min(modalHeight, modalMaxHeight)
        end

        local modalX = (screenWidth - modalWidth) / 2
        local modalY = (screenHeight - modalHeight) / 2 + (opts.offsetY or 0)

        nvgSave(nvg)

        -- 阴影
        local boxShadow = self.props.boxShadow
        if boxShadow == false then
            -- 无阴影
        elseif boxShadow then
            nvgSave(nvg)
            nvgGlobalAlpha(nvg, alpha)
            local geom = self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius)
            self:RenderBoxShadows(nvg, geom, boxShadow)
            nvgRestore(nvg)
        else
            nvgBeginPath(nvg)
            self:CreateShapePath(nvg, self:GetShapeGeometry(
                { x = modalX - 4, y = modalY - 2, w = modalWidth + 8, h = modalHeight + 12 },
                nil,
                Widget.OffsetRadius(borderRadius, 4)
            ))
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(60 * alpha)))
            nvgFill(nvg)
        end

        -- 背景
        local bgColor = Theme.Color("surface")
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius))
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], math.floor(255 * alpha)))
        nvgFill(nvg)

        -- 边框
        local borderColor = self.props.borderColor or Theme.Color("border")
        local borderAlpha = self.props.borderColor and (borderColor[4] or 255) or 100
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = modalX, y = modalY, w = modalWidth, h = modalHeight }, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], math.floor(borderAlpha * alpha)))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)

        self.modalLayout_ = { x = modalX, y = modalY, w = modalWidth, h = modalHeight }

        -- 标题 / 关闭按钮
        local contentY = modalY
        if title then
            contentY = self:RenderHeader(nvg, modalX, modalY, modalWidth, title, showCloseButton, alpha)
        elseif showCloseButton then
            self:RenderCloseButton(nvg, modalX + modalWidth - 44, modalY + 8, alpha)
            contentY = modalY + 16
        end

        -- 内容区域（等背景渐显达到阈值后才显示）
        local footerHeightActual = self.footerWidget_ and footerHeight or 0
        local clipY = contentY
        local clipHeight = math.max(0, modalHeight - (contentY - modalY) - footerHeightActual)

        if self.contentContainer_ and #self.contentContainer_.children > 0 and alpha >= contentThreshold then
            YGNodeCalculateLayout(self.contentContainer_.node, contentAreaWidth, clipHeight, YGDirectionLTR)

            self.contentContainer_.renderOffsetX_ = modalX + cpLeft
            self.contentContainer_.renderOffsetY_ = contentY
            self.contentContainer_.renderWidth_ = contentAreaWidth
            self.contentContainer_.renderHeight_ = clipHeight

            nvgSave(nvg)
            nvgIntersectScissor(nvg, modalX, clipY, modalWidth, clipHeight)
            UI_mod.RenderWidgetSubtree(self.contentContainer_, nvg)
            nvgRestore(nvg)
        end

        -- Footer
        if self.footerWidget_ then
            self:RenderFooter(nvg, modalX, modalY + modalHeight - footerHeight, modalWidth, footerHeight, alpha)
        end

        nvgRestore(nvg)
    end
end

return ModalAnim
