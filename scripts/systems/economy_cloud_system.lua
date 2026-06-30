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

local EconomyCloudSystem = {}

local deps_ = {}
local requests_ = RequestStateMachine.Create("economy", { timeout = 14.0 })
local initialRetryDelay_ = 2.0
local initialRetryTimer_ = 0
local noConnectionLogTimer_ = 0
local state_ = {
    serverEnabled = false,
    ready = false,
    authFarmReady = false,
    commissionsReady = false,
    pending = {},
    lastSyncText = "未同步",
    lastAuthFarmRevision = -1,
}

local function IsClientNetworkAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function IsAuthoritativeClient()
    -- 纯服务器游戏：客户端始终以服务端为权威。
    return true
end

local function BlockIfAuthoritativeNotReady(requireFarm)
    local ready = IsClientNetworkAvailable() and state_.ready == true and (requireFarm ~= true or state_.authFarmReady == true)
    if ready then return false end
    state_.lastSyncText = "同步中..."
    if deps_.showToast then deps_.showToast("正在同步服务器数据，请稍后") end
    return true
end

local function SendRequest(eventName, payload)
    if IsClientNetworkAvailable() then
        return Shared.SendToServer(eventName, payload)
    end
    return false
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

local function ApplyState(cloudState, options)
    if type(cloudState) ~= "table" then return false end
    options = options or {}
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
        deps_.ProgressionSystem.LoadSaveData(cloudState.progression)
        if options.silentEvents ~= true and deps_.onProgressionApplied then deps_.onProgressionApplied(cloudState.progression) end
    end
    if deps_.ActivitySystem and deps_.ActivitySystem.LoadSaveData and cloudState.activity ~= nil then
        deps_.ActivitySystem.LoadSaveData(cloudState.activity)
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

local function ApplyAuthoritativeFarm(farm, source)
    if type(farm) ~= "table" then return false end
    local revision = tonumber(farm.revision)
    if revision == nil then
        if (state_.lastAuthFarmRevision or -1) >= 0 then
            print(string.format("[经济同步] 忽略无 revision 的权威农场 source=%s latest=%d", tostring(source), state_.lastAuthFarmRevision or -1))
            return false
        end
        revision = -1
    end
    if revision >= 0 and revision <= (state_.lastAuthFarmRevision or -1) then
        print(string.format("[经济同步] 忽略重复或过期权威农场 source=%s revision=%d latest=%d", tostring(source), revision, state_.lastAuthFarmRevision or -1))
        return false
    end
    if revision >= 0 then
        state_.lastAuthFarmRevision = revision
    end
    if deps_.onAuthFarmReceived then deps_.onAuthFarmReceived(farm) end
    return true
end

function EconomyCloudSystem.Init(deps)
    deps_ = deps or {}
    state_.serverEnabled = IsClientNetworkAvailable()
    Shared.RegisterClientEvents()
    if network ~= nil and IsClientMode ~= nil and IsClientMode() then
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
    return IsClientNetworkAvailable() and state_.ready == true and (requireFarm ~= true or state_.authFarmReady == true)
end

function EconomyCloudSystem.IsInitialSyncReady()
    return state_.ready == true and state_.authFarmReady == true
end

local function NotifyInitialSyncProgress()
    if deps_.onInitialSyncProgress then deps_.onInitialSyncProgress(EconomyCloudSystem.IsInitialSyncReady(), state_) end
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

function EconomyCloudSystem.GetState()
    return state_
end

