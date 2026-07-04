-- ============================================================================
-- 服务端云存档读取
-- Grow A Garden
-- ============================================================================
-- 统一 uid 候选 key 遍历、score 读取与历史 key 迁移逻辑。
-- ============================================================================

local UserId = require("utils.user_id")

local ServerCloudStore = {}

local ECONOMY_STATE_KEY = "garden_economy_state_v1"

local function BuildUidKeyCandidates(uid)
    return UserId.BuildCloudKeyCandidates(uid)
end

local function GetCanonicalUidKey(uid)
    return UserId.GetCanonicalKey(uid)
end

function ServerCloudStore.CloudPlayerId(uid)
    return UserId.CloudPlayerId(uid)
end

local function StampOwner(value, uid)
    if type(value) ~= "table" then return value end
    local owner = GetCanonicalUidKey(uid)
    if owner ~= nil then value.ownerUserId = owner end
    return value
end

local function TouchEconomyStateIfNeeded(scoreKey, value)
    if scoreKey ~= ECONOMY_STATE_KEY or type(value) ~= "table" then return value end
    local ServerEconomyState = require("server.server_economy_state")
    return ServerEconomyState.TouchEconomyState(value)
end

local function AcceptScoreRead(requestUid, value, hitKey, opts)
    opts = opts or {}
    if type(value) ~= "table" then return false end
    local owner = value.ownerUserId
    if owner == nil then
        if opts.requireOwner == true then
            print(string.format(
                "[存档隔离] 拒绝无 owner 标记的 legacy 档 uid=%s hitKey=%s",
                tostring(GetCanonicalUidKey(requestUid)),
                tostring(hitKey)
            ))
            return false
        end
        if not UserId.Same(hitKey, requestUid) then return false end
        print(string.format(
            "[存档隔离] legacy 无 owner 标记，按 key 接受 uid=%s hitKey=%s",
            tostring(GetCanonicalUidKey(requestUid)),
            tostring(hitKey)
        ))
        return true
    end
    if UserId.Same(owner, requestUid) then
        if value.userId ~= nil and not UserId.Same(value.userId, requestUid) then
            print(string.format(
                "[存档隔离] 拒绝 embedded userId 不匹配 request=%s embedded=%s hitKey=%s",
                tostring(GetCanonicalUidKey(requestUid)),
                tostring(UserId.Normalize(value.userId)),
                tostring(hitKey)
            ))
            return false
        end
        return true
    end
    print(string.format(
        "[存档隔离] 拒绝串档存档 request=%s owner=%s hitKey=%s",
        tostring(GetCanonicalUidKey(requestUid)),
        tostring(UserId.Normalize(owner)),
        tostring(hitKey)
    ))
    return false
end

--- 读取「目标玩家」存档：在 AcceptScoreRead 基础上，额外校验 embedded userId。
local function AcceptTargetScoreRead(targetUid, value, hitKey)
    if not AcceptScoreRead(targetUid, value, hitKey) then return false end
    if value.userId ~= nil and not UserId.Same(value.userId, targetUid) then
        print(string.format(
            "[存档隔离] 拒绝目标档 embedded userId 不匹配 target=%s embedded=%s hitKey=%s",
            tostring(GetCanonicalUidKey(targetUid)),
            tostring(UserId.Normalize(value.userId)),
            tostring(hitKey)
        ))
        return false
    end
    return true
end

function ServerCloudStore.StampOwner(value, uid)
    return StampOwner(value, uid)
end

--- 写入 score 存档（使用 CloudPlayerId + ownerUserId 标记）。
function ServerCloudStore.SetScore(uid, scoreKey, value, events)
    local cloudUid = ServerCloudStore.CloudPlayerId(uid)
    if cloudUid == nil then
        if events ~= nil and events.error ~= nil then events.error(nil, "NO_UID") end
        return
    end
    value = TouchEconomyStateIfNeeded(scoreKey, value)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:Set(cloudUid, scoreKey, StampOwner(value, uid), events)
end

