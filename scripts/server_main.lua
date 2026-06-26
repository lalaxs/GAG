-- ============================================================================
-- 社交花园服务端入口
-- ============================================================================
-- 服务端权威处理：花园快照、作物成熟与可偷状态、排行榜、拜访、偷菜日志、种子赠送。
-- 客户端只上传可视快照；作物 ID、种植时间、成熟、被偷状态与奖励发放由服务端合并保存。
-- ============================================================================

local Shared = require("network.shared")

local scene_ = nil
local connections_ = {}
local connectionUsers_ = {}

local DAILY_STEAL_LIMIT = 10
local DAILY_GIFT_LIMIT = 5
local MAX_SOCIAL_ROWS = 20
local START_GOLD = 150
local SEED_STACK_MAX = 999

local function Now()
    return os and os.time and os.time() or 0
end

local function GetConnectionKey(connection)
    if connection == nil then return "" end
    return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
end

local function GetConnectionUserId(connection)
    if connection == nil or connection.identity == nil or connection.identity["user_id"] == nil then
        return nil
    end
    return connection.identity["user_id"]:GetInt64()
end

local function Send(connection, eventName, data)
    Shared.SendToClient(connection, eventName, data)
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = DeepCopy(item)
    end
    return result
end

local function CopyNumericKeyMap(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        local numericKey = tonumber(key)
        if numericKey ~= nil then
            result[math.floor(numericKey)] = value
        else
            result[key] = value
        end
    end
    return result
end

local function NormalizeEconomyState(state)
    state = type(state) == "table" and state or {}
    state.gold = math.max(0, math.floor(tonumber(state.gold or START_GOLD) or START_GOLD))
    state.seedBag = CopyNumericKeyMap(state.seedBag)
    state.seedBagBuffs = CopyNumericKeyMap(state.seedBagBuffs)
    state.harvested = type(state.harvested) == "table" and state.harvested or {}
    state.seedPacks = type(state.seedPacks) == "table" and state.seedPacks or {}
    state.collectedPlants = CopyNumericKeyMap(state.collectedPlants)
    state.updatedAt = Now()
    return state
end

local function BuildInitialEconomyState()
    return NormalizeEconomyState({
        gold = START_GOLD,
        seedBag = { [1] = 6, [21] = 4, [2] = 2 },
        seedBagBuffs = {},
        harvested = {},
        seedPacks = { pack_common = 1 },
    })
end

local function RequestEconomyState(uid, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = scores[Shared.KEYS.ECONOMY_STATE]
            if type(state) ~= "table" then
                state = BuildInitialEconomyState()
                serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state)
            else
                state = NormalizeEconomyState(state)
            end
            Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
        error = function()
            local state = BuildInitialEconomyState()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state)
            Send(connection, Shared.EVENTS.ECONOMY_STATE_RESPONSE, { success = true, state = state })
        end,
    })
end

local function SaveEconomyState(uid, state, connection)
    local nextState = NormalizeEconomyState(state)
    serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, nextState, {
        ok = function()
            Send(connection, Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, { success = true, state = nextState })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.SAVE_ECONOMY_STATE_RESULT, { success = false, message = "经济数据同步失败: " .. tostring(reason) })
        end,
    })
end

local function BuySeed(uid, plantIndex, price, connection)
    plantIndex = math.max(1, tonumber(plantIndex or 1) or 1)
    price = math.max(0, math.floor(tonumber(price or 0) or 0))
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            if state.gold < price then
                Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "金币不足", state = state })
                return
            end
            local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
            if owned >= SEED_STACK_MAX then
                Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "种子背包已满", state = state })
                return
            end
            state.gold = state.gold - price
            state.seedBag[plantIndex] = owned + 1
            state.updatedAt = Now()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function()
                    Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = true, message = "购买成功", plantIndex = plantIndex, state = state })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "购买失败: " .. tostring(reason), state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.BUY_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason) })
        end,
    })
end

