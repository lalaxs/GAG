-- ============================================================================
-- 服务端玩家会话状态服务
-- Grow A Garden
-- ============================================================================
-- 运行时以内存 session 作为玩家经济/农场唯一权威；云端只用于登录加载和持久化。
-- 云端权威：garden_player_state_v1（统一档）。
-- Load：优先读统一档；没有则读旧拆分档合成 → 标记 dirty → Flush 落统一档（一次性迁移）。
-- Flush：只写统一档（+ 社交独立 key），不再写拆分 key。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")
local ServerUtils = require("server.server_utils")
local PlayerStateCodec = require("network.player_state_codec")

local PlayerStateService = {}

local deps_ = {}
local sessions_ = {}

local FLUSH_INTERVAL = 1.0
local RESPONSE_FIRST_FLUSH_DELAY_SEC = 3
local DIRTY_FORCE_FLUSH_SEC = 10
local FLUSH_RETRY_DELAY_SEC = 5
local FLUSH_TIMEOUT_SEC = 10
-- 云读偶发不回调；先废弃悬挂 token 并重启一次完整 Load，再向上层返回失败。
local LOAD_TIMEOUT_SEC = 10
local MAX_LOAD_RETRIES = 1
local updateAccum_ = 0
local nextLoadToken_ = 1

local function GetPlayerSaveAssemble()
    return require("server.player_save_assemble")
end

local function Now()
    if deps_.Now ~= nil then return deps_.Now() end
    return os and os.time and os.time() or 0
end

local function CanonicalUid(uid)
    return ServerCloudStore.GetCanonicalUidKey(uid)
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
    if canonicalUid == nil then
        return nil
    end
    local key = tostring(canonicalUid)
    local session = sessions_[key]
    if session == nil then
        session = {
            uid = canonicalUid,
            economy = nil,
            farm = nil,
            social = nil,
            profile = nil,
            economyLoaded = false,
            farmLoaded = false,
            loading = false,
            loadCallbacks = {},
            loadRetryCount = 0,
            queue = {},
            processing = false,
            dirtyEconomy = false,
            dirtyFarm = false,
            dirtySocial = false,
            dirtyProfile = false,
            mutateGeneration = 0,
            lastFlushAt = 0,
            flushPending = false,
            flushQueued = false,
            flushFailed = false,
            flushWaiters = {},
            activeFlushCallback = nil,
            revision = 0,
            flushStartedAt = 0,
            flushToken = 0,
            dirtySince = 0,
            flushDueAt = 0,
            flushReason = nil,
        }
        sessions_[key] = session
    end
    if session.mutateGeneration == nil then session.mutateGeneration = 0 end
    if session.flushWaiters == nil then session.flushWaiters = {} end
    if session.loadToken == nil then session.loadToken = 0 end
    if session.loadStartedAt == nil then session.loadStartedAt = 0 end
    return session
end

local function FinishLoad(session, err)
    session.loading = false
    session.loadToken = 0
    session.loadStartedAt = 0
    session.loadRetryCount = 0
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
    return session.dirtyEconomy == true
        or session.dirtyFarm == true
        or session.dirtySocial == true
        or session.dirtyProfile == true
end

local function MarkSessionDirtyForFlush(session, delay, reason)
    if session == nil then return end
    local now = Now()
    if session.dirtySince == nil or session.dirtySince <= 0 then
        session.dirtySince = now
    end
    local flushDelay = math.max(0, tonumber(delay or 0) or 0)
    local dueAt = now + flushDelay
    if session.flushDueAt == nil or session.flushDueAt <= 0 then
        session.flushDueAt = dueAt
    else
        session.flushDueAt = math.min(session.flushDueAt, dueAt)
    end
    session.flushReason = reason or session.flushReason
end

local function ClearDirtyFlushSchedule(session)
    if session == nil then return end
    session.dirtySince = 0
    session.flushDueAt = 0
    session.flushReason = nil
end

local function ScheduleFlushRetry(session, reason)
    if session == nil then return end
    local now = Now()
    if session.dirtySince == nil or session.dirtySince <= 0 then
        session.dirtySince = now
    end
    session.flushDueAt = now + FLUSH_RETRY_DELAY_SEC
    session.flushReason = reason or "retry"
end

--- 变更前快照：mutator/flush 失败时回滚，保证内存与云端一致
local function SnapshotSession(session)
    return {
        economy = ServerUtils.DeepCopy(session.economy),
        farm = ServerUtils.DeepCopy(session.farm),
        profile = ServerUtils.DeepCopy(session.profile),
        dirtyEconomy = session.dirtyEconomy == true,
        dirtyFarm = session.dirtyFarm == true,
        dirtySocial = session.dirtySocial == true,
        dirtyProfile = session.dirtyProfile == true,
        mutateGeneration = session.mutateGeneration or 0,
        revision = session.revision or 0,
    }
