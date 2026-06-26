-- ============================================================================
-- 社交花园系统
-- ============================================================================
-- 管理可参观地块、花园快照、排行榜拜访、偷菜、好友赠送种子。
-- 多人服务器模式下通过远程事件请求服务端；单机/预览环境使用本地模拟数据。
-- ============================================================================

local Shared = require("network.shared")

local SocialGardenSystem = {}

local MODE_OWN = "own"
local MODE_VISIT = "visit"
local DAILY_STEAL_LIMIT = 10
local DAILY_GIFT_LIMIT = 5

local deps_ = {}
local state_ = {
    mode = MODE_OWN,
    visitablePlotIndex = 1,
    visitGarden = nil,
    leaderboard = {},
    gifts = {},
    friends = {},
    recommendedPlayers = {},
    recentVisitors = {},
    stealLogs = {},
    pending = {},
    daily = {
        stealCount = 0,
        giftSentCount = 0,
    },
    lastSyncText = "未同步",
    serverEnabled = false,
    stealingMode = false,
    likedGardens = {},
    likeDeltas = {},
}

local function IsClientNetworkAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function GetNow()
    return os and os.time and os.time() or 0
end

local function ClampPlotIndex(index)
    local unlocked = deps_.getUnlockedPlotCount and deps_.getUnlockedPlotCount() or 1
    return Clamp(tonumber(index or 1) or 1, 1, math.max(1, unlocked))
end

local function GetDisplayName()
    if deps_.getDisplayName then return deps_.getDisplayName() end
    return "Tap玩家"
end

local function GetUserId()
    if deps_.getUserId then return deps_.getUserId() end
    if clientCloud ~= nil and clientCloud.userId ~= nil then return clientCloud.userId end
    return nil
end

local function BuildCropId(plotIndex, cropIndex, crop)
    local x = crop and crop.localPos and crop.localPos.x or 0
    local z = crop and crop.localPos and crop.localPos.z or 0
    return string.format("p%d_c%d_%d_%d_%d", plotIndex, cropIndex, tonumber(crop and crop.plantIndex or 0) or 0, math.floor(x * 1000), math.floor(z * 1000))
end

local function CloneCropForSnapshot(crop, plotIndex, cropIndex)
    if crop == nil then return nil end
    local cropId = BuildCropId(plotIndex or 1, cropIndex or 1, crop)
    return {
        cropId = cropId,
        plantIndex = crop.plantIndex,
        name = crop.name,
        price = crop.price,
        sightValue = crop.sightValue,
        weight = crop.weight,
        baseWeight = crop.baseWeight,
        weightScale = crop.weightScale,
        weightTier = crop.weightTier,
        weightBonus = crop.weightBonus,
        weightMultiplier = crop.weightMultiplier,
        elapsed = crop.elapsed,
        growTime = crop.growTime,
        mature = crop.mature,
        sprouted = crop.sprouted,
        localPos = crop.localPos and { x = crop.localPos.x, z = crop.localPos.z } or { x = 0, z = 0 },
        seedRadius = crop.seedRadius,
        seedHeight = crop.seedHeight,
        pickRadius = crop.pickRadius,
        mutation = crop.mutation,
        rarity = crop.config and crop.config.rarity or crop.rarity,
    }
end

local function BuildPlotSnapshot(plotIndex, plot)
    local plants = {}
    if plot ~= nil and plot.plants ~= nil then
        for cropIndex, crop in ipairs(plot.plants) do
            local data = CloneCropForSnapshot(crop, plotIndex, cropIndex)
            if data ~= nil then table.insert(plants, data) end
        end
    end
    return {
        plotIndex = plotIndex,
        plants = plants,
    }
end

local function BuildSnapshot()
    local plots = deps_.getPlots and deps_.getPlots() or {}
    local plotIndex = ClampPlotIndex(state_.visitablePlotIndex)
    local plot = plots[plotIndex]
    return {
        version = 1,
        userId = GetUserId(),
        nickname = GetDisplayName(),
        visitablePlotIndex = plotIndex,
        unlockedPlotCount = deps_.getUnlockedPlotCount and deps_.getUnlockedPlotCount() or 1,
        tourValue = deps_.getTourValue and deps_.getTourValue() or 0,
        bestTourValue = deps_.getBestTourValue and deps_.getBestTourValue() or 0,
        likeCount = 0,
        updatedAt = GetNow(),
        plot = BuildPlotSnapshot(plotIndex, plot),
    }