local function PlantSeedAuthority(uid, payload, connection)
    payload = payload or {}
    local plantIndex = math.max(1, tonumber(payload.plantIndex or 1) or 1)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedBag[plantIndex] or 0) or 0
            if owned <= 0 then
                Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "没有该种子", state = state })
                return
            end
            state.seedBag[plantIndex] = owned - 1
            local buffCount = tonumber(state.seedBagBuffs[plantIndex] or 0) or 0
            local seedBuff = 0
            if buffCount > 0 then
                state.seedBagBuffs[plantIndex] = buffCount - 1
                seedBuff = 0.01
            end
            state.updatedAt = Now()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function()
                    payload.seedBuff = seedBuff
                    payload.serverAcceptedAt = Now()
                    Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, {
                        success = true,
                        message = "播种确认",
                        requestId = payload.requestId,
                        plantIndex = plantIndex,
                        plotIndex = payload.plotIndex,
                        localPos = payload.localPos,
                        seedBuff = seedBuff,
                        state = state,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "播种失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.PLANT_SEED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

local function HarvestCropAuthority(uid, payload, connection)
    payload = payload or {}
    local crop = payload.crop
    if type(crop) ~= "table" then
        Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "收获数据无效", requestId = payload.requestId })
        return
    end
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            state.harvested = state.harvested or {}
            if #(state.harvested) >= 100 then
                Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "背包已满", requestId = payload.requestId, state = state })
                return
            end
            table.insert(state.harvested, crop)
            state.collectedPlants = state.collectedPlants or {}
            if crop.plantIndex ~= nil then state.collectedPlants[crop.plantIndex] = true end
            state.updatedAt = Now()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function()
                    Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, {
                        success = true,
                        message = "收获确认",
                        requestId = payload.requestId,
                        plotIndex = payload.plotIndex,
                        cropIndex = payload.cropIndex,
                        cropId = payload.cropId,
                        crop = crop,
                        state = state,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "收获失败: " .. tostring(reason), requestId = payload.requestId, state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.HARVEST_CROP_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId })
        end,
    })
end

local function SellHarvested(uid, sellMode, payload, connection)
    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
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
                Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "没有可出售作物", state = state })
                return
            end

            state.harvested = remain
            state.gold = state.gold + total
            state.updatedAt = Now()
            serverCloud:Set(uid, Shared.KEYS.ECONOMY_STATE, state, {
                ok = function()
                    Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = true, message = "出售成功，获得金币 " .. total, total = total, count = #sold, state = state })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "出售失败: " .. tostring(reason), state = state })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.SELL_HARVESTED_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason) })
        end,
    })
end

local function ReadRequest(eventData)
    return Shared.ReadEventData(eventData)
end

