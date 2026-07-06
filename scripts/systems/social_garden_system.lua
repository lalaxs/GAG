-- ============================================================================
-- 社交花园系统
-- ============================================================================
-- 管理可参观地块、花园快照、排行榜拜访、偷菜、好友赠送种子。
-- 多人服务器模式下通过远程事件请求服务端；单机/预览环境使用本地模拟数据。
-- ============================================================================

local Shared = require("network.shared")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local RequestStateMachine = require("client.request_state_machine")
local ServerConfig = require("config.server_tuning")
local SocialSnapshot = require("systems.social.social_snapshot")
local NetworkClient = require("client.network_client")
local UserId = require("utils.user_id")

local SocialGardenSystem = {}

local MODE_OWN = "own"
local MODE_VISIT = "visit"
local DAILY_STEAL_LIMIT = ServerConfig.Tuning.dailyStealLimit
local DAILY_GIFT_LIMIT = ServerConfig.Tuning.dailyGiftLimit
local STEAL_REQUEST_COOLDOWN = 1
local STEAL_RATE_LIMIT_BACKOFF = 8
local SOCIAL_STATE_REFRESH_DELAY = 2
local ALLOW_DEMO_SOCIAL = false
local ALLOW_DEMO_ECONOMY_REWARDS = false

local deps_ = {}
local snapshotHelper_ = nil
local requests_ = RequestStateMachine.Create("social", { timeout = 25.0 })
local EmitSocialChanged = nil
local EnterFallbackGarden = nil
local state_ = {
    mode = MODE_OWN,
    visitablePlotIndex = 1,
    visitGarden = nil,
    leaderboard = {},
    gifts = {},
    friends = {},
    friendRequests = {},
    socialNotices = {},
    giftedTargets = {},
    recommendedPlayers = {},
    recentVisitors = {},
    stealLogs = {},
    pending = {},
    daily = {
        stealCount = 0,
        giftSentCount = 0,
        stealLimit = DAILY_STEAL_LIMIT,
        stealAdCount = 0,
        stealAdLimit = 5,
        seedPackAdCount = 0,
        seedPackAdLimit = 5,
        matureAdCount = 0,
        matureAdLimit = 5,
    },
    lastSyncText = "未同步",
    serverEnabled = false,
    socialSaveLoaded = false,
    socialStateSynced = false,
    boundConnectionKey = nil,
    stealingMode = false,
    lastStealRequestAt = 0,
    stealBackoffUntil = 0,
    socialStateRefreshAt = nil,
    socialStateRefreshReason = nil,
    likedGardens = {},
    likeDeltas = {},
}

local function IsClientNetworkAvailable()
    return NetworkClient.IsRawConnected()
end

local function GetNow()
    return os and os.time and os.time() or 0
end

local function NormalizeUserId(userId)
    return UserId.Normalize(userId)
end

local function BeginRequest(requestType, payload)
    local nextPayload = payload or {}
    nextPayload = requests_:Begin(requestType, nextPayload)
    requests_:SyncLegacyPending(state_.pending)
    return nextPayload
end

local function FinishRequest(requestId, requestType)
    local record = requests_:Finish(requestId, requestType)
    requests_:SyncLegacyPending(state_.pending)
    return record
end

local function FinishRequestExact(requestId)
    local record = nil
    if requestId ~= nil and requestId ~= "" then
        record = requests_:Finish(tostring(requestId))
    end
    requests_:SyncLegacyPending(state_.pending)
    return record
end

local function MarkGiftTarget(targetUserId, value)
    if targetUserId == nil then return end
    state_.giftedTargets[tostring(targetUserId)] = value == true or nil
end

local function RemoveFriendRequestLocally(request)
    if request == nil then return false end
    local requestId = request.requestId or request.listId
    local fromUserId = request.fromUserId
    local removed = false
    for i = #state_.friendRequests, 1, -1 do
        local entry = state_.friendRequests[i]
        if entry ~= nil then
            local entryId = entry.requestId or entry.listId
            local sameId = requestId ~= nil and entryId ~= nil and tostring(entryId) == tostring(requestId)
            local sameSender = fromUserId ~= nil and entry.fromUserId ~= nil and tostring(entry.fromUserId) == tostring(fromUserId)
            if sameId or sameSender then
                table.remove(state_.friendRequests, i)
                removed = true
            end
        end
    end
    return removed
end

local function ShouldRollbackGiftTarget(targetUserId)
    if targetUserId == nil then return false end
    local targetKey = tostring(targetUserId)
    for _, record in pairs(requests_.byId or {}) do
        if record.type == "gift" and record.payload ~= nil and tostring(record.payload.targetUserId) == targetKey then
            return false
        end
    end
    return true
end

local function ClampPlotIndex(index)
    local unlocked = deps_.getUnlockedPlotCount and deps_.getUnlockedPlotCount() or 1
    return Clamp(tonumber(index or 1) or 1, 1, math.max(1, unlocked))
end

local function GetDisplayName()
    if deps_.getDisplayName then return deps_.getDisplayName() end
    return "Tap玩家"
end

local function ShowToastMessage(message, floating)
    if deps_.showToast then deps_.showToast(message) end
    if floating == true and deps_.showFloatingToast then deps_.showFloatingToast(message) end
end

local function GetDailyStealLimit()
    return math.max(DAILY_STEAL_LIMIT, math.floor(tonumber(state_.daily.stealLimit or DAILY_STEAL_LIMIT) or DAILY_STEAL_LIMIT))
end

local function GetStealCount()
    return math.max(0, math.floor(tonumber(state_.daily.stealCount or 0) or 0))
end

local function HasStealAttemptsLeft()
    return GetStealCount() < GetDailyStealLimit()
end

local function ShowStealLimitInsufficient()
    ShowToastMessage("偷取次数不足", true)
end

local function IsStealLimitError(data)
    if data == nil then return false end
    return data.code == "STEAL_LIMIT_REACHED" or data.message == "偷取次数不足"
end

