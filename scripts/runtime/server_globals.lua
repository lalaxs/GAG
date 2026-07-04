-- ============================================================================
-- 服务端全局事件回调绑定
-- Grow A Garden
-- ============================================================================
-- SubscribeToEvent 需要全局函数名；此模块在 Start 前一次性绑定，避免 server_main 堆叠转发 wrapper。
-- ============================================================================

local ServerGlobals = {}

local CONNECTION_HANDLERS = {
    "HandleClientConnected",
    "HandleClientIdentity",
    "HandleClientDisconnected",
}

local GARDEN_HANDLERS = {
    "HandleGardenClientReady",
    "HandleGardenRequestFullSync",
    "HandleGardenSaveSnapshot",
    "HandleGardenRequestSnapshot",
    "HandleGardenRequestRank",
    "HandleGardenRequestLeaderboard",
    "HandleGardenClaimActivityRankReward",
    "HandleGardenRequestSteal",
    "HandleGardenRequestSocialState",
    "HandleGardenRequestEconomyState",
    "HandleGardenRequestSeedShop",
    "HandleGardenRequestAuthFarm",
    "HandleGardenRequestAdReward",
    "HandleGardenBuySeed",
    "HandleGardenClearSave",
    "HandleGardenPlantSeed",
    "HandleGardenHarvestCrop",
    "HandleGardenOpenSeedPack",
    "HandleGardenSellHarvested",
    "HandleGardenRequestCommissions",
    "HandleGardenCompleteCommission",
    "HandleGardenSubmitActivityCrop",
    "HandleGardenExchangeActivityReward",
    "HandleGardenDrawActivityPack",
    "HandleGardenClaimDailyReward",
    "HandleGardenSynthesizePack",
    "HandleGardenUnlockTalent",
    "HandleGardenExpandPlot",
    "HandleGardenSendSeedGift",
    "HandleGardenLikeGarden",
    "HandleGardenSendFriendRequest",
    "HandleGardenRespondFriendRequest",
    "HandleGardenRemoveFriend",
    "HandleGardenClearSocialMessages",
    "HandleGardenRequestGifts",
    "HandleGardenClaimGift",
}

function ServerGlobals.BindEventHandlers(serverEventHandlers)
    for _, name in ipairs(CONNECTION_HANDLERS) do
        _G[name] = function(eventType, eventData)
            serverEventHandlers[name](eventType, eventData)
        end
    end
    for _, name in ipairs(GARDEN_HANDLERS) do
        _G[name] = function(eventType, eventData)
            serverEventHandlers[name](eventType, eventData)
        end
    end
end

return ServerGlobals
