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
local PlayerStateService = nil
local connections_ = nil
local connectionUsers_ = nil
local scene_ = nil
local connKeyToUserId_ = {}
local disconnectedPlayers_ = {}
local pendingReconnect_ = {}
local readyConnections_ = {}
local clientReadyConnections_ = {}
local fullSyncSeq_ = 0
local pendingFullSync_ = {}
local fullSyncBatches_ = {}
-- 服务端 FullSync 超时须早于客户端 load/authFarm pending（35s）。
local FULL_SYNC_TIMEOUT_SEC = 25
local DISCONNECTED_KEEP_SECONDS = 300

function ServerEventHandlers.Init(deps)
    deps_ = deps or {}
    Shared = deps_.Shared
    RequestGuard = deps_.RequestGuard
    SocialServer = deps_.SocialServer
    GiftServer = deps_.GiftServer
    PlayerStateService = deps_.PlayerStateService
    connections_ = deps_.connections
    connectionUsers_ = deps_.connectionUsers
    scene_ = deps_.scene
end

local function GetConnectionKey(connection)
    return deps_.GetConnectionKey(connection)
end

local function GetConnectionGameSessionId(connection)
    if deps_.GetConnectionGameSessionId ~= nil then
        local sessionId = deps_.GetConnectionGameSessionId(connection)
        if sessionId ~= nil then return sessionId end
    end
    return nil
end

local function BuildConnectionLogContext(connection)
    return string.format(
        "game_session_id=%s conn=%s",
        tostring(GetConnectionGameSessionId(connection) or "unknown"),
        tostring(GetConnectionKey(connection))
    )
end

local function GetConnectionUserId(connection)
    return deps_.GetConnectionUserId(connection)
end

local function RegisterConnection(connection)
    if deps_.RegisterConnection ~= nil then
        return deps_.RegisterConnection(connection)
    end
    return nil
end

local function GetConnectionGeneration(connection)
    if deps_.GetConnectionGeneration ~= nil then
        return deps_.GetConnectionGeneration(connection)
    end
    return nil
end

local function IsCurrentConnection(connection, generation)
    if deps_.IsCurrentConnection ~= nil then
        return deps_.IsCurrentConnection(connection, generation)
    end
    return true
end

local function InvalidateConnection(connection)
    if deps_.InvalidateConnection ~= nil then
        deps_.InvalidateConnection(connection)
    end
end

local function GetRequestUserId(connection, data)
    return deps_.GetRequestUserId(connection, data)
end

local function ReadRequest(eventData)
    return deps_.ReadRequest(eventData)
end

local function Send(connection, eventName, data)
    return deps_.Send(connection, eventName, data)
end

local function SendServerSyncAck(connection, stage, data)
    local payload = data or {}
    payload.success = payload.success ~= false
    payload.stage = stage
    payload.serverTime = os and os.time and os.time() or 0
    payload.gameSessionId = GetConnectionGameSessionId(connection)
    payload.connectionKey = GetConnectionKey(connection)
    -- 回声客户端 sync token；缺省不填服务端世代，避免客户端误把两边计数器当同一套。
    if payload.connectionGeneration == nil and payload.clientConnectionGeneration ~= nil then
        payload.connectionGeneration = payload.clientConnectionGeneration
    end
    payload.serverConnectionGeneration = GetConnectionGeneration(connection)
    Send(connection, Shared.EVENTS.SERVER_SYNC_ACK, payload)
end

local function ClientFacingGeneration(waiter)
    if waiter == nil then return nil end
    return waiter.clientConnectionGeneration
end

local function SendIdentityNotReady(connection, eventName, requestId, stage)
    SendServerSyncAck(connection, stage or "identity_not_ready", {
        success = false,
        retryable = true,
        error = "IDENTITY_NOT_READY",
        requestId = requestId,
    })
    if eventName ~= nil then
        Send(connection, eventName, {
            success = false,
            retryable = true,
            message = "玩家身份未就绪，请稍后重试",
            code = "IDENTITY_NOT_READY",
            requestId = requestId,
        })
    end
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

local function IsConnectionAlive(connection)
    if connection == nil then return false end
    if connection.IsConnected ~= nil and connection:IsConnected() ~= true then return false end
    if connection.connected ~= nil and connection.connected ~= true then return false end
    return true
end

local function FindLiveConnectionForUser(uid, preferredConnection)
    if IsConnectionAlive(preferredConnection) then return preferredConnection end
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then return nil end
    for key, connection in pairs(connections_ or {}) do
        if IsConnectionAlive(connection) then
            local mappedUid = NormalizeUserId(connKeyToUserId_[key] or connectionUsers_[key] or GetConnectionUserId(connection))
            if SameUserId(mappedUid, normalizedUid) then
                return connection
            end
        end
    end
    return nil
end

