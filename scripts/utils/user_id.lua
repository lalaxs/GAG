-- ============================================================================
-- 用户 ID 归一化工具（客户端 / 服务端共享）
-- ============================================================================
-- 云端存档 key 统一使用 canonical string，避免 number / string 分裂。
-- 读取历史存档时配合 BuildKeyCandidates 做兼容扫描。
-- ============================================================================

local UserId = {}

local INVALID_UID_TEXT = {
    ["nil"] = true,
    ["null"] = true,
    ["undefined"] = true,
    ["nan"] = true,
    ["unknown"] = true,
    ["guest"] = true,
    ["anonymous"] = true,
    ["none"] = true,
}

local function TrimText(value)
    local text = tostring(value)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function IsInvalidUidText(text)
    if text == nil then return true end
    text = TrimText(text)
    if text == "" or text == "0" then return true end
    return INVALID_UID_TEXT[string.lower(text)] == true
end

--- 从连接 identity Variant 读取 Tap UID（兼容正式服 string / int64）。
---@param value any
---@return string|nil
function UserId.ReadIdentityValue(value)
    if value == nil then return nil end
    if type(value) == "string" or type(value) == "number" then
        return UserId.Normalize(value)
    end
    if type(value.GetString) == "function" then
        local ok, text = pcall(function() return value:GetString() end)
        if ok and text ~= nil and text ~= "" then
            local normalized = UserId.Normalize(text)
            if normalized ~= nil then return normalized end
        end
    end
    if type(value.GetInt64) == "function" then
        local ok, numeric = pcall(function() return value:GetInt64() end)
        if ok and numeric ~= nil and numeric ~= 0 then
            local normalized = UserId.Normalize(numeric)
            if normalized ~= nil then return normalized end
        end
    end
    return UserId.Normalize(value)
end

--- 从任意 identity 字段读取字符串值。
---@param value any
---@return string|nil
function UserId.ReadIdentityText(value)
    if value == nil then return nil end
    if type(value) == "string" or type(value) == "number" then
        local text = TrimText(value)
        if not IsInvalidUidText(text) then return text end
        return nil
    end
    if type(value.GetString) == "function" then
        local ok, text = pcall(function() return value:GetString() end)
        if ok and text ~= nil then
            text = TrimText(text)
            if not IsInvalidUidText(text) then return text end
        end
    end
    if type(value.GetInt64) == "function" then
        local ok, numeric = pcall(function() return value:GetInt64() end)
        if ok and numeric ~= nil and numeric ~= 0 then return tostring(numeric) end
    end
    if type(value.GetInt) == "function" then
        local ok, numeric = pcall(function() return value:GetInt() end)
        if ok and numeric ~= nil and numeric ~= 0 then return tostring(numeric) end
    end
    local text = TrimText(value)
    if not IsInvalidUidText(text) then return text end
    return nil
end

--- 从 Connection.identity 读取 game session / room / match 标识。
---@param connection any
---@return string|nil, string|nil
function UserId.ReadConnectionGameSessionId(connection)
    if connection == nil or connection.identity == nil then return nil, nil end
    local keys = {
        "game_session_id",
        "gameSessionId",
        "game_session",
        "session_id",
        "sessionId",
        "room_id",
        "roomId",
        "match_id",
        "matchId",
    }
    for _, key in ipairs(keys) do
        local text = UserId.ReadIdentityText(connection.identity[key])
        if text ~= nil then return text, key end
    end
    return nil, nil
end

--- 从 Connection.identity 读取 user_id（仅 ClientIdentity 时调用一次）。
---@param connection any
---@return string|nil
function UserId.ReadConnectionIdentity(connection)
    if connection == nil or connection.identity == nil or connection.identity["user_id"] == nil then
        return nil
    end
    return UserId.ReadIdentityValue(connection.identity["user_id"])
end

