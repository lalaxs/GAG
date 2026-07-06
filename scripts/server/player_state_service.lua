-- ============================================================================
-- 服务端玩家会话状态服务
-- Grow A Garden
-- ============================================================================
-- 运行时以内存 session 作为玩家经济/农场状态唯一权威；云端只用于登录加载和后台持久化。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")

local PlayerStateService = {}

local deps_ = {}
local sessions_ = {}

local FLUSH_INTERVAL = 1.0
local updateAccum_ = 0

local function Now()
    if deps_.Now ~= nil then return deps_.Now() end
    return os and os.time and os.time() or 0
end

local function CanonicalUid(uid)
    return ServerCloudStore.GetCanonicalUidKey(uid) or uid
end

local function NormalizeEconomy(state)
    if deps_.NormalizeEconomyState ~= nil then return deps_.NormalizeEconomyState(state) end
    return type(state) == "table" and state or {}
end

local function NormalizeFarm(state)
    if deps_.NormalizeFarmState ~= nil then return deps_.NormalizeFarmState(state) end
    return type(state) == "table" and state or { version = 1, revision = 0, plots = {} }
end

local function BuildInitialEconomy()
    if deps_.BuildInitialEconomyState ~= nil then return deps_.BuildInitialEconomyState() end
    return NormalizeEconomy(nil)
end

local function EnsureEconomyRevision(state)
    if type(state) ~= "table" then return end
    state.revision = math.max(0, math.floor(tonumber(state.revision or 0) or 0))
end

local function EnsureFarmRevision(state)
    if type(state) ~= "table" then return end
    state.revision = math.max(0, math.floor(tonumber(state.revision or 0) or 0))
end

local function Callback(callback, ...)
    if callback == nil then return end
    local ok, err = pcall(callback, ...)
    if ok ~= true then print("[PlayerState] callback error: " .. tostring(err)) end
end

local function GetOrCreateSession(uid)
    local canonicalUid = CanonicalUid(uid)
    local key = tostring(canonicalUid)
    local session = sessions_[key]
    if session == nil then
        session = {
            uid = canonicalUid,
            economy = nil,
            farm = nil,
            social = nil,
            economyLoaded = false,
            farmLoaded = false,
            loading = false,
            loadCallbacks = {},
            queue = {},
            processing = false,
            dirtyEconomy = false,
            dirtyFarm = false,
            dirtySocial = false,
            lastFlushAt = 0,
            flushPending = false,
            flushQueued = false,
            flushFailed = false,
            revision = 0,
        }
        sessions_[key] = session
    end
    return session
end

local function FinishLoad(session, err)
    session.loading = false
    local callbacks = session.loadCallbacks or {}
    session.loadCallbacks = {}
    for _, callback in ipairs(callbacks) do
        Callback(callback, err == nil and session or nil, err)
    end
end

function PlayerStateService.Init(deps)
    deps_ = deps or {}
end

function PlayerStateService.GetSession(uid)
    local session = sessions_[tostring(CanonicalUid(uid))]
    if session == nil or session.economyLoaded ~= true or session.farmLoaded ~= true then return nil end
    return session
end

function PlayerStateService.HasLoadedSession(uid)
    return PlayerStateService.GetSession(uid) ~= nil
end