local function SendToUser(uid, connection, eventName, data)
    if not IsCurrentConnection(connection) then
        print(string.format(
            "[服务端网络] 拒绝失效连接回包 event=%s uid=%s conn=%s",
            tostring(eventName),
            tostring(uid),
            tostring(GetConnectionKey(connection))
        ))
        return false
    end
    if Send(connection, eventName, data) == true then return true end
    local liveConnection = FindLiveConnectionForUser(uid, connection)
    if liveConnection ~= nil and liveConnection ~= connection then
        print(string.format(
            "[服务端网络] 原连接回包失败，改用当前连接 event=%s uid=%s old=%s new=%s",
            tostring(eventName),
            tostring(uid),
            tostring(GetConnectionKey(connection)),
            tostring(GetConnectionKey(liveConnection))
        ))
        return Send(liveConnection, eventName, data)
    end
    return false
end

local function ResolveConnectionUserId(connection)
    if not IsCurrentConnection(connection) then return nil end
    local uid = NormalizeUserId(GetConnectionUserId(connection))
    if uid ~= nil then return uid end
    return nil
end

local function CleanupDisconnectedPlayers()
    local now = Now()
    for uid, info in pairs(disconnectedPlayers_) do
        if info == nil or now - (info.disconnectedAt or 0) > DISCONNECTED_KEEP_SECONDS then
            disconnectedPlayers_[uid] = nil
            if PlayerStateService ~= nil then
                local session = PlayerStateService.GetSession ~= nil and PlayerStateService.GetSession(uid) or nil
                if session ~= nil then
                    print("[服务端重连] 断线保留超时，准备 flush 并清理会话 userId=" .. tostring(uid))
                    if PlayerStateService.Flush ~= nil then
                        PlayerStateService.Flush(uid, function(ok, reason)
                            print(string.format(
                                "[服务端重连] 断线会话清理 flush userId=%s ok=%s reason=%s",
                                tostring(uid),
                                tostring(ok),
                                tostring(reason)
                            ))
                            if PlayerStateService.Clear ~= nil then
                                PlayerStateService.Clear(uid)
                                print("[服务端重连] 已清理断线玩家会话 userId=" .. tostring(uid))
                            end
                        end)
                    elseif PlayerStateService.Clear ~= nil then
                        PlayerStateService.Clear(uid)
                        print("[服务端重连] 已清理断线玩家会话 userId=" .. tostring(uid))
                    end
                end
            end
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

local function ClearPlayerSave(uid, connection, requestId, recordKey, options)
    deps_.ClearPlayerSave(uid, connection, requestId, recordKey, options)
end

local function PlantSeedAuthority(uid, data, connection)
    deps_.PlantSeedAuthority(uid, data, connection, SendToUser)
end

local function HarvestCropAuthority(uid, data, connection)
    deps_.HarvestCropAuthority(uid, data, connection, SendToUser)
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

function ServerEventHandlers.HandleGardenUpdatePlayerProfile(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not IsCurrentConnection(connection) then return end
    local uid = ResolveConnectionUserId(connection)
    local data = ReadRequest(eventData)
    local connectionGeneration = GetConnectionGeneration(connection)
    local function SendProfileFailure(message, retryable)
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, {
            success = false,
            retryable = retryable == true,
            message = message,
            requestId = data.requestId,
            connectionGeneration = connectionGeneration,
        })
    end
    if uid == nil then
        SendProfileFailure("玩家身份未就绪，请稍后重试", true)
        return
    end
    local profile = type(data.profile) == "table" and data.profile or {}
    local customNickname = tostring(profile.customNickname or "")
    if #customNickname > 48 then
        SendProfileFailure("昵称长度无效", false)
        return
    end
    local session = PlayerStateService.GetSession(uid)
    if session == nil then
        SendProfileFailure("玩家存档尚未就绪", true)
        return
    end
    local current = PlayerStateService.GetProfile(uid) or {}
    profile.tapNickname = current.tapNickname or profile.tapNickname or "Tap玩家"
    profile.customNickname = customNickname
    if type(profile.avatar) ~= "table" then profile.avatar = current.avatar end
    PlayerStateService.SetProfile(uid, profile, function(ok, reason)
        if not IsCurrentConnection(connection, connectionGeneration) then
            print(string.format(
                "[玩家资料] 忽略旧连接保存回包 uid=%s requestId=%s generation=%s",
                tostring(uid),
                tostring(data.requestId),
                tostring(connectionGeneration)
            ))
            return
        end
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, {
            success = ok == true,
            retryable = ok ~= true,
            message = ok == true and "玩家资料已保存" or "玩家资料保存失败",
            userId = uid,
            nickname = profile.customNickname ~= "" and profile.customNickname or profile.tapNickname,
            profile = profile,
            requestId = data.requestId,
            connectionGeneration = connectionGeneration,
            gameSessionId = GetConnectionGameSessionId(connection),
            reason = reason,
        })
    end)