end

local function RestoreSession(session, snap)
    session.economy = snap.economy
    session.farm = snap.farm
    session.profile = snap.profile
    session.dirtyEconomy = snap.dirtyEconomy
    session.dirtyFarm = snap.dirtyFarm
    session.dirtySocial = snap.dirtySocial
    session.dirtyProfile = snap.dirtyProfile
    session.mutateGeneration = snap.mutateGeneration
    session.revision = snap.revision
end

function PlayerStateService.Init(deps)
    deps_ = deps or {}
end

function PlayerStateService.GetSession(uid)
    local canonicalUid = CanonicalUid(uid)
    if canonicalUid == nil then return nil end
    local session = sessions_[tostring(canonicalUid)]
    if session == nil or session.economyLoaded ~= true or session.farmLoaded ~= true then return nil end
    return session
end

function PlayerStateService.HasLoadedSession(uid)
    return PlayerStateService.GetSession(uid) ~= nil
end

--- 供客户端上报：本次 Load 来源与统一档写盘结果
function PlayerStateService.GetSaveLoadReport(uid)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then
        return {
            saveSource = "unknown",
            saveMigrated = false,
            saveWriteOk = false,
        }
    end
    local source = session.loadSource or "unknown"
    local profile = PlayerStateService.GetProfile(uid)
    return {
        saveSource = source,
        saveMigrated = source == "migrate_split" or source == "legacy_rescue_split" or source == "legacy_rescue_unified",
        saveWriteOk = session.saveWriteOk ~= false,
        saveWriteReason = session.saveWriteReason,
        profile = profile,
    }
end

function PlayerStateService.GetProfile(uid)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then return nil end
    local profile = type(session.profile) == "table" and ServerUtils.DeepCopy(session.profile) or {}
    profile.tapNickname = profile.tapNickname or "Tap玩家"
    profile.customNickname = profile.customNickname or ""
    profile.avatar = type(profile.avatar) == "table" and profile.avatar or nil
    return profile
end

function PlayerStateService.SetProfile(uid, profile, callback)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then
        Callback(callback, false, "NO_SESSION")
        return
    end
    profile = type(profile) == "table" and ServerUtils.DeepCopy(profile) or {}
    session.profile = profile
    session.dirtyProfile = true
    session.mutateGeneration = (session.mutateGeneration or 0) + 1
    session.lastFlushAt = 0
    MarkSessionDirtyForFlush(session, 0, "profile_update")
    PlayerStateService.Flush(uid, callback)
end

function PlayerStateService.MarkProfileDirty(uid)
    local session = PlayerStateService.GetSession(uid)
    if session == nil then return false end
    session.dirtyProfile = true
    session.mutateGeneration = (session.mutateGeneration or 0) + 1
    MarkSessionDirtyForFlush(session, RESPONSE_FIRST_FLUSH_DELAY_SEC, "profile_update")
    return true
end

