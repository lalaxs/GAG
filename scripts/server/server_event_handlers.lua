-- ============================================================================
-- 服务端事件处理器
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的事件回调实现。server_main.lua 保留全局 wrapper，
-- 以兼容 SubscribeToEvent 的字符串回调。
-- ============================================================================

local ServerEventHandlers = {}

local UserId = require("utils.user_id")

local deps_ = {}
local Shared = nil
local RequestGuard = nil
local SocialServer = nil
local GiftServer = nil
local connections_ = nil
local connectionUsers_ = nil
local scene_ = nil
local connKeyToUserId_ = {}
local disconnectedPlayers_ = {}
local pendingReconnect_ = {}
local readyConnections_ = {}
local DISCONNECTED_KEEP_SECONDS = 300

function ServerEventHandlers.Init(deps)
    deps_ = deps or {}
    Shared = deps_.Shared
    RequestGuard = deps_.RequestGuard
    SocialServer = deps_.SocialServer
    GiftServer = deps_.GiftServer
    connections_ = deps_.connections
    connectionUsers_ = deps_.connectionUsers
    scene_ = deps_.scene
end

local function GetConnectionKey(connection)
    return deps_.GetConnectionKey(connection)
end

local function GetConnectionUserId(connection)
    return deps_.GetConnectionUserId(connection)
end

local function GetRequestUserId(connection, data)
    return deps_.GetRequestUserId(connection, data)
end

local function ReadRequest(eventData)
    return deps_.ReadRequest(eventData)
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function Now()
    return os and os.time and os.time() or 0
end

local function NormalizeUserId(uid)
    if deps_.NormalizeUserId then return deps_.NormalizeUserId(uid) end
    if uid == nil then return nil end
    return tostring(uid)
end

local function SameUserId(left, right)
    return UserId.Same(left, right)
end

local function ResolveConnectionUserId(connection)
    local key = GetConnectionKey(connection)
    return NormalizeUserId(connKeyToUserId_[key] or connectionUsers_[key] or GetConnectionUserId(connection))
end

local function CleanupDisconnectedPlayers()
    local now = Now()
    for uid, info in pairs(disconnectedPlayers_) do
        if info == nil or now - (info.disconnectedAt or 0) > DISCONNECTED_KEEP_SECONDS then
            disconnectedPlayers_[uid] = nil
        end
    end
end

local function SendSeedShopState(connection)
    deps_.SendSeedShopState(connection)
end

local function SendPlayerProfile(uid, connection)
    deps_.SendPlayerProfile(uid, connection)
end

local function RequestEconomyState(uid, connection)
    deps_.RequestEconomyState(uid, connection)
end

local function RequestAuthFarmState(uid, connection)
    deps_.RequestAuthFarmState(uid, connection)
end

local function RequestLeaderboardAuthority(uid, data, connection)
    deps_.RequestLeaderboardAuthority(uid, data, connection)
end

local function ClaimActivityRankRewardAuthority(uid, data, connection)
    deps_.ClaimActivityRankRewardAuthority(uid, data, connection)
end

local function RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, recordKey)
    deps_.RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, recordKey)
end

local function GrantAdReward(uid, data, connection)
    deps_.GrantAdReward(uid, data, connection)
end

local function BuySeed(uid, plantIndex, price, connection, count, requestId, refreshId, recordKey)
    deps_.BuySeed(uid, plantIndex, price, connection, count, requestId, refreshId, recordKey)
end

local function ClearPlayerSave(uid, connection, requestId, recordKey)
    deps_.ClearPlayerSave(uid, connection, requestId, recordKey)
end

local function PlantSeedAuthority(uid, data, connection)
    deps_.PlantSeedAuthority(uid, data, connection)
end

local function HarvestCropAuthority(uid, data, connection)
    deps_.HarvestCropAuthority(uid, data, connection)
end

local function OpenSeedPackAuthority(uid, data, connection)
    deps_.OpenSeedPackAuthority(uid, data, connection)
end

local function SellHarvested(uid, sellMode, data, connection)
    deps_.SellHarvested(uid, sellMode, data, connection)
end

local function RequestCommissionsAuthority(uid, data, connection)
    deps_.RequestCommissionsAuthority(uid, data, connection)
end

local function CompleteCommissionAuthority(uid, data, connection)
    deps_.CompleteCommissionAuthority(uid, data, connection)
end

local function SubmitActivityCropAuthority(uid, data, connection)
    deps_.SubmitActivityCropAuthority(uid, data, connection)
end

local function ExchangeActivityRewardAuthority(uid, data, connection)
    deps_.ExchangeActivityRewardAuthority(uid, data, connection)
end

local function DrawActivityPackAuthority(uid, data, connection)
    deps_.DrawActivityPackAuthority(uid, data, connection)