end

local function SendFullSync(uid, connection, reason, requestId, clientConnectionGeneration)
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then return false end
    local connectionGeneration = GetConnectionGeneration(connection)
    local existingBatch = fullSyncBatches_[normalizedUid]
    if existingBatch ~= nil then
        existingBatch.waiters[#existingBatch.waiters + 1] = {
            connection = connection,
            connectionGeneration = connectionGeneration,
            clientConnectionGeneration = clientConnectionGeneration,
            reason = reason or "unknown",
            requestId = requestId,
        }
        SendServerSyncAck(connection, "full_sync_joined", {
            userId = tostring(normalizedUid),
            reason = reason or "unknown",
            requestId = requestId,
            syncId = existingBatch.syncId,
            batchOwner = true,
            clientConnectionGeneration = clientConnectionGeneration,
        })
        print(string.format(
            "[服务端同步] 同 UID 合并 FullSync 请求 uid=%s requestId=%s ownerSyncId=%s serverGeneration=%s clientGeneration=%s",
            tostring(normalizedUid),
            tostring(requestId),
            tostring(existingBatch.syncId),
            tostring(connectionGeneration),
            tostring(clientConnectionGeneration)
        ))
        return true
    end
    uid = normalizedUid
    -- 标准热路径：Identity 已锁定 UID → PlayerState.Load（统一档 / 一次性拆分迁移）→ 下发。
    fullSyncSeq_ = fullSyncSeq_ + 1
    local syncId = tostring(uid) .. "#" .. tostring(fullSyncSeq_)
    pendingFullSync_[syncId] = {
        uid = uid,
        connection = connection,
        connectionGeneration = connectionGeneration,
        reason = reason or "unknown",
        requestId = requestId,
        startedAt = Now(),
        phase = "player_state_load",
    }
    fullSyncBatches_[uid] = {
        syncId = syncId,
        uid = uid,
        startedAt = Now(),
        waiters = {
            {
                connection = connection,
                connectionGeneration = connectionGeneration,
                clientConnectionGeneration = clientConnectionGeneration,
                reason = reason or "unknown",
                requestId = requestId,
            },
        },
    }
    print("[服务端同步] 启动 UID 单飞 FullSync userId=" .. tostring(uid) .. " reason=" .. tostring(reason or "unknown") .. " syncId=" .. tostring(syncId) .. " " .. BuildConnectionLogContext(connection))
    SendServerSyncAck(connection, "full_sync_started", {
        userId = tostring(uid),
        reason = reason or "unknown",
        requestId = requestId,
        clientConnectionGeneration = clientConnectionGeneration,
        syncId = syncId,
    })

    local function finishSync(session, err)
        local pending = pendingFullSync_[syncId]
        local batch = fullSyncBatches_[uid]
        if pending == nil or batch == nil then
            print("[服务端同步] 忽略过期全量同步回调 userId=" .. tostring(uid) .. " syncId=" .. tostring(syncId) .. " err=" .. tostring(err))
            return
        end
        local elapsed = Now() - (pending.startedAt or Now())
        pendingFullSync_[syncId] = nil
        fullSyncBatches_[uid] = nil
        local liveWaiterCount = 0
        for _, waiter in ipairs(batch.waiters) do
            if waiter ~= nil and IsCurrentConnection(waiter.connection, waiter.connectionGeneration) then
                liveWaiterCount = liveWaiterCount + 1
            end
        end
        if liveWaiterCount <= 0 then
            print(string.format(
                "[服务端同步] FullSync 批次完成但无有效等待连接 uid=%s syncId=%s elapsed=%s",
                tostring(uid), tostring(syncId), tostring(elapsed)
            ))
            return
        end
        local function ForEachLiveWaiter(callback)
            for _, waiter in ipairs(batch.waiters) do
                if waiter ~= nil and IsCurrentConnection(waiter.connection, waiter.connectionGeneration) then
                    callback(waiter)
                else
                    print(string.format(
                        "[服务端同步] 丢弃批次失效 waiter uid=%s syncId=%s requestId=%s generation=%s",
                        tostring(uid),
                        tostring(syncId),
                        tostring(waiter and waiter.requestId),
                        tostring(waiter and waiter.connectionGeneration)
                    ))
                end
            end
        end
        if session == nil then
            ForEachLiveWaiter(function(waiter)
                local waiterConnection = waiter.connection
                local clientGen = ClientFacingGeneration(waiter)
                local needReopen = tostring(err or ""):find("NEED_REOPEN", 1, true) ~= nil
                    or tostring(err or ""):find("LOAD_FAILED", 1, true) ~= nil
                Send(waiterConnection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, {
                    success = false,
                    retryable = needReopen ~= true,
                    needReopen = needReopen == true,
                    message = needReopen and "未能安全读取存档，请重开或重试" or "同步失败",
                    code = needReopen and "NEED_REOPEN" or nil,
                    requestId = waiter.requestId,
                    syncId = syncId,
                    connectionGeneration = clientGen,
                    reason = waiter.reason or "unknown",
                    error = tostring(err),
                })
                Send(waiterConnection, Shared.EVENTS.AUTH_FARM_RESPONSE, {
                    success = false,
                    retryable = needReopen ~= true,
                    needReopen = needReopen == true,
                    message = needReopen and "未能安全读取存档，请重开或重试" or "农场同步失败",
                    code = needReopen and "NEED_REOPEN" or nil,
                    requestId = waiter.requestId,
                    syncId = syncId,
                    connectionGeneration = clientGen,
                    reason = waiter.reason or "unknown",
                    error = tostring(err),
                })
                SendServerSyncAck(waiterConnection, "full_sync_failed", {
                    success = false,
                    userId = tostring(uid),
                    reason = waiter.reason or "unknown",
                    requestId = waiter.requestId,
                    syncId = syncId,
                    error = tostring(err),
                    needReopen = needReopen == true,
                    clientConnectionGeneration = clientGen,
                })
            end)
            print("[服务端同步] 玩家会话加载失败 userId=" .. tostring(uid) .. " syncId=" .. tostring(syncId) .. " elapsed=" .. tostring(elapsed) .. " err=" .. tostring(err))
            return
        end
        local report = {}
        local reportOk, reportResult = pcall(function()
            return PlayerStateService.GetSaveLoadReport(uid) or {}
        end)
        if reportOk == true and type(reportResult) == "table" then
            report = reportResult
        else
            print("[服务端同步] 读取存档报告失败 userId=" .. tostring(uid) .. " syncId=" .. tostring(syncId) .. " err=" .. tostring(reportResult))
        end
        ForEachLiveWaiter(function(waiter)
            local waiterConnection = waiter.connection
            local waiterReason = waiter.reason or "unknown"
            local clientGen = ClientFacingGeneration(waiter)
            local economySent, economyBytes = Send(waiterConnection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, {
                success = true,
                state = session.economy,
                userId = uid,
                saveSource = report.saveSource or session.loadSource,
                saveMigrated = report.saveMigrated == true,
                saveWriteOk = report.saveWriteOk ~= false,
                saveWriteReason = report.saveWriteReason,
                profile = report.profile,
                requestId = waiter.requestId,
                syncId = syncId,
                connectionGeneration = clientGen,
                reason = waiterReason,
            })
            local farmSent, farmBytes = Send(waiterConnection, Shared.EVENTS.AUTH_FARM_RESPONSE, {
                success = true,
                farm = session.farm,
                userId = uid,
                saveSource = report.saveSource or session.loadSource,
                saveMigrated = report.saveMigrated == true,
                saveWriteOk = report.saveWriteOk ~= false,
                profile = report.profile,
                requestId = waiter.requestId,
                syncId = syncId,
                connectionGeneration = clientGen,
                reason = waiterReason,
            })
            if economySent ~= true or farmSent ~= true then
                SendServerSyncAck(waiterConnection, "full_sync_failed", {
                    success = false,
                    userId = tostring(uid),
                    reason = waiterReason,
                    requestId = waiter.requestId,
                    syncId = syncId,
                    error = "FULL_SYNC_SEND_FAILED",
                    economySent = economySent == true,
                    farmSent = farmSent == true,
                    clientConnectionGeneration = clientGen,
                })
                print(string.format(
                    "[服务端同步] 权威状态发送失败 userId=%s requestId=%s syncId=%s economySent=%s farmSent=%s economyBytes=%s farmBytes=%s %s",
                    tostring(uid),
                    tostring(waiter.requestId),
                    tostring(syncId),
                    tostring(economySent == true),
                    tostring(farmSent == true),
                    tostring(economyBytes),
                    tostring(farmBytes),
                    BuildConnectionLogContext(waiterConnection)
                ))
                return
            end
            SendServerSyncAck(waiterConnection, "full_sync_sent", {
                userId = tostring(uid),
                reason = waiterReason,
                requestId = waiter.requestId,
                syncId = syncId,
                saveSource = report.saveSource or session.loadSource,
                saveMigrated = report.saveMigrated == true,
                saveWriteOk = report.saveWriteOk ~= false,
                profile = report.profile,
                economyBytes = economyBytes,
                farmBytes = farmBytes,
                clientConnectionGeneration = clientGen,
            })
            print(string.format(
                "[服务端同步] 已下发完整权威状态 userId=%s reason=%s requestId=%s syncId=%s elapsed=%s saveSource=%s migrated=%s writeOk=%s economyBytes=%s farmBytes=%s %s",
                tostring(uid),
                tostring(waiterReason),
                tostring(waiter.requestId),
                tostring(syncId),
                tostring(elapsed),
                tostring(report.saveSource),
                tostring(report.saveMigrated),
                tostring(report.saveWriteOk),
                tostring(economyBytes),
                tostring(farmBytes),
                BuildConnectionLogContext(waiterConnection)
            ))

            local optionalOk, optionalErr = pcall(function()
                SendPlayerProfile(uid, waiterConnection)
                SendSeedShopState(waiterConnection)
                SocialServer.RequestSocialSave(uid, waiterConnection)
                if waiterReason ~= "return_home_force_sync" then
                    SocialServer.RequestSocialState(uid, waiterConnection)
                else
                    print("[服务端同步] 返回家园仅下发经济/农场/种子商店，跳过完整社交状态 userId=" .. tostring(uid))
                end
            end)
            if optionalOk ~= true then
                SendServerSyncAck(waiterConnection, "full_sync_optional_failed", {
                    success = false,
                    userId = tostring(uid),
                    reason = waiterReason,
                    requestId = waiter.requestId,
                    syncId = syncId,
                    error = tostring(optionalErr),
                    clientConnectionGeneration = clientGen,
                })
                print("[服务端同步] 附加数据下发失败 userId=" .. tostring(uid) .. " syncId=" .. tostring(syncId) .. " err=" .. tostring(optionalErr) .. " " .. BuildConnectionLogContext(waiterConnection))
            end
        end)
    end

    print(string.format(
        "[服务端同步] 开始 PlayerState Load uid=%s syncId=%s requestId=%s",
        tostring(uid),
        tostring(syncId),
        tostring(requestId)
    ))
    PlayerStateService.Load(uid, finishSync)
