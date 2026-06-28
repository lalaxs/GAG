-- ============================================================================
-- 排行榜客户端系统
-- ============================================================================
-- 通过权威服务器读取收入榜、观光榜与当前活动榜，并处理活动榜头像奖励领取。
-- ============================================================================

local Shared = require("network.shared")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local RequestStateMachine = require("client.request_state_machine")

local LeaderboardSystem = {}

local deps_ = {}
local requests_ = RequestStateMachine.Create("leaderboard", { timeout = 14.0 })
local state_ = {
    activeKind = "income",
    activeActivityId = nil,
    lists = {},
    loading = {},
    rewards = {},
    lastError = nil,
}

local function IsClientNetworkAvailable()
    return network ~= nil and IsClientMode ~= nil and IsClientMode() and network:GetServerConnection() ~= nil
end

local function BeginRequest(requestType, payload)
    local nextPayload = payload or {}
    nextPayload = requests_:Begin(requestType, nextPayload)
    return nextPayload
end

local function FinishRequest(requestId, requestType)
    return requests_:Finish(requestId, requestType)
end

local function EmitChanged(reason)
    EventBus.Emit(UIEvents.LEADERBOARD_CHANGED, { reason = reason })
end

local function SendRequest(eventName, payload)
    if IsClientNetworkAvailable() then
        return Shared.SendToServer(eventName, payload)
    end
    return false
end

local function BuildListKey(kind, activityId)
    if kind == "activity" then
        return "activity:" .. tostring(activityId or "current")
    end
    return tostring(kind or "income")
end

function LeaderboardSystem.Init(deps)
    deps_ = deps or {}
    Shared.RegisterClientEvents()
    if network ~= nil and IsClientMode ~= nil and IsClientMode() then
        SubscribeToEvent(Shared.EVENTS.LEADERBOARD_RESPONSE, "HandleGardenLeaderboardResponse")
        SubscribeToEvent(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, "HandleGardenClaimActivityRankRewardResponse")
    end
end

function LeaderboardSystem.Update(dt)
    requests_:Update(function(record)
        state_.lastError = "排行榜请求超时"
        local payload = record.payload or {}
        state_.loading[BuildListKey(payload.kind, payload.activityId)] = false
        if deps_.showToast then deps_.showToast("排行榜请求超时") end
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

function LeaderboardSystem.Request(kind, activityId)
    kind = kind or "income"
    state_.activeKind = kind
    state_.activeActivityId = activityId
    local payload = BeginRequest("rank", { kind = kind, activityId = activityId, count = 20 })
    state_.loading[BuildListKey(kind, activityId)] = true
    state_.lastError = nil
    EmitChanged("request")
    if SendRequest(Shared.EVENTS.REQUEST_LEADERBOARD, payload) then return true end
    FinishRequest(payload.requestId, "rank")
    state_.loading[BuildListKey(kind, activityId)] = false
    state_.lastError = "服务器尚未就绪，无法读取排行榜"
    if deps_.showToast then deps_.showToast(state_.lastError) end
    EmitChanged("request_failed")
    return false
end

function LeaderboardSystem.ClaimActivityRankReward(activityId)
    local unlocked = deps_.getUnlockedAvatarMap and deps_.getUnlockedAvatarMap() or {}
    local payload = BeginRequest("claimActivityRankReward", { activityId = activityId, unlockedAvatars = unlocked })
    if SendRequest(Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD, payload) then return true end
    FinishRequest(payload.requestId, "claimActivityRankReward")
    if deps_.showToast then deps_.showToast("服务器尚未就绪，无法领取奖励") end
    return false
end

function LeaderboardSystem.HandleLeaderboardResponse(data)
    local record = FinishRequest(data.requestId, "rank")
    local kind = data.kind or (record and record.payload and record.payload.kind) or state_.activeKind
    local activityId = data.activityId or (record and record.payload and record.payload.activityId) or state_.activeActivityId
    local key = BuildListKey(kind, activityId)
    state_.loading[key] = false
    if data.success then
        state_.lists[key] = data
        state_.lastError = nil
    else
        state_.lastError = data.message or "排行榜读取失败"
        if deps_.showToast then deps_.showToast(state_.lastError) end
    end
    EmitChanged("response")
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
        if deps_.showFloatingToast then deps_.showFloatingToast(message) elseif deps_.showToast then deps_.showToast(message) end
        LeaderboardSystem.Request("activity", data.activityId)
    else
        if deps_.showToast then deps_.showToast(data.message or "活动排行奖励领取失败") end
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
