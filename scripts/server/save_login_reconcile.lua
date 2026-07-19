-- ============================================================================
-- 登录存档 UID 归一（Save Login Reconcile）
-- ============================================================================
-- 历史兼容：清档时 ClearSession；不再用于 FullSync 热路径。
-- 登录读档已改为 PlayerStateService.Load → BatchGetLoginScores。
-- ============================================================================

local UserId = require("utils.user_id")
local ServerCloudStore = require("server.server_cloud_store")
local SaveEconomyHealth = require("server.save_economy_health")
local ServerEconomyState = require("server.server_economy_state")

local SaveLoginReconcile = {}

local deps_ = {}
local sessionDone_ = {}
local inFlight_ = {}
local nextEnsureAttemptId_ = 0
local ENSURE_TIMEOUT_SEC = 8

local function GetPlayerStateService()
    return require("server.player_state_service")
end

-- 延迟 require，避免与 server_farm_state 形成顶层环（环上会拿到 true）
local function GetServerFarmState()
    return require("server.server_farm_state")
end

local function Now()
    return os and os.time and os.time() or 0
end

function SaveLoginReconcile.Init(deps)
    deps_ = deps or {}
end

function SaveLoginReconcile.ClearSession(uid)
    uid = ServerCloudStore.CanonicalUid(uid) or uid
    sessionDone_[uid] = nil
    local attempt = inFlight_[uid]
    if attempt ~= nil then
        attempt.invalidated = true
        inFlight_[uid] = nil
        for _, waiter in ipairs(attempt.waiters or {}) do
            if waiter ~= nil then waiter(false, "SESSION_CLEARED") end
        end
    end
end

local function IsCurrentAttempt(uid, attemptId)
    local attempt = inFlight_[uid]
    return attempt ~= nil
        and attempt.attemptId == attemptId
        and attempt.invalidated ~= true
        and attempt.settled ~= true
end

local function CompleteAttempt(uid, attemptId, ok, reason)
    local attempt = inFlight_[uid]
    if attempt == nil or attempt.attemptId ~= attemptId or attempt.settled == true then
        return false
    end
    attempt.settled = true
    inFlight_[uid] = nil
    for _, waiter in ipairs(attempt.waiters or {}) do
        if waiter ~= nil then waiter(ok, reason) end
    end
    return true
end

function SaveLoginReconcile.Update(_dt)
    local now = Now()
    for uid, attempt in pairs(inFlight_) do
        local phase = attempt and attempt.phase
        local timeoutSafe = phase == "marker_read"
            or phase == "verify_repaired"
            or phase == "migration_read"
        if attempt ~= nil
            and timeoutSafe
            and attempt.settled ~= true
            and attempt.invalidated ~= true
            and attempt.startedAt ~= nil
            and now - attempt.startedAt >= ENSURE_TIMEOUT_SEC then
            print(string.format(
                "[存档兼容] Ensure 超时，拒绝放行 FullSync uid=%s attempt=%s phase=%s elapsed=%s",
                tostring(uid),
                tostring(attempt.attemptId),
                tostring(attempt.phase),
                tostring(now - attempt.startedAt)
            ))
            CompleteAttempt(uid, attempt.attemptId, false, "ENSURE_TIMEOUT")
        end
    end
end

local function BuildRecordSpecs()
    local shared = deps_.Shared
    if shared == nil then return {} end
    local specs = {
        {
            key = shared.KEYS.ECONOMY_STATE,
            mode = "best",
            label = "经济状态",
            normalize = deps_.NormalizeEconomyState,
            score = ServerEconomyState.ScoreEconomyRecord,
            requireOwner = true,
        },
        {
            key = shared.KEYS.AUTH_FARM_STATE,
            mode = "best",
            label = "权威农场",
            normalize = deps_.NormalizeFarmState,
            score = GetServerFarmState().ScoreFarmState,
            requireOwner = true,
        },
        {
            key = shared.KEYS.SOCIAL_SAVE,
            mode = "first",
            label = "社交存档",
            normalize = nil,
            score = nil,
        },
    }
    if deps_.CommissionStateKey ~= nil then
        specs[#specs + 1] = {
            key = deps_.CommissionStateKey,
            mode = "first",
            label = "委托存档",
            normalize = deps_.NormalizeCommissionState,
            score = nil,
        }
    end
    return specs
end