end

function ServerEventHandlers.Update(dt)
    local now = Now()
    for syncId, pending in pairs(pendingFullSync_) do
        if pending ~= nil and now - (pending.startedAt or 0) >= FULL_SYNC_TIMEOUT_SEC then
            pendingFullSync_[syncId] = nil
            local batch = fullSyncBatches_[pending.uid]
            if batch ~= nil and batch.syncId == syncId then
                fullSyncBatches_[pending.uid] = nil
            end
            for _, waiter in ipairs(batch and batch.waiters or {}) do
                local connection = waiter.connection
                if IsCurrentConnection(connection, waiter.connectionGeneration) then
                    local clientGen = ClientFacingGeneration(waiter)
                    Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, {
                        success = false,
                        retryable = true,
                        message = "同步失败",
                        requestId = waiter.requestId,
                        syncId = syncId,
                        connectionGeneration = clientGen,
                        reason = tostring(waiter.reason),
                    })
                    Send(connection, Shared.EVENTS.AUTH_FARM_RESPONSE, {
                        success = false,
                        retryable = true,
                        message = "农场同步失败",
                        requestId = waiter.requestId,
                        syncId = syncId,
                        connectionGeneration = clientGen,
                        reason = tostring(waiter.reason),
                    })
                    SendServerSyncAck(connection, "full_sync_timeout", {
                        success = false,
                        userId = tostring(pending.uid),
                        reason = tostring(waiter.reason),
                        requestId = waiter.requestId,
                        syncId = syncId,
                        error = "FULL_SYNC_TIMEOUT",
                        phase = pending.phase,
                        elapsed = now - (pending.startedAt or now),
                        clientConnectionGeneration = clientGen,
                    })
                    print(string.format(
                        "[服务端同步] 全量同步首包超时 userId=%s phase=%s reason=%s requestId=%s syncId=%s elapsed=%s serverGeneration=%s clientGeneration=%s %s",
                        tostring(pending.uid),
                        tostring(pending.phase),
                        tostring(waiter.reason),
                        tostring(waiter.requestId),
                        tostring(syncId),
                        tostring(now - (pending.startedAt or now)),
                        tostring(waiter.connectionGeneration),
                        tostring(clientGen),
                        BuildConnectionLogContext(connection)
                    ))
                end
            end
        end
    end
