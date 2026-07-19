-- ============================================================================
-- 服务端云存档读取
-- Grow A Garden
-- ============================================================================
-- 统一 uid 候选 key 遍历、score 读取与历史 key 迁移逻辑。
-- ============================================================================

local UserId = require("utils.user_id")

local ServerCloudStore = {}

--- 写云前深拷贝，避免异步 Commit 持有内存引用时被后续 mutate 改写。
local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return copy
end

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
    if owner ~= nil then
        value.ownerUserId = owner
        value.userId = owner
    end
    return value
end

--- 选档时不再给 canonical cloudId 固定加。内容分数相同才偏向 canonical。
local CANONICAL_SCORE_BONUS = 0

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
        if value.userId ~= nil and not UserId.Same(value.userId, requestUid) then
            print(string.format(
                "[存档隔离] 拒绝 legacy embedded userId 不匹配 request=%s embedded=%s hitKey=%s",
                tostring(GetCanonicalUidKey(requestUid)),
                tostring(UserId.Normalize(value.userId)),
                tostring(hitKey)
            ))
            return false
        end
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

--- 校验 score 表是否属于该 uid（防串档）。
function ServerCloudStore.AcceptOwnedTable(uid, value, opts)
    local hitKey = ServerCloudStore.CloudPlayerId(uid) or GetCanonicalUidKey(uid)
    return AcceptScoreRead(uid, value, hitKey, opts or { requireOwner = true })
end

--- 登录热路径：对 canonical cloudId 一次 BatchGet 拉齐多个 score key。
---@param uid any
---@param keys string[]
---@param done fun(ok: boolean, scores: table|nil, cloudUid: any, err: any)
function ServerCloudStore.BatchGetLoginScores(uid, keys, done)
    local cloudUid = ServerCloudStore.CloudPlayerId(uid)
    if cloudUid == nil then
        if done ~= nil then done(false, nil, nil, "NO_UID") end
        return
    end
    if serverCloud == nil or type(serverCloud.BatchGet) ~= "function" then
        if done ~= nil then done(false, nil, cloudUid, "NO_BATCH_GET") end
        return
    end
    keys = keys or {}
    if #keys <= 0 then
        if done ~= nil then done(true, {}, cloudUid, nil) end
        return
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    local batch = serverCloud:BatchGet(cloudUid)
    for i = 1, #keys do
        ---@diagnostic disable-next-line: param-type-mismatch
        batch = batch:Key(keys[i])
    end
    batch:Fetch({
        ok = function(scores, _iscores, _sscores)
            local result = {}
            if type(scores) == "table" then
                for key, value in pairs(scores) do
                    result[key] = value
                end
            end
            if done ~= nil then done(true, result, cloudUid, nil) end
        end,
        error = function(code, reason)
            if done ~= nil then done(false, nil, cloudUid, reason or code) end
        end,
    })
end

--- 写入 score 存档（使用 CloudPlayerId + ownerUserId 标记）。
function ServerCloudStore.SetScore(uid, scoreKey, value, events)
    local cloudUid = ServerCloudStore.CloudPlayerId(uid)
    if cloudUid == nil then
        if events ~= nil and events.error ~= nil then events.error(nil, "NO_UID") end
        return
    end
    value = DeepCopy(value)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:Set(cloudUid, scoreKey, StampOwner(value, uid), events)
end

--- BatchCommit 写入 score（CloudPlayerId + ownerUserId）。
--- 注意：不再对经济档每次 Touch。Touch 会抬高 saveEpoch，旧选档逻辑会用「多种子旧档」盖掉新 revision。
function ServerCloudStore.BatchScoreSet(commit, uid, scoreKey, value)
    local cloudUid = ServerCloudStore.CloudPlayerId(uid)
    if cloudUid == nil or commit == nil then return end
    value = DeepCopy(value)
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

