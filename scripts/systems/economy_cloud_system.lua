-- ============================================================================
-- 云端权威经济同步系统
-- ============================================================================
-- 客户端只发起具体玩法请求，并接收服务端权威结果。
-- 不再上传整份经济状态，避免客户端覆盖服务端存档。
-- ============================================================================

local Shared = require("network.shared")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local RequestStateMachine = require("client.request_state_machine")
local NetworkClient = require("client.network_client")
local AudioSystem = require("systems.audio_system")
local UserId = require("utils.user_id")

local EconomyCloudSystem = {}

local deps_ = {}
local requests_ = RequestStateMachine.Create("economy", { timeout = 14.0 })
local initialRetryDelay_ = 2.0
local initialRetryTimer_ = initialRetryDelay_
local noConnectionLogTimer_ = 0
local wasServerBound_ = false
local economyRetryableCount_ = 0
local authFarmRetryableCount_ = 0
local authFarmTimeoutCount_ = 0
local economyReadyAt_ = nil
local initialSyncDegraded_ = false
local socialSaveFallbackRequested_ = false
local INITIAL_SYNC_DEGRADE_THRESHOLD = 6
local AUTH_FARM_TIMEOUT_DEGRADE_THRESHOLD = 2
local AUTH_FARM_NO_RESPONSE_WATCHDOG_SECONDS = 6.0
local INITIAL_AUTHORITY_NO_RESPONSE_DEGRADE_SECONDS = 12.0
local OPERATION_TIMEOUT_FULL_SYNC_THRESHOLD = 2
local OPERATION_FULL_SYNC_COOLDOWN = 8.0
local FAILED_RESYNC_COOLDOWN = 8.0
local operationTimeoutCounts_ = {}
local lastOperationFullSyncAt_ = 0
local lastFailedResyncAt_ = 0
local activeFullSyncId_ = nil
local activeFullSyncRequestId_ = nil
local lastFullSyncSentAt_ = 0
local pendingAdReward_ = nil
local completedAdRewardRequestId_ = nil
local AD_REWARD_RETRY_DELAY = 2.0
local AD_REWARD_STORAGE_VERSION = 1
local AD_REWARD_STORAGE_SLOTS = {
    "pending_ad_reward_a.json",
    "pending_ad_reward_b.json",
}
local pendingAdRewardStorageSequence_ = 0
local pendingAdRewardRestored_ = false
local restoredAdRewardOwnerUid_ = nil
local lastKnownOwnerUid_ = nil

local function IsServerSessionBound()
    return NetworkClient.IsSessionBound()
end
local state_ = {
    serverEnabled = false,
    ready = false,
    authFarmReady = false,
    commissionsReady = false,
    pending = {},
    lastSyncText = "未同步",
    lastEconomyRevision = -1,
    lastAuthFarmRevision = -1,
    operationHoldUntil = 0,
    initialAuthorityDegraded = false,
    initialAuthorityDegradedReason = nil,
    initialAuthorityWaitElapsed = 0,
    initialAuthorityTotalWaitElapsed = 0,
    initialAuthorityEconomyReceived = false,
    initialAuthorityFarmReceived = false,
}

local function IsClientNetworkAvailable()
    return NetworkClient.IsRawConnected()
end

local function IsAuthoritativeClient()
    -- 纯服务器游戏：客户端始终以服务端为权威。
    return true
end

local function Now()
    return os and os.clock and os.clock() or 0
end

local function ResolveCurrentOwnerUid()
    local connection = NetworkClient.GetAliveConnection()
    local connectionUid = UserId.ReadConnectionIdentity(connection)
    local dependencyUid = UserId.Normalize(deps_.getUserId and deps_.getUserId() or nil)
    local uid = connectionUid or dependencyUid
    if uid == nil and connection == nil then uid = lastKnownOwnerUid_ end
    if uid ~= nil then lastKnownOwnerUid_ = uid end
    return uid
end

local function ReadAdRewardStorageSlot(path)
    if fileSystem == nil or fileSystem:FileExists(path) ~= true then return nil end
    local file = File(path, FILE_READ)
    if file == nil or file:IsOpen() ~= true then return nil end
    local raw = file:ReadString()
    file:Close()
    local ok, record = pcall(cjson.decode, raw or "")
    if ok ~= true or type(record) ~= "table" then
        print("[广告奖励] 忽略损坏的本地待确认记录 path=" .. tostring(path))
        return nil
    end
    if tonumber(record.version) ~= AD_REWARD_STORAGE_VERSION then return nil end
    record.sequence = math.max(0, math.floor(tonumber(record.sequence or 0) or 0))
    return record
end

local function ReadLatestAdRewardStorageRecord()
    local latest = nil
    for _, path in ipairs(AD_REWARD_STORAGE_SLOTS) do
        local record = ReadAdRewardStorageSlot(path)
        if record ~= nil and (latest == nil or record.sequence > latest.sequence) then
            latest = record
        end
    end
    return latest
end

local function WriteAdRewardStorageRecord(ownerUid, pending)
    if fileSystem == nil then return false end
    pendingAdRewardStorageSequence_ = pendingAdRewardStorageSequence_ + 1
    local record = {
        version = AD_REWARD_STORAGE_VERSION,
        sequence = pendingAdRewardStorageSequence_,
        ownerUid = UserId.Normalize(ownerUid),
        pending = pending,
    }
    local ok, encoded = pcall(cjson.encode, record)
    if ok ~= true or encoded == nil then
        print("[广告奖励] 本地待确认记录编码失败: " .. tostring(encoded))
        return false
    end
    local wroteAny = false
    for _, path in ipairs(AD_REWARD_STORAGE_SLOTS) do
        local file = File(path, FILE_WRITE)
        if file ~= nil and file:IsOpen() == true then
            file:WriteString(encoded)
            file:Close()
            wroteAny = true
        else
            print("[广告奖励] 本地待确认记录打开失败 path=" .. tostring(path))
        end
    end
    return wroteAny
end

local function PersistPendingAdReward()
    if pendingAdReward_ == nil then return false end
    return WriteAdRewardStorageRecord(pendingAdReward_.ownerUid, {
        payload = pendingAdReward_.payload,
        requireFarm = pendingAdReward_.requireFarm == true,
        createdAt = pendingAdReward_.createdAt,
    })
end

local function ClearPersistedAdReward(ownerUid)
    return WriteAdRewardStorageRecord(ownerUid or lastKnownOwnerUid_, nil)
end

local function RestorePendingAdRewardIfReady()
    local ownerUid = ResolveCurrentOwnerUid()
    if ownerUid == nil then return end
    if pendingAdRewardRestored_ == true and UserId.Same(restoredAdRewardOwnerUid_, ownerUid) then return end
    pendingAdRewardRestored_ = true
    restoredAdRewardOwnerUid_ = ownerUid

    if pendingAdReward_ ~= nil and not UserId.Same(pendingAdReward_.ownerUid, ownerUid) then
        print(string.format(
            "[广告奖励] 账号已切换，丢弃内存中的其他账号待确认记录 owner=%s current=%s",
            tostring(pendingAdReward_.ownerUid),
            tostring(ownerUid)
        ))
        pendingAdReward_ = nil
        requests_:Cancel("adReward")
    end

    local record = ReadLatestAdRewardStorageRecord()
    if record == nil then return end
    pendingAdRewardStorageSequence_ = record.sequence
    if record.pending == nil then return end
    if not UserId.Same(record.ownerUid, ownerUid) then
        print(string.format(
            "[广告奖励] 丢弃其他账号的本地待确认记录 owner=%s current=%s",
            tostring(record.ownerUid),
            tostring(ownerUid)
        ))
        ClearPersistedAdReward(ownerUid)
        return
    end

    local stored = record.pending
    local payload = type(stored.payload) == "table" and stored.payload or nil
    local requestId = payload ~= nil and tostring(payload.requestId or "") or ""
    local rewardType = payload ~= nil and tostring(payload.rewardType or "") or ""
    if requestId == "" or rewardType == "" then
        print("[广告奖励] 丢弃字段不完整的本地待确认记录")
        ClearPersistedAdReward(ownerUid)
        return
    end

    pendingAdReward_ = {
        ownerUid = ownerUid,
        payload = payload,
        requireFarm = stored.requireFarm == true or rewardType == "mature_plot",
        createdAt = tonumber(stored.createdAt) or 0,
        sent = false,
        retryAt = 0,
        attempts = 0,
    }
    print(string.format(
        "[广告奖励] 已恢复本地待确认请求 requestId=%s rewardType=%s owner=%s",
        requestId,
        rewardType,
        ownerUid
    ))
end

local function BlockIfAuthoritativeNotReady(requireFarm)
    local now = Now()
    local holdRemaining = (state_.operationHoldUntil or 0) - now
    if requireFarm == true and holdRemaining > 0.01 then
        state_.lastSyncText = "同步中..."
        if deps_.showToast then deps_.showToast("同步中", true) end
        return true
    elseif holdRemaining <= 0.01 then
        state_.operationHoldUntil = 0
    end

    if IsClientNetworkAvailable() and not IsServerSessionBound() then
        NetworkClient.BindServerConnection(true)
    end

    local rawConnected = IsClientNetworkAvailable() == true
    local bound = IsServerSessionBound() == true
    local economyReady = state_.ready == true
    local farmReady = requireFarm ~= true or state_.authFarmReady == true
    local ready = rawConnected and bound and economyReady and farmReady
    if ready and state_.initialAuthorityDegraded ~= true then return false end
    if state_.initialAuthorityDegraded == true then
        state_.lastSyncText = "存档同步失败，请重试或重开"
        if deps_.showToast then deps_.showToast("存档未就绪，暂不能操作", true) end
        return true
    end

    state_.lastSyncText = "同步中..."
    if initialSyncDegraded_ ~= true and deps_.showToast then deps_.showToast("同步中") end
    return true
end

local function SendRequest(eventName, payload)
    return NetworkClient.SendRequest(eventName, payload)
end

local function ReportServerFailure(data, reason)
    if NetworkClient.ReportServerResponseFailure ~= nil then
        return NetworkClient.ReportServerResponseFailure(data, reason)
    end
    return false
end

local function BeginRequest(requestType, payload, options)
    local nextPayload = payload or {}
    local record
    nextPayload, record = requests_:Begin(requestType, nextPayload, options)
    requests_:SyncLegacyPending(state_.pending)
    return nextPayload, record
end

local function FinishRequest(requestId, requestType)
    local record = requests_:Finish(requestId, requestType)
    requests_:SyncLegacyPending(state_.pending)
    return record
end

local function FinishExactRequest(requestId, requestType)
    local record = nil
    if requestId ~= nil then
        record = requests_:Finish(requestId)
    elseif requestType ~= nil then
        record = requests_:Finish(nil, requestType)
    end
    requests_:SyncLegacyPending(state_.pending)
    return record
end

local function ClearActiveFullSyncIfIdle()
    if requests_:IsPending("load") or requests_:IsPending("authFarm") then
        return
    end
    activeFullSyncId_ = nil
    activeFullSyncRequestId_ = nil
end

