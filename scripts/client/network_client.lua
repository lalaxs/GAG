-- ============================================================================
-- 客户端网络层
-- Grow A Garden
-- ============================================================================
-- 统一连接检测、远程请求发送、CLIENT_READY 绑定与权威重同步。
-- NetworkRecovery 负责断线 UI/轮询；本模块负责底层网络与会话语义。
-- ============================================================================

local Shared = require("network.shared")
local UserId = require("utils.user_id")

local NetworkClient = {}

local deps_ = {}
local requestFailureNotifyCooldown_ = 0
local trackedConnection_ = nil
local connectionGeneration_ = 0
local lastConnectionKey_ = nil

local function NotifyRequestFailed(reason, message, options)
    if deps_.NetworkRecovery ~= nil and deps_.NetworkRecovery.NotifyServerRequestFailed ~= nil then
        deps_.NetworkRecovery.NotifyServerRequestFailed(reason, message, options)
    elseif deps_.showToast ~= nil then
        deps_.showToast(message or "网络连接失败，请检查网络后重试")
    end
end

function NetworkClient.Init(deps)
    deps_ = deps or {}
end

function NetworkClient.Update(dt)
    if requestFailureNotifyCooldown_ > 0 then
        requestFailureNotifyCooldown_ = math.max(0, requestFailureNotifyCooldown_ - (dt or 0))
    end
    local conn = NetworkClient.GetConnection()
    if conn ~= trackedConnection_ then
        trackedConnection_ = conn
        connectionGeneration_ = connectionGeneration_ + 1
        lastConnectionKey_ = nil
        print(string.format(
            "[客户端连接] 连接世代变化 generation=%s connection=%s",
            tostring(connectionGeneration_),
            tostring(conn ~= nil)
        ))
    end
end

function NetworkClient.ReportRequestFailure(reason, message, force, options)
    options = options or {}
    if force == true then options.critical = true end
    if options.critical ~= true then
        print("[网络请求] 非关键请求失败，不进入全局断线 reason=" .. tostring(reason or "request_failed"))
        if deps_.showToast ~= nil and message ~= nil and message ~= "" then
            deps_.showToast(message)
        end
        return false
    end
    if force ~= true and requestFailureNotifyCooldown_ > 0 then return false end
    requestFailureNotifyCooldown_ = 2.0
    NotifyRequestFailed(reason or "request_failed", message or "网络连接失败，服务器请求未响应。请检查网络后点击重新连接", options)
    return true
end

local function IsNetworkFailureMessage(message)
    message = tostring(message or "")
    if message == "" then return false end
    return string.find(message, "同步失败", 1, true) ~= nil
        or string.find(message, "农场同步失败", 1, true) ~= nil
        or string.find(message, "玩家身份未就绪", 1, true) ~= nil
        or string.find(message, "服务器尚未就绪", 1, true) ~= nil
        or string.find(message, "服务器未连接", 1, true) ~= nil
end

local function IsServerBusyMessage(message, code)
    if code == "RATE_LIMITED" then return true end
    message = tostring(message or "")
    if message == "" then return false end
    return string.find(message, "花园同步中", 1, true) ~= nil
        or string.find(message, "榜单繁忙", 1, true) ~= nil
        or string.find(message, "服务器繁忙", 1, true) ~= nil
        or string.find(message, "read rate limit exceeded", 1, true) ~= nil
end

function NetworkClient.ReportServerResponseFailure(data, reason)
    data = data or {}
    if data.success == true then return false end
    local message = tostring(data.message or "")
    if string.find(message, "玩家身份未就绪", 1, true) ~= nil then
        return NetworkClient.ReportRequestFailure(
            "identity_not_ready",
            "网络会话已失效，正在等待平台重新认证。若长时间无响应，请刷新页面重新进入游戏",
            true
        )
    end
    if IsServerBusyMessage(message, data.code) then
        return false
    end
    if data.retryable == true or IsNetworkFailureMessage(message) then
        local failureReason = tostring(reason or "server_response_failed")
        local critical = failureReason == "load" or failureReason == "authFarm"
        return NetworkClient.ReportRequestFailure(
            failureReason,
            critical and "网络连接失败，服务器暂时无法响应。请检查网络后点击重新连接" or (message ~= "" and message or "服务器响应较慢，请稍后重试"),
            critical,
            { critical = critical }
        )
    end
    return false
end

function NetworkClient.IsClientMode()
    return network ~= nil and IsClientMode ~= nil and IsClientMode()
end

function NetworkClient.GetConnection()
    if not NetworkClient.IsClientMode() then return nil end
    return network:GetServerConnection()
end

function NetworkClient.IsConnectionAlive(conn)
    if conn == nil then return false end
    if conn.IsConnected ~= nil then
        return conn:IsConnected() == true
    end
    if conn.connected ~= nil then
        return conn.connected == true
    end
    return true
end

function NetworkClient.GetAliveConnection()
    local conn = NetworkClient.GetConnection()
    if NetworkClient.IsConnectionAlive(conn) ~= true then return nil end
    return conn
end

