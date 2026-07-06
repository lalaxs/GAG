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
    if ready then return false end

    state_.lastSyncText = "同步中..."
    if initialSyncDegraded_ ~= true and deps_.showToast then deps_.showToast("同步中") end
    return true
end

local function SendRequest(eventName, payload)
    return NetworkClient.SendRequest(eventName, payload)
end

local function BeginRequest(requestType, payload)
    local nextPayload = payload or {}
    local record
    nextPayload, record = requests_:Begin(requestType, nextPayload)
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
    Shared.RegisterClientEvents()
    if NetworkClient.IsClientMode() then
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
    return IsClientNetworkAvailable() and IsServerSessionBound() and state_.ready == true and (requireFarm ~= true or state_.authFarmReady == true)
end

function EconomyCloudSystem.IsInitialSyncReady()
    return state_.ready == true and state_.authFarmReady == true
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

local function RequestAuthorityRefresh(reason)
    local refreshReason = reason or "request_timeout"
    EconomyCloudSystem.RequestState({ force = true, reason = refreshReason })
    EconomyCloudSystem.RequestSeedShop()
    EconomyCloudSystem.RequestAuthFarm({ force = true, reason = refreshReason })
    if EconomyCloudSystem.IsReady(false) then
        EconomyCloudSystem.RequestCommissions()
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

function EconomyCloudSystem.Update(dt)
    requests_:Update(function(record)
        requests_:SyncLegacyPending(state_.pending)
        state_.lastSyncText = "请求超时，正在重拉服务器数据"
        if deps_.showToast then deps_.showToast("重连中") end
        print("[经济同步] 请求超时: " .. tostring(record.type) .. " " .. tostring(record.id))
        if record.type == "authFarm" then
            authFarmTimeoutCount_ = authFarmTimeoutCount_ + 1
            if state_.ready == true and authFarmTimeoutCount_ >= AUTH_FARM_TIMEOUT_DEGRADE_THRESHOLD then
                DegradeAuthFarmForInitialSync("request_timeout")
            else
                EconomyCloudSystem.RequestAuthFarm({ force = true, reason = "timeout_retry" })
            end
        elseif record.type == "plant" or record.type == "harvest" then
            if record.type == "plant" and deps_.onPlantSeedFailed then deps_.onPlantSeedFailed(record.payload) end
            EconomyCloudSystem.HoldFarmOperations(1.5, "timeout_" .. tostring(record.type))
            print("[经济同步] 玩法请求超时，已短暂退避，不立即重拉权威农场: " .. tostring(record.type))
        elseif record.type ~= "load" then
            RequestAuthorityRefresh("timeout_" .. tostring(record.type))
        end
    end)
    if EconomyCloudSystem.IsInitialSyncReady() then return end
    if state_.ready == true and state_.authFarmReady ~= true and economyReadyAt_ ~= nil then
        local elapsed = (os and os.clock and os.clock() or 0) - economyReadyAt_
        if elapsed >= AUTH_FARM_NO_RESPONSE_WATCHDOG_SECONDS then
            DegradeAuthFarmForInitialSync("no_response_watchdog")
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
    noConnectionLogTimer_ = 0
    if initialRetryTimer_ > 0 then return end
    initialRetryTimer_ = initialRetryDelay_
    if state_.ready ~= true then
        print("[经济同步] 重试读取经济状态")
        EconomyCloudSystem.RequestState()
    end
    if state_.authFarmReady ~= true then
        print("[经济同步] 重试读取权威农场")
        EconomyCloudSystem.RequestAuthFarm()
    end
end

function EconomyCloudSystem.RequestState(options)
    options = options or {}
    if state_.ready == true and options.force ~= true then return true end
    if options.force == true then requests_:Cancel("load") end
    if requests_:IsPending("load") then return true end
    local payload = BeginRequest("load", { reason = options.reason or "sync", userId = deps_.getUserId and deps_.getUserId() or nil })
    if SendRequest(Shared.EVENTS.REQUEST_ECONOMY_STATE, payload) then return true end
    FinishRequest(payload.requestId, "load")
    return false
end

function EconomyCloudSystem.RequestAuthFarm(options)
    options = options or {}
    authFarmRequestForce_ = options.force == true
    if state_.authFarmReady == true and options.force ~= true and options.background ~= true then return true end
    if options.force == true then requests_:Cancel("authFarm") end
    if requests_:IsPending("authFarm") then return true end
    local payload = BeginRequest("authFarm", { reason = options.reason or "sync", userId = deps_.getUserId and deps_.getUserId() or nil })
    if SendRequest(Shared.EVENTS.REQUEST_AUTH_FARM, payload) then return true end
    FinishRequest(payload.requestId, "authFarm")
    return false
end

