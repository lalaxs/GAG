-- ============================================================================

-- 服务端通用工具函数

-- Grow A Garden

-- ============================================================================

-- 从 server_main.lua 拆出的低风险工具函数。

-- 只承接原有实现，不改变参数、返回值和边界处理。

-- ============================================================================



local UserId = require("utils.user_id")



local ServerUtils = {}



local gameConfig_ = nil

--- ClientIdentity 认证后的 UID 缓存。存档读写只允许使用此缓存，禁止重复读 identity 兜底。

local certifiedConnUid_ = {}
local connectionStates_ = {}
local activeConnectionByKey_ = {}
local activeConnectionByUid_ = {}
local nextConnectionGeneration_ = 0



function ServerUtils.Init(deps)

    deps = deps or {}

    gameConfig_ = deps.GameConfig

end



function ServerUtils.Now()

    return os and os.time and os.time() or 0

end



function ServerUtils.GetConnectionKey(connection)

    if connection == nil then return "" end

    return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())

end

function ServerUtils.GetConnectionGameSessionId(connection)

    return UserId.ReadConnectionGameSessionId(connection)

end



function ServerUtils.RegisterConnection(connection)
    if connection == nil then return nil end
    local key = ServerUtils.GetConnectionKey(connection)
    nextConnectionGeneration_ = nextConnectionGeneration_ + 1
    local previous = activeConnectionByKey_[key]
    if previous ~= nil and previous ~= connection then
        local previousState = connectionStates_[previous]
        if previousState ~= nil then
            previousState.active = false
            previousState.invalidatedReason = "connection_replaced"
        end
        certifiedConnUid_[key] = nil
        print(string.format(
            "[服务端连接] 替换旧连接 key=%s oldGeneration=%s newGeneration=%s",
            tostring(key),
            tostring(previousState and previousState.generation),
            tostring(nextConnectionGeneration_)
        ))
    end
    local state = {
        connection = connection,
        key = key,
        generation = nextConnectionGeneration_,
        active = true,
        identityReady = false,
        userId = nil,
        gameSessionId = ServerUtils.GetConnectionGameSessionId(connection),
    }
    connectionStates_[connection] = state
    activeConnectionByKey_[key] = connection
    print(string.format(
        "[服务端连接] 注册连接 key=%s generation=%s game_session_id=%s",
        tostring(key),
        tostring(state.generation),
        tostring(state.gameSessionId or "unknown")
    ))
    return state
end

function ServerUtils.GetConnectionState(connection)
    return connectionStates_[connection]
end

function ServerUtils.GetConnectionGeneration(connection)
    local state = connectionStates_[connection]
    return state and state.generation or nil
end

function ServerUtils.IsCurrentConnection(connection, generation)
    local state = connectionStates_[connection]
    if state == nil or state.active ~= true then return false end
    if activeConnectionByKey_[state.key] ~= connection then return false end
    return generation == nil or state.generation == generation
end

function ServerUtils.InvalidateConnection(connection)
    if connection == nil then return end
    local state = connectionStates_[connection]
    if state == nil then
        certifiedConnUid_[ServerUtils.GetConnectionKey(connection)] = nil
        return
    end
    state.active = false
    state.invalidatedReason = "client_disconnected"
    if state.userId ~= nil and activeConnectionByUid_[state.userId] == connection then
        activeConnectionByUid_[state.userId] = nil
    end
    if activeConnectionByKey_[state.key] == connection then
        activeConnectionByKey_[state.key] = nil
        certifiedConnUid_[state.key] = nil
    end
    print(string.format(
        "[服务端连接] 失效连接 key=%s generation=%s userId=%s",
        tostring(state.key),
        tostring(state.generation),
        tostring(state.userId)
    ))
end

--- ClientIdentity 事件中调用：认证 UID 只读取一次并锁定。
function ServerUtils.RegisterConnectionUserId(connection, uid)

    uid = UserId.Normalize(uid)

    if connection == nil or uid == nil then return nil end

    local key = ServerUtils.GetConnectionKey(connection)

    local state = connectionStates_[connection]
    if state == nil or state.active ~= true or activeConnectionByKey_[key] ~= connection then
        return nil
    end
    local previousForUid = activeConnectionByUid_[uid]
    if previousForUid ~= nil and previousForUid ~= connection then
        local previousState = connectionStates_[previousForUid]
        if previousState ~= nil then
            previousState.active = false
            previousState.invalidatedReason = "uid_replaced"
        end
        print(string.format(
            "[服务端认证] 同 UID 新连接替换旧连接 uid=%s oldGeneration=%s newGeneration=%s",
            tostring(uid),
            tostring(previousState and previousState.generation),
            tostring(state.generation)
        ))
    end
    certifiedConnUid_[key] = uid
    state.userId = uid
    state.identityReady = true
    activeConnectionByUid_[uid] = connection

    return uid

end



function ServerUtils.ClearConnectionUserId(connection)
    if connection == nil then return end
    local state = connectionStates_[connection]
    local key = ServerUtils.GetConnectionKey(connection)
    if state ~= nil and activeConnectionByKey_[key] ~= connection then
        return
    end
    certifiedConnUid_[key] = nil
    if state ~= nil then
        if state.userId ~= nil and activeConnectionByUid_[state.userId] == connection then
            activeConnectionByUid_[state.userId] = nil
        end
        state.userId = nil
        state.identityReady = false
    end
