-- ============================================================================
-- 云端权威经济同步系统
-- ============================================================================
-- 负责将金币、种子背包、收获背包、种子包同步到服务端，并接收服务端权威结果。
-- 现阶段用于主经济闭环落云；服务端操作成功后回写本地状态，UI 继续复用原有展示。
-- ============================================================================

local Shared = require("network.shared")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local RequestStateMachine = require("client.request_state_machine")

local EconomyCloudSystem = {}

local deps_ = {}
local requests_ = RequestStateMachine.Create("economy", { timeout = 14.0 })
local state_ = {
    serverEnabled = false,
    ready = false,
    authFarmReady = false,
    pending = {},
    lastSyncText = "未同步",
}

local function IsClientNetworkAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function IsAuthoritativeClient()
    return IsClientMode ~= nil and IsClientMode()
end

local function BlockIfAuthoritativeNotReady(requireFarm)
    if not IsAuthoritativeClient() then return false end
    local ready = state_.ready == true and (requireFarm ~= true or state_.authFarmReady == true)
    if IsClientNetworkAvailable() and ready then return false end
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

local function BuildState()
    return {
        gold = deps_.getGold and deps_.getGold() or 0,
        seedBag = deps_.InventorySystem and deps_.InventorySystem.GetSeedBag and deps_.InventorySystem.GetSeedBag() or {},
        seedBagBuffs = deps_.InventorySystem and deps_.InventorySystem.GetSeedBagBuffs and deps_.InventorySystem.GetSeedBagBuffs() or {},
        harvested = deps_.InventorySystem and deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or {},
        seedPacks = deps_.InventorySystem and deps_.InventorySystem.GetSeedPacks and deps_.InventorySystem.GetSeedPacks() or {},
        collectedPlants = deps_.InventorySystem and deps_.InventorySystem.GetCollectedPlants and deps_.InventorySystem.GetCollectedPlants() or {},
    }
end

local function ApplyState(cloudState)
    if type(cloudState) ~= "table" then return false end
    if deps_.WalletSystem and deps_.WalletSystem.SetBalance then
        deps_.WalletSystem.SetBalance(tonumber(cloudState.gold or 0) or 0)
    end
    if deps_.InventorySystem ~= nil then
        ReplaceTable(deps_.InventorySystem.GetSeedBag(), cloudState.seedBag)
        ReplaceTable(deps_.InventorySystem.GetSeedBagBuffs(), cloudState.seedBagBuffs)
        ReplaceTable(deps_.InventorySystem.GetHarvested(), cloudState.harvested)
        ReplaceTable(deps_.InventorySystem.GetSeedPacks(), cloudState.seedPacks)
        if deps_.InventorySystem.GetCollectedPlants ~= nil then
            ReplaceTable(deps_.InventorySystem.GetCollectedPlants(), cloudState.collectedPlants)
        end
    end
    if deps_.syncInventoryRefs then deps_.syncInventoryRefs() end
    if deps_.markDirty then deps_.markDirty() end
    EventBus.Emit(UIEvents.WALLET_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.SEEDPACK_CHANGED, { reason = "economy_state_applied" })
    EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "economy_state_applied" })
    return true
end

function EconomyCloudSystem.Init(deps)
    deps_ = deps or {}
    state_.serverEnabled = IsClientNetworkAvailable()
    Shared.RegisterClientEvents()
    if network ~= nil and IsClientMode ~= nil and IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.ECONOMY_STATE_RESPONSE, "HandleGardenEconomyStateResponse")
        SubscribeToEvent(Shared.EVENTS.AUTH_FARM_RESPONSE, "HandleGardenAuthFarmResponse")
        SubscribeToEvent(Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, "HandleGardenSaveEconomyStateResult")
        SubscribeToEvent(Shared.EVENTS.BUY_SEED_RESPONSE, "HandleGardenBuySeedResponse")
        SubscribeToEvent(Shared.EVENTS.CLEAR_SAVE_RESPONSE, "HandleGardenClearSaveResponse")
        SubscribeToEvent(Shared.EVENTS.PLANT_SEED_RESPONSE, "HandleGardenPlantSeedResponse")
        SubscribeToEvent(Shared.EVENTS.HARVEST_CROP_RESPONSE, "HandleGardenHarvestCropResponse")
        SubscribeToEvent(Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, "HandleGardenOpenSeedPackResponse")
        SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED_RESPONSE, "HandleGardenSellHarvestedResponse")
        SubscribeToEvent("ServerReady", "HandleGardenEconomyServerReady")
    end
end

function EconomyCloudSystem.IsAuthoritativeClient()
    return IsAuthoritativeClient()
