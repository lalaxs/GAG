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

local SaveLoginReconcile = {}

local deps_ = {}
local sessionDone_ = {}

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
    sessionDone_[ServerCloudStore.CanonicalUid(uid) or uid] = nil
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
            minSchemaVersion = ServerEconomyState.SAVE_SCHEMA_VERSION,
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
        local canonicalUid = uid
        local migratedCount = 0
        local commit = serverCloud:BatchCommit("登录存档UID归一")
        local economyKey = deps_.Shared and deps_.Shared.KEYS.ECONOMY_STATE
        for _, spec in ipairs(specs) do
            local info = migrations[spec.key]
            if info == nil or info.value == nil then
                goto continue_spec
            end
            if spec.key == economyKey and hadReadError == true then
                print(string.format("[存档兼容] 登录归一跳过 %s：云读存在失败", tostring(spec.label or spec.key)))
                goto continue_spec
            end
            local stamped = ServerCloudStore.StampOwner(info.value, canonicalUid)
            local cloudUid = ServerCloudStore.CloudPlayerId(canonicalUid)
            if spec.key == economyKey then
                stamped = ServerEconomyState.TouchEconomyState(stamped)
                ---@diagnostic disable-next-line: param-type-mismatch
                commit:ScoreSet(cloudUid, spec.key, stamped)
                if info.bestKey ~= nil and not UserId.Same(info.bestKey, canonicalUid) then
                    migratedCount = migratedCount + 1
                    print(string.format(
                        "[存档兼容] 登录归一 %s: %s -> %s",
                        tostring(spec.label or spec.key),
                        tostring(info.bestKey),
                        tostring(canonicalUid)
                    ))
                else
                    print(string.format(
                        "[存档兼容] 登录归一 %s: normalize 后写回 canonical uid=%s",
                        tostring(spec.label or spec.key),
                        tostring(canonicalUid)
                    ))
                end
                SaveEconomyHealth.AuditSuspiciousEmpty(canonicalUid, info.value, {
                    source = "login_reconcile",
                    bestKey = info.bestKey,
                })
            elseif info.bestKey ~= nil and not UserId.Same(info.bestKey, canonicalUid) then
                ---@diagnostic disable-next-line: param-type-mismatch
                commit:ScoreSet(cloudUid, spec.key, stamped)
                migratedCount = migratedCount + 1
                print(string.format(
                    "[存档兼容] 登录归一 %s: %s -> %s",
                    tostring(spec.label or spec.key),
                    tostring(info.bestKey),
                    tostring(canonicalUid)
                ))
            end
            ::continue_spec::
        end
        ---@diagnostic disable-next-line: param-type-mismatch
        commit:ScoreSet(ServerCloudStore.CloudPlayerId(canonicalUid), deps_.Shared.KEYS.SAVE_UID_RECONCILED, {
            version = 2,
            at = Now(),
            migrated = migratedCount,
            hadReadError = hadReadError == true,
            saveSchemaVersion = ServerEconomyState.SAVE_SCHEMA_VERSION,
        })
        commit:Commit({
            ok = function()
                sessionDone_[uid] = true
                SaveEconomyHealth.MarkWriteBackDone(uid)
                print(string.format("[存档兼容] 登录归一完成 uid=%s migrated=%d", tostring(uid), migratedCount))
                if done ~= nil then done(true, { migrated = migratedCount, hadReadError = hadReadError }) end
            end,
            error = function(_, reason)
                sessionDone_[uid] = true
                print(string.format("[存档兼容] 登录归一提交失败 uid=%s reason=%s（仍继续登录）", tostring(uid), tostring(reason)))
                if done ~= nil then done(true, { migrated = migratedCount, hadReadError = hadReadError, commitError = reason }) end
            end,
        })
    end

    local function acceptSpecValue(spec, value, bestKey)
        if value == nil or bestKey == nil then return nil end
        local minSchema = math.floor(tonumber(spec.minSchemaVersion or 0) or 0)
        if minSchema > 0 and (math.floor(tonumber(value.saveSchemaVersion or 0) or 0) < minSchema) then
            print(string.format(
                "[存档兼容] 登录归一忽略旧 schema %s key=%s schema=%s",
                tostring(spec.label or spec.key),
                tostring(bestKey),
                tostring(value.saveSchemaVersion)
            ))
            return nil
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
            ServerCloudStore.ReadBestScore(uid, spec.key, {
                normalize = spec.normalize,
                score = spec.score,
                requireOwner = spec.requireOwner,
                logLabel = spec.label,
            }, function(value, bestKey, specHadError)
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

    local markerKey = deps_.Shared and deps_.Shared.KEYS.SAVE_UID_RECONCILED
    if markerKey == nil then
        RunMigration(uid, done)
        return
    end

    ServerCloudStore.Get(uid, markerKey, {
        ok = function(scores)
            local marker = scores and scores[markerKey]
            if type(marker) == "table" and (tonumber(marker.version or 0) or 0) >= 2 then
                sessionDone_[uid] = true
                if done ~= nil then done(true) end
                return
            end
            RunMigration(uid, done)
        end,
        error = function()
            RunMigration(uid, done)
        end,
    })
end

return SaveLoginReconcile
