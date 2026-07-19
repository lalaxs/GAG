-- ============================================================================
-- 服务端核心经济行为
-- Grow A Garden
-- ============================================================================
-- 经济/农场玩法状态以 PlayerStateService 内存 session 为唯一运行时权威。
-- 云端只在登录加载和后台 flush 时作为持久化介质。
-- ============================================================================

local ServerEconomyActions = {}

local ServerCloudStore = require("server.server_cloud_store")
local SaveLoginReconcile = require("server.save_login_reconcile")
local SaveEconomyHealth = require("server.save_economy_health")
local ServerFarmState = require("server.server_farm_state")
local ServerEconomyState = require("server.server_economy_state")

local deps_ = {}

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

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
    local data = extra or {}
    data.success = false
    data.code = code
    data.message = message
    Send(connection, eventName, data)
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

local function BuildInitialEconomyState(options)
    return deps_.BuildInitialEconomyState(options)
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

local function RecordResponse(uid, recordKey, response)
    if deps_.RequestGuard ~= nil and deps_.RequestGuard.Record ~= nil then
        deps_.RequestGuard.Record(uid, recordKey, response)
    end
end

local function SafeRecordResponse(uid, recordKey, response)
    if deps_.RequestGuard == nil or deps_.RequestGuard.Record == nil then return end
    local ok, err = pcall(function()
        deps_.RequestGuard.Record(uid, recordKey, response)
    end)
    if ok ~= true then
        print("[PlayerState] request record failed uid=" .. tostring(uid) .. " err=" .. tostring(err))
    end
end

local function CommitSideEffects(uid, label, build)
    local c = serverCloud:BatchCommit(label)
    local ok, err = pcall(build, c)
    if ok ~= true then
        print("[PlayerState] side commit build failed label=" .. tostring(label) .. " err=" .. tostring(err))
        return
    end
    c:Commit({
        ok = function() end,
        error = function(_, reason)
            print("[PlayerState] side commit failed label=" .. tostring(label) .. " uid=" .. tostring(uid) .. " reason=" .. tostring(reason))
        end,
    })
end

local function BuildStatePatch(state, options)
    state = type(state) == "table" and state or {}
    options = options or {}
    local patch = {
        revision = state.revision,
        gold = state.gold,
        exp = state.exp,
        level = state.level,
        progression = state.progression,
        activity = state.activity,
        dailyTaskState = state.dailyTaskState,
        tutorial = state.tutorial,
    }
    if options.plantIndex ~= nil then
        patch.seedBag = { [options.plantIndex] = state.seedBag and state.seedBag[options.plantIndex] or 0 }
        patch.seedBagBuffs = { [options.plantIndex] = state.seedBagBuffs and state.seedBagBuffs[options.plantIndex] or 0 }
    end
    if options.harvestItem ~= nil then
        patch.harvestAdd = options.harvestItem
    end
    if options.seedPackId ~= nil then
        patch.seedPacks = { [options.seedPackId] = state.seedPacks and state.seedPacks[options.seedPackId] or 0 }
    end
    if options.collectedPlantIndex ~= nil then
        patch.collectedPlants = { [options.collectedPlantIndex] = true }
    end
    if options.activityReward ~= nil and options.activityReward.type == "dark_seed" and options.activityReward.plantIndex ~= nil then
        local plantIndex = options.activityReward.plantIndex
        patch.seedBag = patch.seedBag or {}
        patch.collectedPlants = patch.collectedPlants or {}
        patch.seedBag[plantIndex] = state.seedBag and state.seedBag[plantIndex] or 0
        patch.collectedPlants[plantIndex] = true
    end
    return patch
end

