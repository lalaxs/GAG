-- ============================================================================
-- 网络断线恢复运行时
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有断线恢复逻辑，不改变同步顺序、提示文案和状态判断。
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

local function IsRawServerConnectionAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function IsReadyServerConnectionAvailable()
    return state_.serverReady == true and IsRawServerConnectionAvailable()
end

function NetworkRecovery.IsServerConnectionAvailable()
    return IsRawServerConnectionAvailable()
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
    local _, readySent = socialGardenSystem.BindServerConnection(true)
    if readySent ~= true then
        economyCloudSystem.RequestState({ force = true, reason = syncReason })
        economyCloudSystem.RequestSeedShop()
        economyCloudSystem.RequestAuthFarm({ force = true, reason = syncReason })
        socialGardenSystem.RequestSocialState()
        if economyCloudSystem.IsReady(false) then
            economyCloudSystem.RequestCommissions()
        end
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

function NetworkRecovery.Update(dt)
    if network == nil or IsClientMode == nil or not IsClientMode() then return end
    state_.timer = state_.timer - (dt or 0)
    if state_.timer > 0 then return end
    state_.timer = state_.checkInterval

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

function NetworkRecovery.ResetConnectionState()
    state_.serverReady = false
    state_.wasConnected = IsReadyServerConnectionAvailable()
    state_.syncPending = not state_.wasConnected
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