local function IsCloudRateLimitError(data)
    if data == nil then return false end
    local message = tostring(data.message or "")
    return string.find(message, "read rate limit exceeded", 1, true) ~= nil
end

local function ScheduleSocialStateRefresh(reason)
    local nextAt = GetNow() + SOCIAL_STATE_REFRESH_DELAY
    if state_.socialStateRefreshAt == nil or nextAt < state_.socialStateRefreshAt then
        state_.socialStateRefreshAt = nextAt
    end
    state_.socialStateRefreshReason = reason or state_.socialStateRefreshReason or "deferred"
end

local function FlushScheduledSocialStateRefresh()
    if state_.socialStateRefreshAt == nil then return end
    if GetNow() < state_.socialStateRefreshAt then return end
    if requests_:IsPending("socialState") then return end
    local reason = state_.socialStateRefreshReason or "deferred"
    state_.socialStateRefreshAt = nil
    state_.socialStateRefreshReason = nil
    SocialGardenSystem.RequestSocialState({ reason = reason })
end

local function GetSeedDisplayName(seedId, cropIndex)
    local plants = deps_.getPlants and deps_.getPlants() or {}
    local plant = plants[tonumber(seedId or 0) or 0]
    if plant ~= nil and plant.name ~= nil and plant.name ~= "" then
        return tostring(plant.name)
    end
    local crop = state_.visitGarden and state_.visitGarden.plot and state_.visitGarden.plot.plants and state_.visitGarden.plot.plants[cropIndex]
    if crop ~= nil and crop.name ~= nil and crop.name ~= "" then
        return tostring(crop.name)
    end
    return "作物"
end

local function BuildStealFloatingMessage(data)
    local reward = data and data.reward or nil
    if reward ~= nil and reward.type == "seed" then
        local count = math.max(1, math.floor(tonumber(reward.count or 1) or 1))
        local seedName = GetSeedDisplayName(reward.seedId, data.cropIndex)
        return "偷取成功，获得" .. seedName .. "种子 x" .. tostring(count)
    end
    if reward ~= nil and reward.type == "none" then
        return "偷取成功，但没有获得种子"
    end
    return data and data.message or "偷菜成功"
end

local function GetAvatarProfile()
    if deps_.getAvatarProfile then return deps_.getAvatarProfile() end
    return nil
end

local function GetUserId()
    if deps_.getUserId then return UserId.Normalize(deps_.getUserId()) end
    if clientCloud ~= nil and clientCloud.userId ~= nil then return UserId.Normalize(clientCloud.userId) end
    return nil
end

local function IsFriendUser(userId)
    local normalized = NormalizeUserId(userId)
    if normalized == nil then return false end
    for _, friend in ipairs(state_.friends or {}) do
        if NormalizeUserId(friend.userId or friend.friendUserId) == normalized then return true end
    end
    return false
end

local function IsInvalidFriendRequest(request)
    if type(request) ~= "table" then return true end
    local selfUserId = NormalizeUserId(GetUserId())
    local fromUserId = NormalizeUserId(request.fromUserId)
    local targetUserId = NormalizeUserId(request.targetUserId)
    if fromUserId == nil then return true end
    if selfUserId ~= nil and fromUserId == selfUserId then return true end
    if selfUserId ~= nil and targetUserId ~= nil and targetUserId ~= selfUserId then return true end
    if IsFriendUser(fromUserId) then return true end
    return false
end

local function FilterFriendRequests(requests)
    local result = {}
    for _, request in ipairs(requests or {}) do
        if IsInvalidFriendRequest(request) then
            print(string.format("[社交健康] 客户端过滤异常好友申请 from=%s target=%s", tostring(request and request.fromUserId), tostring(request and request.targetUserId)))
        else
            result[#result + 1] = request
        end
    end
    return result
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
            price = plant.seedPrice or plant.fruitPrice or 10,
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
    if ALLOW_DEMO_SOCIAL ~= true then return end
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
    return NetworkClient.SendRequest(eventName, payload)
end

local function ApplyGiftReward(gift)
    if ALLOW_DEMO_ECONOMY_REWARDS ~= true then return false end
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
    if ALLOW_DEMO_ECONOMY_REWARDS ~= true then return false end
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
    snapshotHelper_ = SocialSnapshot.create(deps_, state_, {
        clampPlotIndex = ClampPlotIndex,
        getNow = GetNow,
    })
    state_.serverEnabled = IsClientNetworkAvailable()
    Shared.RegisterClientEvents()
    if NetworkClient.IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.SAVE_GARDEN_RESULT, "HandleGardenSaveSnapshotResult")
        SubscribeToEvent(Shared.EVENTS.GARDEN_RESPONSE, "HandleGardenSnapshotResponse")
        SubscribeToEvent(Shared.EVENTS.RANK_RESPONSE, "HandleGardenRankResponse")
        SubscribeToEvent(Shared.EVENTS.STEAL_RESPONSE, "HandleGardenStealResponse")
        SubscribeToEvent(Shared.EVENTS.SOCIAL_STATE_RESPONSE, "HandleGardenSocialStateResponse")
        SubscribeToEvent(Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "HandleGardenSendSeedGiftResponse")
        SubscribeToEvent(Shared.EVENTS.GIFTS_RESPONSE, "HandleGardenGiftsResponse")
        SubscribeToEvent(Shared.EVENTS.CLAIM_GIFT_RESPONSE, "HandleGardenClaimGiftResponse")
        SubscribeToEvent(Shared.EVENTS.LIKE_GARDEN_RESPONSE, "HandleGardenLikeGardenResponse")
        SubscribeToEvent(Shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, "HandleGardenSendFriendRequestResponse")
        SubscribeToEvent(Shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, "HandleGardenRespondFriendRequestResponse")
        SubscribeToEvent(Shared.EVENTS.REMOVE_FRIEND_RESPONSE, "HandleGardenRemoveFriendResponse")
        SubscribeToEvent(Shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, "HandleGardenClearSocialMessagesResponse")
    end
    EnsureDemoData()
end