end

--- 每个连接仅首次全量同步；必须等 ClientIdentity 与客户端 scene ready 都完成。
local function TrySendFullSyncOnFirstReady(connection, uid, reason)
    local normalizedUid = NormalizeUserId(uid)
    if connection == nil or normalizedUid == nil then return false end
    local key = GetConnectionKey(connection)
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
    if not firstReady then return false end
    SendFullSync(uid, connection, reason or "first_ready", nil, nil)
    return true
end

local function TrySendFullSyncWhenBothReady(connection, reason)
    if connection == nil then return false end
    local key = GetConnectionKey(connection)
    local uid = ResolveConnectionUserId(connection)
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then
        print("[服务端就绪] 等待 ClientIdentity 认证完成后再同步存档 addr=" .. tostring(connection:GetAddress()) .. " " .. BuildConnectionLogContext(connection))
        SendIdentityNotReady(connection, nil, nil, "full_sync_wait_identity")
        return false
    end
    if clientReadyConnections_[key] ~= true then
        print("[服务端就绪] 等待客户端 scene ready userId=" .. tostring(normalizedUid) .. " addr=" .. tostring(connection:GetAddress()))
        return false
    end
    return TrySendFullSyncOnFirstReady(connection, normalizedUid, reason)
end

function ServerEventHandlers.HandleClientConnected(eventType, eventData)
    CleanupDisconnectedPlayers()
    local connection = eventData["Connection"]:GetPtr("Connection")
    RegisterConnection(connection)
    connections_[GetConnectionKey(connection)] = connection
    -- 不在 ClientConnected 设置 connection.scene，否则会早于客户端绑定 scene 触发 LoadScene。
    print(string.format(
        "[服务端] ClientConnected addr=%s %s",
        tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort()),
        BuildConnectionLogContext(connection)
    ))
