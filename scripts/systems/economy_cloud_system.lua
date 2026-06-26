-- ============================================================================
-- 云端权威经济同步系统
-- ============================================================================
-- 负责将金币、种子背包、收获背包、种子包同步到服务端，并接收服务端权威结果。
-- 现阶段用于主经济闭环落云；服务端操作成功后回写本地状态，UI 继续复用原有展示。
-- ============================================================================

local Shared = require("network.shared")

local EconomyCloudSystem = {}

local deps_ = {}
local state_ = {
    serverEnabled = false,
    ready = false,
    pending = {},
    lastSyncText = "未同步",
}

local function IsClientNetworkAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function SendRequest(eventName, payload)
    if IsClientNetworkAvailable() then
        return Shared.SendToServer(eventName, payload)
    end
    return false
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
    if deps_.rebuildUI then deps_.rebuildUI() end
    if deps_.refreshUI then deps_.refreshUI(true) end
    return true
end

function EconomyCloudSystem.Init(deps)
    deps_ = deps or {}
    state_.serverEnabled = IsClientNetworkAvailable()
    Shared.RegisterClientEvents()
    if network ~= nil and IsClientMode ~= nil and IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.ECONOMY_STATE_RESPONSE, "HandleGardenEconomyStateResponse")
        SubscribeToEvent(Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, "HandleGardenSaveEconomyStateResult")
        SubscribeToEvent(Shared.EVENTS.BUY_SEED_RESPONSE, "HandleGardenBuySeedResponse")
        SubscribeToEvent(Shared.EVENTS.PLANT_SEED_RESPONSE, "HandleGardenPlantSeedResponse")
        SubscribeToEvent(Shared.EVENTS.HARVEST_CROP_RESPONSE, "HandleGardenHarvestCropResponse")
        SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED_RESPONSE, "HandleGardenSellHarvestedResponse")
        SubscribeToEvent("ServerReady", "HandleGardenEconomyServerReady")
    end
end

function EconomyCloudSystem.GetState()
    return state_
end

function EconomyCloudSystem.RequestState()
    state_.pending.load = true
    if SendRequest(Shared.EVENTS.REQUEST_ECONOMY_STATE, {}) then return true end
    state_.pending.load = false
    return false
end

function EconomyCloudSystem.UploadState()
    local payload = { state = BuildState() }
    state_.lastSyncText = "同步中..."
    if SendRequest(Shared.EVENTS.SAVE_ECONOMY_STATE, payload) then return true end
    state_.lastSyncText = "本地预览"
    return false
end

function EconomyCloudSystem.BuySeed(plantIndex, price)
    state_.pending.buy = true
    if SendRequest(Shared.EVENTS.BUY_SEED, { plantIndex = plantIndex, price = price }) then return true end
    state_.pending.buy = false
    return false
end

function EconomyCloudSystem.PlantSeed(payload)
    payload = payload or {}
    state_.pending.plant = payload
    if SendRequest(Shared.EVENTS.PLANT_SEED, payload) then return true end
    state_.pending.plant = nil
    return false
end

function EconomyCloudSystem.HarvestCrop(payload)
    payload = payload or {}
    state_.pending.harvest = payload
    if SendRequest(Shared.EVENTS.HARVEST_CROP, payload) then return true end
    state_.pending.harvest = nil
    return false
end

function EconomyCloudSystem.SellAllHarvested()
    state_.pending.sell = true
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, { mode = "all" }) then return true end
    state_.pending.sell = false
    return false
end

function EconomyCloudSystem.SellBagItem(item)
    local harvested = deps_.InventorySystem and deps_.InventorySystem.GetHarvested and deps_.InventorySystem.GetHarvested() or {}
    local targetIndex = 0
    for index, row in ipairs(harvested) do
        if row == item then targetIndex = index; break end
    end
    if targetIndex <= 0 then return false end
    state_.pending.sell = true
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, { mode = "index", index = targetIndex }) then return true end
    state_.pending.sell = false
    return false
end

function EconomyCloudSystem.SellHarvestedByFilter(filter)
    state_.pending.sell = true
    if SendRequest(Shared.EVENTS.SELL_HARVESTED, { mode = "filter", filter = filter or {} }) then return true end
    state_.pending.sell = false
    return false
end

function EconomyCloudSystem.HandleEconomyStateResponse(data)
    state_.pending.load = false
    if data.success and ApplyState(data.state) then
        state_.ready = true
        state_.lastSyncText = "已同步"
    elseif deps_.showToast then
        deps_.showToast(data.message or "经济数据读取失败")
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
    state_.pending.buy = false
    if data.success then
        ApplyState(data.state)
        if deps_.showToast then deps_.showToast(data.message or "购买成功") end
    elseif deps_.showToast then
        if data.state ~= nil then ApplyState(data.state) end
        deps_.showToast(data.message or "购买失败")
    end
end

function EconomyCloudSystem.HandlePlantSeedResponse(data)
    state_.pending.plant = nil
    if data.success then
        ApplyState(data.state)
        if deps_.onPlantSeedConfirmed then deps_.onPlantSeedConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "播种失败") end
    end
end

function EconomyCloudSystem.HandleHarvestCropResponse(data)
    state_.pending.harvest = nil
    if data.success then
        ApplyState(data.state)
        if deps_.onHarvestCropConfirmed then deps_.onHarvestCropConfirmed(data) end
    else
        if data.state ~= nil then ApplyState(data.state) end
        if deps_.showToast then deps_.showToast(data.message or "收获失败") end
    end
end

function EconomyCloudSystem.HandleSellHarvestedResponse(data)
    state_.pending.sell = false
    if data.success then
        ApplyState(data.state)
        if deps_.showToast then deps_.showToast(data.message or "出售成功") end
    elseif deps_.showToast then
        if data.state ~= nil then ApplyState(data.state) end
        deps_.showToast(data.message or "出售失败")
    end
end

function HandleGardenEconomyStateResponse(eventType, eventData)
    EconomyCloudSystem.HandleEconomyStateResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSaveEconomyStateResult(eventType, eventData)
    EconomyCloudSystem.HandleSaveEconomyStateResult(Shared.ReadEventData(eventData))
end

function HandleGardenBuySeedResponse(eventType, eventData)
    EconomyCloudSystem.HandleBuySeedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenPlantSeedResponse(eventType, eventData)
    EconomyCloudSystem.HandlePlantSeedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenHarvestCropResponse(eventType, eventData)
    EconomyCloudSystem.HandleHarvestCropResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSellHarvestedResponse(eventType, eventData)
    EconomyCloudSystem.HandleSellHarvestedResponse(Shared.ReadEventData(eventData))
end

function HandleGardenEconomyServerReady(eventType, eventData)
    EconomyCloudSystem.RequestState()
end

return EconomyCloudSystem
