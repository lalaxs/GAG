-- ============================================================================
-- 网络断线恢复运行时
-- Grow A Garden
-- ============================================================================
-- 客户端在后台匹配模式下可能收不到第二次 ServerReady。
-- 恢复逻辑不能只依赖 ServerReady：只要轮询发现 serverConnection 已恢复，
-- 就主动重新绑定 scene、发送 CLIENT_READY，并强制拉取服务端权威状态。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local NetworkClient = require("client.network_client")

local NetworkRecovery = {}

local deps_ = {}
local state_ = {
    checkInterval = 0.75,
    timer = 0,
    wasConnected = false,
    serverReady = false,
    syncPending = false,
    loadingElapsed = 0,
    loadingHintShown = false,
    loadingNoticeElapsed = 0,
    loadingNoConnectionTimeout = 20.0,
    platformWaitActive = false,
    platformWaitElapsed = 0,
    platformWaitTimeout = 15.0,
    platformWaitTimedOut = false,
    platformWaitNoticeElapsed = 0,
    platformWaitNoticeInterval = 5.0,
    platformWaitToastShown = false,
    lastConnectionKey = nil,
    rawConnectedWithoutReadyElapsed = 0,
    disconnectedNoticeElapsed = 0,
    disconnectedNoticeInterval = 10.0,
    rawReadyFallbackDelay = 1.5,
    syncCooldown = 0,
    minSyncInterval = 1.5,
    pendingSyncReason = nil,
    retrying = false,
    initialClientReadyGrace = 0,
    -- 已绑定但迟迟收不到经济/农场权威：多为匹配层“before connection”僵尸连接
    authorityWaitElapsed = 0,
    -- 服务端首包 Load 可能含数次云读；过短会误杀慢但健康的 FullSync
    zombieAuthorityTimeout = 45.0,
    authorityRetryInterval = 10.0,
    authorityRetryElapsed = 0,
    authorityRetryCount = 0,
    maxAuthorityAutoRetries = 2,
    zombieRecoverCooldown = 0,
    zombieRecoverCount = 0,
    zombieUnhealthy = false,
    lastRestoreRequestAt = 0,
    restoreRequestCooldown = 4.0,
}

local disconnectModal_ = nil
local retryButton_ = nil
local statusLabel_ = nil
---@type fun(message: string|nil)
local ShowDisconnectModal = nil
---@type fun(): boolean
local EnsureDisconnectModalMounted = nil

function NetworkRecovery.IsDisconnectModalOpen()
    return disconnectModal_ ~= nil
        and disconnectModal_.IsOpen ~= nil
        and disconnectModal_:IsOpen() == true
end

function NetworkRecovery.EnsureDisconnectModalMounted()
    return EnsureDisconnectModalMounted()
end

function NetworkRecovery.Init(deps)
    deps_ = deps or {}
    if deps_.ModalRegistry ~= nil and deps_.ModalRegistry.Register ~= nil then
        deps_.ModalRegistry.Register("networkRecovery", function()
            return NetworkRecovery.IsDisconnectModalOpen()
        end)
    end
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then
        deps_.showToast(text, silent)
    end
end

local function Now()
    return os and os.clock and os.clock() or 0
end

local function IsRestoreRequestCoolingDown()
    return Now() - (state_.lastRestoreRequestAt or 0) < (state_.restoreRequestCooldown or 4.0)
end

local function MarkRestoreRequest()
    state_.lastRestoreRequestAt = Now()
end

local function IsDisconnectModalOpen()
    return NetworkRecovery.IsDisconnectModalOpen()
end

EnsureDisconnectModalMounted = function()
    if not IsDisconnectModalOpen() then return false end
    local root = UI.GetRoot()
    if root == nil then return false end
    if disconnectModal_.parent == root then return true end
    if disconnectModal_.parent ~= nil and disconnectModal_.parent.RemoveChild ~= nil then
        disconnectModal_.parent:RemoveChild(disconnectModal_)
    end
    root:AddChild(disconnectModal_)
    disconnectModal_.autoMountParent_ = root
    UI.PushOverlay(disconnectModal_)
    print("[网络恢复] 已重新挂载断线弹窗到当前 UI 根节点")
    return true
end

local function GetSocialGardenSystem()
    return deps_.SocialGardenSystem
end

local function EnsureConnectionScene()
    if deps_.getScene ~= nil then
        NetworkClient.EnsureConnectionScene(deps_.getScene)
    end
end

local function BindServerConnection(forceReady)
    return NetworkClient.BindServerConnection(forceReady)
end

local function GetServerConnection()
    if NetworkClient.GetAliveConnection ~= nil then
        return NetworkClient.GetAliveConnection()
    end
    return NetworkClient.GetConnection()
end

local function GetConnectionKey(connection)
    if connection == nil then return nil end
    local address = connection.GetAddress ~= nil and connection:GetAddress() or tostring(connection.address or "")
    local port = connection.GetPort ~= nil and connection:GetPort() or tostring(connection.port or "")
    return tostring(address) .. ":" .. tostring(port)
end

local function ReadVariantBool(value)
    if value == nil then return false end
    if type(value) == "boolean" then return value == true end
    if type(value.GetBool) == "function" then
        local ok, result = pcall(function() return value:GetBool() end)
        if ok then return result == true end
    end
    return tostring(value) == "true"