local function RunMigration(uid, attemptId, done)
    if not IsCurrentAttempt(uid, attemptId) then return end
    uid = ServerCloudStore.CanonicalUid(uid)
    if uid == nil then
        if done ~= nil then done(false, "NO_UID") end
        return
    end

    local specs = BuildRecordSpecs()
    if #specs <= 0 then
        sessionDone_[uid] = true
        if done ~= nil then done(true, "NO_SPECS") end
        return
    end

    local migrations = {}
    local pending = #specs
    local hadReadError = false
    local function MarkMigrationReadPhase()
        local attempt = inFlight_[uid]
        if attempt ~= nil and attempt.attemptId == attemptId then
            attempt.phase = "migration_read"
        end
    end
    MarkMigrationReadPhase()

    local function finishMigration()
        if not IsCurrentAttempt(uid, attemptId) then return end
        -- 迁移读云期间若会话已建立，禁止用旧云档覆盖；以内存为准并 flush
        if GetPlayerStateService().HasLoadedSession(uid) then
            print(string.format("[存档兼容] 登录归一中止：内存会话已存在 uid=%s", tostring(uid)))
            GetPlayerStateService().Flush(uid, function(ok, reason)
                if not IsCurrentAttempt(uid, attemptId) then return end
                if ok == true then sessionDone_[uid] = true end
                if done ~= nil then done(ok == true, { skipped = true, reason = reason or "session_loaded" }) end
            end)
            return
        end
        local canonicalUid = uid
        local migratedCount = 0
        local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
        local farmKey = deps_.Shared and deps_.Shared.KEYS.AUTH_FARM_STATE
        local economyInfo = economyKey ~= nil and migrations[economyKey] or nil
        local farmInfo = farmKey ~= nil and migrations[farmKey] or nil
        if economyInfo ~= nil and farmInfo ~= nil
            and type(economyInfo.value) == "table"
            and type(farmInfo.value) == "table" then
            ServerEconomyState.SyncProgressionTourValueFromFarm(economyInfo.value, farmInfo.value)
        end
        local commit = serverCloud:BatchCommit("登录存档UID归一")
        local attempt = inFlight_[uid]
        if attempt ~= nil and attempt.attemptId == attemptId then
            attempt.phase = "migration_commit"
        end
        local writtenKeys = {}
        for _, spec in ipairs(specs) do
            local info = migrations[spec.key]
            if info == nil or info.value == nil then
                goto continue_spec
            end
            if spec.key == economyKey and hadReadError == true then
                print(string.format("[存档兼容] 登录归一跳过 %s：云读存在失败", tostring(spec.label or spec.key)))
                goto continue_spec
            end
            local cloudUid = ServerCloudStore.CloudPlayerId(canonicalUid)
            local bestKey = info.bestKey
            local fromLegacy = bestKey ~= nil
                and (not UserId.Same(bestKey, canonicalUid))
                and (not UserId.Same(bestKey, cloudUid))
            local needsOwnerStamp = type(info.value) == "table" and info.value.ownerUserId == nil
            -- 禁止把已在 canonical 的档再 Touch/写回：Touch 会抬高 saveEpoch，用旧内容盖掉新玩法写入
            if not fromLegacy and not needsOwnerStamp then
                print(string.format(
                    "[存档兼容] 登录归一跳过 %s：canonical 已是最新 bestKey=%s revision=%s",
                    tostring(spec.label or spec.key),
                    tostring(bestKey),
                    tostring(type(info.value) == "table" and info.value.revision)
                ))
                goto continue_spec
            end
            local stamped = ServerCloudStore.StampOwner(info.value, canonicalUid)
            ---@diagnostic disable-next-line: param-type-mismatch
            commit:ScoreSet(cloudUid, spec.key, stamped)
            writtenKeys[spec.key] = true
            if fromLegacy then
                migratedCount = migratedCount + 1
                print(string.format(
                    "[存档兼容] 登录归一 %s: %s -> %s revision=%s",
                    tostring(spec.label or spec.key),
                    tostring(bestKey),
                    tostring(canonicalUid),
                    tostring(stamped.revision)
                ))
            else
                print(string.format(
                    "[存档兼容] 登录归一 %s: 补写 owner 标记 uid=%s revision=%s",
                    tostring(spec.label or spec.key),
                    tostring(canonicalUid),
                    tostring(stamped.revision)
                ))
            end
            if spec.key == economyKey then
                SaveEconomyHealth.AuditSuspiciousEmpty(canonicalUid, info.value, {
                    source = "login_reconcile",
                    bestKey = info.bestKey,
                })
            end
            ::continue_spec::
        end
        -- 不在此处写 unified：无 ledger 的半成品会挡住 PlayerStateService 的完整合成。
        -- 统一档由 PlayerStateService.Load（含 ledger/mirror）负责首次落盘。
        local canFinalizeMigration = hadReadError ~= true
        if hadReadError == true then
            print(string.format("[存档兼容] 登录归一检测到云读失败 uid=%s：本次只尝试写回 canonical，不写完成标记，不清理旧副本", tostring(canonicalUid)))
        end
        if canFinalizeMigration then
            ---@diagnostic disable-next-line: param-type-mismatch
            commit:ScoreSet(ServerCloudStore.CloudPlayerId(canonicalUid), deps_.Shared.KEYS.SAVE_UID_RECONCILED, {
                version = 3,
                at = Now(),
                migrated = migratedCount,
                hadReadError = false,
                repaired = true,
                saveSchemaVersion = ServerEconomyState.SAVE_SCHEMA_VERSION,
            })
        end
        commit:Commit({
            ok = function()
                if not IsCurrentAttempt(uid, attemptId) then return end
                if canFinalizeMigration then
                    sessionDone_[uid] = true
                    SaveEconomyHealth.MarkWriteBackDone(uid)
                end
                print(string.format("[存档兼容] 登录归一提交成功 uid=%s migrated=%d finalized=%s", tostring(uid), migratedCount, tostring(canFinalizeMigration)))
                local purgeKeys = {}
                if canFinalizeMigration and economyKey ~= nil and writtenKeys[economyKey] == true then
                    purgeKeys[#purgeKeys + 1] = economyKey
                end
                if canFinalizeMigration and farmKey ~= nil and writtenKeys[farmKey] == true then
                    purgeKeys[#purgeKeys + 1] = farmKey
                end
                local socialKey = deps_.Shared and deps_.Shared.KEYS.SOCIAL_SAVE
                if canFinalizeMigration and socialKey ~= nil and writtenKeys[socialKey] == true then
                    purgeKeys[#purgeKeys + 1] = socialKey
                end
                if #purgeKeys <= 0 then
                    if done ~= nil then
                        done(canFinalizeMigration, { migrated = migratedCount, hadReadError = hadReadError, finalized = canFinalizeMigration })
                    end
                    return
                end
                local purgePending = #purgeKeys
                local purgeAttempt = inFlight_[uid]
                if purgeAttempt ~= nil and purgeAttempt.attemptId == attemptId then
                    purgeAttempt.phase = "migration_purge"
                end
                local function onPurged()
                    if not IsCurrentAttempt(uid, attemptId) then return end
                    purgePending = purgePending - 1
                    if purgePending <= 0 and done ~= nil then
                        done(true, { migrated = migratedCount, hadReadError = false, finalized = true })
                    end
                end
                for _, scoreKey in ipairs(purgeKeys) do
                    ServerCloudStore.DeleteNonCanonicalScoreCopies(uid, scoreKey, onPurged)
                end
            end,
            error = function(_, reason)
                if not IsCurrentAttempt(uid, attemptId) then return end
                print(string.format("[存档兼容] 登录归一提交失败 uid=%s reason=%s（不写完成标记，保留旧副本，下次重试）", tostring(uid), tostring(reason)))
                if done ~= nil then done(false, { migrated = migratedCount, hadReadError = hadReadError, commitError = reason }) end
            end,
        })
    end

    local function acceptSpecValue(spec, value, bestKey)
        if value == nil or bestKey == nil then return nil end
        if spec.key == (deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE) then
            local schema = math.floor(tonumber(value.saveSchemaVersion or 0) or 0)
            if schema < ServerEconomyState.SAVE_SCHEMA_VERSION then
                print(string.format(
                    "[存档兼容] 登录归一升级旧 schema %s key=%s schema=%s -> %s",
                    tostring(spec.label or spec.key),
                    tostring(bestKey),
                    tostring(value.saveSchemaVersion),
                    tostring(ServerEconomyState.SAVE_SCHEMA_VERSION)
                ))
            end
        end
        return value, bestKey
    end

    local function onSpecDone(spec, value, bestKey, specHadError)
        if not IsCurrentAttempt(uid, attemptId) then return end
        if specHadError == true then hadReadError = true end
        value, bestKey = acceptSpecValue(spec, value, bestKey)
        if value ~= nil and bestKey ~= nil then
            migrations[spec.key] = { value = value, bestKey = bestKey }
        end
        pending = pending - 1
        if pending <= 0 then finishMigration() end
    end

    for _, spec in ipairs(specs) do
        if spec.mode == "best" then
            local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
            local farmKey = deps_.Shared and deps_.Shared.KEYS.AUTH_FARM_STATE
            ServerCloudStore.ReadPlayerScore(uid, spec.key, {
                normalize = spec.normalize,
                score = spec.score,
                compareScore = spec.score,
                requireOwner = spec.requireOwner,
                allowLegacyRescue = true,
                shouldLegacyRescue = spec.key == economyKey and SaveEconomyHealth.LooksLikeFreshAccount
                    or (spec.key == farmKey and deps_.FarmLooksEmpty),
                logLabel = spec.label,
            }, function(value, bestKey, specHadError, meta)
                if not IsCurrentAttempt(uid, attemptId) then return end
                if meta ~= nil and meta.legacyRescued == true and value ~= nil then
                    value = ServerCloudStore.StampOwner(value, uid)
                end
                onSpecDone(spec, value, bestKey, specHadError)
            end)
        else
            ServerCloudStore.ReadScore(uid, spec.key, function(value, bestKey, specHadError)
                if not IsCurrentAttempt(uid, attemptId) then return end
                if value ~= nil and spec.normalize ~= nil then
                    value = spec.normalize(value)
                end
                onSpecDone(spec, value, bestKey, specHadError)
            end)
        end
    end
end


--- 确保当前会话已执行登录 UID 归一（幂等，每 uid 每会话一次）。
function SaveLoginReconcile.Ensure(uid, done)
    uid = ServerCloudStore.CanonicalUid(uid)
    if uid == nil then
        if done ~= nil then done(false, "NO_UID") end
        return
    end
    if sessionDone_[uid] == true then
        if done ~= nil then done(true, "SESSION_DONE") end
        return
    end

    -- 会话已在内存中：禁止再用云端旧副本 remigrate 覆盖；优先 flush 脏档
    if GetPlayerStateService().HasLoadedSession(uid) then
        sessionDone_[uid] = true
        GetPlayerStateService().Flush(uid, function(ok, reason)
            print(string.format(
                "[存档兼容] 已有内存会话，跳过登录归一 uid=%s flushOk=%s reason=%s",
                tostring(uid),
                tostring(ok),
                tostring(reason)
            ))
            if done ~= nil then done(ok == true, reason or "SESSION_LOADED") end
        end)
        return
    end

    local pending = inFlight_[uid]
    if pending ~= nil then
        if done ~= nil then pending.waiters[#pending.waiters + 1] = done end
        return
    end

    nextEnsureAttemptId_ = nextEnsureAttemptId_ + 1
    local attempt = {
        attemptId = nextEnsureAttemptId_,
        startedAt = Now(),
        phase = "marker_read",
        settled = false,
        invalidated = false,
        waiters = {},
    }
    if done ~= nil then attempt.waiters[#attempt.waiters + 1] = done end
    inFlight_[uid] = attempt
    local attemptId = attempt.attemptId

    local function complete(ok, reason)
        CompleteAttempt(uid, attemptId, ok, reason)
    end

    local function runMigration()
        if not IsCurrentAttempt(uid, attemptId) then return end
        attempt.phase = "migration"
        RunMigration(uid, attemptId, complete)
    end

    local markerKey = deps_.Shared and deps_.Shared.KEYS.SAVE_UID_RECONCILED
    if markerKey == nil then
        runMigration()
        return
    end

    ServerCloudStore.Get(uid, markerKey, {
        ok = function(scores)
            if not IsCurrentAttempt(uid, attemptId) then return end
            local marker = scores and scores[markerKey]
            -- 清档标记优先：任意 version 的 cleared 都禁止扫 legacy 复活
            if type(marker) == "table" and marker.cleared == true then
                sessionDone_[uid] = true
                complete(true, "CLEARED")
                return
            end
            if type(marker) == "table" and (tonumber(marker.version or 0) or 0) >= 3 then
                if marker.repaired == true then
                    attempt.phase = "verify_repaired"
                    local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
                    ServerCloudStore.ReadPlayerScore(uid, economyKey, {
                        normalize = deps_.NormalizeEconomyState,
                        score = ServerEconomyState.ScoreEconomyRecord,
                        compareScore = ServerEconomyState.ScoreEconomyRecord,
                        requireOwner = true,
                        allowLegacyRescue = true,
                        shouldLegacyRescue = SaveEconomyHealth.LooksLikeFreshAccount,
                        logLabel = "经济状态",
                    }, function(state, _bestKey, _readErr, meta)
                        if not IsCurrentAttempt(uid, attemptId) then return end
                        if state ~= nil and SaveEconomyHealth.LooksLikeFreshAccount(state) ~= true then
                            sessionDone_[uid] = true
                            complete(true, "REPAIRED")
                            return
                        end
                        print(string.format(
                            "[存档兼容] repaired 标记但经济像新号/空档，强制补迁移 uid=%s legacyRescued=%s",
                            tostring(uid),
                            tostring(meta ~= nil and meta.legacyRescued == true)
                        ))
                        runMigration()
                    end)
                    return
                end
                print(string.format(
                    "[存档兼容] 检测到未补迁移标记 uid=%s，重新执行登录归一",
                    tostring(uid)
                ))
                runMigration()
                return
            end
            runMigration()
        end,
        error = function(_, reason)
            if not IsCurrentAttempt(uid, attemptId) then return end
            print(string.format(
                "[存档兼容] 读取归一标记失败 uid=%s reason=%s，继续执行迁移",
                tostring(uid),
                tostring(reason)
            ))
            runMigration()
        end,
    })
end

return SaveLoginReconcile
