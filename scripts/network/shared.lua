-- ============================================================================
-- 社交花园网络共享定义
-- ============================================================================

local Shared = {}

Shared.KEYS = {
    GARDEN_SNAPSHOT = "garden_snapshot_v1",
    TOUR_RANK = "garden_tour_rank",
    LIKE_COUNT = "garden_like_count",
    STEAL_LOGS = "garden_steal_logs_v1",
    RECENT_VISITORS = "garden_recent_visitors_v1",
    SEED_REWARDS = "garden_seed_rewards_v1",
    FRIENDS = "garden_friends_v1",
    FRIEND_REQUESTS = "garden_friend_requests_v1",
    SOCIAL_NOTICES = "garden_social_notices_v1",
    GIFT_SENT_TARGETS = "garden_gift_sent_targets_v1",
    SOCIAL_GOLD = "gold",
    ECONOMY_STATE = "garden_economy_state_v1",
    AUTH_FARM_STATE = "garden_auth_farm_state_v1",
    SHARED_SEED_SHOP = "garden_shared_seed_shop_v1",
}

Shared.EVENTS = {
    CLIENT_READY = "GardenClientReady",
    PLAYER_PROFILE = "GardenPlayerProfile",
    SAVE_GARDEN = "GardenSaveSnapshot",
    SAVE_GARDEN_RESULT = "GardenSaveSnapshotResult",
    REQUEST_GARDEN = "GardenRequestSnapshot",
    GARDEN_RESPONSE = "GardenSnapshotResponse",
    REQUEST_RANK = "GardenRequestRank",
    RANK_RESPONSE = "GardenRankResponse",
    REQUEST_STEAL = "GardenRequestSteal",
    STEAL_RESPONSE = "GardenStealResponse",
    REQUEST_SOCIAL_STATE = "GardenRequestSocialState",
    SOCIAL_STATE_RESPONSE = "GardenSocialStateResponse",
    REQUEST_ECONOMY_STATE = "GardenRequestEconomyState",
    ECONOMY_STATE_RESPONSE = "GardenEconomyStateResponse",
    REQUEST_SEED_SHOP = "GardenRequestSeedShop",
    SEED_SHOP_RESPONSE = "GardenSeedShopResponse",
    REQUEST_AUTH_FARM = "GardenRequestAuthFarm",
    AUTH_FARM_RESPONSE = "GardenAuthFarmResponse",
    BUY_SEED = "GardenBuySeed",
    BUY_SEED_RESPONSE = "GardenBuySeedResponse",
    CLEAR_SAVE = "GardenClearSave",
    CLEAR_SAVE_RESPONSE = "GardenClearSaveResponse",
    PLANT_SEED = "GardenPlantSeed",
    PLANT_SEED_RESPONSE = "GardenPlantSeedResponse",
    HARVEST_CROP = "GardenHarvestCrop",
    HARVEST_CROP_RESPONSE = "GardenHarvestCropResponse",
    OPEN_SEED_PACK = "GardenOpenSeedPack",
    OPEN_SEED_PACK_RESPONSE = "GardenOpenSeedPackResponse",
    SELL_HARVESTED = "GardenSellHarvested",
    SELL_HARVESTED_RESPONSE = "GardenSellHarvestedResponse",
    CLAIM_DAILY_REWARD = "GardenClaimDailyReward",
    CLAIM_DAILY_REWARD_RESPONSE = "GardenClaimDailyRewardResponse",
    SYNTHESIZE_PACK = "GardenSynthesizePack",
    SYNTHESIZE_PACK_RESPONSE = "GardenSynthesizePackResponse",
    UNLOCK_TALENT = "GardenUnlockTalent",
    UNLOCK_TALENT_RESPONSE = "GardenUnlockTalentResponse",
    EXPAND_PLOT = "GardenExpandPlot",
    EXPAND_PLOT_RESPONSE = "GardenExpandPlotResponse",
    REQUEST_COMMISSIONS = "GardenRequestCommissions",
    COMMISSIONS_RESPONSE = "GardenCommissionsResponse",
    COMPLETE_COMMISSION = "GardenCompleteCommission",
    COMPLETE_COMMISSION_RESPONSE = "GardenCompleteCommissionResponse",
    SUBMIT_ACTIVITY_CROP = "GardenSubmitActivityCrop",
    SUBMIT_ACTIVITY_CROP_RESPONSE = "GardenSubmitActivityCropResponse",
    EXCHANGE_ACTIVITY_REWARD = "GardenExchangeActivityReward",
    EXCHANGE_ACTIVITY_REWARD_RESPONSE = "GardenExchangeActivityRewardResponse",
    DRAW_ACTIVITY_PACK = "GardenDrawActivityPack",
    DRAW_ACTIVITY_PACK_RESPONSE = "GardenDrawActivityPackResponse",
    SEND_SEED_GIFT = "GardenSendSeedGift",
    SEND_SEED_GIFT_RESPONSE = "GardenSendSeedGiftResponse",
    REQUEST_GIFTS = "GardenRequestGifts",
    GIFTS_RESPONSE = "GardenGiftsResponse",
    CLAIM_GIFT = "GardenClaimGift",
    CLAIM_GIFT_RESPONSE = "GardenClaimGiftResponse",
    LIKE_GARDEN = "GardenLikeGarden",
    LIKE_GARDEN_RESPONSE = "GardenLikeGardenResponse",
    SEND_FRIEND_REQUEST = "GardenSendFriendRequest",
    SEND_FRIEND_REQUEST_RESPONSE = "GardenSendFriendRequestResponse",
    RESPOND_FRIEND_REQUEST = "GardenRespondFriendRequest",
    RESPOND_FRIEND_REQUEST_RESPONSE = "GardenRespondFriendRequestResponse",
    REMOVE_FRIEND = "GardenRemoveFriend",
    REMOVE_FRIEND_RESPONSE = "GardenRemoveFriendResponse",
    CLEAR_SOCIAL_MESSAGES = "GardenClearSocialMessages",
    CLEAR_SOCIAL_MESSAGES_RESPONSE = "GardenClearSocialMessagesResponse",
}