function SocialGardenSystem.IsServerBound()
    return state_.serverEnabled == true and state_.boundConnectionKey ~= nil
end

function SocialGardenSystem.BindServerConnection(forceReady)
    local conn = NetworkClient.GetConnection()
    if conn ~= nil and deps_.getScene ~= nil then
        local scene = deps_.getScene()
        if scene == nil then
            return false, false
        end
        NetworkClient.EnsureConnectionScene(deps_.getScene)
        conn.scene = scene
        local connectionKey = "connected"
        if forceReady ~= true and state_.serverEnabled == true and state_.boundConnectionKey == connectionKey then
            return true, false
        end
        state_.boundConnectionKey = connectionKey
        conn:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true)
        -- 社交状态由服务端 CLIENT_READY → SendFullSync 推送；重连走 SessionSync / NetworkRecovery。
        state_.serverEnabled = true
        print("[社交花园] 已绑定后台服务器连接并发送客户端就绪")
        if deps_.onServerBound ~= nil then deps_.onServerBound() end
        return true, true
    end
    state_.serverEnabled = false
    state_.boundConnectionKey = nil
    return false, false
end

function SocialGardenSystem.RequestFullSync(reason)
    if not IsClientNetworkAvailable() then return false end
    return SendRequest(Shared.EVENTS.REQUEST_FULL_SYNC, { reason = reason or "manual" })
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
    state_.socialSaveLoaded = true
    if type(data) ~= "table" then return end
    state_.visitablePlotIndex = math.max(1, math.floor(tonumber(data.visitablePlotIndex or 1) or 1))
    if type(data.daily) == "table" then state_.daily = data.daily end
    if type(data.likedGardens) == "table" then state_.likedGardens = data.likedGardens end
    if type(data.likeDeltas) == "table" then state_.likeDeltas = data.likeDeltas end
end

function SocialGardenSystem.IsSocialSaveLoaded()
    return state_.socialSaveLoaded == true
end

function SocialGardenSystem.GetState()
    return state_
end

function SocialGardenSystem.Update(_dt)
    requests_:Update(function(record)
        requests_:SyncLegacyPending(state_.pending)
        state_.lastSyncText = "请求超时"
        if record.type == "visit" then
            if record.payload ~= nil and record.payload.targetUserId ~= nil then
                EnterFallbackGarden(record.payload.targetUserId)
            elseif deps_.showToast then
                deps_.showToast("拜访超时")
            end
        elseif record.type == "steal" then
            SocialGardenSystem.MarkVisitCropStealPending(record.payload and record.payload.cropId, record.payload and record.payload.cropIndex, false)
            if deps_.showToast then
                deps_.showToast("偷菜超时")
            end
        elseif deps_.showToast then
            deps_.showToast("社交同步中")
        end
        if record.type ~= "socialState" then
            SocialGardenSystem.RequestSocialState({ force = true, reason = "timeout_" .. tostring(record.type) })
        end
        print("[社交花园] 请求超时: " .. tostring(record.type) .. " " .. tostring(record.id))
    end)
    FlushScheduledSocialStateRefresh()
end

function SocialGardenSystem.IsVisitMode()
    return state_.mode == MODE_VISIT
end

function SocialGardenSystem.IsStealingMode()
    return state_.stealingMode == true
end

function SocialGardenSystem.BeginStealingMode()
    if state_.mode ~= MODE_VISIT then return false end
    if not HasStealAttemptsLeft() then
        ShowStealLimitInsufficient()
        return false
    end
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
    state_.socialSaveLoaded = true
    if deps_.showToast then deps_.showToast("已将第 " .. plotIndex .. " 块地设为可参观地块") end
    SocialGardenSystem.UploadSnapshot({ force = true })
    if deps_.markDirty then deps_.markDirty() end
    EmitSocialChanged("updated")
    return true
end

function SocialGardenSystem.BuildSnapshot()
    if snapshotHelper_ == nil then return {} end
    return snapshotHelper_.BuildSnapshot()
end

function SocialGardenSystem.UploadSnapshot(options)
    options = options or {}
    if state_.mode ~= MODE_OWN then
        print("[社交花园] 当前处于拜访模式，跳过花园快照上传")
        return false
    end
    if options.force ~= true and state_.socialSaveLoaded ~= true then
        print("[社交花园] 社交存档尚未恢复，跳过自动花园快照上传")
        return false
    end
    local snapshot = SocialGardenSystem.BuildSnapshot()
    state_.lastSyncText = "同步中..."
    local payload = BeginRequest("saveGarden", { snapshot = snapshot })
    if SendRequest(Shared.EVENTS.SAVE_GARDEN, payload) then
        return true
    end
    FinishRequest(payload.requestId, "saveGarden")
    state_.lastSyncText = "等待服务器"
    if deps_.showToast then deps_.showToast("服务器未连接，花园快照暂未同步") end
    return false
end

function SocialGardenSystem.RequestLeaderboard()
    local payload = BeginRequest("rank", { count = 20 })
    if SendRequest(Shared.EVENTS.REQUEST_RANK, payload) then return true end
    FinishRequest(payload.requestId, "rank")
    if ALLOW_DEMO_SOCIAL then EnsureDemoData() end
    if deps_.showToast then deps_.showToast("网络异常，排行榜暂时无法读取") end
    return false
end

local function MergeLeaderboardWithFallback(list)
    if ALLOW_DEMO_SOCIAL ~= true then return list or {} end
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
    if ALLOW_DEMO_SOCIAL then EnsureDemoData() end
    return state_.leaderboard
end

function SocialGardenSystem.GetFriends()
    if ALLOW_DEMO_SOCIAL then EnsureDemoData() end
    return state_.friends or {}
end

function SocialGardenSystem.IsSocialStateLoading()
    return requests_:IsPending("socialState")
end

function SocialGardenSystem.HasSocialStateSynced()
    return state_.socialStateSynced == true
end

function SocialGardenSystem.GetRecentVisitors()
    return state_.recentVisitors or {}
end