local function SendMutationResult(connection, eventName, result, fallbackRequestId, sendOverride, uid)
    local function send(data)
        if sendOverride ~= nil and uid ~= nil then
            return sendOverride(uid, connection, eventName, data)
        end
        return Send(connection, eventName, data)
    end
    result = type(result) == "table" and result or {}
    -- 仅在整体成功时下发 mutator response；flush 失败时绝不能把 success=true 的旧 response 发出去
    if result.success == true and type(result.response) == "table" then
        send(result.response)
        return
    end
    local response = type(result.response) == "table" and result.response or nil
    if response ~= nil and response.success ~= true then
        response.success = false
        if response.message == nil then response.message = result.message or "同步失败" end
        if response.code == nil then response.code = result.code end
        if response.retryable == nil then response.retryable = result.retryable == true end
        if response.requestId == nil then response.requestId = fallbackRequestId end
        send(response)
        return
    end
    local requestId = fallbackRequestId
    if response ~= nil and response.requestId ~= nil then
        requestId = response.requestId
    end
    send({
        success = false,
        message = result.message or "同步失败",
        code = result.code,
        retryable = result.retryable == true,
        requestId = requestId,
    })
end

function ServerEconomyActions.RequestEconomyState(uid, connection)
    local canonicalUid = ServerCloudStore.GetCanonicalUidKey(uid)
    print(string.format("[存档] 请求经济状态 userId=%s cloudId=%s", tostring(canonicalUid), tostring(ServerCloudStore.CloudPlayerId(uid))))
    -- 进游戏热路径不跑 Ensure，直接 Load（统一存档优先）
    deps_.PlayerStateService.Load(uid, function(session, err)
        if session == nil then
            Send(connection, deps_.Shared.EVENTS.ECONOMY_STATE_RESPONSE, {
                success = false,
                retryable = true,
                message = "同步失败",
            })
            print("[PlayerState] request economy load failed uid=" .. tostring(canonicalUid) .. " err=" .. tostring(err))
            return
        end
        Send(connection, deps_.Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = session.economy })
    end)
end

function ServerEconomyActions.BuySeed(uid, plantIndex, _price, connection, count, requestId, refreshId, recordKey)
    uid = CloudUid(uid)
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

                deps_.PlayerStateService.MutateEconomy(uid, "buy_seed", function(state)
                    local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
                    local buyCount = math.min(count, available)
                    if buyCount <= 0 then
                        return { success = false, response = { success = false, message = "库存不足", requestId = requestId, state = state } }
                    end
                    local totalPrice = price * buyCount
                    if state.gold < totalPrice then
                        buyCount = price > 0 and math.min(buyCount, math.floor(state.gold / price)) or buyCount
                        totalPrice = price * buyCount
                    end
                    if buyCount <= 0 then
                        return { success = false, response = { success = false, message = "金币不足", requestId = requestId, state = state } }
                    end
                    state.gold = state.gold - totalPrice
                    state.seedBag[plantIndex] = owned + buyCount
                    local remainingStock = math.max(0, available - buyCount)
                    return {
                        success = true,
                        response = {
                            success = true,
                            message = "购买成功 x" .. tostring(buyCount),
                            requestId = requestId,
                            plantIndex = plantIndex,
                            price = totalPrice,
                            count = buyCount,
                            state = state,
                            shopPatch = {
                                refreshId = shop.refreshId,
                                stock = { [plant.name] = remainingStock },
                                serverTime = Now(),
                                nextRefreshAt = shop.nextRefreshAt,
                                nextRefreshIn = shop.nextRefreshIn,
                            },
                        },
                    }
                end, function(result)
                    local response = result and result.response or nil
                    if result ~= nil and result.success == true and type(response) == "table" then
                        CommitSideEffects(uid, "全服商店购买种子", function(c)
                            c:QuotaAdd(deps_.globalShopUid, quotaKey, response.count or 1, maxStock)
                            deps_.RequestGuard.AddToCommit(c, uid, recordKey, response)
                        end)
                        if deps_.ServerShop ~= nil then
                            if deps_.ServerShop.ApplyLocalSoldDelta ~= nil then
                                deps_.ServerShop.ApplyLocalSoldDelta(shop.refreshId, plantIndex, response.count or 1)
                            elseif deps_.ServerShop.InvalidateAvailableShopCache ~= nil then
                                deps_.ServerShop.InvalidateAvailableShopCache("buy_seed_success")
                            end
                        end
                        Send(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, response)
                        return
                    end
                    deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, response or { success = false, message = result and result.message or "购买失败", requestId = requestId })
                end)
            end,
            error = function(_, reason)
                local reasonText = tostring(reason or "unknown")
                -- 已限流时禁止再拉全量库存（每种子一次 QuotaGet），否则会放大限流。
                if reasonText:find("read rate limit exceeded", 1, true) then
                    Send(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, {
                        success = false,
                        retryable = true,
                        message = "商店库存繁忙，请稍后再试",
                        requestId = requestId,
                    })
                    return
                end
                deps_.SendFullAvailableSeedShop(connection, deps_.Shared.EVENTS.BUY_SEED_RESPONSE, {
                    success = false,
                    message = "库存读取失败: " .. reasonText,
                    requestId = requestId,
                    retryable = true,
                })
            end,
        })
    end)
