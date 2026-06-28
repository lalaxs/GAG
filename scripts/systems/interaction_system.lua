-- ============================================================================
-- 世界交互系统 (Interaction System)
-- Grow A Garden
-- ============================================================================
-- 管理世界点击命中、鼠标/触摸相机手势与键盘快捷操作。
-- UI 只需要调用 SuppressNextWorldTap 来避免按钮点击穿透到世界。
-- ============================================================================

local FloatingToast = require("ui.floating_toast")
local AudioSystem = require("systems.audio_system")

local InteractionSystem = {}

local config_ = nil
local cameraSystem_ = nil
local deps_ = {}
local suppressNextWorldTap_ = false
local touchGestureActive_ = false
local lastPinchDistance_ = 0

--- 检查是否有 UI 弹窗正在拦截交互（Modal 等）
local function IsUIBlocking()
    if deps_.isUIBlocking then
        return deps_.isUIBlocking()
    end
    return false
end

function InteractionSystem.Init(config, cameraSystem, deps)
    config_ = config
    cameraSystem_ = cameraSystem
    deps_ = deps or {}
    suppressNextWorldTap_ = false
    touchGestureActive_ = false
    lastPinchDistance_ = 0
end

function InteractionSystem.SuppressNextWorldTap()
    suppressNextWorldTap_ = true
end

local function IsPlotDisplayToolbarArea(x, y)
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local logicalX = x / dpr
    local logicalY = y / dpr
    local left = logicalW - 14 - 56 - 12
    local right = logicalW
    local top = 152 - 12
    local bottom = 152 + 5 * 40 + 4 * 8 + 12
    return logicalX >= left and logicalX <= right and logicalY >= top and logicalY <= bottom
end

local function IsWorldTapArea(x, y)
    if IsPlotDisplayToolbarArea(x, y) then
        print(string.format("[交互] 忽略右上地块工具栏区域触摸 x=%d y=%d", x, y))
        return false
    end

    local dpr = graphics:GetDPR()
    local h = graphics:GetHeight() / dpr
    local logicalY = y / dpr
    local bottomReserved = 86
    if cameraSystem_.GetViewMode() == cameraSystem_.ViewMode.PLANT then
        local tab = deps_.getPlantTab and deps_.getPlantTab() or "seed"
        if tab == "bag" then
            bottomReserved = 520
        elseif tab == "harvest" then
            bottomReserved = 420
        else
            bottomReserved = 245
        end
    end
    return logicalY > 170 and logicalY < h - bottomReserved
end

local function PlotHitFromScreen(x, y)
    local camera = deps_.getCamera and deps_.getCamera() or nil
    if camera == nil then return nil, nil end
    if not IsWorldTapArea(x, y) then return nil, nil end

    local plots = deps_.getPlots and deps_.getPlots() or nil
    if plots == nil then return nil, nil end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local ray = camera:GetScreenRay(x / w, y / h)
    if math.abs(ray.direction.y) < 0.001 then return nil, nil end

    local surfaceY = 0.92
    local t = (surfaceY - ray.origin.y) / ray.direction.y
    if t <= 0 then return nil, nil end
    local hit = ray.origin + ray.direction * t

    local bestIndex = nil
    local bestDist = 9999
    local bestLocal = nil
    for i = 1, #plots do
        local plot = plots[i]
        if plot ~= nil and plot.visible ~= false then
            local pos = deps_.plotWorldPosition(i)
            local dx = hit.x - pos.x
            local dz = hit.z - pos.z
            local dist = dx * dx + dz * dz
            if dist < bestDist then
                bestDist = dist
                bestIndex = i
                bestLocal = Vector3(dx / config_.PlotSize, 0, dz / config_.PlotSize)
            end
        end
    end

    local plantableHalf = config_.PlantableHalf or 0.60
    if bestIndex ~= nil then
        -- 地块视觉是方形/圆角方形，播种位置也由 CropSystem.ClampToPlot 按 X/Z 方形范围限制。
        -- 这里不能用圆形半径判断，否则四个角落会看起来在土地上但永远点不中。
        if math.abs(bestLocal.x) <= plantableHalf and math.abs(bestLocal.z) <= plantableHalf then
            return bestIndex, bestLocal, nil
        end
        if cameraSystem_.GetViewMode() == cameraSystem_.ViewMode.PLANT and deps_.getPlantTab ~= nil and deps_.getPlantTab() == "harvest" then
            return bestIndex, bestLocal, "edge"
        end
        return nil, nil, "edge"
    end
    return nil, nil, nil
end

local function HandleWorldTap(x, y)
    if suppressNextWorldTap_ then
        suppressNextWorldTap_ = false
        return
    end

    local plotIndex, localPos, missReason = PlotHitFromScreen(x, y)
    if plotIndex == nil then
        if missReason == "edge" and cameraSystem_.GetViewMode() == cameraSystem_.ViewMode.PLANT and deps_.getPlantTab ~= nil and deps_.getPlantTab() == "seed" then
            local text = "请换个地方播种"
            if deps_.showToast ~= nil then deps_.showToast(text) end
            FloatingToast.Show(text)
        end
        return
    end

    if cameraSystem_.GetViewMode() == cameraSystem_.ViewMode.FARM then
        deps_.setSelectedPlot(plotIndex)
        deps_.refreshSelection()
        deps_.showToast("已选中田地，可查看状态；点击下方开始种植后操作")
        deps_.refreshUI(true)
    else
        deps_.performPlotAction(plotIndex, localPos)
    end
