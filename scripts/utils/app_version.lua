-- ============================================================================
-- 应用版本号（与 .project/project.json 的 version 字段保持一致）
-- ============================================================================

local AppVersion = {}

-- 与 .project/project.json -> version 同步，勿用 Text 资源加载（Web 端会报 unknown resource type）
local VERSION = "1.4.21"

function AppVersion.Get()
    return VERSION
end

function AppVersion.GetDisplayLabel()
    return "V" .. VERSION
end

return AppVersion