function SocialGardenSystem.GetStealLogs()
    return state_.stealLogs or {}
end

function SocialGardenSystem.RequestSocialState(options)
    options = options or {}
    if options.force == true then requests_:Cancel("socialState") end
    if requests_:IsPending("socialState") then return true end
    local payload = BeginRequest("socialState", { userId = GetUserId(), reason = options.reason or "sync" })
    if SendRequest(Shared.EVENTS.REQUEST_SOCIAL_STATE, payload) then return true end
    FinishRequest(payload.requestId, "socialState")
    return false
end

local function EnterDemoGarden(userId)
    local entry = FindDemoPlayer(userId)
    if entry == nil then return false end
    local garden = BuildDemoGarden(entry.userId, entry.nickname, entry.score, tonumber(entry.userId) or 0, true)
    EnterVisitMode(garden)
    FinishRequest(nil, "visit")
    if deps_.showToast then deps_.showToast("正在拜访 " .. entry.nickname .. " 的花园") end
    return true
end

EnterFallbackGarden = function(userId)
    if ALLOW_DEMO_SOCIAL ~= true then
        FinishRequest(nil, "visit")
        if deps_.showToast then deps_.showToast("网络异常，无法拜访该花园") end
        return false
    end
    local entry = FindDemoPlayer(userId)
    if entry ~= nil then
        return EnterDemoGarden(userId)
    end
    local garden = BuildFallbackGarden(userId, "游客花园")
    EnterVisitMode(garden)
    FinishRequest(nil, "visit")
    if deps_.showToast then deps_.showToast("该玩家暂无花园数据，正在展示兜底花园") end
    return true
end

function SocialGardenSystem.VisitPlayer(userId)
    if userId == nil then return false end
    local pendingVisit = requests_:GetPending("visit")
    if pendingVisit ~= nil and pendingVisit.payload ~= nil and tostring(pendingVisit.payload.targetUserId) == tostring(userId) then
        if deps_.showToast then deps_.showToast("正在拜访该花园，请稍候") end
        return false
    end
    local payload = BeginRequest("visit", { targetUserId = NormalizeUserId(userId) or userId })
    state_.pending.visitUserId = NormalizeUserId(userId) or userId
    if SendRequest(Shared.EVENTS.REQUEST_GARDEN, payload) then
        if deps_.showToast then deps_.showToast("正在前往对方花园...") end
        return true
    end
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
    if not HasStealAttemptsLeft() then
        ShowStealLimitInsufficient()
        return false
    end
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
        if crop.mature == true and crop.stolen ~= true and crop.stealPending ~= true and crop.localPos ~= nil then
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
    if requests_:IsPending("steal") then
        if deps_.showToast then deps_.showToast("正在偷菜，请稍候") end
        return false
    end
    local now = GetNow()
    if now < (state_.stealBackoffUntil or 0) then
        if deps_.showToast then deps_.showToast("服务器繁忙，请稍后再偷菜") end
        return false
    end
    if now - (state_.lastStealRequestAt or 0) < STEAL_REQUEST_COOLDOWN then
        if deps_.showToast then deps_.showToast("操作太快，请稍候") end
        return false
    end
    if not HasStealAttemptsLeft() then
        ShowStealLimitInsufficient()
        return false
    end
    cropIndex = cropIndex or 1
    if garden.isFallback == true and ResolveLocalSteal ~= nil then
        return ResolveLocalSteal(cropIndex, cropId)
    end
    local payload = BeginRequest("steal", { targetUserId = garden.userId, cropIndex = cropIndex, cropId = cropId })
    if SendRequest(Shared.EVENTS.REQUEST_STEAL, payload) then
        state_.lastStealRequestAt = now
        SocialGardenSystem.MarkVisitCropStealPending(cropId, cropIndex, true)
        return true
    end
    FinishRequest(payload.requestId, "steal")
    SocialGardenSystem.MarkVisitCropStealPending(cropId, cropIndex, false)
    if ALLOW_DEMO_SOCIAL ~= true then
        if deps_.showToast then deps_.showToast("网络异常，偷菜失败") end
        return false
    end
    if not HasStealAttemptsLeft() then
        ShowStealLimitInsufficient()
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
    EmitSocialChanged("updated")
    return true
end

function SocialGardenSystem.GetFriendRequests()
    return state_.friendRequests or {}
end

function SocialGardenSystem.GetSocialNotices()
    return state_.socialNotices or {}
end

function SocialGardenSystem.HasGiftedToday(targetUserId)
    return state_.giftedTargets ~= nil and state_.giftedTargets[tostring(targetUserId)] == true
end

function SocialGardenSystem.SendFriendRequest(targetUserId)
    local normalizedTargetUserId = NormalizeUserId(targetUserId)
    if normalizedTargetUserId == nil then
        if deps_.showToast then deps_.showToast("请输入有效玩家 ID") end
        return false
    end
    if normalizedTargetUserId == NormalizeUserId(GetUserId()) then
        if deps_.showToast then deps_.showToast("不能添加自己为好友") end
        return false
    end
    local payload = BeginRequest("friendRequest", {
        targetUserId = normalizedTargetUserId,
        profile = {
            nickname = GetDisplayName(),
            avatar = GetAvatarProfile(),
        },
    })
    if SendRequest(Shared.EVENTS.SEND_FRIEND_REQUEST, payload) then
        if deps_.showToast then deps_.showToast("已发出好友申请") end
        return true
    end
    FinishRequest(payload.requestId, "friendRequest")
    if deps_.showToast then deps_.showToast("网络异常，好友申请发送失败") end
    return false
end

