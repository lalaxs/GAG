-- ============================================================================
-- 场景系统 (Scene System)
-- Grow A Garden
-- ============================================================================
-- 管理 3D 场景、灯光、相机组件与天空背景创建。
-- ============================================================================

local SkyUtils = require "urhox-libs.Rendering.SkyUtils"

local SceneSystem = {}

---@return Scene, Node, Camera
function SceneSystem.CreateScene()
    local scene = Scene()
    scene:CreateComponent("Octree", LOCAL)
    scene:CreateComponent("DebugRenderer", LOCAL)

    local zoneNode = scene:CreateChild("Zone", LOCAL)
    local zone = zoneNode:CreateComponent("Zone", LOCAL)
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.48, 0.52, 0.48)
    zone.fogColor = Color(0.75, 0.88, 0.72, 1.0)
    zone.fogStart = 55.0
    zone.fogEnd = 120.0

    local lightNode = scene:CreateChild("Sun", LOCAL)
    lightNode.direction = Vector3(0.45, -1.0, 0.55)
    local light = lightNode:CreateComponent("Light", LOCAL)
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.94, 0.82)
    light.castShadows = true
    light.shadowBias = BiasParameters(0.00025, 0.5)
    light.shadowCascade = CascadeParameters(10.0, 30.0, 90.0, 0.0, 0.8)

    local cameraNode = scene:CreateChild("Camera", LOCAL)
    local camera = cameraNode:CreateComponent("Camera", LOCAL)
    camera.nearClip = 0.1
    camera.farClip = 300.0
    camera.fov = 45.0
    renderer:SetViewport(0, Viewport:new(scene, camera))
    renderer.hdrRendering = true

    return scene, cameraNode, camera
end

---@param scene Scene|nil
function SceneSystem.CreateSkybox(scene)
    if scene == nil then return end

    SkyUtils.CreateGradientSky(scene, {
        zenith   = Color(0.55, 0.78, 0.58),
        horizon  = Color(0.75, 0.88, 0.72),
        ground   = Color(0.55, 0.72, 0.52),
        skyExp   = 0.6,
        hdrBoost = 2.0,
    })

    print("[BG] 渐变天空盒已创建")
end

return SceneSystem
