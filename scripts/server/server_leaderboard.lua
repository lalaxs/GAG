-- ============================================================================
-- 服务端排行榜系统
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的排行榜信息、榜单查询和活动榜奖励领取逻辑。
-- ============================================================================

local ServerLeaderboard = {}

local deps_ = {}
local ServerCloudStore = require("server.server_cloud_store")
local LeaderboardSanitize = require("server.leaderboard_sanitize")
local UserId = require("utils.user_id")

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

local function RankUid(uid)
    return UserId.ForRankCloud(uid) or CloudUid(uid)
end

function ServerLeaderboard.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

function ServerLeaderboard.GetIncomeRankInfo(now)
    now = math.max(0, math.floor(tonumber(now or Now()) or 0))
    local cycleIndex = math.floor(now / deps_.incomeRankRefreshInterval)
    local cycleStart = cycleIndex * deps_.incomeRankRefreshInterval
    local cycleEnd = cycleStart + deps_.incomeRankRefreshInterval
    return {
        key = deps_.Shared.KEYS.INCOME_RANK_PREFIX .. tostring(cycleIndex),
        cycleId = "income_" .. tostring(cycleIndex),
        cycleStart = cycleStart,
        cycleEnd = cycleEnd,
        timeLeft = math.max(0, cycleEnd - now),
    }
end

function ServerLeaderboard.GetActivityRankInfo(activityId, cycleInfo)
    cycleInfo = cycleInfo or (deps_.GameConfig.GetActivityCycleInfo and deps_.GameConfig.GetActivityCycleInfo(Now())) or { activityId = "sweet", cycleId = "sweet_0", timeLeft = 0 }
    activityId = activityId or cycleInfo.activityId or "sweet"
    return {
        key = deps_.Shared.KEYS.ACTIVITY_RANK_PREFIX .. tostring(activityId) .. "_" .. tostring(cycleInfo.cycleId or "0"),
        rewardKey = deps_.Shared.KEYS.ACTIVITY_RANK_REWARD_PREFIX .. tostring(activityId) .. "_" .. tostring(cycleInfo.cycleId or "0"),
        cycleId = cycleInfo.cycleId or tostring(activityId) .. "_0",
        activityId = activityId,
        cycleStart = cycleInfo.cycleStart,
        cycleEnd = cycleInfo.cycleEnd,
        timeLeft = cycleInfo.timeLeft or 0,
    }
end

function ServerLeaderboard.ResolveLeaderboardInfo(kind, activityId)
    kind = tostring(kind or "income")
    if kind == "tour" then
        return { kind = "tour", key = deps_.Shared.KEYS.TOUR_RANK, title = "观光排行榜", resetMode = "never" }
    elseif kind == "like" then
        return { kind = "like", key = deps_.Shared.KEYS.LIKE_COUNT, title = "点赞排行榜", resetMode = "never" }
    elseif kind == "activity" then
        local cycleInfo = deps_.GetCurrentActivityCycleInfo()
        local info = ServerLeaderboard.GetActivityRankInfo(activityId or cycleInfo.activityId, cycleInfo)
        info.kind = "activity"
        info.title = ((deps_.GetActivityConfig(info.activityId) or {}).name or "活动") .. "排行榜"
        info.resetMode = "activity_cycle"
        return info
    end
    local info = ServerLeaderboard.GetIncomeRankInfo()
    info.kind = "income"
    info.title = "收入排行榜"
    info.resetMode = "7d"
    return info
end

function ServerLeaderboard.GetRankItemScore(item, key)
    if item == nil then return 0 end
    if type(item.iscore) == "table" then
        return math.max(0, math.floor(tonumber(item.iscore[key] or 0) or 0))
    end
    return math.max(0, math.floor(tonumber(item.score or item.value or 0) or 0))
end