end

local function ClaimDailyRewardAuthority(uid, data, connection)
    deps_.ClaimDailyRewardAuthority(uid, data, connection)
end

local function SynthesizePackAuthority(uid, data, connection)
    deps_.SynthesizePackAuthority(uid, data, connection)
end

local function UnlockTalentAuthority(uid, data, connection)
    deps_.UnlockTalentAuthority(uid, data, connection)
end

local function ExpandPlotAuthority(uid, data, connection)
    deps_.ExpandPlotAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleClientConnected(eventType, eventData)
    CleanupDisconnectedPlayers()
    local connection = eventData["Connection"]:GetPtr("Connection")
    connections_[GetConnectionKey(connection)] = connection
    -- 不在 ClientConnected 设置 connection.scene，否则会早于客户端绑定 scene 触发 LoadScene。
end

function ServerEventHandlers.HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local key = GetConnectionKey(connection)
    local rawUid = deps_.ReadConnectionIdentity and deps_.ReadConnectionIdentity(connection) or nil
    local uid = NormalizeUserId(rawUid)
    if uid ~= nil then
        if deps_.RegisterConnectionUserId ~= nil then
            deps_.RegisterConnectionUserId(connection, uid)
        end
        connectionUsers_[key] = uid
        connKeyToUserId_[key] = uid
        local ServerCloudStore = require("server.server_cloud_store")
        print(string.format(
            "[服务端] ClientIdentity userId=%s cloudId=%s addr=%s",
            tostring(uid),
            tostring(ServerCloudStore.CloudPlayerId(uid)),
            tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
        ))
        if disconnectedPlayers_[uid] ~= nil then
            pendingReconnect_[key] = uid
            print("[服务端重连] 识别到玩家重连 userId=" .. tostring(uid))
        end
    end
end

function ServerEventHandlers.HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local key = GetConnectionKey(connection)
    local uid = NormalizeUserId(connKeyToUserId_[key] or connectionUsers_[key] or GetConnectionUserId(connection))
    if uid ~= nil then
        disconnectedPlayers_[uid] = {
            userId = uid,
            disconnectedAt = Now(),
            lastConnectionKey = key,
        }
        print("[服务端重连] 玩家断线，暂存重连上下文 userId=" .. tostring(uid))
    end
    connections_[key] = nil
    connectionUsers_[key] = nil
    connKeyToUserId_[key] = nil
    if deps_.ClearConnectionUserId ~= nil then
        deps_.ClearConnectionUserId(connection)
    end
    pendingReconnect_[key] = nil
    readyConnections_[key] = nil
end

local function SendFullSync(uid, connection, reason)
    SendPlayerProfile(uid, connection)
    SocialServer.RequestSocialState(uid, connection)
    RequestEconomyState(uid, connection)
    SendSeedShopState(connection)
    RequestAuthFarmState(uid, connection)
    print("[服务端同步] 已下发完整权威状态 userId=" .. tostring(uid) .. " reason=" .. tostring(reason or "unknown"))
end

function ServerEventHandlers.HandleGardenClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local key = GetConnectionKey(connection)
    local uid = ResolveConnectionUserId(connection)
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then
        print("[服务端就绪] 等待 ClientIdentity 认证完成后再同步存档 addr=" .. tostring(connection:GetAddress()))
        return
    end
    local firstReady = readyConnections_[key] ~= true
    if firstReady or connection.scene ~= scene_ then
        connection.scene = scene_
    end
    readyConnections_[key] = true
    local reconnectUid = pendingReconnect_[key]
    if reconnectUid ~= nil and reconnectUid == normalizedUid then
        pendingReconnect_[key] = nil
        disconnectedPlayers_[normalizedUid] = nil
        print("[服务端重连] 已恢复玩家连接 userId=" .. tostring(normalizedUid))
    end
    if not firstReady then
        print("[服务端就绪] 忽略重复 CLIENT_READY userId=" .. tostring(normalizedUid))
        return
    end
    SendFullSync(uid, connection, data.reason or "client_ready")
end

