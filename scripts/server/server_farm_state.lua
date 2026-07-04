-- ============================================================================
-- 服务端权威农场状态
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的农场状态归一化、作物查找/刷新、观光值计算、拜访花园构建和权威农场请求逻辑。
-- ============================================================================

local ServerFarmState = {}

local ServerCloudStore = require("server.server_cloud_store")
local SaveLoginReconcile = require("server.save_login_reconcile")
local UserId = require("utils.user_id")

local deps_ = {}

function ServerFarmState.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function NormalizePlotIndex(value)
    return deps_.NormalizePlotIndex(value)
end

local function NormalizeLocalPos(value)
    return deps_.NormalizeLocalPos(value)
end

local function RecalculateAuthoritativeItemPrice(item)
    deps_.RecalculateAuthoritativeItemPrice(item)
end

local function BuildUidKeyCandidates(uid)
    if deps_.BuildUidKeyCandidates ~= nil then return deps_.BuildUidKeyCandidates(uid) end
    return { uid }
end

local function GetCanonicalUidKey(uid)
    if deps_.GetCanonicalUidKey ~= nil then return deps_.GetCanonicalUidKey(uid) end
    return uid
end

local function ScoreFarmState(state)
    if type(state) ~= "table" then return -1 end
    local score = math.max(0, tonumber(state.revision or 0) or 0) * 1000
    for _, plot in pairs(state.plots or {}) do
        if type(plot) == "table" and type(plot.plants) == "table" then
            score = score + #plot.plants * 100
            for _, crop in ipairs(plot.plants) do
                if type(crop) == "table" and crop.harvested ~= true then score = score + 1 end
            end
        end
    end
    return score
end

function ServerFarmState.NormalizeFarmState(state)
    state = type(state) == "table" and state or {}
    state.version = 1
    state.revision = tonumber(state.revision or 0) or 0
    local normalizedPlots = {}
    if type(state.plots) == "table" then
        for plotKey, plot in pairs(state.plots) do
            local plotIndex = tonumber(plotKey)
            if plotIndex ~= nil then
                plotIndex = math.max(1, math.floor(plotIndex))
                plot = type(plot) == "table" and plot or {}
                plot.plants = type(plot.plants) == "table" and plot.plants or {}
                for _, crop in ipairs(plot.plants) do
                    RecalculateAuthoritativeItemPrice(crop)
                end
                normalizedPlots[plotIndex] = plot
            end
        end
    end
    state.plots = normalizedPlots
    state.updatedAt = Now()
    return state
end

function ServerFarmState.GetFarmPlot(state, plotIndex)
    plotIndex = math.max(1, tonumber(plotIndex or 1) or 1)
    state.plots[plotIndex] = state.plots[plotIndex] or { plants = {} }
    state.plots[plotIndex].plants = state.plots[plotIndex].plants or {}
    return state.plots[plotIndex]
end

function ServerFarmState.ScoreFarmState(state)
    return ScoreFarmState(state)
end

function ServerFarmState.FindFarmCrop(state, cropId)
    if cropId == nil then return nil, nil, nil end
    for plotIndex, plot in pairs(state.plots or {}) do
        for cropIndex, crop in ipairs(plot.plants or {}) do
            if crop.cropId == cropId or crop.serverCropId == cropId then
                return crop, tonumber(plotIndex), cropIndex
            end
        end
    end
    return nil, nil, nil
end