function EconomyCloudSystem.Update(dt)
    requests_:Update(function(record)
        requests_:SyncLegacyPending(state_.pending)
        state_.lastSyncText = "请求超时，正在重拉服务器数据"
        if deps_.showToast then deps_.showToast("服务器请求超时，正在重新同步") end
        print("[经济同步] 请求超时: " .. tostring(record.type) .. " " .. tostring(record.id))
        if record.type ~= "load" and record.type ~= "authFarm" then
            RequestAuthorityRefresh("timeout_" .. tostring(record.type))
        end
    end)
    if EconomyCloudSystem.IsInitialSyncReady() then return end
    initialRetryTimer_ = initialRetryTimer_ - (dt or 0)
    if not IsClientNetworkAvailable() then
        noConnectionLogTimer_ = noConnectionLogTimer_ - (dt or 0)
        if noConnectionLogTimer_ <= 0 then
            noConnectionLogTimer_ = 10.0
            print("[经济同步] 等待服务器连接后同步权威状态")
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
    if state_.authFarmReady == true and options.force ~= true then return true end
    if options.force == true then requests_:Cancel("authFarm") end
    if requests_:IsPending("authFarm") then return true end
    local payload = BeginRequest("authFarm", { reason = options.reason or "sync", userId = deps_.getUserId and deps_.getUserId() or nil })
    if SendRequest(Shared.EVENTS.REQUEST_AUTH_FARM, payload) then return true end
    FinishRequest(payload.requestId, "authFarm")
    return false
end

function EconomyCloudSystem.UploadState()
    state_.lastSyncText = IsClientNetworkAvailable() and "服务器权威" or "等待服务器"
    return false
end

function EconomyCloudSystem.RequestSeedShop()
    if IsClientNetworkAvailable() then
        return Shared.SendToServer(Shared.EVENTS.REQUEST_SEED_SHOP, {})
    end
    return false
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

function EconomyCloudSystem.PlantSeed(payload)
    if BlockIfAuthoritativeNotReady(true) then return false end
    payload = BeginRequest("plant", payload or {})
    if SendRequest(Shared.EVENTS.PLANT_SEED, payload) then return true end
    FinishRequest(payload.requestId, "plant")
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
    local payload = BeginRequest("sell", { mode = "all" })
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, payload) then return true end
    FinishRequest(payload.requestId, "sell")
    return false
end

function EconomyCloudSystem.SellBagItem(item)
    if BlockIfAuthoritativeNotReady(false) then return false end
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
        state_.lastSyncText = "已同步"
        print("[经济同步] 经济状态已同步")
        EconomyCloudSystem.RequestCommissions()
        NotifyInitialSyncProgress()
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
        print("[经济同步] 权威农场已同步")
        ApplyAuthoritativeFarm(data.farm, "authFarm")
        NotifyInitialSyncProgress()
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
        state_.ready = true
        state_.authFarmReady = true
        state_.commissionsReady = false
        ApplyState(data.state)
        state_.lastAuthFarmRevision = -1
        ApplyAuthoritativeFarm(data.farm, "clearSave")
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
        ApplyState(data.state)
        NoteAuthFarmRevision(data.farmRevision, "plant")
        if deps_.onPlantSeedConfirmed then deps_.onPlantSeedConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "播种失败") end
    end
end

function EconomyCloudSystem.HandleHarvestCropResponse(data)
    FinishRequest(data.requestId, "harvest")
    print(string.format("[经济同步] 收到收获响应 requestId=%s success=%s message=%s cropId=%s", tostring(data.requestId), tostring(data.success), tostring(data.message), tostring(data.cropId)))
    if data.success then
        ApplyState(data.state)
        NoteAuthFarmRevision(data.farmRevision, "harvest")
        if deps_.onHarvestCropConfirmed then deps_.onHarvestCropConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if data.farm ~= nil then
            ApplyAuthoritativeFarm(data.farm, "harvest_failed")
        else
            EconomyCloudSystem.RequestAuthFarm({ force = true, reason = "harvest_failed" })
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

function HandleGardenEconomyServerReady(eventType, eventData)
    EconomyCloudSystem.RequestState({ force = true, reason = "server_ready" })
    EconomyCloudSystem.RequestSeedShop()
    EconomyCloudSystem.RequestAuthFarm({ force = true, reason = "server_ready" })
    EconomyCloudSystem.RequestCommissions()
end

return EconomyCloudSystem