function ServerLeaderboard.AddPreviousActivityRewardStatus(uid, data, done)
    uid = CloudUid(uid)
    if data.kind ~= "activity" then
        done(data)
        return
    end
    local previousCycleInfo = deps_.GetPreviousActivityCycleInfo()
    if previousCycleInfo == nil then
        data.previousRewardEligible = false
        data.previousRewardClaimed = false
        done(data)
        return
    end
    local previousInfo = ServerLeaderboard.GetActivityRankInfo(previousCycleInfo.activityId, previousCycleInfo)
    data.previousActivityId = previousInfo.activityId
    data.previousCycleId = previousInfo.cycleId
    data.previousCycleStart = previousInfo.cycleStart
    data.previousCycleEnd = previousInfo.cycleEnd
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:GetUserRank(RankUid(uid), previousInfo.key, {
        ok = function(previousRank, previousScore)
            previousScore = math.max(0, math.floor(tonumber(previousScore or 0) or 0))
            data.previousRank = previousRank
            data.previousScore = previousScore
            data.previousRewardEligible = previousRank ~= nil and previousRank <= deps_.activityRankRewardTop and previousScore > 0
            ServerCloudStore.Get(uid, previousInfo.rewardKey, {
                ok = function(scores)
                    data.previousRewardClaimed = type(scores[previousInfo.rewardKey]) == "table"
                    done(data)
                end,
                error = function()
                    data.previousRewardClaimed = false
                    done(data)
                end,
            })
        end,
        error = function()
            data.previousRank = nil
            data.previousScore = 0
            data.previousRewardEligible = false
            data.previousRewardClaimed = false
            done(data)
        end,
    })
end

function ServerLeaderboard.SendLeaderboardWithMyRank(uid, connection, requestId, info, list)
    uid = CloudUid(uid)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:GetUserRank(RankUid(uid), info.key, {
        ok = function(myRank, myScore)
            local myScoreValue = math.max(0, math.floor(tonumber(myScore or 0) or 0))
            for _, entry in ipairs(list or {}) do
                if UserId.Same(entry.userId, uid) then
                    entry.score = myScoreValue
                    entry.isMe = true
                end
            end

            local function SendWithRewardStatus(rewardClaimed)
                local data = {
                    success = true,
                    requestId = requestId,
                    kind = info.kind,
                    activityId = info.activityId,
                    cycleId = info.cycleId,
                    cycleStart = info.cycleStart,
                    cycleEnd = info.cycleEnd,
                    timeLeft = info.timeLeft,
                    resetMode = info.resetMode,
                    title = info.title,
                    list = list,
                    myRank = myRank,
                    myScore = myScoreValue,
                    rewardEligible = info.kind == "activity" and myRank ~= nil and myRank <= deps_.activityRankRewardTop,
                    rewardClaimed = rewardClaimed == true,
                }
                ServerLeaderboard.AddPreviousActivityRewardStatus(uid, data, function(response)
                    Send(connection, deps_.Shared.EVENTS.LEADERBOARD_RESPONSE, response)
                end)
            end
            if info.kind ~= "activity" then
                SendWithRewardStatus(false)
                return
            end
            ServerCloudStore.Get(uid, info.rewardKey, {
                ok = function(scores)
                    SendWithRewardStatus(type(scores[info.rewardKey]) == "table")
                end,
                error = function()
                    SendWithRewardStatus(false)
                end,
            })
        end,
        error = function()
            local data = { success = true, requestId = requestId, kind = info.kind, activityId = info.activityId, cycleId = info.cycleId, resetMode = info.resetMode, title = info.title, list = list, myRank = nil, myScore = 0 }
            ServerLeaderboard.AddPreviousActivityRewardStatus(uid, data, function(response)
                Send(connection, deps_.Shared.EVENTS.LEADERBOARD_RESPONSE, response)
            end)
        end,
    })
end