end

function ServerEventHandlers.HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connectionGeneration = GetConnectionGeneration(connection)
    if not IsCurrentConnection(connection, connectionGeneration) then
        print("[服务端认证] 忽略失效连接 ClientIdentity " .. BuildConnectionLogContext(connection))
        return
    end
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
            "[服务端] ClientIdentity userId=%s generation=%s cloudId=%s addr=%s %s",
            tostring(uid),
            tostring(connectionGeneration),
            tostring(ServerCloudStore.CloudPlayerId(uid)),
            tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort()),
            BuildConnectionLogContext(connection)
        ))
        if disconnectedPlayers_[uid] ~= nil then
            pendingReconnect_[key] = uid
            print("[服务端重连] 识别到玩家重连 userId=" .. tostring(uid))
        end
        if TrySendFullSyncWhenBothReady(connection, "client_identity") then
            print(string.format(
                "[服务端就绪] ClientIdentity 后双闸门完成，全量同步 userId=%s addr=%s",
                tostring(uid),
                tostring(connection:GetAddress())
            ))
        end
    else
        print(string.format(
            "[服务端] ClientIdentity 无有效 UID raw=%s addr=%s %s",
            tostring(rawUid),
            tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort()),
            BuildConnectionLogContext(connection)
        ))
    end
end

function ServerEventHandlers.HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connectionGeneration = GetConnectionGeneration(connection)
    local key = GetConnectionKey(connection)
    local isCurrent = IsCurrentConnection(connection, connectionGeneration)
    local uid = isCurrent and NormalizeUserId(GetConnectionUserId(connection)) or nil
    if uid ~= nil then
        disconnectedPlayers_[uid] = {
            userId = uid,
            disconnectedAt = Now(),
            lastConnectionKey = key,
        }
        print("[服务端重连] 玩家断线，暂存重连上下文 userId=" .. tostring(uid))
        -- 关游戏/断线：尝试 flush；会话保留供同房重连，不 Clear
        -- 玩法 mutate 已在成功回包前 flush；此处兜底未落盘脏档
        if PlayerStateService ~= nil and PlayerStateService.Flush ~= nil then
            local session = PlayerStateService.GetSession(uid)
            if session ~= nil then
                print(string.format(
                    "[PlayerState] 断线 flush begin uid=%s dirtyE=%s dirtyF=%s pending=%s",
                    tostring(uid),
                    tostring(session.dirtyEconomy == true),
                    tostring(session.dirtyFarm == true),
                    tostring(session.flushPending == true)
                ))
            end
            PlayerStateService.Flush(uid, function(ok, reason)
                print(string.format(
                    "[PlayerState] 断线 flush uid=%s ok=%s reason=%s",
                    tostring(uid),
                    tostring(ok),
                    tostring(reason)
                ))
            end)
        end
    end
    InvalidateConnection(connection)
    if isCurrent then
        connections_[key] = nil
        connectionUsers_[key] = nil
        connKeyToUserId_[key] = nil
        if deps_.ClearConnectionUserId ~= nil then
            deps_.ClearConnectionUserId(connection)
        end
        pendingReconnect_[key] = nil
        readyConnections_[key] = nil
        clientReadyConnections_[key] = nil
    else
        print(string.format(
            "[服务端重连] 忽略旧连接断开清理 key=%s generation=%s",
            tostring(key),
            tostring(connectionGeneration)
        ))
    end
end

