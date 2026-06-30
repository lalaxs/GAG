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
    local canonicalUid = GetCanonicalUidKey(uid)
    local candidates = BuildUidKeyCandidates(uid)
    local bestKey = nil
    local bestFarm = nil
    local bestScore = -1
    local index = 1
    local hadReadError = false

    local function refreshFarm(farmState)
        for _, plot in pairs(farmState.plots or {}) do
            for _, crop in ipairs(plot.plants or {}) do
                ServerFarmState.RefreshAuthCrop(crop)
            end
        end
        return farmState
    end

    local function finishWithFarm()
        if bestFarm == nil then
            if hadReadError then
                print("[存档] 权威农场读取失败，保留原云端农场等待客户端重试")
                Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, {
                    success = false,
                    retryable = true,
                    message = "权威农场读取失败，请稍后重试",
                })
                return
            end
            Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = refreshFarm(ServerFarmState.NormalizeFarmState(nil)) })
            return
        end
        bestFarm = refreshFarm(bestFarm)
        if bestKey ~= canonicalUid then
            print(string.format("[存档兼容] 权威农场命中历史 uid key=%s，迁移到当前 key=%s", tostring(bestKey), tostring(canonicalUid)))
            serverCloud:Set(canonicalUid, deps_.Shared.KEYS.AUTH_FARM_STATE, bestFarm, {
                ok = function()
                    Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = bestFarm })
                end,
                error = function(_, reason)
                    print("[存档兼容] 权威农场迁移失败，使用历史 key 数据返回: " .. tostring(reason))
                    Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = bestFarm })
                end,
            })
            return
        end
        Send(connection, deps_.Shared.EVENTS.AUTH_FARM_RESPONSE, { success = true, farm = bestFarm })
    end

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            finishWithFarm()
            return
        end
        serverCloud:Get(key, deps_.Shared.KEYS.AUTH_FARM_STATE, {
            ok = function(scores)
                local rawFarm = scores and scores[deps_.Shared.KEYS.AUTH_FARM_STATE]
                if type(rawFarm) == "table" then
                    local farmState = ServerFarmState.NormalizeFarmState(rawFarm)
                    local score = ScoreFarmState(farmState)
                    if score > bestScore then
                        bestScore = score
                        bestFarm = farmState
                        bestKey = key
                    end
                end
                readNext()
            end,
            error = function(_, reason)
                hadReadError = true
                print(string.format("[存档兼容] 权威农场读取失败 key=%s reason=%s", tostring(key), tostring(reason)))
                readNext()
            end,
        })
    end

    readNext()
end

return ServerFarmState
