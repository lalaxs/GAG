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
    lastConnectionKey = nil,
    rawDisconnectedElapsed = 0,
    rawConnectedWithoutReadyElapsed = 0,
    disconnectedNoticeElapsed = 0,
    disconnectedNoticeInterval = 10.0,
    rawReadyFallbackDelay = 1.5,
    syncCooldown = 0,
    minSyncInterval = 1.5,
    pendingSyncReason = nil,
    retrying = false,
    retryMessage = nil,
    initialClientReadyGrace = 0,
}

local disconnectModal_ = nil
local retryButton_ = nil
local statusLabel_ = nil
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

local function EnsureConnectionScene()
    if deps_.getScene ~= nil then
        NetworkClient.EnsureConnectionScene(deps_.getScene)
    end
end

local function BindServerConnection(forceReady)
    return NetworkClient.BindServerConnection(forceReady)
end

local function GetServerConnection()
    return NetworkClient.GetConnection()
end

local function GetConnectionKey(connection)
    if connection == nil then return nil end
    return "connected"
end

local function IsRawServerConnectionAvailable()
    return NetworkClient.IsRawConnected()
end

local function IsReadyServerConnectionAvailable()
    return state_.serverReady == true and IsRawServerConnectionAvailable()
end

local function SetDisconnectModalStatus(text, retrying)
    state_.retryMessage = text
    state_.retrying = retrying == true
    if statusLabel_ ~= nil then statusLabel_:SetText(text or "网络连接已断开") end
    if retryButton_ ~= nil then
        retryButton_:SetDisabled(state_.retrying)
        retryButton_:SetText(state_.retrying and "重连中..." or "重试连接")
    end
end

local function CloseDisconnectModal()
    if disconnectModal_ ~= nil then
        disconnectModal_:Close()
        disconnectModal_ = nil
    end
    retryButton_ = nil
    statusLabel_ = nil
    state_.retrying = false
    state_.retryMessage = nil
end

local function ShowDisconnectModal(message)
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
        end,
    }

    statusLabel_ = UI.Label {
        text = message or "网络连接已断开，请检查网络后重试",
        fontSize = 15,
        fontColor = {92, 70, 48, 255},
        textAlign = "center",
    }

    retryButton_ = UI.Button {
        text = "重试连接",
        height = 44,
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
        gap = 16,
        children = {
            UI.Label {
                text = "当前无法连接到游戏服务器，部分操作可能无法保存。",
                fontSize = 14,
                fontColor = {116, 92, 58, 235},
                textAlign = "center",
            },
            statusLabel_,
            retryButton_,
        },
    })
    ModalAnim.Apply(disconnectModal_, { fixedHeight = 245 })
    disconnectModal_:Open()
end

function NetworkRecovery.IsServerConnectionAvailable()
    return IsReadyServerConnectionAvailable()
end

function NetworkRecovery.RequestSync(reason)
    if state_.initialClientReadyGrace > 0 and reason ~= "manual_retry" then
        state_.syncPending = false
        state_.pendingSyncReason = nil
        print("[网络恢复] 初始 CLIENT_READY 同步保护中，跳过重复同步: " .. tostring(reason))
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
    CloseDisconnectModal()
    print("[网络恢复] 已请求服务器权威数据重同步: " .. tostring(syncReason))
    return true
end

function NetworkRecovery.RetryNow()
    SetDisconnectModalStatus("正在尝试重新连接服务器...", true)
    if IsRawServerConnectionAvailable() then
        state_.serverReady = true
        state_.rawConnectedWithoutReadyElapsed = 0
        state_.syncCooldown = 0
        state_.syncPending = true
        if NetworkRecovery.RequestSync("manual_retry") then
            ShowToast("网络已恢复，正在同步数据")
            return true
        end
    end
    state_.syncPending = true
    SetDisconnectModalStatus("暂时还没有连接到服务器，请稍后再试", false)
    ShowToast("暂时无法重连，请稍后再试")
    return false
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
    local socialGardenSystem = GetSocialGardenSystem()
    if socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() ~= true then
        BindServerConnection(true)
    end
    state_.serverReady = socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true
    if state_.serverReady ~= true then
        state_.syncPending = true
        return false
    end
    state_.syncPending = true
    NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
    return NetworkRecovery.RequestSync(reason or "raw_connection_ready")