end

function ServerEconomyActions.ClearPlayerSave(uid, connection, requestId, recordKey, options)
    options = options or {}
    uid = CloudUid(uid)
    SaveLoginReconcile.ClearSession(uid)
    SaveEconomyHealth.ClearSession(uid)

    local function CommitClearedSave(clearedFarmRevision)
        local now = Now()
        local canonicalUid = ServerCloudStore.GetCanonicalUidKey(uid)
        local economyState = ServerCloudStore.StampOwner(BuildInitialEconomyState({ saveEpoch = now, cleared = true }), canonicalUid)
        economyState.revision = math.max(1, math.floor(tonumber(economyState.revision or 0) or 0) + 1)
        economyState.force = true
        economyState.cleared = true
        local farmState = ServerCloudStore.StampOwner(NormalizeFarmState(nil), canonicalUid)
        farmState.revision = math.max(1, math.floor(tonumber(clearedFarmRevision or 1) or 1))
        farmState.updatedAt = now
        local socialSave = { visitablePlotIndex = 1, updatedAt = now }
        local reconcileMarker = {
            version = 3,
            at = now,
            cleared = true,
            repaired = true,
            migrated = 0,
            saveEpoch = now,
            saveSchemaVersion = ServerEconomyState.SAVE_SCHEMA_VERSION,
        }
        local response = {
            success = true,
            message = "游戏存档已清除",
            requestId = requestId,
            state = economyState,
            farm = farmState,
            socialSave = socialSave,
            force = true,
            cleared = true,
        }
        deps_.PlayerStateService.Reset(uid, economyState, farmState, socialSave)

        local scoreKeys = {
            deps_.Shared.KEYS.PLAYER_STATE,
            deps_.Shared.KEYS.ECONOMY_STATE,
            deps_.Shared.KEYS.ECONOMY_LEDGER,
            deps_.Shared.KEYS.AUTH_FARM_STATE,
            deps_.Shared.KEYS.SOCIAL_SAVE,
        }
        if options.includeCommission == true and options.commissionStateKey ~= nil then
            scoreKeys[#scoreKeys + 1] = options.commissionStateKey
        end
        local uniqueScoreKeys = {}
        local uniqueScoreKeyList = {}
        for _, scoreKey in ipairs(scoreKeys) do
            if scoreKey ~= nil and uniqueScoreKeys[scoreKey] ~= true then
                uniqueScoreKeys[scoreKey] = true
                uniqueScoreKeyList[#uniqueScoreKeyList + 1] = scoreKey
            end
        end
        scoreKeys = uniqueScoreKeyList
        local listKeys = {
            deps_.Shared.KEYS.GARDEN_SNAPSHOT,
            deps_.Shared.KEYS.STEAL_LOGS,
            deps_.Shared.KEYS.RECENT_VISITORS,
            deps_.Shared.KEYS.SEED_REWARDS,
            deps_.Shared.KEYS.FRIENDS,
            deps_.Shared.KEYS.FRIEND_REQUESTS,
            deps_.Shared.KEYS.SOCIAL_NOTICES,
            deps_.Shared.KEYS.GIFT_SENT_TARGETS,
        }
        local uniqueListKeys = {}
        local uniqueListKeyList = {}
        for _, listKey in ipairs(listKeys) do
            if listKey ~= nil and uniqueListKeys[listKey] ~= true then
                uniqueListKeys[listKey] = true
                uniqueListKeyList[#uniqueListKeyList + 1] = listKey
            end
        end

        local purgePending = #scoreKeys + #uniqueListKeyList
        local purgeFinished = false
        local purgeFailed = false
        local function afterPurge(success)
            if purgeFinished then return end
            if success ~= true then purgeFailed = true end
            purgePending = purgePending - 1
            if purgePending > 0 then return end
            purgeFinished = true
            if purgeFailed then
                SendError(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, "CLEAR_SAVE_FAILED", "清除旧存档失败，请稍后重试", { requestId = requestId })
                return
            end
            local cloudUid = CloudUid(uid)
            if cloudUid == nil then
                SendError(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, "CLEAR_SAVE_FAILED", "清除存档失败", { requestId = requestId })
                return
            end
            local PlayerSaveAssemble = require("server.player_save_assemble")
            local unifiedDoc = PlayerSaveAssemble.BuildDoc(economyState, farmState, math.max(
                tonumber(economyState.revision or 0) or 0,
                tonumber(farmState.revision or 0) or 0
            ), canonicalUid)
            unifiedDoc.cleared = true
            local c = serverCloud:BatchCommit("清除游戏存档")
            ---@diagnostic disable-next-line: param-type-mismatch
            c:ScoreSet(cloudUid, deps_.Shared.KEYS.PLAYER_STATE, unifiedDoc)
            ---@diagnostic disable-next-line: param-type-mismatch
            c:ScoreSet(cloudUid, deps_.Shared.KEYS.SOCIAL_SAVE, socialSave)
            ---@diagnostic disable-next-line: param-type-mismatch
            c:ScoreSet(cloudUid, deps_.Shared.KEYS.SAVE_UID_RECONCILED, reconcileMarker)
            deps_.RequestGuard.AddToCommit(c, uid, recordKey, response)
            c:Commit({
                ok = function()
                    print(string.format("[存档] 清档完成 uid=%s farmRevision=%d schema=%s epoch=%s", tostring(canonicalUid), farmState.revision, tostring(economyState.saveSchemaVersion), tostring(economyState.saveEpoch)))
                    Send(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, response)
                end,
                error = function(_, reason)
                    print("[存档] 云端清档失败: " .. tostring(reason))
                    SendError(connection, deps_.Shared.EVENTS.CLEAR_SAVE_RESPONSE, "CLEAR_SAVE_FAILED", "清除存档失败", { requestId = requestId })
                end,
            })
        end
        for _, scoreKey in ipairs(scoreKeys) do
            ServerCloudStore.DeleteScoreAllCandidates(uid, scoreKey, afterPurge)
        end
        for _, listKey in ipairs(uniqueListKeyList) do
            ServerCloudStore.DeleteListAllCandidates(uid, listKey, afterPurge)
        end
    end

    -- 清档前读农场 revision：优先统一档
    ServerCloudStore.ReadPlayerScore(uid, deps_.Shared.KEYS.PLAYER_STATE, {
        requireOwner = true,
        logLabel = "清档前统一档",
    }, function(doc)
        local bestFarm = type(doc) == "table" and doc.farm or nil
        local function finish(farm)
            local nextRevision = 1
            if type(farm) == "table" then
                nextRevision = math.max(1, math.floor(tonumber(farm.revision or 0) or 0) + 1)
            end
            CommitClearedSave(nextRevision)
        end
        if type(bestFarm) == "table" then
            finish(bestFarm)
            return
        end
        ServerCloudStore.ReadBestScore(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
            normalize = NormalizeFarmState,
            score = ServerFarmState.ScoreFarmState,
            logLabel = "清档前农场",
        }, function(legacyFarm)
            finish(legacyFarm)
        end)
    end)
end

function ServerEconomyActions.PlantSeedAuthority(uid, payload, connection, sendOverride)
    uid = CloudUid(uid)
    payload = payload or {}
    local plantIndex = NormalizePlantIndex(payload.plantIndex)
    if plantIndex == nil then
        SendError(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, "INVALID_PLANT", "作物配置不存在", { requestId = payload.requestId })
        return
    end
    payload.plantIndex = plantIndex
    payload.plotIndex = NormalizePlotIndex(payload.plotIndex)
    payload.localPos = NormalizeLocalPos(payload.localPos)

    deps_.PlayerStateService.MutateEconomyAndFarm(uid, "plant_seed", function(state, farmState)
        local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
        if owned <= 0 then
            print(string.format("[播种请求][服务端] 拒绝：没有种子 uid=%s requestId=%s plant=%s owned=%s", tostring(uid), tostring(payload.requestId), tostring(plantIndex), tostring(owned)))
            return { success = false, response = { success = false, message = "没有该种子", requestId = payload.requestId, retryable = true, farm = farmState } }
        end
        local plot = GetFarmPlot(farmState, payload.plotIndex)
        if #plot.plants >= deps_.GetMaxCropsPerPlot() then
            print(string.format("[播种请求][服务端] 拒绝：地块已满 uid=%s requestId=%s plot=%s count=%d", tostring(uid), tostring(payload.requestId), tostring(payload.plotIndex), #plot.plants))
            return { success = false, response = { success = false, message = "这块田地已满", requestId = payload.requestId, retryable = true, farm = farmState } }
        end
        local buffCount = tonumber(state.seedBagBuffs[plantIndex] or 0) or 0
        local seedBuff = buffCount > 0 and 0.01 or 0
        local crop = deps_.BuildAuthoritativeCrop(uid, payload, seedBuff, deps_.GetServerMutationTalentBonus(state))
        if crop == nil then
            return { success = false, response = { success = false, message = "作物配置不存在", requestId = payload.requestId, retryable = true, farm = farmState } }
        end
        state.seedBag[plantIndex] = owned - 1
        if buffCount > 0 then state.seedBagBuffs[plantIndex] = buffCount - 1 end
        state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
        state.tutorial.plantGuideDone = true
        state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
        state.dailyTaskState.progress.plant = math.min(99, (state.dailyTaskState.progress.plant or 0) + 1)
        table.insert(plot.plants, crop)
        deps_.SyncProgressionTourValueFromFarm(state, farmState)
        return {
            success = true,
            sideState = state,
            response = {
                success = true,
                message = "播种确认",
                requestId = payload.requestId,
                plantIndex = plantIndex,
                plotIndex = payload.plotIndex,
                localPos = payload.localPos,
                seedBuff = seedBuff,
                crop = crop,
                farmPatch = { type = "addCrop", plotIndex = payload.plotIndex, crop = crop },
                statePatch = BuildStatePatch(state, { plantIndex = plantIndex }),
                farmRevision = farmState.revision,
            },
        }
    end, function(result)
        local response = result and result.response or nil
        if result ~= nil and result.success == true and type(response) == "table" then
            if sendOverride ~= nil then
                sendOverride(uid, connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, response)
            else
                Send(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, response)
            end
            SafeRecordResponse(uid, payload._requestRecordKey, response)
            CommitSideEffects(uid, "播种排行榜更新", function(c)
                local sideState = result.sideState or response.statePatch or {}
                deps_.AddTourRankCommit(c, uid, sideState)
                deps_.AddActivityRankCommit(c, uid, sideState)
            end)
            return
        end
        SendMutationResult(connection, deps_.Shared.EVENTS.PLANT_SEED_RESPONSE, result, payload.requestId, sendOverride, uid)
    end)
end

function ServerEconomyActions.HarvestCropAuthority(uid, payload, connection, sendOverride)
    uid = CloudUid(uid)
    payload = payload or {}

    deps_.PlayerStateService.MutateEconomyAndFarm(uid, "harvest_crop", function(state, farmState)
        local crop, plotIndex, cropIndex = deps_.FindFarmCropFromHarvestPayload(farmState, payload)
        local function failure(message, extra, opts)
            opts = opts or {}
            local data = extra or {}
            data.success = false
            data.message = message
            data.requestId = payload.requestId
            data.retryable = opts.retryable ~= false
            -- 仅疑似两端农场不一致时才拉 FullSync；常规失败附带 farm 让客户端软对齐，避免风暴。
            if opts.needsFullSync == true then
                data.needsFullSync = true
            else
                data.farm = farmState
            end
            return { success = false, response = data }
        end
        if crop == nil then
            return failure("作物不存在或已收获", nil, { needsFullSync = false })
        end
        deps_.RefreshAuthCrop(crop)
        print(string.format("[权威收获] 请求 requestId=%s uid=%s plot=%s cropIndex=%s cropId=%s mature=%s", tostring(payload.requestId), tostring(uid), tostring(plotIndex), tostring(cropIndex), tostring(crop.cropId or crop.serverCropId), tostring(crop.mature)))
        if crop.harvested == true then
            return failure("这株作物已经收获过了", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
        end
        if crop.mature ~= true then
            return failure("作物尚未成熟", { cropId = crop.cropId or crop.serverCropId, plotIndex = plotIndex, cropIndex = cropIndex })
        end

        state.harvested = state.harvested or {}
        local harvestBagCapacity = deps_.GetHarvestBagCapacityFromState(state)
        if #(state.harvested) >= harvestBagCapacity then
            return failure("背包已满，出售作物或点天赋扩容", {
                bagCount = #state.harvested,
                bagCapacity = harvestBagCapacity,
            }, { retryable = false })
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
        local plot = GetFarmPlot(farmState, plotIndex)
        table.remove(plot.plants, cropIndex)
        deps_.SyncProgressionTourValueFromFarm(state, farmState)
        return {
            success = true,
            sideState = state,
            response = {
                success = true,
                message = "收获确认",
                requestId = payload.requestId,
                plotIndex = plotIndex,
                cropIndex = cropIndex,
                cropId = crop.cropId or crop.serverCropId or payload.cropId,
                crop = harvestItem,
                farmPatch = { type = "removeCrop", plotIndex = plotIndex, cropIndex = cropIndex, cropId = crop.cropId or crop.serverCropId or payload.cropId },
                droppedPack = droppedPack,
                droppedPackName = droppedPack ~= nil and deps_.GameConfig.SEED_PACK_CONFIG[droppedPack] and deps_.GameConfig.SEED_PACK_CONFIG[droppedPack].packName or nil,
                activityReward = activityReward,
                exp = exp,
                statePatch = BuildStatePatch(state, {
                    harvestItem = harvestItem,
                    seedPackId = droppedPack,
                    collectedPlantIndex = crop.plantIndex,
                    activityReward = activityReward,
                }),
                farmRevision = farmState.revision,
            },
        }
    end, function(result)
        local response = result and result.response or nil
        if result ~= nil and result.success == true and type(response) == "table" then
            if sendOverride ~= nil then
                sendOverride(uid, connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
            else
                Send(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, response)
            end
            SafeRecordResponse(uid, payload._requestRecordKey, response)
            CommitSideEffects(uid, "收获排行榜更新", function(c)
                local sideState = result.sideState or response.statePatch or {}
                deps_.AddTourRankCommit(c, uid, sideState)
                deps_.AddActivityRankCommit(c, uid, sideState)
            end)
            return
        end
        SendMutationResult(connection, deps_.Shared.EVENTS.HARVEST_CROP_RESPONSE, result, payload.requestId, sendOverride, uid)
    end)
end

function ServerEconomyActions.OpenSeedPackAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local packId = tostring(payload.packId or "")
    local requestedCount = NormalizePositiveCount(payload.count or 1, deps_.maxOpenPackCount)
    local openAll = payload.openAll == true
    if not deps_.IsValidPackId(packId) then
        SendError(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, "INVALID_PACK", "种子包不存在", { requestId = payload.requestId })
        return
    end
    local packCfg = deps_.GameConfig.SEED_PACK_CONFIG[packId]

    deps_.PlayerStateService.MutateEconomy(uid, "open_seed_pack", function(state)
        local owned = tonumber(state.seedPacks[packId] or 0) or 0
        local openCount = openAll and owned or math.min(requestedCount, owned)
        if openCount <= 0 then
            return { success = false, response = { success = false, message = "暂无可开启的种子包", requestId = payload.requestId, state = state } }
        end
        local results = {}
        for _ = 1, openCount do
            for _ = 1, math.max(1, tonumber(packCfg.onceOpenCount or 1) or 1) do
                local seedId = deps_.RollSeedFromPack(packCfg)
                results[#results + 1] = { seedId = seedId, packId = packId, rollPackId = packId, seedBuff = packCfg.seedBuff or 0, isNew = state.collectedPlants[seedId] ~= true, isPity = false }
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
        local title = openCount > 1 and (packCfg.packName .. " x" .. openCount) or packCfg.packName
        return { success = true, response = { success = true, message = "开包成功", requestId = payload.requestId, packId = packId, title = title, results = results, openedCount = openCount, openAll = openAll, state = state } }
    end, function(result)
        local response = result and result.response or nil
        if result ~= nil and result.success == true and type(response) == "table" then
            RecordResponse(uid, payload._requestRecordKey, response)
            Send(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, response)
            return
        end
        SendMutationResult(connection, deps_.Shared.EVENTS.OPEN_SEED_PACK_RESPONSE, result, payload.requestId)
    end)
end

function ServerEconomyActions.SellHarvested(uid, sellMode, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    if not deps_.IsValidSellMode(sellMode) then
        SendError(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, "INVALID_SELL_MODE", "出售方式无效", { requestId = payload.requestId })
        return
    end
    deps_.PlayerStateService.MutateEconomy(uid, "sell", function(state)
        local harvested = state.harvested or {}
        local sold = {}
        local remain = {}
        local total = 0
        local targetIndex = tonumber(payload.index or 0) or 0
        local filter = payload.filter or {}
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
            local shouldSell = sellMode == "all" or (sellMode == "index" and index == targetIndex) or (sellMode == "filter" and MatchesFilter(item))
            if shouldSell then
                sold[#sold + 1] = item
                total = total + math.max(0, math.floor(tonumber(item.price or 0) or 0))
            else
                remain[#remain + 1] = item
            end
        end
        if #sold <= 0 then
            return { success = false, response = { success = false, message = "没有可出售作物", requestId = payload.requestId, state = state } }
        end
        state.harvested = remain
        state.gold = state.gold + total
        state.dailyTaskState = NormalizeDailyTaskState(state.dailyTaskState)
        state.dailyTaskState.progress.sell = math.min(99, (state.dailyTaskState.progress.sell or 0) + 1)
        return { success = true, response = { success = true, message = "出售成功，获得金币 " .. total, requestId = payload.requestId, total = total, count = #sold, state = state } }
    end, function(result)
        local response = result and result.response or nil
        if result ~= nil and result.success == true and type(response) == "table" then
            RecordResponse(uid, payload._requestRecordKey, response)
            CommitSideEffects(uid, "出售收入排行", function(c)
                deps_.AddIncomeRankCommit(c, uid, response.total or 0)
            end)
            Send(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, response)
            return
        end
        SendMutationResult(connection, deps_.Shared.EVENTS.SELL_HARVESTED_RESPONSE, result, payload.requestId)
    end)
end

return ServerEconomyActions
