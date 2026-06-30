-- ============================================================================
-- 服务端核心经济行为
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的经济状态请求、购买、清档、播种、收获、开包和出售权威逻辑。
-- ============================================================================

local ServerEconomyActions = {}

local deps_ = {}

function ServerEconomyActions.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function SendError(connection, eventName, code, message, extra)
    deps_.SendError(connection, eventName, code, message, extra)
end

local function NormalizePlantIndex(value)
    return deps_.NormalizePlantIndex(value)
end

local function NormalizePositiveCount(value, maxValue)
    return deps_.NormalizePositiveCount(value, maxValue)
end

local function NormalizePlotIndex(value)
    return deps_.NormalizePlotIndex(value)
end

local function NormalizeLocalPos(value)
    return deps_.NormalizeLocalPos(value)
end

local function NormalizeEconomyState(state)
    return deps_.NormalizeEconomyState(state)
end

local function BuildInitialEconomyState()
    return deps_.BuildInitialEconomyState()
end

local function NormalizeFarmState(state)
    return deps_.NormalizeFarmState(state)
end

local function GetFarmPlot(state, plotIndex)
    return deps_.GetFarmPlot(state, plotIndex)
end

local function NormalizeDailyTaskState(daily)
    return deps_.NormalizeDailyTaskState(daily)
end

local function NextRevision(state)
    deps_.NextRevision(state)
end

local function AddTourRankCommit(commit, uid, state)
    deps_.AddTourRankCommit(commit, uid, state)
end

local function AddActivityRankCommit(commit, uid, state)
    deps_.AddActivityRankCommit(commit, uid, state)
end

function ServerEconomyActions.RequestEconomyState(uid, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = scores[deps_.Shared.KEYS.ECONOMY_STATE]
            if type(state) ~= "table" then
                state = BuildInitialEconomyState()
                serverCloud:Set(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            else
                state = NormalizeEconomyState(state)
            end
            Send(connection, deps_.Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
        error = function()
            local state = BuildInitialEconomyState()
            serverCloud:Set(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            Send(connection, deps_.Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
    })
end

function ServerEconomyActions.BuySeed(uid, plantIndex, _price, connection, count, requestId, refreshId)
    plantIndex = NormalizePlantIndex(plantIndex)
    count = NormalizePositiveCount(count or 1)
    if plantIndex == nil then
        SendError(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, "INVALID_PLANT", "种子配置不存在", { requestId = requestId })
        return
    end
    local plant = deps_.GameConfig.PLANTS[plantIndex]
    local price = math.max(0, math.floor(tonumber(plant.seedPrice or 0) or 0))
    deps_.EnsureSeedShopState(function(shop)
        if refreshId ~= nil and math.floor(tonumber(refreshId or 0) or 0) ~= shop.refreshId then
            deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "商店已刷新，请重新购买", requestId = requestId })
            return
        end
        local maxStock = math.max(0, math.floor(tonumber(shop.stock[plant.name] or 0) or 0))
        if maxStock <= 0 then
            deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄", requestId = requestId })
            return
        end

        local quotaKey = deps_.BuildSeedShopQuotaKey(shop.refreshId, plantIndex)
        serverCloud.quota:Get(deps_.globalShopUid, quotaKey, {
            ok = function(rows)
                local quotaRow = rows and rows[1]
                local soldCount = math.max(0, math.floor(tonumber(quotaRow and quotaRow.value or 0) or 0))
                local available = math.max(0, maxStock - soldCount)
                if available <= 0 then
                    deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄", requestId = requestId })
                    deps_.BroadcastFullAvailableSeedShop()
                    return
                end

                serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
                    ok = function(scores)
                        local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                        local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
                        local buyCount = math.min(count, available)
                        if buyCount <= 0 then
                            deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "库存不足", requestId = requestId, state = state })
                            return
                        end
                        local totalPrice = price * buyCount
                        if state.gold < totalPrice then
                            buyCount = math.min(buyCount, math.floor(state.gold / price))
                            totalPrice = price * buyCount
                        end
                        if buyCount <= 0 then
                            deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "金币不足", requestId = requestId, state = state })
                            return
                        end

                        state.gold = state.gold - totalPrice
                        state.seedBag[plantIndex] = owned + buyCount
                        state.updatedAt = Now()
                        NextRevision(state)

                        local c = serverCloud:BatchCommit("全服商店原子购买种子")
                        c:QuotaAdd(deps_.globalShopUid, quotaKey, buyCount, maxStock)
                        c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                        c:Commit({
                            ok = function()
                                deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = true, message = "购买成功 x" .. tostring(buyCount), requestId = requestId, plantIndex = plantIndex, price = totalPrice, count = buyCount, state = state })
                                deps_.BroadcastFullAvailableSeedShop()
                            end,
                            error = function(_, reason)
                                deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "该种子已售罄或购买失败: " .. tostring(reason), requestId = requestId, state = state })
                                deps_.BroadcastFullAvailableSeedShop()
                            end,
                        })
                    end,
                    error = function(_, reason)
                        deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = requestId })
                    end,
                })
            end,
            error = function(_, reason)
                deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "库存读取失败: " .. tostring(reason), requestId = requestId })
            end,
        })
    end)