end

local function BuildDemoGarden(userId, nickname, score, seedOffset, isFallback)
    local plants = deps_.getPlants and deps_.getPlants() or {}
    local crops = {}
    for i = 1, 4 do
        local plantIndex = ((i + (seedOffset or 0) - 1) % math.max(1, #plants)) + 1
        local plant = plants[plantIndex] or { name = "神秘作物", fruitPrice = 10, growTime = 8 }
        table.insert(crops, {
            cropId = string.format("demo_%s_%d", tostring(userId), i),
            plantIndex = plantIndex,
            name = plant.name,
            price = plant.fruitPrice or 10,
            sightValue = plant.sightBase or 10,
            weight = plant.baseWeight or 1.0,
            baseWeight = plant.baseWeight or 1.0,
            weightScale = 1.0,
            weightTier = "Normal",
            weightBonus = 1.0,
            weightMultiplier = 1.0,
            elapsed = plant.growTime or 8,
            growTime = plant.growTime or 8,
            mature = true,
            sprouted = true,
            localPos = { x = -0.42 + (i - 1) * 0.28, z = (i % 2 == 0) and 0.22 or -0.18 },
            seedRadius = 0.09,
            seedHeight = 0.015,
            pickRadius = 0.55,
            mutation = { sizeScale = 1.0, specials = {}, priceMultiplier = 1.0, timeMultiplier = 1.0 },
            rarity = plant.rarity or "普通",
        })
    end
    return {
        version = 1,
        userId = userId,
        nickname = nickname,
        visitablePlotIndex = 1,
        unlockedPlotCount = 3,
        tourValue = score,
        bestTourValue = score,
        likeCount = 12 + ((tonumber(userId or 0) or 0) % 37),
        isFallback = isFallback == true,
        updatedAt = GetNow(),
        plot = { plotIndex = 1, plants = crops },
    }
end

local function BuildFallbackGarden(userId, nickname)
    return BuildDemoGarden(userId or 0, nickname or "游客花园", 520, tonumber(userId or 0) or 0, true)
end

local function GetFallbackLeaderboardEntries()
    return {
        { rank = 1, userId = 90001, nickname = "糖霜园丁", score = 1880, isMe = false, source = "fallback" },
        { rank = 2, userId = 90002, nickname = "星环农夫", score = 1520, isMe = false, source = "fallback" },
        { rank = 3, userId = GetUserId() or 0, nickname = GetDisplayName(), score = deps_.getBestTourValue and deps_.getBestTourValue() or 0, isMe = true, source = "local" },
        { rank = 4, userId = 90003, nickname = "夜幕采集者", score = 980, isMe = false, source = "fallback" },
    }
end

local function EnsureDemoData()
    if #state_.leaderboard <= 0 then
        state_.leaderboard = GetFallbackLeaderboardEntries()
    end
    if #state_.friends > 0 then return end
    state_.friends = {
        { userId = 90001, nickname = "糖霜园丁", score = 1880 },
        { userId = 90002, nickname = "星环农夫", score = 1520 },
        { userId = 90003, nickname = "夜幕采集者", score = 980 },
    }
end

local function FindDemoPlayer(userId)
    EnsureDemoData()
    for _, entry in ipairs(GetFallbackLeaderboardEntries()) do
        if tostring(entry.userId) == tostring(userId) then
            return entry
        end
    end
    return nil
end

local function SendRequest(eventName, payload)
    if IsClientNetworkAvailable() then
        return Shared.SendToServer(eventName, payload)
    end
    return false
end

local function ApplyGiftReward(gift)
    if gift == nil then return false end
    local seedId = tonumber(gift.seedId or gift.plantIndex or 1) or 1
    local count = tonumber(gift.count or 1) or 1
    if deps_.addSeedToBag then
        local added = deps_.addSeedToBag(seedId, count, 0)
        return added > 0
    end
    return false
end

local function ApplyStealReward(reward)
    if reward == nil or reward.type == "none" then return false end
    if reward.type == "seed" and deps_.addSeedToBag then
        return deps_.addSeedToBag(reward.seedId or 1, reward.count or 1, 0) > 0
    elseif reward.type == "seed_pack" and deps_.addSeedPack then
        return deps_.addSeedPack(reward.packId or "pack_common", reward.count or 1)
    end
    return false
end

local function ApplyLocalLikeDelta(garden)
    if garden == nil then return end
    local key = tostring(garden.userId or "fallback")
    if garden.baseLikeCount == nil then
        garden.baseLikeCount = tonumber(garden.likeCount or 0) or 0
    end
    garden.likeCount = garden.baseLikeCount + (tonumber(state_.likeDeltas[key] or 0) or 0)
end

local function EnterVisitMode(garden)
    if garden == nil then return false end
    ApplyLocalLikeDelta(garden)
    state_.mode = MODE_VISIT
    state_.visitGarden = garden
    state_.stealingMode = false
    if deps_.enterVisitMode then deps_.enterVisitMode(garden) end
    return true
end

function SocialGardenSystem.Init(deps)
    deps_ = deps or {}
    state_.serverEnabled = IsClientNetworkAvailable()
    Shared.RegisterClientEvents()
    if network ~= nil and IsClientMode ~= nil and IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.SAVE_GARDEN_RESULT, "HandleGardenSaveSnapshotResult")
        SubscribeToEvent(Shared.EVENTS.GARDEN_RESPONSE, "HandleGardenSnapshotResponse")
        SubscribeToEvent(Shared.EVENTS.RANK_RESPONSE, "HandleGardenRankResponse")
        SubscribeToEvent(Shared.EVENTS.STEAL_RESPONSE, "HandleGardenStealResponse")
        SubscribeToEvent(Shared.EVENTS.SOCIAL_STATE_RESPONSE, "HandleGardenSocialStateResponse")
        SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "HandleGardenSendSeedGiftResponse")
        SubscribeToEvent(Shared.EVENTS.GIFTS_RESPONSE, "HandleGardenGiftsResponse")
        SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT_RESPONSE, "HandleGardenClaimGiftResponse")
        SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN_RESPONSE, "HandleGardenLikeGardenResponse")
        SubscribeToEvent("ServerReady", "HandleGardenServerReady")
        SocialGardenSystem.BindServerConnection()
    end
    EnsureDemoData()