local function IsCurrentSyncResponse(data, expectedType)
    data = data or {}
    local responseUid = UserId.Normalize(data.userId)
        or UserId.Normalize(type(data.state) == "table" and data.state.ownerUserId or nil)
        or UserId.Normalize(type(data.farm) == "table" and data.farm.ownerUserId or nil)
    local currentConnection = NetworkClient.GetAliveConnection()
    local currentUid = UserId.ReadConnectionIdentity(currentConnection)
        or UserId.Normalize(deps_.getUserId and deps_.getUserId() or nil)
    if responseUid ~= nil and currentUid ~= nil and responseUid ~= currentUid then
        print(string.format(
            "[经济同步] 拒绝其他账号的权威响应 type=%s responseUid=%s currentUid=%s requestId=%s syncId=%s",
            tostring(expectedType),
            tostring(responseUid),
            tostring(currentUid),
            tostring(data.requestId),
            tostring(data.syncId)
        ))
        return false
    end
    if data.syncId == nil then
        return true
    end
    -- 服务端 first_ready / force_bind 首推可能没有 requestId。
    -- 客户端尚未发起带 requestId 的 FullSync 时必须接受，否则会丢掉已成功的权威包。
    if data.requestId == nil then
        -- 本批 ACK 已接受的 syncId：即使无 requestId（例如回家仅发社交 FullSync）也要收下。
        if activeFullSyncId_ ~= nil and tostring(data.syncId) == tostring(activeFullSyncId_) then
            return true
        end
        if activeFullSyncRequestId_ ~= nil
            and (requests_:IsPending("load") or requests_:IsPending("authFarm")) then
            print(string.format(
                "[经济同步] 忽略无 requestId 的 FullSync 响应（已有本地 pending） type=%s syncId=%s activeRequestId=%s",
                tostring(expectedType), tostring(data.syncId), tostring(activeFullSyncRequestId_)
            ))
            return false
        end
        if activeFullSyncId_ ~= nil and tostring(data.syncId) ~= tostring(activeFullSyncId_) then
            print(string.format(
                "[经济同步] 忽略无 requestId 的旧 FullSync 批次 type=%s syncId=%s activeSyncId=%s",
                tostring(expectedType), tostring(data.syncId), tostring(activeFullSyncId_)
            ))
            return false
        end
        return true
    end
    -- 官方标准：有 requestId 时用 requestId/syncId 识别本批响应。
    if activeFullSyncRequestId_ ~= nil and tostring(data.requestId) ~= tostring(activeFullSyncRequestId_) then
        print(string.format(
            "[经济同步] 忽略非当前 FullSync 请求 type=%s requestId=%s activeRequestId=%s syncId=%s",
            tostring(expectedType), tostring(data.requestId), tostring(activeFullSyncRequestId_), tostring(data.syncId)
        ))
        return false
    end
    if activeFullSyncId_ ~= nil and tostring(data.syncId) ~= tostring(activeFullSyncId_) then
        print(string.format(
            "[经济同步] 忽略旧 FullSync 批次 type=%s requestId=%s syncId=%s activeSyncId=%s",
            tostring(expectedType),
            tostring(data.requestId),
            tostring(data.syncId),
            tostring(activeFullSyncId_)
        ))
        return false
    end
    return true
end

local function FinishFullSyncRequest(requestId, requestType, data)
    local record = nil
    -- authFarm pending 的自身 id 是 authFarm_*，但服务端常回显 FullSync 的 load requestId。
    -- 这里必须按类型结算 pending，不能用 load 的 requestId 去 Finish（会被当成已结束的 load）。
    if requestType == "authFarm" then
        local pending = requests_:GetPending("authFarm")
        if pending ~= nil then
            record = FinishExactRequest(pending.id)
        end
        if record == nil then
            record = FinishExactRequest(nil, "authFarm")
        end
    elseif requestId ~= nil then
        record = FinishExactRequest(requestId)
    elseif requestType ~= nil then
        local pending = requests_:GetPending(requestType)
        record = pending ~= nil and FinishExactRequest(pending.id) or nil
    end
    if record == nil and data ~= nil and data.syncId ~= nil then
        print(string.format(
            "[经济同步] FullSync 响应未匹配 pending type=%s requestId=%s syncId=%s",
            tostring(requestType),
            tostring(requestId),
            tostring(data.syncId)
        ))
    end
    ClearActiveFullSyncIfIdle()
    return record
end
local function ReplaceTable(target, source)
    if target == nil then return end
    for key in pairs(target) do target[key] = nil end
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        local numericKey = tonumber(key)
        if numericKey ~= nil then
            target[math.floor(numericKey)] = value
        else
            target[key] = value
        end
    end
end

local function IsStaleEconomyState(cloudState, options)
    if type(cloudState) ~= "table" then return true end
    options = options or {}
    local incomingRevision = tonumber(cloudState.revision)
    if options.force == true or cloudState.force == true or cloudState.cleared == true then
        state_.lastEconomyRevision = incomingRevision or -1
        return false
    end
    if incomingRevision ~= nil then
        local currentRevision = state_.lastEconomyRevision or -1
        if incomingRevision < currentRevision then
            print(string.format("[经济同步] 忽略过期经济状态 revision=%d latest=%d", incomingRevision, currentRevision))
            return true
        end
        state_.lastEconomyRevision = incomingRevision
    elseif (state_.lastEconomyRevision or -1) >= 0 then
        print(string.format("[经济同步] 忽略无 revision 的经济状态 latest=%d", state_.lastEconomyRevision or -1))
        return true
    end
    return false
end

local function ApplyState(cloudState, options)
    if type(cloudState) ~= "table" then return false end
    options = options or {}
    if IsStaleEconomyState(cloudState, options) then return false end
    if deps_.WalletSystem and deps_.WalletSystem.SetBalance then
        deps_.WalletSystem.SetBalance(tonumber(cloudState.gold or 0) or 0)
    end
    if deps_.InventorySystem ~= nil then
        ReplaceTable(deps_.InventorySystem.GetSeedBag(), cloudState.seedBag)
        ReplaceTable(deps_.InventorySystem.GetSeedBagBuffs(), cloudState.seedBagBuffs)
        ReplaceTable(deps_.InventorySystem.GetHarvested(), cloudState.harvested)
        if deps_.InventorySystem.NormalizeHarvestedPrices ~= nil then
            deps_.InventorySystem.NormalizeHarvestedPrices()
        end
        ReplaceTable(deps_.InventorySystem.GetSeedPacks(), cloudState.seedPacks)
        if deps_.InventorySystem.GetCollectedPlants ~= nil then
            ReplaceTable(deps_.InventorySystem.GetCollectedPlants(), cloudState.collectedPlants)
        end
        if deps_.InventorySystem.GetDailyTaskState ~= nil and cloudState.dailyTaskState ~= nil then
            ReplaceTable(deps_.InventorySystem.GetDailyTaskState(), cloudState.dailyTaskState)
        end
        if deps_.InventorySystem.GetTutorialState ~= nil and cloudState.tutorial ~= nil then
            ReplaceTable(deps_.InventorySystem.GetTutorialState(), cloudState.tutorial)
            deps_.InventorySystem.GetTutorialState().plantGuideDone = deps_.InventorySystem.GetTutorialState().plantGuideDone == true
        end
    end
    if deps_.TalentSystem and deps_.TalentSystem.LoadSaveData and cloudState.talent ~= nil then
        deps_.TalentSystem.LoadSaveData(cloudState.talent)
    end
    if deps_.ProgressionSystem and deps_.ProgressionSystem.LoadSaveData and cloudState.progression ~= nil then
        deps_.ProgressionSystem.LoadSaveData(cloudState.progression, { skipTourFields = true })
        if deps_.refreshTourValue ~= nil then
            deps_.refreshTourValue()
        end
        if options.silentEvents ~= true and deps_.onProgressionApplied then deps_.onProgressionApplied(cloudState.progression) end
    end
    if deps_.ActivitySystem and deps_.ActivitySystem.LoadSaveData and cloudState.activity ~= nil then
        deps_.ActivitySystem.LoadSaveData(cloudState.activity)
    end
    if deps_.applyEconomyOwnerHint and cloudState.ownerUserId ~= nil then
        deps_.applyEconomyOwnerHint(cloudState.ownerUserId)
    end
    if deps_.syncInventoryRefs then deps_.syncInventoryRefs() end
    if deps_.markDirty then deps_.markDirty() end
    if options.silentEvents == true then return true end
    EventBus.Emit(UIEvents.WALLET_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.TALENT_CHANGED, { reason = "economy_state_applied" })
    return true
end

local function ApplyStatePatch(patch, options)
    if type(patch) ~= "table" then return false end
    options = options or {}
    local revision = tonumber(patch.revision)
    if revision ~= nil and revision > (state_.lastEconomyRevision or -1) then
        state_.lastEconomyRevision = revision
    end
    if patch.gold ~= nil and deps_.WalletSystem and deps_.WalletSystem.SetBalance then
        deps_.WalletSystem.SetBalance(tonumber(patch.gold or 0) or 0)
    end
    if deps_.InventorySystem ~= nil then
        local seedBag = deps_.InventorySystem.GetSeedBag and deps_.InventorySystem.GetSeedBag() or nil
        if seedBag ~= nil and type(patch.seedBag) == "table" then
            for key, value in pairs(patch.seedBag) do
                local index = tonumber(key)
                if index ~= nil then seedBag[math.floor(index)] = tonumber(value or 0) or 0 end
            end
        end
        local seedBagBuffs = deps_.InventorySystem.GetSeedBagBuffs and deps_.InventorySystem.GetSeedBagBuffs() or nil
        if seedBagBuffs ~= nil and type(patch.seedBagBuffs) == "table" then
            for key, value in pairs(patch.seedBagBuffs) do
                local index = tonumber(key)
                if index ~= nil then seedBagBuffs[math.floor(index)] = tonumber(value or 0) or 0 end
            end
        end
        local harvested = deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or nil
        if harvested ~= nil and type(patch.harvestAdd) == "table" then
            harvested[#harvested + 1] = patch.harvestAdd
            if deps_.InventorySystem.NormalizeHarvestedPrices ~= nil then deps_.InventorySystem.NormalizeHarvestedPrices() end
        end
        local seedPacks = deps_.InventorySystem.GetSeedPacks and deps_.InventorySystem.GetSeedPacks() or nil
        if seedPacks ~= nil and type(patch.seedPacks) == "table" then
            for key, value in pairs(patch.seedPacks) do
                seedPacks[tostring(key)] = tonumber(value or 0) or 0
            end
        end
        local collectedPlants = deps_.InventorySystem.GetCollectedPlants and deps_.InventorySystem.GetCollectedPlants() or nil
        if collectedPlants ~= nil and type(patch.collectedPlants) == "table" then
            for key, value in pairs(patch.collectedPlants) do
                local index = tonumber(key)
                if index ~= nil then collectedPlants[math.floor(index)] = value == true end
            end
        end
        if patch.dailyTaskState ~= nil and deps_.InventorySystem.GetDailyTaskState ~= nil then
            ReplaceTable(deps_.InventorySystem.GetDailyTaskState(), patch.dailyTaskState)
        end
        if patch.tutorial ~= nil and deps_.InventorySystem.GetTutorialState ~= nil then
            ReplaceTable(deps_.InventorySystem.GetTutorialState(), patch.tutorial)
            deps_.InventorySystem.GetTutorialState().plantGuideDone = deps_.InventorySystem.GetTutorialState().plantGuideDone == true
        end
    end
    if patch.progression ~= nil and deps_.ProgressionSystem and deps_.ProgressionSystem.LoadSaveData then
        deps_.ProgressionSystem.LoadSaveData(patch.progression, { skipTourFields = true })
        if deps_.refreshTourValue ~= nil then deps_.refreshTourValue() end
        if options.silentEvents ~= true and deps_.onProgressionApplied then deps_.onProgressionApplied(patch.progression) end
    end
    if patch.activity ~= nil and deps_.ActivitySystem and deps_.ActivitySystem.LoadSaveData then
        deps_.ActivitySystem.LoadSaveData(patch.activity)
    end
    if deps_.syncInventoryRefs then deps_.syncInventoryRefs() end
    if deps_.markDirty then deps_.markDirty() end
    if options.silentEvents == true then return true end
    EventBus.Emit(UIEvents.WALLET_CHANGED, { reason = "economy_patch_applied" })
    EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = "economy_patch_applied" })
    EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "economy_patch_applied" })
    EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "economy_patch_applied" })
    EventBus.Emit(UIEvents.TALENT_CHANGED, { reason = "economy_patch_applied" })
    return true
