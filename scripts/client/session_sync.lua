-- ============================================================================
-- 客户端会话同步（兼容层）
-- ============================================================================
-- Phase 6 后逻辑已迁入 network_client.lua；保留此模块避免旧 require 路径断裂。
-- ============================================================================

local NetworkClient = require("client.network_client")

return {
    Init = NetworkClient.Init,
    IsServerBound = NetworkClient.IsSessionBound,
    BindServerConnection = NetworkClient.BindServerConnection,
    RequestAuthoritySync = NetworkClient.RequestAuthoritySync,
}