end

function SocialGardenSystem.BindServerConnection()
    local conn = network ~= nil and network:GetServerConnection() or nil
    if conn ~= nil and deps_.getScene ~= nil then
        conn.scene = deps_.getScene()
        conn:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true)
        Shared.SendToServer(Shared.EVENTS.REQUEST_SOCIAL_STATE, {})
        state_.serverEnabled = true
        print("[社交花园] 已绑定后台服务器连接")
        return true
    end
    state_.serverEnabled = false
    return false
end

function SocialGardenSystem.GetSaveData()
    return {
        visitablePlotIndex = state_.visitablePlotIndex,
        daily = state_.daily,
        likedGardens = state_.likedGardens,
        likeDeltas = state_.likeDeltas,
    }
end

function SocialGardenSystem.LoadSaveData(data)
    if type(data) ~= "table" then return end
    state_.visitablePlotIndex = ClampPlotIndex(data.visitablePlotIndex or 1)
    if type(data.daily) == "table" then state_.daily = data.daily end
    if type(data.likedGardens) == "table" then state_.likedGardens = data.likedGardens end
    if type(data.likeDeltas) == "table" then state_.likeDeltas = data.likeDeltas end
end

function SocialGardenSystem.GetState()
    return state_
end

function SocialGardenSystem.IsVisitMode()
    return state_.mode == MODE_VISIT
end

function SocialGardenSystem.IsStealingMode()
    return state_.stealingMode == true
end

function SocialGardenSystem.BeginStealingMode()
    if state_.mode ~= MODE_VISIT then return false end
    state_.stealingMode = true
    if deps_.enterStealingMode then deps_.enterStealingMode(state_.visitGarden) end
    if deps_.showToast then deps_.showToast("点击成熟作物偷取种子") end
    return true
end

function SocialGardenSystem.EndStealingMode()
    if state_.mode ~= MODE_VISIT then return false end
    state_.stealingMode = false
    if deps_.exitStealingMode then deps_.exitStealingMode(state_.visitGarden) end
    return true
end

function SocialGardenSystem.GetVisitGarden()
    return state_.visitGarden
end

function SocialGardenSystem.GetVisitablePlotIndex()
    state_.visitablePlotIndex = ClampPlotIndex(state_.visitablePlotIndex)
    return state_.visitablePlotIndex
