-- ============================================================================
-- 排行榜客户端系统
-- ============================================================================
-- 通过权威服务器读取收入榜、观光榜与当前活动榜，并处理活动榜头像奖励领取。
-- ============================================================================

local Shared = require("network.shared")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local RequestStateMachine = require("client.request_state_machine")
local NetworkClient = require("client.network_client")

local LeaderboardSystem = {}

local REQUEST_COOLDOWN = 8
local RATE_LIMIT_BACKOFF = 12
local CROSS_RANK_COOLDOWN = 12

local deps_ = {}
local requests_ = RequestStateMachine.Create("leaderboard", { timeout = 14.0 })
local state_ = {
    activeKind = "income",
    activeActivityId = nil,
    lists = {},
    loading = {},
    requestStartedAt = {},
    rateLimitUntil = 0,
    rewards = {},
    errors = {},
    lastError = nil,
}

local function IsClientNetworkAvailable()
    return NetworkClient.IsRawConnected()
end

local function Now()
    return os and os.time and os.time() or 0
end

local function IsRateLimitMessage(message)
    message = tostring(message or "")
    return string.find(message, "read rate limit exceeded", 1, true) ~= nil
        or string.find(message, "榜单繁忙", 1, true) ~= nil
end

local function BeginRequest(requestType, payload, options)
    local nextPayload = payload or {}
    nextPayload = requests_:Begin(requestType, nextPayload, options or { suppressNetworkFailure = true })
    return nextPayload
end

local function FinishRequest(requestId, requestType)
    return requests_:Finish(requestId, requestType)
end

local function EmitChanged(reason)
    EventBus.Emit(UIEvents.LEADERBOARD_CHANGED, { reason = reason })
end

local function SendRequest(eventName, payload)
    return NetworkClient.SendRequest(eventName, payload)
end

local function BuildListKey(kind, activityId)
    if kind == "activity" then
        return "activity:" .. tostring(activityId or "current")
    end
    return tostring(kind or "income")
end

local function SetListError(key, message)
    message = message or "排行榜读取失败"
    state_.errors[key] = message
    state_.lastError = message
end

local function ClearListError(key)
    state_.errors[key] = nil
    state_.lastError = nil
end

local function IsSocialRankCoolingDown(now)
    local social = deps_.SocialGardenSystem
    if social == nil or social.GetLastRankRequestAt == nil then return false end
    local lastSocialRankAt = tonumber(social.GetLastRankRequestAt() or 0) or 0
    return lastSocialRankAt > 0 and now - lastSocialRankAt < CROSS_RANK_COOLDOWN
end

function LeaderboardSystem.Init(deps)
    deps_ = deps or {}
    Shared.RegisterClientEvents()
    if NetworkClient.IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.LEADERBOARD_RESPONSE, "HandleGardenLeaderboardResponse")
        SubscribeToEvent(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, "HandleGardenClaimActivityRankRewardResponse")
    end
end

function LeaderboardSystem.Update(dt)
    requests_:Update(function(record)
        local payload = record.payload or {}
        local key = BuildListKey(payload.kind, payload.activityId)
        state_.loading[key] = false
        SetListError(key, "网络连接失败，排行榜请求超时，请重试")
        if deps_.showToast then deps_.showToast(state_.lastError) end
        EmitChanged("timeout")
    end)
end

function LeaderboardSystem.GetState()
    return state_
end

function LeaderboardSystem.GetList(kind, activityId)
    return state_.lists[BuildListKey(kind, activityId)] or {}
end

function LeaderboardSystem.IsLoading(kind, activityId)
    return state_.loading[BuildListKey(kind, activityId)] == true
end

function LeaderboardSystem.GetError(kind, activityId)
    return state_.errors[BuildListKey(kind, activityId)]
end

function LeaderboardSystem.ClearPendingRequests(reason)
    requests_:Clear()
    for key in pairs(state_.loading) do
        state_.loading[key] = false
        state_.errors[key] = "网络连接已重置，请重试"
    end
    state_.lastError = "网络连接已重置，请重试"
    EmitChanged(reason or "network_reset")
end