end

local function NoteAuthFarmRevision(revision, source)
    local value = tonumber(revision)
    if value == nil then return end
    if value > (state_.lastAuthFarmRevision or -1) then
        state_.lastAuthFarmRevision = value
        print(string.format("[经济同步] 已记录权威农场 revision source=%s revision=%d", tostring(source), value))
    end
end

local authFarmRequestForce_ = false
local clearedAuthFarmRevisionFloor_ = nil

local function CountFarmPlants(farm)
    if type(farm) ~= "table" or type(farm.plots) ~= "table" then return 0 end
    local count = 0
    for _, plot in pairs(farm.plots) do
        if type(plot) == "table" and type(plot.plants) == "table" then
            count = count + #plot.plants
        end
    end
    return count
end

local function ApplyAuthoritativeFarm(farm, source, options)
    options = options or {}
    if type(farm) ~= "table" then return false end
    local revision = tonumber(farm.revision)
    local latestRevision = state_.lastAuthFarmRevision or -1
    if farm.degraded == true and CountFarmPlants(farm) == 0 and latestRevision > 0 then
        print(string.format("[经济同步] 忽略降级空农场覆盖 source=%s latest=%d", tostring(source), latestRevision))
        return false
    end
    if revision == nil then
        if not options.force and latestRevision >= 0 then
            print(string.format("[经济同步] 忽略无 revision 的权威农场 source=%s latest=%d", tostring(source), latestRevision))
            return false
        end
        revision = -1
    end
    if revision >= 0 and revision < latestRevision then
        print(string.format("[经济同步] 忽略过期权威农场 source=%s revision=%d latest=%d", tostring(source), revision, latestRevision))
        return false
    end
    if not options.force and revision >= 0 and revision == latestRevision then
        print(string.format("[经济同步] 忽略重复权威农场 source=%s revision=%d latest=%d", tostring(source), revision, latestRevision))
        return false
    end
    if revision >= 0 then
        state_.lastAuthFarmRevision = revision
    end
    if deps_.onAuthFarmReceived then deps_.onAuthFarmReceived(farm) end
    state_.operationHoldUntil = 0
    return true
end

function EconomyCloudSystem.ForceSyncAuthFarm(farm, source)
    return ApplyAuthoritativeFarm(farm, source or "force_sync", { force = true })
end

function EconomyCloudSystem.Init(deps)
    deps_ = deps or {}
    initialRetryTimer_ = initialRetryDelay_
    wasServerBound_ = false
    socialSaveFallbackRequested_ = false
    authFarmTimeoutCount_ = 0
    economyReadyAt_ = nil
    state_.serverEnabled = IsClientNetworkAvailable()
    activeFullSyncId_ = nil
    activeFullSyncRequestId_ = nil
    pendingAdReward_ = nil
    completedAdRewardRequestId_ = nil
    pendingAdRewardStorageSequence_ = 0
    pendingAdRewardRestored_ = false
    restoredAdRewardOwnerUid_ = nil
    lastKnownOwnerUid_ = nil
    Shared.RegisterClientEvents()
    if NetworkClient.IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.SERVER_SYNC_ACK, "HandleGardenServerSyncAck")
        SubscribeToEvent(Shared.EVENTS.ECONOMY_STATE_RESPONSE, "HandleGardenEconomyStateResponse")
        SubscribeToEvent(Shared.EVENTS.SEED_SHOP_RESPONSE, "HandleGardenSeedShopResponse")
        SubscribeToEvent(Shared.EVENTS.AUTH_FARM_RESPONSE, "HandleGardenAuthFarmResponse")
        SubscribeToEvent(Shared.EVENTS.BUY_SEED_RESPONSE, "HandleGardenBuySeedResponse")
        SubscribeToEvent(Shared.EVENTS.CLEAR_SAVE_RESPONSE, "HandleGardenClearSaveResponse")
        SubscribeToEvent(Shared.EVENTS.PLANT_SEED_RESPONSE, "HandleGardenPlantSeedResponse")
        SubscribeToEvent(Shared.EVENTS.HARVEST_CROP_RESPONSE, "HandleGardenHarvestCropResponse")
        SubscribeToEvent(Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, "HandleGardenOpenSeedPackResponse")
        SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED_RESPONSE, "HandleGardenSellHarvestedResponse")
        SubscribeToEvent(Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, "HandleGardenClaimDailyRewardResponse")
        SubscribeToEvent(Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, "HandleGardenSynthesizePackResponse")
        SubscribeToEvent(Shared.EVENTS.UNLOCK_TALENT_RESPONSE, "HandleGardenUnlockTalentResponse")
        SubscribeToEvent(Shared.EVENTS.EXPAND_PLOT_RESPONSE, "HandleGardenExpandPlotResponse")
        SubscribeToEvent(Shared.EVENTS.COMMISSIONS_RESPONSE, "HandleGardenCommissionsResponse")
        SubscribeToEvent(Shared.EVENTS.COMPLETE_COMMISSION_RESPONSE, "HandleGardenCompleteCommissionResponse")
        SubscribeToEvent(Shared.EVENTS.SUBMIT_ACTIVITY_CROP_RESPONSE, "HandleGardenSubmitActivityCropResponse")
        SubscribeToEvent(Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD_RESPONSE, "HandleGardenExchangeActivityRewardResponse")
        SubscribeToEvent(Shared.EVENTS.DRAW_ACTIVITY_PACK_RESPONSE, "HandleGardenDrawActivityPackResponse")
        SubscribeToEvent(Shared.EVENTS.AD_REWARD_RESPONSE, "HandleGardenAdRewardResponse")
    end
end

function EconomyCloudSystem.IsAuthoritativeClient()
    return IsAuthoritativeClient()
end

function EconomyCloudSystem.IsReady(requireFarm)
    return state_.initialAuthorityDegraded ~= true
        and IsClientNetworkAvailable()
        and IsServerSessionBound()
        and state_.ready == true
        and (requireFarm ~= true or state_.authFarmReady == true)
end

function EconomyCloudSystem.IsInitialSyncReady()
    return state_.ready == true and state_.authFarmReady == true and state_.initialAuthorityDegraded ~= true
end

function EconomyCloudSystem.CanEnterInitialUi()
    -- 必须收到真实权威首包后才进主界面；超时失败停在 Loading/重开页，禁止只读半进。
    return state_.initialAuthorityDegraded ~= true
        and state_.ready == true
        and state_.authFarmReady == true
        and state_.initialAuthorityEconomyReceived == true
        and state_.initialAuthorityFarmReceived == true
end

function EconomyCloudSystem.GetInitialSyncErrorText()
    if state_.initialAuthorityDegraded ~= true then return nil end
    local reason = tostring(state_.initialAuthorityDegradedReason or "authority_no_response")
    if reason == "need_reopen" or reason == "load_failed" then
        return "未能安全读取到本账号存档。请点击重新同步；若仍失败，请使用「重开存档」创建新存档。"
    end
    if reason == "initial_authority_no_response" or reason == "initial_authority_total_no_response" then
        return "未能安全读取到本账号存档。请点击重新同步；若仍失败，可使用「重开存档」创建新存档。"
    end
    if reason == "zombie_connection_loading_timeout" then
        return "房间已连接但未收到存档数据。请刷新重进，或使用「重开存档」创建新存档。"
    end
    return "存档同步失败，暂时无法进入游戏。请重新同步；若无法读取旧档，可重开一份新存档。"
end

function EconomyCloudSystem.IsInitialAuthorityDegraded()
    return state_.initialAuthorityDegraded == true
end

--- Loading 错误页点击「重新同步」：清除失败闸门并强制 FullSync。
function EconomyCloudSystem.RetryInitialSync(reason)
    state_.initialAuthorityDegraded = false
    state_.initialAuthorityDegradedReason = nil
    state_.ready = false
    state_.authFarmReady = false
    state_.initialAuthorityEconomyReceived = false
    state_.initialAuthorityFarmReceived = false
    state_.initialAuthorityWaitElapsed = 0
    state_.initialAuthorityTotalWaitElapsed = 0
    economyRetryableCount_ = 0
    authFarmRetryableCount_ = 0
    initialSyncDegraded_ = false
    state_.lastSyncText = "同步中..."
    print("[经济同步] Loading 重新同步 reason=" .. tostring(reason or "loading_retry"))
    return EconomyCloudSystem.RequestFullSync(reason or "loading_retry", { force = true })
end

local function ClearInitialAuthorityDegradation(reason)
    if state_.initialAuthorityDegraded ~= true then return end
    if state_.initialAuthorityEconomyReceived ~= true or state_.initialAuthorityFarmReceived ~= true then return end
    state_.initialAuthorityDegraded = false
    state_.initialAuthorityDegradedReason = nil
    state_.initialAuthorityWaitElapsed = 0
    state_.initialAuthorityTotalWaitElapsed = 0
    initialSyncDegraded_ = false
    state_.lastSyncText = "已同步"
    print("[经济同步] 服务端权威首包已恢复，退出只读降级模式 reason=" .. tostring(reason or "authority_restored"))
    if deps_.showToast then deps_.showToast("服务器同步已恢复，操作已开放") end
end

function EconomyCloudSystem.MarkAuthoritySyncPending(reason)
    local hadInitialSync = state_.ready == true and state_.authFarmReady == true
    state_.lastSyncText = "同步中..."
    if hadInitialSync ~= true then
        state_.ready = false
        state_.authFarmReady = false
        state_.initialAuthorityWaitElapsed = 0
        if state_.initialAuthorityEconomyReceived == true and state_.initialAuthorityFarmReceived == true then
            state_.initialAuthorityTotalWaitElapsed = 0
        end
        state_.initialAuthorityEconomyReceived = false
        state_.initialAuthorityFarmReceived = false
        economyReadyAt_ = nil
    end
    authFarmTimeoutCount_ = 0
    print("[经济同步] 已标记重连后等待权威同步 reason=" .. tostring(reason or "network_recovery") .. " hadInitialSync=" .. tostring(hadInitialSync))
end

