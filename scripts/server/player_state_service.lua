-- ============================================================================
-- 服务端玩家会话状态服务
-- Grow A Garden
-- ============================================================================
-- 运行时以内存 session 作为玩家经济/农场状态唯一权威；云端只用于登录加载和后台持久化。
-- 成功 mutate 后必须等待 flush 完成再回调客户端，避免关游戏时最新改动未写入云端。
-- mutator 失败或 flush 失败时回滚到变更前快照，保证内存与云端一致。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")
local ServerUtils = require("server.server_utils")
local ServerEconomyState = require("server.server_economy_state")

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
            mutateGeneration = 0,
            lastFlushAt = 0,
            flushPending = false,
            flushQueued = false,
            flushFailed = false,
            flushWaiters = {},
            revision = 0,
        }
        sessions_[key] = session
    end
    if session.mutateGeneration == nil then session.mutateGeneration = 0 end
    if session.flushWaiters == nil then session.flushWaiters = {} end
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

local function NotifyFlushWaiters(session, ok, reason)
    local waiters = session.flushWaiters or {}
    session.flushWaiters = {}
    for _, waiter in ipairs(waiters) do
        Callback(waiter, ok, reason)
    end
end

local function IsDirty(session)
    return session.dirtyEconomy == true or session.dirtyFarm == true or session.dirtySocial == true
end

--- 变更前快照：mutator/flush 失败时回滚，保证内存与云端一致
local function SnapshotSession(session)
    return {
        economy = ServerUtils.DeepCopy(session.economy),
        farm = ServerUtils.DeepCopy(session.farm),
        dirtyEconomy = session.dirtyEconomy == true,
        dirtyFarm = session.dirtyFarm == true,
        dirtySocial = session.dirtySocial == true,
        mutateGeneration = session.mutateGeneration or 0,
        revision = session.revision or 0,
    }
end