function PlayerStateService.Load(uid, callback)
    local session = GetOrCreateSession(uid)
    if session == nil then
        print("[PlayerState] load rejected: invalid uid=" .. tostring(uid))
        Callback(callback, nil, "NO_UID")
        return
    end
    if session.economyLoaded == true and session.farmLoaded == true then
        Callback(callback, session, nil)
        return
    end

    local sharedKeys = deps_.Shared and deps_.Shared.KEYS
    if sharedKeys == nil or sharedKeys.PLAYER_STATE == nil then
        print("[PlayerState] load aborted: Shared.KEYS.PLAYER_STATE not ready")
        Callback(callback, nil, "SHARED_KEYS_MISSING")
        return
    end

    session.loadCallbacks[#session.loadCallbacks + 1] = callback
    if session.loading == true then return end
    session.loading = true
    session.loadStartedAt = Now()
    local loadToken = nextLoadToken_
    nextLoadToken_ = nextLoadToken_ + 1
    session.loadToken = loadToken

    local uidKey = session.uid
    print(string.format(
        "[PlayerState] load begin uid=%s token=%s cachedEconomy=%s cachedFarm=%s callbacks=%s",
        tostring(uidKey),
        tostring(loadToken),
        tostring(session.economyLoaded == true),
        tostring(session.farmLoaded == true),
        tostring(#session.loadCallbacks)
    ))

    local function isCurrentLoad()
        return session.loadToken == loadToken
    end

    local function countPlants(farm)
        if type(farm) ~= "table" or type(farm.plots) ~= "table" then return 0 end
        local n = 0
        for _, plot in pairs(farm.plots) do
            if type(plot) == "table" and type(plot.plants) == "table" then
                n = n + #plot.plants
            end
        end
        return n
    end

    ---@param unifiedRevision number|nil
    local function applyAndFinish(economy, farm, source, markDirty, unifiedRevision)
        if not isCurrentLoad() then return end
        economy = ServerCloudStore.StampOwner(NormalizeEconomy(economy), uidKey)
        farm = ServerCloudStore.StampOwner(NormalizeFarm(farm), uidKey)
        EnsureEconomyRevision(economy)
        EnsureFarmRevision(farm)
        session.economy = economy
        session.farm = farm
        session.economyLoaded = true
        session.farmLoaded = true
        session.revision = math.max(
            tonumber(unifiedRevision or 0) or 0,
            tonumber(economy.revision or 0) or 0,
            tonumber(farm.revision or 0) or 0
        )
        if markDirty == true then
            session.dirtyEconomy = true
            session.dirtyFarm = true
            session.mutateGeneration = (session.mutateGeneration or 0) + 1
        end
        print(string.format(
            "[PlayerState] load ok uid=%s token=%s source=%s sessionRevision=%s economyRevision=%s farmRevision=%s gold=%s level=%s plants=%s dirty=%s",
            tostring(uidKey),
            tostring(loadToken),
            tostring(source),
            tostring(session.revision),
            tostring(economy.revision),
            tostring(farm.revision),
            tostring(economy.gold),
            tostring(economy.talent and economy.talent.level),
            tostring(countPlants(farm)),
            tostring(markDirty == true)
        ))
        session.loadSource = source
        -- 迁移/新号：首包优先返回，统一档落盘后台执行；避免云写入不回调导致 FullSync 卡在 loading。
        if IsDirty(session) then
            session.saveWriteOk = nil
            session.saveWriteReason = "PENDING_BACKGROUND_FLUSH"
            FinishLoad(session, nil)
            PlayerStateService.Flush(session.uid, function(ok, reason)
                session.saveWriteOk = ok == true
                session.saveWriteReason = reason
                print(string.format(
                    "[PlayerState] migrate background flush uid=%s token=%s ok=%s reason=%s source=%s",
                    tostring(uidKey),
                    tostring(loadToken),
                    tostring(ok == true),
                    tostring(reason),
                    tostring(source)
                ))
            end)
            return
        end
        session.saveWriteOk = true
        session.saveWriteReason = nil
        FinishLoad(session, nil)
    end

    local function scoreEconomyRecord(state)
        if deps_.ScoreEconomyRecord ~= nil then return deps_.ScoreEconomyRecord(state) end
        if deps_.ScoreEconomyContent ~= nil then return deps_.ScoreEconomyContent(state) end
        return math.max(0, tonumber(state and state.revision or 0) or 0)
    end

    local function scoreFarmState(state)
        if deps_.ScoreFarmState ~= nil then return deps_.ScoreFarmState(state) end
        return math.max(0, tonumber(state and state.revision or 0) or 0) * 1000 + countPlants(state) * 100
    end

    local function economyLooksFresh(state)
        if type(state) ~= "table" then return true end
        if deps_.ScoreEconomyContent ~= nil then
            local initial = BuildInitialEconomy()
            return deps_.ScoreEconomyContent(state) <= deps_.ScoreEconomyContent(initial) + 50
        end
        return math.max(0, tonumber(state.revision or 0) or 0) <= 0
    end

    local function farmLooksEmpty(state)
        if deps_.FarmLooksEmpty ~= nil then return deps_.FarmLooksEmpty(state) == true end
        return countPlants(state) <= 0 and math.max(0, tonumber(state and state.revision or 0) or 0) <= 0
    end

    local function unifiedLooksFresh(doc)
        local Assemble = GetPlayerSaveAssemble()
        if not Assemble.IsUnifiedDoc(doc) then return true end
        if doc.cleared == true then return false end
        local economy, farm = Assemble.SplitViews(doc)
        return economyLooksFresh(economy) and farmLooksEmpty(farm)
    end

    local function scoreUnifiedDoc(doc)
        local Assemble = GetPlayerSaveAssemble()
        if not Assemble.IsUnifiedDoc(doc) then return -1 end
        local economy, farm = Assemble.SplitViews(doc)
        return math.max(0, tonumber(doc.revision or 0) or 0) * 100000
            + scoreEconomyRecord(economy)
            + scoreFarmState(farm)
    end

    local function checkClearedMarker(onCleared, onContinue)
        local markerKey = sharedKeys.SAVE_UID_RECONCILED
        if markerKey == nil then
            onContinue()
            return
        end
        ServerCloudStore.Get(uidKey, markerKey, {
            ok = function(scores)
                if not isCurrentLoad() then return end
                local marker = scores and scores[markerKey]
                if type(marker) == "table" and marker.cleared == true then
                    print(string.format("[PlayerState] legacy rescue blocked by cleared marker uid=%s", tostring(uidKey)))
                    onCleared()
                    return
                end
                onContinue()
            end,
            error = function()
                if not isCurrentLoad() then return end
                onContinue()
            end,
        })
    end

    local function applyUnifiedDoc(doc, source, markDirty)
        local Assemble = GetPlayerSaveAssemble()
        session.profile = type(doc.profile) == "table" and ServerUtils.DeepCopy(doc.profile) or nil
        local economy, farm, rev = Assemble.SplitViews(doc)
        local migrateCodec = Assemble.NeedsCompaction(doc)
        if migrateCodec then
            print(string.format(
                "[PlayerState] compact migration scheduled uid=%s source=%s oldCodec=%s newCodec=%s",
                tostring(uidKey),
                tostring(source),
                tostring(doc and doc.codecVersion),
                tostring(PlayerStateCodec.VERSION)
            ))
        end
        applyAndFinish(economy, farm, source, markDirty == true or migrateCodec, rev)
    end

    --- 无统一档：读旧拆分 → 组装 → 标记 dirty 落盘为统一档（老玩家一次性迁移）
    local function migrateFromSplit(allowLegacyRescue, source)
        if sharedKeys.ECONOMY_STATE == nil or sharedKeys.AUTH_FARM_STATE == nil then
            applyAndFinish(BuildInitialEconomy(), NormalizeFarm(nil), "new_player", true, nil)
            return
        end

        local economyOpts = {
            normalize = NormalizeEconomy,
            requireOwner = true,
            canonicalOnly = allowLegacyRescue ~= true,
            logLabel = allowLegacyRescue == true and "救援读经济" or "迁移读经济",
        }
        local farmOpts = {
            normalize = NormalizeFarm,
            requireOwner = true,
            canonicalOnly = allowLegacyRescue ~= true,
            logLabel = allowLegacyRescue == true and "救援读农场" or "迁移读农场",
        }
        if allowLegacyRescue == true then
            economyOpts.score = scoreEconomyRecord
            economyOpts.compareScore = scoreEconomyRecord
            economyOpts.allowLegacyRescue = true
            economyOpts.shouldLegacyRescue = economyLooksFresh
            farmOpts.score = scoreFarmState
            farmOpts.compareScore = scoreFarmState
            farmOpts.allowLegacyRescue = true
            farmOpts.shouldLegacyRescue = farmLooksEmpty
        end

        print(string.format(
            "[PlayerState] no usable unified, migrate from split uid=%s rescue=%s",
            tostring(uidKey),
            tostring(allowLegacyRescue == true)
        ))
        ServerCloudStore.ReadPlayerScore(uidKey, sharedKeys.ECONOMY_STATE, economyOpts, function(economy, _, economyErr, economyMeta)
            if not isCurrentLoad() then return end
            if economyErr == true and type(economy) ~= "table" then
                if allowLegacyRescue ~= true then
                    checkClearedMarker(function()
                        applyAndFinish(BuildInitialEconomy(), NormalizeFarm(nil), "cleared_marker_new_player", true, nil)
                    end, function()
                        migrateFromSplit(true, "legacy_rescue_split")
                    end)
                else
                    FinishLoad(session, "ECONOMY_LOAD_FAILED")
                end
                return
            end
            if type(economy) ~= "table" then
                economy = BuildInitialEconomy()
            end
            if economyMeta ~= nil and economyMeta.legacyRescued == true then
                economy = ServerCloudStore.StampOwner(economy, uidKey)
            end

            ServerCloudStore.ReadPlayerScore(uidKey, sharedKeys.ECONOMY_LEDGER, {
                requireOwner = true,
                canonicalOnly = allowLegacyRescue ~= true,
                logLabel = allowLegacyRescue == true and "救援读账本" or "迁移读账本",
                allowLegacyRescue = allowLegacyRescue == true,
            }, function(ledger, _, ledgerErr, ledgerMeta)
                if not isCurrentLoad() then return end
                if ledgerErr == true then
                    -- 账本硬失败不阻断：用经济本体继续
                    ledger = nil
                end
                if ledgerMeta ~= nil and ledgerMeta.legacyRescued == true then
                    ledger = ServerCloudStore.StampOwner(ledger, uidKey)
                end

                ServerCloudStore.ReadPlayerScore(uidKey, sharedKeys.AUTH_FARM_STATE, farmOpts, function(farm, _, farmErr, farmMeta)
                    if not isCurrentLoad() then return end
                    if farmErr == true and type(farm) ~= "table" then
                        if allowLegacyRescue ~= true then
                            checkClearedMarker(function()
                                applyAndFinish(BuildInitialEconomy(), NormalizeFarm(nil), "cleared_marker_new_player", true, nil)
                            end, function()
                                migrateFromSplit(true, "legacy_rescue_split")
                            end)
                        else
                            FinishLoad(session, "FARM_LOAD_FAILED")
                        end
                        return
                    end
                    if type(farm) ~= "table" then
                        farm = NormalizeFarm(nil)
                    end
                    if farmMeta ~= nil and farmMeta.legacyRescued == true then
                        farm = ServerCloudStore.StampOwner(farm, uidKey)
                    end

                    local Assemble = GetPlayerSaveAssemble()
                    local docAssembled, meta = Assemble.AssembleFromSplit(economy, farm, ledger, { now = Now() })
                    session.profile = type(docAssembled.profile) == "table" and ServerUtils.DeepCopy(docAssembled.profile) or nil
                    local ecoView, farmView, unifiedRev = Assemble.SplitViews(docAssembled)
                    if meta ~= nil and meta.repairSuspect == true then
                        print(string.format("[PlayerState] migrate repairSuspect uid=%s", tostring(uidKey)))
                    end
                    local splitLooksFresh = economyLooksFresh(ecoView) and farmLooksEmpty(farmView)
                    local loadSource = splitLooksFresh and "new_player" or (source or "migrate_split")
                    if allowLegacyRescue ~= true and splitLooksFresh then
                        checkClearedMarker(function()
                            applyAndFinish(ecoView, farmView, loadSource, true, unifiedRev)
                        end, function()
                            migrateFromSplit(true, "legacy_rescue_split")
                        end)
                        return
                    end
                    -- 新号（拆分也空）与老号迁移：都落统一档
                    applyAndFinish(ecoView, farmView, loadSource, true, unifiedRev)
                end)
            end)
        end)
    end

    local function tryLegacyUnifiedThenSplit()
        ServerCloudStore.ReadPlayerScore(uidKey, sharedKeys.PLAYER_STATE, {
            requireOwner = true,
            normalize = function(value) return value end,
            score = scoreUnifiedDoc,
            compareScore = scoreUnifiedDoc,
            allowLegacyRescue = true,
            shouldLegacyRescue = unifiedLooksFresh,
            logLabel = "统一档legacy救援",
        }, function(rescuedDoc, _, rescueErr, meta)
            if not isCurrentLoad() then return end
            if rescueErr ~= true and GetPlayerSaveAssemble().IsUnifiedDoc(rescuedDoc) and unifiedLooksFresh(rescuedDoc) ~= true then
                if meta ~= nil and meta.legacyRescued == true then
                    rescuedDoc = ServerCloudStore.StampOwner(rescuedDoc, uidKey)
                end
                applyUnifiedDoc(rescuedDoc, "legacy_rescue_unified", true)
                return
            end
            migrateFromSplit(false, "migrate_split")
        end)
    end

    local function applySplitFromBatch(economy, farm, ledger, source)
        local Assemble = GetPlayerSaveAssemble()
        if type(economy) ~= "table" then economy = BuildInitialEconomy() end
        if type(farm) ~= "table" then farm = NormalizeFarm(nil) end
        local docAssembled, meta = Assemble.AssembleFromSplit(economy, farm, ledger, { now = Now() })
        session.profile = type(docAssembled.profile) == "table" and ServerUtils.DeepCopy(docAssembled.profile) or nil
        local ecoView, farmView, unifiedRev = Assemble.SplitViews(docAssembled)
        if meta ~= nil and meta.repairSuspect == true then
            print(string.format("[PlayerState] migrate repairSuspect uid=%s", tostring(uidKey)))
        end
        local splitLooksFresh = economyLooksFresh(ecoView) and farmLooksEmpty(farmView)
        local loadSource = splitLooksFresh and "new_player" or (source or "migrate_split")
        applyAndFinish(ecoView, farmView, loadSource, true, unifiedRev)
    end

    local function processCanonicalBatch(scores)
        scores = scores or {}
        local Assemble = GetPlayerSaveAssemble()
        local doc = scores[sharedKeys.PLAYER_STATE]
        local marker = scores[sharedKeys.SAVE_UID_RECONCILED]
        local markerCleared = type(marker) == "table" and marker.cleared == true

        if type(doc) == "table" and Assemble.IsUnifiedDoc(doc) then
            if ServerCloudStore.AcceptOwnedTable(uidKey, doc, { requireOwner = true }) ~= true then
                print(string.format("[PlayerState] BatchGet unified owner 拒绝 uid=%s → NEED_REOPEN", tostring(uidKey)))
                FinishLoad(session, "NEED_REOPEN:OWNER_MISMATCH")
                return
            end
            if doc.cleared == true or unifiedLooksFresh(doc) ~= true then
                applyUnifiedDoc(doc, "unified", false)
                return
            end
            print(string.format("[PlayerState] BatchGet unified looks fresh, try legacy rescue uid=%s", tostring(uidKey)))
        end

        if markerCleared then
            print(string.format("[PlayerState] BatchGet cleared marker uid=%s", tostring(uidKey)))
            if Assemble.IsUnifiedDoc(doc) and ServerCloudStore.AcceptOwnedTable(uidKey, doc, { requireOwner = true }) then
                applyUnifiedDoc(doc, "unified", false)
            else
                applyAndFinish(BuildInitialEconomy(), NormalizeFarm(nil), "cleared_marker_new_player", true, nil)
            end
            return
        end

        local economy = scores[sharedKeys.ECONOMY_STATE]
        local farm = scores[sharedKeys.AUTH_FARM_STATE]
        local ledger = scores[sharedKeys.ECONOMY_LEDGER]
        local ownedEconomy = type(economy) == "table"
            and ServerCloudStore.AcceptOwnedTable(uidKey, economy, { requireOwner = true }) == true
        local ownedFarm = type(farm) == "table"
            and ServerCloudStore.AcceptOwnedTable(uidKey, farm, { requireOwner = true }) == true
        if type(ledger) == "table"
            and ServerCloudStore.AcceptOwnedTable(uidKey, ledger, { requireOwner = true }) ~= true then
            ledger = nil
        end

        if ownedEconomy == true or ownedFarm == true then
            if ownedEconomy ~= true then economy = BuildInitialEconomy() end
            if ownedFarm ~= true then farm = NormalizeFarm(nil) end
            local ecoView, farmView = economy, farm
            local splitLooksFresh = economyLooksFresh(ecoView) and farmLooksEmpty(farmView)
            if splitLooksFresh then
                print(string.format("[PlayerState] BatchGet split looks fresh, try legacy rescue uid=%s", tostring(uidKey)))
                tryLegacyUnifiedThenSplit()
                return
            end
            print(string.format("[PlayerState] BatchGet migrate_split uid=%s", tostring(uidKey)))
            applySplitFromBatch(economy, farm, ledger, "migrate_split")
            return
        end

        -- canonical 无可用档：冷路径 legacy 扫一次，仍没有则新号
        tryLegacyUnifiedThenSplit()
    end

    -- 官方标准热路径：一次 BatchGet 拉齐登录 key
    local loginKeys = {
        sharedKeys.PLAYER_STATE,
        sharedKeys.ECONOMY_STATE,
        sharedKeys.AUTH_FARM_STATE,
        sharedKeys.ECONOMY_LEDGER,
        sharedKeys.SAVE_UID_RECONCILED,
    }
    local compactKeys = {}
    for i = 1, #loginKeys do
        if loginKeys[i] ~= nil then
            compactKeys[#compactKeys + 1] = loginKeys[i]
        end
    end
    ServerCloudStore.BatchGetLoginScores(uidKey, compactKeys, function(ok, scores, cloudUid, err)
        if not isCurrentLoad() then return end
        if ok ~= true then
            print(string.format(
                "[PlayerState] login BatchGet hard-fail uid=%s cloudUid=%s err=%s → LOAD_FAILED",
                tostring(uidKey),
                tostring(cloudUid),
                tostring(err)
            ))
            FinishLoad(session, "PLAYER_STATE_LOAD_FAILED")
            return
        end
        print(string.format(
            "[PlayerState] login BatchGet ok uid=%s cloudUid=%s keys=%d",
            tostring(uidKey),
            tostring(cloudUid),
            tostring(#compactKeys)
        ))
        processCanonicalBatch(scores)
    end)
end


local function IsResponseFirstAction(actionName)
    return actionName == "plant_seed"
        or actionName == "harvest_crop"
        or actionName == "sell"
        or actionName == "sell_harvested"
        or actionName == "open_seed_pack"
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
    session.lastFlushAt = 0
    if session.dirtySince == nil or session.dirtySince <= 0 then
        session.dirtySince = now
    end
    session.flushReason = item.actionName
    print(string.format(
        "[PlayerState] mutate uid=%s action=%s economyRevision=%s farmRevision=%s gen=%s",
        tostring(session.uid),
        tostring(item.actionName),
        tostring(session.economy and session.economy.revision),
        tostring(session.farm and session.farm.revision),
        tostring(session.mutateGeneration)
    ))

    if IsResponseFirstAction(item.actionName) then
        print(string.format(
            "[PlayerState] mutate response-first uid=%s action=%s gen=%s flushDelay=%ss",
            tostring(session.uid),
            tostring(item.actionName),
            tostring(session.mutateGeneration),
            tostring(RESPONSE_FIRST_FLUSH_DELAY_SEC)
        ))
        MarkSessionDirtyForFlush(session, RESPONSE_FIRST_FLUSH_DELAY_SEC, item.actionName)
        session.processing = false
        Callback(item.callback, result, session)
        ProcessQueue(session)
        return
    end

    -- 非即时玩法操作仍等待 flush 完成再回调，避免敏感资源先成功后落盘失败。
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
    if session == nil then
        print("[PlayerState] mark dirty rejected: invalid uid=" .. tostring(uid))
        return
    end
    if kind == "economy" then session.dirtyEconomy = true end
    if kind == "farm" then session.dirtyFarm = true end
    if kind == "social" then session.dirtySocial = true end
    if kind == "profile" then session.dirtyProfile = true end
end

function PlayerStateService.Reset(uid, economy, farm, social)
    local session = GetOrCreateSession(uid)
    if session == nil then
        print("[PlayerState] reset rejected: invalid uid=" .. tostring(uid))
        return nil
    end
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
    local canonicalUid = CanonicalUid(uid)
    if canonicalUid == nil then return end
    local session = sessions_[tostring(canonicalUid)]
    if session ~= nil then
        NotifyFlushWaiters(session, false, "SESSION_CLEARED")
    end
    sessions_[tostring(canonicalUid)] = nil
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

    local writeUnifiedPlayerState = (
        session.dirtyEconomy == true
            or session.dirtyFarm == true
            or session.dirtyProfile == true
    )
        and type(session.economy) == "table"
        and type(session.farm) == "table"
    local writeSocial = session.dirtySocial == true and type(session.social) == "table"
    if not writeUnifiedPlayerState and not writeSocial then
        session.flushQueued = false
        Callback(callback, true)
        NotifyFlushWaiters(session, true)
        return
    end

    local flushGeneration = session.mutateGeneration or 0
    local economyRevision = tonumber(session.economy and session.economy.revision or 0) or 0
    local farmRevision = tonumber(session.farm and session.farm.revision or 0) or 0
    session.flushPending = true
    session.flushStartedAt = Now()
    session.flushToken = (session.flushToken or 0) + 1
    local flushToken = session.flushToken
    session.activeFlushCallback = callback
    session.flushQueued = false
    print(string.format(
        "[PlayerState] flush begin uid=%s economyRevision=%s farmRevision=%s gen=%s writeUnified=%s writeSocial=%s",
        tostring(session.uid),
        tostring(economyRevision),
        tostring(farmRevision),
        tostring(flushGeneration),
        tostring(writeUnifiedPlayerState),
        tostring(writeSocial),
        tostring(session.dirtyProfile == true)
    ))
    local c = serverCloud:BatchCommit("保存玩家会话状态")
    if writeUnifiedPlayerState then
        local doc = GetPlayerSaveAssemble().BuildDoc(
            session.economy,
            session.farm,
            session.revision,
            session.uid
        )
        doc.profile = ServerUtils.DeepCopy(session.profile)
        ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.PLAYER_STATE, doc)
    end
    if writeSocial then
        ServerCloudStore.BatchScoreSet(c, session.uid, deps_.Shared.KEYS.SOCIAL_SAVE, session.social)
    end
    c:Commit({
        ok = function()
            if session.flushToken ~= flushToken then
                print(string.format("[PlayerState] flush ok ignored uid=%s staleToken=%s currentToken=%s", tostring(session.uid), tostring(flushToken), tostring(session.flushToken)))
                return
            end
            session.flushPending = false
            session.flushStartedAt = 0
            session.activeFlushCallback = nil
            session.flushFailed = false
            session.lastFlushAt = Now()
            if (session.mutateGeneration or 0) == flushGeneration then
                if writeUnifiedPlayerState then
                    session.dirtyEconomy = false
                    session.dirtyFarm = false
                end
                if writeSocial then session.dirtySocial = false end
                if session.dirtyProfile == true
                    and type(session.profile) == "table" then
                    session.dirtyProfile = false
                end
                if not IsDirty(session) and session.dirtyProfile ~= true then
                    ClearDirtyFlushSchedule(session)
                end
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
            Callback(callback, true)
            NotifyFlushWaiters(session, true)
            if session.flushQueued == true then
                session.flushQueued = false
                session.lastFlushAt = 0
                PlayerStateService.Flush(session.uid)
            elseif IsDirty(session) then
                MarkSessionDirtyForFlush(session, RESPONSE_FIRST_FLUSH_DELAY_SEC, "post_flush_dirty")
            end
        end,
        error = function(_, reason)
            if session.flushToken ~= flushToken then
                print(string.format("[PlayerState] flush error ignored uid=%s staleToken=%s currentToken=%s reason=%s", tostring(session.uid), tostring(flushToken), tostring(session.flushToken), tostring(reason)))
                return
            end
            session.flushPending = false
            session.flushStartedAt = 0
            session.activeFlushCallback = nil
            session.flushFailed = true
            if writeUnifiedPlayerState then
                session.dirtyEconomy = true
                session.dirtyFarm = true
            end
            if writeSocial then
                session.dirtySocial = true
            end
            if session.dirtyProfile == true then
                session.dirtyProfile = true
            end
            ScheduleFlushRetry(session, "flush_error")
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
            and session.flushPending == true
            and (session.flushStartedAt or 0) > 0
            and now - session.flushStartedAt >= FLUSH_TIMEOUT_SEC then
            session.flushPending = false
            session.flushStartedAt = 0
            session.flushToken = (session.flushToken or 0) + 1
            local activeFlushCallback = session.activeFlushCallback
            session.activeFlushCallback = nil
            session.flushFailed = true
            if type(session.economy) == "table" then session.dirtyEconomy = true end
            if type(session.farm) == "table" then session.dirtyFarm = true end
            ScheduleFlushRetry(session, "flush_timeout")
            print(string.format(
                "[PlayerState] flush timeout uid=%s elapsed=%s",
                tostring(session.uid),
                tostring(FLUSH_TIMEOUT_SEC)
            ))
            Callback(activeFlushCallback, false, "FLUSH_TIMEOUT")
            NotifyFlushWaiters(session, false, "FLUSH_TIMEOUT")
        elseif session ~= nil
            and session.loading == true
            and (session.loadStartedAt or 0) > 0
            and now - session.loadStartedAt >= LOAD_TIMEOUT_SEC then
            local retryCount = tonumber(session.loadRetryCount or 0) or 0
            if retryCount < MAX_LOAD_RETRIES then
                local callbacks = session.loadCallbacks or {}
                session.loadCallbacks = {}
                session.loading = false
                session.loadToken = 0
                session.loadStartedAt = 0
                session.loadRetryCount = retryCount + 1
                print(string.format(
                    "[PlayerState] load timeout, restart uid=%s retry=%s/%s",
                    tostring(session.uid),
                    tostring(session.loadRetryCount),
                    tostring(MAX_LOAD_RETRIES)
                ))
                -- 旧云读即使稍后回调，也会因 loadToken 已失效而被忽略。
                -- 新 Load 完成后再统一通知原有 FullSync 等待者。
                PlayerStateService.Load(session.uid, function(loadedSession, err)
                    for _, waiter in ipairs(callbacks) do
                        Callback(waiter, loadedSession, err)
                    end
                end)
            else
                print(string.format(
                    "[PlayerState] load timeout uid=%s elapsed=%s retries=%s",
                    tostring(session.uid),
                    tostring(now - session.loadStartedAt),
                    tostring(retryCount)
                ))
                FinishLoad(session, "LOAD_TIMEOUT")
            end
        elseif session ~= nil
            and session.flushPending ~= true
            and IsDirty(session) then
            local dueAt = tonumber(session.flushDueAt or 0) or 0
            local dirtySince = tonumber(session.dirtySince or 0) or 0
            local forceByAge = dirtySince > 0 and now - dirtySince >= DIRTY_FORCE_FLUSH_SEC
            local dueBySchedule = dueAt <= 0 or now >= dueAt
            local dueByLegacyInterval = now - (session.lastFlushAt or 0) >= FLUSH_INTERVAL and dueAt <= 0
            if forceByAge or dueBySchedule or dueByLegacyInterval then
                print(string.format(
                    "[PlayerState] scheduled flush uid=%s reason=%s age=%s force=%s",
                    tostring(session.uid),
                    tostring(session.flushReason),
                    tostring(dirtySince > 0 and (now - dirtySince) or 0),
                    tostring(forceByAge)
                ))
                PlayerStateService.Flush(session.uid)
            end
        end
    end
end

function PlayerStateService.WhenFlushIdle(uid, callback)
    local session = PlayerStateService.GetSession(uid)
    if session == nil or session.flushPending ~= true then
        Callback(callback, true)
        return
    end
    session.flushWaiters[#session.flushWaiters + 1] = function()
        Callback(callback, true)
    end
end

--- 拜访/偷菜：优先统一档，再回退旧农场 key
function PlayerStateService.ReadTargetFarm(targetUid, done)
    local keys = deps_.Shared and deps_.Shared.KEYS
    if keys == nil then
        done(nil, nil, true)
        return
    end
    if keys.PLAYER_STATE ~= nil then
        ServerCloudStore.ReadPlayerScore(targetUid, keys.PLAYER_STATE, {
            requireOwner = true,
            logLabel = "目标统一档",
        }, function(doc, _, err)
            if err ~= true and GetPlayerSaveAssemble().IsUnifiedDoc(doc) then
                done(doc.farm, "unified", false)
                return
            end
            if keys.AUTH_FARM_STATE == nil then
                done(nil, nil, err == true)
                return
            end
            ServerCloudStore.ReadPlayerScore(targetUid, keys.AUTH_FARM_STATE, {
                requireOwner = true,
                logLabel = "目标农场回退",
            }, function(farm, hitKey, farmErr)
                if farmErr ~= true and type(farm) == "table" then
                    done(farm, hitKey, false)
                    return
                end
                done(farm, hitKey, farmErr == true)
            end)
        end)
        return
    end
    ServerCloudStore.ReadPlayerScore(targetUid, keys.AUTH_FARM_STATE, {
        requireOwner = true,
        logLabel = "目标农场",
    }, function(farm, hitKey, farmErr)
        done(farm, hitKey, farmErr == true)
    end)
end

return PlayerStateService