--- BatchCommit 写入 score（CloudPlayerId + ownerUserId）。
function ServerCloudStore.BatchScoreSet(commit, uid, scoreKey, value)
    local cloudUid = ServerCloudStore.CloudPlayerId(uid)
    if cloudUid == nil or commit == nil then return end
    value = TouchEconomyStateIfNeeded(scoreKey, value)
    ---@diagnostic disable-next-line: param-type-mismatch
    commit:ScoreSet(cloudUid, scoreKey, StampOwner(value, uid))
end

--- 按 uid 候选 key 顺序读取第一个有效 table 存档。
---@param uid any
---@param scoreKey string
---@param done fun(value: table|nil, hitKey: any, errorReason: any)
---@param opts table|nil
function ServerCloudStore.ReadScore(uid, scoreKey, done, opts)
    opts = opts or {}
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1
    local fallbackError = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done(nil, GetCanonicalUidKey(uid), fallbackError)
            return
        end
        serverCloud:Get(key, scoreKey, {
            ok = function(scores)
                local value = scores and scores[scoreKey]
                if type(value) == "table" and AcceptScoreRead(uid, value, key, opts) then
                    done(value, key, nil)
                    return
                end
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
end

--- 读取指定目标玩家的 score（拜访/跨用户读档专用，校验 ownerUserId + embedded userId）。
---@param targetUid any
---@param scoreKey string
---@param done fun(value: table|nil, hitKey: any, errorReason: any)
function ServerCloudStore.ReadTargetScore(targetUid, scoreKey, done)
    local candidates = BuildUidKeyCandidates(targetUid)
    local index = 1
    local fallbackError = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done(nil, GetCanonicalUidKey(targetUid), fallbackError)
            return
        end
        serverCloud:Get(key, scoreKey, {
            ok = function(scores)
                local value = scores and scores[scoreKey]
                if type(value) == "table" and AcceptTargetScoreRead(targetUid, value, key) then
                    done(value, key, nil)
                    return
                end
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
end

--- serverCloud:Get 的兼容替代：自动扫描 uid 候选 key。
--- 回调签名与 serverCloud:Get 一致（ok(scores, iscores)），便于现有代码迁移。
function ServerCloudStore.Get(uid, scoreKey, events, opts)
    events = events or {}
    opts = opts or {}
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1
    local fallbackError = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            if events.error ~= nil then
                events.error(nil, fallbackError or "NOT_FOUND")
            end
            return
        end
        serverCloud:Get(key, scoreKey, {
            ok = function(scores, iscores)
                local tableValue = scores and scores[scoreKey]
                if type(tableValue) == "table" then
                    if AcceptScoreRead(uid, tableValue, key, opts) then
                        if events.ok ~= nil then events.ok(scores, iscores) end
                        return
                    end
                    readNext()
                    return
                end
                local hasValue = (type(scores) == "table" and scores[scoreKey] ~= nil)
                    or (type(iscores) == "table" and iscores[scoreKey] ~= nil)
                if hasValue then
                    if events.ok ~= nil then events.ok(scores, iscores) end
                    return
                end
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
end

--- 遍历 uid 候选 key，返回 score 最高的归一化存档。
---@param uid any
---@param scoreKey string
---@param opts table|nil
---@param done fun(bestValue: table|nil, bestKey: any, hadReadError: boolean)
function ServerCloudStore.ReadBestScore(uid, scoreKey, opts, done)
    opts = opts or {}
    local candidates = BuildUidKeyCandidates(uid)
    local bestKey = nil
    local bestValue = nil
    local bestScore = -1
    local index = 1
    local hadReadError = false
    local logLabel = opts.logLabel or scoreKey

    local canonicalUid = GetCanonicalUidKey(uid)

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done(bestValue, bestKey, hadReadError)
            return
        end
        serverCloud:Get(key, scoreKey, {
            ok = function(scores)
                local rawValue = scores and scores[scoreKey]
                if type(rawValue) == "table" and AcceptScoreRead(uid, rawValue, key, opts) then
                    local normalized = opts.normalize ~= nil and opts.normalize(rawValue) or rawValue
                    if type(normalized) == "table" then
                        local score = opts.score ~= nil and opts.score(normalized) or 0
                        local preferNew = score > bestScore
                        if not preferNew and score == bestScore and canonicalUid ~= nil then
                            preferNew = UserId.Same(key, canonicalUid) and not UserId.Same(bestKey, canonicalUid)
                        end
                        if preferNew then
                            bestScore = score
                            bestValue = normalized
                            bestKey = key
                        end
                    end
                end
                readNext()
            end,
            error = function(_, reason)
                hadReadError = true
                print(string.format("[存档兼容] %s读取失败 key=%s reason=%s", tostring(logLabel), tostring(key), tostring(reason)))
                readNext()
            end,
        })
    end

    readNext()
end

function ServerCloudStore.GetCanonicalUidKey(uid)
    return GetCanonicalUidKey(uid)
end

function ServerCloudStore.CanonicalUid(uid)
    return GetCanonicalUidKey(uid)
end

--- 若命中历史 uid key，则迁移到 canonical key 后再回调。
function ServerCloudStore.MigrateScoreIfNeeded(canonicalUid, bestKey, scoreKey, value, opts)
    opts = opts or {}
    canonicalUid = GetCanonicalUidKey(canonicalUid)
    if bestKey == nil or UserId.Same(bestKey, canonicalUid) or value == nil or canonicalUid == nil then
        if opts.onReady ~= nil then opts.onReady(value, false) end
        return
    end
    local label = opts.migrationLabel or "存档"
    print(string.format("[存档兼容] %s命中历史 uid key=%s，迁移到当前 key=%s", label, tostring(bestKey), tostring(canonicalUid)))
    local cloudUid = ServerCloudStore.CloudPlayerId(canonicalUid)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:Set(cloudUid, scoreKey, StampOwner(value, canonicalUid), {
        ok = function()
            if opts.onReady ~= nil then opts.onReady(value, true) end
        end,
        error = function(_, reason)
            print(string.format("[存档兼容] %s迁移失败，使用历史 key 数据返回: %s", label, tostring(reason)))
            if opts.onReady ~= nil then opts.onReady(value, true) end
        end,
    })
end

--- serverCloud.list:Get 的兼容替代：扫描 uid 全部候选 key 并合并去重。
--- 避免 number/string 分裂时“第一个非空 key”覆盖真实存档。
function ServerCloudStore.ListGet(uid, listKey, events)
    events = events or {}
    uid = GetCanonicalUidKey(uid) or uid
    local candidates = BuildUidKeyCandidates(uid)
    local merged = {}
    local seen = {}
    local index = 1
    local fallbackError = nil
    local hitKeys = {}

    local function rowMarker(row)
        if type(row) ~= "table" then return nil end
        local value = row.value or row
        local listId = row.list_id or row.listId
        if listId == nil and type(value) == "table" then
            listId = value.listId
        end
        if listId ~= nil then return "id:" .. tostring(listId) end
        return nil
    end

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            if events.ok ~= nil then
                events.ok(merged, hitKeys[1])
            elseif events.error ~= nil then
                events.error(nil, fallbackError or "NOT_FOUND")
            end
            return
        end
        serverCloud.list:Get(key, listKey, {
            ok = function(rows)
                local added = false
                for _, row in ipairs(rows or {}) do
                    local marker = rowMarker(row) or ("key:" .. tostring(key) .. ":" .. tostring(#merged + 1))
                    if seen[marker] ~= true then
                        seen[marker] = true
                        merged[#merged + 1] = row
                        added = true
                    end
                end
                if added then hitKeys[#hitKeys + 1] = key end
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
end

--- serverCloud.quota:Get 的兼容替代：扫描 uid 候选 key，返回第一个非空配额行。
function ServerCloudStore.QuotaGet(uid, quotaKey, events)
    events = events or {}
    uid = GetCanonicalUidKey(uid) or uid
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1
    local fallbackError = nil
    local fallbackRows = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            if events.ok ~= nil then events.ok(fallbackRows or {}, nil) end
            if fallbackRows == nil and events.error ~= nil then
                events.error(nil, fallbackError or "NOT_FOUND")
            end
            return
        end
        serverCloud.quota:Get(key, quotaKey, {
            ok = function(rows)
                if rows ~= nil and #rows > 0 then
                    if events.ok ~= nil then events.ok(rows, key) end
                    return
                end
                fallbackRows = fallbackRows or rows
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
end

return ServerCloudStore