local function GetNicknameMap(userIds)
    local map = {}
    local clean = {}
    local seen = {}
    for _, uid in ipairs(userIds or {}) do
        if uid ~= nil and not seen[tostring(uid)] then
            seen[tostring(uid)] = true
            clean[#clean + 1] = uid
        end
    end
    if GetUserNickname == nil or #clean <= 0 then return map end
    GetUserNickname({
        userIds = clean,
        onSuccess = function(nicknames)
            for _, info in ipairs(nicknames or {}) do
                map[info.userId] = info.nickname or "Tap玩家"
                map[tostring(info.userId)] = info.nickname or "Tap玩家"
            end
        end,
    })
    return map
end

local function GetCropList(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.plot) ~= "table" or type(snapshot.plot.plants) ~= "table" then
        return {}
    end
    return snapshot.plot.plants
end

local function BuildCropId(snapshot, crop, cropIndex)
    if crop.cropId ~= nil and crop.cropId ~= "" then return tostring(crop.cropId) end
    local plotIndex = snapshot and snapshot.visitablePlotIndex or snapshot and snapshot.plot and snapshot.plot.plotIndex or 1
    local x = crop and crop.localPos and crop.localPos.x or 0
    local z = crop and crop.localPos and crop.localPos.z or 0
    return string.format("p%d_c%d_%d_%d_%d", tonumber(plotIndex or 1) or 1, cropIndex, tonumber(crop and crop.plantIndex or 0) or 0, math.floor(x * 1000), math.floor(z * 1000))
end

local function BuildOldCropMap(oldSnapshot)
    local map = {}
    for index, crop in ipairs(GetCropList(oldSnapshot)) do
        local id = crop.serverCropId or crop.cropId or BuildCropId(oldSnapshot, crop, index)
        if id ~= nil then map[tostring(id)] = crop end
    end
    return map
end

local function CanonicalizeSnapshot(uid, snapshot, oldSnapshot)
    local now = Now()
    snapshot.userId = uid
    snapshot.updatedAt = now
    snapshot.version = 2
    snapshot.plot = snapshot.plot or { plotIndex = snapshot.visitablePlotIndex or 1, plants = {} }
    snapshot.plot.plants = snapshot.plot.plants or {}

    local oldMap = BuildOldCropMap(oldSnapshot)
    for index, crop in ipairs(snapshot.plot.plants) do
        local cropId = BuildCropId(snapshot, crop, index)
        local old = oldMap[cropId]
        local growTime = math.max(1, tonumber(crop.growTime or old and old.growTime or 1) or 1)
        local elapsed = math.max(0, tonumber(crop.elapsed or 0) or 0)
        local plantedAt = old and old.plantedAt or (now - math.min(elapsed, growTime))
        local matureAt = old and old.matureAt or (plantedAt + growTime)

        crop.cropId = cropId
        crop.serverCropId = cropId
        crop.plantedAt = plantedAt
        crop.growTime = growTime
        crop.matureAt = matureAt
        crop.elapsed = math.max(0, math.min(growTime, now - plantedAt))
        crop.mature = now >= matureAt
        crop.stealable = crop.mature == true and crop.stolen ~= true

        if old ~= nil then
            crop.stolen = old.stolen == true
            crop.stolenBy = old.stolenBy
            crop.stolenAt = old.stolenAt
            crop.stealReward = old.stealReward
            crop.stealable = crop.mature == true and crop.stolen ~= true
        else
            crop.stolen = crop.stolen == true
            crop.stealable = crop.mature == true and crop.stolen ~= true
        end
    end
    return snapshot
end

local function RefreshRuntimeSnapshot(snapshot)
    local now = Now()
    for _, crop in ipairs(GetCropList(snapshot)) do
        if crop.plantedAt == nil then
            local growTime = math.max(1, tonumber(crop.growTime or 1) or 1)
            local elapsed = math.max(0, tonumber(crop.elapsed or 0) or 0)
            crop.plantedAt = now - math.min(elapsed, growTime)
            crop.matureAt = crop.plantedAt + growTime
        end
        crop.growTime = math.max(1, tonumber(crop.growTime or 1) or 1)
        crop.matureAt = crop.matureAt or (crop.plantedAt + crop.growTime)
        crop.elapsed = math.max(0, math.min(crop.growTime, now - crop.plantedAt))
        crop.mature = now >= crop.matureAt
        crop.stealable = crop.mature == true and crop.stolen ~= true
    end
    return snapshot
end

local function GetCrop(snapshot, cropIndex, cropId)
    local plants = GetCropList(snapshot)
    if cropId ~= nil and cropId ~= "" then
        for index, crop in ipairs(plants) do
            if crop.cropId == cropId or crop.serverCropId == cropId then return crop, index end
        end
    end
    cropIndex = math.max(1, tonumber(cropIndex or 1) or 1)
    return plants[cropIndex], cropIndex
end

local function GetStealChance(crop)
    local rarity = crop and crop.rarity or crop and crop.config and crop.config.rarity or "普通"
    local chances = {
        ["普通"] = 0.80,
        ["罕见"] = 0.65,
        ["稀有"] = 0.48,
        ["史诗"] = 0.32,
        ["传奇"] = 0.18,
        ["神话"] = 0.10,
    }
    return chances[rarity] or 0.45
end

local function RollStealReward(crop)
    local seedId = crop and crop.plantIndex or 1
    local chance = GetStealChance(crop)
    if math.random() <= chance then
        return { type = "seed", seedId = seedId, count = 1, chance = chance }
    end
    return { type = "none", chance = chance }
end

local function BuildStealRecordKey(targetUid, cropId)
    return "steal_record_" .. tostring(targetUid) .. "_" .. tostring(cropId or "unknown")
end

local function NormalizeListRows(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
            value.listId = row.list_id or row.listId
            result[#result + 1] = value
        end
    end
    table.sort(result, function(a, b)
        return tonumber(a.time or a.stolenAt or a.visitedAt or a.sentAt or 0) > tonumber(b.time or b.stolenAt or b.visitedAt or b.sentAt or 0)
    end)
    while #result > MAX_SOCIAL_ROWS do table.remove(result) end
    return result
end

local function FetchStealLogs(uid, done)
    serverCloud.list:Get(uid, Shared.KEYS.STEAL_LOGS, {
        ok = function(rows) done(NormalizeListRows(rows)) end,
        error = function() done({}) end,
    })
end

local function FetchRecentVisitors(uid, done)
    serverCloud.list:Get(uid, Shared.KEYS.RECENT_VISITORS, {
        ok = function(rows) done(NormalizeListRows(rows)) end,
        error = function() done({}) end,
    })
end

local function SaveGardenSnapshot(uid, snapshot, connection)
    if type(snapshot) ~= "table" then
        Send(connection, Shared.EVENTS.SAVE_GARDEN_RESULT, { success = false, message = "花园快照无效" })
        return
    end

    serverCloud:Get(uid, Shared.KEYS.GARDEN_SNAPSHOT, {
        ok = function(scores)
            local oldSnapshot = scores[Shared.KEYS.GARDEN_SNAPSHOT]
            local canonical = CanonicalizeSnapshot(uid, snapshot, oldSnapshot)
            local score = math.max(0, math.floor(tonumber(canonical.bestTourValue or canonical.tourValue or 0) or 0))
            serverCloud:BatchSet(uid)
                :Set(Shared.KEYS.GARDEN_SNAPSHOT, canonical)
                :SetInt(Shared.KEYS.TOUR_RANK, score)
                :Save("保存权威社交花园", {
                    ok = function()
                        Send(connection, Shared.EVENTS.SAVE_GARDEN_RESULT, { success = true, message = "花园快照已同步" })
                    end,
                    error = function(_, reason)
                        Send(connection, Shared.EVENTS.SAVE_GARDEN_RESULT, { success = false, message = "同步失败: " .. tostring(reason) })
                    end,
                })
        end,
        error = function()
            local canonical = CanonicalizeSnapshot(uid, snapshot, nil)
            local score = math.max(0, math.floor(tonumber(canonical.bestTourValue or canonical.tourValue or 0) or 0))
            serverCloud:BatchSet(uid)
                :Set(Shared.KEYS.GARDEN_SNAPSHOT, canonical)
                :SetInt(Shared.KEYS.TOUR_RANK, score)
                :Save("首次保存权威社交花园", {
                    ok = function()
                        Send(connection, Shared.EVENTS.SAVE_GARDEN_RESULT, { success = true, message = "花园快照已同步" })
                    end,
                    error = function(_, reason)
                        Send(connection, Shared.EVENTS.SAVE_GARDEN_RESULT, { success = false, message = "同步失败: " .. tostring(reason) })
                    end,
                })
        end,
    })
end

local function RequestGardenSnapshot(requesterUid, targetUid, connection)
    if targetUid == nil or targetUid <= 0 then
        Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "玩家 ID 无效" })
        return
    end
    serverCloud:Get(targetUid, Shared.KEYS.GARDEN_SNAPSHOT, {
        ok = function(scores)
            local garden = scores[Shared.KEYS.GARDEN_SNAPSHOT]
            if type(garden) ~= "table" or garden.plot == nil then
                Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "该玩家尚未开放花园" })
                return
            end
            RefreshRuntimeSnapshot(garden)
            local c = serverCloud:BatchCommit("记录花园拜访")
            if requesterUid ~= nil and tostring(requesterUid) ~= tostring(targetUid) then
                c:ListAdd(targetUid, Shared.KEYS.RECENT_VISITORS, {
                    userId = requesterUid,
                    visitedAt = Now(),
                    time = Now(),
                })
                c:ListAdd(requesterUid, Shared.KEYS.RECENT_VISITORS, {
                    userId = targetUid,
                    visitedAt = Now(),
                    time = Now(),
                    direction = "visited",
                })
            end
            c:Commit()
            serverCloud:Get(targetUid, Shared.KEYS.LIKE_COUNT, {
                ok = function(likeScores)
                    garden.likeCount = tonumber(likeScores[Shared.KEYS.LIKE_COUNT] or garden.likeCount or 0) or 0
                    Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = true, garden = garden })
                end,
                error = function()
                    garden.likeCount = tonumber(garden.likeCount or 0) or 0
                    Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = true, garden = garden })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "读取花园失败: " .. tostring(reason) })
        end,
    })
