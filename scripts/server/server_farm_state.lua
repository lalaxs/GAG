-- ============================================================================
-- 服务端权威农场状态
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的农场状态归一化、作物查找/刷新、观光值计算、拜访花园构建和权威农场请求逻辑。
-- ============================================================================

local ServerFarmState = {}

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

function ServerFarmState.NormalizeFarmState(state)
    state = type(state) == "table" and state or {}
    state.version = 1
    state.revision = tonumber(state.revision or 0) or 0
    state.plots = type(state.plots) == "table" and state.plots or {}
    for _, plot in pairs(state.plots) do
        plot.plants = type(plot.plants) == "table" and plot.plants or {}
        for _, crop in ipairs(plot.plants) do
            RecalculateAuthoritativeItemPrice(crop)
        end
    end
    state.updatedAt = Now()
    return state
end

function ServerFarmState.GetFarmPlot(state, plotIndex)
    plotIndex = math.max(1, tonumber(plotIndex or 1) or 1)
    state.plots[plotIndex] = state.plots[plotIndex] or { plants = {} }
    state.plots[plotIndex].plants = state.plots[plotIndex].plants or {}
    return state.plots[plotIndex]
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
    local cropIndex = math.floor(tonumber(payload.cropIndex or 0) or 0)
    if cropIndex >= 1 and plot.plants[cropIndex] ~= nil then
        return plot.plants[cropIndex], plotIndex, cropIndex
    end

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
        if bestCrop ~= nil then return bestCrop, plotIndex, bestIndex end
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
        userId = uid,
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

function ServerFarmState.RequestAuthFarmState(uid, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
        ok = function(scores)
            local farmState = ServerFarmState.NormalizeFarmState(scores[deps_.Shared.KEYS.AUTH_FARM_STATE])
            for _, plot in pairs(farmState.plots or {}) do
                for _, crop in ipairs(plot.plants or {}) do
                    ServerFarmState.RefreshAuthCrop(crop)
                end
            end
            Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = farmState })
        end,
        error = function()
            Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = ServerFarmState.NormalizeFarmState(nil) })
        end,
    })
end

return ServerFarmState