function ServerEventHandlers.HandleGardenClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local isCurrent = IsCurrentConnection(connection)
    if not isCurrent then
        print("[服务端就绪] 忽略失效连接 CLIENT_READY " .. BuildConnectionLogContext(connection))
        return
    end
    local key = GetConnectionKey(connection)
    local data = ReadRequest(eventData)
    clientReadyConnections_[key] = true
    local uid = ResolveConnectionUserId(connection)
    local normalizedUid = NormalizeUserId(uid)
    print(string.format(
        "[服务端就绪] 收到客户端 scene ready userId=%s requestId=%s reason=%s addr=%s key=%s %s",
        tostring(normalizedUid),
        tostring(data.requestId),
        tostring(data.reason or "client_ready"),
        tostring(connection:GetAddress()),
        tostring(key),
        BuildConnectionLogContext(connection)
    ))
    SendServerSyncAck(connection, "client_ready_received", {
        userId = normalizedUid,
        requestId = data.requestId,
        reason = data.reason or "client_ready",
        hasIdentity = normalizedUid ~= nil,
    })
    if normalizedUid == nil then
        TrySendFullSyncWhenBothReady(connection, data.reason or "client_ready")
        return
    end
    if not TrySendFullSyncWhenBothReady(connection, data.reason or "client_ready") then
        print("[服务端就绪] 忽略重复 CLIENT_READY userId=" .. tostring(normalizedUid))
    end
end