function ServerFarmState.FindFarmCropFromHarvestPayload(state, payload)
    payload = payload or {}
    local requestedCropId = payload.cropId
    if requestedCropId ~= nil and requestedCropId ~= "" then
        local crop, plotIndex, cropIndex = ServerFarmState.FindFarmCrop(state, requestedCropId)
        if crop ~= nil then return crop, plotIndex, cropIndex end
    end

    local plotIndex = NormalizePlotIndex(payload.plotIndex)
    local plot = ServerFarmState.GetFarmPlot(state, plotIndex)

    local posSource = payload.localPos or (payload.crop and payload.crop.localPos)
    if type(posSource) == "table" then
        local localPos = NormalizeLocalPos(posSource)
        local bestCrop, bestIndex, bestDist = nil, nil, 999999
        for index, crop in ipairs(plot.plants or {}) do
            local cropPos = crop.localPos or {}
            local dx = (tonumber(cropPos.x or 0) or 0) - localPos.x
            local dz = (tonumber(cropPos.z or 0) or 0) - localPos.z
            local dist = dx * dx + dz * dz
            local radius = math.max(0.55, tonumber(crop.pickRadius or 0.55) or 0.55)
            if dist <= radius * radius and dist < bestDist then
                bestCrop = crop
                bestIndex = index
                bestDist = dist
            end
        end
        if bestCrop ~= nil then
            if requestedCropId ~= nil and requestedCropId ~= "" then
                print(string.format(
                    "[权威收获] cropId 未命中，按 localPos 回退 cropId=%s -> %s",
                    tostring(requestedCropId),
                    tostring(bestCrop.cropId or bestCrop.serverCropId)
                ))
            end
            return bestCrop, plotIndex, bestIndex
        end
    end

    if requestedCropId ~= nil and requestedCropId ~= "" then
        print(string.format(
            "[权威收获] cropId/localPos 均未命中 cropId=%s plot=%s cropIndex=%s",
            tostring(requestedCropId),
            tostring(payload.plotIndex),
            tostring(payload.cropIndex)
        ))
        return nil, nil, nil
    end

    local cropIndex = math.floor(tonumber(payload.cropIndex or 0) or 0)
    if cropIndex >= 1 and plot.plants[cropIndex] ~= nil then
        return plot.plants[cropIndex], plotIndex, cropIndex
    end

    return nil, nil, nil
end

function ServerFarmState.RefreshAuthCrop(crop)
    local now = Now()
    crop.growTime = math.max(1, tonumber(crop.growTime or 1) or 1)
    crop.plantedAt = tonumber(crop.plantedAt or now) or now
    crop.matureAt = tonumber(crop.matureAt or (crop.plantedAt + crop.growTime)) or (crop.plantedAt + crop.growTime)
    crop.elapsed = math.max(0, math.min(crop.growTime, now - crop.plantedAt))
    crop.mature = now >= crop.matureAt
    crop.stealable = crop.mature == true and crop.stolen ~= true and crop.harvested ~= true
end

function ServerFarmState.CalculateAuthCropSightValue(crop)
    if type(crop) ~= "table" or crop.harvested == true then return 0 end
    ServerFarmState.RefreshAuthCrop(crop)
    local plant = deps_.GameConfig.PLANTS[tonumber(crop.plantIndex or 0) or 0] or {}
    local baseValue = tonumber(crop.sightValue or plant.sightBase or plant.fruitPrice or 1) or 1
    local growthMultiplier = 1.0
    if crop.mature ~= true then
        local progress = 0
        if crop.growTime ~= nil and crop.growTime > 0 then
            progress = Clamp((crop.elapsed or 0) / crop.growTime, 0.0, 1.0)
        end
        if progress < 0.18 then
            growthMultiplier = 0.1
        elseif progress < 0.55 then
            growthMultiplier = 0.3
        else
            growthMultiplier = 0.6
        end
    end
    return math.max(0, math.floor(baseValue * growthMultiplier + 0.5))
end

function ServerFarmState.CalculateAuthFarmTourValue(farmState)
    farmState = ServerFarmState.NormalizeFarmState(farmState)
    local total = 0
    for _, plot in pairs(farmState.plots or {}) do
        for _, crop in ipairs(plot.plants or {}) do
            total = total + ServerFarmState.CalculateAuthCropSightValue(crop)
        end
    end
    return total
end