end

local function RequestRank(count, connection, requesterUid)
    count = Clamp(tonumber(count or 20) or 20, 1, 50)
    serverCloud:GetRankList(Shared.KEYS.TOUR_RANK, 1, count, {
        ok = function(rankList)
            local userIds = {}
            local result = {}
            for i, item in ipairs(rankList or {}) do
                local userId = item.userId or item.player
                if userId ~= nil then
                    userIds[#userIds + 1] = userId
                    result[#result + 1] = {
                        rank = i,
                        userId = userId,
                        nickname = "Tap玩家",
                        score = item.iscore and item.iscore[Shared.KEYS.TOUR_RANK] or 0,
                        isMe = tostring(userId) == tostring(requesterUid),
                        source = "rank",
                    }
                end
            end
            local nickMap = GetNicknameMap(userIds)
            for _, entry in ipairs(result) do
                entry.nickname = nickMap[entry.userId] or nickMap[tostring(entry.userId)] or entry.nickname
            end
            Send(connection, Shared.EVENTS.RANK_RESPONSE, { success = true, list = result })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.RANK_RESPONSE, { success = false, message = "排行榜读取失败: " .. tostring(reason) })
        end,
    })
end

local function RequestSteal(uid, targetUid, cropIndex, cropId, connection)
    cropIndex = math.max(1, tonumber(cropIndex or 1) or 1)
    cropId = tostring(cropId or "")
    if targetUid == nil or targetUid <= 0 then
        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "目标花园无效" })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "不能偷自己的菜" })
        return
    end

    serverCloud.quota:Add(uid, "daily_steal", 1, DAILY_STEAL_LIMIT, "day", 1, {
        ok = function()
            serverCloud:Get(targetUid, Shared.KEYS.GARDEN_SNAPSHOT, {
                ok = function(scores)
                    local snapshot = scores[Shared.KEYS.GARDEN_SNAPSHOT]
                    if type(snapshot) ~= "table" then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "目标花园不存在" })
                        return
                    end
                    RefreshRuntimeSnapshot(snapshot)
                    local crop, actualIndex = GetCrop(snapshot, cropIndex, cropId)
                    if crop == nil then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "没有找到这株作物" })
                        return
                    end
                    local actualCropId = tostring(crop.serverCropId or crop.cropId or cropId)
                    if crop.mature ~= true then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物还没成熟" })
                        return
                    end
                    if crop.stolen == true then
                        Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物已经被偷过了" })
                        return
                    end

                    local recordKey = BuildStealRecordKey(targetUid, actualCropId)
                    serverCloud.list:Get(uid, recordKey, {
                        ok = function(records)
                            if records ~= nil and #records > 0 then
                                Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "这株作物你已经偷过了" })
                                return
                            end

                            local reward = RollStealReward(crop)
                            local now = Now()
                            crop.stolen = true
                            crop.stolenBy = uid
                            crop.stolenAt = now
                            crop.stealable = false
                            crop.stealReward = reward
                            snapshot.updatedAt = now

                            local log = {
                                thiefUserId = uid,
                                targetUserId = targetUid,
                                cropId = actualCropId,
                                cropIndex = actualIndex,
                                cropName = crop.name or "作物",
                                seedId = crop.plantIndex or reward.seedId or 1,
                                gotSeed = reward.type == "seed",
                                reward = reward,
                                stolenAt = now,
                                time = now,
                            }

                            local c = serverCloud:BatchCommit("权威偷菜")
                            c:ScoreSet(targetUid, Shared.KEYS.GARDEN_SNAPSHOT, snapshot)
                            c:ListAdd(uid, recordKey, { targetUserId = targetUid, cropId = actualCropId, stolenAt = now })
                            c:ListAdd(targetUid, Shared.KEYS.STEAL_LOGS, log)
                            c:ListAdd(targetUid, Shared.KEYS.RECENT_VISITORS, { userId = uid, visitedAt = now, time = now, action = "steal" })
                            if reward.type == "seed" then
                                c:ListAdd(uid, Shared.KEYS.SEED_REWARDS, reward)
                                c:ListAdd(uid, "seed_rewards", reward)
                            end
                            c:Commit({
                                ok = function()
                                    local message = reward.type == "none" and "偷菜成功，但没有获得种子" or "偷菜成功，奖励已发放"
                                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, {
                                        success = true,
                                        message = message,
                                        reward = reward,
                                        cropId = actualCropId,
                                        cropIndex = actualIndex,
                                        daily = { limit = DAILY_STEAL_LIMIT },
                                    })
                                end,
                                error = function(_, reason)
                                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜提交失败: " .. tostring(reason) })
                                end,
                            })
                        end,
                        error = function(_, reason)
                            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "偷菜记录读取失败: " .. tostring(reason) })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "读取目标花园失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function()
            Send(connection, Shared.EVENTS.STEAL_RESPONSE, { success = false, message = "今日偷菜次数已用完" })
        end,
    })