--- serverCloud:Get 的兼容替代：优先 canonical cloudId，再扫描 uid 候选 key。
--- 回调签名与 serverCloud:Get 一致（ok(scores, iscores)），便于现有代码迁移。
function ServerCloudStore.Get(uid, scoreKey, events, opts)
    events = events or {}
    opts = opts or {}
    local canonicalCloudId = ServerCloudStore.CloudPlayerId(uid)
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

    if canonicalCloudId ~= nil then
        ---@diagnostic disable-next-line: param-type-mismatch
        serverCloud:Get(canonicalCloudId, scoreKey, {
            ok = function(scores, iscores)
                local tableValue = scores and scores[scoreKey]
                if type(tableValue) == "table" and AcceptScoreRead(uid, tableValue, canonicalCloudId, opts) then
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
        return
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
            print(string.format(
                "[存档读] complete uid=%s scoreKey=%s label=%s candidates=%d hitKey=%s hit=%s bestScore=%s hadReadError=%s",
                tostring(canonicalUid),
                tostring(scoreKey),
                tostring(logLabel),
                #candidates,
                tostring(bestKey),
                tostring(type(bestValue) == "table"),
                tostring(bestScore),
                tostring(hadReadError)
            ))
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
                        score = score + (function()
                            if opts.ignoreCanonicalBonus == true then return 0 end
                            local canonicalCloudId = ServerCloudStore.CloudPlayerId(uid)
                            if UserId.Same(key, canonicalCloudId) or UserId.Same(key, canonicalUid) then
                                return CANONICAL_SCORE_BONUS
                            end
                            return 0
                        end)()
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

--- 删除 uid 所有候选 key 上的 score（清档/归一后作废副本）。
function ServerCloudStore.DeleteScoreAllCandidates(uid, scoreKey, done)
    local candidates = BuildUidKeyCandidates(uid)
    if #candidates <= 0 then
        if done ~= nil then done(true) end
        return
    end
    local pending = #candidates
    local hadError = false
    local function onDone()
        pending = pending - 1
        if pending <= 0 and done ~= nil then done(not hadError) end
    end
    for _, key in ipairs(candidates) do
        local cloudKey = ServerCloudStore.CloudPlayerId(key) or key
        ---@diagnostic disable-next-line: param-type-mismatch
        serverCloud:Delete(cloudKey, scoreKey, {
            ok = onDone,
            error = function(_, reason)
                hadError = true
                print(string.format(
                    "[存档兼容] 删除副本失败 uid=%s key=%s scoreKey=%s reason=%s",
                    tostring(GetCanonicalUidKey(uid)),
                    tostring(cloudKey),
                    tostring(scoreKey),
                    tostring(reason)
                ))
                onDone()
            end,
        })
    end
end

--- 删除 uid 所有候选 key 上的列表项。
function ServerCloudStore.DeleteListAllCandidates(uid, listKey, done)
    ServerCloudStore.ListGet(uid, listKey, {
        ok = function(rows)
            local listIds = {}
            local seen = {}
            for _, row in ipairs(rows or {}) do
                local value = row.value or row
                local listId = row.list_id or row.listId
                    or (type(value) == "table" and (value.listId or value.giftId) or nil)
                if listId ~= nil then
                    local marker = type(listId) .. ":" .. tostring(listId)
                    if seen[marker] ~= true then
                        seen[marker] = true
                        listIds[#listIds + 1] = tonumber(listId) or listId
                    end
                end
            end
            if #listIds <= 0 then
                if done ~= nil then done(true) end
                return
            end
            local c = serverCloud:BatchCommit("清除玩家列表存档-" .. tostring(listKey))
            for _, listId in ipairs(listIds) do
                c:ListDelete(listId)
            end
            c:Commit({
                ok = function()
                    if done ~= nil then done(true) end
                end,
                error = function(_, reason)
                    print(string.format(
                        "[存档] 删除列表失败 uid=%s listKey=%s reason=%s",
                        tostring(GetCanonicalUidKey(uid)),
                        tostring(listKey),
                        tostring(reason)
                    ))
                    if done ~= nil then done(false) end
                end,
            })
        end,
        error = function(_, reason)
            print(string.format(
                "[存档] 读取列表失败 uid=%s listKey=%s reason=%s",
                tostring(GetCanonicalUidKey(uid)),
                tostring(listKey),
                tostring(reason)
            ))
            if done ~= nil then done(false) end
        end,
    })
end

--- 删除非 canonical cloudId 的候选 key 副本（登录归一后保留主档）。
function ServerCloudStore.DeleteNonCanonicalScoreCopies(uid, scoreKey, done)
    uid = GetCanonicalUidKey(uid) or uid
    local canonicalCloudId = ServerCloudStore.CloudPlayerId(uid)
    if canonicalCloudId == nil then
        if done ~= nil then done(true) end
        return
    end
    local candidates = BuildUidKeyCandidates(uid)
    local toDelete = {}
    local seen = {}
    for _, key in ipairs(candidates) do
        local cloudKey = ServerCloudStore.CloudPlayerId(key) or key
        local marker = type(cloudKey) .. ":" .. tostring(cloudKey)
        if seen[marker] ~= true and not UserId.Same(cloudKey, canonicalCloudId) then
            seen[marker] = true
            toDelete[#toDelete + 1] = cloudKey
        end
    end
    if #toDelete <= 0 then
        if done ~= nil then done(true) end
        return
    end
    local pending = #toDelete
    local hadError = false
    local function onDone()
        pending = pending - 1
        if pending <= 0 and done ~= nil then done(not hadError) end
    end
    for _, cloudKey in ipairs(toDelete) do
        ---@diagnostic disable-next-line: param-type-mismatch
        serverCloud:Delete(cloudKey, scoreKey, {
            ok = onDone,
            error = function(_, reason)
                hadError = true
                print(string.format(
                    "[存档兼容] 删除非 canonical 副本失败 uid=%s key=%s scoreKey=%s reason=%s",
                    tostring(uid),
                    tostring(cloudKey),
                    tostring(scoreKey),
                    tostring(reason)
                ))
                onDone()
            end,
        })
    end
end

local function CompareRescueScore(value, opts)
    if type(value) ~= "table" then return -1 end
    if opts.compareScore ~= nil then return opts.compareScore(value) end
    if opts.score ~= nil then return opts.score(value) end
    return 0
end

local function ShouldAttemptLegacyRescue(primaryValue, opts)
    if opts.allowLegacyRescue ~= true then return false end
    -- 无 owner 的历史档没有可信归属证明，登录热路径默认永久禁用自动认领。
    -- 仅允许由显式的一次性迁移工具开启，避免新号初始档在下次登录时又被高分旧档覆盖。
    if opts.allowOwnerlessLegacyRescue ~= true then return false end
    if primaryValue == nil then
        return opts.allowMissingPrimaryLegacyRescue == true
    end
    if opts.shouldLegacyRescue ~= nil then return opts.shouldLegacyRescue(primaryValue) == true end
    return false
end

local function FinishPlayerScoreRead(done, value, bestKey, hadReadError, meta)
    if done == nil then return end
    if type(value) ~= "table" then
        done(nil, bestKey, hadReadError, meta or {})
        return
    end
    done(value, bestKey, hadReadError, meta or {})
end

--- 玩家读档：优先 canonical cloudId（与 BatchScoreSet 写入一致）。
--- opts.canonicalOnly=true 时不回退全量扫描（清档后防污染复活）。
--- opts.allowLegacyRescue=true 仅表示调用方具备救援流程；还必须显式传 allowOwnerlessLegacyRescue=true。
--- 登录热路径不传该资格，因此不会自动认领无 owner 历史档。
--- primaryValue=nil 还需额外传 allowMissingPrimaryLegacyRescue=true。
function ServerCloudStore.ReadPlayerScore(uid, scoreKey, opts, done)
    opts = opts or {}
    if opts.canonicalOnly == true then
        local canonicalCloudId = ServerCloudStore.CloudPlayerId(uid)
        if canonicalCloudId == nil then
            if done ~= nil then done(nil, ServerCloudStore.GetCanonicalUidKey(uid), false, {}) end
            return
        end
        ---@diagnostic disable-next-line: param-type-mismatch
        serverCloud:Get(canonicalCloudId, scoreKey, {
            ok = function(scores)
                local rawValue = scores and scores[scoreKey]
                if type(rawValue) == "table" and AcceptScoreRead(uid, rawValue, canonicalCloudId, opts) then
                    local normalized = opts.normalize ~= nil and opts.normalize(rawValue) or rawValue
                    FinishPlayerScoreRead(done, normalized, canonicalCloudId, false, {})
                    return
                end
                FinishPlayerScoreRead(done, nil, canonicalCloudId, false, {})
            end,
            error = function()
                FinishPlayerScoreRead(done, nil, canonicalCloudId, true, {})
            end,
        })
        return
    end

    ServerCloudStore.ReadBestScore(uid, scoreKey, opts, function(bestValue, bestKey, hadReadError)
        local normalizedPrimary = type(bestValue) == "table"
            and (opts.normalize ~= nil and opts.normalize(bestValue) or bestValue)
            or nil
        if ShouldAttemptLegacyRescue(normalizedPrimary, opts) ~= true then
            FinishPlayerScoreRead(done, normalizedPrimary, bestKey, hadReadError, {})
            return
        end

        local legacyOpts = {
            normalize = opts.normalize,
            score = opts.score,
            compareScore = opts.compareScore,
            requireOwner = false,
            ignoreCanonicalBonus = true,
            logLabel = tostring(opts.logLabel or scoreKey) .. "(legacy救援)",
        }
        ServerCloudStore.ReadBestScore(uid, scoreKey, legacyOpts, function(legacyValue, legacyKey, legacyHadError)
            local normalizedLegacy = type(legacyValue) == "table"
                and (opts.normalize ~= nil and opts.normalize(legacyValue) or legacyValue)
                or nil
            if normalizedLegacy == nil then
                FinishPlayerScoreRead(done, normalizedPrimary, bestKey, hadReadError or legacyHadError, {})
                return
            end

            local primaryScore = CompareRescueScore(normalizedPrimary, opts)
            local legacyScore = CompareRescueScore(normalizedLegacy, opts)
            local margin = opts.legacyRescueMargin or 50
            if normalizedPrimary == nil or legacyScore > primaryScore + margin then
                print(string.format(
                    "[存档兼容] legacy 救援命中 uid=%s scoreKey=%s hitKey=%s primaryScore=%s legacyScore=%s",
                    tostring(GetCanonicalUidKey(uid)),
                    tostring(scoreKey),
                    tostring(legacyKey),
                    tostring(primaryScore),
                    tostring(legacyScore)
                ))
                FinishPlayerScoreRead(done, normalizedLegacy, legacyKey, hadReadError or legacyHadError, {
                    legacyRescued = true,
                })
                return
            end
            FinishPlayerScoreRead(done, normalizedPrimary, bestKey, hadReadError, {})
        end)
    end)
end

--- 从与经济档相同的 hitKey 读取权威农场，避免跨 key 拼档。
function ServerCloudStore.ReadFarmAtKey(uid, hitKey, scoreKey, opts, done)
    opts = opts or {}
    local readKey = hitKey or ServerCloudStore.CloudPlayerId(uid)
    if readKey == nil then
        if done ~= nil then done(nil, readKey) end
        return
    end
    serverCloud:Get(readKey, scoreKey, {
        ok = function(scores)
            local rawValue = scores and scores[scoreKey]
            if type(rawValue) ~= "table" or not AcceptScoreRead(uid, rawValue, readKey, opts) then
                if done ~= nil then done(nil, readKey) end
                return
            end
            local normalized = opts.normalize ~= nil and opts.normalize(rawValue) or rawValue
            if done ~= nil then done(normalized, readKey) end
        end,
        error = function()
            if done ~= nil then done(nil, readKey) end
        end,
    })
end

function ServerCloudStore.GetCanonicalUidKey(uid)
    return GetCanonicalUidKey(uid)
end

function ServerCloudStore.CanonicalUid(uid)
    return GetCanonicalUidKey(uid)
end

--- 若命中历史 uid key，则迁移到 canonical key 后再回调。
--- 登录热路径已改 BatchGet；此函数仅供少数冷路径兼容调用。
--- opts.respondBeforeWrite=true 时先 onReady 再异步写云，避免 Set 挂起阻塞下发。
function ServerCloudStore.MigrateScoreIfNeeded(canonicalUid, bestKey, scoreKey, value, opts)
    opts = opts or {}
    canonicalUid = GetCanonicalUidKey(canonicalUid)
    if bestKey == nil or UserId.Same(bestKey, canonicalUid) or value == nil or canonicalUid == nil then
        if opts.onReady ~= nil then opts.onReady(value, false) end
        return
    end
    local label = opts.migrationLabel or "存档"
    print(string.format("[存档兼容] %s命中历史 uid key=%s，迁移到当前 key=%s", label, tostring(bestKey), tostring(canonicalUid)))
    if opts.respondBeforeWrite == true and opts.onReady ~= nil then
        opts.onReady(value, true)
    end
    local cloudUid = ServerCloudStore.CloudPlayerId(canonicalUid)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:Set(cloudUid, scoreKey, StampOwner(value, canonicalUid), {
        ok = function()
            if opts.respondBeforeWrite == true then
                print(string.format("[存档兼容] %s后台迁移写云成功 key=%s", label, tostring(canonicalUid)))
            elseif opts.onReady ~= nil then
                opts.onReady(value, true)
            end
        end,
        error = function(_, reason)
            print(string.format("[存档兼容] %s迁移失败，使用历史 key 数据返回: %s", label, tostring(reason)))
            if opts.respondBeforeWrite ~= true and opts.onReady ~= nil then
                opts.onReady(value, true)
            end
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