function SocialGardenSystem.RespondFriendRequest(request, accepted)
    if request == nil then return false end
    if IsInvalidFriendRequest(request) then
        if RemoveFriendRequestLocally(request) then EmitSocialChanged("updated") end
        if deps_.showToast then deps_.showToast("已清理异常好友申请") end
        SocialGardenSystem.RequestSocialState({ force = true, reason = "invalid_friend_request" })
        return true
    end
    local payload = BeginRequest("friendRespond", {
        requestIdValue = request.requestId or request.listId,
        fromUserId = request.fromUserId,
        accepted = accepted == true,
    })
    if SendRequest(Shared.EVENTS.RESPOND_FRIEND_REQUEST, payload) then
        if deps_.showToast then deps_.showToast(accepted == true and "正在同意好友申请..." or "正在拒绝好友申请...") end
        return true
    end
    FinishRequest(payload.requestId, "friendRespond")
    if deps_.showToast then deps_.showToast("网络异常，处理好友申请失败") end
    return false
end

function SocialGardenSystem.RemoveFriend(friendUserId)
    local targetUserId = tostring(friendUserId or "")
    if targetUserId == "" or targetUserId == "0" then
        if deps_.showToast then deps_.showToast("好友 ID 无效") end
        return false
    end
    local payload = BeginRequest("removeFriend", { friendUserId = targetUserId })
    if SendRequest(Shared.EVENTS.REMOVE_FRIEND, payload) then return true end
    FinishRequest(payload.requestId, "removeFriend")
    if deps_.showToast then deps_.showToast("网络异常，删除好友失败") end
    return false
end

function SocialGardenSystem.ClearSocialMessages()
    local payload = BeginRequest("clearMessages", {})
    if SendRequest(Shared.EVENTS.CLEAR_SOCIAL_MESSAGES, payload) then return true end
    FinishRequest(payload.requestId, "clearMessages")
    if deps_.showToast then deps_.showToast("网络异常，清除消息失败") end
    return false
end

function SocialGardenSystem.SendSeedGift(targetUserId, seedId)
    local normalizedTargetUserId = NormalizeUserId(targetUserId)
    seedId = tonumber(seedId or 1) or 1
    if normalizedTargetUserId == nil then
        if deps_.showToast then deps_.showToast("请输入好友玩家 ID") end
        return false
    end
    if SocialGardenSystem.HasGiftedToday(normalizedTargetUserId) then
        if deps_.showToast then deps_.showToast("今天已经给这位好友送过礼了") end
        return false
    end
    if (state_.daily.giftSentCount or 0) >= DAILY_GIFT_LIMIT then
        if deps_.showToast then deps_.showToast("今日赠送次数已用完") end
        return false
    end
    local payload = BeginRequest("gift", {
        targetUserId = normalizedTargetUserId,
        seedId = 0,
        count = 1,
        profile = {
            nickname = GetDisplayName(),
            avatar = GetAvatarProfile(),
        },
    })
    if SendRequest(Shared.EVENTS.SEND_SEED_GIFT, payload) then
        MarkGiftTarget(normalizedTargetUserId, true)
        ShowToastMessage("正在赠送种子...", true)
        EmitSocialChanged("updated")
        return true
    end
    FinishRequest(payload.requestId, "gift")
    if ALLOW_DEMO_SOCIAL ~= true then
        if deps_.showToast then deps_.showToast("网络异常，赠送失败") end
        return false
    end
    state_.daily.giftSentCount = (state_.daily.giftSentCount or 0) + 1
    MarkGiftTarget(normalizedTargetUserId, true)
    if deps_.showToast then deps_.showToast("已向好友发送种子礼物") end
    EmitSocialChanged("updated")
    return true
end

function SocialGardenSystem.RequestGifts()
    local payload = BeginRequest("gifts", {})
    if SendRequest(Shared.EVENTS.REQUEST_GIFTS, payload) then return true end
    FinishRequest(payload.requestId, "gifts")
    return false
end

function SocialGardenSystem.GetGifts()
    return state_.gifts
end

local function RemoveGiftById(giftId)
    if giftId == nil then return false, nil end
    state_.gifts = state_.gifts or {}
    local removed = false
    local removedGift = nil
    for i = #state_.gifts, 1, -1 do
        if tostring(state_.gifts[i].giftId or state_.gifts[i].listId) == tostring(giftId) then
            removedGift = removedGift or state_.gifts[i]
            table.remove(state_.gifts, i)
            removed = true
        end
    end
    return removed, removedGift
end

local function GetRewardDescription(reward)
    if type(reward) ~= "table" then return nil end
    if reward.description ~= nil and reward.description ~= "" then return tostring(reward.description) end
    local count = math.max(1, math.floor(tonumber(reward.count or 1) or 1))
    if reward.type == "seed" or reward.seedId ~= nil or reward.plantIndex ~= nil then
        local seedId = tonumber(reward.seedId or reward.plantIndex or 1) or 1
        local plants = deps_.getPlants and deps_.getPlants() or {}
        local plant = plants[seedId]
        local name = plant and plant.name or reward.name or "神秘"
        return tostring(name) .. "种子 x" .. tostring(count)
    end
    if reward.type == "seed_pack" or reward.packId ~= nil then
        return tostring(reward.name or "随机种子包") .. " x" .. tostring(count)
    end
    return tostring(reward.name or "礼物") .. " x" .. tostring(count)
end

function SocialGardenSystem.ClaimGift(gift)
    if gift == nil then return false end
    local payload = BeginRequest("claimGift", {
        giftId = tostring(gift.giftId or gift.listId or ""),
        listId = tostring(gift.listId or gift.giftId or ""),
        seedId = gift.seedId,
        count = gift.count,
    })
    if SendRequest(Shared.EVENTS.CLAIM_GIFT, payload) then
        return true
    end
    FinishRequest(payload.requestId, "claimGift")
    if ALLOW_DEMO_SOCIAL ~= true then
        if deps_.showToast then deps_.showToast("网络异常，领取失败") end
        return false
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
    if ALLOW_DEMO_SOCIAL ~= true then
        ShowStealResult("网络异常，偷菜失败")
        return false
    end
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
    if not HasStealAttemptsLeft() then
        ShowStealLimitInsufficient()
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
    EmitSocialChanged("updated")
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
    if garden.likedByMe == true then return true end
    return state_.likedGardens[tostring(garden.userId or "fallback")] == true
end

