-- ============================================================================
-- 服务端请求幂等守卫
-- ============================================================================
-- 统一处理 requestId 去重、重复请求回放、请求结果记录。
-- 依赖运行时全局 serverCloud / os。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")

local RequestGuard = {}
local memoryRecords_ = {}
local inFlightRecords_ = {}
local MEMORY_RECORD_TTL = 120
local IN_FLIGHT_TTL = 120

local function Now()
    return os and os.time and os.time() or 0
end

local function CleanupMemoryRecords()
    local now = Now()
    for key, record in pairs(memoryRecords_) do
        if record == nil or now - (record.time or 0) > MEMORY_RECORD_TTL then
            memoryRecords_[key] = nil
        end
    end
    for key, record in pairs(inFlightRecords_) do
        if record == nil or now - (record.time or 0) > IN_FLIGHT_TTL then
            inFlightRecords_[key] = nil
        end
    end
end

local function IsFastLocalAction(action)
    return action == "plant" or action == "harvest" or action == "sell" or action == "open_pack"
end

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

function RequestGuard.BuildRecordKey(action, requestId)
    action = tostring(action or "op")
    if action == "ad_reward" then
        return "request_once_ad_reward_" .. tostring(requestId or "")
    end
    local day = os and os.date and os.date("%Y%m%d", Now()) or "unknown"
    return "request_once_" .. day .. "_" .. action .. "_" .. tostring(requestId or "")
end

function RequestGuard.Check(uid, action, requestId, onFresh, onDuplicate, onError)
    uid = CloudUid(uid)
    if requestId == nil or requestId == "" then
        onFresh(nil)
        return
    end
    local key = RequestGuard.BuildRecordKey(action, requestId)
    local memoryKey = tostring(uid) .. ":" .. key
    CleanupMemoryRecords()
    if action == "ad_reward" and inFlightRecords_[memoryKey] ~= nil then
        if onDuplicate then
            onDuplicate({
                success = false,
                retryable = true,
                code = "REQUEST_IN_FLIGHT",
                message = "广告奖励正在确认中",
                requestId = requestId,
            })
        end
        return
    end
    if IsFastLocalAction(action) then
        local cached = memoryRecords_[memoryKey]
        if cached ~= nil then
            if onDuplicate then onDuplicate(cached.response) end
            return
        end
        onFresh(key)
        return
    end
    ServerCloudStore.ListGet(uid, key, {
        ok = function(rows)
            if rows ~= nil and #rows > 0 then
                if onDuplicate then onDuplicate(rows[1].value or rows[1]) end
                return
            end
            if action == "ad_reward" and inFlightRecords_[memoryKey] ~= nil then
                if onDuplicate then
                    onDuplicate({
                        success = false,
                        retryable = true,
                        code = "REQUEST_IN_FLIGHT",
                        message = "广告奖励正在确认中",
                        requestId = requestId,
                    })
                end
                return
            end
            if action == "ad_reward" then
                inFlightRecords_[memoryKey] = { time = Now() }
            end
            onFresh(key)
        end,
        error = function(_, reason)
            local text = tostring(reason or "")
            if text == "NOT_FOUND" or string.find(text, "NOT_FOUND", 1, true) ~= nil then
                if action == "ad_reward" and inFlightRecords_[memoryKey] ~= nil then
                    if onDuplicate then
                        onDuplicate({
                            success = false,
                            retryable = true,
                            code = "REQUEST_IN_FLIGHT",
                            message = "广告奖励正在确认中",
                            requestId = requestId,
                        })
                    end
                    return
                end
                if action == "ad_reward" then
                    inFlightRecords_[memoryKey] = { time = Now() }
                end
                onFresh(key)
                return
            end
            if onError then onError(reason) end
        end,
    })
end

local function IsFastRecordKey(key)
    local text = tostring(key or "")
    return string.find(text, "_plant_", 1, true) ~= nil
        or string.find(text, "_harvest_", 1, true) ~= nil
        or string.find(text, "_sell_", 1, true) ~= nil
        or string.find(text, "_open_pack_", 1, true) ~= nil
end

function RequestGuard.Record(uid, key, response)
    uid = CloudUid(uid)
    if key == nil or key == "" then return end
    local memoryKey = tostring(uid) .. ":" .. tostring(key)
    inFlightRecords_[memoryKey] = nil
    memoryRecords_[memoryKey] = { response = response, time = Now() }
    if IsFastRecordKey(key) then return end
    serverCloud.list:Add(uid, key, { response = response, time = Now() })
end

function RequestGuard.CompleteCommitted(uid, key, response)
    uid = CloudUid(uid)
    if key == nil or key == "" then return end
    local memoryKey = tostring(uid) .. ":" .. tostring(key)
    inFlightRecords_[memoryKey] = nil
    memoryRecords_[memoryKey] = { response = response, time = Now() }
end

function RequestGuard.Release(uid, key)
    uid = CloudUid(uid)
    if key == nil or key == "" then return end
    inFlightRecords_[tostring(uid) .. ":" .. tostring(key)] = nil
end

function RequestGuard.AddToCommit(commit, uid, key, response)
    uid = CloudUid(uid)
    if commit == nil or key == nil or key == "" then return end
    commit:ListAdd(uid, key, { response = response, time = Now() })
end

return RequestGuard