local function RestoreSession(session, snap)
    session.economy = snap.economy
    session.farm = snap.farm
    session.dirtyEconomy = snap.dirtyEconomy
    session.dirtyFarm = snap.dirtyFarm
    session.dirtySocial = snap.dirtySocial
    session.mutateGeneration = snap.mutateGeneration
    session.revision = snap.revision
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

    -- 登录归一已把 best 写到 canonical；此处只读 canonical，与 BatchScoreSet 一致
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

    local function FinishEconomyAndLoadFarm(economy, economyKey, economyMeta)
        economy = ServerCloudStore.StampOwner(NormalizeEconomy(economy), uidKey)
        EnsureEconomyRevision(economy)
        if economyMeta ~= nil and economyMeta.legacyRescued == true then
            session.dirtyEconomy = true
            session.mutateGeneration = (session.mutateGeneration or 0) + 1
        end

        local ledgerOpts = {
            requireOwner = true,
            canonicalOnly = true,
            logLabel = "玩家会话经济账本",
        }
        ServerCloudStore.ReadPlayerScore(uidKey, deps_.Shared.KEYS.ECONOMY_LEDGER, ledgerOpts, function(ledger, ledgerKey, ledgerErr)
            -- ledger 读失败不阻断：完整经济档仍可用
            if type(ledger) == "table" and ledgerErr ~= true then
                local beforeRev = tonumber(economy.revision or 0) or 0
                local merged, didApply = ServerEconomyState.ApplyEconomyLedger(economy, ledger)
                economy = merged
                if didApply == true then
                    session.dirtyEconomy = true
                    session.mutateGeneration = (session.mutateGeneration or 0) + 1
                    print(string.format(
                        "[PlayerState] ledger repair uid=%s fullRev=%s ledgerRev=%s ledgerKey=%s carrotSeeds=%s",
                        tostring(uidKey),
                        tostring(beforeRev),
                        tostring(economy.revision),
                        tostring(ledgerKey),
                        tostring(tonumber(economy.seedBag and economy.seedBag[1] or 0) or 0)
                    ))
                end
            end

            ServerCloudStore.ReadPlayerScore(uidKey, deps_.Shared.KEYS.AUTH_FARM_STATE, farmOpts, function(farm, farmKey, farmErr, farmMeta)
                if type(farm) ~= "table" then
                    if farmErr == true then
                        FinishLoad(session, "FARM_LOAD_FAILED")
                        return
                    end
                    farm = NormalizeFarm(nil)
                    session.dirtyFarm = true
                    session.mutateGeneration = (session.mutateGeneration or 0) + 1
                end
                farm = ServerCloudStore.StampOwner(NormalizeFarm(farm), uidKey)
                EnsureFarmRevision(farm)
                if farmMeta ~= nil and farmMeta.legacyRescued == true then
                    session.dirtyFarm = true
                    session.mutateGeneration = (session.mutateGeneration or 0) + 1
                end

                -- 农场镜像优先于完整经济档（农场写入更可靠）
                if type(farm.economyMirror) == "table" then
                    local beforeRev = tonumber(economy.revision or 0) or 0
                    local merged, didApply = ServerEconomyState.ApplyEconomyLedger(economy, farm.economyMirror)
                    economy = merged
                    if didApply == true then
                        session.dirtyEconomy = true
                        session.mutateGeneration = (session.mutateGeneration or 0) + 1
                        print(string.format(
                            "[PlayerState] farm-mirror repair uid=%s fullRev=%s mirrorRev=%s carrotSeeds=%s",
                            tostring(uidKey),
                            tostring(beforeRev),
                            tostring(economy.revision),
                            tostring(tonumber(economy.seedBag and economy.seedBag[1] or 0) or 0)
                        ))
                    end
                end

                session.economy = economy
                session.farm = farm
                session.economyLoaded = true
                session.farmLoaded = true
                session.revision = math.max(tonumber(economy.revision or 0) or 0, tonumber(farm.revision or 0) or 0)
                local pairedFarm = tonumber(economy.pairedFarmRevision)
                local pairedEco = tonumber(farm.pairedEconomyRevision)
                local seedCarrot = tonumber(economy.seedBag and economy.seedBag[1] or 0) or 0
                print(string.format(
                    "[PlayerState] load ok uid=%s economyKey=%s farmKey=%s economyRevision=%s farmRevision=%s gold=%s carrotSeeds=%s pairedFarm=%s pairedEco=%s",
                    tostring(uidKey),
                    tostring(economyKey),
                    tostring(farmKey),
                    tostring(economy.revision),
                    tostring(farm.revision),
                    tostring(economy.gold),
                    tostring(seedCarrot),
                    tostring(pairedFarm),
                    tostring(pairedEco)
                ))
                if (pairedFarm ~= nil and pairedFarm ~= tonumber(farm.revision))
                    or (pairedEco ~= nil and pairedEco ~= tonumber(economy.revision)) then
                    print(string.format(
                        "[PlayerState] load pair mismatch uid=%s ecoRev=%s farmRev=%s pairedFarm=%s pairedEco=%s",
                        tostring(uidKey),
                        tostring(economy.revision),
                        tostring(farm.revision),
                        tostring(pairedFarm),
                        tostring(pairedEco)
                    ))
                    -- 农场已前进但经济仍落后：强制写回（含 ledger），避免继续用陈旧种子袋
                    if pairedEco ~= nil and pairedEco > (tonumber(economy.revision) or 0) then
                        session.dirtyEconomy = true
                        session.mutateGeneration = (session.mutateGeneration or 0) + 1
                    end
                end
                FinishLoad(session, nil)
                if IsDirty(session) then
                    PlayerStateService.Flush(session.uid)
                end
            end)
        end)
    end

    ServerCloudStore.ReadPlayerScore(uidKey, deps_.Shared.KEYS.ECONOMY_STATE, economyOpts, function(economy, economyKey, economyErr, economyMeta)
        if type(economy) ~= "table" then
            if economyErr == true then
                FinishLoad(session, "ECONOMY_LOAD_FAILED")
                return
            end
            economy = BuildInitialEconomy()
            session.dirtyEconomy = true
            session.mutateGeneration = (session.mutateGeneration or 0) + 1
        end
        FinishEconomyAndLoadFarm(economy, economyKey, economyMeta)
    end)
end