function SocialGardenSystem.ApplyLocalLike(garden)
    if ALLOW_DEMO_SOCIAL ~= true then
        if deps_.showToast then deps_.showToast("网络异常，点赞失败") end
        return false
    end
    if garden == nil then return false end
    local key = tostring(garden.userId or "fallback")
    state_.likedGardens[key] = true
    state_.likeDeltas[key] = (tonumber(state_.likeDeltas[key] or 0) or 0) + 1
    if garden.baseLikeCount == nil then
        garden.baseLikeCount = tonumber(garden.likeCount or 0) or 0
    end
    garden.likeCount = garden.baseLikeCount + (tonumber(state_.likeDeltas[key] or 0) or 0)
    if deps_.showToast then deps_.showToast("已点赞这个花园") end
    EmitSocialChanged("updated")
    if deps_.markDirty then deps_.markDirty() end
    return true
end

function SocialGardenSystem.LikeVisitGarden()
    local garden = state_.visitGarden
    if garden == nil then return false end
    local key = tostring(garden.userId or "fallback")
    if garden.isFallback ~= true then
        local payload = BeginRequest("like", { targetUserId = garden.userId })
        if SendRequest(Shared.EVENTS.LIKE_GARDEN, payload) then
            return true
        end
        FinishRequest(payload.requestId, "like")
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
            crop.stealPending = nil
            return true
        end
    end
    return false
end

function SocialGardenSystem.MarkVisitCropStealPending(cropId, cropIndex, pending)
    local crops = SocialGardenSystem.GetVisitCrops()
    for index, crop in ipairs(crops) do
        if (cropId ~= nil and crop.cropId == cropId) or (cropIndex ~= nil and index == cropIndex) then
            crop.stealPending = pending == true or nil
            return true
        end
    end
    return false
end

function SocialGardenSystem.GetDailyText()
    return string.format("偷菜 %d/%d · 赠送 %d/%d", state_.daily.stealCount or 0, DAILY_STEAL_LIMIT, state_.daily.giftSentCount or 0, DAILY_GIFT_LIMIT)
end

EmitSocialChanged = function(reason)
    EventBus.Emit(UIEvents.SOCIAL_CHANGED, { reason = reason })
end

function SocialGardenSystem.HandleSaveSnapshotResult(data)
    FinishRequest(data.requestId, "saveGarden")
    state_.lastSyncText = data.success and "已同步" or "同步失败"
    if deps_.showToast then deps_.showToast(data.message or state_.lastSyncText) end
end

function SocialGardenSystem.HandleGardenResponse(data)
    data = data or {}
    local pending = FinishRequestExact(data.requestId)
    if pending == nil or pending.type ~= "visit" then
        local visitPending = requests_:GetPending("visit")
        if visitPending ~= nil and data.success == true and type(data.garden) == "table" then
            local expectedTarget = UserId.Normalize(visitPending.payload and visitPending.payload.targetUserId)
            local responseTarget = UserId.Normalize(data.targetUserId) or UserId.Normalize(data.garden.userId)
            if expectedTarget ~= nil and UserId.Same(expectedTarget, responseTarget) then
                pending = requests_:Finish(visitPending.id)
                requests_:SyncLegacyPending(state_.pending)
                print("[社交花园] 拜访响应 requestId 未匹配，已按 targetUserId 关联 target=" .. tostring(expectedTarget))
            end
        end
    end
    if pending == nil or pending.type ~= "visit" then
        if data.success == true and type(data.garden) == "table" and state_.mode ~= MODE_VISIT then
            local responseTarget = UserId.Normalize(data.targetUserId) or UserId.Normalize(data.garden.userId)
            local expectedTarget = UserId.Normalize(state_.pending.visitUserId)
            if responseTarget ~= nil and expectedTarget ~= nil and UserId.Same(responseTarget, expectedTarget) then
                print("[社交花园] 拜访响应迟到到达，仍按目标关联 target=" .. tostring(expectedTarget))
                pending = { type = "visit", payload = { targetUserId = expectedTarget } }
            end
        end
        if pending == nil or pending.type ~= "visit" then
            print("[社交花园] 忽略无效或过期的拜访响应 requestId=" .. tostring(data.requestId))
            return
        end
    end
    local targetUserId = UserId.Normalize(data.targetUserId)
        or UserId.Normalize(pending.payload and pending.payload.targetUserId)
    state_.pending.visitUserId = nil
    if data.success ~= true then
        if deps_.showToast then deps_.showToast(data.message or "花园读取失败") end
        return
    end
    local garden = data.garden
    if type(garden) ~= "table" then
        if targetUserId ~= nil and EnterFallbackGarden(targetUserId) then return end
        if deps_.showToast then deps_.showToast("花园数据无效") end
        return
    end
    if targetUserId ~= nil then
        garden.userId = UserId.Normalize(garden.userId) or targetUserId
        if not UserId.Same(garden.userId, targetUserId) then
            print(string.format(
                "[社交花园] 拜访响应 UID 不匹配 target=%s garden=%s",
                tostring(targetUserId),
                tostring(garden.userId)
            ))
            if EnterFallbackGarden(targetUserId) then return end
            if deps_.showToast then deps_.showToast("花园数据异常，暂时无法拜访") end
            return
        end
    end
    EnterVisitMode(garden)
    if garden.likedByMe == true then
        state_.likedGardens[tostring(garden.userId or "fallback")] = true
    end
    if deps_.showToast then deps_.showToast("正在拜访 " .. (garden.nickname or "好友") .. " 的花园") end
end

function SocialGardenSystem.HandleRankResponse(data)
    FinishRequest(data.requestId, "rank")
    if data.success and type(data.list) == "table" then
        state_.leaderboard = MergeLeaderboardWithFallback(data.list)
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        deps_.showToast(data.message or "排行榜读取失败")
    end
end

