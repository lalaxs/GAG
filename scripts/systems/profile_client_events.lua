-- ============================================================================
-- 玩家资料客户端远程事件桥接
-- ============================================================================
-- 引擎 SubscribeToEvent 需要全局函数名（见 network-game-guide §4.6）。
-- ============================================================================

local Shared = require("network.shared")

local function GetPlayerSystem()
    return require("systems.player_system")
end

function HandlePlayerProfileResponse(eventType, eventData)
    GetPlayerSystem().HandleProfileResponse(Shared.ReadEventData(eventData))
end

if network ~= nil and IsClientMode ~= nil and IsClientMode() then
    SubscribeToEvent(Shared.EVENTS.PLAYER_PROFILE, "HandlePlayerProfileResponse")
end

return true