function ServerEventHandlers.HandleGardenRequestFullSync(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not IsCurrentConnection(connection) then
        print("[服务端同步] 忽略失效连接全量同步请求 " .. BuildConnectionLogContext(connection))
        return
    end
    local data = ReadRequest(eventData)
    local uid = ResolveConnectionUserId(connection)
    local normalizedUid = NormalizeUserId(uid)
    if normalizedUid == nil then
        print("[服务端同步] 等待 ClientIdentity 认证完成后再全量同步 addr=" .. tostring(connection:GetAddress()) .. " " .. BuildConnectionLogContext(connection))
        SendIdentityNotReady(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, data.requestId, "full_sync_request_identity_missing")
        Send(connection, Shared.EVENTS.AUTH_FARM_RESPONSE, {
            success = false,
            retryable = true,
            message = "玩家身份未就绪，请稍后重试",
            code = "IDENTITY_NOT_READY",
            requestId = data.requestId,
        })
        return
    end
    local key = GetConnectionKey(connection)
    print("[服务端同步] 收到客户端全量同步请求 userId=" .. tostring(normalizedUid) .. " requestId=" .. tostring(data.requestId) .. " clientGeneration=" .. tostring(data.clientConnectionGeneration) .. " serverGeneration=" .. tostring(GetConnectionGeneration(connection)) .. " reason=" .. tostring(data.reason or "request_full_sync") .. " " .. BuildConnectionLogContext(connection))
    SendServerSyncAck(connection, "full_sync_request_received", {
        userId = normalizedUid,
        requestId = data.requestId,
        clientConnectionGeneration = data.clientConnectionGeneration,
        reason = data.reason or "request_full_sync",
        clientReady = clientReadyConnections_[key] == true,
    })
    if clientReadyConnections_[key] ~= true then
        if not TrySendFullSyncWhenBothReady(connection, data.reason or "request_full_sync") then
            print("[服务端同步] 全量同步请求等待客户端 scene ready userId=" .. tostring(normalizedUid))
        end
        return
    end
    if connection.scene == nil or connection.scene ~= scene_ then
        connection.scene = scene_
    end
    SendFullSync(normalizedUid, connection, data.reason or "request_full_sync", data.requestId, data.clientConnectionGeneration)
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
    SocialServer.RequestRank(data.count, connection, uid, data.requestId)
end

function ServerEventHandlers.HandleGardenRequestLeaderboard(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.LEADERBOARD_RESPONSE, data.requestId, "leaderboard_identity_missing")
        return
    end
    RequestLeaderboardAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenClaimActivityRankReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, data.requestId, "activity_rank_reward_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenRequestSteal(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.STEAL_RESPONSE, data.requestId, "steal_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenRequestSocialState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local data = ReadRequest(eventData)
    local uid = GetRequestUserId(connection, data)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SOCIAL_STATE_RESPONSE, data.requestId, "social_state_identity_missing")
        return
    end
    SocialServer.RequestSocialState(uid, connection)
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
    local data = ReadRequest(eventData)
    if deps_.SendFullAvailableSeedShop ~= nil then
        deps_.SendFullAvailableSeedShop(connection, Shared.EVENTS.SEED_SHOP_RESPONSE, {
            success = true,
            requestId = data.requestId,
        })
        return
    end
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
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.AD_REWARD_RESPONSE, data.requestId, "ad_reward_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenBuySeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.BUY_SEED_RESPONSE, data.requestId, "buy_seed_identity_missing")
        return
    end
    RequestGuard.Check(uid, "buy_seed", data.requestId, function(recordKey)
        BuySeed(uid, data.plantIndex, data.price, connection, data.count, data.requestId, data.refreshId, recordKey)
    end, function(record)
        local response = record.response or record
        deps_.SendFullAvailableSeedShop(connection, Shared.EVENTS.BUY_SEED_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenClearSave(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, data.requestId, "clear_save_identity_missing")
        return
    end
    RequestGuard.Check(uid, "clear_save", data.requestId, function(recordKey)
        ClearPlayerSave(uid, connection, data.requestId, recordKey, {
            includeCommission = data.reopenSave == true,
            commissionStateKey = deps_.commissionStateKey,
        })
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.CLEAR_SAVE_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenPlantSeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    print(string.format("[播种请求][服务端] 收到 uid=%s requestId=%s plot=%s plant=%s", tostring(uid), tostring(data.requestId), tostring(data.plotIndex), tostring(data.plantIndex)))
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, data.requestId, "plant_seed_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenHarvestCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    print(string.format("[收获请求][服务端] 收到 uid=%s requestId=%s plot=%s cropId=%s cropIndex=%s", tostring(uid), tostring(data.requestId), tostring(data.plotIndex), tostring(data.cropId), tostring(data.cropIndex)))
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, data.requestId, "harvest_crop_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenOpenSeedPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, data.requestId, "open_seed_pack_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenSellHarvested(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, data.requestId, "sell_harvested_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenRequestCommissions(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.COMMISSIONS_RESPONSE, data.requestId, "commissions_identity_missing")
        return
    end
    RequestCommissionsAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenCompleteCommission(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, data.requestId, "complete_commission_identity_missing")
        return
    end
    CompleteCommissionAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenSubmitActivityCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, data.requestId, "submit_activity_crop_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenExchangeActivityReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, data.requestId, "exchange_activity_reward_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenDrawActivityPack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, data.requestId, "draw_activity_pack_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenClaimDailyReward(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, data.requestId, "claim_daily_reward_identity_missing")
        return
    end
    ClaimDailyRewardAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenSynthesizePack(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, data.requestId, "synthesize_pack_identity_missing")
        return
    end
    SynthesizePackAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenUnlockTalent(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.UNLOCK_TALENT_RESPONSE, data.requestId, "unlock_talent_identity_missing")
        return
    end
    UnlockTalentAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenExpandPlot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.EXPAND_PLOT_RESPONSE, data.requestId, "expand_plot_identity_missing")
        return
    end
    ExpandPlotAuthority(uid, data, connection)
end

function ServerEventHandlers.HandleGardenSendSeedGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, data.requestId, "send_seed_gift_identity_missing")
        return
    end
    RequestGuard.Check(uid, "gift", data.requestId, function(recordKey)
        GiftServer.SendSeedGift(uid, data.targetUserId, data.seedId, data.count, connection, data.requestId, recordKey, data.profile)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenLikeGarden(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, data.requestId, "like_garden_identity_missing")
        return
    end
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

function ServerEventHandlers.HandleGardenSendFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, data.requestId, "send_friend_request_identity_missing")
        return
    end
    RequestGuard.Check(uid, "friend_request", data.requestId, function(recordKey)
        SocialServer.SendFriendRequest(uid, data.targetUserId, connection, data.requestId, recordKey, data.profile)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenRespondFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, data.requestId, "respond_friend_request_identity_missing")
        return
    end
    RequestGuard.Check(uid, "friend_respond", data.requestId, function(recordKey)
        SocialServer.RespondFriendRequest(uid, data.requestIdValue, data.fromUserId, data.accepted == true, connection, data.requestId, recordKey)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenRemoveFriend(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, data.requestId, "remove_friend_identity_missing")
        return
    end
    RequestGuard.Check(uid, "remove_friend", data.requestId, function(recordKey)
        SocialServer.RemoveFriend(uid, data.friendUserId, connection, data.requestId, recordKey)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId, friendUserId = data.friendUserId })
    end)
end

function ServerEventHandlers.HandleGardenClearSocialMessages(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, data.requestId, "clear_social_messages_identity_missing")
        return
    end
    RequestGuard.Check(uid, "clear_social_messages", data.requestId, function(recordKey)
        SocialServer.ClearSocialMessages(uid, connection, data.requestId, recordKey)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
end

function ServerEventHandlers.HandleGardenRequestGifts(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.GIFTS_RESPONSE, nil, "request_gifts_identity_missing")
        return
    end
    GiftServer.RequestGifts(uid, connection)
end

function ServerEventHandlers.HandleGardenClaimGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid == nil then
        SendIdentityNotReady(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, data.requestId, "claim_gift_identity_missing")
        return
    end
    RequestGuard.Check(uid, "claim_gift", data.requestId, function(recordKey)
        GiftServer.ClaimGift(uid, data.giftId or data.listId, data.seedId, data.count, connection, data.requestId, recordKey)
    end, function(record)
        local response = record.response or record
        Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, response)
    end, function(reason)
        Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = false, message = "请求去重检查失败: " .. tostring(reason), requestId = data.requestId })
    end)
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