--- 经济/农场档是否允许下发给目标玩家。
---@param requestUid any
---@param value table|nil
---@return boolean
function UserId.IsOwnedSave(requestUid, value)
    if type(value) ~= "table" then return false end
    local owner = value.ownerUserId
    if owner == nil then return false end
    if not UserId.Same(owner, requestUid) then return false end
    if value.userId ~= nil and not UserId.Same(value.userId, requestUid) then return false end
    return true
end

--- 将任意 UID 输入归一化为 canonical string（或 nil）。
---@param userId any
---@return string|nil
function UserId.Normalize(userId)
    if userId == nil or userId == 0 or userId == "" then return nil end
    local text = TrimText(userId)
    if IsInvalidUidText(text) then return nil end
    local integerText = string.match(text, "^(%-?%d+)%.0+$")
    if integerText ~= nil then
        if IsInvalidUidText(integerText) then return nil end
        return integerText
    end
    local numericId = tonumber(text)
    if numericId ~= nil and numericId == math.floor(numericId) and math.abs(numericId) < 9007199254740992 then
        return string.format("%.0f", numericId)
    end
    return text
end

--- 判断两个 UID 是否指向同一用户。
---@param left any
---@param right any
---@return boolean
function UserId.Same(left, right)
    local leftId = UserId.Normalize(left)
    local rightId = UserId.Normalize(right)
    return leftId ~= nil and rightId ~= nil and leftId == rightId
end

--- 生成云端读取候选 key（原始值、canonical string、安全整数 number）。
---@param uid any
---@return table
function UserId.BuildKeyCandidates(uid)
    local normalized = UserId.Normalize(uid)
    if normalized == nil then return {} end
    local keys = {}
    local seen = {}
    local function add(key)
        if key == nil or key == "" then return end
        local marker = type(key) .. ":" .. tostring(key)
        if seen[marker] == true then return end
        seen[marker] = true
        keys[#keys + 1] = key
    end
    add(uid)
    add(normalized)
    local numeric = tonumber(normalized)
    if numeric ~= nil and numeric == math.floor(numeric) and math.abs(numeric) < 9007199254740992 then
        add(numeric)
    end
    return keys
end

--- 写入云端时使用的 canonical key（始终为 string 或 nil）。
---@param uid any
---@return string|nil
function UserId.GetCanonicalKey(uid)
    return UserId.Normalize(uid)
end

--- 排行榜 cloud API 优先使用安全整数 UID（GetRankList 的 player 为 number）。
---@param uid any
---@return number|string|nil
function UserId.ForRankCloud(uid)
    local normalized = UserId.Normalize(uid)
    if normalized == nil then return nil end
    local numeric = tonumber(normalized)
    if numeric ~= nil and numeric == math.floor(numeric) and math.abs(numeric) < 9007199254740992 then
        return numeric
    end
    return normalized
end

--- serverCloud 读写使用的玩家 ID（优先 number，与官方 serverCloud 文档一致）。
---@param uid any
---@return number|string|nil
function UserId.CloudPlayerId(uid)
    return UserId.ForRankCloud(uid) or UserId.Normalize(uid)
end

--- 云端存档扫描候选 key：优先 number，再 canonical string。
---@param uid any
---@return table
function UserId.BuildCloudKeyCandidates(uid)
    local normalized = UserId.Normalize(uid)
    if normalized == nil then return {} end
    local keys = {}
    local seen = {}
    local function add(key)
        if key == nil or key == "" then return end
        local marker = type(key) .. ":" .. tostring(key)
        if seen[marker] == true then return end
        seen[marker] = true
        keys[#keys + 1] = key
    end
    add(UserId.CloudPlayerId(normalized))
    add(normalized)
    add(uid)
    return keys
end

-- 兼容旧命名
UserId.NormalizeUserId = UserId.Normalize
UserId.SameUserId = UserId.Same
UserId.BuildUidKeyCandidates = UserId.BuildKeyCandidates
UserId.BuildCloudUidKeyCandidates = UserId.BuildCloudKeyCandidates
UserId.GetCanonicalUidKey = UserId.GetCanonicalKey

return UserId