function SocialGardenSystem.HandleStealResponse(data)
    local pending = FinishRequest(data.requestId, "steal")
    if data.success then
        SocialGardenSystem.MarkVisitCropStolen(data.cropId, data.cropIndex)
        if data.state ~= nil and deps_.applyEconomyState ~= nil then
            deps_.applyEconomyState(data.state)
        elseif data.reward ~= nil then
            ApplyStealReward(data.reward)
        end
        if data.daily ~= nil then
            if data.daily.stealCount ~= nil then
                state_.daily.stealCount = data.daily.stealCount
            elseif data.daily.stealCountDelta ~= nil then
                state_.daily.stealCount = (state_.daily.stealCount or 0) + data.daily.stealCountDelta
            end
            if data.daily.limit ~= nil then
                state_.daily.stealLimit = data.daily.limit
            end
        end
        ScheduleSocialStateRefresh("steal_success")
        local message = data.message or "偷菜成功"
        local floatingMessage = BuildStealFloatingMessage(data)
        if deps_.showToast then deps_.showToast(message) end
        if deps_.showFloatingToast then deps_.showFloatingToast(floatingMessage) end
        if deps_.markDirty then deps_.markDirty() end
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        SocialGardenSystem.MarkVisitCropStealPending(data.cropId or (pending and pending.payload and pending.payload.cropId), data.cropIndex or (pending and pending.payload and pending.payload.cropIndex), false)
        if IsCloudRateLimitError(data) then
            state_.stealBackoffUntil = GetNow() + STEAL_RATE_LIMIT_BACKOFF
            ScheduleSocialStateRefresh("steal_rate_limited")
        end
        if IsStealLimitError(data) then
            if data.daily ~= nil then
                if data.daily.stealCount ~= nil then
                    state_.daily.stealCount = data.daily.stealCount
                end
                if data.daily.limit ~= nil then
                    state_.daily.stealLimit = data.daily.limit
                end
            end
            ShowStealLimitInsufficient()
        else
            deps_.showToast(data.message or "偷菜失败")
        end
    end
end

function SocialGardenSystem.ApplyAdRewardDaily(daily)
    if type(daily) ~= "table" then return false end
    if daily.stealAdCount ~= nil then state_.daily.stealAdCount = daily.stealAdCount end
    if daily.stealAdLimit ~= nil then state_.daily.stealAdLimit = daily.stealAdLimit end
    if daily.limit ~= nil then state_.daily.stealLimit = daily.limit end
    if daily.seedPackAdCount ~= nil then state_.daily.seedPackAdCount = daily.seedPackAdCount end
    if daily.seedPackAdLimit ~= nil then state_.daily.seedPackAdLimit = daily.seedPackAdLimit end
    if daily.matureAdCount ~= nil then state_.daily.matureAdCount = daily.matureAdCount end
    if daily.matureAdLimit ~= nil then state_.daily.matureAdLimit = daily.matureAdLimit end
    EmitSocialChanged("updated")
    return true
end