end

function ServerEconomyActions.ClearPlayerSave(uid, connection)
    local economyState = BuildInitialEconomyState()
    local farmState = NormalizeFarmState(nil)
    local c = serverCloud:BatchCommit("清除游戏存档")
    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, economyState)
    c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
    c:Commit({
        ok = function()
            Send(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, { success = true, message = "游戏存档已清除", state = economyState, farm = farmState })
        end,
        error = function(_, reason)
            print("[存档] 云端清档失败: " .. tostring(reason))
            SendError(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, "CLEAR_SAVE_FAILED", "清除存档失败")
        end,
    })
end

function ServerEconomyActions.PlantSeedAuthority(uid, payload, connection)
    payload = payload or {}
    local plantIndex = NormalizePlantIndex(payload.plantIndex)
    if plantIndex == nil then
        SendError(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, "INVALID_PLANT", "作物配置不存在", { requestId = payload.requestId })
        return
    end
    payload.plantIndex = plantIndex
    payload.plotIndex = NormalizePlotIndex(payload.plotIndex)
    payload.localPos = NormalizeLocalPos(payload.localPos)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
            if owned <= 0 then
                Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "没有该种子", state = state })
                return
            end
            local buffCount = tonumber(state.seedBagBuffs[plantIndex] or 0) or 0
            local seedBuff = 0
            if buffCount > 0 then seedBuff = 0.01 end
            local mutationBonus = deps_.GetServerMutationTalentBonus(state)

            serverCloud:Get(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
                ok = function(farmScores)
                    local farmState = NormalizeFarmState(farmScores[deps_.Shared.KEYS.AUTH_FARM_STATE])
                    local plot = GetFarmPlot(farmState, payload.plotIndex)
                    if #plot.plants >= deps_.GetMaxCropsPerPlot() then
                        Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "这块田地已满", requestId = payload.requestId, state = state })
                        return
                    end

                    local crop = deps_.BuildAuthoritativeCrop(uid, payload, seedBuff, mutationBonus)
                    if crop == nil then
                        Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "作物配置不存在", requestId = payload.requestId, state = state })
                        return
                    end

                    state.seedBag[plantIndex] = owned - 1
                    if buffCount > 0 then state.seedBagBuffs[plantIndex] = buffCount - 1 end
                    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
                    state.tutorial.plantGuideDone = true
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.plant = math.min(99, (state.dailyTaskState.progress.plant or 0) + 1)
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    deps_.SyncProgressionTourValueFromFarm(state, farmState)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)

                    local response = {
                        success = true,
                        message = "播种确认",
                        requestId = payload.requestId,
                        plantIndex = plantIndex,
                        plotIndex = payload.plotIndex,
                        localPos = payload.localPos,
                        seedBuff = seedBuff,
                        crop = crop,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("权威播种")
                    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
                    c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                    deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "播种失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
                error = function()
                    local farmState = NormalizeFarmState(nil)
                    local plot = GetFarmPlot(farmState, payload.plotIndex)
                    local crop = deps_.BuildAuthoritativeCrop(uid, payload, seedBuff, mutationBonus)
                    if crop == nil then
                        Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "作物配置不存在", requestId = payload.requestId, state = state })
                        return
                    end
                    state.seedBag[plantIndex] = owned - 1
                    if buffCount > 0 then state.seedBagBuffs[plantIndex] = buffCount - 1 end
                    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
                    state.tutorial.plantGuideDone = true
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.plant = math.min(99, (state.dailyTaskState.progress.plant or 0) + 1)
                    state.updatedAt = Now()
                    NextRevision(state)
                    table.insert(plot.plants, crop)
                    deps_.SyncProgressionTourValueFromFarm(state, farmState)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)
                    local response = {
                        success = true,
                        message = "播种确认",
                        requestId = payload.requestId,
                        plantIndex = plantIndex,
                        plotIndex = payload.plotIndex,
                        localPos = payload.localPos,
                        seedBuff = seedBuff,
                        crop = crop,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("首次权威播种")
                    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
                    c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                    deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "播种失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

function ServerEconomyActions.HarvestCropAuthority(uid, payload, connection)
    payload = payload or {}

    serverCloud:Get(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(farmScores)
            local farmState = NormalizeFarmState(farmScores[deps_.Shared.KEYS.AUTH_FARM_STATE])
            local function SendHarvestFailure(message, extra)
                local data = extra or {}
                data.success = false
                data.message = message
                data.requestId = payload.requestId
                data.farm = farmState
                print(string.format("[权威收获] 拒绝 requestId=%s cropId=%s plot=%s cropIndex=%s reason=%s", tostring(payload.requestId), tostring(payload.cropId), tostring(payload.plotIndex), tostring(payload.cropIndex), tostring(message)))
                Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, data)
            end
            local crop, plotIndex, cropIndex = deps_.FindFarmCropFromHarvestPayload(farmState, payload)
            if crop == nil then
                SendHarvestFailure("作物不存在或已收获")
                return
            end
            deps_.RefreshAuthCrop(crop)
            print(string.format("[权威收获] 请求 requestId=%s uid=%s plot=%s cropIndex=%s cropId=%s now=%d plantedAt=%s matureAt=%s elapsed=%.2f growTime=%.2f mature=%s",
                tostring(payload.requestId),
                tostring(uid),
                tostring(plotIndex),
                tostring(cropIndex),
                tostring(crop.cropId or crop.serverCropId),
                Now(),
                tostring(crop.plantedAt),
                tostring(crop.matureAt),
                tonumber(crop.elapsed or 0) or 0,
                tonumber(crop.growTime or 0) or 0,
                tostring(crop.mature)))
            if crop.harvested == true then
                SendHarvestFailure("这株作物已经收获过了", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
                return
            end
            if crop.mature ~= true then
                SendHarvestFailure("作物尚未成熟", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
                return
            end

            serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
                ok = function(scores)
                    local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                    state.harvested = state.harvested or {}
                    local harvestBagCapacity = deps_.GetHarvestBagCapacityFromState(state)
                    if #(state.harvested) >= harvestBagCapacity then
                        SendHarvestFailure("背包已满，出售作物或点天赋扩容", {
                            state = state,
                            cropId = crop.cropId or crop.serverCropId,
                            plotIndex = plotIndex,
                            cropIndex = cropIndex,
                            bagCount = #state.harvested,
                            bagCapacity = harvestBagCapacity,
                        })
                        return
                    end

                    local harvestItem = {
                        name = crop.name,
                        price = crop.price,
                        sightValue = crop.sightValue,
                        rarity = crop.rarity,
                        plantIndex = crop.plantIndex,
                        weight = crop.weight,
                        baseWeight = crop.baseWeight,
                        weightTier = crop.weightTier,
                        weightMultiplier = crop.weightMultiplier,
                        mutation = crop.mutation,
                        localPos = crop.localPos,
                        cropId = crop.cropId,
                    }
                    table.insert(state.harvested, harvestItem)
                    state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
                    state.dailyTaskState.progress.harvest = math.min(99, (state.dailyTaskState.progress.harvest or 0) + 1)
                    local exp = deps_.AddServerHarvestExp(state, crop.rarity, crop.mutation and crop.mutation.priceMultiplier or 1.0)
                    local droppedPack = deps_.RollHarvestDropPack(crop.rarity)
                    if droppedPack ~= nil and deps_.GameConfig.SEED_PACK_CONFIG[droppedPack] ~= nil then
                        state.seedPacks[droppedPack] = (tonumber(state.seedPacks[droppedPack] or 0) or 0) + 1
                    end
                    local activityReward = deps_.ApplyActivityHarvestReward(state, harvestItem)
                    state.collectedPlants = state.collectedPlants or {}
                    if crop.plantIndex ~= nil then state.collectedPlants[crop.plantIndex] = true end
                    state.updatedAt = Now()
                    NextRevision(state)

                    local plot = GetFarmPlot(farmState, plotIndex)
                    table.remove(plot.plants, cropIndex)
                    deps_.SyncProgressionTourValueFromFarm(state, farmState)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)

                    local response = {
                        success = true,
                        message = "收获确认",
                        requestId = payload.requestId,
                        plotIndex = plotIndex,
                        cropIndex = cropIndex,
                        cropId = crop.cropId or crop.serverCropId or payload.cropId,
                        crop = harvestItem,
                        droppedPack = droppedPack,
                        droppedPackName = droppedPack ~= nil and deps_.GameConfig.SEED_PACK_CONFIG[droppedPack] and deps_.GameConfig.SEED_PACK_CONFIG[droppedPack].packName or nil,
                        activityReward = activityReward,
                        exp = exp,
                        state = state,
                    }
                    local c = serverCloud:BatchCommit("权威收获")
                    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    AddActivityRankCommit(c, uid, state)
                    c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                    deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                    c:Commit({
                        ok = function()
                            Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "收获失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "农场数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

function ServerEconomyActions.OpenSeedPackAuthority(uid, payload, connection)
    payload = payload or {}
    local packId = tostring(payload.packId or "")
    local requestedCount = NormalizePositiveCount(payload.count or 1, deps_.maxOpenPackCount)
    local openAll = payload.openAll == true
    if not deps_.IsValidPackId(packId) then
        SendError(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, "INVALID_PACK", "种子包不存在", { requestId = payload.requestId })
        return
    end
    local packCfg = deps_.GameConfig.SEED_PACK_CONFIG[packId]

    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedPacks[packId] or 0) or 0
            local openCount = openAll and owned or math.min(requestedCount, owned)
            if openCount <= 0 then
                Send(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "暂无可开启的种子包", requestId = payload.requestId, state = state })
                return
            end

            local results = {}
            for _ = 1, openCount do
                for _ = 1, math.max(1, tonumber(packCfg.onceOpenCount or 1) or 1) do
                    local seedId = deps_.RollSeedFromPack(packCfg)
                    results[#results + 1] = {
                        seedId = seedId,
                        packId = packId,
                        rollPackId = packId,
                        seedBuff = packCfg.seedBuff or 0,
                        isNew = state.collectedPlants[seedId] ~= true,
                        isPity = false,
                    }
                end
            end

            state.seedPacks[packId] = owned - openCount
            for _, result in ipairs(results) do
                local seedId = result.seedId
                state.seedBag[seedId] = (tonumber(state.seedBag[seedId] or 0) or 0) + 1
                if result.seedBuff ~= nil and result.seedBuff > 0 then
                    state.seedBagBuffs[seedId] = (tonumber(state.seedBagBuffs[seedId] or 0) or 0) + 1
                end
            end
            state.updatedAt = Now()
            NextRevision(state)

            local title = openCount > 1 and (packCfg.packName .. " x" .. openCount) or packCfg.packName
            local response = {
                success = true,
                message = "开包成功",
                requestId = payload.requestId,
                packId = packId,
                title = title,
                results = results,
                openedCount = openCount,
                openAll = openAll,
                state = state,
            }
            local c = serverCloud:BatchCommit("权威开包")
            c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
            c:Commit({
                ok = function()
                    Send(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, response)
                end,
                error = function(_, reason)
                    Send(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "开包失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

function ServerEconomyActions.SellHarvested(uid, sellMode, payload, connection)
    if not deps_.IsValidSellMode(sellMode) then
        SendError(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, "INVALID_SELL_MODE", "出售方式无效", { requestId = payload and payload.requestId })
        return
    end
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local harvested = state.harvested or {}
            local sold = {}
            local remain = {}
            local total = 0
            local targetIndex = tonumber(payload and payload.index or 0) or 0
            local filter = payload and payload.filter or {}

            local function IsBasicMutated(item)
                local mutation = item and item.mutation
                return mutation ~= nil and (mutation.sizePrefix ~= nil or mutation.colorMutation ~= nil)
            end
            local function IsSpecialMutated(item)
                local specials = item and item.mutation and item.mutation.specials
                return specials ~= nil and #specials > 0
            end
            local function MatchesFilter(item)
                local hasFilter = filter.basicMutation or filter.specialMutation or filter.giant
                if not hasFilter then return not IsBasicMutated(item) and not IsSpecialMutated(item) and item.weightTier ~= "Giant" end
                if filter.basicMutation and IsBasicMutated(item) then return true end
                if filter.specialMutation and IsSpecialMutated(item) then return true end
                if filter.giant and item.weightTier == "Giant" then return true end
                return false
            end

            for index, item in ipairs(harvested) do
                local shouldSell = false
                if sellMode == "all" then
                    shouldSell = true
                elseif sellMode == "index" then
                    shouldSell = index == targetIndex
                elseif sellMode == "filter" then
                    shouldSell = MatchesFilter(item)
                end
                if shouldSell then
                    sold[#sold + 1] = item
                    total = total + math.max(0, math.floor(tonumber(item.price or 0) or 0))
                else
                    remain[#remain + 1] = item
                end
            end

            if #sold <= 0 then
                Send(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "没有可出售作物", state = state })
                return
            end

            state.harvested = remain
            state.gold = state.gold + total
            state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
            state.dailyTaskState.progress.sell = math.min(99, (state.dailyTaskState.progress.sell or 0) + 1)
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "出售成功，获得金币 " .. total, requestId = payload and payload.requestId, total = total, count = #sold, state = state }
            local c = serverCloud:BatchCommit("权威出售")
            c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
            deps_.AddIncomeRankCommit(c, uid, total)
            deps_.RequestGuard.AddToCommit(c, uid, payload and payload._requestRecordKey, response)
            c:Commit({
                ok = function()
                    Send(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, response)
                end,
                error = function(_, reason)
                    Send(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "出售失败: " .. tostring(reason), state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason) })
        end,
    })
end

return ServerEconomyActions