function NetworkClient.GetGameSessionId()
    local conn = NetworkClient.GetAliveConnection()
    local sessionId = UserId.ReadConnectionGameSessionId(conn)
    return sessionId
end

function NetworkClient.GetConnectionGeneration()
    return connectionGeneration_
end

function NetworkClient.GetConnectionContext()
    return {
        generation = connectionGeneration_,
        connectionKey = NetworkClient.GetConnectionKey(),
        gameSessionId = NetworkClient.GetGameSessionId(),
    }
end

function NetworkClient.IsCurrentConnection(conn, generation)
    if conn == nil or conn ~= NetworkClient.GetConnection() then return false end
    return generation == nil or generation == connectionGeneration_
end

function NetworkClient.GetConnectionKey()
    local conn = NetworkClient.GetAliveConnection()
    if conn == nil then return nil end
    local address = conn.GetAddress ~= nil and conn:GetAddress() or tostring(conn.address or "")
    local port = conn.GetPort ~= nil and conn:GetPort() or tostring(conn.port or "")
    return tostring(address) .. ":" .. tostring(port)
end

function NetworkClient.GetConnectionLogContext()
    local key = NetworkClient.GetConnectionKey() or "nil"
    return string.format(
        "game_session_id=%s conn=%s generation=%s",
        tostring(NetworkClient.GetGameSessionId() or "unknown"),
        key,
        tostring(connectionGeneration_)
    )
end

--- 底层 serverConnection 是否可用（匹配完成，尚未 necessarily CLIENT_READY）。
function NetworkClient.IsRawConnected()
    return NetworkClient.GetAliveConnection() ~= nil
end

--- CLIENT_READY 已发送且社交层已绑定（权威 push 主轴就绪）。
function NetworkClient.IsSessionBound()
    local socialGardenSystem = deps_.SocialGardenSystem
    if socialGardenSystem ~= nil and socialGardenSystem.IsServerBound ~= nil then
        return socialGardenSystem.IsServerBound() == true
    end
    return false
end

function NetworkClient.SendRequest(eventName, payload)
    if not NetworkClient.IsRawConnected() then
        NetworkClient.ReportRequestFailure("no_room_connection", "网络连接失败，当前没有房间服务器连接。请检查网络后点击重新连接", true, { critical = true })
        return false
    end
    if not NetworkClient.IsSessionBound() then
        NetworkClient.BindServerConnection(true)
        if not NetworkClient.IsSessionBound() then
            NetworkClient.ReportRequestFailure("session_not_bound", "网络连接失败，无法绑定房间服务器。请点击重新连接", true, { critical = true })
            return false
        end
    end
    local sent = Shared.SendToServer(eventName, payload)
    if sent ~= true then
        NetworkClient.ReportRequestFailure("send_failed", "网络连接失败，请检查网络后点击重新连接", true, { critical = true })
        return false
    end
    return true
end

function NetworkClient.EnsureConnectionScene(getScene)
    local conn = NetworkClient.GetAliveConnection()
    if conn == nil then return false end
    local scene = type(getScene) == "function" and getScene() or nil
    if scene == nil then return false end
    if conn.scene == nil then
        conn.scene = scene
    end
    return true
end

function NetworkClient.BindServerConnection(forceReady)
    local socialGardenSystem = deps_.SocialGardenSystem
    if socialGardenSystem ~= nil and socialGardenSystem.BindServerConnection ~= nil then
        return socialGardenSystem.BindServerConnection(forceReady == true)
    end
    return false, false
end

function NetworkClient.RequestAuthoritySync(reason)
    local socialGardenSystem = deps_.SocialGardenSystem
    local economyCloudSystem = deps_.EconomyCloudSystem
    if socialGardenSystem == nil or economyCloudSystem == nil then return false end

    local syncReason = reason or "session_sync"
    local bound = NetworkClient.IsSessionBound()
    if not bound then
        bound = NetworkClient.BindServerConnection(false) == true
    end
    if not bound or not NetworkClient.IsSessionBound() then
        print("[网络同步] 会话尚未绑定，跳过无效权威同步: " .. tostring(syncReason))
        return false
    end

    local requested = false
    if economyCloudSystem.RequestFullSync ~= nil then
        requested = economyCloudSystem.RequestFullSync(syncReason) == true
    elseif socialGardenSystem.RequestFullSync ~= nil then
        requested = socialGardenSystem.RequestFullSync(syncReason) == true
    else
        requested = economyCloudSystem.RequestState({ force = true, reason = syncReason }) == true or requested
        economyCloudSystem.RequestSeedShop()
        requested = economyCloudSystem.RequestAuthFarm({ force = true, reason = syncReason }) == true or requested
        requested = socialGardenSystem.RequestSocialState({ force = true, reason = syncReason }) == true or requested
    end
    if economyCloudSystem.IsReady(false) then
        economyCloudSystem.RequestCommissions()
    end
    if socialGardenSystem.UploadSnapshot ~= nil
        and socialGardenSystem.IsSocialSaveLoaded ~= nil
        and socialGardenSystem.IsSocialSaveLoaded() == true then
        socialGardenSystem.UploadSnapshot()
    end
    return requested
end

return NetworkClient