end

local function RequestSocialState(uid, connection)
    FetchStealLogs(uid, function(stealLogs)
        FetchRecentVisitors(uid, function(recentVisitors)
            serverCloud:GetRankList(Shared.KEYS.TOUR_RANK, 1, 12, {
                ok = function(rankList)
                    local userIds = {}
                    local recommended = {}
                    local seen = { [tostring(uid)] = true }

                    for _, row in ipairs(recentVisitors) do
                        local userId = row.userId or row.thiefUserId or row.targetUserId
                        if userId ~= nil and not seen[tostring(userId)] then
                            seen[tostring(userId)] = true
                            userIds[#userIds + 1] = userId
                            recommended[#recommended + 1] = { userId = userId, score = 0, source = row.direction == "visited" and "recent_visit" or "recent_visitor" }
                        end
                    end

                    for i, item in ipairs(rankList or {}) do
                        local userId = item.userId or item.player
                        if userId ~= nil and not seen[tostring(userId)] then
                            seen[tostring(userId)] = true
                            userIds[#userIds + 1] = userId
                            recommended[#recommended + 1] = {
                                userId = userId,
                                rank = i,
                                score = item.iscore and item.iscore[Shared.KEYS.TOUR_RANK] or 0,
                                source = "rank",
                            }
                        end
                    end

                    for _, row in ipairs(stealLogs) do
                        if row.thiefUserId ~= nil then userIds[#userIds + 1] = row.thiefUserId end
                    end
                    for _, row in ipairs(recentVisitors) do
                        if row.userId ~= nil then userIds[#userIds + 1] = row.userId end
                    end

                    local nickMap = GetNicknameMap(userIds)
                    for _, entry in ipairs(recommended) do
                        entry.nickname = nickMap[entry.userId] or nickMap[tostring(entry.userId)] or "Tap玩家"
                    end
                    for _, row in ipairs(stealLogs) do
                        row.thiefNickname = nickMap[row.thiefUserId] or nickMap[tostring(row.thiefUserId)] or "Tap玩家"
                    end
                    for _, row in ipairs(recentVisitors) do
                        row.nickname = nickMap[row.userId] or nickMap[tostring(row.userId)] or "Tap玩家"
                    end

                    Send(connection, Shared.EVENTS.SOCIAL_STATE_RESPONSE, {
                        success = true,
                        stealLogs = stealLogs,
                        recentVisitors = recentVisitors,
                        recommendedPlayers = recommended,
                    })
                end,
                error = function()
                    Send(connection, Shared.EVENTS.SOCIAL_STATE_RESPONSE, {
                        success = true,
                        stealLogs = stealLogs,
                        recentVisitors = recentVisitors,
                        recommendedPlayers = {},
                    })
                end,
            })
        end)
    end)
end

local function SendSeedGift(uid, targetUid, seedId, count, connection)
    targetUid = tonumber(targetUid or 0) or 0
    seedId = tonumber(seedId or 1) or 1
    count = math.max(1, tonumber(count or 1) or 1)
    if targetUid <= 0 then
        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "好友玩家 ID 无效" })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "不能给自己赠送种子" })
        return
    end

    serverCloud.quota:Add(uid, "daily_seed_gift", 1, DAILY_GIFT_LIMIT, "day", 1, {
        ok = function()
            local gift = {
                fromUserId = uid,
                seedId = seedId,
                count = count,
                sentAt = Now(),
                time = Now(),
            }
            serverCloud.message:Send(uid, "seed_gift", targetUid, gift, {
                ok = function()
                    Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, {
                        success = true,
                        message = "种子已送给好友",
                        daily = { limit = DAILY_GIFT_LIMIT },
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "赠送失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function()
            Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "今日赠送次数已用完" })
        end,
    })
end

local function BuildLikeRecordKey(targetUid)
    return "liked_garden_" .. tostring(targetUid)
end

local function LikeGarden(uid, targetUid, connection)
    targetUid = tonumber(targetUid or 0) or 0
    if targetUid <= 0 then
        Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "花园不存在" })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "不能给自己的花园点赞" })
        return
    end
    local recordKey = BuildLikeRecordKey(targetUid)
    serverCloud.list:Get(uid, recordKey, {
        ok = function(records)
            if records ~= nil and #records > 0 then
                serverCloud:Get(targetUid, Shared.KEYS.LIKE_COUNT, {
                    ok = function(scores)
                        Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, {
                            success = false,
                            alreadyLiked = true,
                            message = "已经点赞过这个花园了",
                            likeCount = tonumber(scores[Shared.KEYS.LIKE_COUNT] or 0) or 0,
                        })
                    end,
                    error = function()
                        Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, alreadyLiked = true, message = "已经点赞过这个花园了" })
                    end,
                })
                return
            end
            local c = serverCloud:BatchCommit("点赞花园")
            c:ListAdd(uid, recordKey, { targetUserId = targetUid, likedAt = Now() })
            c:ScoreAddInt(targetUid, Shared.KEYS.LIKE_COUNT, 1)
            c:Commit({
                ok = function()
                    serverCloud:Get(targetUid, Shared.KEYS.LIKE_COUNT, {
                        ok = function(scores)
                            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, {
                                success = true,
                                message = "已点赞这个花园",
                                targetUserId = targetUid,
                                likeCount = tonumber(scores[Shared.KEYS.LIKE_COUNT] or 0) or 0,
                            })
                        end,
                        error = function()
                            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = true, message = "已点赞这个花园", targetUserId = targetUid })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "点赞失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "点赞记录读取失败: " .. tostring(reason) })
        end,
    })
