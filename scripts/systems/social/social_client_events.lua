-- ============================================================================
-- 社交花园客户端远程事件桥接
-- ============================================================================
-- 引擎 SubscribeToEvent 需要全局函数名；此处集中注册，避免主模块过长。
-- ============================================================================

local Shared = require("network.shared")

local function GetSocialGardenSystem()
    return require("systems.social_garden_system")
end

function HandleGardenSaveSnapshotResult(eventType, eventData)
    GetSocialGardenSystem().HandleSaveSnapshotResult(Shared.ReadEventData(eventData))
end

function HandleGardenSnapshotResponse(eventType, eventData)
    GetSocialGardenSystem().HandleGardenResponse(Shared.ReadEventData(eventData))
end

function HandleGardenRankResponse(eventType, eventData)
    GetSocialGardenSystem().HandleRankResponse(Shared.ReadEventData(eventData))
end

function HandleGardenStealResponse(eventType, eventData)
    GetSocialGardenSystem().HandleStealResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSocialStateResponse(eventType, eventData)
    GetSocialGardenSystem().HandleSocialStateResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSendSeedGiftResponse(eventType, eventData)
    GetSocialGardenSystem().HandleSendSeedGiftResponse(Shared.ReadEventData(eventData))
end

function HandleGardenGiftsResponse(eventType, eventData)
    GetSocialGardenSystem().HandleGiftsResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClaimGiftResponse(eventType, eventData)
    GetSocialGardenSystem().HandleClaimGiftResponse(Shared.ReadEventData(eventData))
end

function HandleGardenLikeGardenResponse(eventType, eventData)
    GetSocialGardenSystem().HandleLikeGardenResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSendFriendRequestResponse(eventType, eventData)
    GetSocialGardenSystem().HandleSendFriendRequestResponse(Shared.ReadEventData(eventData))
end

function HandleGardenRespondFriendRequestResponse(eventType, eventData)
    GetSocialGardenSystem().HandleRespondFriendRequestResponse(Shared.ReadEventData(eventData))
end

function HandleGardenRemoveFriendResponse(eventType, eventData)
    GetSocialGardenSystem().HandleRemoveFriendResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClearSocialMessagesResponse(eventType, eventData)
    GetSocialGardenSystem().HandleClearSocialMessagesResponse(Shared.ReadEventData(eventData))
end

function HandleGardenServerReady(eventType, eventData)
    local socialGardenSystem = GetSocialGardenSystem()
    local ok, isNewBinding = socialGardenSystem.BindServerConnection()
    if ok and isNewBinding then
        socialGardenSystem.UploadSnapshot()
    end
end

return true