end

function EconomyCloudSystem.IsReady(requireFarm)
    if not IsAuthoritativeClient() then return true end
    return IsClientNetworkAvailable() and state_.ready == true and (requireFarm ~= true or state_.authFarmReady == true)
end

function EconomyCloudSystem.IsBlocked(requireFarm)
    return BlockIfAuthoritativeNotReady(requireFarm)
end

function EconomyCloudSystem.GetState()
    return state_
end

function EconomyCloudSystem.Update(_dt)
    requests_:Update(function(record)
        requests_:SyncLegacyPending(state_.pending)
        state_.lastSyncText = "请求超时"
        if deps_.showToast then deps_.showToast("服务器请求超时，请稍后重试") end
        print("[经济同步] 请求超时: " .. tostring(record.type) .. " " .. tostring(record.id))
    end)
end

function EconomyCloudSystem.RequestState()
    local payload = BeginRequest("load", {})
    if SendRequest(Shared.EVENTS.REQUEST_ECONOMY_STATE, payload) then return true end
    FinishRequest(payload.requestId, "load")
    return false
end

function EconomyCloudSystem.RequestAuthFarm()
    local payload = BeginRequest("authFarm", {})
    if SendRequest(Shared.EVENTS.REQUEST_AUTH_FARM, payload) then return true end
    FinishRequest(payload.requestId, "authFarm")
    return false
end

function EconomyCloudSystem.UploadState()
    state_.lastSyncText = IsClientNetworkAvailable() and "服务器权威" or "本地预览"
    return false
end

function EconomyCloudSystem.BuySeed(plantIndex, price, count)
    if BlockIfAuthoritativeNotReady(false) then return false end
    local payload = BeginRequest("buy", { plantIndex = plantIndex, price = price, count = count or 1 })
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
    payload = BeginRequest("harvest", payload or {})
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

function EconomyCloudSystem.HandleEconomyStateResponse(data)
    FinishRequest(data.requestId, "load")
    if data.success and ApplyState(data.state) then
        state_.ready = true
        state_.lastSyncText = "已同步"
    elseif deps_.showToast then
        deps_.showToast(data.message or "经济数据读取失败")
    end
end

function EconomyCloudSystem.HandleAuthFarmResponse(data)
    FinishRequest(data.requestId, "authFarm")
    if data.success then
        state_.authFarmReady = true
        if deps_.onAuthFarmReceived then deps_.onAuthFarmReceived(data.farm) end
    elseif deps_.showToast then
        deps_.showToast(data.message or "权威农场读取失败")
    end
end

function EconomyCloudSystem.HandleSaveEconomyStateResult(data)
    state_.lastSyncText = data.success and "已同步" or "同步失败"
    if data.success then
        ApplyState(data.state)
    elseif deps_.showToast then
        deps_.showToast(data.message or "经济数据同步失败")
    end
end

function EconomyCloudSystem.HandleBuySeedResponse(data)
    FinishRequest(data.requestId, "buy")
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
        ApplyState(data.state)
        if deps_.onAuthFarmReceived then deps_.onAuthFarmReceived(data.farm) end
        if deps_.showToast then deps_.showToast(data.message or "游戏存档已清除") end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "清除存档失败") end
    end
end

function EconomyCloudSystem.HandlePlantSeedResponse(data)
    FinishRequest(data.requestId, "plant")
    if data.success then
        ApplyState(data.state)
        if deps_.onPlantSeedConfirmed then deps_.onPlantSeedConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "播种失败") end
    end
end

function EconomyCloudSystem.HandleHarvestCropResponse(data)
    FinishRequest(data.requestId, "harvest")
    if data.success then
        ApplyState(data.state)
        if deps_.onHarvestCropConfirmed then deps_.onHarvestCropConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "收获失败") end
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

function EconomyCloudSystem.ApplyAuthoritativeState(cloudState)
    return ApplyState(cloudState)
end

function HandleGardenEconomyStateResponse(eventType, eventData)
    EconomyCloudSystem.HandleEconomyStateResponse(Shared.ReadEventData(eventData))
end

function HandleGardenAuthFarmResponse(eventType, eventData)
    EconomyCloudSystem.HandleAuthFarmResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSaveEconomyStateResult(eventType, eventData)
    EconomyCloudSystem.HandleSaveEconomyStateResult(Shared.ReadEventData(eventData))
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

function HandleGardenEconomyServerReady(eventType, eventData)
    EconomyCloudSystem.RequestState()
    EconomyCloudSystem.RequestAuthFarm()
end

return EconomyCloudSystem