end



--- 从连接 identity 直接读取 UID（仅供 ClientIdentity 首次认证使用）。

function ServerUtils.ReadConnectionIdentity(connection)

    return UserId.ReadConnectionIdentity(connection)

end



--- 获取已认证的玩家 UID。必须先经过 ClientIdentity，不再从普通业务请求回读 identity。
function ServerUtils.GetConnectionUserId(connection)
    if connection == nil then return nil end
    local state = connectionStates_[connection]
    if state == nil or state.active ~= true or state.identityReady ~= true then
        return nil
    end
    return state.userId or certifiedConnUid_[state.key]
end



function ServerUtils.NormalizeUserId(userId)

    return UserId.Normalize(userId)

end



function ServerUtils.BuildUidKeyCandidates(uid)

    return UserId.BuildKeyCandidates(uid)

end



function ServerUtils.GetCanonicalUidKey(uid)

    return UserId.GetCanonicalKey(uid)

end



function ServerUtils.GetRequestUserId(connection, _data)

    return ServerUtils.GetConnectionUserId(connection)

end



function ServerUtils.SameUserId(left, right)

    return UserId.Same(left, right)

end



function ServerUtils.GetNicknameRows(response)

    if type(response) ~= "table" then return {} end

    if type(response.nicknames) == "table" then return response.nicknames end

    return response

end



function ServerUtils.GetNicknameMap(userIds, done)

    local map = {}

    local clean = {}

    local seen = {}

    for _, uid in ipairs(userIds or {}) do

        local normalized = UserId.Normalize(uid)

        if normalized ~= nil and seen[normalized] ~= true then

            seen[normalized] = true

            clean[#clean + 1] = UserId.ForRankCloud(normalized) or normalized

        end

    end

    if GetUserNickname == nil or #clean <= 0 then

        done(map)

        return

    end

    GetUserNickname({

        userIds = clean,

        onSuccess = function(response)

            for _, info in ipairs(ServerUtils.GetNicknameRows(response)) do

                local normalized = UserId.Normalize(info.userId)

                local nickname = info.nickname or "Tap玩家"

                if normalized ~= nil then map[normalized] = nickname end

                map[info.userId] = nickname

                map[tostring(info.userId)] = nickname

            end

            done(map)

        end,

        onError = function()

            done(map)

        end,

    })

end



function ServerUtils.NormalizePlantIndex(value)

    local index = math.floor(tonumber(value or 0) or 0)

    if index < 1 or gameConfig_.PLANTS[index] == nil then return nil end

    return index

end



function ServerUtils.NormalizePlotIndex(value)

    local index = math.floor(tonumber(value or 1) or 1)

    if index < 1 then index = 1 end

    return index

end



function ServerUtils.NormalizePositiveCount(value, maxValue)

    local count = math.floor(tonumber(value or 1) or 1)

    if count < 1 then count = 1 end

    if maxValue ~= nil then count = math.min(count, maxValue) end

    return count

end



function ServerUtils.NormalizeLocalPos(value)

    value = type(value) == "table" and value or {}

    local half = gameConfig_.CONFIG and gameConfig_.CONFIG.PlantableHalf or 0.60

    local x = Clamp(tonumber(value.x or 0) or 0, -half, half)

    local z = Clamp(tonumber(value.z or 0) or 0, -half, half)

    return { x = x, z = z }

end



function ServerUtils.IsValidPackId(packId)

    return type(packId) == "string" and gameConfig_.SEED_PACK_CONFIG[packId] ~= nil

end



function ServerUtils.IsValidSellMode(mode)

    return mode == "all" or mode == "index" or mode == "filter"

end



function ServerUtils.NextRevision(state)

    state.revision = (tonumber(state.revision or 0) or 0) + 1

end



function ServerUtils.GetMaxCropsPerPlot()

    return gameConfig_.CONFIG and gameConfig_.CONFIG.MaxCropsPerPlot or 10

end



function ServerUtils.DeepCopy(value)

    if type(value) ~= "table" then return value end

    local result = {}

    for key, item in pairs(value) do

        result[key] = ServerUtils.DeepCopy(item)

    end

    return result

end



function ServerUtils.CopyNumericKeyMap(source)

    local result = {}

    if type(source) ~= "table" then return result end

    for key, value in pairs(source) do

        local numericKey = tonumber(key)

        if numericKey ~= nil then

            result[math.floor(numericKey)] = value

        else

            result[key] = value

        end

    end

    return result

end



function ServerUtils.RollWeighted(pool)

    local total = 0

    for _, item in ipairs(pool or {}) do

        total = total + math.max(0, tonumber(item.weight or 0) or 0)

    end

    if total <= 0 then return nil end

    local r = math.random() * total

    local acc = 0

    for _, item in ipairs(pool or {}) do

        acc = acc + math.max(0, tonumber(item.weight or 0) or 0)

        if r <= acc then return item end

    end

    return pool[#pool]

end



function ServerUtils.RandomRange(minValue, maxValue)

    return minValue + math.random() * (maxValue - minValue)

end



function ServerUtils.RandItem(list)

    if list == nil or #list <= 0 then return nil end

    return list[math.random(1, #list)]

end



function ServerUtils.ClampValue(value, minValue, maxValue)

    return math.min(math.max(value, minValue), maxValue)

end



return ServerUtils