end

local function RequestGifts(uid, connection)
    serverCloud.message:Get(uid, "seed_gift", false, {
        ok = function(messages)
            local gifts = {}
            for _, msg in ipairs(messages or {}) do
                local value = msg.value or {}
                gifts[#gifts + 1] = {
                    giftId = msg.message_id,
                    fromUserId = value.fromUserId,
                    seedId = value.seedId,
                    count = value.count or 1,
                    sentAt = value.sentAt or msg.time,
                    claimed = false,
                }
            end
            Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = true, gifts = gifts })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = false, message = "礼物读取失败: " .. tostring(reason) })
        end,
    })
end

local function ClaimGift(uid, giftId, seedId, count, connection)
    if giftId == nil then
        Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = false, message = "礼物不存在" })
        return
    end
    seedId = tonumber(seedId or 1) or 1
    count = math.max(1, tonumber(count or 1) or 1)
    local reward = { type = "seed", seedId = seedId, count = count }
    local c = serverCloud:BatchCommit("领取种子礼物")
    c:ListAdd(uid, Shared.KEYS.SEED_REWARDS, reward)
    c:ListAdd(uid, "seed_rewards", reward)
    c:Commit({
        ok = function()
            serverCloud.message:MarkRead(giftId)
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = true, message = "好友种子已领取", gift = reward })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, { success = false, message = "领取失败: " .. tostring(reason) })
        end,
    })