function PlayerStateService.Load(uid, callback)
    local session = GetOrCreateSession(uid)
    if session.economyLoaded == true and session.farmLoaded == true then
        Callback(callback, session, nil)
        return
    end
    session.loadCallbacks[#session.loadCallbacks + 1] = callback
    if session.loading == true then return end
    session.loading = true

    local uidKey = session.uid
    print(string.format("[PlayerState] load uid=%s", tostring(uidKey)))

    local economyOpts = {
        normalize = NormalizeEconomy,
        requireOwner = true,
        canonicalOnly = true,
        logLabel = "玩家会话经济",
    }
    local farmOpts = {
        normalize = NormalizeFarm,
        requireOwner = true,
        canonicalOnly = true,
        logLabel = "玩家会话农场",
    }

    ServerCloudStore.ReadPlayerScore(uidKey, deps_.Shared.KEYS.ECONOMY_STATE, economyOpts, function(economy, economyKey, economyErr, economyMeta)
        if type(economy) ~= "table" then
            if economyErr == true then
                FinishLoad(session, "ECONOMY_LOAD_FAILED")
                return
            end
            economy = BuildInitialEconomy()
        end
        economy = ServerCloudStore.StampOwner(NormalizeEconomy(economy), uidKey)
        EnsureEconomyRevision(economy)
        if economyMeta ~= nil and economyMeta.legacyRescued == true then
            session.dirtyEconomy = true
        end

        ServerCloudStore.ReadPlayerScore(uidKey, deps_.Shared.KEYS.AUTH_FARM_STATE, farmOpts, function(farm, farmKey, farmErr, farmMeta)
            if type(farm) ~= "table" then
                if farmErr == true then
                    FinishLoad(session, "FARM_LOAD_FAILED")
                    return
                end
                farm = NormalizeFarm(nil)
            end
            farm = ServerCloudStore.StampOwner(NormalizeFarm(farm), uidKey)
            EnsureFarmRevision(farm)
            if farmMeta ~= nil and farmMeta.legacyRescued == true then
                session.dirtyFarm = true
            end
            session.economy = economy
            session.farm = farm
            session.social = session.social or nil
            session.economyLoaded = true
            session.farmLoaded = true
            session.revision = math.max(tonumber(economy.revision or 0) or 0, tonumber(farm.revision or 0) or 0)
            print(string.format(
                "[PlayerState] load ok uid=%s economyKey=%s farmKey=%s economyRevision=%s farmRevision=%s",
                tostring(uidKey),
                tostring(economyKey),
                tostring(farmKey),
                tostring(economy.revision),
                tostring(farm.revision)
            ))
            FinishLoad(session, nil)
        end)
    end)
end

local function ProcessQueue(session)
    if session.processing == true then return end
    local item = table.remove(session.queue, 1)
    if item == nil then return end
    session.processing = true

    local ok, result = pcall(function()
        if item.kind == "economy" then
            return item.mutator(session.economy, session)
        end
        return item.mutator(session.economy, session.farm, session)
    end)
    if ok ~= true then
        result = { success = false, message = tostring(result), code = "MUTATOR_ERROR" }
    end
    result = type(result) == "table" and result or { success = false, message = "操作失败" }

    if result.success == true then
        local now = Now()
        if item.kind == "economy" or item.kind == "economy_farm" then
            EnsureEconomyRevision(session.economy)
            session.economy.revision = session.economy.revision + 1
            session.economy.updatedAt = now
            session.dirtyEconomy = true
            if type(result.response) == "table" and result.response.state == nil then
                result.response.state = session.economy
            end
        end
        if item.kind == "economy_farm" then
            EnsureFarmRevision(session.farm)
            session.farm.revision = session.farm.revision + 1
            session.farm.updatedAt = now
            session.dirtyFarm = true
            if type(result.response) == "table" then
                if result.response.farm == nil then result.response.farm = session.farm end
                if result.response.farmRevision == nil then result.response.farmRevision = session.farm.revision end
            end
        end
        session.revision = session.revision + 1
        -- 允许下一帧立刻 flush，降低断线/关房前未落云的窗口
        session.lastFlushAt = 0
        print(string.format(
            "[PlayerState] mutate uid=%s action=%s economyRevision=%s farmRevision=%s",
            tostring(session.uid),
            tostring(item.actionName),
            tostring(session.economy and session.economy.revision),
            tostring(session.farm and session.farm.revision)
        ))
    end

    session.processing = false
    Callback(item.callback, result, session)
    ProcessQueue(session)
end

local function EnqueueMutation(uid, kind, actionName, mutator, callback)
    PlayerStateService.Load(uid, function(session, err)
        if session == nil then
            Callback(callback, { success = false, message = "同步失败", retryable = true, error = err })
            return
        end
        session.queue[#session.queue + 1] = {
            kind = kind,
            actionName = actionName,
            mutator = mutator,
            callback = callback,
        }
        ProcessQueue(session)
    end)
end

function PlayerStateService.MutateEconomy(uid, actionName, mutator, callback)
    EnqueueMutation(uid, "economy", actionName, mutator, callback)
end

function PlayerStateService.MutateEconomyAndFarm(uid, actionName, mutator, callback)
    EnqueueMutation(uid, "economy_farm", actionName, mutator, callback)
end

function PlayerStateService.MarkDirty(uid, kind)
    local session = GetOrCreateSession(uid)
    if kind == "economy" then session.dirtyEconomy = true end
    if kind == "farm" then session.dirtyFarm = true end
    if kind == "social" then session.dirtySocial = true end
end

function PlayerStateService.Reset(uid, economy, farm, social)
    local session = GetOrCreateSession(uid)
    session.economy = ServerCloudStore.StampOwner(NormalizeEconomy(economy), session.uid)
    session.farm = ServerCloudStore.StampOwner(NormalizeFarm(farm), session.uid)
    session.social = type(social) == "table" and social or nil
    EnsureEconomyRevision(session.economy)
    EnsureFarmRevision(session.farm)
    session.economyLoaded = true
    session.farmLoaded = true
    session.loading = false
    session.queue = {}
    session.processing = false
    session.dirtyEconomy = true
    session.dirtyFarm = true
    session.dirtySocial = type(social) == "table"
    session.revision = session.revision + 1
    print(string.format("[PlayerState] reset uid=%s economyRevision=%s farmRevision=%s", tostring(session.uid), tostring(session.economy.revision), tostring(session.farm.revision)))
    return session
end

function PlayerStateService.Clear(uid)
    sessions_[tostring(CanonicalUid(uid))] = nil
end

function PlayerStateService.Flush(uid, callback)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then
        Callback(callback, false, "NO_SESSION")
        return
    end
    if session.flushPending == true then
        session.flushQueued = true
        Callback(callback, false, "FLUSH_PENDING")
        return
    end
    local writeEconomy = session.dirtyEconomy == true and type(session.economy) == "table"
    local writeFarm = session.dirtyFarm == true and type(session.farm) == "table"
    local writeSocial = session.dirtySocial == true and type(session.social) == "table"
    if not writeEconomy and not writeFarm and not writeSocial then
        session.flushQueued = false
        Callback(callback, true)
        return
    end

    local economyRevision = tonumber(session.economy and session.economy.revision or 0) or 0
    local farmRevision = tonumber(session.farm and session.farm.revision or 0) or 0
    session.flushPending = true
    session.flushQueued = false
    local c = serverCloud:BatchCommit("保存玩家会话状态")
    if writeEconomy then ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.ECONOMY_STATE, session.economy) end
    if writeFarm then ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.AUTH_FARM_STATE, session.farm) end
    if writeSocial then ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.SOCIAL_SAVE, session.social) end
    c:Commit({
        ok = function()
            session.flushPending = false
            session.flushFailed = false
            session.lastFlushAt = Now()
            if writeEconomy and (tonumber(session.economy and session.economy.revision or 0) or 0) == economyRevision then
                session.dirtyEconomy = false
            end
            if writeFarm and (tonumber(session.farm and session.farm.revision or 0) or 0) == farmRevision then
                session.dirtyFarm = false
            end
            if writeSocial then session.dirtySocial = false end
            print(string.format("[PlayerState] flush uid=%s ok economyRevision=%s farmRevision=%s", tostring(session.uid), tostring(economyRevision), tostring(farmRevision)))
            Callback(callback, true)
            if session.flushQueued == true
                or session.dirtyEconomy == true
                or session.dirtyFarm == true
                or session.dirtySocial == true then
                session.flushQueued = false
                session.lastFlushAt = 0
                PlayerStateService.Flush(session.uid)
            end
        end,
        error = function(_, reason)
            session.flushPending = false
            session.flushFailed = true
            if writeEconomy then session.dirtyEconomy = true end
            if writeFarm then session.dirtyFarm = true end
            if writeSocial then session.dirtySocial = true end
            print(string.format("[PlayerState] flush uid=%s failed reason=%s", tostring(session.uid), tostring(reason)))
            Callback(callback, false, reason)
        end,
    })
end

function PlayerStateService.FlushAll(callback)
    local keys = {}
    for key, session in pairs(sessions_) do
        if session ~= nil and (session.dirtyEconomy == true or session.dirtyFarm == true or session.dirtySocial == true) then
            keys[#keys + 1] = key
        end
    end
    if #keys <= 0 then
        Callback(callback, true)
        return
    end
    local pending = #keys
    local allOk = true
    for _, key in ipairs(keys) do
        PlayerStateService.Flush(sessions_[key].uid, function(ok)
            if ok ~= true then allOk = false end
            pending = pending - 1
            if pending <= 0 then Callback(callback, allOk) end
        end)
    end
end

function PlayerStateService.Update(dt)
    updateAccum_ = updateAccum_ + (tonumber(dt or 0) or 0)
    if updateAccum_ < 1.0 then return end
    updateAccum_ = 0
    local now = Now()
    for _, session in pairs(sessions_) do
        if session ~= nil
            and session.flushPending ~= true
            and (session.dirtyEconomy == true or session.dirtyFarm == true or session.dirtySocial == true)
            and now - (session.lastFlushAt or 0) >= FLUSH_INTERVAL then
            PlayerStateService.Flush(session.uid)
        end
    end
end

return PlayerStateService