function ServerLeaderboard.RequestLeaderboardAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local info = ServerLeaderboard.ResolveLeaderboardInfo(payload.kind, payload.activityId)
    local count = deps_.NormalizePositiveCount(payload.count or 20, 50)
    serverCloud:GetRankList(info.key, 1, count, {
        ok = function(rankList)
            local userIds = {}
            local result = {}
            for i, item in ipairs(rankList or {}) do
                local userId = LeaderboardSanitize.ResolveRankUserId(item)
                if userId ~= nil then
                    userIds[#userIds + 1] = userId
                    result[#result + 1] = {
                        rank = i,
                        userId = userId,
                        nickname = "Tap玩家",
                        score = ServerLeaderboard.GetRankItemScore(item, info.key),
                    }
                end
            end
            deps_.GetNicknameMap(userIds, function(nickMap)
                deps_.SocialServer.FetchGardenProfiles(userIds, function(profileMap)
                    local filtered = LeaderboardSanitize.FilterForDisplay(uid, result, profileMap, nickMap, info.kind)
                    ServerLeaderboard.SendLeaderboardWithMyRank(uid, connection, payload.requestId, info, filtered)
                end)
            end)
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.LEADERBOARD_RESPONSE, { success = false, requestId = payload.requestId, kind = payload.kind, activityId = payload.activityId, message = "排行榜读取失败: " .. tostring(reason) })
        end,
    })
end

function ServerLeaderboard.PickLockedAvatar(unlocked)
    unlocked = type(unlocked) == "table" and unlocked or {}
    local locked = {}
    for index, _ in ipairs(deps_.GameConfig.PLANTS or {}) do
        local avatarId = "plant_" .. tostring(index)
        if unlocked[avatarId] ~= true and unlocked[tostring(index)] ~= true and unlocked[index] ~= true then
            locked[#locked + 1] = index
        end
    end
    if #locked <= 0 then return nil end
    return locked[math.random(1, #locked)]
end

function ServerLeaderboard.ClaimActivityRankRewardAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local cycleInfo = deps_.GetPreviousActivityCycleInfo()
    if cycleInfo == nil then
        Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, message = "没有上期活动奖励可领" })
        return
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    local info = ServerLeaderboard.GetActivityRankInfo(cycleInfo.activityId, cycleInfo)
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:GetUserRank(RankUid(uid), info.key, {
        ok = function(rank, score)
            score = math.max(0, math.floor(tonumber(score or 0) or 0))
            if rank == nil or rank > deps_.activityRankRewardTop or score <= 0 then
                Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期没有进入活动榜前20，没有奖励可领" })
                return
            end
            ServerCloudStore.Get(uid, info.rewardKey, {
                ok = function(rewardRows)
                    if type(rewardRows[info.rewardKey]) == "table" then
                        Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期活动排行奖励已领取" })
                        return
                    end
                    local avatarIndex = ServerLeaderboard.PickLockedAvatar(payload.unlockedAvatars)
                    local reward = avatarIndex ~= nil and { type = "avatar", avatarIndex = avatarIndex, avatarId = "plant_" .. tostring(avatarIndex) } or { type = "none" }
                    local message = avatarIndex ~= nil and "上期活动排行奖励：解锁头像" or "已拥有全部头像，本次不发放头像奖励"
                    serverCloud:Set(uid, info.rewardKey, { claimedAt = Now(), rank = rank, score = score, reward = reward }, {
                        ok = function()
                            local response = { success = true, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, rank = rank, score = score, reward = reward, message = message }
                            deps_.RequestGuard.Record(uid, payload._requestRecordKey, response)
                            Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "奖励领取失败: " .. tostring(reason) })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "奖励状态读取失败: " .. tostring(reason) })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, deps_.Shared.EVENTS.CLAIM_ACTIVITY_RANK_REWARD_RESPONSE, { success = false, requestId = payload.requestId, activityId = info.activityId, cycleId = info.cycleId, message = "上期排名读取失败: " .. tostring(reason) })
        end,
    })
end

return ServerLeaderboard
