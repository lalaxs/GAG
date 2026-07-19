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
    "HandleGardenUpdatePlayerProfile",
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
    local function wrap(name)
        return function(eventType, eventData)
            local handler = serverEventHandlers[name]
            if handler == nil then
                print("[服务端] 缺少事件处理函数 " .. tostring(name))
                return
            end
            local ok, err = pcall(handler, eventType, eventData)
            if ok ~= true then
                print(string.format(
                    "[服务端异常] %s: %s",
                    tostring(name),
                    tostring(err)
                ))
            end
        end
    end
    for _, name in ipairs(CONNECTION_HANDLERS) do
        _G[name] = wrap(name)
    end
    for _, name in ipairs(GARDEN_HANDLERS) do
        _G[name] = wrap(name)
    end
end

return ServerGlobals