local function ProcessQueue(session)
    if session.processing == true then return end
    local item = table.remove(session.queue, 1)
    if item == nil then return end
    session.processing = true

    local snap = SnapshotSession(session)
    local ok, result = pcall(function()
        if item.kind == "economy" then
            return item.mutator(session.economy, session)
        end
        if item.kind == "farm" then
            return item.mutator(session.farm, session)
        end
        return item.mutator(session.economy, session.farm, session)
    end)
    if ok ~= true then
        RestoreSession(session, snap)
        result = { success = false, message = tostring(result), code = "MUTATOR_ERROR" }
    end
    result = type(result) == "table" and result or { success = false, message = "操作失败" }

    if result.success ~= true then
        RestoreSession(session, snap)
        session.processing = false
        Callback(item.callback, result, session)
        ProcessQueue(session)
        return
    end

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
    if item.kind == "farm" or item.kind == "economy_farm" then
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
    session.mutateGeneration = (session.mutateGeneration or 0) + 1
    -- 联合变更时写入配对 revision，便于发现经济/农场被拆档覆盖
    if item.kind == "economy_farm" then
        session.economy.pairedFarmRevision = session.farm.revision
        session.farm.pairedEconomyRevision = session.economy.revision
    elseif item.kind == "economy" and type(session.farm) == "table" then
        session.economy.pairedFarmRevision = session.farm.revision
    elseif item.kind == "farm" and type(session.economy) == "table" then
        session.farm.pairedEconomyRevision = session.economy.revision
    end
    -- 经济变更时把种子袋镜像挂到农场（农场写入稳定，用于经济档不落盘时恢复）
    if (item.kind == "economy" or item.kind == "economy_farm") and type(session.farm) == "table" and type(session.economy) == "table" then
        ServerEconomyState.AttachEconomyMirrorToFarm(session.farm, session.economy)
        session.dirtyFarm = true
    end
    session.lastFlushAt = 0
    print(string.format(
        "[PlayerState] mutate uid=%s action=%s economyRevision=%s farmRevision=%s gen=%s",
        tostring(session.uid),
        tostring(item.actionName),
        tostring(session.economy and session.economy.revision),
        tostring(session.farm and session.farm.revision),
        tostring(session.mutateGeneration)
    ))

    -- 成功 mutate 后必须等 flush 完成再回调，避免客户端先收到成功但云端未落盘
    PlayerStateService.Flush(session.uid, function(flushOk, flushReason)
        if flushOk ~= true then
            RestoreSession(session, snap)
            result = {
                success = false,
                message = "保存失败，请重试",
                code = "FLUSH_FAILED",
                retryable = true,
                flushReason = flushReason,
            }
            print(string.format(
                "[PlayerState] mutate flush failed uid=%s action=%s reason=%s (rolled back)",
                tostring(session.uid),
                tostring(item.actionName),
                tostring(flushReason)
            ))
        else
            print(string.format(
                "[PlayerState] mutate flush ok uid=%s action=%s gen=%s",
                tostring(session.uid),
                tostring(item.actionName),
                tostring(session.mutateGeneration)
            ))
        end
        session.processing = false
        Callback(item.callback, result, session)
        ProcessQueue(session)
    end)
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

function PlayerStateService.MutateFarm(uid, actionName, mutator, callback)
    EnqueueMutation(uid, "farm", actionName, mutator, callback)
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
    session.mutateGeneration = (session.mutateGeneration or 0) + 1
    session.flushWaiters = {}
    session.revision = session.revision + 1
    print(string.format("[PlayerState] reset uid=%s economyRevision=%s farmRevision=%s", tostring(session.uid), tostring(session.economy.revision), tostring(session.farm.revision)))
    return session
end

function PlayerStateService.Clear(uid)
    local session = sessions_[tostring(CanonicalUid(uid))]
    if session ~= nil then
        NotifyFlushWaiters(session, false, "SESSION_CLEARED")
    end
    sessions_[tostring(CanonicalUid(uid))] = nil
end