end

function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    connections_[GetConnectionKey(connection)] = connection
end

function HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then
        connectionUsers_[GetConnectionKey(connection)] = uid
    end
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local key = GetConnectionKey(connection)
    connections_[key] = nil
    connectionUsers_[key] = nil
end

function HandleGardenClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    connection.scene = scene_
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestSocialState(uid, connection) end
    if uid ~= nil then RequestEconomyState(uid, connection) end
end

function HandleGardenSaveSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SaveGardenSnapshot(uid, data.snapshot, connection) end
end

function HandleGardenRequestSnapshot(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    RequestGardenSnapshot(uid, tonumber(data.targetUserId or 0) or 0, connection)
end

function HandleGardenRequestRank(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    RequestRank(data.count, connection, uid)
end

function HandleGardenRequestSteal(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then RequestSteal(uid, tonumber(data.targetUserId or 0) or 0, data.cropIndex, data.cropId, connection) end
end

function HandleGardenRequestSocialState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestSocialState(uid, connection) end
end

function HandleGardenRequestEconomyState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestEconomyState(uid, connection) end
end

function HandleGardenSaveEconomyState(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SaveEconomyState(uid, data.state, connection) end
end

function HandleGardenBuySeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then BuySeed(uid, data.plantIndex, data.price, connection) end
end

function HandleGardenPlantSeed(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then PlantSeedAuthority(uid, data, connection) end
end

function HandleGardenHarvestCrop(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then HarvestCropAuthority(uid, data, connection) end
end

function HandleGardenSellHarvested(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SellHarvested(uid, data.mode or "all", data, connection) end
end

function HandleGardenSendSeedGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then SendSeedGift(uid, data.targetUserId, data.seedId, data.count, connection) end
end

function HandleGardenLikeGarden(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then LikeGarden(uid, data.targetUserId, connection) end
end

function HandleGardenRequestGifts(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    if uid ~= nil then RequestGifts(uid, connection) end
end

function HandleGardenClaimGift(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local uid = GetConnectionUserId(connection)
    local data = ReadRequest(eventData)
    if uid ~= nil then ClaimGift(uid, data.giftId, data.seedId, data.count, connection) end
end

function Start()
    math.randomseed(os.time())
    scene_ = Scene()
    Shared.RegisterServerEvents()
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleGardenClientReady")
    SubscribeToEvent(Shared.EVENTS.SAVE_GARDEN, "HandleGardenSaveSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GARDEN, "HandleGardenRequestSnapshot")
    SubscribeToEvent(Shared.EVENTS.REQUEST_RANK, "HandleGardenRequestRank")
    SubscribeToEvent(Shared.EVENTS.REQUEST_STEAL, "HandleGardenRequestSteal")
    SubscribeToEvent(Shared.EVENTS.REQUEST_SOCIAL_STATE, "HandleGardenRequestSocialState")
    SubscribeToEvent(Shared.EVENTS.REQUEST_ECONOMY_STATE, "HandleGardenRequestEconomyState")
    SubscribeToEvent(Shared.EVENTS.SAVE_ECONOMY_STATE, "HandleGardenSaveEconomyState")
    SubscribeToEvent(Shared.EVENTS.BUY_SEED, "HandleGardenBuySeed")
    SubscribeToEvent(Shared.EVENTS.PLANT_SEED, "HandleGardenPlantSeed")
    SubscribeToEvent(Shared.EVENTS.HARVEST_CROP, "HandleGardenHarvestCrop")
    SubscribeToEvent(Shared.EVENTS.SELL_HARVESTED, "HandleGardenSellHarvested")
    SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT, "HandleGardenSendSeedGift")
    SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN, "HandleGardenLikeGarden")
    SubscribeToEvent(Shared.EVENTS.REQUEST_GIFTS, "HandleGardenRequestGifts")
    SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT, "HandleGardenClaimGift")
    print("[社交花园服务端] 权威农场服务已启动")
end
