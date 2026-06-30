-- ============================================================================
-- 网络断线恢复运行时
-- Grow A Garden
-- ============================================================================
-- 客户端在后台匹配模式下可能收不到第二次 ServerReady。
-- 恢复逻辑不能只依赖 ServerReady：只要轮询发现 serverConnection 已恢复，
-- 就主动重新绑定 scene、发送 CLIENT_READY，并强制拉取服务端权威状态。
-- ============================================================================

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
    lastConnectionKey = nil,
    rawDisconnectedElapsed = 0,
    rawConnectedWithoutReadyElapsed = 0,
    disconnectedNoticeElapsed = 0,
    disconnectedNoticeInterval = 10.0,
    rawReadyFallbackDelay = 1.5,
}

function NetworkRecovery.Init(deps)
    deps_ = deps or {}
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then
        deps_.showToast(text, silent)
    end
end

local function GetSocialGardenSystem()
    return deps_.SocialGardenSystem
end

local function GetEconomyCloudSystem()
    return deps_.EconomyCloudSystem
end

local function GetServerConnection()
    if network == nil or IsClientMode == nil or not IsClientMode() then return nil end
    return network:GetServerConnection()
end

local function GetConnectionKey(connection)
    if connection == nil then return nil end
    return "connected"
end

local function IsRawServerConnectionAvailable()
    return GetServerConnection() ~= nil
end

local function IsReadyServerConnectionAvailable()
    return state_.serverReady == true and IsRawServerConnectionAvailable()
end

function NetworkRecovery.IsServerConnectionAvailable()
    return IsReadyServerConnectionAvailable()
end

function NetworkRecovery.RequestSync(reason)
    if not IsReadyServerConnectionAvailable() then
        state_.syncPending = true
        return false
    end
    state_.syncPending = false
    local syncReason = reason or "network_recovered"
    local socialGardenSystem = GetSocialGardenSystem()
    local economyCloudSystem = GetEconomyCloudSystem()
    socialGardenSystem.BindServerConnection(true)
    economyCloudSystem.RequestState({ force = true, reason = syncReason })
    economyCloudSystem.RequestSeedShop()
    economyCloudSystem.RequestAuthFarm({ force = true, reason = syncReason })
    socialGardenSystem.RequestSocialState({ force = true, reason = syncReason })
    if economyCloudSystem.IsReady(false) then
        economyCloudSystem.RequestCommissions()
    end
    socialGardenSystem.UploadSnapshot()
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

local function ForceReadyFromRawConnection(reason)
    if not IsRawServerConnectionAvailable() then return false end
    state_.serverReady = true
    state_.syncPending = true
    NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
    return NetworkRecovery.RequestSync(reason or "raw_connection_ready")
end

function NetworkRecovery.Update(dt)
    if network == nil or IsClientMode == nil or not IsClientMode() then return end
    dt = dt or 0
    state_.timer = state_.timer - dt
    if state_.timer > 0 then return end
    local tick = state_.checkInterval
    state_.timer = tick

    local rawConnection = GetServerConnection()
    local rawAvailable = rawConnection ~= nil
    local connectionKey = GetConnectionKey(rawConnection)

    if rawAvailable then
        state_.rawDisconnectedElapsed = 0
        if state_.lastConnectionKey ~= connectionKey then
            state_.lastConnectionKey = connectionKey
            state_.serverReady = false
            state_.rawConnectedWithoutReadyElapsed = 0
            state_.syncPending = true
            state_.wasConnected = false
            print("[网络恢复] 检测到服务器连接，准备重新绑定")
        elseif state_.serverReady ~= true then
            state_.rawConnectedWithoutReadyElapsed = state_.rawConnectedWithoutReadyElapsed + tick
        end

        if state_.serverReady ~= true and state_.rawConnectedWithoutReadyElapsed >= state_.rawReadyFallbackDelay then
            ForceReadyFromRawConnection("raw_connection_fallback")
        end
        if state_.serverReady ~= true then
            return
        end
    else
        state_.serverReady = false
        state_.lastConnectionKey = nil
        state_.rawConnectedWithoutReadyElapsed = 0
        state_.rawDisconnectedElapsed = state_.rawDisconnectedElapsed + tick
        state_.disconnectedNoticeElapsed = state_.disconnectedNoticeElapsed + tick
        if state_.disconnectedNoticeElapsed >= state_.disconnectedNoticeInterval then
            state_.disconnectedNoticeElapsed = 0
            print("[网络恢复] 暂未获得服务器连接，等待后台匹配完成")
        end
    end

    local connected = IsReadyServerConnectionAvailable()
    if connected == state_.wasConnected then
        if connected and state_.syncPending then
            NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
            NetworkRecovery.RequestSync("pending_recovery")
        end
        return
    end

    state_.wasConnected = connected
    if connected then
        NetworkRecovery.RestoreOwnFarm("网络已恢复，已返回我的花园并同步数据")
        NetworkRecovery.RequestSync("network_recovered")
    else
        state_.syncPending = true
        if NetworkRecovery.RestoreOwnFarm("网络连接已断开，已先返回我的花园") then
            print("[网络恢复] 断线时处于拜访模式，已恢复本地花园显示")
        else
            ShowToast("网络连接已断开，等待恢复")
        end
    end
end

function NetworkRecovery.HandleServerReady()
    state_.serverReady = true
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.wasConnected = IsReadyServerConnectionAvailable()
    local socialGardenSystem = GetSocialGardenSystem()
    if NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园") then
        socialGardenSystem.UploadSnapshot()
    end
    if state_.wasConnected then
        NetworkRecovery.RequestSync("server_ready")
    else
        state_.syncPending = true
    end
end

function NetworkRecovery.HandleServerDisconnected()
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.lastConnectionKey = nil
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.rawDisconnectedElapsed = 0
    state_.disconnectedNoticeElapsed = 0
    ShowToast("网络连接已断开，等待恢复")
end

function NetworkRecovery.ResetConnectionState()
    state_.serverReady = false
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = not state_.wasConnected
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    state_.rawDisconnectedElapsed = 0
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.disconnectedNoticeElapsed = 0
end

function NetworkRecovery.ResetLoadingState()
    state_.loadingElapsed = 0
    state_.loadingHintShown = false
end

function NetworkRecovery.UpdateLoading(dt)
    state_.loadingElapsed = state_.loadingElapsed + (dt or 0)
    if state_.loadingElapsed >= 10.0 and state_.loadingHintShown ~= true then
        state_.loadingHintShown = true
        return true
    end
    return false
end

return NetworkRecovery
