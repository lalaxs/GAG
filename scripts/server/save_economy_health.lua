-- ============================================================================
-- 经济存档健康检查与 normalize 写回
-- ============================================================================
-- P0：首次成功读取 / 登录归一后，将 normalize 后的经济档写回 canonical UID；
-- 对已迁移标记但内容像新号空档的情况打告警日志。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")
local ServerEconomyState = require("server.server_economy_state")

local SaveEconomyHealth = {}

local deps_ = {}
local writeBackDone_ = {}

function SaveEconomyHealth.Init(deps)
    deps_ = deps or {}
end

function SaveEconomyHealth.ClearSession(uid)
    writeBackDone_[ServerCloudStore.CanonicalUid(uid) or uid] = nil
end

function SaveEconomyHealth.MarkWriteBackDone(uid)
    uid = ServerCloudStore.CanonicalUid(uid)
    if uid ~= nil then writeBackDone_[uid] = true end
end

local function ScoreEconomyState(state)
    return ServerEconomyState.ScoreEconomyContent(state)
end

local function BuildInitialEconomyState()
    if deps_.BuildInitialEconomyState ~= nil then
        return deps_.BuildInitialEconomyState()
    end
    return {}
end

--- 经济档是否「像新号初始档」（normalize 后仍几乎无进度）。
function SaveEconomyHealth.LooksLikeFreshAccount(state)
    local initial = BuildInitialEconomyState()
    local stateScore = ScoreEconomyState(state)
    local initialScore = ScoreEconomyState(initial)
    return stateScore <= initialScore + 50
end

--- 已做过 UID 归一/迁移，但经济档看起来像空档 → 仅打日志，不改玩家数据。
function SaveEconomyHealth.AuditSuspiciousEmpty(uid, state, context)
    uid = ServerCloudStore.CanonicalUid(uid)
    if uid == nil or type(state) ~= "table" then return end
    if SaveEconomyHealth.LooksLikeFreshAccount(state) ~= true then return end

    local markerKey = deps_.Shared and deps_.Shared.KEYS.SAVE_UID_RECONCILED
    if markerKey == nil then return end

    context = context or {}
    ServerCloudStore.Get(uid, markerKey, {
        ok = function(scores)
            local marker = scores and scores[markerKey]
            if type(marker) ~= "table" then return end
            if marker.cleared == true then return end
            local migrated = math.max(0, math.floor(tonumber(marker.migrated or 0) or 0))
            local version = math.floor(tonumber(marker.version or 0) or 0)
            local hadReadError = marker.hadReadError == true
            if version < 2 then return end
            if migrated <= 0 and hadReadError ~= true then return end

            local initial = BuildInitialEconomyState()
            print(string.format(
                "[存档告警] 可疑空经济档 uid=%s economyScore=%d initialScore=%d migrated=%d hadReadError=%s source=%s bestKey=%s",
                tostring(uid),
                ScoreEconomyState(state),
                ScoreEconomyState(initial),
                migrated,
                tostring(hadReadError),
                tostring(context.source or "unknown"),
                tostring(context.bestKey)
            ))
        end,
        error = function() end,
    })
end

--- 每个会话一次：将 normalize 后的经济档写回 canonical UID（结构修复落盘）。
function SaveEconomyHealth.EnsureWriteBack(canonicalUid, state, bestKey, onDone)
    canonicalUid = ServerCloudStore.CanonicalUid(canonicalUid)
    if canonicalUid == nil or type(state) ~= "table" then
        if onDone ~= nil then onDone(state) end
        return
    end
    if writeBackDone_[canonicalUid] == true then
        if onDone ~= nil then onDone(state) end
        return
    end

    local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
    if economyKey == nil then
        if onDone ~= nil then onDone(state) end
        return
    end

    ServerCloudStore.SetScore(canonicalUid, economyKey, state, {
        ok = function()
            writeBackDone_[canonicalUid] = true
            print(string.format(
                "[存档兼容] 经济档 normalize 后已写回 canonical uid=%s sourceKey=%s",
                tostring(canonicalUid),
                tostring(bestKey)
            ))
            if onDone ~= nil then onDone(state) end
        end,
        error = function(_, reason)
            print(string.format(
                "[存档兼容] 经济档 normalize 写回失败 uid=%s reason=%s（仍继续登录）",
                tostring(canonicalUid),
                tostring(reason)
            ))
            if onDone ~= nil then onDone(state) end
        end,
    })
end

return SaveEconomyHealth
