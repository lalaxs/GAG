-- ============================================================================
-- 社交服务端模块
-- ============================================================================
-- 只处理花园快照、拜访访问、排行榜、社交状态与点赞。
-- 偷菜逻辑仍保留在 server_main.lua，避免一次性拆分造成耦合风险。
-- ============================================================================

local SocialServer = {}

local deps_ = {}

local function Now()
    return os and os.time and os.time() or 0
end

local function Shared()
    return deps_.Shared
end

local function Send(connection, eventName, data)
    Shared().SendToClient(connection, eventName, data)
end

local function NormalizePositiveCount(value, maxValue)
    if deps_.normalizePositiveCount ~= nil then
        return deps_.normalizePositiveCount(value, maxValue)
    end
    local count = math.floor(tonumber(value or 1) or 1)
    if count < 1 then count = 1 end
    if maxValue ~= nil then count = math.min(count, maxValue) end
    return count
end

local function GetNicknameMap(userIds, done)
    local map = {}
    local clean = {}
    local seen = {}
    for _, uid in ipairs(userIds or {}) do
        if uid ~= nil and not seen[tostring(uid)] then
            seen[tostring(uid)] = true
            clean[#clean + 1] = uid
        end
    end
    if GetUserNickname == nil or #clean <= 0 then
        done(map)
        return
    end
    GetUserNickname({
        userIds = clean,
        onSuccess = function(nicknames)
            for _, info in ipairs(nicknames or {}) do
                map[info.userId] = info.nickname or "Tap玩家"
                map[tostring(info.userId)] = info.nickname or "Tap玩家"
            end
            done(map)
        end,
        onError = function()
            done(map)
        end,
    })
end

local function GetCropList(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.plot) ~= "table" or type(snapshot.plot.plants) ~= "table" then
        return {}
    end
    return snapshot.plot.plants
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
    while #result > (deps_.maxSocialRows or 20) do table.remove(result) end
    return result
end

local function FetchStealLogs(uid, done)
    serverCloud.list:Get(uid, Shared().KEYS.STEAL_LOGS, {
        ok = function(rows) done(NormalizeListRows(rows)) end,
        error = function() done({}) end,
    })
end

local function FetchRecentVisitors(uid, done)
    serverCloud.list:Get(uid, Shared().KEYS.RECENT_VISITORS, {
        ok = function(rows) done(NormalizeListRows(rows)) end,
        error = function() done({}) end,
    })
end

local function BuildLikeRecordKey(targetUid)
    return "liked_garden_" .. tostring(targetUid)
end

local function SaveCanonicalGardenSnapshot(uid, snapshot, farmState, connection, saveLabel)
    local shared = Shared()
    local canonical = deps_.buildVisitGardenFromAuthFarm(uid, snapshot.nickname, farmState, snapshot)
    canonical.nickname = snapshot.nickname or canonical.nickname
    canonical.unlockedPlotCount = math.max(1, tonumber(snapshot.unlockedPlotCount or canonical.unlockedPlotCount or 1) or 1)
    local score = math.max(0, math.floor(tonumber(canonical.bestTourValue or canonical.tourValue or 0) or 0))
    serverCloud:BatchSet(uid)
        :Set(shared.KEYS.GARDEN_SNAPSHOT, canonical)
        :SetInt(shared.KEYS.TOUR_RANK, score)
        :Save(saveLabel or "保存权威社交花园", {
            ok = function()
                Send(connection, shared.EVENTS.SAVE_GARDEN_RESULT, { success = true, message = "花园快照已同步", score = score })
            end,
            error = function(_, reason)
                Send(connection, shared.EVENTS.SAVE_GARDEN_RESULT, { success = false, message = "同步失败: " .. tostring(reason) })
            end,
        })
end

function SocialServer.Init(deps)
    deps_ = deps or {}
end

function SocialServer.SaveGardenSnapshot(uid, snapshot, connection)
    local shared = Shared()
    if type(snapshot) ~= "table" then
        Send(connection, shared.EVENTS.SAVE_GARDEN_RESULT, { success = false, message = "花园快照无效" })
        return
    end

    serverCloud:Get(uid, shared.KEYS.AUTH_FARM_STATE, {
        ok = function(scores)
            SaveCanonicalGardenSnapshot(uid, snapshot, scores[shared.KEYS.AUTH_FARM_STATE], connection, "保存权威社交花园")
        end,
        error = function()
            SaveCanonicalGardenSnapshot(uid, snapshot, nil, connection, "首次保存权威社交花园")
        end,
    })
end

function SocialServer.RequestGardenSnapshot(requesterUid, targetUid, connection)
    local shared = Shared()
    if targetUid == nil or targetUid <= 0 then
        Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "玩家 ID 无效" })
        return
    end
    serverCloud:Get(targetUid, shared.KEYS.GARDEN_SNAPSHOT, {
        ok = function(scores)
            local garden = scores[shared.KEYS.GARDEN_SNAPSHOT]
            if type(garden) ~= "table" or garden.plot == nil then
                Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "该玩家尚未开放花园" })
                return
            end
            RefreshRuntimeSnapshot(garden)
            local function SendGardenWithLikes(resolvedGarden)
                local function SendWithLikedState()
                    if requesterUid ~= nil and tostring(requesterUid) ~= tostring(targetUid) then
                        serverCloud.list:Get(requesterUid, BuildLikeRecordKey(targetUid), {
                            ok = function(records)
                                resolvedGarden.likedByMe = records ~= nil and #records > 0
                                Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = true, garden = resolvedGarden })
                            end,
                            error = function()
                                resolvedGarden.likedByMe = false
                                Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = true, garden = resolvedGarden })
                            end,
                        })
                    else
                        resolvedGarden.likedByMe = tostring(requesterUid) == tostring(targetUid)
                        Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = true, garden = resolvedGarden })
                    end
                end
                serverCloud:Get(targetUid, shared.KEYS.LIKE_COUNT, {
                    ok = function(likeScores)
                        resolvedGarden.likeCount = tonumber(likeScores[shared.KEYS.LIKE_COUNT] or resolvedGarden.likeCount or 0) or 0
                        SendWithLikedState()
                    end,
                    error = function()
                        resolvedGarden.likeCount = tonumber(resolvedGarden.likeCount or 0) or 0
                        SendWithLikedState()
                    end,
                })
            end
            local c = serverCloud:BatchCommit("记录花园拜访")
            if requesterUid ~= nil and tostring(requesterUid) ~= tostring(targetUid) then
                c:ListAdd(targetUid, shared.KEYS.RECENT_VISITORS, {
                    userId = requesterUid,
                    visitedAt = Now(),
                    time = Now(),
                })
                c:ListAdd(requesterUid, shared.KEYS.RECENT_VISITORS, {
                    userId = targetUid,
                    visitedAt = Now(),
                    time = Now(),
                    direction = "visited",
                })
            end
            c:Commit({
                ok = function()
                    print("[社交] 花园拜访记录已写入")
                end,
                error = function(_, reason)
                    print("[社交] 花园拜访记录写入失败: " .. tostring(reason))
                end,
            })
            serverCloud:Get(targetUid, shared.KEYS.AUTH_FARM_STATE, {
                ok = function(farmScores)
                    local authGarden = deps_.buildVisitGardenFromAuthFarm(targetUid, garden.nickname, farmScores[shared.KEYS.AUTH_FARM_STATE], garden)
                    SendGardenWithLikes(authGarden)
                end,
                error = function()
                    SendGardenWithLikes(garden)
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.GARDEN_RESPONSE, { success = false, message = "读取花园失败: " .. tostring(reason) })
        end,
    })