function PlayerStateService.Flush(uid, callback)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then
        Callback(callback, false, "NO_SESSION")
        return
    end
    if session.flushPending == true then
        if callback ~= nil then
            session.flushWaiters[#session.flushWaiters + 1] = callback
        end
        session.flushQueued = true
        return
    end

    local writeEconomy = session.dirtyEconomy == true and type(session.economy) == "table"
    local writeFarm = session.dirtyFarm == true and type(session.farm) == "table"
    local writeSocial = session.dirtySocial == true and type(session.social) == "table"
    if writeEconomy and type(session.farm) == "table" then
        ServerEconomyState.AttachEconomyMirrorToFarm(session.farm, session.economy)
        writeFarm = true
    end
    if not writeEconomy and not writeFarm and not writeSocial then
        session.flushQueued = false
        Callback(callback, true)
        NotifyFlushWaiters(session, true)
        return
    end

    local flushGeneration = session.mutateGeneration or 0
    local economyRevision = tonumber(session.economy and session.economy.revision or 0) or 0
    local farmRevision = tonumber(session.farm and session.farm.revision or 0) or 0
    session.flushPending = true
    session.flushQueued = false
    print(string.format(
        "[PlayerState] flush begin uid=%s economyRevision=%s farmRevision=%s gen=%s writeE=%s writeF=%s",
        tostring(session.uid),
        tostring(economyRevision),
        tostring(farmRevision),
        tostring(flushGeneration),
        tostring(writeEconomy),
        tostring(writeFarm)
    ))
    local c = serverCloud:BatchCommit("保存玩家会话状态")
    if writeEconomy then
        ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.ECONOMY_STATE, session.economy)
        local ledger = ServerEconomyState.BuildEconomyLedger(session.economy)
        if type(ledger) == "table" then
            ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.ECONOMY_LEDGER, ledger)
        end
    end
    if writeFarm then ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.AUTH_FARM_STATE, session.farm) end
    if writeSocial then ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.SOCIAL_SAVE, session.social) end
    c:Commit({
        ok = function()
            session.flushPending = false
            session.flushFailed = false
            session.lastFlushAt = Now()
            if (session.mutateGeneration or 0) == flushGeneration then
                if writeEconomy then session.dirtyEconomy = false end
                if writeFarm then session.dirtyFarm = false end
                if writeSocial then session.dirtySocial = false end
            else
                print(string.format(
                    "[PlayerState] flush uid=%s keep dirty (gen %s -> %s)",
                    tostring(session.uid),
                    tostring(flushGeneration),
                    tostring(session.mutateGeneration)
                ))
            end
            print(string.format(
                "[PlayerState] flush uid=%s ok economyRevision=%s farmRevision=%s gen=%s",
                tostring(session.uid),
                tostring(economyRevision),
                tostring(farmRevision),
                tostring(flushGeneration)
            ))
            local function AfterVerify()
                Callback(callback, true)
                NotifyFlushWaiters(session, true)
                if session.flushQueued == true or IsDirty(session) then
                    session.flushQueued = false
                    session.lastFlushAt = 0
                    PlayerStateService.Flush(session.uid)
                end
            end
            -- 写后读 ledger：完整经济档偶发不落盘时，至少确认账本 revision
            local retryCount = session.flushRetryCount or 0
            if writeEconomy and economyRevision > 0 and retryCount < 2 then
                ServerCloudStore.ReadPlayerScore(session.uid, deps_.Shared.KEYS.ECONOMY_LEDGER, {
                    requireOwner = true,
                    canonicalOnly = true,
                    logLabel = "flush校验账本",
                }, function(ledger, ledgerKey, ledgerErr)
                    if ledgerErr == true then
                        AfterVerify()
                        return
                    end
                    local ledgerRev = type(ledger) == "table" and (tonumber(ledger.revision or 0) or 0) or 0
                    if ledgerRev >= economyRevision then
                        session.flushRetryCount = 0
                        AfterVerify()
                        return
                    end
                    print(string.format(
                        "[PlayerState] flush verify lag uid=%s expectEco=%s ledgerRev=%s key=%s — reflush",
                        tostring(session.uid),
                        tostring(economyRevision),
                        tostring(ledgerRev),
                        tostring(ledgerKey)
                    ))
                    session.dirtyEconomy = true
                    session.mutateGeneration = (session.mutateGeneration or 0) + 1
                    session.flushRetryCount = retryCount + 1
                    AfterVerify()
                end)
                return
            end
            if writeEconomy and retryCount >= 2 then
                print(string.format(
                    "[PlayerState] flush verify give up uid=%s expect=%s",
                    tostring(session.uid),
                    tostring(economyRevision)
                ))
            end
            session.flushRetryCount = 0
            AfterVerify()
        end,
        error = function(_, reason)
            session.flushPending = false
            session.flushFailed = true
            if writeEconomy then session.dirtyEconomy = true end
            if writeFarm then session.dirtyFarm = true end
            if writeSocial then session.dirtySocial = true end
            print(string.format("[PlayerState] flush uid=%s failed reason=%s", tostring(session.uid), tostring(reason)))
            Callback(callback, false, reason)
            NotifyFlushWaiters(session, false, reason)
        end,
    })
end

function PlayerStateService.FlushAll(callback)
    local keys = {}
    for key, session in pairs(sessions_) do
        if session ~= nil and IsDirty(session) then
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
            and IsDirty(session)
            and now - (session.lastFlushAt or 0) >= FLUSH_INTERVAL then
            PlayerStateService.Flush(session.uid)
        end
    end
end

return PlayerStateService