end

function InteractionSystem.HandleMouseButtonDown(eventData)
    if IsUIBlocking() then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function InteractionSystem.HandleMouseMove(eventData)
    if IsUIBlocking() then return end
    if cameraSystem_.GetViewMode() ~= cameraSystem_.ViewMode.FARM then return end
    if not input:GetMouseButtonDown(MOUSEB_LEFT) then return end
    local y = eventData["Y"]:GetInt()
    if not IsWorldTapArea(eventData["X"]:GetInt(), y) then return end

    local dx = eventData["DX"]:GetInt()
    local dy = eventData["DY"]:GetInt()
    if math.abs(dx) > 0 or math.abs(dy) > 0 then
        cameraSystem_.RotateYaw(dx * 0.16)
        cameraSystem_.AdjustPitch(dy * 0.08, 24.0, 68.0)
    end
end

function InteractionSystem.HandleMouseWheel(eventData)
    if IsUIBlocking() then return end
    if cameraSystem_.GetViewMode() ~= cameraSystem_.ViewMode.FARM then return end
    local wheel = eventData["Wheel"]:GetInt()
    if wheel == 0 then return end
    cameraSystem_.AdjustDistance(-wheel * 0.8, config_.FarmViewMinDistance, config_.FarmViewMaxDistance)
end

function InteractionSystem.HandleTouchBegin(eventData)
    if IsUIBlocking() then return end
    local touch = input:GetTouch(0)
    if touch ~= nil and touch.touchedElement then return end
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function InteractionSystem.HandleTouchMove()
    touchGestureActive_ = true
end

function InteractionSystem.UpdateTouchCameraGesture()
    if IsUIBlocking() then
        lastPinchDistance_ = 0
        return
    end
    if cameraSystem_.GetViewMode() ~= cameraSystem_.ViewMode.FARM then
        lastPinchDistance_ = 0
        return
    end

    local touchCount = input.numTouches
    if touchCount == 1 then
        lastPinchDistance_ = 0
        local touch = input:GetTouch(0)
        if touch ~= nil and not touch.touchedElement then
            local dx = touch.delta.x
            local dy = touch.delta.y
            if math.abs(dx) > 0 or math.abs(dy) > 0 then
                touchGestureActive_ = true
                cameraSystem_.RotateYaw(-dx * 0.16)
                cameraSystem_.AdjustPitch(dy * 0.08, 24.0, 68.0)
            end
        end
    elseif touchCount >= 2 then
        local touch1 = input:GetTouch(0)
        local touch2 = input:GetTouch(1)
        if touch1 ~= nil and touch2 ~= nil and not touch1.touchedElement and not touch2.touchedElement then
            local dx = touch1.position.x - touch2.position.x
            local dy = touch1.position.y - touch2.position.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if lastPinchDistance_ > 0 then
                local delta = dist - lastPinchDistance_
                if math.abs(delta) > 0.5 then
                    touchGestureActive_ = true
                    cameraSystem_.AdjustDistance(-delta * 0.018, config_.FarmViewMinDistance, config_.FarmViewMaxDistance)
                end
            end
            lastPinchDistance_ = dist
        end
    else
        lastPinchDistance_ = 0
        touchGestureActive_ = false
    end
end

function InteractionSystem.HandleInput(dt)
    if input:GetKeyPress(KEY_LEFT) then deps_.selectPlotByDelta(-1, 0) end
    if input:GetKeyPress(KEY_RIGHT) then deps_.selectPlotByDelta(1, 0) end
    if input:GetKeyPress(KEY_UP) then deps_.selectPlotByDelta(0, -1) end
    if input:GetKeyPress(KEY_DOWN) then deps_.selectPlotByDelta(0, 1) end
    if input:GetKeyPress(KEY_Q) then deps_.cycleSeed(-1) end
    if input:GetKeyPress(KEY_E) then deps_.cycleSeed(1) end
    if input:GetKeyPress(KEY_B) then deps_.buySelectedSeed(); deps_.refreshUI(true) end
    if input:GetKeyPress(KEY_G) then deps_.sellAllHarvested(); deps_.refreshUI(true) end

    if input:GetKeyPress(KEY_SPACE) then
        if cameraSystem_.GetViewMode() == cameraSystem_.ViewMode.FARM then
            deps_.enterPlantView()
        else
            local plot = deps_.getSelectedPlot()
            if plot ~= nil and deps_.countMaturePlants(plot) > 0 then
                deps_.harvestNearestMature(deps_.getSelectedPlotIndex(), nil)
            elseif plot ~= nil and deps_.countPlotPlants(plot) < config_.MaxCropsPerPlot then
                deps_.plantSeed(deps_.getSelectedPlotIndex(), deps_.getSelectedSeedIndex())
            end
            deps_.refreshUI(true)
        end
    end

    if input:GetKeyDown(KEY_A) then
        cameraSystem_.RotateYaw(-70.0 * dt)
    end
    if input:GetKeyDown(KEY_D) then
        cameraSystem_.RotateYaw(70.0 * dt)
    end
    if input:GetKeyDown(KEY_W) then
        cameraSystem_.AdjustDistance(-8.0 * dt, config_.FarmViewMinDistance, config_.FarmViewMaxDistance)
    end
    if input:GetKeyDown(KEY_S) then
        cameraSystem_.AdjustDistance(8.0 * dt, config_.FarmViewMinDistance, config_.FarmViewMaxDistance)
    end
end

return InteractionSystem