end

function SocialServer.RequestRank(count, connection, requesterUid)
    local shared = Shared()
    count = NormalizePositiveCount(count or 20, 50)
    serverCloud:GetRankList(shared.KEYS.TOUR_RANK, 1, count, {
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
                        score = item.iscore and item.iscore[shared.KEYS.TOUR_RANK] or 0,
                        isMe = tostring(userId) == tostring(requesterUid),
                        source = "rank",
                    }
                end
            end
            GetNicknameMap(userIds, function(nickMap)
                for _, entry in ipairs(result) do
                    entry.nickname = nickMap[entry.userId] or nickMap[tostring(entry.userId)] or entry.nickname
                end
                Send(connection, shared.EVENTS.RANK_RESPONSE, { success = true, list = result })
            end)
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.RANK_RESPONSE, { success = false, message = "排行榜读取失败: " .. tostring(reason) })
        end,
    })
end

function SocialServer.RequestSocialState(uid, connection)
    local shared = Shared()
    FetchStealLogs(uid, function(stealLogs)
        FetchRecentVisitors(uid, function(recentVisitors)
            serverCloud:GetRankList(shared.KEYS.TOUR_RANK, 1, 12, {
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
                                score = item.iscore and item.iscore[shared.KEYS.TOUR_RANK] or 0,
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

                    GetNicknameMap(userIds, function(nickMap)
                        for _, entry in ipairs(recommended) do
                            entry.nickname = nickMap[entry.userId] or nickMap[tostring(entry.userId)] or "Tap玩家"
                        end
                        for _, row in ipairs(stealLogs) do
                            row.thiefNickname = nickMap[row.thiefUserId] or nickMap[tostring(row.thiefUserId)] or "Tap玩家"
                        end
                        for _, row in ipairs(recentVisitors) do
                            row.nickname = nickMap[row.userId] or nickMap[tostring(row.userId)] or "Tap玩家"
                        end

                        Send(connection, shared.EVENTS.SOCIAL_STATE_RESPONSE, {
                            success = true,
                            stealLogs = stealLogs,
                            recentVisitors = recentVisitors,
                            recommendedPlayers = recommended,
                        })
                    end)
                end,
                error = function()
                    Send(connection, shared.EVENTS.SOCIAL_STATE_RESPONSE, {
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

function SocialServer.LikeGarden(uid, targetUid, connection, requestId, requestRecordKey)
    local shared = Shared()
    targetUid = tonumber(targetUid or 0) or 0
    if targetUid <= 0 then
        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "花园不存在", requestId = requestId })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "不能给自己的花园点赞", requestId = requestId })
        return
    end
    local recordKey = BuildLikeRecordKey(targetUid)
    serverCloud.list:Get(uid, recordKey, {
        ok = function(records)
            if records ~= nil and #records > 0 then
                serverCloud:Get(targetUid, shared.KEYS.LIKE_COUNT, {
                    ok = function(scores)
                        local response = {
                            success = false,
                            alreadyLiked = true,
                            message = "已经点赞过这个花园了",
                            targetUserId = targetUid,
                            requestId = requestId,
                            likeCount = tonumber(scores[shared.KEYS.LIKE_COUNT] or 0) or 0,
                        }
                        deps_.RequestGuard.Record(uid, requestRecordKey, response)
                        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                    end,
                    error = function()
                        local response = { success = false, alreadyLiked = true, message = "已经点赞过这个花园了", targetUserId = targetUid, requestId = requestId }
                        deps_.RequestGuard.Record(uid, requestRecordKey, response)
                        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                    end,
                })
                return
            end
            local response = {
                success = true,
                message = "已点赞这个花园",
                targetUserId = targetUid,
                requestId = requestId,
            }
            local c = serverCloud:BatchCommit("点赞花园")
            c:ListAdd(uid, recordKey, { targetUserId = targetUid, likedAt = Now() })
            c:ScoreAddInt(targetUid, shared.KEYS.LIKE_COUNT, 1)
            c:Commit({
                ok = function()
                    serverCloud:Get(targetUid, shared.KEYS.LIKE_COUNT, {
                        ok = function(scores)
                            response.likeCount = tonumber(scores[shared.KEYS.LIKE_COUNT] or 0) or 0
                            deps_.RequestGuard.Record(uid, requestRecordKey, response)
                            Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                        end,
                        error = function()
                            Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "点赞失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "点赞记录读取失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

return SocialServer