function LeaderboardSystem.Request(kind, activityId, forceRefresh)
    kind = kind or "income"
    state_.activeKind = kind
    state_.activeActivityId = activityId
    local key = BuildListKey(kind, activityId)
    local now = Now()
    if now < (state_.rateLimitUntil or 0) then
        SetListError(key, "榜单繁忙，请稍后再试")
        if deps_.showToast then deps_.showToast(state_.lastError) end
        EmitChanged("rate_limited")
        return false
    end
    if state_.loading[key] == true then
        return true
    end
    local hasCache = state_.lists[key] ~= nil
    local lastStarted = tonumber(state_.requestStartedAt[key] or 0) or 0
    if hasCache and now - lastStarted < REQUEST_COOLDOWN then
        ClearListError(key)
        EmitChanged("cached")
        return true
    end
    if IsSocialRankCoolingDown(now) then
        if hasCache then
            ClearListError(key)
            print("[排行榜] 社交观光榜刚刷新，主排行榜暂用缓存避免云榜限流 kind=" .. tostring(kind))
            EmitChanged("cross_rank_cached")
        else
            SetListError(key, "榜单正在同步，请稍后点击刷新")
            print("[排行榜] 社交观光榜刚刷新，延后主排行榜请求避免云榜限流 kind=" .. tostring(kind))
            EmitChanged("cross_rank_delayed")
        end
        return hasCache
    end
    if forceRefresh ~= true and hasCache then
        ClearListError(key)
        EmitChanged("cached")
        return true
    end
    local payload = BeginRequest("rank", { kind = kind, activityId = activityId, count = 20 })
    state_.loading[key] = true
    state_.requestStartedAt[key] = now
    ClearListError(key)
    EmitChanged("request")
    if SendRequest(Shared.EVENTS.REQUEST_LEADERBOARD, payload) then return true end
    FinishRequest(payload.requestId, "rank")
    state_.loading[key] = false
    SetListError(key, "网络连接失败，无法拉取排行榜数据，请检查网络后重试")
    if deps_.showToast then deps_.showToast(state_.lastError) end
    EmitChanged("request_failed")
    return false
end

function LeaderboardSystem.ClaimPreviousActivityRankReward()
    local unlocked = deps_.getUnlockedAvatarMap and deps_.getUnlockedAvatarMap() or {}
    local payload = BeginRequest("claimActivityRankReward", { unlockedAvatars = unlocked })
    if SendRequest(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD, payload) then return true end
    FinishRequest(payload.requestId, "claimActivityRankReward")
    if deps_.showToast then deps_.showToast("服务器尚未就绪，无法领取奖励") end
    return false
end

function LeaderboardSystem.ClaimActivityRankReward()
    return LeaderboardSystem.ClaimPreviousActivityRankReward()
end

function LeaderboardSystem.HandleLeaderboardResponse(data)
    local record = FinishRequest(data.requestId, "rank")
    local kind = data.kind or (record and record.payload and record.payload.kind) or state_.activeKind
    local activityId = data.activityId or (record and record.payload and record.payload.activityId) or state_.activeActivityId
    local key = BuildListKey(kind, activityId)
    state_.loading[key] = false
    if data.success then
        state_.lists[key] = data
        ClearListError(key)
    else
        SetListError(key, data.message or "排行榜读取失败")
        if NetworkClient.ReportServerResponseFailure ~= nil then
            NetworkClient.ReportServerResponseFailure(data, "leaderboard")
        end
        if IsRateLimitMessage(state_.lastError) then
            state_.rateLimitUntil = Now() + RATE_LIMIT_BACKOFF
        end
        if deps_.showToast then deps_.showToast(state_.lastError) end
    end
    EmitChanged("response")
end

local function ShowRewardToast(message)
    message = message or "活动排行奖励领取失败"
    if deps_.showToast then deps_.showToast(message) end
    if deps_.showFloatingToast then deps_.showFloatingToast(message) end
end

function LeaderboardSystem.HandleClaimActivityRankRewardResponse(data)
    FinishRequest(data.requestId, "claimActivityRankReward")
    if data.success then
        if data.state ~= nil and deps_.applyEconomyState ~= nil then
            deps_.applyEconomyState(data.state)
        end
        if data.reward ~= nil and data.reward.type == "avatar" and deps_.unlockAvatarReward ~= nil then
            deps_.unlockAvatarReward(data.reward.avatarId or data.reward.avatarIndex)
        end
        state_.rewards[tostring(data.cycleId or data.activityId or "current")] = data.reward or { type = "none" }
        local message = data.message or "活动排行奖励已领取"
        ShowRewardToast(message)
        LeaderboardSystem.Request("activity", state_.activeActivityId)
    else
        if NetworkClient.ReportServerResponseFailure ~= nil then
            NetworkClient.ReportServerResponseFailure(data, "claimActivityRankReward")
        end
        ShowRewardToast(data.message or "活动排行奖励领取失败")
    end
    EmitChanged("reward")
end

function HandleGardenLeaderboardResponse(eventType, eventData)
    LeaderboardSystem.HandleLeaderboardResponse(Shared.ReadEventData(eventData))
end

function HandleGardenClaimActivityRankRewardResponse(eventType, eventData)
    LeaderboardSystem.HandleClaimActivityRankRewardResponse(Shared.ReadEventData(eventData))
end

return LeaderboardSystem