function EconomyCloudSystem.ClearPendingRequests(reason)
    requests_:Clear()
    if pendingAdReward_ ~= nil then
        pendingAdReward_.sent = false
        pendingAdReward_.retryAt = Now() + AD_REWARD_RETRY_DELAY
        print(string.format(
            "[广告奖励] 网络请求已重置，保留待领取奖励 requestId=%s reason=%s",
            tostring(pendingAdReward_.payload and pendingAdReward_.payload.requestId),
            tostring(reason or "network_reset")
        ))
    end
    activeFullSyncId_ = nil
    activeFullSyncRequestId_ = nil
    requests_:SyncLegacyPending(state_.pending)
    if deps_.Shop ~= nil and deps_.Shop.SetSeedShopError ~= nil then
        deps_.Shop.SetSeedShopError("网络连接已重置，请重试同步商店")
    end
    print("[经济同步] 已清理未完成请求 reason=" .. tostring(reason or "network_reset"))
end

local function EnsureSocialSaveFallback()
    if socialSaveFallbackRequested_ == true then return end
    if EconomyCloudSystem.IsInitialSyncReady() ~= true then return end
    if not IsServerSessionBound() then return end
    local social = deps_.SocialGardenSystem
    if social == nil or social.IsSocialSaveLoaded == nil then return end
    if social.IsSocialSaveLoaded() == true then return end
    socialSaveFallbackRequested_ = true
    print("[经济同步] 核心数据已就绪但社交档未恢复，补拉社交状态")
    if social.RequestSocialState ~= nil then
        social.RequestSocialState({ force = true, reason = "core_sync_social_fallback" })
    end
end

local function NotifyInitialSyncProgress()
    EnsureSocialSaveFallback()
    if deps_.onInitialSyncProgress then deps_.onInitialSyncProgress(EconomyCloudSystem.IsInitialSyncReady(), state_) end
end

--- 启动阶段权威农场无法及时同步时解除 loading，但保留最后确认农场，避免空快照覆盖玩家作物。
local function DegradeAuthFarmForInitialSync(reason)
    if state_.authFarmReady == true then return end
    requests_:Cancel("authFarm")
    state_.authFarmReady = true
    initialSyncDegraded_ = true
    authFarmRetryableCount_ = 0
    authFarmTimeoutCount_ = 0
    print("[经济同步] 权威农场同步超时/失败，保留当前农场显示 reason=" .. tostring(reason))
    if deps_.showToast then deps_.showToast("农场数据同步较慢，已保留当前花园并继续后台同步") end
    NotifyInitialSyncProgress()
end

local function DegradeInitialAuthorityForLoading(reason)
    if state_.initialAuthorityDegraded == true then return end
    state_.initialAuthorityDegraded = true
    state_.initialAuthorityDegradedReason = tostring(reason or "authority_no_response")
    -- 不伪造 ready：停留 Loading 错误页，由「重新同步 / 重开存档」闭环。
    state_.ready = false
    state_.authFarmReady = false
    state_.lastSyncText = "存档同步失败"
    requests_:Cancel("load")
    requests_:Cancel("authFarm")
    requests_:SyncLegacyPending(state_.pending)
    initialSyncDegraded_ = true
    print("[经济同步] 首包超时，停留 Loading/重开页 reason=" .. state_.initialAuthorityDegradedReason)
end

local function RequestAuthorityRefresh(reason)
    local refreshReason = reason or "request_timeout"
    EconomyCloudSystem.RequestFullSync(refreshReason, { force = true })
    EconomyCloudSystem.RequestSeedShop()
    if EconomyCloudSystem.IsReady(false) then
        EconomyCloudSystem.RequestCommissions()
    end
end

local function MaybeRequestOperationTimeoutFullSync(requestType, reason)
    requestType = tostring(requestType or "operation")
    operationTimeoutCounts_[requestType] = (operationTimeoutCounts_[requestType] or 0) + 1
    local count = operationTimeoutCounts_[requestType]
    local now = Now()
    if count < OPERATION_TIMEOUT_FULL_SYNC_THRESHOLD then
        print(string.format("[经济同步] %s 首次超时，仅释放 pending，不立即全量同步 count=%d", requestType, count))
        return false
    end
    if now - (lastOperationFullSyncAt_ or 0) < OPERATION_FULL_SYNC_COOLDOWN then
        print(string.format("[经济同步] %s 超时达到阈值，但全量同步冷却中 count=%d", requestType, count))
        return false
    end
    lastOperationFullSyncAt_ = now
    EconomyCloudSystem.RequestFullSync(reason or ("timeout_" .. requestType .. "_reconcile"), { force = true, background = true, coalesce = true })
    print(string.format("[经济同步] %s 连续超时，触发冷却保护下的全量校正 count=%d", requestType, count))
    return true
end

--- 玩法失败后的 FullSync：有 pending 则合并，冷却内不反复重启，避免 syncId 风暴与 authFarm 错配。
local function MaybeRequestFailedResync(reason)
    local now = Now()
    if requests_:IsPending("load") or requests_:IsPending("authFarm") then
        print(string.format("[经济同步] 失败重同步合并到进行中的 FullSync reason=%s", tostring(reason)))
        return true
    end
    if now - (lastFailedResyncAt_ or 0) < FAILED_RESYNC_COOLDOWN then
        print(string.format(
            "[经济同步] 失败重同步冷却中，跳过 reason=%s remain=%.1fs",
            tostring(reason),
            FAILED_RESYNC_COOLDOWN - (now - (lastFailedResyncAt_ or 0))
        ))
        return false
    end
    lastFailedResyncAt_ = now
    lastOperationFullSyncAt_ = now
    return EconomyCloudSystem.RequestFullSync(reason or "failed_resync", { force = true, background = true, coalesce = true })
end

local function ClearOperationTimeout(requestType)
    if requestType ~= nil then
        operationTimeoutCounts_[tostring(requestType)] = 0
    end
end

function EconomyCloudSystem.IsBlocked(requireFarm)
    return BlockIfAuthoritativeNotReady(requireFarm)
end

function EconomyCloudSystem.HoldFarmOperations(seconds, reason)
    local duration = math.max(0, tonumber(seconds or 1.0) or 1.0)
    state_.operationHoldUntil = math.max(state_.operationHoldUntil or 0, Now() + duration)
    state_.lastSyncText = "同步中..."
    print(string.format("[经济同步] 暂停农场操作 %.2fs reason=%s", duration, tostring(reason)))
end

function EconomyCloudSystem.GetState()
    return state_
end

local function TrySendPendingAdReward()
    RestorePendingAdRewardIfReady()
    local pending = pendingAdReward_
    if pending == nil or pending.sent == true then return false end
    local currentOwnerUid = ResolveCurrentOwnerUid()
    if currentOwnerUid == nil or not UserId.Same(pending.ownerUid, currentOwnerUid) then
        if currentOwnerUid ~= nil then
            print(string.format(
                "[广告奖励] 当前账号与待确认记录不匹配，停止发送 owner=%s current=%s",
                tostring(pending.ownerUid),
                tostring(currentOwnerUid)
            ))
        end
        return false
    end
    if Now() < (pending.retryAt or 0) then return false end
    if not EconomyCloudSystem.IsReady(pending.requireFarm == true) then return false end

    local payload = pending.payload
    if requests_:IsPending("adReward") then return false end
    BeginRequest("adReward", payload, { suppressNetworkFailure = true })
    pending.sent = true
    pending.attempts = (pending.attempts or 0) + 1
    if SendRequest(Shared.EVENTS.REQUEST_AD_REWARD, payload) then
        print(string.format(
            "[广告奖励] 已发送待领取请求 requestId=%s rewardType=%s attempt=%d",
            tostring(payload.requestId),
            tostring(payload.rewardType),
            pending.attempts
        ))
        return true
    end

    FinishExactRequest(payload.requestId)
    pending.sent = false
    pending.retryAt = Now() + AD_REWARD_RETRY_DELAY
    print(string.format(
        "[广告奖励] 发送失败，等待网络恢复后重试 requestId=%s rewardType=%s",
        tostring(payload.requestId),
        tostring(payload.rewardType)
    ))
    return false
end

