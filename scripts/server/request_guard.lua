-- ============================================================================
-- 服务端请求幂等守卫
-- ============================================================================
-- 统一处理 requestId 去重、重复请求回放、请求结果记录。
-- 依赖运行时全局 serverCloud / os。
-- ============================================================================

local RequestGuard = {}

local function Now()
    return os and os.time and os.time() or 0
end

function RequestGuard.BuildRecordKey(action, requestId)
    local day = os and os.date and os.date("%Y%m%d", Now()) or "unknown"
    return "request_once_" .. day .. "_" .. tostring(action or "op") .. "_" .. tostring(requestId or "")
end

function RequestGuard.Check(uid, action, requestId, onFresh, onDuplicate, onError)
    if requestId == nil or requestId == "" then
        onFresh(nil)
        return
    end
    local key = RequestGuard.BuildRecordKey(action, requestId)
    serverCloud.list:Get(uid, key, {
        ok = function(rows)
            if rows ~= nil and #rows > 0 then
                if onDuplicate then onDuplicate(rows[1].value or rows[1]) end
                return
            end
            onFresh(key)
        end,
        error = function(_, reason)
            if onError then onError(reason) end
        end,
    })
end

function RequestGuard.Record(uid, key, response)
    if key == nil or key == "" then return end
    serverCloud.list:Add(uid, key, { response = response, time = Now() })
end

function RequestGuard.AddToCommit(commit, uid, key, response)
    if commit == nil or key == nil or key == "" then return end
    commit:ListAdd(uid, key, { response = response, time = Now() })
end

return RequestGuard