function SocialGardenSystem.HandleSocialStateResponse(data)
    FinishRequest(data.requestId, "socialState")
    if data.success then
        local phase = data.phase or "full"
        SocialGardenSystem.LoadSaveData(type(data.socialSave) == "table" and data.socialSave or {})
        if phase == "save" then
            print("[社交花园] 社交档核心数据已恢复")
            if deps_.onSocialSaveSynced ~= nil then deps_.onSocialSaveSynced() end
            return
        end
        state_.socialStateSynced = true
        if type(data.friends) == "table" then
            if #data.friends > 0 or #(state_.friends or {}) == 0 then
                state_.friends = data.friends
            else
                print(string.format("[社交健康] 忽略空好友列表覆盖，保留本地 count=%d reason=%s", #(state_.friends or {}), tostring(data.reason or "social_state")))
            end
        end
        if type(data.friendRequests) == "table" then state_.friendRequests = FilterFriendRequests(data.friendRequests) end
        if type(data.socialNotices) == "table" then state_.socialNotices = data.socialNotices end
        if type(data.giftedTargets) == "table" then state_.giftedTargets = data.giftedTargets end
        if type(data.recommendedPlayers) == "table" then state_.recommendedPlayers = data.recommendedPlayers end
        if type(data.recentVisitors) == "table" then state_.recentVisitors = data.recentVisitors end
        if type(data.stealLogs) == "table" then state_.stealLogs = data.stealLogs end
        if type(data.daily) == "table" then
            local nextStealCount = tonumber(data.daily.stealCount or 0) or 0
            local nextGiftSentCount = tonumber(data.daily.giftSentCount or 0) or 0
            state_.daily.stealCount = math.max(tonumber(state_.daily.stealCount or 0) or 0, nextStealCount)
            state_.daily.giftSentCount = math.max(tonumber(state_.daily.giftSentCount or 0) or 0, nextGiftSentCount)
            if data.daily.stealLimit ~= nil then state_.daily.stealLimit = data.daily.stealLimit end
            if data.daily.stealAdCount ~= nil then state_.daily.stealAdCount = data.daily.stealAdCount end
            if data.daily.stealAdLimit ~= nil then state_.daily.stealAdLimit = data.daily.stealAdLimit end
            if data.daily.seedPackAdCount ~= nil then state_.daily.seedPackAdCount = data.daily.seedPackAdCount end
            if data.daily.seedPackAdLimit ~= nil then state_.daily.seedPackAdLimit = data.daily.seedPackAdLimit end
            if data.daily.matureAdCount ~= nil then state_.daily.matureAdCount = data.daily.matureAdCount end
            if data.daily.matureAdLimit ~= nil then state_.daily.matureAdLimit = data.daily.matureAdLimit end
        end
        EmitSocialChanged("updated")
        if deps_.onSocialStateSynced ~= nil then deps_.onSocialStateSynced() end
    elseif deps_.showToast then
        deps_.showToast(data.message or "社交数据读取失败")
    end
end

function SocialGardenSystem.HandleSendSeedGiftResponse(data)
    FinishRequest(data.requestId, "gift")
    if data.success then
        if data.state ~= nil and deps_.applyEconomyState ~= nil then
            deps_.applyEconomyState(data.state)
        end
        if data.daily ~= nil then
            if data.daily.giftSentCount ~= nil then
                state_.daily.giftSentCount = data.daily.giftSentCount
            elseif data.daily.giftSentDelta ~= nil then
                state_.daily.giftSentCount = (state_.daily.giftSentCount or 0) + data.daily.giftSentDelta
            end
        end
        if data.targetUserId ~= nil then MarkGiftTarget(data.targetUserId, true) end
        local message = data.message or "种子已送出"
        ShowToastMessage(message, true)
        SocialGardenSystem.RequestSocialState()
        if deps_.markDirty then deps_.markDirty() end
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        if data.state ~= nil and deps_.applyEconomyState ~= nil then
            deps_.applyEconomyState(data.state)
        end
        if data.targetUserId ~= nil and ShouldRollbackGiftTarget(data.targetUserId) then
            MarkGiftTarget(data.targetUserId, false)
            EmitSocialChanged("updated")
        end
        local message = data.message or "赠送失败"
        ShowToastMessage(message, true)
    end
end

function SocialGardenSystem.HandleLikeGardenResponse(data)
    FinishRequest(data.requestId, "like")
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
        EmitSocialChanged("updated")
        if deps_.markDirty then deps_.markDirty() end
    else
        if data.alreadyLiked == true and garden ~= nil then
            local key = tostring(garden.userId or "fallback")
            state_.likedGardens[key] = true
            if data.likeCount ~= nil then
                garden.baseLikeCount = tonumber(data.likeCount) or tonumber(garden.likeCount or 0) or 0
                garden.likeCount = garden.baseLikeCount
            end
            EmitSocialChanged("updated")
            if deps_.markDirty then deps_.markDirty() end
        end
        if deps_.showToast then deps_.showToast(data.message or "点赞失败") end
    end
end

function SocialGardenSystem.HandleSendFriendRequestResponse(data)
    FinishRequest(data.requestId, "friendRequest")
    if data.success then
        ShowToastMessage("已发送好友申请", true)
        SocialGardenSystem.RequestSocialState()
    elseif deps_.showToast then
        deps_.showToast(data.message or "好友申请发送失败")
    end
end

function SocialGardenSystem.HandleRespondFriendRequestResponse(data)
    FinishRequest(data.requestId, "friendRespond")
    if data.success then
        if data.fromUserId ~= nil then
            RemoveFriendRequestLocally({ fromUserId = data.fromUserId, requestId = data.requestIdValue })
        end
        if deps_.showToast then deps_.showToast(data.message or "好友申请已处理") end
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        deps_.showToast(data.message or "好友申请处理失败")
    end
    SocialGardenSystem.RequestSocialState({ force = true, reason = data.success and "friend_respond" or "friend_respond_failed" })
end

function SocialGardenSystem.HandleRemoveFriendResponse(data)
    FinishRequest(data.requestId, "removeFriend")
    if data.success then
        local friendUserId = data.friendUserId
        if friendUserId ~= nil then
            for i = #state_.friends, 1, -1 do
                if tostring(state_.friends[i].userId) == tostring(friendUserId) then
                    table.remove(state_.friends, i)
                end
            end
        end
        if deps_.showToast then deps_.showToast(data.message or "已删除好友") end
        EmitSocialChanged("updated")
        SocialGardenSystem.RequestSocialState()
    elseif deps_.showToast then
        deps_.showToast(data.message or "删除好友失败")
    end
end

function SocialGardenSystem.HandleClearSocialMessagesResponse(data)
    FinishRequest(data.requestId, "clearMessages")
    if data.success then
        state_.recentVisitors = {}
        state_.stealLogs = {}
        state_.socialNotices = {}
        if type(data.gifts) == "table" then state_.gifts = data.gifts end
        if type(data.friendRequests) == "table" then state_.friendRequests = FilterFriendRequests(data.friendRequests) end
        SocialGardenSystem.RequestGifts()
        if deps_.showToast then deps_.showToast(data.message or "消息已清除") end
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        deps_.showToast(data.message or "消息清除失败")
    end
end

function SocialGardenSystem.HandleGiftsResponse(data)
    FinishRequest(data.requestId, "gifts")
    if data.success and type(data.gifts) == "table" then
        state_.gifts = data.gifts
        EmitSocialChanged("updated")
    elseif deps_.showToast then
        deps_.showToast(data.message or "礼物读取失败")
    end
end

function SocialGardenSystem.HandleClaimGiftResponse(data)
    FinishRequest(data.requestId, "claimGift")
    if data.success then
        local removed, removedGift = RemoveGiftById(data.giftId)
        local reward = data.gift or data.reward or (removedGift and (removedGift.reward or removedGift)) or nil
        local rewardText = GetRewardDescription(reward)
        if data.state ~= nil and deps_.applyEconomyState ~= nil then
            deps_.applyEconomyState(data.state)
        elseif data.alreadyClaimed ~= true then
            ApplyGiftReward(reward)
        end
        local message = data.message or "礼物已领取"
        if rewardText ~= nil and string.find(message, rewardText, 1, true) == nil then
            if data.alreadyClaimed == true then
                message = "礼物已处理：" .. rewardText
            else
                message = "已领取" .. rewardText
            end
        end
        if deps_.showToast then deps_.showToast(message) end
        if deps_.showFloatingToast then deps_.showFloatingToast(message) end
        if removed then EmitSocialChanged("updated") end
        SocialGardenSystem.RequestGifts()
        if deps_.markDirty then deps_.markDirty() end
    else
        local message = data.message or "领取失败"
        if deps_.showToast then deps_.showToast(message) end
        if deps_.showFloatingToast then deps_.showFloatingToast(message) end
        if data.code == "GIFT_ALREADY_CLAIMED" or data.code == "GIFT_NOT_FOUND" or data.code == "INVALID_GIFT_CONTENT" then
            RemoveGiftById(data.giftId)
            SocialGardenSystem.RequestGifts()
            EmitSocialChanged("updated")
        end
    end
end

require("systems.social.social_client_events")

return SocialGardenSystem
