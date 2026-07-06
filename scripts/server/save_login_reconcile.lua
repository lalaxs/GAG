-- ============================================================================
-- 登录存档 UID 归一（Save Login Reconcile）
-- ============================================================================
-- 玩家首次连接/重连时，将所有分散在不同 uid key 下的 score 存档
-- 一次性迁移到 canonical string key，避免老账号经济/农场读不到而卡 loading。
-- ============================================================================

local UserId = require("utils.user_id")
local ServerCloudStore = require("server.server_cloud_store")
local SaveEconomyHealth = require("server.save_economy_health")
local ServerEconomyState = require("server.server_economy_state")
local PlayerStateService = require("server.player_state_service")

local SaveLoginReconcile = {}

local deps_ = {}
local sessionDone_ = {}
local inFlight_ = {}

local function Now()
    return os and os.time and os.time() or 0
end

local function ScoreFarmState(state)
    if type(state) ~= "table" then return -1 end
    local score = math.max(0, tonumber(state.revision or 0) or 0) * 1000
    local cropCount = 0
    for _, plot in pairs(state.plots or {}) do
        cropCount = cropCount + #(plot.plants or {})
    end
    score = score + cropCount * 100
    score = score + math.max(0, tonumber(state.updatedAt or 0) or 0)
    return score
end

function SaveLoginReconcile.Init(deps)
    deps_ = deps or {}
end

function SaveLoginReconcile.ClearSession(uid)
    uid = ServerCloudStore.CanonicalUid(uid) or uid
    sessionDone_[uid] = nil
    inFlight_[uid] = nil
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
            score = ScoreFarmState,
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

local function RunMigration(uid, done)
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

    local function finishMigration()
        -- 迁移读云期间若会话已建立，禁止用旧云档覆盖；以内存为准并 flush
        if PlayerStateService.HasLoadedSession(uid) then
            sessionDone_[uid] = true
            print(string.format("[存档兼容] 登录归一中止：内存会话已存在 uid=%s", tostring(uid)))
            PlayerStateService.Flush(uid, function()
                if done ~= nil then done(true, { skipped = true, reason = "session_loaded" }) end
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
            ServerEconomyState.AttachEconomyMirrorToFarm(farmInfo.value, economyInfo.value)
        end
        local commit = serverCloud:BatchCommit("登录存档UID归一")
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
            if spec.key == economyKey and type(stamped) == "table" then
                local ledger = ServerEconomyState.BuildEconomyLedger(stamped)
                if type(ledger) == "table" then
                    ---@diagnostic disable-next-line: param-type-mismatch
                    commit:ScoreSet(cloudUid, deps_.Shared.KEYS.ECONOMY_LEDGER, ServerCloudStore.StampOwner(ledger, canonicalUid))
                end
            end
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
                local function onPurged()
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
                compareScore = spec.key == economyKey and ServerEconomyState.ScoreEconomyContent or spec.score,
                requireOwner = spec.requireOwner,
                allowLegacyRescue = true,
                shouldLegacyRescue = spec.key == economyKey and SaveEconomyHealth.LooksLikeFreshAccount
                    or (spec.key == farmKey and deps_.FarmLooksEmpty),
                logLabel = spec.label,
            }, function(value, bestKey, specHadError, meta)
                if meta ~= nil and meta.legacyRescued == true and value ~= nil then
                    value = ServerCloudStore.StampOwner(value, uid)
                end
                onSpecDone(spec, value, bestKey, specHadError)
            end)
        else
            ServerCloudStore.ReadScore(uid, spec.key, function(value, bestKey, specHadError)
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
        if done ~= nil then done(false) end
        return
    end
    if sessionDone_[uid] == true then
        if done ~= nil then done(true) end
        return
    end

    -- 会话已在内存中：禁止再用云端旧副本 remigrate 覆盖；优先 flush 脏档
    if PlayerStateService.HasLoadedSession(uid) then
        sessionDone_[uid] = true
        PlayerStateService.Flush(uid, function(ok, reason)
            print(string.format(
                "[存档兼容] 已有内存会话，跳过登录归一 uid=%s flushOk=%s reason=%s",
                tostring(uid),
                tostring(ok),
                tostring(reason)
            ))
            if done ~= nil then done(true) end
        end)
        return
    end

    local pending = inFlight_[uid]
    if pending ~= nil then
        pending[#pending + 1] = done
        return
    end
    inFlight_[uid] = { done }

    local function complete(...)
        local waiters = inFlight_[uid] or {}
        inFlight_[uid] = nil
        for _, waiter in ipairs(waiters) do
            if waiter ~= nil then waiter(...) end
        end
    end

    local markerKey = deps_.Shared and deps_.Shared.KEYS.SAVE_UID_RECONCILED
    if markerKey == nil then
        RunMigration(uid, function(...)
            complete(...)
        end)
        return
    end

    ServerCloudStore.Get(uid, markerKey, {
        ok = function(scores)
            local marker = scores and scores[markerKey]
            -- 清档标记优先：任意 version 的 cleared 都禁止扫 legacy 复活
            if type(marker) == "table" and marker.cleared == true then
                sessionDone_[uid] = true
                complete(true)
                return
            end
            if type(marker) == "table" and (tonumber(marker.version or 0) or 0) >= 3 then
                if marker.repaired == true then
                    local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
                    ServerCloudStore.ReadPlayerScore(uid, economyKey, {
                        normalize = deps_.NormalizeEconomyState,
                        score = ServerEconomyState.ScoreEconomyRecord,
                        compareScore = ServerEconomyState.ScoreEconomyContent,
                        requireOwner = true,
                        allowLegacyRescue = true,
                        shouldLegacyRescue = SaveEconomyHealth.LooksLikeFreshAccount,
                        logLabel = "经济状态",
                    }, function(state, _bestKey, _readErr, meta)
                        if state ~= nil and SaveEconomyHealth.LooksLikeFreshAccount(state) ~= true then
                            sessionDone_[uid] = true
                            complete(true)
                            return
                        end
                        print(string.format(
                            "[存档兼容] repaired 标记但经济像新号/空档，强制补迁移 uid=%s legacyRescued=%s",
                            tostring(uid),
                            tostring(meta ~= nil and meta.legacyRescued == true)
                        ))
                        RunMigration(uid, function(...)
                            complete(...)
                        end)
                    end)
                    return
                end
                print(string.format(
                    "[存档兼容] 检测到未补迁移标记 uid=%s，重新执行登录归一",
                    tostring(uid)
                ))
                RunMigration(uid, function(...)
                    complete(...)
                end)
                return
            end
            RunMigration(uid, function(...)
                complete(...)
            end)
        end,
        error = function()
            RunMigration(uid, function(...)
                complete(...)
            end)
        end,
    })
end

return SaveLoginReconcile