end

local function IsReconnectConnection(connection)
    if connection == nil then return false end
    local identity = connection.identity
    if identity == nil and connection.GetIdentity ~= nil then
        local ok, result = pcall(function() return connection:GetIdentity() end)
        if ok then identity = result end
    end
    if identity == nil then return false end
    return ReadVariantBool(identity["is_reconnect"])
end

local function BuildConnectionDebugText(connection)
    if connection == nil then return "connection=nil" end
    local alive = NetworkClient.IsConnectionAlive ~= nil and NetworkClient.IsConnectionAlive(connection) == true
    return string.format(
        "key=%s game_session_id=%s alive=%s reconnect=%s connected=%s pending=%s rtt=%s lastHeard=%s",
        tostring(GetConnectionKey(connection)),
        tostring(NetworkClient.GetGameSessionId ~= nil and NetworkClient.GetGameSessionId() or "unknown"),
        tostring(alive),
        tostring(IsReconnectConnection(connection)),
        tostring(connection.connected),
        tostring(connection.connectPending),
        tostring(connection.roundTripTime),
        tostring(connection.lastHeardTime)
    )
end

local function ReadEventFieldText(eventData, field)
    if eventData == nil then return "" end
    local value = nil
    if type(eventData.GetVariant) == "function" then
        local ok, result = pcall(function() return eventData:GetVariant(field) end)
        if ok then value = result end
    end
    if value == nil and eventData[field] ~= nil then
        value = eventData[field]
    end
    if value == nil then return "" end
    if type(value.GetString) == "function" then
        local ok, result = pcall(function() return value:GetString() end)
        if ok and result ~= nil and result ~= "" then return tostring(result) end
    end
    if type(value.GetInt) == "function" then
        local ok, result = pcall(function() return value:GetInt() end)
        if ok and result ~= nil then return tostring(result) end
    end
    return tostring(value)
end

local function BuildTransportDebugText(eventData)
    return string.format(
        "address=%s port=%s protocol=%s reason=%s error=%s",
        ReadEventFieldText(eventData, "Address"),
        ReadEventFieldText(eventData, "Port"),
        ReadEventFieldText(eventData, "Protocol"),
        ReadEventFieldText(eventData, "Reason"),
        ReadEventFieldText(eventData, "Error")
    )
end

local function IsRawServerConnectionAvailable()
    return NetworkClient.IsRawConnected()
end

local function IsReadyServerConnectionAvailable()
    return state_.serverReady == true and IsRawServerConnectionAvailable()
end

local function IsAuthoritySynced()
    local economy = deps_.EconomyCloudSystem
    if economy == nil then return false end
    if economy.IsInitialAuthorityDegraded ~= nil and economy.IsInitialAuthorityDegraded() == true then return false end
    if economy.IsInitialSyncReady == nil then return false end
    return economy.IsInitialSyncReady() == true
end

local function ClearServerBind()
    local socialGardenSystem = GetSocialGardenSystem()
    if socialGardenSystem ~= nil and socialGardenSystem.ClearServerBind ~= nil then
        socialGardenSystem.ClearServerBind()
    end
end

local function MarkAuthoritySyncPending(reason)
    local economy = deps_.EconomyCloudSystem
    if economy ~= nil and economy.MarkAuthoritySyncPending ~= nil then
        economy.MarkAuthoritySyncPending(reason)
    end
end

local function ClearBusinessPending(reason)
    local economy = deps_.EconomyCloudSystem
    if economy ~= nil and economy.ClearPendingRequests ~= nil then
        economy.ClearPendingRequests(reason)
    end
    local social = deps_.SocialGardenSystem
    if social ~= nil and social.ClearPendingRequests ~= nil then
        social.ClearPendingRequests(reason)
    end
    local leaderboard = deps_.LeaderboardSystem
    if leaderboard ~= nil and leaderboard.ClearPendingRequests ~= nil then
        leaderboard.ClearPendingRequests(reason)
    end
end

local function GetAuthorityStage()
    if state_.zombieUnhealthy == true then
        return "网络会话失效，请刷新重进"
    end
    if state_.platformWaitTimedOut == true then
        return "房间连接未恢复，请刷新重进"
    end
    if state_.platformWaitActive == true and IsRawServerConnectionAvailable() ~= true then
        return "等待平台恢复房间连接"
    end
    if IsRawServerConnectionAvailable() ~= true then return "等待平台恢复房间连接" end
    local economy = deps_.EconomyCloudSystem
    if economy ~= nil and economy.GetState ~= nil then
        local state = economy.GetState()
        if type(state) == "table" then
            if state.ready == true and state.authFarmReady == true then return "权威数据已同步" end
            if state.ready == true then return "等待权威农场" end
            if state.authFarmReady == true then return "等待经济状态" end
        end
    end
    if IsRawServerConnectionAvailable() ~= true then return "等待平台恢复房间连接" end
    local socialGardenSystem = GetSocialGardenSystem()
    local bound = socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true
    if bound ~= true then return "等待发送客户端就绪" end
    return "等待服务器权威首包"
end

