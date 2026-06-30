-- ============================================================================
-- 服务端通用工具函数
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的低风险工具函数。
-- 只承接原有实现，不改变参数、返回值和边界处理。
-- ============================================================================

local ServerUtils = {}

local gameConfig_ = nil

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

function ServerUtils.GetConnectionUserId(connection)
    if connection == nil or connection.identity == nil or connection.identity["user_id"] == nil then
        return nil
    end
    return connection.identity["user_id"]:GetInt64()
end

function ServerUtils.NormalizeUserId(userId)
    if userId == nil or userId == 0 or userId == "" then return nil end
    local text = tostring(userId)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "0" then return nil end
    local integerText = string.match(text, "^(%-?%d+)%.0+$")
    if integerText ~= nil then return integerText end
    local numericId = tonumber(text)
    if numericId ~= nil and numericId == math.floor(numericId) and math.abs(numericId) < 9007199254740992 then
        return string.format("%.0f", numericId)
    end
    return text
end

function ServerUtils.GetRequestUserId(connection, data)
    local uid = ServerUtils.GetConnectionUserId(connection)
    if uid ~= nil then return uid end
    if type(data) ~= "table" then return nil end
    return ServerUtils.NormalizeUserId(data.userId)
end

function ServerUtils.SameUserId(left, right)
    local leftId = ServerUtils.NormalizeUserId(left)
    local rightId = ServerUtils.NormalizeUserId(right)
    return leftId ~= nil and rightId ~= nil and leftId == rightId
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
        local normalized = ServerUtils.NormalizeUserId(uid)
        if normalized ~= nil and seen[normalized] ~= true then
            seen[normalized] = true
            clean[#clean + 1] = normalized
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
                local normalized = ServerUtils.NormalizeUserId(info.userId)
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