function EconomyCloudSystem.Update(dt)
    requests_:Update(function(record)
        requests_:SyncLegacyPending(state_.pending)
        print("[经济同步] 请求超时: " .. tostring(record.type) .. " " .. tostring(record.id))
        if record.type == "seedShop" then
            if deps_.Shop and deps_.Shop.SetSeedShopError then
                deps_.Shop.SetSeedShopError("商店请求超时，请稍后重试")
            end
            if deps_.showToast then deps_.showToast("商店响应较慢，请稍后重试") end
            return
        end
        if record.type == "commissions" then
            state_.lastSyncText = "委托同步超时"
            if deps_.showToast then deps_.showToast("委托同步较慢，请稍后重试") end
            return
        end
        if record.type == "authFarm" then
            state_.lastSyncText = "请求超时，正在重拉服务器数据"
            if deps_.showToast then deps_.showToast("服务器同步较慢，正在重试") end
            authFarmTimeoutCount_ = authFarmTimeoutCount_ + 1
            if state_.ready == true and authFarmTimeoutCount_ >= AUTH_FARM_TIMEOUT_DEGRADE_THRESHOLD then
                DegradeAuthFarmForInitialSync("request_timeout")
            else
                EconomyCloudSystem.RequestFullSync("timeout_auth_farm", { force = true })
            end
        elseif record.type == "load" then
            state_.lastSyncText = "请求超时，正在重拉服务器数据"
            if deps_.showToast then deps_.showToast("服务器同步较慢，正在重试") end
            if state_.ready ~= true then
                EconomyCloudSystem.RequestFullSync("timeout_load", { force = true })
            end
        elseif record.type == "plant" then
            if deps_.onPlantSeedFailed then deps_.onPlantSeedFailed(record.payload) end
            EconomyCloudSystem.HoldFarmOperations(0.35, "timeout_plant")
            if deps_.showToast then deps_.showToast("播种响应较慢，请稍后再试") end
            if deps_.showFloatingToast then deps_.showFloatingToast("播种响应较慢") end
            MaybeRequestOperationTimeoutFullSync("plant", "timeout_plant_reconcile")
            print("[经济同步] 播种请求超时，已清理 pending；连续超时才请求权威校正")
        elseif record.type == "harvest" then
            EconomyCloudSystem.HoldFarmOperations(0.35, "timeout_harvest")
            if deps_.showToast then deps_.showToast("收获响应较慢，请稍后再试") end
            if deps_.showFloatingToast then deps_.showFloatingToast("收获响应较慢") end
            MaybeRequestOperationTimeoutFullSync("harvest", "timeout_harvest_reconcile")
            print("[经济同步] 收获请求超时，已清理 pending；连续超时才请求权威校正")
        elseif record.type == "adReward" then
            if pendingAdReward_ ~= nil
                and tostring(pendingAdReward_.payload.requestId) == tostring(record.id) then
                pendingAdReward_.sent = false
                pendingAdReward_.retryAt = Now() + AD_REWARD_RETRY_DELAY
                print(string.format(
                    "[广告奖励] 响应超时，保留同一 requestId 等待重试 requestId=%s",
                    tostring(record.id)
                ))
            end
            if deps_.showToast then deps_.showToast("广告奖励确认中，将在网络恢复后自动重试") end
        elseif record.type == "sell" or record.type == "openPack" then
            EconomyCloudSystem.HoldFarmOperations(0.8, "timeout_" .. tostring(record.type))
            if deps_.showToast then deps_.showToast("服务器响应较慢，请稍后重试") end
            print("[经济同步] 玩法请求超时，不触发全量同步: " .. tostring(record.type))
        else
            state_.lastSyncText = "后台请求超时"
            if deps_.showToast then deps_.showToast("服务器响应较慢，请稍后重试") end
            print("[经济同步] 后台请求超时，不触发全量同步: " .. tostring(record.type))
        end
    end)
    TrySendPendingAdReward()
    if EconomyCloudSystem.IsInitialSyncReady() and state_.initialAuthorityDegraded ~= true then return end
    if state_.ready == true and state_.authFarmReady ~= true and economyReadyAt_ ~= nil then
        local elapsed = (os and os.clock and os.clock() or 0) - economyReadyAt_
        if elapsed >= AUTH_FARM_NO_RESPONSE_WATCHDOG_SECONDS then
            DegradeAuthFarmForInitialSync("no_response_watchdog")
            return
        end
    end
    if state_.initialAuthorityDegraded ~= true
        and (state_.initialAuthorityEconomyReceived ~= true or state_.initialAuthorityFarmReceived ~= true) then
        state_.initialAuthorityTotalWaitElapsed = (state_.initialAuthorityTotalWaitElapsed or 0) + (dt or 0)
        if state_.initialAuthorityTotalWaitElapsed >= INITIAL_AUTHORITY_NO_RESPONSE_DEGRADE_SECONDS then
            DegradeInitialAuthorityForLoading("initial_authority_total_no_response")
            return
        end
    end
    initialRetryTimer_ = initialRetryTimer_ - (dt or 0)
    local serverBound = IsServerSessionBound()
    if serverBound and not wasServerBound_ then
        initialRetryTimer_ = initialRetryDelay_
        wasServerBound_ = true
    elseif not serverBound then
        wasServerBound_ = false
    end
    if not IsClientNetworkAvailable() then
        noConnectionLogTimer_ = noConnectionLogTimer_ - (dt or 0)
        if noConnectionLogTimer_ <= 0 then
            noConnectionLogTimer_ = 10.0
            print("[经济同步] 等待服务器连接后同步权威状态")
        end
        return
    end
    if not serverBound then
        noConnectionLogTimer_ = noConnectionLogTimer_ - (dt or 0)
        if noConnectionLogTimer_ <= 0 then
            noConnectionLogTimer_ = 10.0
            print("[经济同步] 等待 CLIENT_READY 绑定后再同步权威状态")
        end
        return
    end
    -- 平台僵尸连接：停止刷 FullSync；启动 watchdog 停在 Loading/重开页。
    local nrOk, NetworkRecovery = pcall(require, "runtime.network_recovery")
    if nrOk and NetworkRecovery ~= nil and NetworkRecovery.IsZombieUnhealthy ~= nil
        and NetworkRecovery.IsZombieUnhealthy() == true then
        if state_.initialAuthorityDegraded ~= true
            and (state_.initialAuthorityEconomyReceived ~= true or state_.initialAuthorityFarmReceived ~= true) then
            DegradeInitialAuthorityForLoading("zombie_connection_loading_timeout")
        end
        return
    end
    noConnectionLogTimer_ = 0
    if state_.initialAuthorityDegraded ~= true
        and (state_.initialAuthorityEconomyReceived ~= true or state_.initialAuthorityFarmReceived ~= true) then
        state_.initialAuthorityWaitElapsed = (state_.initialAuthorityWaitElapsed or 0) + (dt or 0)
        if state_.initialAuthorityWaitElapsed >= INITIAL_AUTHORITY_NO_RESPONSE_DEGRADE_SECONDS then
            DegradeInitialAuthorityForLoading("initial_authority_no_response")
            return
        end
    end
    if initialRetryTimer_ > 0 then return end
    initialRetryTimer_ = initialRetryDelay_
    if state_.initialAuthorityDegraded == true then
        print("[经济同步] Loading 失败页后台继续请求权威首包")
        EconomyCloudSystem.RequestFullSync("initial_degraded_retry", { force = true })
    elseif state_.ready ~= true or state_.authFarmReady ~= true then
        print("[经济同步] 重试全量同步")
        EconomyCloudSystem.RequestFullSync("initial_retry")
    end
end

function EconomyCloudSystem.RequestFullSync(reason, options)
    options = options or {}
    local syncReason = reason or "full_sync"
    local hasPending = requests_:IsPending("load") or requests_:IsPending("authFarm")
    -- coalesce：已有进行中的 FullSync 时不 Cancel 重启，避免风暴与 pending 错配。
    if hasPending and (options.coalesce == true or options.force ~= true) then
        print(string.format(
            "[经济同步] FullSync 合并到进行中的请求 reason=%s force=%s coalesce=%s activeRequestId=%s",
            tostring(syncReason),
            tostring(options.force == true),
            tostring(options.coalesce == true),
            tostring(activeFullSyncRequestId_)
        ))
        return true
    end
    if options.force == true then
        requests_:Cancel("load")
        requests_:Cancel("authFarm")
    end
    local userId = deps_.getUserId and deps_.getUserId() or nil
    local connectionContext = NetworkClient.GetConnectionContext ~= nil and NetworkClient.GetConnectionContext() or {}
    local loadPayload = BeginRequest("load", {
        reason = syncReason,
        userId = userId,
        connectionGeneration = connectionContext.generation,
        gameSessionId = connectionContext.gameSessionId,
    }, { timeout = 30.0 })
    local farmPayload = BeginRequest("authFarm", {
        reason = syncReason,
        userId = userId,
        connectionGeneration = connectionContext.generation,
        gameSessionId = connectionContext.gameSessionId,
        fullSyncRequestId = loadPayload and loadPayload.requestId or nil,
    }, { timeout = 30.0 })
    activeFullSyncId_ = nil
    activeFullSyncRequestId_ = loadPayload and loadPayload.requestId or nil
    lastFullSyncSentAt_ = Now()
    print(string.format(
        "[经济同步] FullSync request reason=%s force=%s background=%s uid=%s loadRequestId=%s farmRequestId=%s ready=%s authFarmReady=%s",
        tostring(syncReason),
        tostring(options.force == true),
        tostring(options.background == true),
        tostring(userId),
        tostring(loadPayload and loadPayload.requestId),
        tostring(farmPayload and farmPayload.requestId),
        tostring(state_.ready == true),
        tostring(state_.authFarmReady == true)
    ))
    if SendRequest(Shared.EVENTS.REQUEST_FULL_SYNC, {
        reason = syncReason,
        requestId = loadPayload and loadPayload.requestId or nil,
        userId = userId,
        clientConnectionGeneration = connectionContext.generation,
        gameSessionId = connectionContext.gameSessionId,
    }) then
        return true
    end
    FinishRequest(nil, "load")
    FinishRequest(nil, "authFarm")
    ClearActiveFullSyncIfIdle()
    return false
end

function EconomyCloudSystem.RequestState(options)
    options = options or {}
    if state_.ready == true and options.force ~= true then return true end
    return EconomyCloudSystem.RequestFullSync(options.reason or "request_state", options)
end

function EconomyCloudSystem.RequestAuthFarm(options)
    options = options or {}
    authFarmRequestForce_ = options.force == true
    if state_.authFarmReady == true and options.force ~= true and options.background ~= true then return true end
    return EconomyCloudSystem.RequestFullSync(options.reason or "request_auth_farm", options)
end

function EconomyCloudSystem.MarkAuthFarmDirty(reason)
    state_.authFarmReady = false
    authFarmTimeoutCount_ = 0
    authFarmRequestForce_ = true
    local syncReason = reason or "auth_farm_dirty"
    if IsClientNetworkAvailable() and not IsServerSessionBound() then
        NetworkClient.BindServerConnection(true)
    end
    return EconomyCloudSystem.RequestFullSync(syncReason, { force = true })
end

function EconomyCloudSystem.UploadState()
    state_.lastSyncText = IsClientNetworkAvailable() and "服务器权威" or "等待服务器"
    return false
end

function EconomyCloudSystem.RequestSeedShop()
    local payload = BeginRequest("seedShop", {}, { suppressNetworkFailure = true })
    if NetworkClient.SendRequest(Shared.EVENTS.REQUEST_SEED_SHOP, payload) then return true end
    FinishRequest(payload.requestId, "seedShop")
    return false
end

function EconomyCloudSystem.BuySeed(plantIndex, price, count, seedName, refreshId)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("buy", { plantIndex = plantIndex, price = price, count = count or 1, seedName = seedName, refreshId = refreshId })
    if SendRequest(Shared.EVENTS.BUY_SEED, payload) then return true end
    FinishRequest(payload.requestId, "buy")
    return false
end

function EconomyCloudSystem.ClearSave(options)
    options = options or {}
    if BlockIfAuthoritativeNotReady(false) then return false end
    RestorePendingAdRewardIfReady()
    if pendingAdReward_ ~= nil then
        if deps_.showToast then deps_.showToast("广告奖励仍在确认中，请确认完成后再清除存档") end
        print("[广告奖励] 阻止清档与待确认奖励交叉 requestId="
            .. tostring(pendingAdReward_.payload and pendingAdReward_.payload.requestId))
        return false
    end
    local payload = BeginRequest("clearSave", {
        reopenSave = options.reopenSave == true,
    })
    if SendRequest(Shared.EVENTS.CLEAR_SAVE, payload) then return true end
    FinishRequest(payload.requestId, "clearSave")
    return false
end

function EconomyCloudSystem.IsPlantPending()
    return requests_:IsPending("plant")
end

function EconomyCloudSystem.PlantSeed(payload)
    if BlockIfAuthoritativeNotReady(true) then
        print(string.format("[经济同步] 播种请求被同步状态阻止 ready=%s authFarmReady=%s bound=%s raw=%s hold=%.3f requestId=%s",
            tostring(state_.ready),
            tostring(state_.authFarmReady),
            tostring(IsServerSessionBound()),
            tostring(IsClientNetworkAvailable()),
            math.max(0, (state_.operationHoldUntil or 0) - Now()),
            tostring(payload and payload.requestId)))
        return false
    end
    if requests_:IsPending("plant") then
        if deps_.showToast then deps_.showToast("播种请求处理中，请稍后", true) end
        print("[经济同步] 忽略重复播种请求，已有请求处理中")
        return false
    end
    payload = BeginRequest("plant", payload or {}, { suppressNetworkFailure = true })
    print(string.format("[经济同步] 发送播种请求 requestId=%s plot=%s plant=%s conn={%s}", tostring(payload.requestId), tostring(payload.plotIndex), tostring(payload.plantIndex), tostring(NetworkClient.GetConnectionLogContext())))
    if SendRequest(Shared.EVENTS.PLANT_SEED, payload) then return true end
    FinishRequest(payload.requestId, "plant")
    return false
end

function EconomyCloudSystem.IsHarvestPending()
    return requests_:IsPending("harvest")
end

local function BlockIfRequestPending(requestType, message)
    if requests_:IsPending(requestType) then
        if deps_.showToast then deps_.showToast(message or "请求处理中，请稍后", true) end
        print("[经济同步] 忽略重复请求，已有请求处理中: " .. tostring(requestType))
        return true
    end
    return false
end