end

function NetworkRecovery.Update(dt)
    if not NetworkClient.IsClientMode() then return end
    dt = dt or 0
    if state_.syncCooldown > 0 then
        state_.syncCooldown = math.max(0, state_.syncCooldown - dt)
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
        EnsureConnectionScene()
        state_.rawDisconnectedElapsed = 0
        if state_.lastConnectionKey ~= connectionKey then
            state_.lastConnectionKey = connectionKey
            state_.serverReady = false
            state_.rawConnectedWithoutReadyElapsed = 0
            state_.syncPending = true
            state_.wasConnected = false
            print("[网络恢复] 检测到服务器连接，准备重新绑定")
            local socialGardenSystem = GetSocialGardenSystem()
            local boundFresh = false
            if socialGardenSystem ~= nil
                and socialGardenSystem.IsServerBound ~= nil
                and socialGardenSystem.IsServerBound() ~= true then
                BindServerConnection(true)
                if socialGardenSystem.IsServerBound() == true then
                    state_.serverReady = true
                    boundFresh = true
                end
            end
            if boundFresh then
                -- CLIENT_READY 已触发服务端 SendFullSync，无需再 RequestFullSync。
                state_.wasConnected = true
                state_.syncPending = false
                return
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
        CloseDisconnectModal()
        NetworkRecovery.RestoreOwnFarm("网络已恢复，已返回我的花园并同步数据")
        NetworkRecovery.RequestSync("network_recovered")
    else
        state_.syncPending = true
        ShowDisconnectModal("网络连接已断开，请检查网络后点击重试")
        if NetworkRecovery.RestoreOwnFarm("网络连接已断开，已先返回我的花园") then
            print("[网络恢复] 断线时处于拜访模式，已恢复本地花园显示")
        else
            ShowToast("网络连接已断开，等待恢复")
        end
    end
end

function NetworkRecovery.HandleServerReady()
    local socialGardenSystem = GetSocialGardenSystem()
    if socialGardenSystem ~= nil
        and socialGardenSystem.IsServerBound ~= nil
        and socialGardenSystem.IsServerBound() == true then
        state_.serverReady = true
        state_.rawConnectedWithoutReadyElapsed = 0
        state_.wasConnected = IsReadyServerConnectionAvailable()
        state_.syncPending = false
        CloseDisconnectModal()
        return
    end
    BindServerConnection(true)
    state_.serverReady = true
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = false
    CloseDisconnectModal()
    NetworkRecovery.RestoreOwnFarm("网络已恢复，正在同步我的花园")
end

function NetworkRecovery.HandleServerDisconnected()
    state_.serverReady = false
    state_.wasConnected = false
    state_.syncPending = true
    state_.lastConnectionKey = nil
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.rawDisconnectedElapsed = 0
    state_.disconnectedNoticeElapsed = 0
    state_.syncCooldown = 0
    state_.pendingSyncReason = nil
    ShowDisconnectModal("网络连接已断开，请检查网络后点击重试")
    ShowToast("网络连接已断开，等待恢复")
end

--- Start() 已发送 CLIENT_READY 且服务端会推送全量同步时调用，避免 NetworkRecovery 再触发一次 network_recovered 重拉。
function NetworkRecovery.NotifyInitialClientReady()
    if not IsRawServerConnectionAvailable() then return end
    state_.serverReady = true
    state_.wasConnected = true
    state_.syncPending = false
    state_.pendingSyncReason = nil
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.initialClientReadyGrace = 3.0
end

function NetworkRecovery.ResetConnectionState()
    state_.serverReady = false
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = not state_.wasConnected
    state_.lastConnectionKey = GetConnectionKey(GetServerConnection())
    state_.rawDisconnectedElapsed = 0
    state_.rawConnectedWithoutReadyElapsed = 0
    state_.disconnectedNoticeElapsed = 0
    state_.syncCooldown = 0
    state_.pendingSyncReason = nil
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