Shared.SERVER_EVENTS = {
    Shared.EVENTS.CLIENT_READY,
    Shared.EVENTS.SAVE_GARDEN,
    Shared.EVENTS.REQUEST_GARDEN,
    Shared.EVENTS.REQUEST_RANK,
    Shared.EVENTS.REQUEST_STEAL,
    Shared.EVENTS.REQUEST_SOCIAL_STATE,
    Shared.EVENTS.REQUEST_ECONOMY_STATE,
    Shared.EVENTS.REQUEST_SEED_SHOP,
    Shared.EVENTS.REQUEST_AUTH_FARM,
    Shared.EVENTS.BUY_SEED,
    Shared.EVENTS.CLEAR_SAVE,
    Shared.EVENTS.PLANT_SEED,
    Shared.EVENTS.HARVEST_CROP,
    Shared.EVENTS.OPEN_SEED_PACK,
    Shared.EVENTS.SELL_HARVESTED,
    Shared.EVENTS.CLAIM_DAILY_REWARD,
    Shared.EVENTS.SYNTHESIZE_PACK,
    Shared.EVENTS.UNLOCK_TALENT,
    Shared.EVENTS.EXPAND_PLOT,
    Shared.EVENTS.REQUEST_COMMISSIONS,
    Shared.EVENTS.COMPLETE_COMMISSION,
    Shared.EVENTS.SUBMIT_ACTIVITY_CROP,
    Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD,
    Shared.EVENTS.DRAW_ACTIVITY_PACK,
    Shared.EVENTS.SEND_SEED_GIFT,
    Shared.EVENTS.REQUEST_GIFTS,
    Shared.EVENTS.CLAIM_GIFT,
    Shared.EVENTS.LIKE_GARDEN,
    Shared.EVENTS.SEND_FRIEND_REQUEST,
    Shared.EVENTS.RESPOND_FRIEND_REQUEST,
    Shared.EVENTS.REMOVE_FRIEND,
    Shared.EVENTS.CLEAR_SOCIAL_MESSAGES,
}

Shared.CLIENT_EVENTS = {
    Shared.EVENTS.PLAYER_PROFILE,
    Shared.EVENTS.SAVE_GARDEN_RESULT,
    Shared.EVENTS.GARDEN_RESPONSE,
    Shared.EVENTS.RANK_RESPONSE,
    Shared.EVENTS.STEAL_RESPONSE,
    Shared.EVENTS.SOCIAL_STATE_RESPONSE,
    Shared.EVENTS.ECONOMY_STATE_RESPONSE,
    Shared.EVENTS.SEED_SHOP_RESPONSE,
    Shared.EVENTS.AUTH_FARM_RESPONSE,
    Shared.EVENTS.BUY_SEED_RESPONSE,
    Shared.EVENTS.CLEAR_SAVE_RESPONSE,
    Shared.EVENTS.PLANT_SEED_RESPONSE,
    Shared.EVENTS.HARVEST_CROP_RESPONSE,
    Shared.EVENTS.OPEN_SEED_PACK_RESPONSE,
    Shared.EVENTS.SELL_HARVESTED_RESPONSE,
    Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE,
    Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE,
    Shared.EVENTS.UNLOCK_TALENT_RESPONSE,
    Shared.EVENTS.EXPAND_PLOT_RESPONSE,
    Shared.EVENTS.COMMISSIONS_RESPONSE,
    Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE,
    Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE,
    Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE,
    Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE,
    Shared.EVENTS.SEND_SEED_GIFT_RESPONSE,
    Shared.EVENTS.GIFTS_RESPONSE,
    Shared.EVENTS.CLAIM_GIFT_RESPONSE,
    Shared.EVENTS.LIKE_GARDEN_RESPONSE,
    Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE,
    Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE,
    Shared.EVENTS.REMOVE_FRIEND_RESPONSE,
    Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE,
}

function Shared.RegisterServerEvents()
    if network == nil then return end
    for _, eventName in ipairs(Shared.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

function Shared.RegisterClientEvents()
    if network == nil then return end
    for _, eventName in ipairs(Shared.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

function Shared.Encode(data)
    local ok, encoded = pcall(cjson.encode, data or {})
    if ok and encoded ~= nil then return encoded end
    return "{}"
end

function Shared.Decode(raw)
    if raw == nil or raw == "" then return {} end
    local ok, data = pcall(cjson.decode, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

function Shared.SendToServer(eventName, data)
    if network == nil then return false end
    local connection = network:GetServerConnection()
    if connection == nil then return false end
    local eventData = VariantMap()
    eventData["Data"] = Variant(Shared.Encode(data))
    connection:SendRemoteEvent(eventName, true, eventData)
    return true
end

function Shared.SendToClient(connection, eventName, data)
    if connection == nil then return false end
    local eventData = VariantMap()
    eventData["Data"] = Variant(Shared.Encode(data))
    connection:SendRemoteEvent(eventName, true, eventData)
    return true
end

function Shared.ReadEventData(eventData)
    if eventData == nil or eventData["Data"] == nil then return {} end
    return Shared.Decode(eventData["Data"]:GetString())
end

return Shared