function EconomyCloudSystem.HarvestCrop(payload)
    if BlockIfAuthoritativeNotReady(true) then return false end
    if requests_:IsPending("harvest") then
        if deps_.showToast then deps_.showToast("收获请求处理中，请稍后") end
        print("[经济同步] 忽略重复收获请求，已有请求处理中")
        return true
    end
    payload = BeginRequest("harvest", payload or {}, { suppressNetworkFailure = true })
    print(string.format("[经济同步] 发送收获请求 requestId=%s plot=%s cropId=%s cropIndex=%s conn={%s}", tostring(payload.requestId), tostring(payload.plotIndex), tostring(payload.cropId), tostring(payload.cropIndex), tostring(NetworkClient.GetConnectionLogContext())))
    if SendRequest(Shared.EVENTS.HARVEST_CROP, payload) then return true end
    FinishRequest(payload.requestId, "harvest")
    return false
end

function EconomyCloudSystem.OpenSeedPack(packId, count, openAll)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("openPack", {
        packId = packId,
        count = count or 1,
        openAll = openAll == true,
    }, { suppressNetworkFailure = true })
    if SendRequest(Shared.EVENTS.OPEN_SEED_PACK, payload) then return true end
    FinishRequest(payload.requestId, "openPack")
    return false
end

function EconomyCloudSystem.SellAllHarvested()
    if BlockIfAuthoritativeNotReady(false) then return false end
    if BlockIfRequestPending("sell", "出售请求处理中，请稍后") then return true end
    local payload = BeginRequest("sell", { mode = "all" }, { suppressNetworkFailure = true })
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, payload) then return true end
    FinishRequest(payload.requestId, "sell")
    return false
end

function EconomyCloudSystem.SellBagItem(item)
    if BlockIfAuthoritativeNotReady(false) then return false end
    if BlockIfRequestPending("sell", "出售请求处理中，请稍后") then return true end
    local harvested = deps_.InventorySystem and deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or {}
    local targetIndex = 0
    for index, row in ipairs(harvested) do
        if row == item then targetIndex = index; break end
    end
    if targetIndex <= 0 then return false end
    local payload = BeginRequest("sell", { mode = "index", index = targetIndex }, { suppressNetworkFailure = true })
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, payload) then return true end
    FinishRequest(payload.requestId, "sell")
    return false
end

function EconomyCloudSystem.SellHarvestedByFilter(filter)
    if BlockIfAuthoritativeNotReady(false) then return false end
    if BlockIfRequestPending("sell", "出售请求处理中，请稍后") then return true end
    local payload = BeginRequest("sell", { mode = "filter", filter = filter or {} }, { suppressNetworkFailure = true })
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, payload) then return true end
    FinishRequest(payload.requestId, "sell")
    return false
end

function EconomyCloudSystem.ClaimDailyReward()
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("dailyReward", {})
    if SendRequest(Shared.EVENTS.CLAIM_DAILY_REWARD, payload) then return true end
    FinishRequest(payload.requestId, "dailyReward")
    return false
end

function EconomyCloudSystem.SynthesizePack(packId, count)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local synthCount = math.max(1, math.floor(tonumber(count or 1) or 1))
    local payload = BeginRequest("synthesizePack", { packId = packId, count = synthCount })
    if SendRequest(Shared.EVENTS.SYNTHESIZE_PACK, payload) then return true end
    FinishRequest(payload.requestId, "synthesizePack")
    return false
end

function EconomyCloudSystem.UnlockTalent(talentId)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("unlockTalent", { talentId = talentId })
    if SendRequest(Shared.EVENTS.UNLOCK_TALENT, payload) then return true end
    FinishRequest(payload.requestId, "unlockTalent")
    return false
end

function EconomyCloudSystem.ExpandPlot()
    if BlockIfAuthoritativeNotReady(true) then return false end
    local payload = BeginRequest("expandPlot", {})
    if SendRequest(Shared.EVENTS.EXPAND_PLOT, payload) then return true end
    FinishRequest(payload.requestId, "expandPlot")
    return false
end

function EconomyCloudSystem.RequestCommissions()
    if BlockIfAuthoritativeNotReady(false) then return false end
    if requests_:IsPending("commissions") then return true end
    local payload = BeginRequest("commissions", {}, { suppressNetworkFailure = true })
    if SendRequest(Shared.EVENTS.REQUEST_COMMISSIONS, payload) then return true end
    FinishRequest(payload.requestId, "commissions")
    return false
end

function EconomyCloudSystem.CompleteCommission(commission, item)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local harvested = deps_.InventorySystem and deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or {}
    local targetIndex = 0
    for index, row in ipairs(harvested) do
        if row == item then targetIndex = index; break end
    end
    if targetIndex <= 0 then return false end
    local payload = BeginRequest("completeCommission", { commissionId = commission and commission.id, itemIndex = targetIndex })
    if SendRequest(Shared.EVENTS.COMPLETE_COMMISSION, payload) then return true end
    FinishRequest(payload.requestId, "completeCommission")
    return false
end

function EconomyCloudSystem.SubmitActivityCrop(item)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local harvested = deps_.InventorySystem and deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or {}
    local targetIndex = 0
    for index, row in ipairs(harvested) do
        if row == item then targetIndex = index; break end
    end
    if targetIndex <= 0 then return false end
    local payload = BeginRequest("submitActivityCrop", { itemIndex = targetIndex })
    if SendRequest(Shared.EVENTS.SUBMIT_ACTIVITY_CROP, payload) then return true end
    FinishRequest(payload.requestId, "submitActivityCrop")
    return false
end

function EconomyCloudSystem.ExchangeActivityReward(rewardId)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("exchangeActivityReward", { rewardId = rewardId })
    if SendRequest(Shared.EVENTS.EXCHANGE_ACTIVITY_REWARD, payload) then return true end
    FinishRequest(payload.requestId, "exchangeActivityReward")
    return false
end

function EconomyCloudSystem.DrawActivityPack(count)
    if BlockIfAuthoritativeNotReady(false) then return false end
    if requests_:IsPending("drawActivityPack") then
        if deps_.showToast then deps_.showToast("抽取请求处理中，请稍后") end
        return true
    end
    local payload = BeginRequest("drawActivityPack", { count = count or 1 })
    if SendRequest(Shared.EVENTS.DRAW_ACTIVITY_PACK, payload) then return true end
    FinishRequest(payload.requestId, "drawActivityPack")
    return false
end

function EconomyCloudSystem.HasPendingAdReward()
    RestorePendingAdRewardIfReady()
    return pendingAdReward_ ~= nil
end

function EconomyCloudSystem.RequestAdReward(rewardType, extra)
    RestorePendingAdRewardIfReady()
    if pendingAdReward_ ~= nil then
        if deps_.showToast then deps_.showToast("上一笔广告奖励仍在确认中，请稍后") end
        return false
    end

    local ownerUid = ResolveCurrentOwnerUid()
    if ownerUid == nil then
        if deps_.showToast then deps_.showToast("玩家身份尚未就绪，请稍后重试") end
        return false
    end

    local payload = {}
    if type(extra) == "table" then
        for key, value in pairs(extra) do payload[key] = value end
    end
    payload.rewardType = rewardType
    payload.requestId = requests_:NextId("adReward")
    pendingAdReward_ = {
        ownerUid = ownerUid,
        payload = payload,
        requireFarm = rewardType == "mature_plot",
        createdAt = os and os.time and os.time() or 0,
        sent = false,
        retryAt = 0,
        attempts = 0,
    }
    if not PersistPendingAdReward() then
        pendingAdReward_ = nil
        if deps_.showToast then deps_.showToast("无法安全保存广告奖励请求，请稍后重试") end
        print("[广告奖励] 本地持久化失败，未向服务端提交，避免进程退出后丢失")
        return false
    end
    print(string.format(
        "[广告奖励] 已记录完整观看，等待服务端确认 requestId=%s rewardType=%s",
        tostring(payload.requestId),
        tostring(rewardType)
    ))
    TrySendPendingAdReward()
    return true
end

local function HandleGenericStateResult(data, requestType, defaultSuccess, defaultFail)
    FinishRequest(data.requestId, requestType)
    if data.success then
        if data.state ~= nil then ApplyState(data.state) end
        if data.farm ~= nil then ApplyAuthoritativeFarm(data.farm, requestType) end
        if deps_.showToast then deps_.showToast(data.message or defaultSuccess) end
        if deps_.showFloatingToast then deps_.showFloatingToast(data.message or defaultSuccess) end
        if deps_.refreshUI then deps_.refreshUI(true) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, requestType)
        if deps_.showToast then deps_.showToast(data.message or defaultFail) end
    end
end

function EconomyCloudSystem.HandleServerSyncAck(data)
    data = data or {}
    if data.syncId ~= nil and (data.stage == "full_sync_started" or data.stage == "full_sync_joined") then
        -- 以 requestId 为准接受批次；若本批已有 activeRequestId 则要求匹配。
        if activeFullSyncRequestId_ ~= nil
            and data.requestId ~= nil
            and tostring(data.requestId) ~= tostring(activeFullSyncRequestId_) then
            print(string.format(
                "[服务端ACK] 忽略非当前 FullSync ACK stage=%s syncId=%s requestId=%s activeRequestId=%s",
                tostring(data.stage),
                tostring(data.syncId),
                tostring(data.requestId),
                tostring(activeFullSyncRequestId_)
            ))
            return
        end
        activeFullSyncId_ = tostring(data.syncId)
        if data.requestId ~= nil then
            activeFullSyncRequestId_ = data.requestId
        end
        print(string.format(
            "[服务端ACK] 接受 FullSync 批次 stage=%s syncId=%s requestId=%s",
            tostring(data.stage),
            tostring(activeFullSyncId_),
            tostring(activeFullSyncRequestId_)
        ))
    elseif data.syncId ~= nil and activeFullSyncId_ ~= nil and tostring(data.syncId) ~= tostring(activeFullSyncId_) then
        print(string.format(
            "[服务端ACK] 忽略旧 FullSync ACK stage=%s syncId=%s activeSyncId=%s",
            tostring(data.stage), tostring(data.syncId), tostring(activeFullSyncId_)
        ))
        return
    end
    print(string.format(
        "[服务端ACK] stage=%s success=%s userId=%s reason=%s syncId=%s error=%s game_session_id=%s conn=%s serverTime=%s",
        tostring(data.stage),
        tostring(data.success),
        tostring(data.userId),
        tostring(data.reason),
        tostring(data.syncId),
        tostring(data.error),
        tostring(data.gameSessionId or "unknown"),
        tostring(data.connectionKey),
        tostring(data.serverTime)
    ))
end

