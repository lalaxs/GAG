-- ============================================================================
-- 客户端统一请求状态机
-- ============================================================================
-- 跟踪客户端向服务器发出的请求，统一管理 pending、requestId、超时和响应收尾。
-- 本模块不直接发送网络请求，只维护请求状态。
-- ============================================================================

local RequestStateMachine = {}
RequestStateMachine.__index = RequestStateMachine

local DEFAULT_TIMEOUT = 12.0

local function Now()
    return os and os.clock and os.clock() or 0
end

local function WallTime()
    return os and os.time and os.time() or 0
end

function RequestStateMachine.Create(name, options)
    local self = setmetatable({}, RequestStateMachine)
    self.name = name or "requests"
    self.timeout = options and options.timeout or DEFAULT_TIMEOUT
    self.seq = 0
    self.byId = {}
    self.byType = {}
    self.lastError = nil
    return self
end

function RequestStateMachine:NextId(prefix)
    self.seq = self.seq + 1
    return tostring(prefix or "req") .. "_" .. tostring(WallTime()) .. "_" .. tostring(self.seq)
end

function RequestStateMachine:Begin(requestType, payload, options)
    requestType = tostring(requestType or "request")
    payload = payload or {}
    local requestId = payload.requestId or self:NextId(requestType)
    payload.requestId = requestId
    local record = {
        id = requestId,
        type = requestType,
        payload = payload,
        startedAt = Now(),
        timeout = options and options.timeout or self.timeout,
    }
    self.byId[requestId] = record
    self.byType[requestType] = record
    return payload, record
end

function RequestStateMachine:Finish(requestId, fallbackType)
    local record = requestId ~= nil and self.byId[requestId] or nil
    if record == nil and fallbackType ~= nil then
        record = self.byType[fallbackType]
    end
    if record == nil then return nil end
    self.byId[record.id] = nil
    if self.byType[record.type] == record then
        self.byType[record.type] = nil
    end
    return record
end

function RequestStateMachine:Fail(requestId, fallbackType, reason)
    self.lastError = reason
    return self:Finish(requestId, fallbackType)
end

function RequestStateMachine:IsPending(requestType)
    return self.byType[tostring(requestType or "")] ~= nil
end

function RequestStateMachine:GetPending(requestType)
    return self.byType[tostring(requestType or "")]
end

function RequestStateMachine:Cancel(requestType)
    local record = self.byType[tostring(requestType or "")]
    if record == nil then return nil end
    self.byId[record.id] = nil
    self.byType[record.type] = nil
    return record
end

function RequestStateMachine:SyncLegacyPending(target)
    if type(target) ~= "table" then return end
    for key in pairs(target) do target[key] = nil end
    for requestType, record in pairs(self.byType) do
        target[requestType] = record.payload or true
    end
end

function RequestStateMachine:Update(onTimeout)
    local now = Now()
    local expired = {}
    for requestId, record in pairs(self.byId) do
        if now - record.startedAt >= record.timeout then
            expired[#expired + 1] = record
        end
    end
    for _, record in ipairs(expired) do
        self:Finish(record.id)
        self.lastError = "timeout"
        if onTimeout then onTimeout(record) end
    end
    return #expired
end

function RequestStateMachine:Clear()
    self.byId = {}
    self.byType = {}
    self.lastError = nil
end

return RequestStateMachine
