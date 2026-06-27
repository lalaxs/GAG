-- ============================================================================
-- 相机系统 (Camera System)
-- Grow A Garden
-- ============================================================================
-- 管理查看/种植模式、相机旋转与缩放状态。
-- ============================================================================

local CameraSystem = {}

CameraSystem.ViewMode = {
    FARM = 1,
    PLANT = 2,
}

local config_ = nil
---@type Node|nil
local cameraNode_ = nil
local viewMode_ = CameraSystem.ViewMode.FARM
local cameraYaw_ = 0.0
local cameraPitch_ = 0.0
local cameraDistance_ = 0.0
local plantViewDistance_ = 0.0
local cameraTarget_ = Vector3(0, 0, 0)

---@param config table
---@param cameraNode Node|nil
function CameraSystem.Init(config, cameraNode)
    config_ = config
    cameraNode_ = cameraNode
    viewMode_ = CameraSystem.ViewMode.FARM
    cameraYaw_ = config.FarmViewYaw
    cameraPitch_ = config.FarmViewPitch
    cameraDistance_ = config.FarmViewDistance
    plantViewDistance_ = config.PlantViewDistance
    cameraTarget_ = Vector3(0, 0, 0)
end

function CameraSystem.GetViewMode()
    return viewMode_
end

function CameraSystem.IsFarmView()
    return viewMode_ == CameraSystem.ViewMode.FARM
end

function CameraSystem.IsPlantView()
    return viewMode_ == CameraSystem.ViewMode.PLANT
end

function CameraSystem.UpdateCamera()
    if cameraNode_ == nil then return end
    local yaw = math.rad(cameraYaw_)
    local pitch = math.rad(cameraPitch_)
    local targetY = viewMode_ == CameraSystem.ViewMode.PLANT and -0.3 or 0.7
    local target = Vector3(cameraTarget_.x, targetY, cameraTarget_.z)
    local x = math.sin(yaw) * math.cos(pitch) * cameraDistance_
    local y = math.sin(pitch) * cameraDistance_
    local z = -math.cos(yaw) * math.cos(pitch) * cameraDistance_
    cameraNode_.position = target + Vector3(x, y, z)
    cameraNode_:LookAt(target)
end

function CameraSystem.EnterPlantView()
    viewMode_ = CameraSystem.ViewMode.PLANT
    cameraYaw_ = config_.PlantViewYaw
    cameraPitch_ = config_.PlantViewPitch
    cameraDistance_ = plantViewDistance_
    CameraSystem.UpdateCamera()
end

function CameraSystem.EnterFarmView()
    viewMode_ = CameraSystem.ViewMode.FARM
    cameraYaw_ = config_.FarmViewYaw
    cameraPitch_ = config_.FarmViewPitch
    cameraDistance_ = config_.FarmViewDistance
    CameraSystem.UpdateCamera()
end

function CameraSystem.SetTarget(target)
    cameraTarget_ = target or Vector3(0, 0, 0)
    CameraSystem.UpdateCamera()
end

function CameraSystem.GetTarget()
    return cameraTarget_
end

function CameraSystem.RotateYaw(delta)
    cameraYaw_ = cameraYaw_ + delta
    CameraSystem.UpdateCamera()
end

function CameraSystem.AdjustPitch(delta, minPitch, maxPitch)
    cameraPitch_ = Clamp(cameraPitch_ + delta, minPitch, maxPitch)
    CameraSystem.UpdateCamera()
end

function CameraSystem.AdjustDistance(delta, minDistance, maxDistance)
    cameraDistance_ = Clamp(cameraDistance_ + delta, minDistance, maxDistance)
    if viewMode_ == CameraSystem.ViewMode.PLANT then
        plantViewDistance_ = cameraDistance_
    end
    CameraSystem.UpdateCamera()
end

function CameraSystem.SetDistance(distance)
    cameraDistance_ = distance
    if viewMode_ == CameraSystem.ViewMode.PLANT then
        plantViewDistance_ = cameraDistance_
    end
    CameraSystem.UpdateCamera()
end

function CameraSystem.GetDistance()
    return cameraDistance_
end

return CameraSystem