function EconomyCloudSystem.MarkAuthFarmDirty(reason)
    state_.authFarmReady = false
    authFarmTimeoutCount_ = 0
    authFarmRequestForce_ = true
    local syncReason = reason or "auth_farm_dirty"
    if IsClientNetworkAvailable() and not IsServerSessionBound() then
        NetworkClient.BindServerConnection(true)
    end
    EconomyCloudSystem.RequestState({ force = true, reason = syncReason })
    EconomyCloudSystem.RequestAuthFarm({ force = true, reason = syncReason })
    return true
end

function EconomyCloudSystem.UploadState()
    state_.lastSyncText = IsClientNetworkAvailable() and "服务器权威" or "等待服务器"
    return false
end

function EconomyCloudSystem.RequestSeedShop()
    return NetworkClient.SendRequest(Shared.EVENTS.REQUEST_SEED_SHOP, {})
end

function EconomyCloudSystem.BuySeed(plantIndex, price, count, seedName, refreshId)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("buy", { plantIndex = plantIndex, price = price, count = count or 1, seedName = seedName, refreshId = refreshId })
    if SendRequest(Shared.EVENTS.BUY_SEED, payload) then return true end
    FinishRequest(payload.requestId, "buy")
    return false
end

function EconomyCloudSystem.ClearSave()
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("clearSave", {})
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
    payload = BeginRequest("plant", payload or {})
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
    payload = BeginRequest("harvest", payload or {})
    print(string.format("[经济同步] 发送收获请求 requestId=%s plot=%s cropId=%s cropIndex=%s", tostring(payload.requestId), tostring(payload.plotIndex), tostring(payload.cropId), tostring(payload.cropIndex)))
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
    })
    if SendRequest(Shared.EVENTS.OPEN_SEED_PACK, payload) then return true end
    FinishRequest(payload.requestId, "openPack")
    return false
end

function EconomyCloudSystem.SellAllHarvested()
    if BlockIfAuthoritativeNotReady(false) then return false end
    if BlockIfRequestPending("sell", "出售请求处理中，请稍后") then return true end
    local payload = BeginRequest("sell", { mode = "all" })
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
    local payload = BeginRequest("sell", { mode = "index", index = targetIndex })
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, payload) then return true end
    FinishRequest(payload.requestId, "sell")
    return false
end

function EconomyCloudSystem.SellHarvestedByFilter(filter)
    if BlockIfAuthoritativeNotReady(false) then return false end
    if BlockIfRequestPending("sell", "出售请求处理中，请稍后") then return true end
    local payload = BeginRequest("sell", { mode = "filter", filter = filter or {} })
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
    local payload = BeginRequest("commissions", {})
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

function EconomyCloudSystem.RequestAdReward(rewardType, extra)
    if BlockIfAuthoritativeNotReady(rewardType == "mature_plot") then return false end
    if requests_:IsPending("adReward") then
        if deps_.showToast then deps_.showToast("广告奖励发放中，请稍后") end
        return true
    end
    local payload = {}
    if type(extra) == "table" then
        for key, value in pairs(extra) do payload[key] = value end
    end
    payload.rewardType = rewardType
    payload = BeginRequest("adReward", payload)
    if SendRequest(Shared.EVENTS.REQUEST_AD_REWARD, payload) then return true end
    FinishRequest(payload.requestId, "adReward")
    if deps_.showToast then deps_.showToast("奖励请求发送失败，请稍后重试") end
    return false
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
        if deps_.showToast then deps_.showToast(data.message or defaultFail) end
    end
end

function EconomyCloudSystem.HandleEconomyStateResponse(data)
    FinishRequest(data.requestId, "load")
    if data.success and ApplyState(data.state) then
        state_.ready = true
        economyReadyAt_ = os and os.clock and os.clock() or 0
        economyRetryableCount_ = 0
        state_.lastSyncText = "已同步"
        local profileUid = deps_.getUserId and deps_.getUserId() or nil
        local talent = type(data.state) == "table" and data.state.talent or {}
        local progression = type(data.state) == "table" and data.state.progression or {}
        print(string.format(
            "[经济同步] 经济状态已同步 profileUid=%s gold=%s level=%s exp=%s plots=%s owner=%s schema=%s epoch=%s",
            tostring(profileUid),
            tostring(data.state and data.state.gold),
            tostring(talent.level),
            tostring(talent.exp),
            tostring(progression.unlockedPlotCount),
            tostring(data.state and data.state.ownerUserId),
            tostring(data.state and data.state.saveSchemaVersion),
            tostring(data.state and data.state.saveEpoch)
        ))
        EconomyCloudSystem.RequestCommissions()
        NotifyInitialSyncProgress()
    elseif data.retryable == true then
        economyRetryableCount_ = economyRetryableCount_ + 1
        state_.lastSyncText = "同步中..."
        print(string.format("[经济同步] 经济数据暂不可用，将自动重试 (%d/%d)", economyRetryableCount_, INITIAL_SYNC_DEGRADE_THRESHOLD))
    elseif deps_.showToast then
        deps_.showToast(data.message or "经济数据读取失败")
    end
end