end

function SocialGardenSystem.SetVisitablePlotIndex(plotIndex)
    plotIndex = ClampPlotIndex(plotIndex)
    state_.visitablePlotIndex = plotIndex
    if deps_.showToast then deps_.showToast("已将第 " .. plotIndex .. " 块地设为可参观地块") end
    SocialGardenSystem.UploadSnapshot()
    if deps_.markDirty then deps_.markDirty() end
    if deps_.rebuildUI then deps_.rebuildUI() end
    return true
end

function SocialGardenSystem.BuildSnapshot()
    return BuildSnapshot()
end

function SocialGardenSystem.UploadSnapshot()
    local snapshot = BuildSnapshot()
    state_.lastSyncText = "同步中..."
    if SendRequest(Shared.EVENTS.SAVE_GARDEN, { snapshot = snapshot }) then
        return true
    end
    state_.lastSyncText = "本地预览"
    if clientCloud ~= nil then
        clientCloud:BatchSet()
            :Set(Shared.KEYS.GARDEN_SNAPSHOT, snapshot)
            :SetInt(Shared.KEYS.TOUR_RANK, snapshot.bestTourValue or snapshot.tourValue or 0)
            :Save("同步花园", {
                ok = function()
                    state_.lastSyncText = "已同步"
                    if deps_.showToast then deps_.showToast("花园快照已同步") end
                end,
                error = function(_, reason)
                    state_.lastSyncText = "同步失败"
                    if deps_.showToast then deps_.showToast("同步失败: " .. tostring(reason)) end
                end,
            })
    end
    return false
end

function SocialGardenSystem.RequestLeaderboard()
    state_.pending.rank = true
    if SendRequest(Shared.EVENTS.REQUEST_RANK, { count = 20 }) then return true end
    EnsureDemoData()
    state_.pending.rank = false
    return false
end