function ServerFarmState.BuildVisitGardenFromAuthFarm(uid, nickname, farmState, snapshot)
    farmState = ServerFarmState.NormalizeFarmState(farmState)
    local plotIndex = tonumber(snapshot and snapshot.visitablePlotIndex or 1) or 1
    local plot = ServerFarmState.GetFarmPlot(farmState, plotIndex)
    local plants = {}
    for _, crop in ipairs(plot.plants or {}) do
        if crop.harvested ~= true then
            ServerFarmState.RefreshAuthCrop(crop)
            plants[#plants + 1] = crop
        end
    end
    local tourValue = ServerFarmState.CalculateAuthFarmTourValue(farmState)
    local bestTourValue = tourValue
    return {
        version = 3,
        source = "auth_farm",
        userId = UserId.Normalize(uid) or uid,
        nickname = nickname or snapshot and snapshot.nickname or "Tap玩家",
        avatar = snapshot and snapshot.avatar or nil,
        visitablePlotIndex = plotIndex,
        unlockedPlotCount = snapshot and snapshot.unlockedPlotCount or 1,
        tourValue = tourValue,
        bestTourValue = bestTourValue,
        likeCount = 0,
        updatedAt = Now(),
        plot = { plotIndex = plotIndex, plants = plants },
    }
end

local function DeliverAuthFarm(uid, connection, farm, bestKey)
    uid = ServerCloudStore.CanonicalUid(uid) or uid
    local canonicalUid = ServerCloudStore.GetCanonicalUidKey(uid)

    if not UserId.IsOwnedSave(canonicalUid, farm) then
        print(string.format(
            "[存档隔离] 拒绝下发权威农场 uid=%s owner=%s embedded=%s bestKey=%s",
            tostring(canonicalUid),
            tostring(farm and farm.ownerUserId),
            tostring(farm and farm.userId),
            tostring(bestKey)
        ))
        Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, {
            success = false,
            retryable = true,
            message = "农场存档归属校验失败，请稍后重试",
        })
        return
    end

    local function refreshFarm(farmState)
        for _, plot in pairs(farmState.plots or {}) do
            for _, crop in ipairs(plot.plants or {}) do
                ServerFarmState.RefreshAuthCrop(crop)
            end
        end
        return farmState
    end

    farm = refreshFarm(farm)
    ServerCloudStore.MigrateScoreIfNeeded(canonicalUid, bestKey, deps_.Shared.KEYS.AUTH_FARM_STATE, farm, {
        migrationLabel = "权威农场",
        onReady = function(resolved)
            Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = resolved })
        end,
    })
end

local function LoadAuthFarmState(uid, connection)
    uid = ServerCloudStore.CanonicalUid(uid) or uid

    local function refreshFarm(farmState)
        for _, plot in pairs(farmState.plots or {}) do
            for _, crop in ipairs(plot.plants or {}) do
                ServerFarmState.RefreshAuthCrop(crop)
            end
        end
        return farmState
    end

    ServerCloudStore.ReadBestScore(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
        normalize = ServerFarmState.NormalizeFarmState,
        score = ScoreFarmState,
        requireOwner = true,
        logLabel = "权威农场",
    }, function(bestFarm, bestKey, hadReadError)
        if bestFarm ~= nil and not UserId.IsOwnedSave(uid, bestFarm) then
            print(string.format(
                "[存档隔离] 拒绝下发权威农场 uid=%s owner=%s bestKey=%s",
                tostring(uid),
                tostring(bestFarm.ownerUserId),
                tostring(bestKey)
            ))
            bestFarm = nil
            bestKey = nil
        end
        if bestFarm ~= nil then
            DeliverAuthFarm(uid, connection, bestFarm, bestKey)
            return
        end
        if hadReadError then
            Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, {
                success = false,
                retryable = true,
                message = "权威农场读取失败，请稍后重试",
            })
            return
        end
        Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, {
            success = true,
            farm = refreshFarm(ServerFarmState.NormalizeFarmState(nil)),
        })
    end)
end

function ServerFarmState.RequestAuthFarmState(uid, connection)
    print(string.format(
        "[存档] 请求权威农场 uid=%s cloudId=%s",
        tostring(ServerCloudStore.GetCanonicalUidKey(uid)),
        tostring(ServerCloudStore.CloudPlayerId(uid))
    ))
    SaveLoginReconcile.Ensure(uid, function()
        LoadAuthFarmState(uid, connection)
    end)
end

return ServerFarmState