local function CompactStatusLine(text)
    text = tostring(text or "网络连接已断开，请检查网络后重试")
    text = string.gsub(text, "恢复后会自动重新同步数据。", "恢复后自动同步。")
    text = string.gsub(text, "正在等待平台恢复房间连接", "等待平台恢复房间连接")
    text = string.gsub(text, "当前没有房间服务器连接", "暂无房间服务器连接")
    text = string.gsub(text, "请检查网络后点击重新连接", "请检查网络后重试")
    return text
end

local function BuildStatusMessage(message)
    local stage = GetAuthorityStage()
    local elapsed = math.floor((state_.authorityWaitElapsed or 0) + 0.5)
    if state_.platformWaitActive == true and IsRawServerConnectionAvailable() ~= true then
        elapsed = math.floor((state_.platformWaitElapsed or 0) + 0.5)
    end
    local retries = tonumber(state_.authorityRetryCount or 0) or 0
    local lines = {
        CompactStatusLine(message),
        "阶段：" .. tostring(stage),
    }
    if elapsed > 0 then lines[#lines + 1] = "等待：" .. tostring(elapsed) .. "秒" end
    if retries > 0 then lines[#lines + 1] = "已自动重试：" .. tostring(retries) .. "次" end
    return table.concat(lines, "\n")
end

---@type fun(reason: string|nil): boolean
local RecoverZombieConnection
---@type fun(reason: string|nil): boolean
local ForceReadyFromRawConnection
---@type fun(text: string|nil, retrying: boolean|nil)
local SetDisconnectModalStatus

local function RetryAuthorityHandshake(reason)
    if state_.authorityRetryCount >= state_.maxAuthorityAutoRetries then return false end
    if not IsRawServerConnectionAvailable() then return false end
    state_.authorityRetryCount = state_.authorityRetryCount + 1
    state_.authorityRetryElapsed = 0
    state_.syncCooldown = 0
    state_.syncPending = true
    ClearServerBind()
    MarkAuthoritySyncPending(tostring(reason or "authority_retry"))
    state_.serverReady = false
    print(string.format(
        "[网络恢复] 自动重新发送 CLIENT_READY 与权威同步请求 count=%s reason=%s",
        tostring(state_.authorityRetryCount),
        tostring(reason or "authority_retry")
    ))
    local ok = ForceReadyFromRawConnection(reason or "authority_retry")
    if ok == true then
        SetDisconnectModalStatus("已自动重新连接，正在等待服务器权威状态...", false)
        return true
    end
    SetDisconnectModalStatus("自动重新连接请求未发出，等待下一次重试或手动点击重新连接。", false)
    return false
end

SetDisconnectModalStatus = function(text, retrying)
    state_.retrying = retrying == true
    EnsureDisconnectModalMounted()
    if statusLabel_ ~= nil then statusLabel_:SetText(BuildStatusMessage(text or "网络连接已断开")) end
    if retryButton_ ~= nil then
        retryButton_:SetDisabled(state_.retrying)
        local buttonText = "检查连接"
        if state_.retrying then
            buttonText = "处理中..."
        elseif state_.platformWaitTimedOut == true and IsRawServerConnectionAvailable() ~= true then
            buttonText = "请刷新重进"
        elseif IsRawServerConnectionAvailable() then
            buttonText = "重试同步"
        end
        retryButton_:SetText(buttonText)
    end
end

local function ClearPlatformWait()
    state_.platformWaitActive = false
    state_.platformWaitElapsed = 0
    state_.platformWaitTimedOut = false
    state_.platformWaitNoticeElapsed = 0
    state_.platformWaitToastShown = false
end

local function StartPlatformWait(message)
    if state_.platformWaitActive ~= true then
        state_.platformWaitActive = true
        state_.platformWaitElapsed = 0
        state_.platformWaitTimedOut = false
        state_.platformWaitNoticeElapsed = 0
        state_.platformWaitToastShown = false
        print("[网络恢复] 未获得 serverConnection，进入平台房间连接等待状态")
    end
    SetDisconnectModalStatus(message or "当前没有房间服务器连接，正在等待平台恢复。请确认网络已恢复。", false)
end

local function SetPlatformWaitTimedOut()
    state_.platformWaitTimedOut = true
    SetDisconnectModalStatus("未能恢复房间连接，请刷新页面重新进入游戏。", false)
end

local function CloseDisconnectModal()
    if disconnectModal_ ~= nil then
        disconnectModal_:Close()
        disconnectModal_ = nil
    end
    retryButton_ = nil
    statusLabel_ = nil
    state_.retrying = false
    ClearPlatformWait()
end

ShowDisconnectModal = function(message)
    if disconnectModal_ ~= nil then
        SetDisconnectModalStatus(message or "网络连接已断开，请检查网络后重试", false)
        return
    end
    disconnectModal_ = UI.Modal {
        title = "网络连接断开",
        size = "sm",
        closeOnOverlay = false,
        showCloseButton = false,
        contentPadding = {18, 20, 20, 20},
        contentGap = 14,
        onClose = function()
            disconnectModal_ = nil
            retryButton_ = nil
            statusLabel_ = nil
            ClearPlatformWait()
        end,
    }

    statusLabel_ = UI.Label {
        text = BuildStatusMessage(message or "网络连接已断开，请检查网络后重试"),
        width = "100%",
        fontSize = 14,
        lineHeight = 1.3,
        fontColor = {92, 70, 48, 255},
        textAlign = "center",
        whiteSpace = "normal",
        wordBreak = "break-word",
        maxLines = 6,
    }

    retryButton_ = UI.Button {
        text = IsRawServerConnectionAvailable() and "重试同步" or "检查连接",
        width = 168,
        height = 44,
        alignSelf = "center",
        fontSize = 16,
        fontWeight = "bold",
        backgroundColor = {78, 155, 100, 255},
        fontColor = {255, 255, 255, 255},
        borderRadius = 16,
        onClick = function()
            NetworkRecovery.RetryNow()
        end,
    }

    disconnectModal_:AddContent(UI.Panel {
        width = "100%",
        gap = 14,
        alignItems = "center",
        children = {
            UI.Label {
                text = "当前无法连接到游戏服务器，部分操作可能无法保存。",
                width = "100%",
                fontSize = 14,
                lineHeight = 1.3,
                fontColor = {116, 92, 58, 235},
                textAlign = "center",
                whiteSpace = "normal",
                wordBreak = "break-word",
                maxLines = 3,
            },
            statusLabel_,
            retryButton_,
        },
    })
    ModalAnim.Apply(disconnectModal_, { fixedHeight = 325 })
    disconnectModal_:Open()
    EnsureDisconnectModalMounted()
end

function NetworkRecovery.IsServerConnectionAvailable()
    return IsReadyServerConnectionAvailable()
end

function NetworkRecovery.HasRawServerConnection()
    return IsRawServerConnectionAvailable()
end

function NetworkRecovery.RequestSync(reason)
    if state_.zombieUnhealthy == true then
        print("[网络恢复] 已判定平台僵尸连接，跳过权威重试: " .. tostring(reason))
        return false
    end
    if state_.initialClientReadyGrace > 0 and reason ~= "manual_retry" and IsAuthoritySynced() then
        state_.syncPending = false
        state_.pendingSyncReason = nil
        print("[网络恢复] 初始 CLIENT_READY 同步保护中，权威数据已就绪，跳过重复同步: " .. tostring(reason))
        return false
    end
    if not IsReadyServerConnectionAvailable() then
        state_.syncPending = true
        state_.pendingSyncReason = reason or state_.pendingSyncReason
        return false
    end
    local syncReason = reason or state_.pendingSyncReason or "network_recovered"
    if state_.syncCooldown > 0 then
        state_.syncPending = true
        state_.pendingSyncReason = syncReason
        print("[网络恢复] 同步请求过于频繁，已延后: " .. tostring(syncReason))
        return false
    end
    state_.syncPending = false
    state_.pendingSyncReason = nil
    state_.syncCooldown = state_.minSyncInterval
    local requested = NetworkClient.RequestAuthoritySync(syncReason)
    if requested ~= true then
        state_.syncPending = true
        state_.pendingSyncReason = syncReason
        state_.syncCooldown = math.min(state_.syncCooldown, 0.3)
        print("[网络恢复] 权威数据重同步未发出，等待会话绑定: " .. tostring(syncReason))
        return false
    end
    SetDisconnectModalStatus("已连接服务器，正在同步权威数据...", false)
    print("[网络恢复] 已请求服务器权威数据重同步: " .. tostring(syncReason))
    return true
end

function NetworkRecovery.RestoreOwnFarm(message)
    local socialGardenSystem = GetSocialGardenSystem()
    if not socialGardenSystem.IsVisitMode() then return false end
    socialGardenSystem.ReturnHome()
    if message ~= nil then ShowToast(message) end
    return true
end

ForceReadyFromRawConnection = function(reason)
    if not IsRawServerConnectionAvailable() then return false end
    ClearPlatformWait()
    local socialGardenSystem = GetSocialGardenSystem()
    local alreadyBound = socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true
    if socialGardenSystem ~= nil and alreadyBound ~= true then
        BindServerConnection(true)
    end
    state_.serverReady = socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true
    if state_.serverReady ~= true then
        state_.syncPending = true
        return false
    end
    if IsAuthoritySynced() == true then
        state_.syncPending = false
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        CloseDisconnectModal()
        return true
    end
    if IsRestoreRequestCoolingDown() then
        state_.syncPending = true
        print("[网络恢复] 恢复同步请求冷却中，跳过重复 FullSync reason=" .. tostring(reason))
        return true
    end
    state_.syncPending = true
    MarkRestoreRequest()
    MarkAuthoritySyncPending(tostring(reason or "raw_connection_ready"))
    NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
    return NetworkRecovery.RequestSync(reason or "raw_connection_ready")
end

local function TryRestoreFromCurrentConnection(reason, message)
    local rawConnection = NetworkClient.GetConnection ~= nil and NetworkClient.GetConnection() or nil
    local aliveConnection = GetServerConnection()
    print(string.format(
        "[网络恢复] 收到底层连接事件 reason=%s raw={%s} alive=%s",
        tostring(reason),
        BuildConnectionDebugText(rawConnection),
        tostring(aliveConnection ~= nil)
    ))

    state_.zombieRecoverCooldown = 0
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.syncCooldown = 0
    state_.pendingSyncReason = tostring(reason or "platform_reconnect")

    if aliveConnection == nil then
        state_.serverReady = false
        state_.wasConnected = false
        state_.syncPending = true
        state_.lastConnectionKey = nil
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        ClearServerBind()
        MarkAuthoritySyncPending(tostring(reason or "platform_reconnect_wait"))
        ClearPlatformWait()
        ShowDisconnectModal(message or "平台正在恢复房间连接，等待服务器连接恢复。")
        StartPlatformWait(message or "平台正在恢复房间连接，等待服务器连接恢复。")
        return false
    end

    state_.zombieUnhealthy = false
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.lastConnectionKey = GetConnectionKey(aliveConnection)
    state_.authorityWaitElapsed = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    if reason == "server_connected" and IsDisconnectModalOpen() ~= true then
        EnsureConnectionScene()
        print("[网络恢复] 首次 ServerConnected 等待 ServerReady，避免提前重复 FullSync")
        return true
    end
    if IsAuthoritySynced() == true and NetworkClient.IsSessionBound ~= nil and NetworkClient.IsSessionBound() == true then
        state_.serverReady = true
        state_.wasConnected = true
        state_.syncPending = false
        CloseDisconnectModal()
        print("[网络恢复] 权威数据已就绪，忽略重复底层连接事件 reason=" .. tostring(reason))
        return true
    end
    ClearServerBind()
    EnsureConnectionScene()
    SetDisconnectModalStatus(message or "已检测到服务器连接，正在重新绑定...", false)
    if ForceReadyFromRawConnection(reason or "platform_reconnect") then
        SetDisconnectModalStatus("已重新连接服务器，正在同步权威数据...", false)
        ShowToast("已重新连接，正在同步数据")
        return true
    end
    SetDisconnectModalStatus("已检测到服务器连接，但客户端就绪请求未发出，请再次点击重新连接。", false)
    ShowToast("服务器连接已恢复，请再次点击重新连接")
    return false
end

function NetworkRecovery.HandleNetworkReconnecting()
    print("[网络恢复] 收到 NetworkReconnecting，平台开始恢复网络连接")
    state_.zombieUnhealthy = false
    state_.zombieRecoverCooldown = 0
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.pendingSyncReason = "network_reconnecting"
    ClearServerBind()
    MarkAuthoritySyncPending("network_reconnecting")
    ShowDisconnectModal("网络正在恢复，等待平台重新连接房间服务器。")
    StartPlatformWait("网络正在恢复，等待平台重新连接房间服务器。")
end

function NetworkRecovery.HandleNetworkReconnected()
    TryRestoreFromCurrentConnection("network_reconnected", "平台网络已恢复，正在重新绑定房间服务器。")
end

function NetworkRecovery.HandleServerConnected()
    TryRestoreFromCurrentConnection("server_connected", "服务器连接已恢复，正在重新绑定房间会话。")
end

function NetworkRecovery.HandleConnectFailed()
    print("[网络恢复] 收到 ConnectFailed，房间服务器连接失败")
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.pendingSyncReason = "connect_failed"
    ClearServerBind()
    MarkAuthoritySyncPending("connect_failed")
    ShowDisconnectModal("房间服务器连接失败，正在等待平台恢复。")
    StartPlatformWait("房间服务器连接失败，正在等待平台恢复。")
end

function NetworkRecovery.HandleTransportConnected(eventData)
    print("[网络恢复] 收到 TransportConnected " .. BuildTransportDebugText(eventData))
end

function NetworkRecovery.HandleTransportDisconnected(eventData)
    print("[网络恢复] 收到 TransportDisconnected " .. BuildTransportDebugText(eventData))
end

function NetworkRecovery.HandleTransportConnectFailed(eventData)
    print("[网络恢复] 收到 TransportConnectFailed " .. BuildTransportDebugText(eventData))
end

function NetworkRecovery.RetryNow()
    if not IsRawServerConnectionAvailable() then
        print("[网络恢复] 手动重试时无可用 serverConnection raw={" .. BuildConnectionDebugText(NetworkClient.GetConnection()) .. "}")
        state_.lastConnectionKey = nil
        state_.serverReady = false
        state_.wasConnected = false
        state_.syncPending = true
        state_.pendingSyncReason = "manual_retry_wait_platform"
        state_.rawConnectedWithoutReadyElapsed = 0
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        if state_.platformWaitActive ~= true then
            print("[网络恢复] 手动检查时无 serverConnection，等待平台恢复，不调用 ReturnToLobby")
        end
        if state_.platformWaitTimedOut == true then
            SetPlatformWaitTimedOut()
            ShowToast("房间连接未恢复，请刷新页面重新进入游戏", true)
            return false
        end
        StartPlatformWait("当前没有房间服务器连接，正在等待平台恢复。恢复后会自动重新同步数据。")
        if state_.platformWaitToastShown ~= true then
            state_.platformWaitToastShown = true
            ShowToast("正在等待平台恢复房间连接")
        end
        return false
    end

    ClearPlatformWait()
    if IsAuthoritySynced() == true and NetworkClient.IsSessionBound ~= nil and NetworkClient.IsSessionBound() == true then
        state_.serverReady = true
        state_.wasConnected = true
        state_.syncPending = false
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        CloseDisconnectModal()
        ShowToast("网络已恢复")
        return true
    end
    if state_.serverReady == true and IsAuthoritySynced() ~= true then
        ClearServerBind()
        state_.serverReady = false
    end
    state_.zombieUnhealthy = false
    SetDisconnectModalStatus("正在重新发送客户端就绪并请求服务器数据...", true)
    state_.zombieRecoverCooldown = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    state_.syncCooldown = 0
    state_.syncPending = true
    MarkAuthoritySyncPending("manual_retry")
    ClearServerBind()
    state_.serverReady = false
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    if ForceReadyFromRawConnection("manual_retry") then
        ShowToast("正在重新连接并同步数据")
        SetDisconnectModalStatus("已重新发送连接请求，正在等待服务器权威状态...", false)
        return true
    end
    SetDisconnectModalStatus("已找到服务器连接，但客户端就绪请求发送失败，请再次点击重新连接。", false)
    ShowToast("重新连接请求未发出，请再次尝试")
    return false
end

--- 匹配失败后引擎仍可能留下半死 serverConnection。
--- 后台匹配模式下不能在游戏脚本内新建连接；这里只清绑定、停止权威重试，并提示用户重连。
RecoverZombieConnection = function(reason)
    if state_.zombieRecoverCooldown > 0 then return false end
    state_.zombieRecoverCooldown = 30.0
    state_.zombieRecoverCount = (state_.zombieRecoverCount or 0) + 1
    state_.authorityWaitElapsed = 0
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = false
    state_.pendingSyncReason = nil
    state_.lastConnectionKey = nil
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.initialClientReadyGrace = 0
    state_.zombieUnhealthy = true
    ClearServerBind()
    MarkAuthoritySyncPending("zombie_connection")
    ClearBusinessPending("zombie_connection")
    print(string.format(
        "[网络恢复] 检测到僵尸连接（平台 history_errors），已停止权威重试 count=%s reason=%s",
        tostring(state_.zombieRecoverCount),
        tostring(reason or "no_authority")
    ))
    ShowDisconnectModal(
        "未能收到服务器权威状态。请点击重新连接；如果连续失败，再刷新页面。"
    )
    ShowToast("服务器同步异常，请点击重新连接")
    return true
end

function NetworkRecovery.Update(dt)
    if not NetworkClient.IsClientMode() then return end
    EnsureDisconnectModalMounted()
    dt = dt or 0
    if state_.syncCooldown > 0 then
        state_.syncCooldown = math.max(0, state_.syncCooldown - dt)
    end
    if state_.zombieRecoverCooldown > 0 then
        state_.zombieRecoverCooldown = math.max(0, state_.zombieRecoverCooldown - dt)
    end
    state_.timer = state_.timer - dt
    if state_.initialClientReadyGrace > 0 then
        state_.initialClientReadyGrace = math.max(0, state_.initialClientReadyGrace - dt)
    end
    if state_.timer > 0 then return end
    local tick = state_.checkInterval
    state_.timer = tick

    local rawConnection = GetServerConnection()
    local rawAvailable = rawConnection ~= nil
    local connectionKey = GetConnectionKey(rawConnection)

    if rawAvailable then
        if state_.platformWaitActive == true or state_.platformWaitTimedOut == true then
            print("[网络恢复] 已重新获得 serverConnection，准备自动恢复房间会话")
            ClearPlatformWait()
            state_.zombieUnhealthy = false
            SetDisconnectModalStatus("已检测到房间服务器连接，正在重新绑定...", false)
        end
        EnsureConnectionScene()
        -- 已判定为平台僵尸：不再重绑、不再刷权威请求
        if state_.zombieUnhealthy == true then
            return
        end
        if state_.zombieRecoverCooldown > 0 then
            -- 刚处理僵尸连接，避免立刻重新绑定半死连接
            return
        end
        if state_.lastConnectionKey ~= connectionKey then
            state_.lastConnectionKey = connectionKey
            state_.rawConnectedWithoutReadyElapsed = 0
            state_.authorityWaitElapsed = 0
            state_.authorityRetryElapsed = 0
            state_.authorityRetryCount = 0
            state_.syncPending = true
            state_.wasConnected = false
            print("[网络恢复] 检测到服务器连接，准备重新绑定")
            local socialGardenSystem = GetSocialGardenSystem()
            local alreadyBound = socialGardenSystem ~= nil
                and socialGardenSystem.IsServerBound ~= nil
                and socialGardenSystem.IsServerBound() == true
            if alreadyBound then
                -- 旧连接断开后可能残留 serverEnabled/boundConnectionKey；恢复时必须强制重发 CLIENT_READY。
                ClearServerBind()
            end
            state_.serverReady = false
            if socialGardenSystem ~= nil then
                BindServerConnection(true)
                if socialGardenSystem.IsServerBound ~= nil and socialGardenSystem.IsServerBound() == true then
                    state_.serverReady = true
                    state_.wasConnected = true
                    state_.syncPending = true
                    SetDisconnectModalStatus("已连接服务器，正在等待权威数据...", false)
                    if state_.initialClientReadyGrace <= 0 then
                        state_.initialClientReadyGrace = 1.5
                    end
                    return
                end
            end
        elseif state_.serverReady ~= true then
            state_.rawConnectedWithoutReadyElapsed = state_.rawConnectedWithoutReadyElapsed + tick
        end

        if state_.serverReady ~= true and state_.initialClientReadyGrace <= 0 and state_.rawConnectedWithoutReadyElapsed >= state_.rawReadyFallbackDelay then
            ForceReadyFromRawConnection("raw_connection_fallback")
        end
        if state_.serverReady ~= true then
            return
        end

        -- 已绑定但无权威响应：判定为匹配层僵尸连接，停止刷权威请求并提示用户重连。
        -- 注意：initialClientReadyGrace 只抑制重复 RequestSync，不推迟僵尸计时。
        if IsAuthoritySynced() then
            state_.authorityWaitElapsed = 0
            state_.authorityRetryElapsed = 0
            state_.authorityRetryCount = 0
            state_.syncPending = false
            state_.pendingSyncReason = nil
            CloseDisconnectModal()
        else
            state_.authorityWaitElapsed = state_.authorityWaitElapsed + tick
            state_.authorityRetryElapsed = state_.authorityRetryElapsed + tick
            if state_.authorityRetryElapsed >= state_.authorityRetryInterval
                and state_.authorityRetryCount < state_.maxAuthorityAutoRetries then
                RetryAuthorityHandshake("auto_authority_retry")
                return
            end
            if state_.authorityWaitElapsed >= state_.zombieAuthorityTimeout then
                RecoverZombieConnection("no_authority_after_bind")
                return
            end
        end
    else
        state_.serverReady = false
        state_.lastConnectionKey = nil
        state_.rawConnectedWithoutReadyElapsed = 0
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        if disconnectModal_ ~= nil and state_.platformWaitActive ~= true then
            StartPlatformWait("当前没有房间服务器连接，正在等待平台恢复。恢复后会自动重新同步数据。")
        end
        if state_.platformWaitActive == true then
            state_.platformWaitElapsed = state_.platformWaitElapsed + tick
            state_.platformWaitNoticeElapsed = state_.platformWaitNoticeElapsed + tick
            if state_.platformWaitTimedOut ~= true and state_.platformWaitElapsed >= state_.platformWaitTimeout then
                print("[网络恢复] 等待平台恢复房间连接超时 elapsed=" .. tostring(math.floor(state_.platformWaitElapsed + 0.5)))
                SetPlatformWaitTimedOut()
                ShowToast("房间连接未恢复，请刷新页面重新进入游戏")
            elseif state_.platformWaitTimedOut ~= true and state_.platformWaitNoticeElapsed >= state_.platformWaitNoticeInterval then
                state_.platformWaitNoticeElapsed = 0
                SetDisconnectModalStatus("当前没有房间服务器连接，正在等待平台恢复。恢复后会自动重新同步数据。", false)
            end
        end
        state_.disconnectedNoticeElapsed = state_.disconnectedNoticeElapsed + tick
        if state_.disconnectedNoticeElapsed >= state_.disconnectedNoticeInterval then
            state_.disconnectedNoticeElapsed = 0
            print("[网络恢复] 暂未获得服务器连接，等待后台匹配完成")
        end
    end

    local connected = IsReadyServerConnectionAvailable()
    if connected == state_.wasConnected then
        if connected and state_.syncPending and state_.zombieUnhealthy ~= true then
            NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
            NetworkRecovery.RequestSync("pending_recovery")
        end
        return
    end

    state_.wasConnected = connected
    if connected then
        state_.zombieUnhealthy = false
        NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
        SetDisconnectModalStatus("已连接服务器，正在同步权威数据...", false)
        NetworkRecovery.RequestSync("network_recovered")
    else
        state_.syncPending = true
        ClearServerBind()
        MarkAuthoritySyncPending("connection_lost")
        ClearBusinessPending("connection_lost")
        StartPlatformWait("网络连接已断开，正在等待平台恢复房间连接。恢复后会自动重新同步数据。")
        ShowDisconnectModal("网络连接已断开，正在等待平台恢复房间连接。恢复后会自动重新同步数据。")
        if NetworkRecovery.RestoreOwnFarm("网络连接已断开，已先返回我的花园") then
            print("[网络恢复] 断线时处于拜访模式，已恢复本地花园显示")
        else
            ShowToast("网络连接已断开，等待恢复")
        end
    end
end

function NetworkRecovery.HandleServerReady()
    print("[网络恢复] 收到 ServerReady，准备绑定房间连接 raw={" .. BuildConnectionDebugText(NetworkClient.GetConnection()) .. "}")
    ClearPlatformWait()
    ClearServerBind()
    BindServerConnection(true)
    local socialGardenSystem = GetSocialGardenSystem()
    local bound = socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true
    state_.serverReady = bound == true
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.authorityWaitElapsed = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = true
    if state_.serverReady ~= true then
        SetDisconnectModalStatus("已收到服务器连接，但客户端就绪请求发送失败，请再次点击重新连接。", false)
        return
    end
    MarkAuthoritySyncPending("server_ready")
    if state_.initialClientReadyGrace <= 0 then
        state_.initialClientReadyGrace = 0
    end
    SetDisconnectModalStatus("已收到服务器连接，正在等待权威数据...", false)
    NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
end

function NetworkRecovery.HandleServerDisconnected()
    print("[网络恢复] 收到 ServerDisconnected raw={" .. BuildConnectionDebugText(NetworkClient.GetConnection()) .. "}")
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.lastConnectionKey = nil
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.authorityWaitElapsed = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    state_.disconnectedNoticeElapsed = 0
    state_.syncCooldown = 0
    state_.pendingSyncReason = nil
    ClearServerBind()
    MarkAuthoritySyncPending("server_disconnected")
    ClearBusinessPending("server_disconnected")
    StartPlatformWait("网络连接已断开，正在等待平台恢复房间连接。恢复后会自动重新同步数据。")
    ShowDisconnectModal("网络连接已断开，正在等待平台恢复房间连接。恢复后会自动重新同步数据。")
    ShowToast("网络连接已断开，等待恢复")
end

function NetworkRecovery.NotifyServerRequestFailed(reason, message, options)
    options = options or {}
    local failureReason = tostring(reason or "request_failed")
    local text = message or "网络连接失败，服务器请求未响应。请检查网络后点击重新连接"
    if string.find(text, "花园同步中", 1, true) ~= nil
        or string.find(text, "榜单繁忙", 1, true) ~= nil
        or string.find(text, "服务器繁忙", 1, true) ~= nil then
        print("[网络恢复] 忽略业务繁忙，不进入网络恢复 reason=" .. failureReason .. " message=" .. tostring(text))
        return false
    end
    if options.critical ~= true then
        print("[网络恢复] 忽略非关键请求失败 reason=" .. failureReason .. " message=" .. tostring(text))
        ShowToast(text)
        return false
    end
    if IsRawServerConnectionAvailable() == true
        and (failureReason == "request_timeout_load" or failureReason == "request_timeout_authFarm") then
        state_.syncPending = true
        state_.pendingSyncReason = failureReason
        MarkAuthoritySyncPending(failureReason)
        print("[网络恢复] 权威首包响应较慢，保持连接并继续等待 reason=" .. failureReason)
        ShowToast("服务器响应较慢，正在继续同步")
        return false
    end
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.pendingSyncReason = failureReason
    state_.syncCooldown = 0
    ClearServerBind()
    MarkAuthoritySyncPending(failureReason)
    ClearBusinessPending(failureReason)
    print("[网络恢复] 服务器请求失败，显示网络错误 reason=" .. failureReason)
    if failureReason == "identity_not_ready" then
        state_.zombieUnhealthy = true
        state_.syncPending = false
        state_.authorityWaitElapsed = 0
        state_.authorityRetryElapsed = 0
        state_.authorityRetryCount = 0
        ClearPlatformWait()
        ShowDisconnectModal(text)
        SetDisconnectModalStatus(text, false)
        ShowToast("网络会话已失效，请等待平台恢复或刷新重进")
        return true
    end
    if IsRawServerConnectionAvailable() ~= true then
        StartPlatformWait(text .. "\n正在等待平台恢复房间连接。")
    end
    ShowDisconnectModal(text)
    ShowToast("网络连接失败，请点击重新连接")
    return true
end

function NetworkRecovery.IsZombieUnhealthy()
    return state_.zombieUnhealthy == true
end

--- Start() 已发送 CLIENT_READY 且服务端会推送全量同步时调用，避免 NetworkRecovery 再触发一次 network_recovered 重拉。
function NetworkRecovery.NotifyInitialClientReady()
    if not IsRawServerConnectionAvailable() then return end
    state_.serverReady = true
    state_.wasConnected = true
    state_.syncPending = false
    state_.pendingSyncReason = nil
    state_.zombieUnhealthy = false
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.authorityWaitElapsed = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    -- 仅抑制重复 RequestSync；僵尸计时不受此影响
    state_.initialClientReadyGrace = 1.5
end

function NetworkRecovery.ResetConnectionState()
    state_.serverReady = false
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = not state_.wasConnected
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.authorityWaitElapsed = 0
    state_.authorityRetryElapsed = 0
    state_.authorityRetryCount = 0
    state_.disconnectedNoticeElapsed = 0
    state_.syncCooldown = 0
    state_.pendingSyncReason = nil
end

function NetworkRecovery.ResetLoadingState()
    state_.loadingElapsed = 0
    state_.loadingHintShown = false
    state_.loadingNoticeElapsed = 0
end

function NetworkRecovery.GetLoadingMessage()
    if IsRawServerConnectionAvailable() ~= true then
        if state_.loadingElapsed >= state_.loadingNoConnectionTimeout then
            return "未能恢复房间连接，请刷新页面重新进入游戏"
        end
        return "正在等待房间服务器连接..."
    end
    return "服务器响应较慢，正在重试同步..."
end

function NetworkRecovery.UpdateLoading(dt)
    local delta = dt or 0
    state_.loadingElapsed = state_.loadingElapsed + delta
    state_.loadingNoticeElapsed = state_.loadingNoticeElapsed + delta
    if state_.loadingElapsed < 10.0 then return false end
    if state_.loadingHintShown ~= true then
        state_.loadingHintShown = true
        state_.loadingNoticeElapsed = 0
        return true
    end
    if state_.loadingElapsed >= state_.loadingNoConnectionTimeout and state_.loadingNoticeElapsed >= 3.0 then
        state_.loadingNoticeElapsed = 0
        if IsRawServerConnectionAvailable() ~= true then
            print("[启动同步] 等待房间服务器超时 rawConnected=false elapsed=" .. tostring(math.floor(state_.loadingElapsed + 0.5)))
        end
        return true
    end
    return false
end

return NetworkRecovery