function EconomyCloudSystem.HandleSeedShopResponse(data)
    if data.success and deps_.Shop and deps_.Shop.ApplyServerSeedShop then
        deps_.Shop.ApplyServerSeedShop(data.shop)
    elseif deps_.showToast then
        deps_.showToast(data.message or "商店同步失败")
    end
end

function EconomyCloudSystem.HandleAuthFarmResponse(data)
    FinishRequest(data.requestId, "authFarm")
    if data.success then
        state_.authFarmReady = true
        authFarmRetryableCount_ = 0
        local farmRevision = tonumber(data.farm and data.farm.revision or 0) or 0
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
        NotifyInitialSyncProgress()
    elseif data.retryable == true then
        state_.lastSyncText = "同步中..."
        if state_.authFarmReady == true then
            print("[经济同步] 后台权威农场暂不可用，保留当前农场: " .. tostring(data.message or "retryable"))
            return
        end
        authFarmRetryableCount_ = math.min(authFarmRetryableCount_ + 1, INITIAL_SYNC_DEGRADE_THRESHOLD)
        print(string.format("[经济同步] 权威农场暂不可用，将自动重试 (%d/%d)", authFarmRetryableCount_, INITIAL_SYNC_DEGRADE_THRESHOLD))
        if state_.ready == true and authFarmRetryableCount_ >= INITIAL_SYNC_DEGRADE_THRESHOLD then
            DegradeAuthFarmForInitialSync("retryable_exhausted")
        end
    elseif deps_.showToast then
        deps_.showToast(data.message or "权威农场读取失败")
    end
end

function EconomyCloudSystem.HandleBuySeedResponse(data)
    FinishRequest(data.requestId, "buy")
    if data.shop ~= nil and deps_.Shop and deps_.Shop.ApplyServerSeedShop then
        deps_.Shop.ApplyServerSeedShop(data.shop)
    end
    if data.success then
        ApplyState(data.state)
        local text = data.message or "购买成功"
        if deps_.showToast then deps_.showToast(text) end
        if deps_.showFloatingToast then deps_.showFloatingToast(text) end
    elseif deps_.showToast then
        if data.state ~= nil then ApplyState(data.state) end
        deps_.showToast(data.message or "购买失败")
    end
end

function EconomyCloudSystem.HandleClearSaveResponse(data)
    FinishRequest(data.requestId, "clearSave")
    if data.success then
        requests_:Cancel("authFarm")
        state_.ready = true
        state_.authFarmReady = true
        state_.commissionsReady = false
        ApplyState(data.state, { force = true })
        if data.socialSave ~= nil and deps_.SocialGardenSystem ~= nil and deps_.SocialGardenSystem.LoadSaveData ~= nil then
            deps_.SocialGardenSystem.LoadSaveData(data.socialSave)
        end
        clearedAuthFarmRevisionFloor_ = math.max(0, math.floor(tonumber(data.farm and data.farm.revision or 0) or 0))
        ApplyAuthoritativeFarm(data.farm, "clearSave", { force = true })
        if deps_.showToast then deps_.showToast(data.message or "游戏存档已清除") end
        if deps_.onClearSaveCompleted then deps_.onClearSaveCompleted(true) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "清除存档失败") end
        if deps_.onClearSaveCompleted then deps_.onClearSaveCompleted(false) end
    end
end

function EconomyCloudSystem.HandlePlantSeedResponse(data)
    FinishRequest(data.requestId, "plant")
    if data.success then
        if deps_.onPlantSeedConfirmed then deps_.onPlantSeedConfirmed(data) end
        ApplyState(data.state)
        if deps_.refreshTourValue ~= nil then deps_.refreshTourValue() end
        NoteAuthFarmRevision(data.farmRevision, "plant")
    else
        if deps_.onPlantSeedFailed then deps_.onPlantSeedFailed(data) end
        if data.state ~= nil then ApplyState(data.state) end
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
        if deps_.onHarvestCropConfirmed then deps_.onHarvestCropConfirmed(data) end
        ApplyState(data.state)
        if deps_.refreshTourValue ~= nil then deps_.refreshTourValue() end
        NoteAuthFarmRevision(data.farmRevision, "harvest")
    else
        if data.state ~= nil then ApplyState(data.state) end
        if data.farm ~= nil then
            EconomyCloudSystem.ForceSyncAuthFarm(data.farm, "harvest_failed")
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
        if deps_.showToast then deps_.showToast(data.message or "开包失败") end
    end
end

function EconomyCloudSystem.HandleSellHarvestedResponse(data)
    FinishRequest(data.requestId, "sell")
    if data.success then
        ApplyState(data.state)
        AudioSystem.PlaySFX("sell_coin")
        if deps_.showToast then deps_.showToast(data.message or "出售成功") end
    elseif deps_.showToast then
        if data.state ~= nil then ApplyState(data.state) end
        deps_.showToast(data.message or "出售失败")
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
    FinishRequest(data.requestId, "adReward")
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
