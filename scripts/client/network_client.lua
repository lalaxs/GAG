-- ============================================================================
-- 客户端网络层
-- Grow A Garden
-- ============================================================================
-- 统一连接检测、远程请求发送、CLIENT_READY 绑定与权威重同步。
-- NetworkRecovery 负责断线 UI/轮询；本模块负责底层网络与会话语义。
-- ============================================================================

local Shared = require("network.shared")

local NetworkClient = {}

local deps_ = {}

function NetworkClient.Init(deps)
    deps_ = deps or {}
end

function NetworkClient.IsClientMode()
    return network ~= nil and IsClientMode ~= nil and IsClientMode()
end

function NetworkClient.GetConnection()
    if not NetworkClient.IsClientMode() then return nil end
    return network:GetServerConnection()
end

--- 底层 serverConnection 是否可用（匹配完成，尚未 necessarily CLIENT_READY）。
function NetworkClient.IsRawConnected()
    return NetworkClient.GetConnection() ~= nil
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
    if not NetworkClient.IsRawConnected() then return false end
    if not NetworkClient.IsSessionBound() then
        NetworkClient.BindServerConnection(true)
        if not NetworkClient.IsSessionBound() then return false end
    end
    return Shared.SendToServer(eventName, payload)
end

function NetworkClient.EnsureConnectionScene(getScene)
    local conn = NetworkClient.GetConnection()
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
    if socialGardenSystem.RequestFullSync ~= nil then
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