function EconomyCloudSystem.HandleEconomyStateResponse(data)
    data = data or {}
    if not IsCurrentSyncResponse(data, "load") then return end
    if data.requestId ~= nil and FinishFullSyncRequest(data.requestId, "load", data) == nil then return end
    print(string.format(
        "[经济同步] 经济响应到达 success=%s retryable=%s requestId=%s syncId=%s reason=%s saveSource=%s",
        tostring(data.success),
        tostring(data.retryable),
        tostring(data.requestId),
        tostring(data.syncId),
        tostring(data.reason),
        tostring(data.saveSource)
    ))
    if data.requestId == nil then FinishRequest(nil, "load") end
    if data.success and ApplyState(data.state) then
        state_.ready = true
        state_.initialAuthorityEconomyReceived = true
        economyReadyAt_ = os and os.clock and os.clock() or 0
        economyRetryableCount_ = 0
        state_.lastSyncText = "已同步"
        local profileUid = deps_.getUserId and deps_.getUserId() or nil
        local talent = type(data.state) == "table" and data.state.talent or {}
        local progression = type(data.state) == "table" and data.state.progression or {}
        print(string.format(
            "[经济同步] 经济状态已同步 profileUid=%s gold=%s level=%s exp=%s plots=%s owner=%s schema=%s epoch=%s requestId=%s syncId=%s source=%s writeOk=%s",
            tostring(profileUid),
            tostring(data.state and data.state.gold),
            tostring(talent.level),
            tostring(talent.exp),
            tostring(progression.unlockedPlotCount),
            tostring(data.state and data.state.ownerUserId),
            tostring(data.state and data.state.saveSchemaVersion),
            tostring(data.state and data.state.saveEpoch),
            tostring(data.requestId),
            tostring(data.syncId),
            tostring(data.saveSource),
            tostring(data.saveWriteOk)
        ))
        -- 存档迁移结果（服务端随 FullSync 下发，便于无服务端日志时核对）
        do
            local source = tostring(data.saveSource or "unknown")
            local migrated = data.saveMigrated == true
            local writeOk = data.saveWriteOk
            local resultText
            if source == "migrate_split" then
                if writeOk == false then
                    resultText = "本次从拆分档迁移，但统一档写盘失败"
                else
                    resultText = "本次从拆分档迁移为统一档，写盘成功"
                end
            elseif source == "unified" then
                resultText = "已是统一档，直接读取（未走拆分迁移）"
            elseif source == "new_player" then
                if writeOk == false then
                    resultText = "新号统一档写盘失败"
                else
                    resultText = "新号已写入统一档"
                end
            else
                resultText = "来源未知"
            end
            print(string.format(
                "[存档迁移] 结果=%s | source=%s migrated=%s writeOk=%s reason=%s",
                resultText,
                source,
                tostring(migrated),
                tostring(writeOk),
                tostring(data.saveWriteReason)
            ))
        end
        EconomyCloudSystem.RequestCommissions()
        ClearInitialAuthorityDegradation("economy_response")
        NotifyInitialSyncProgress()
    elseif data.needReopen == true or data.code == "NEED_REOPEN" then
        DegradeInitialAuthorityForLoading("need_reopen")
        print("[经济同步] 存档不可安全读取，进入重开页: " .. tostring(data.message or data.error))
    elseif data.retryable == true then
        economyRetryableCount_ = economyRetryableCount_ + 1
        state_.lastSyncText = "同步中..."
        ReportServerFailure(data, "load")
        print(string.format("[经济同步] 经济数据暂不可用，将自动重试 (%d/%d)", economyRetryableCount_, INITIAL_SYNC_DEGRADE_THRESHOLD))
    else
        DegradeInitialAuthorityForLoading("load_failed")
        ReportServerFailure(data, "load")
        print("[经济同步] 经济数据读取失败: " .. tostring(data.message or "fail"))
    end
end

function EconomyCloudSystem.HandleSeedShopResponse(data)
    FinishRequest(data.requestId, "seedShop")
    if data.success and deps_.Shop and deps_.Shop.ApplyServerSeedShop then
        deps_.Shop.ApplyServerSeedShop(data.shop)
    else
        if deps_.Shop and deps_.Shop.SetSeedShopError then
            deps_.Shop.SetSeedShopError(data.message or "网络连接失败，商店同步失败，请重试")
        end
        ReportServerFailure(data, "seedShop")
        if deps_.showToast then deps_.showToast(data.message or "商店同步失败") end
    end
end

function EconomyCloudSystem.HandleAuthFarmResponse(data)
    data = data or {}
    if not IsCurrentSyncResponse(data, "authFarm") then return end
    local pendingFarm = requests_:GetPending("authFarm")
    local expectedLoadRequestId = pendingFarm and pendingFarm.payload and pendingFarm.payload.fullSyncRequestId
    if pendingFarm ~= nil and data.requestId ~= nil then
        local rid = tostring(data.requestId)
        local matchesFarmId = rid == tostring(pendingFarm.id)
        local matchesLoadId = expectedLoadRequestId ~= nil and rid == tostring(expectedLoadRequestId)
        if not matchesFarmId and not matchesLoadId then
            print(string.format(
                "[经济同步] 忽略旧农场 FullSync 响应 requestId=%s farmRequestId=%s loadRequestId=%s syncId=%s",
                tostring(data.requestId),
                tostring(pendingFarm.id),
                tostring(expectedLoadRequestId),
                tostring(data.syncId)
            ))
            return
        end
    end
    -- 有 pending 才强制匹配；服务端首推（无客户端 request）允许无 pending 直接应用。
    if pendingFarm ~= nil then
        if FinishFullSyncRequest(data.requestId, "authFarm", data) == nil then
            print(string.format(
                "[经济同步] 农场响应未匹配 pending requestId=%s syncId=%s",
                tostring(data.requestId),
                tostring(data.syncId)
            ))
            return
        end
    else
        FinishFullSyncRequest(nil, "authFarm", data)
    end
    local farmRevision = tonumber(data.farm and data.farm.revision or 0) or 0
    local farmPlants = 0
    if type(data.farm) == "table" and type(data.farm.plots) == "table" then
        for _, plot in pairs(data.farm.plots) do
            if type(plot) == "table" and type(plot.plants) == "table" then
                farmPlants = farmPlants + #plot.plants
            end
        end
    end
    print(string.format(
        "[经济同步] 农场响应到达 success=%s retryable=%s requestId=%s syncId=%s reason=%s revision=%s plants=%s degraded=%s forced=%s",
        tostring(data.success),
        tostring(data.retryable),
        tostring(data.requestId),
        tostring(data.syncId),
        tostring(data.reason),
        tostring(farmRevision),
        tostring(farmPlants),
        tostring(data.degraded == true),
        tostring(authFarmRequestForce_ == true)
    ))
    if data.success then
        state_.authFarmReady = true
        state_.initialAuthorityFarmReceived = true
        authFarmRetryableCount_ = 0
        if clearedAuthFarmRevisionFloor_ ~= nil and farmRevision < clearedAuthFarmRevisionFloor_ then
            print(string.format(
                "[经济同步] 忽略清档前的过期权威农场 revision=%d floor=%d",
                farmRevision,
                clearedAuthFarmRevisionFloor_
            ))
            NotifyInitialSyncProgress()
            return
        end
        if farmRevision >= (clearedAuthFarmRevisionFloor_ or 0) then
            clearedAuthFarmRevisionFloor_ = nil
        end
        print("[经济同步] 权威农场已同步" .. (data.degraded == true and "（降级）" or ""))
        local farm = data.farm
        if type(farm) == "table" and data.degraded == true then
            farm.degraded = true
        end
        ApplyAuthoritativeFarm(farm, "authFarm", { force = authFarmRequestForce_ })
        authFarmRequestForce_ = false
        if data.degraded == true then
            initialSyncDegraded_ = true
            if deps_.showToast then deps_.showToast(data.message or "农场数据暂时不可用，已进入默认农场") end
        end
        ClearInitialAuthorityDegradation("auth_farm_response")
        NotifyInitialSyncProgress()
    elseif data.needReopen == true or data.code == "NEED_REOPEN" then
        DegradeInitialAuthorityForLoading("need_reopen")
        print("[经济同步] 农场存档不可安全读取，进入重开页: " .. tostring(data.message or data.error))
    elseif data.retryable == true then
        state_.lastSyncText = "同步中..."
        ReportServerFailure(data, "authFarm")
        if state_.authFarmReady == true then
            print("[经济同步] 后台权威农场暂不可用，保留当前农场: " .. tostring(data.message or "retryable"))
            return
        end
        authFarmRetryableCount_ = math.min(authFarmRetryableCount_ + 1, INITIAL_SYNC_DEGRADE_THRESHOLD)
        print(string.format("[经济同步] 权威农场暂不可用，将自动重试 (%d/%d)", authFarmRetryableCount_, INITIAL_SYNC_DEGRADE_THRESHOLD))
    else
        DegradeInitialAuthorityForLoading("load_failed")
        ReportServerFailure(data, "authFarm")
        print("[经济同步] 权威农场读取失败: " .. tostring(data.message or "fail"))
    end
end

function EconomyCloudSystem.HandleBuySeedResponse(data)
    FinishRequest(data.requestId, "buy")
    if data.shopPatch ~= nil and deps_.Shop and deps_.Shop.ApplyServerSeedShopPatch then
        deps_.Shop.ApplyServerSeedShopPatch(data.shopPatch)
    elseif data.shop ~= nil and deps_.Shop and deps_.Shop.ApplyServerSeedShop then
        deps_.Shop.ApplyServerSeedShop(data.shop)
    end
    if data.success then
        ApplyState(data.state)
        local text = data.message or "购买成功"
        if deps_.showToast then deps_.showToast(text) end
        if deps_.showFloatingToast then deps_.showFloatingToast(text) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, "buy")
        if deps_.showToast then deps_.showToast(data.message or "购买失败") end
    end
end

function EconomyCloudSystem.HandleClearSaveResponse(data)
    FinishRequest(data.requestId, "clearSave")
    if data.success then
        if pendingAdReward_ ~= nil then
            FinishExactRequest(pendingAdReward_.payload and pendingAdReward_.payload.requestId)
            pendingAdReward_ = nil
        end
        ClearPersistedAdReward(ResolveCurrentOwnerUid())
        requests_:Cancel("authFarm")
        state_.initialAuthorityDegraded = false
        state_.initialAuthorityDegradedReason = nil
        state_.ready = true
        state_.authFarmReady = true
        state_.initialAuthorityEconomyReceived = true
        state_.initialAuthorityFarmReceived = true
        state_.commissionsReady = false
        initialSyncDegraded_ = false
        ApplyState(data.state, { force = true })
        if data.socialSave ~= nil and deps_.SocialGardenSystem ~= nil and deps_.SocialGardenSystem.LoadSaveData ~= nil then
            deps_.SocialGardenSystem.LoadSaveData(data.socialSave)
        end
        clearedAuthFarmRevisionFloor_ = math.max(0, math.floor(tonumber(data.farm and data.farm.revision or 0) or 0))
        ApplyAuthoritativeFarm(data.farm, "clearSave", { force = true })
        if deps_.showToast then deps_.showToast(data.message or "游戏存档已清除") end
        if deps_.onClearSaveCompleted then deps_.onClearSaveCompleted(true) end
        NotifyInitialSyncProgress()
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "清除存档失败") end
        if deps_.onClearSaveCompleted then deps_.onClearSaveCompleted(false) end
    end
end

function EconomyCloudSystem.HandlePlantSeedResponse(data)
    FinishRequest(data.requestId, "plant")
    if data.success then
        ClearOperationTimeout("plant")
        if deps_.onPlantSeedConfirmed then deps_.onPlantSeedConfirmed(data) end
        if data.state ~= nil then
            ApplyState(data.state)
        else
            ApplyStatePatch(data.statePatch)
        end
        if deps_.refreshTourValue ~= nil then deps_.refreshTourValue() end
        NoteAuthFarmRevision(data.farmRevision, "plant")
    else
        if deps_.onPlantSeedFailed then deps_.onPlantSeedFailed(data) end
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, "plant")
        if data.farm ~= nil then
            EconomyCloudSystem.ForceSyncAuthFarm(data.farm, "plant_failed")
        elseif data.needsFullSync == true then
            MaybeRequestFailedResync("plant_failed_resync")
        end
        if data.retryable == true then
            EconomyCloudSystem.HoldFarmOperations(1.2, "plant_retryable")
            print("[经济同步] 播种遇到可重试失败，已短暂退避，不立即重拉权威农场")
        end
        local message = data.message or "播种失败"
        if deps_.showToast then deps_.showToast(message) end
        if deps_.showFloatingToast then deps_.showFloatingToast(message) end
    end
