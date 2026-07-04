-- ============================================================================
-- 服务端请求幂等守卫
-- ============================================================================
-- 统一处理 requestId 去重、重复请求回放、请求结果记录。
-- 依赖运行时全局 serverCloud / os。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")

local RequestGuard = {}

local function Now()
    return os and os.time and os.time() or 0
end

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

function RequestGuard.BuildRecordKey(action, requestId)
    local day = os and os.date and os.date("%Y%m%d", Now()) or "unknown"
    return "request_once_" .. day .. "_" .. tostring(action or "op") .. "_" .. tostring(requestId or "")
end

function RequestGuard.Check(uid, action, requestId, onFresh, onDuplicate, onError)
    uid = CloudUid(uid)
    if requestId == nil or requestId == "" then
        onFresh(nil)
        return
    end
    local key = RequestGuard.BuildRecordKey(action, requestId)
    ServerCloudStore.ListGet(uid, key, {
        ok = function(rows)
            if rows ~= nil and #rows > 0 then
                if onDuplicate then onDuplicate(rows[1].value or rows[1]) end
                return
            end
            onFresh(key)
        end,
        error = function(_, reason)
            local text = tostring(reason or "")
            if text == "NOT_FOUND" or string.find(text, "NOT_FOUND", 1, true) ~= nil then
                onFresh(key)
                return
            end
            if onError then onError(reason) end
        end,
    })
end

function RequestGuard.Record(uid, key, response)
    uid = CloudUid(uid)
    if key == nil or key == "" then return end
    serverCloud.list:Add(uid, key, { response = response, time = Now() })
end

function RequestGuard.AddToCommit(commit, uid, key, response)
    uid = CloudUid(uid)
    if commit == nil or key == nil or key == "" then return end
    commit:ListAdd(uid, key, { response = response, time = Now() })
end

return RequestGuard