local function MergeLeaderboardWithFallback(list)
    EnsureDemoData()
    local merged = {}
    local seen = {}
    for _, entry in ipairs(list or {}) do
        if entry.userId ~= nil and not seen[tostring(entry.userId)] then
            seen[tostring(entry.userId)] = true
            merged[#merged + 1] = entry
        end
    end
    for _, entry in ipairs(GetFallbackLeaderboardEntries()) do
        if entry.userId ~= nil and not seen[tostring(entry.userId)] then
            seen[tostring(entry.userId)] = true
            local fallback = {
                rank = #merged + 1,
                userId = entry.userId,
                nickname = entry.nickname,
                score = entry.score,
                source = "fallback",
            }
            merged[#merged + 1] = fallback
        end
    end
    return merged
end

function SocialGardenSystem.GetLeaderboard()
    EnsureDemoData()
    return state_.leaderboard
end

function SocialGardenSystem.GetFriends()
    EnsureDemoData()
    local rows = {}
    local seen = {}
    for _, entry in ipairs(state_.recommendedPlayers or {}) do
        if entry.userId ~= nil and not seen[tostring(entry.userId)] then
            seen[tostring(entry.userId)] = true
            rows[#rows + 1] = entry
        end
    end
    for _, entry in ipairs(state_.friends or {}) do
        if entry.userId ~= nil and not seen[tostring(entry.userId)] then
            seen[tostring(entry.userId)] = true
            rows[#rows + 1] = entry
        end
    end
    return rows
end

function SocialGardenSystem.GetRecentVisitors()
    return state_.recentVisitors or {}
end

function SocialGardenSystem.GetStealLogs()
    return state_.stealLogs or {}
end

function SocialGardenSystem.RequestSocialState()
    if SendRequest(Shared.EVENTS.REQUEST_SOCIAL_STATE, {}) then return true end
    return false
end

local function EnterDemoGarden(userId)
    local entry = FindDemoPlayer(userId)
    if entry == nil then return false end
    local garden = BuildDemoGarden(entry.userId, entry.nickname, entry.score, tonumber(entry.userId) or 0, true)
    EnterVisitMode(garden)
    state_.pending.visit = false
    if deps_.showToast then deps_.showToast("正在拜访 " .. entry.nickname .. " 的花园") end
    return true
end

local function EnterFallbackGarden(userId)
    local entry = FindDemoPlayer(userId)
    if entry ~= nil then
        return EnterDemoGarden(userId)
    end
    local garden = BuildFallbackGarden(userId, "游客花园")
    EnterVisitMode(garden)
    state_.pending.visit = false
    if deps_.showToast then deps_.showToast("该玩家暂无花园数据，正在展示兜底花园") end
    return true
end

function SocialGardenSystem.VisitPlayer(userId)
    if userId == nil then return false end
    state_.pending.visit = true
    state_.pending.visitUserId = userId
    if SendRequest(Shared.EVENTS.REQUEST_GARDEN, { targetUserId = userId }) then return true end
    return EnterFallbackGarden(userId)
end

function SocialGardenSystem.VisitByInput(text)
    local userId = tonumber(text or "")
    if userId == nil then
        if deps_.showToast then deps_.showToast("请输入有效玩家 ID") end
        return false
    end
    return SocialGardenSystem.VisitPlayer(userId)
end

function SocialGardenSystem.ReturnHome()
    state_.mode = MODE_OWN
    state_.visitGarden = nil
    state_.stealingMode = false
    if deps_.returnHome then deps_.returnHome() end
    if deps_.showToast then deps_.showToast("已返回我的花园") end
end

function SocialGardenSystem.GetStealChanceText(crop)
    local rarity = crop and crop.rarity or crop and crop.config and crop.config.rarity or "普通"
    local chances = {
        ["普通"] = 80,
        ["罕见"] = 65,
        ["稀有"] = 48,
        ["史诗"] = 32,
        ["传奇"] = 18,
        ["神话"] = 10,
    }
    return tostring(chances[rarity] or 45) .. "%"
end

function SocialGardenSystem.RequestStealAtLocalPosition(localPos)
    if not SocialGardenSystem.IsStealingMode() then
        SocialGardenSystem.BeginStealingMode()
        return false
    end
    local garden = state_.visitGarden
    local crops = SocialGardenSystem.GetVisitCrops()
    if garden == nil or localPos == nil or #crops == 0 then
        if deps_.showToast then deps_.showToast("这里没有可偷取的成熟作物") end
        return false
    end
    local bestIndex = nil
    local bestCrop = nil
    local bestDist = 9999
    for index, crop in ipairs(crops) do
        if crop.mature == true and crop.stolen ~= true and crop.localPos ~= nil then
            local dx = (crop.localPos.x or 0) - localPos.x
            local dz = (crop.localPos.z or 0) - localPos.z
            local dist = dx * dx + dz * dz
            local radius = math.max(0.55, crop.pickRadius or 0.55)
            if dist <= radius * radius and dist < bestDist then
                bestDist = dist
                bestIndex = index
                bestCrop = crop
            end
        end
    end
    if bestCrop == nil then
        if deps_.showToast then deps_.showToast("请点击成熟且未偷过的作物") end
        return false
    end
    return SocialGardenSystem.RequestSteal(bestIndex, bestCrop.cropId)
end

local ResolveLocalSteal = nil

function SocialGardenSystem.RequestSteal(cropIndex, cropId)
    local garden = state_.visitGarden
    if garden == nil then return false end
    cropIndex = cropIndex or 1
    if garden.isFallback == true and ResolveLocalSteal ~= nil then
        return ResolveLocalSteal(cropIndex, cropId)
    end
    if SendRequest(Shared.EVENTS.REQUEST_STEAL, { targetUserId = garden.userId, cropIndex = cropIndex, cropId = cropId }) then
        return true
    end
    if (state_.daily.stealCount or 0) >= DAILY_STEAL_LIMIT then
        if deps_.showToast then deps_.showToast("今日偷菜次数已用完") end
        return false
    end
    local crop = garden.plot and garden.plot.plants and garden.plot.plants[cropIndex]
    if crop ~= nil and crop.stolen == true then
        if deps_.showToast then deps_.showToast("这株作物已经偷过了") end
        return false
    end
    state_.daily.stealCount = (state_.daily.stealCount or 0) + 1
    local seedId = 1
    if crop ~= nil and crop.plantIndex ~= nil then seedId = crop.plantIndex end
    local reward = math.random() <= 0.72 and { type = "seed", seedId = seedId, count = 1 } or { type = "none" }
    ApplyStealReward(reward)
    SocialGardenSystem.MarkVisitCropStolen(cropId or (crop and crop.cropId), cropIndex)
    if deps_.showToast then
        if reward.type == "seed" then
            deps_.showToast("偷取成功，获得该作物种子 x1")
        else
            deps_.showToast("偷取成功，但没有获得种子")
        end
    end
    if deps_.markDirty then deps_.markDirty() end
    if deps_.rebuildUI then deps_.rebuildUI() end
    return true
end

function SocialGardenSystem.SendSeedGift(targetUserId, seedId)
    targetUserId = tonumber(targetUserId or 0)
    seedId = tonumber(seedId or 1) or 1
    if targetUserId <= 0 then
        if deps_.showToast then deps_.showToast("请输入好友玩家 ID") end
        return false
    end
    if SendRequest(Shared.EVENTS.SEND_SEED_GIFT, { targetUserId = targetUserId, seedId = seedId, count = 1 }) then
        return true
    end
    if (state_.daily.giftSentCount or 0) >= DAILY_GIFT_LIMIT then
        if deps_.showToast then deps_.showToast("今日赠送次数已用完") end
        return false
    end
    state_.daily.giftSentCount = (state_.daily.giftSentCount or 0) + 1
    if deps_.showToast then deps_.showToast("已向好友发送种子礼物") end
    return true
end

function SocialGardenSystem.RequestGifts()
    if SendRequest(Shared.EVENTS.REQUEST_GIFTS, {}) then return true end
    return false
end

function SocialGardenSystem.GetGifts()
    return state_.gifts
end

function SocialGardenSystem.ClaimGift(gift)
    if gift == nil then return false end
    if SendRequest(Shared.EVENTS.CLAIM_GIFT, { giftId = gift.giftId, seedId = gift.seedId, count = gift.count }) then
        return true
    end
    local ok = ApplyGiftReward(gift)
    if ok then
        gift.claimed = true
        if deps_.showToast then deps_.showToast("已领取好友种子") end
        if deps_.markDirty then deps_.markDirty() end
    end
    return ok
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

local function ShowStealResult(message)
    if deps_.showToast then deps_.showToast(message) end
    if deps_.showFloatingToast then deps_.showFloatingToast(message) end
end

ResolveLocalSteal = function(cropIndex, cropId)
    local garden = state_.visitGarden
    local crop = garden and garden.plot and garden.plot.plants and garden.plot.plants[cropIndex]
    if crop == nil then
        ShowStealResult("没有点中可偷取的作物")
        return false
    end
    if crop.mature ~= true then
        ShowStealResult("只能偷成熟作物")
        return false
    end
    if crop.stolen == true then
        ShowStealResult("这株作物已经偷过了")
        return false
    end
    state_.daily.stealCount = (state_.daily.stealCount or 0) + 1
    local chance = GetStealChance(crop)
    local reward = math.random() <= chance and { type = "seed", seedId = crop.plantIndex or 1, count = 1 } or { type = "none" }
    ApplyStealReward(reward)
    SocialGardenSystem.MarkVisitCropStolen(cropId or crop.cropId, cropIndex)
    if reward.type == "seed" then
        ShowStealResult("偷取成功，获得" .. tostring(crop.name or "作物") .. "种子 x1")
    else
        ShowStealResult("偷取成功，但没有获得种子")
    end
    if deps_.markDirty then deps_.markDirty() end
    if deps_.rebuildUI then deps_.rebuildUI() end
    return true
end

function SocialGardenSystem.GetVisitTourValue()
    local garden = state_.visitGarden
    return tonumber(garden and (garden.tourValue or garden.bestTourValue) or 0) or 0
end

function SocialGardenSystem.GetVisitLikeCount()
    local garden = state_.visitGarden
    return tonumber(garden and garden.likeCount or 0) or 0
end

function SocialGardenSystem.HasLikedVisitGarden()
    local garden = state_.visitGarden
    if garden == nil then return false end
    if garden.isFallback ~= true then return false end
    return state_.likedGardens[tostring(garden.userId or "fallback")] == true
end

function SocialGardenSystem.ApplyLocalLike(garden)
    if garden == nil then return false end
    local key = tostring(garden.userId or "fallback")
    state_.likedGardens[key] = true
    state_.likeDeltas[key] = (tonumber(state_.likeDeltas[key] or 0) or 0) + 1
    if garden.baseLikeCount == nil then
        garden.baseLikeCount = tonumber(garden.likeCount or 0) or 0
    end
    garden.likeCount = garden.baseLikeCount + (tonumber(state_.likeDeltas[key] or 0) or 0)
    if deps_.showToast then deps_.showToast("已点赞这个花园") end
    if deps_.rebuildUI then deps_.rebuildUI() end
    if deps_.markDirty then deps_.markDirty() end
    return true
end

function SocialGardenSystem.LikeVisitGarden()
    local garden = state_.visitGarden
    if garden == nil then return false end
    local key = tostring(garden.userId or "fallback")
    if garden.isFallback ~= true then
        if SendRequest(Shared.EVENTS.LIKE_GARDEN, { targetUserId = garden.userId }) then
            return true
        end
    end
    if state_.likedGardens[key] == true then
        if deps_.showToast then deps_.showToast("已经点赞过这个花园了") end
        return false
    end
    return SocialGardenSystem.ApplyLocalLike(garden)
end

function SocialGardenSystem.GetMatureVisitCrops()
    local rows = {}
    for index, crop in ipairs(SocialGardenSystem.GetVisitCrops()) do
        if crop.mature == true then
            rows[#rows + 1] = { index = index, crop = crop }
        end
    end
    return rows
end

function SocialGardenSystem.GetVisitCrops()
    local garden = state_.visitGarden
    if garden == nil or garden.plot == nil or type(garden.plot.plants) ~= "table" then
        return {}
    end
    return garden.plot.plants
end

function SocialGardenSystem.CountStealableCrops()
    local count = 0
    for _, crop in ipairs(SocialGardenSystem.GetVisitCrops()) do
        if crop.mature == true and crop.stolen ~= true then count = count + 1 end
    end
    return count
end

function SocialGardenSystem.MarkVisitCropStolen(cropId, cropIndex)
    local crops = SocialGardenSystem.GetVisitCrops()
    for index, crop in ipairs(crops) do
        if (cropId ~= nil and crop.cropId == cropId) or (cropIndex ~= nil and index == cropIndex) then
            crop.stolen = true
            return true
        end
    end
    return false
end

function SocialGardenSystem.GetDailyText()
    return string.format("偷菜 %d/%d · 赠送 %d/%d", state_.daily.stealCount or 0, DAILY_STEAL_LIMIT, state_.daily.giftSentCount or 0, DAILY_GIFT_LIMIT)
end

function SocialGardenSystem.HandleSaveSnapshotResult(data)
    state_.lastSyncText = data.success and "已同步" or "同步失败"
    if deps_.showToast then deps_.showToast(data.message or state_.lastSyncText) end
end

function SocialGardenSystem.HandleGardenResponse(data)
    local pendingUserId = state_.pending.visitUserId
    state_.pending.visit = false
    state_.pending.visitUserId = nil
    if not data.success then
        if pendingUserId ~= nil and EnterFallbackGarden(pendingUserId) then return end
        if deps_.showToast then deps_.showToast(data.message or "花园读取失败") end
        return
    end
    EnterVisitMode(data.garden)
    if deps_.showToast then deps_.showToast("正在拜访 " .. (data.garden.nickname or "好友") .. " 的花园") end
end

function SocialGardenSystem.HandleRankResponse(data)
    state_.pending.rank = false
    if data.success and type(data.list) == "table" then
        state_.leaderboard = MergeLeaderboardWithFallback(data.list)
        if deps_.rebuildUI then deps_.rebuildUI() end
    elseif deps_.showToast then
        deps_.showToast(data.message or "排行榜读取失败")
    end
end

function SocialGardenSystem.HandleStealResponse(data)
    if data.success then
        SocialGardenSystem.MarkVisitCropStolen(data.cropId, data.cropIndex)
        if data.reward ~= nil then ApplyStealReward(data.reward) end
        if data.daily ~= nil then state_.daily.stealCount = data.daily.stealCount or state_.daily.stealCount end
        SocialGardenSystem.RequestSocialState()
        if deps_.showToast then deps_.showToast(data.message or "偷菜成功") end
        if deps_.markDirty then deps_.markDirty() end
        if deps_.rebuildUI then deps_.rebuildUI() end
    elseif deps_.showToast then
        deps_.showToast(data.message or "偷菜失败")
    end
end

function SocialGardenSystem.HandleSocialStateResponse(data)
    if data.success then
        if type(data.recommendedPlayers) == "table" then state_.recommendedPlayers = data.recommendedPlayers end
        if type(data.recentVisitors) == "table" then state_.recentVisitors = data.recentVisitors end
        if type(data.stealLogs) == "table" then state_.stealLogs = data.stealLogs end
        if deps_.rebuildUI then deps_.rebuildUI() end
    elseif deps_.showToast then
        deps_.showToast(data.message or "社交数据读取失败")
    end
end

function SocialGardenSystem.HandleSendSeedGiftResponse(data)
    if data.success then
        if data.daily ~= nil then state_.daily.giftSentCount = data.daily.giftSentCount or state_.daily.giftSentCount end
        if deps_.showToast then deps_.showToast(data.message or "种子已送出") end
    elseif deps_.showToast then
        deps_.showToast(data.message or "赠送失败")
    end
end

function SocialGardenSystem.HandleLikeGardenResponse(data)
    local garden = state_.visitGarden
    if data.success then
        if garden ~= nil then
            local key = tostring(garden.userId or "fallback")
            state_.likedGardens[key] = true
            garden.baseLikeCount = tonumber(data.likeCount or garden.baseLikeCount or garden.likeCount or 0) or 0
            state_.likeDeltas[key] = 0
            garden.likeCount = garden.baseLikeCount
        end
        if deps_.showToast then deps_.showToast(data.message or "已点赞这个花园") end
        if deps_.rebuildUI then deps_.rebuildUI() end
        if deps_.markDirty then deps_.markDirty() end
    else
        if data.alreadyLiked == true and garden ~= nil then
            local key = tostring(garden.userId or "fallback")
            state_.likedGardens[key] = true
            if data.likeCount ~= nil then
                garden.baseLikeCount = tonumber(data.likeCount) or tonumber(garden.likeCount or 0) or 0
                garden.likeCount = garden.baseLikeCount
            end
            if deps_.rebuildUI then deps_.rebuildUI() end
            if deps_.markDirty then deps_.markDirty() end
        end
        if deps_.showToast then deps_.showToast(data.message or "点赞失败") end
    end
end

function SocialGardenSystem.HandleGiftsResponse(data)
    if data.success and type(data.gifts) == "table" then
        state_.gifts = data.gifts
    elseif deps_.showToast then
        deps_.showToast(data.message or "礼物读取失败")
    end
end

function SocialGardenSystem.HandleClaimGiftResponse(data)
    if data.success then
        ApplyGiftReward(data.gift or data.reward)
        if deps_.showToast then deps_.showToast(data.message or "礼物已领取") end
        SocialGardenSystem.RequestGifts()
        if deps_.markDirty then deps_.markDirty() end
    elseif deps_.showToast then
        deps_.showToast(data.message or "领取失败")
    end
end

function HandleGardenSaveSnapshotResult(eventType, eventData)
    SocialGardenSystem.HandleSaveSnapshotResult(Shared.ReadEventData(eventData))
end

function HandleGardenSnapshotResponse(eventType, eventData)
    SocialGardenSystem.HandleGardenResponse(Shared.ReadEventData(eventData))
end

function HandleGardenRankResponse(eventType, eventData)
    SocialGardenSystem.HandleRankResponse(Shared.ReadEventData(eventData))
end

function HandleGardenStealResponse(eventType, eventData)
    SocialGardenSystem.HandleStealResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSocialStateResponse(eventType, eventData)
    SocialGardenSystem.HandleSocialStateResponse(Shared.ReadEventData(eventData))
end

function HandleGardenSendSeedGiftResponse(eventType, eventData)
    SocialGardenSystem.HandleSendSeedGiftResponse(Shared.ReadEventData(eventData))
end

function HandleGardenGiftsResponse(eventType, eventData)
    SocialGardenSystem.HandleGiftsResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClaimGiftResponse(eventType, eventData)
    SocialGardenSystem.HandleClaimGiftResponse(Shared.ReadEventData(eventData))
end

function HandleGardenLikeGardenResponse(eventType, eventData)
    SocialGardenSystem.HandleLikeGardenResponse(Shared.ReadEventData(eventData))
end

function HandleGardenServerReady(eventType, eventData)
    SocialGardenSystem.BindServerConnection()
    SocialGardenSystem.RequestSocialState()
    SocialGardenSystem.UploadSnapshot()
end

return SocialGardenSystem