end

function EconomyCloudSystem.HandleHarvestCropResponse(data)
    FinishRequest(data.requestId, "harvest")
    print(string.format("[经济同步] 收到收获响应 requestId=%s success=%s message=%s cropId=%s", tostring(data.requestId), tostring(data.success), tostring(data.message), tostring(data.cropId)))
    if data.success then
        ClearOperationTimeout("harvest")
        if deps_.onHarvestCropConfirmed then deps_.onHarvestCropConfirmed(data) end
        if data.state ~= nil then
            ApplyState(data.state)
        else
            ApplyStatePatch(data.statePatch)
        end
        if deps_.refreshTourValue ~= nil then deps_.refreshTourValue() end
        NoteAuthFarmRevision(data.farmRevision, "harvest")
    else
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, "harvest")
        if data.farm ~= nil then
            EconomyCloudSystem.ForceSyncAuthFarm(data.farm, "harvest_failed")
        elseif data.needsFullSync == true then
            MaybeRequestFailedResync("harvest_failed_resync")
        elseif data.retryable == true then
            EconomyCloudSystem.HoldFarmOperations(1.2, "harvest_retryable")
            print("[经济同步] 收获遇到可重试失败，已短暂退避，不立即重拉权威农场")
        end
        local message = data.message or "收获失败"
        if deps_.showToast then deps_.showToast(message) end
        if deps_.showFloatingToast then deps_.showFloatingToast(message) end
    end
end

function EconomyCloudSystem.HandleOpenSeedPackResponse(data)
    FinishRequest(data.requestId, "openPack")
    if data.success then
        ApplyState(data.state)
        if deps_.onSeedPackOpened then deps_.onSeedPackOpened(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, "openPack")
        if deps_.showToast then deps_.showToast(data.message or "开包失败") end
    end
end

function EconomyCloudSystem.HandleSellHarvestedResponse(data)
    FinishRequest(data.requestId, "sell")
    if data.success then
        ApplyState(data.state)
        AudioSystem.PlaySFX("sell_coin")
        if deps_.showToast then deps_.showToast(data.message or "出售成功") end
    else
        if data.state ~= nil then ApplyState(data.state) end
        ReportServerFailure(data, "sell")
        if deps_.showToast then deps_.showToast(data.message or "出售失败") end
    end
end

function EconomyCloudSystem.HandleClaimDailyRewardResponse(data)
    HandleGenericStateResult(data, "dailyReward", "每日奖励已领取", "领取每日奖励失败")
end

function EconomyCloudSystem.HandleSynthesizePackResponse(data)
    HandleGenericStateResult(data, "synthesizePack", "合成成功", "合成失败")
end

function EconomyCloudSystem.HandleUnlockTalentResponse(data)
    FinishRequest(data.requestId, "unlockTalent")
    if data.success then
        if data.state ~= nil then ApplyState(data.state) end
        local text = data.message or "天赋已解锁"
        if deps_.showToast then deps_.showToast(text) end
        if deps_.showFloatingToast then deps_.showFloatingToast(text) end
        EventBus.Emit(UIEvents.TALENT_CHANGED, { reason = "unlock_talent", successText = text })
        if deps_.refreshUI then deps_.refreshUI(true) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "解锁天赋失败") end
    end
end

function EconomyCloudSystem.HandleExpandPlotResponse(data)
    HandleGenericStateResult(data, "expandPlot", "扩地成功", "扩地失败")
end

function EconomyCloudSystem.HandleCommissionsResponse(data)
    FinishRequest(data.requestId, "commissions")
    if data.success and deps_.CommissionSystem and deps_.CommissionSystem.LoadSaveData then
        deps_.CommissionSystem.LoadSaveData(data.commission)
        state_.commissionsReady = true
        NotifyInitialSyncProgress()
        if deps_.refreshUI then deps_.refreshUI(true) end
    elseif deps_.showToast then
        deps_.showToast(data.message or "委托读取失败")
    end
end

function EconomyCloudSystem.HandleCompleteCommissionResponse(data)
    FinishRequest(data.requestId, "completeCommission")
    if data.success then
        if data.state ~= nil then ApplyState(data.state) end
        if data.commission ~= nil and deps_.CommissionSystem and deps_.CommissionSystem.LoadSaveData then
            deps_.CommissionSystem.LoadSaveData(data.commission)
        end
        local message = data.message or "委托完成，获得种子包"
        if deps_.showFloatingToast then
            deps_.showFloatingToast(message)
        elseif deps_.showToast then
            deps_.showToast(message)
        end
        if deps_.refreshUI then deps_.refreshUI(true) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "委托提交失败") end
    end
end

function EconomyCloudSystem.HandleSubmitActivityCropResponse(data)
    HandleGenericStateResult(data, "submitActivityCrop", "上交成功", "上交失败")
end

function EconomyCloudSystem.HandleExchangeActivityRewardResponse(data)
    HandleGenericStateResult(data, "exchangeActivityReward", "兑换成功", "兑换失败")
end

function EconomyCloudSystem.HandleDrawActivityPackResponse(data)
    local record = FinishExactRequest(data.requestId, "drawActivityPack")
    if record == nil then
        print("[经济同步] 忽略重复或过期的活动抽取响应: " .. tostring(data.requestId))
        return
    end
    if data.success then
        if data.state ~= nil then ApplyState(data.state, { silentEvents = true }) end
        local rewards = data.rewards or {}
        if deps_.onActivityDrawResult and #rewards > 0 then
            deps_.onActivityDrawResult(rewards)
        elseif deps_.onActivityDrawFailed then
            deps_.onActivityDrawFailed()
        end
        if deps_.showToast then deps_.showToast(data.message or "抽取成功") end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.onActivityDrawFailed then deps_.onActivityDrawFailed() end
        if deps_.showToast then deps_.showToast(data.message or "抽取失败") end
    end
end

function EconomyCloudSystem.HandleAdRewardResponse(data)
    data = data or {}
    local responseRequestId = tostring(data.requestId or "")
    if completedAdRewardRequestId_ ~= nil
        and responseRequestId == tostring(completedAdRewardRequestId_) then
        print("[广告奖励] 忽略已完成请求的重复响应 requestId=" .. responseRequestId)
        return
    end

    local pending = pendingAdReward_
    if pending == nil
        or responseRequestId == ""
        or responseRequestId ~= tostring(pending.payload.requestId) then
        print(string.format(
            "[广告奖励] 忽略非当前待领取响应 responseRequestId=%s pendingRequestId=%s",
            responseRequestId,
            tostring(pending and pending.payload and pending.payload.requestId)
        ))
        return
    end

    FinishExactRequest(responseRequestId)
    if data.retryable == true then
        pending.sent = false
        pending.retryAt = Now() + AD_REWARD_RETRY_DELAY
        ReportServerFailure(data, "adReward")
        if deps_.showToast then deps_.showToast("广告奖励等待网络恢复，将自动重试") end
        print("[广告奖励] 服务端暂未就绪，保留同一 requestId 重试 requestId=" .. responseRequestId)
        return
    end

    pendingAdReward_ = nil
    ClearPersistedAdReward(pending.ownerUid)
    completedAdRewardRequestId_ = responseRequestId
    if data.success then
        if data.state ~= nil then ApplyState(data.state) end
        if data.farm ~= nil then ApplyAuthoritativeFarm(data.farm, "adReward") end
        if deps_.onAdRewardGranted then deps_.onAdRewardGranted(data) end
        if deps_.showToast then deps_.showToast(data.message or "广告奖励已发放") end
        if deps_.showFloatingToast then deps_.showFloatingToast(data.message or "广告奖励已发放") end
        if deps_.refreshUI then deps_.refreshUI(true) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if data.farm ~= nil then ApplyAuthoritativeFarm(data.farm, "adReward") end
        if deps_.onAdRewardFailed then deps_.onAdRewardFailed(data) end
        if deps_.showToast then deps_.showToast(data.message or "广告奖励领取失败") end
    end
end

function EconomyCloudSystem.ApplyAuthoritativeState(cloudState)
    return ApplyState(cloudState)
end

function HandleGardenServerSyncAck(eventType, eventData)
    EconomyCloudSystem.HandleServerSyncAck(Shared.ReadEventData(eventData))
end

function HandleGardenEconomyStateResponse(eventType, eventData)
    EconomyCloudSystem.HandleEconomyStateResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSeedShopResponse(eventType, eventData)
    EconomyCloudSystem.HandleSeedShopResponse(Shared.ReadEventData(eventData))
end

function HandleGardenAuthFarmResponse(eventType, eventData)
    EconomyCloudSystem.HandleAuthFarmResponse(Shared.ReadEventData(eventData))
end

function HandleGardenBuySeedResponse(eventType, eventData)
    EconomyCloudSystem.HandleBuySeedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClearSaveResponse(eventType, eventData)
    EconomyCloudSystem.HandleClearSaveResponse(Shared.ReadEventData(eventData))
end

function HandleGardenPlantSeedResponse(eventType, eventData)
    EconomyCloudSystem.HandlePlantSeedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenHarvestCropResponse(eventType, eventData)
    EconomyCloudSystem.HandleHarvestCropResponse(Shared.ReadEventData(eventData))
end

function HandleGardenOpenSeedPackResponse(eventType, eventData)
    EconomyCloudSystem.HandleOpenSeedPackResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSellHarvestedResponse(eventType, eventData)
    EconomyCloudSystem.HandleSellHarvestedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClaimDailyRewardResponse(eventType, eventData)
    EconomyCloudSystem.HandleClaimDailyRewardResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSynthesizePackResponse(eventType, eventData)
    EconomyCloudSystem.HandleSynthesizePackResponse(Shared.ReadEventData(eventData))
end

function HandleGardenUnlockTalentResponse(eventType, eventData)
    EconomyCloudSystem.HandleUnlockTalentResponse(Shared.ReadEventData(eventData))
end

function HandleGardenExpandPlotResponse(eventType, eventData)
    EconomyCloudSystem.HandleExpandPlotResponse(Shared.ReadEventData(eventData))
end

function HandleGardenCommissionsResponse(eventType, eventData)
    EconomyCloudSystem.HandleCommissionsResponse(Shared.ReadEventData(eventData))
end

function HandleGardenCompleteCommissionResponse(eventType, eventData)
    EconomyCloudSystem.HandleCompleteCommissionResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSubmitActivityCropResponse(eventType, eventData)
    EconomyCloudSystem.HandleSubmitActivityCropResponse(Shared.ReadEventData(eventData))
end

function HandleGardenExchangeActivityRewardResponse(eventType, eventData)
    EconomyCloudSystem.HandleExchangeActivityRewardResponse(Shared.ReadEventData(eventData))
end

function HandleGardenDrawActivityPackResponse(eventType, eventData)
    EconomyCloudSystem.HandleDrawActivityPackResponse(Shared.ReadEventData(eventData))
end

function HandleGardenAdRewardResponse(eventType, eventData)
    EconomyCloudSystem.HandleAdRewardResponse(Shared.ReadEventData(eventData))
end

return EconomyCloudSystem