function ServerEventHandlers.HandleGardenRequestFullSync(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = ResolveConnectionUserId(connection)
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then
        print("[服务端同步] 等待 ClientIdentity 认证完成后再全量同步 addr=" .. tostring(connection:GetAddress()))
        return
    end
    if connection.scene == nil or connection.scene ~= scene_ then
        connection.scene = scene_
    end
    SendFullSync(uid, connection, data.reason or "request_full_sync")
end

function ServerEventHandlers.HandleGardenSaveSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SocialServer.SaveGardenSnapshot(uid, data.snapshot, connection) end
end

function ServerEventHandlers.HandleGardenRequestSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = ResolveConnectionUserId(connection)
    if uid == nil then
        Send(connection, Shared.EVENTS.GARDEN_RESPONSE, {
            success = false,
            message = "玩家身份未就绪，请稍后重试",
            requestId = data.requestId,
            retryable = true,
        })
        return
    end
    RequestGuard.Check(uid, "visit", data.requestId, function(recordKey)
            SocialServer.RequestGardenSnapshot(uid, data.targetUserId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            local expectedTarget = NormalizeUserId(data.targetUserId)
            local cachedTarget = NormalizeUserId(response.targetUserId)
                or (type(response.garden) == "table" and NormalizeUserId(response.garden.userId))
            if expectedTarget ~= nil and cachedTarget ~= nil and not SameUserId(expectedTarget, cachedTarget) then
                print(string.format(
                    "[社交] 拜访去重缓存 target 不匹配 expected=%s cached=%s，重新请求",
                    tostring(expectedTarget),
                    tostring(cachedTarget)
                ))
                SocialServer.RequestGardenSnapshot(uid, data.targetUserId, connection, data.requestId, nil)
                return
            end
            response.requestId = data.requestId or response.requestId
            response.targetUserId = expectedTarget or response.targetUserId
            Send(connection, Shared.EVENTS.GARDEN_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
end

function ServerEventHandlers.HandleGardenRequestRank(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    SocialServer.RequestRank(data.count, connection, uid)
end

function ServerEventHandlers.HandleGardenRequestLeaderboard(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestLeaderboardAuthority(uid, data, connection)
    end
end

function ServerEventHandlers.HandleGardenClaimActivityRankReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "activity_rank_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            ClaimActivityRankRewardAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRequestSteal(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "steal", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            RequestSteal(uid, data.targetUserId, data.cropIndex, data.cropId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRequestSocialState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = GetRequestUserId(connection, data)
    if uid ~= nil then SocialServer.RequestSocialState(uid, connection) end
end

function ServerEventHandlers.HandleGardenRequestEconomyState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = GetRequestUserId(connection, data)
    if uid == nil then
        Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = false, message = "玩家身份未就绪，请稍后重试", requestId = data.requestId, retryable = true })
        return
    end
    RequestEconomyState(uid, connection)
end

function ServerEventHandlers.HandleGardenRequestSeedShop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    SendSeedShopState(connection)
end

function ServerEventHandlers.HandleGardenRequestAuthFarm(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = GetRequestUserId(connection, data)
    if uid == nil then
        Send(connection, Shared.EVENTS.AUTH_FARM_RESPONSE, { success = false, message = "玩家身份未就绪，请稍后重试", requestId = data.requestId, retryable = true })
        return
    end
    RequestAuthFarmState(uid, connection)
end

function ServerEventHandlers.HandleGardenRequestAdReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "ad_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            GrantAdReward(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenBuySeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "buy_seed", data.requestId, function(recordKey)
            BuySeed(uid, data.plantIndex, data.price, connection, data.count, data.requestId, data.refreshId, recordKey)
        end, function(record)
            local response = record.response or record
            deps_.SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenClearSave(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "clear_save", data.requestId, function(recordKey)
            ClearPlayerSave(uid, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenPlantSeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "plant", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            PlantSeedAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenHarvestCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "harvest", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            HarvestCropAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenOpenSeedPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "open_pack", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            OpenSeedPackAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenSellHarvested(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "sell", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SellHarvested(uid, data.mode or "all", data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRequestCommissions(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then RequestCommissionsAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenCompleteCommission(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then CompleteCommissionAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenSubmitActivityCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "submit_activity_crop", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SubmitActivityCropAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenExchangeActivityReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "exchange_activity_reward", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            ExchangeActivityRewardAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenDrawActivityPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "draw_activity_pack", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            DrawActivityPackAuthority(uid, data, connection)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenClaimDailyReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then ClaimDailyRewardAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenSynthesizePack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SynthesizePackAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenUnlockTalent(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then UnlockTalentAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenExpandPlot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then ExpandPlotAuthority(uid, data, connection) end
end

function ServerEventHandlers.HandleGardenSendSeedGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "gift", data.requestId, function(recordKey)
            GiftServer.SendSeedGift(uid, data.targetUserId, data.seedId, data.count, connection, data.requestId, recordKey, data.profile)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenLikeGarden(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "like", data.requestId, function(recordKey)
            data._requestRecordKey = recordKey
            SocialServer.LikeGarden(uid, data.targetUserId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenSendFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "friend_request", data.requestId, function(recordKey)
            SocialServer.SendFriendRequest(uid, data.targetUserId, connection, data.requestId, recordKey, data.profile)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRespondFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "friend_respond", data.requestId, function(recordKey)
            SocialServer.RespondFriendRequest(uid, data.requestIdValue, data.fromUserId, data.accepted == true, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRemoveFriend(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "remove_friend", data.requestId, function(recordKey)
            SocialServer.RemoveFriend(uid, data.friendUserId, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId, friendUserId = data.friendUserId })
        end)
    end
end

function ServerEventHandlers.HandleGardenClearSocialMessages(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "clear_social_messages", data.requestId, function(recordKey)
            SocialServer.ClearSocialMessages(uid, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end

function ServerEventHandlers.HandleGardenRequestGifts(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then GiftServer.RequestGifts(uid, connection) end
end

function ServerEventHandlers.HandleGardenClaimGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then
        RequestGuard.Check(uid, "claim_gift", data.requestId, function(recordKey)
            GiftServer.ClaimGift(uid, data.giftId or data.listId, data.seedId, data.count, connection, data.requestId, recordKey)
        end, function(record)
            local response = record.response or record
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, response)
        end, function(reason)
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
        end)
    end
end


function ServerEventHandlers.Register()
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleGardenClientReady")
    SubscribeToEvent(Shared.EVENTS.REQUEST_FULL_SYNC, "HandleGardenRequestFullSync")
    SubscribeToEvent(Shared.EVENTS.SAVE_GARDEN, "HandleGardenSaveSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GARDEN, "HandleGardenRequestSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_RANK, "HandleGardenRequestRank")
    SubscribeToEvent(Shared.EVENTS.REQUEST_LEADERBOARD, "HandleGardenRequestLeaderboard")
    SubscribeToEvent(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD, "HandleGardenClaimActivityRankReward")
    SubscribeToEvent(Shared.EVENTS.REQUEST_STEAL, "HandleGardenRequestSteal")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SOCIAL_STATE, "HandleGardenRequestSocialState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_ECONOMY_STATE, "HandleGardenRequestEconomyState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SEED_SHOP, "HandleGardenRequestSeedShop")
    SubscribeToEvent(Shared.EVENTS.REQUEST_AUTH_FARM, "HandleGardenRequestAuthFarm")
    SubscribeToEvent(Shared.EVENTS.REQUEST_AD_REWARD, "HandleGardenRequestAdReward")
    SubscribeToEvent(Shared.EVENTS.BUY_SEED, "HandleGardenBuySeed")
    SubscribeToEvent(Shared.EVENTS.CLEAR_SAVE, "HandleGardenClearSave")
    SubscribeToEvent(Shared.EVENTS.PLANT_SEED, "HandleGardenPlantSeed")
    SubscribeToEvent(Shared.EVENTS.HARVEST_CROP, "HandleGardenHarvestCrop")
    SubscribeToEvent(Shared.EVENTS.OPEN_SEED_PACK, "HandleGardenOpenSeedPack")
    SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED, "HandleGardenSellHarvested")
    SubscribeToEvent(Shared.EVENTS.CLAIM_DAILY_REWARD, "HandleGardenClaimDailyReward")
    SubscribeToEvent(Shared.EVENTS.SYNTHESIZE_PACK, "HandleGardenSynthesizePack")
    SubscribeToEvent(Shared.EVENTS.UNLOCK_TALENT, "HandleGardenUnlockTalent")
    SubscribeToEvent(Shared.EVENTS.EXPAND_PLOT, "HandleGardenExpandPlot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_COMMISSIONS, "HandleGardenRequestCommissions")
    SubscribeToEvent(Shared.EVENTS.COMPLETE_COMMISSION, "HandleGardenCompleteCommission")
    SubscribeToEvent(Shared.EVENTS.SUBMIT_ACTIVITY_CROP, "HandleGardenSubmitActivityCrop")
    SubscribeToEvent(Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD, "HandleGardenExchangeActivityReward")
    SubscribeToEvent(Shared.EVENTS.DRAW_ACTIVITY_PACK, "HandleGardenDrawActivityPack")
    SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT, "HandleGardenSendSeedGift")
    SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN, "HandleGardenLikeGarden")
    SubscribeToEvent(Shared.EVENTS.SEND_FRIEND_REQUEST, "HandleGardenSendFriendRequest")
    SubscribeToEvent(Shared.EVENTS.RESPOND_FRIEND_REQUEST, "HandleGardenRespondFriendRequest")
    SubscribeToEvent(Shared.EVENTS.REMOVE_FRIEND, "HandleGardenRemoveFriend")
    SubscribeToEvent(Shared.EVENTS.CLEAR_SOCIAL_MESSAGES, "HandleGardenClearSocialMessages")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GIFTS, "HandleGardenRequestGifts")
    SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT, "HandleGardenClaimGift")
end

return ServerEventHandlers
