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
    SOCIAL_GOLD = "gold",
    ECONOMY_STATE = "garden_economy_state_v1",
}

Shared.EVENTS = {
    CLIENT_READY = "GardenClientReady",
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
    SAVE_ECONOMY_STATE = "GardenSaveEconomyState",
    SAVE_ECONOMY_STATE_RESULT = "GardenSaveEconomyStateResult",
    BUY_SEED = "GardenBuySeed",
    BUY_SEED_RESPONSE = "GardenBuySeedResponse",
    PLANT_SEED = "GardenPlantSeed",
    PLANT_SEED_RESPONSE = "GardenPlantSeedResponse",
    HARVEST_CROP = "GardenHarvestCrop",
    HARVEST_CROP_RESPONSE = "GardenHarvestCropResponse",
    SELL_HARVESTED = "GardenSellHarvested",
    SELL_HARVESTED_RESPONSE = "GardenSellHarvestedResponse",
    SEND_SEED_GIFT = "GardenSendSeedGift",
    SEND_SEED_GIFT_RESPONSE = "GardenSendSeedGiftResponse",
    REQUEST_GIFTS = "GardenRequestGifts",
    GIFTS_RESPONSE = "GardenGiftsResponse",
    CLAIM_GIFT = "GardenClaimGift",
    CLAIM_GIFT_RESPONSE = "GardenClaimGiftResponse",
    LIKE_GARDEN = "GardenLikeGarden",
    LIKE_GARDEN_RESPONSE = "GardenLikeGardenResponse",
}

Shared.SERVER_EVENTS = {
    Shared.EVENTS.CLIENT_READY,
    Shared.EVENTS.SAVE_GARDEN,
    Shared.EVENTS.REQUEST_GARDEN,
    Shared.EVENTS.REQUEST_RANK,
    Shared.EVENTS.REQUEST_STEAL,
    Shared.EVENTS.REQUEST_SOCIAL_STATE,
    Shared.EVENTS.REQUEST_ECONOMY_STATE,
    Shared.EVENTS.SAVE_ECONOMY_STATE,
    Shared.EVENTS.BUY_SEED,
    Shared.EVENTS.PLANT_SEED,
    Shared.EVENTS.HARVEST_CROP,
    Shared.EVENTS.SELL_HARVESTED,
    Shared.EVENTS.SEND_SEED_GIFT,
    Shared.EVENTS.REQUEST_GIFTS,
    Shared.EVENTS.CLAIM_GIFT,
    Shared.EVENTS.LIKE_GARDEN,
}

Shared.CLIENT_EVENTS = {
    Shared.EVENTS.SAVE_GARDEN_RESULT,
    Shared.EVENTS.GARDEN_RESPONSE,
    Shared.EVENTS.RANK_RESPONSE,
    Shared.EVENTS.STEAL_RESPONSE,
    Shared.EVENTS.SOCIAL_STATE_RESPONSE,
    Shared.EVENTS.ECONOMY_STATE_RESPONSE,
    Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT,
    Shared.EVENTS.BUY_SEED_RESPONSE,
    Shared.EVENTS.PLANT_SEED_RESPONSE,
    Shared.EVENTS.HARVEST_CROP_RESPONSE,
    Shared.EVENTS.SELL_HARVESTED_RESPONSE,
    Shared.EVENTS.SEND_SEED_GIFT_RESPONSE,
    Shared.EVENTS.GIFTS_RESPONSE,
    Shared.EVENTS.CLAIM_GIFT_RESPONSE,
    Shared.EVENTS.LIKE_GARDEN_RESPONSE,
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
