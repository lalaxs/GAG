-- ============================================================================
-- 扩地流程控制器
-- Grow A Garden
-- ============================================================================
-- 纯服务器游戏：扩地属于权威经济/农场进度，客户端不再本地扣金币或解锁地块。
-- ============================================================================

local ExpansionController = {}

local deps_ = {}

local function ShowToast(text)
    if deps_.showToast ~= nil then
        deps_.showToast(text)
    end
end

function ExpansionController.Init(deps)
    deps_ = deps or {}
end

function ExpansionController.ExpandNextPlot()
    if deps_.expandPlot and deps_.expandPlot() then
        ShowToast("正在请求服务器扩地...")
        return true
    end
    ShowToast("同步中")
    return false, "server_required"
end

return ExpansionController
