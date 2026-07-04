-- ============================================================================
-- 社交服务端模块
-- ============================================================================
-- 只处理花园快照、拜访访问、排行榜、社交状态与点赞。
-- 偷菜逻辑仍保留在 server_main.lua，避免一次性拆分造成耦合风险。
-- ============================================================================

local SocialServer = {}

local ServerCloudStore = require("server.server_cloud_store")
local UserId = require("utils.user_id")
local LeaderboardSanitize = require("server.leaderboard_sanitize")
local SocialProfile = require("server.social_profile")

local deps_ = {}

local function Now()
    return os and os.time and os.time() or 0
end

local function NormalizeUserId(userId)
    if deps_.normalizeUserId ~= nil then return deps_.normalizeUserId(userId) end
    return UserId.Normalize(userId)
end

local function BuildUidKeyCandidates(uid)
    if deps_.buildUidKeyCandidates ~= nil then return deps_.buildUidKeyCandidates(uid) end
    return UserId.BuildKeyCandidates(uid)
end

local function GetCanonicalUidKey(uid)
    if deps_.getCanonicalUidKey ~= nil then return deps_.getCanonicalUidKey(uid) end
    return UserId.GetCanonicalKey(uid)
end

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or GetCanonicalUidKey(uid) or uid
end

local function NormalizeListId(value)
    if value == nil or value == "" then return nil end
    local text = tostring(value)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end
    local integerText = string.match(text, "^(%-?%d+)%.0+$")
    if integerText ~= nil then return integerText end
    return text
end

local function SameUserId(left, right)
    local leftId = NormalizeUserId(left)
    local rightId = NormalizeUserId(right)
    return leftId ~= nil and rightId ~= nil and leftId == rightId
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

local function GetFriendLimit()
    return math.max(1, math.floor(tonumber(deps_.friendLimit or 50) or 50))
end

local function CountFriends(rows, ownerUid)
    local seen = {}
    local count = 0
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
            local userId = NormalizeUserId(value.userId or value.friendUserId)
            if userId ~= nil and not UserId.Same(userId, ownerUid) and seen[userId] ~= true then
                seen[userId] = true
                count = count + 1
            end
        end
    end
    return count
end

local function DayKey()
    return os and os.date and os.date("%Y%m%d", Now()) or "unknown"
end

local function BuildVisitRecordKey(visitorUid)
    return "visit_" .. DayKey() .. "_" .. tostring(visitorUid or "unknown")
end

local function NormalizeAvatar(value)
    if type(value) ~= "table" then return nil end
    local plantIndex = tonumber(value.plantIndex or value.selectedAvatar or value.index)
    local image = value.image
    if plantIndex == nil and (image == nil or image == "") then return nil end
    local normalized = {
        image = image,
        avatarId = value.avatarId,
        visualId = value.visualId,
        color = value.color,
        name = value.name,
        rarity = value.rarity,
    }
    if plantIndex ~= nil then
        normalized.plantIndex = math.floor(plantIndex)
        normalized.selectedAvatar = math.floor(plantIndex)
    end
    return normalized
end

local function IsDefaultAvatar(value)
    local avatar = NormalizeAvatar(value)
    if avatar == nil then return true end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    if plantIndex ~= nil then return math.floor(plantIndex) == 1 end
    return tostring(avatar.image or "") == "image/plants/plants (1).png"
end

local function ChooseDisplayNickname(primary, fallback)
    if not SocialProfile.IsPlaceholderNickname(primary) then return primary end
    if not SocialProfile.IsPlaceholderNickname(fallback) then return fallback end
    return primary or fallback
end

local function ChooseDisplayAvatar(primary, fallback)
    local primaryAvatar = NormalizeAvatar(primary)
    local fallbackAvatar = NormalizeAvatar(fallback)
    if fallbackAvatar ~= nil and (primaryAvatar == nil or (IsDefaultAvatar(primaryAvatar) and not IsDefaultAvatar(fallbackAvatar))) then
        return fallbackAvatar
    end
    return primaryAvatar
end

local function MergeResolvedProfile(profile, fallbackNickname, fallbackAvatar)
    profile = type(profile) == "table" and profile or {}
    return {
        nickname = ChooseDisplayNickname(profile.nickname, fallbackNickname) or "Tap玩家",
        avatar = ChooseDisplayAvatar(profile.avatar, fallbackAvatar),
        score = profile.score or 0,
    }
end

local function MergeSnapshotProfile(snapshot, existingSnapshot, tapNickname)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local incomingPlaceholderName = SocialProfile.IsPlaceholderNickname(snapshot.nickname)
    if incomingPlaceholderName and tapNickname ~= nil and tapNickname ~= "" then
        snapshot.nickname = tapNickname
        incomingPlaceholderName = false
    end

    if type(existingSnapshot) ~= "table" then return snapshot end

    if incomingPlaceholderName and not SocialProfile.IsPlaceholderNickname(existingSnapshot.nickname) then
        snapshot.nickname = existingSnapshot.nickname
    end

    local incomingAvatar = NormalizeAvatar(snapshot.avatar)
    local existingAvatar = NormalizeAvatar(existingSnapshot.avatar)
    if existingAvatar ~= nil and (incomingAvatar == nil or (IsDefaultAvatar(incomingAvatar) and not IsDefaultAvatar(existingAvatar))) then
        snapshot.avatar = existingAvatar
    end

    return snapshot
end

local function GetNicknameMap(userIds, done)
    local map = {}
    local clean = {}
    local seen = {}
    for _, uid in ipairs(userIds or {}) do
        local normalized = NormalizeUserId(uid)
        if normalized ~= nil and not seen[normalized] then
            seen[normalized] = true
            clean[#clean + 1] = UserId.ForRankCloud(normalized) or normalized
        end
    end
    if GetUserNickname == nil or #clean <= 0 then
        done(map)
        return
    end
    GetUserNickname({
        userIds = clean,
        onSuccess = function(response)
            local rows = response
            if type(response) == "table" and type(response.nicknames) == "table" then
                rows = response.nicknames
            end
            for _, info in ipairs(rows or {}) do
                local normalized = NormalizeUserId(info.userId)
                local nickname = info.nickname or "Tap玩家"
                if normalized ~= nil then map[normalized] = nickname end
                map[info.userId] = nickname
                map[tostring(info.userId)] = nickname
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

local function ReadListFromUidCandidates(uid, listKey, done)
    ServerCloudStore.ListGet(uid, listKey, {
        ok = function(rows, hitKey)
            done(rows or {}, hitKey)
        end,
        error = function()
            done({}, nil)
        end,
    })
end

local function ReadQuotaFromUidCandidates(uid, quotaKey, done)
    ServerCloudStore.QuotaGet(uid, quotaKey, {
        ok = function(rows, hitKey)
            done(rows or {}, hitKey)
        end,
        error = function()
            done({}, nil)
        end,
    })
end

local function FetchStealLogs(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.STEAL_LOGS, function(rows) done(NormalizeListRows(rows)) end)
end

local function FetchRecentVisitors(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.RECENT_VISITORS, function(rows)
        local normalized = NormalizeListRows(rows)
        local result = {}
        local seen = {}
        for _, row in ipairs(normalized) do
            local userId = NormalizeUserId(row.userId or row.thiefUserId or row.targetUserId)
            local key = row.visitKey or (userId ~= nil and BuildVisitRecordKey(userId)) or row.listId
            key = tostring(key or (#result + 1))
            if not seen[key] then
                seen[key] = true
                if userId ~= nil then row.userId = userId end
                result[#result + 1] = row
            end
        end
        done(result)
    end)
end

local function NormalizeFriendRows(rows, ownerUid)
    local result = {}
    local seen = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
            local userId = NormalizeUserId(value.userId or value.friendUserId)
            if userId ~= nil and not SameUserId(userId, ownerUid) and not seen[userId] then
                seen[userId] = true
                result[#result + 1] = {
                    listId = row.list_id or row.listId or value.listId,
                    userId = userId,
                    nickname = value.nickname,
                    avatar = NormalizeAvatar(value.avatar),
                    addedAt = value.addedAt or value.time,
                    score = value.score or value.tourValue or 0,
                    source = "friend",
                }
            end
        end
    end
    table.sort(result, function(a, b)
        return tonumber(a.addedAt or 0) > tonumber(b.addedAt or 0)
    end)
    return result
end

local function CollectSelfFriendRows(rows, ownerUid)
    local deletes = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and SameUserId(value.userId or value.friendUserId, ownerUid) then
            deletes[#deletes + 1] = row
        end
    end
    return deletes
end

local function ListDeleteId(listId)
    if listId == nil then return nil end
    local numericListId = tonumber(listId)
    return numericListId ~= nil and numericListId or listId
end

local function CommitListDeletes(label, rows, done)
    rows = rows or {}
    if #rows <= 0 then
        if done ~= nil then done(true) end
        return
    end
    local c = serverCloud:BatchCommit(label)
    local deleteCount = 0
    for _, row in ipairs(rows) do
        local value = row.value or row
        local listId = NormalizeListId(row.list_id or row.listId or (type(value) == "table" and value.listId or nil))
        local deleteId = ListDeleteId(listId)
        if deleteId ~= nil then
            c:ListDelete(deleteId)
            deleteCount = deleteCount + 1
        end
    end
    if deleteCount <= 0 then
        print(string.format("[社交] %s失败: 无有效 list_id，rows=%d", tostring(label), #rows))
        if done ~= nil then done(false) end
        return
    end
    c:Commit({
        ok = function()
            if done ~= nil then done(true) end
        end,
        error = function(_, reason)
            print(string.format("[社交] %s失败: %s", tostring(label), tostring(reason)))
            if done ~= nil then done(false) end
        end,
    })
end

local function CommitListDeletesSequential(labelPrefix, jobs, done)
    jobs = jobs or {}
    local index = 1
    local function nextJob()
        local job = jobs[index]
        index = index + 1
        if job == nil then
            if done ~= nil then done(true) end
            return
        end
        CommitListDeletes(labelPrefix .. tostring(job.label or index), job.rows or {}, function(success)
            if success ~= true then
                if done ~= nil then done(false) end
                return
            end
            nextJob()
        end)
    end
    nextJob()
end

local function NormalizeFriendRequestFromUserId(value)
    if type(value) ~= "table" then return nil end
    return NormalizeUserId(value.fromUserId or value.senderUserId)
end

local function NormalizeFriendRequestTargetUserId(value)
    if type(value) ~= "table" then return nil end
    return NormalizeUserId(value.targetUserId or value.receiverUserId or value.ownerUserId)
end

local function NormalizeFriendRequestRows(rows, ownerUid)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and (value.status == nil or value.status == "pending") then
            local fromUserId = NormalizeFriendRequestFromUserId(value)
            local targetUserId = NormalizeFriendRequestTargetUserId(value)
            if fromUserId ~= nil and targetUserId ~= nil and SameUserId(targetUserId, ownerUid) and not SameUserId(fromUserId, ownerUid) then
                result[#result + 1] = {
                    listId = row.list_id or row.listId or value.listId,
                    requestId = row.list_id or row.listId or value.requestId,
                    senderUserId = fromUserId,
                    receiverUserId = targetUserId,
                    ownerUserId = targetUserId,
                    profileTrusted = value.senderUserId ~= nil and value.receiverUserId ~= nil and value.ownerUserId ~= nil,
                    fromUserId = fromUserId,
                    fromNickname = value.fromNickname,
                    avatar = NormalizeAvatar(value.avatar),
                    targetUserId = targetUserId,
                    sentAt = value.sentAt or value.time,
                    time = value.time or value.sentAt,
                    status = "pending",
                }
            end
        end
    end
    table.sort(result, function(a, b)
        return tonumber(a.sentAt or a.time or 0) > tonumber(b.sentAt or b.time or 0)
    end)
    return result
end

local function CollectInvalidFriendRequestRows(rows, ownerUid)
    local deletes = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and (value.status == nil or value.status == "pending") then
            local fromUserId = NormalizeFriendRequestFromUserId(value)
            local targetUserId = NormalizeFriendRequestTargetUserId(value)
            if fromUserId == nil
                or targetUserId == nil
                or SameUserId(fromUserId, ownerUid)
                or not SameUserId(targetUserId, ownerUid) then
                deletes[#deletes + 1] = row
            end
        end
    end
    return deletes
end

local function BuildFriendSet(friends)
    local set = {}
    for _, friend in ipairs(friends or {}) do
        local userId = NormalizeUserId(friend.userId or friend.friendUserId)
        if userId ~= nil then set[userId] = true end
    end
    return set
end

local function FilterFriendRequestsForExistingFriends(rows, requests, friends, ownerUid)
    local friendSet = BuildFriendSet(friends)
    local deletes = {}
    local filtered = {}
    for _, request in ipairs(requests or {}) do
        local fromUserId = NormalizeUserId(request.fromUserId)
        if fromUserId ~= nil and friendSet[fromUserId] == true then
            for _, row in ipairs(rows or {}) do
                local value = row.value or row
                if type(value) == "table" and (value.status == nil or value.status == "pending") then
                    local valueFromUserId = NormalizeFriendRequestFromUserId(value)
                    local valueTargetUserId = NormalizeFriendRequestTargetUserId(value)
                    if (SameUserId(valueFromUserId, fromUserId) and SameUserId(valueTargetUserId, ownerUid))
                        or (SameUserId(valueFromUserId, ownerUid) and SameUserId(valueTargetUserId, fromUserId)) then
                        deletes[#deletes + 1] = row
                    end
                end
            end
        else
            filtered[#filtered + 1] = request
        end
    end
    return filtered, deletes
end

local function GetSocialNoticeTargetUserId(value)
    if type(value) ~= "table" then return nil end
    return NormalizeUserId(value.targetUserId)
end

local function GetSocialNoticeSenderUserId(value)
    if type(value) ~= "table" then return nil end
    return NormalizeUserId(value.senderUserId)
end

local function GetSocialNoticeActorUserId(value)
    if type(value) ~= "table" then return nil end
    if value.type == "friend_request_sent" then
        return GetSocialNoticeTargetUserId(value)
    end
    return NormalizeUserId(value.fromUserId)
end

--- friend_request_sent 是发件箱通知，只应出现在发起方；接收方 list 出现则视为脏数据。
local function IsValidSocialNoticeForOwner(value, ownerUid)
    if type(value) ~= "table" then return false end
    local owner = NormalizeUserId(ownerUid)
    if owner == nil then return true end
    if value.type == "friend_request_sent" then
        local targetUserId = GetSocialNoticeTargetUserId(value)
        if targetUserId ~= nil and SameUserId(targetUserId, owner) then
            return false
        end
        local senderUserId = GetSocialNoticeSenderUserId(value)
        if senderUserId ~= nil then
            return SameUserId(senderUserId, owner)
        end
        return targetUserId ~= nil and not SameUserId(targetUserId, owner)
    end
    if value.type == "friend_request_accepted" or value.type == "friend_request_rejected" then
        local responderUserId = NormalizeUserId(value.fromUserId)
        if responderUserId ~= nil and SameUserId(responderUserId, owner) then
            return false
        end
    end
    return true
end

local function CollectInvalidSocialNoticeRows(rows, ownerUid)
    local deletes = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and not IsValidSocialNoticeForOwner(value, ownerUid) then
            deletes[#deletes + 1] = row
        end
    end
    return deletes
end

local function NormalizeNoticeRows(rows, ownerUid)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and IsValidSocialNoticeForOwner(value, ownerUid) then
            value.listId = row.list_id or row.listId or value.listId
            result[#result + 1] = value
        end
    end
    table.sort(result, function(a, b)
        return tonumber(a.time or a.sentAt or 0) > tonumber(b.time or b.sentAt or 0)
    end)
    return result
end

local function FetchFriends(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.FRIENDS, function(rows)
        local selfFriendRows = CollectSelfFriendRows(rows, uid)
        local friends = NormalizeFriendRows(rows, uid)
        if #selfFriendRows > 0 then
            CommitListDeletes("清理异常自我好友", selfFriendRows, function(cleaned)
                if cleaned then
                    print(string.format("[社交健康] 已清理自我好友记录 uid=%s count=%d", tostring(NormalizeUserId(uid)), #selfFriendRows))
                end
                done(friends)
            end)
            return
        end
        done(friends)
    end)
end

local function FetchFriendRequests(uid, friends, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.FRIEND_REQUESTS, function(rows)
        local invalidRequestRows = CollectInvalidFriendRequestRows(rows, uid)
        local requests = NormalizeFriendRequestRows(rows, uid)
        local friendFilteredRequests, friendRequestDeletes = FilterFriendRequestsForExistingFriends(rows, requests, friends, uid)
        local deletes = {}
        for _, row in ipairs(invalidRequestRows) do deletes[#deletes + 1] = row end
        for _, row in ipairs(friendRequestDeletes) do deletes[#deletes + 1] = row end
        if #deletes > 0 then
            CommitListDeletes("清理异常好友申请", deletes, function(cleaned)
                if cleaned then
                    print(string.format("[社交健康] 已清理异常好友申请 uid=%s count=%d", tostring(NormalizeUserId(uid)), #deletes))
                end
                done(friendFilteredRequests)
            end)
            return
        end
        done(friendFilteredRequests)
    end)
end

local function FetchSocialNotices(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.SOCIAL_NOTICES, function(rows)
        local invalidRows = CollectInvalidSocialNoticeRows(rows, uid)
        local notices = NormalizeNoticeRows(rows, uid)
        if #invalidRows > 0 then
            CommitListDeletes("清理异常社交通知", invalidRows, function(cleaned)
                if cleaned then
                    print(string.format("[社交健康] 已清理异常社交通知 uid=%s count=%d", tostring(NormalizeUserId(uid)), #invalidRows))
                end
                done(notices)
            end)
            return
        end
        done(notices)
    end)
end

local function ReadScoreFromUidCandidates(uid, scoreKey, done)
    ServerCloudStore.ReadScore(uid, scoreKey, done)
end

local function ReadTargetScoreFromUidCandidates(uid, scoreKey, done)
    ServerCloudStore.ReadTargetScore(uid, scoreKey, done)
end

local function FetchGardenProfiles(userIds, done)
    local ids = {}
    local seen = {}
    for _, userId in ipairs(userIds or {}) do
        local normalized = NormalizeUserId(userId)
        if normalized ~= nil and not seen[normalized] then
            seen[normalized] = true
            ids[#ids + 1] = normalized
        end
    end
    local profiles = {}
    local index = 1
    local function nextOne()
        local userId = ids[index]
        index = index + 1
        if userId == nil then
            done(profiles)
            return
        end
        ReadTargetScoreFromUidCandidates(UserId.ForRankCloud(userId) or userId, Shared().KEYS.GARDEN_SNAPSHOT, function(garden)
            if type(garden) == "table" then
                local ownerId = UserId.Normalize(garden.userId) or userId
                if UserId.Same(ownerId, userId) then
                    SocialProfile.StoreProfile(profiles, userId, {
                        nickname = garden.nickname,
                        avatar = NormalizeAvatar(garden.avatar),
                        score = garden.tourValue or 0,
                    })
                else
                    print(string.format("[社交] 跳过快照 UID 不匹配 target=%s owner=%s", tostring(userId), tostring(garden.userId)))
                end
            end
            nextOne()
        end)
    end
    nextOne()
end

local function BuildLikeRecordKey(targetUid)
    return "liked_garden_" .. tostring(targetUid)
end

local function BuildFriendPairKey(leftUid, rightUid)
    local left = tostring(NormalizeUserId(leftUid) or leftUid or "")
    local right = tostring(NormalizeUserId(rightUid) or rightUid or "")
    if left > right then left, right = right, left end
    return "friend_pair_" .. left .. "_" .. right
end

local function SaveCanonicalGardenSnapshot(uid, snapshot, farmState, connection, saveLabel)
    local shared = Shared()
    local canonicalUid = GetCanonicalUidKey(uid) or NormalizeUserId(uid)
    local rankUid = UserId.ForRankCloud(canonicalUid) or CloudUid(uid)
    local canonical = deps_.buildVisitGardenFromAuthFarm(canonicalUid, snapshot.nickname, farmState, snapshot)
    canonical.nickname = snapshot.nickname or canonical.nickname
    canonical.avatar = NormalizeAvatar(snapshot.avatar or canonical.avatar)
    canonical.unlockedPlotCount = math.max(1, tonumber(snapshot.unlockedPlotCount or canonical.unlockedPlotCount or 1) or 1)
    local score = math.max(0, math.floor(tonumber(canonical.tourValue or 0) or 0))
    local label = saveLabel or "保存权威社交花园"
    local c = serverCloud:BatchCommit(label)
    ServerCloudStore.BatchScoreSet(c, uid, shared.KEYS.GARDEN_SNAPSHOT, canonical)
    ServerCloudStore.BatchScoreSet(c, uid, shared.KEYS.SOCIAL_SAVE, {
        visitablePlotIndex = canonical.visitablePlotIndex,
        updatedAt = Now(),
    })
    c:ScoreSetInt(rankUid, shared.KEYS.TOUR_RANK, score)
    c:Commit({
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

    ReadScoreFromUidCandidates(uid, shared.KEYS.GARDEN_SNAPSHOT, function(existingSnapshot)
        GetNicknameMap({ uid }, function(nickMap)
            local canonicalUid = GetCanonicalUidKey(uid) or NormalizeUserId(uid)
            local tapNickname = SocialProfile.LookupNickname(nickMap, canonicalUid or uid)
            local mergedSnapshot = MergeSnapshotProfile(snapshot, existingSnapshot, tapNickname)
            ReadScoreFromUidCandidates(uid, shared.KEYS.AUTH_FARM_STATE, function(farmState)
                SaveCanonicalGardenSnapshot(uid, mergedSnapshot, farmState, connection, farmState ~= nil and "保存权威社交花园" or "首次保存权威社交花园")
            end)
        end)
    end)
end

local function ResolveCloudReadUid(uid)
    local normalized = NormalizeUserId(uid)
    return UserId.ForRankCloud(normalized) or normalized or uid
end

local function SnapshotBelongsToTarget(snapshot, targetUid)
    if type(snapshot) ~= "table" then return false end
    if snapshot.userId == nil then return true end
    return UserId.Same(snapshot.userId, targetUid)
end

function SocialServer.RequestGardenSnapshot(requesterUid, targetUid, connection, requestId, requestRecordKey)
    local shared = Shared()
    local normalizedRequesterUid = NormalizeUserId(requesterUid)
    local normalizedTargetUid = NormalizeUserId(targetUid)
    if normalizedTargetUid == nil then
        local response = { success = false, message = "玩家 ID 无效", requestId = requestId }
        Send(connection, shared.EVENTS.GARDEN_RESPONSE, response)
        return
    end
    print(string.format(
        "[社交] 拜访花园 requester=%s target=%s",
        tostring(normalizedRequesterUid),
        tostring(normalizedTargetUid)
    ))
    local requesterCloudUid = normalizedRequesterUid or requesterUid
    local targetCloudUid = ResolveCloudReadUid(normalizedTargetUid)
    local function SendGardenResponse(response)
        response.requestId = requestId
        response.targetUserId = normalizedTargetUid
        if requestRecordKey ~= nil and response.success == true then
            deps_.RequestGuard.Record(requesterUid, requestRecordKey, response)
        end
        Send(connection, shared.EVENTS.GARDEN_RESPONSE, response)
    end

    local SendGardenWithLikes

    local function SendTargetGarden(resolvedGarden)
        if type(resolvedGarden) ~= "table" then
            SendGardenResponse({ success = false, message = "花园数据无效" })
            return
        end
        resolvedGarden.userId = normalizedTargetUid
        GetNicknameMap({ normalizedTargetUid }, function(targetNickMap)
            FetchGardenProfiles({ normalizedTargetUid }, function(targetProfileMap)
                SocialProfile.ApplyDisplayProfile(resolvedGarden, normalizedTargetUid, targetProfileMap, targetNickMap)
                SendGardenWithLikes(resolvedGarden)
            end)
        end)
    end

    SendGardenWithLikes = function(resolvedGarden)
        local function SendWithLikedState()
            if normalizedRequesterUid ~= nil and normalizedRequesterUid ~= normalizedTargetUid then
                ServerCloudStore.ListGet(requesterCloudUid, BuildLikeRecordKey(normalizedTargetUid), {
                    ok = function(records)
                        resolvedGarden.likedByMe = records ~= nil and #records > 0
                        SendGardenResponse({ success = true, garden = resolvedGarden })
                    end,
                    error = function()
                        resolvedGarden.likedByMe = false
                        SendGardenResponse({ success = true, garden = resolvedGarden })
                    end,
                })
            else
                resolvedGarden.likedByMe = normalizedRequesterUid == normalizedTargetUid
                SendGardenResponse({ success = true, garden = resolvedGarden })
            end
        end
        ServerCloudStore.Get(targetCloudUid, shared.KEYS.LIKE_COUNT, {
            ok = function(_scores, iscores)
                local likeScores = iscores or _scores or {}
                resolvedGarden.likeCount = tonumber(likeScores[shared.KEYS.LIKE_COUNT] or resolvedGarden.likeCount or 0) or 0
                SendWithLikedState()
            end,
            error = function()
                resolvedGarden.likeCount = tonumber(resolvedGarden.likeCount or 0) or 0
                SendWithLikedState()
            end,
        })
    end

    local function RecordVisit(visitorProfile, done)
        if normalizedRequesterUid == nil or normalizedRequesterUid == normalizedTargetUid then
            if done then done() end
            return
        end
        local profile = type(visitorProfile) == "table" and visitorProfile or {}
        local visitKey = BuildVisitRecordKey(normalizedRequesterUid)
        ServerCloudStore.ListGet(targetCloudUid, shared.KEYS.RECENT_VISITORS, {
            ok = function(rows)
                local c = serverCloud:BatchCommit("记录花园拜访")
                for _, row in ipairs(rows or {}) do
                    local value = row.value or row
                    if type(value) == "table" and (value.visitKey == visitKey or SameUserId(value.userId, normalizedRequesterUid)) then
                        local listId = row.list_id or row.listId or value.listId
                        if listId ~= nil then c:ListDelete(listId) end
                    end
                end
                local now = Now()
                c:ListAdd(targetCloudUid, shared.KEYS.RECENT_VISITORS, {
                    userId = normalizedRequesterUid,
                    nickname = profile.nickname or "Tap玩家",
                    avatar = NormalizeAvatar(profile.avatar),
                    visitKey = visitKey,
                    visitedAt = now,
                    time = now,
                })
                c:Commit({
                    ok = function()
                        print("[社交] 花园拜访记录已写入")
                        if done then done() end
                    end,
                    error = function(_, reason)
                        print("[社交] 花园拜访记录写入失败: " .. tostring(reason))
                        if done then done() end
                    end,
                })
            end,
            error = function(_, reason)
                print("[社交] 花园拜访记录读取失败: " .. tostring(reason))
                if done then done() end
            end,
        })
    end

    ReadTargetScoreFromUidCandidates(targetCloudUid, shared.KEYS.GARDEN_SNAPSHOT, function(garden)
        local snapshotMeta = type(garden) == "table" and garden or {}
        local snapshotValid = SnapshotBelongsToTarget(snapshotMeta, normalizedTargetUid)
        if type(garden) == "table" and garden.plot ~= nil and snapshotValid then
            RefreshRuntimeSnapshot(garden)
        elseif type(garden) == "table" and not snapshotValid then
            print(string.format(
                "[社交] 目标快照 UID 不匹配 target=%s owner=%s，忽略快照地块",
                tostring(normalizedTargetUid),
                tostring(garden.userId)
            ))
            snapshotMeta = {
                visitablePlotIndex = garden.visitablePlotIndex,
                unlockedPlotCount = garden.unlockedPlotCount,
            }
        else
            snapshotMeta = { visitablePlotIndex = 1, unlockedPlotCount = 1 }
        end
        ReadTargetScoreFromUidCandidates(targetCloudUid, shared.KEYS.AUTH_FARM_STATE, function(farmState, farmKey, farmError)
            if type(farmState) == "table" then
                if not UserId.Same(farmKey, GetCanonicalUidKey(normalizedTargetUid)) then
                    print(string.format("[存档兼容] 拜访花园使用历史权威农场 key=%s target=%s", tostring(farmKey), tostring(normalizedTargetUid)))
                end
                local authGarden = deps_.buildVisitGardenFromAuthFarm(
                    normalizedTargetUid,
                    snapshotValid and snapshotMeta.nickname or nil,
                    farmState,
                    snapshotMeta
                )
                print(string.format(
                    "[社交] 拜访命中权威农场 target=%s plants=%d",
                    tostring(normalizedTargetUid),
                    #(authGarden.plot and authGarden.plot.plants or {})
                ))
                SendTargetGarden(authGarden)
            elseif snapshotValid and snapshotMeta.plot ~= nil then
                SendTargetGarden(snapshotMeta)
            else
                local emptyGarden = deps_.buildVisitGardenFromAuthFarm(
                    normalizedTargetUid,
                    nil,
                    {},
                    snapshotMeta
                )
                print(string.format(
                    "[社交] 拜访降级空花园 target=%s reason=%s",
                    tostring(normalizedTargetUid),
                    tostring(farmError or "no_farm")
                ))
                SendTargetGarden(emptyGarden)
            end
        end)

        if normalizedRequesterUid ~= nil and normalizedRequesterUid ~= normalizedTargetUid then
            GetNicknameMap({ normalizedRequesterUid }, function(nickMap)
                FetchGardenProfiles({ normalizedRequesterUid }, function(profileMap)
                    local profile = profileMap[normalizedRequesterUid] or {}
                    RecordVisit({
                        nickname = profile.nickname or nickMap[normalizedRequesterUid] or "Tap玩家",
                        avatar = NormalizeAvatar(profile.avatar),
                    })
                end)
            end)
        end
    end)
end

function SocialServer.RequestRank(count, connection, requesterUid)
    local shared = Shared()
    count = NormalizePositiveCount(count or 20, 50)
    serverCloud:GetRankList(shared.KEYS.TOUR_RANK, 1, count, {
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
                        score = item.iscore and item.iscore[shared.KEYS.TOUR_RANK] or 0,
                        source = "rank",
                    }
                end
            end
            GetNicknameMap(userIds, function(nickMap)
                FetchGardenProfiles(userIds, function(profileMap)
                    local filtered = LeaderboardSanitize.FilterForDisplay(requesterUid, result, profileMap, nickMap, "tour")
                    Send(connection, shared.EVENTS.RANK_RESPONSE, { success = true, list = filtered })
                end)
            end)
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.RANK_RESPONSE, { success = false, message = "排行榜读取失败: " .. tostring(reason) })
        end,
    })
end

local function FetchDailyQuota(uid, done)
    local daily = { stealCount = 0, giftSentCount = 0, stealAdCount = 0, stealLimit = deps_.dailyStealLimit or 5, seedPackAdCount = 0, seedPackAdLimit = deps_.dailySeedPackAdLimit or 5, matureAdCount = 0, matureAdLimit = deps_.dailyMatureAdLimit or 5 }
    ReadQuotaFromUidCandidates(uid, "daily_steal", function(stealRows)
        local row = stealRows and stealRows[1]
        daily.stealCount = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
        ReadQuotaFromUidCandidates(uid, "daily_steal_ad_bonus", function(bonusRows)
            local bonusRow = bonusRows and bonusRows[1]
            local bonus = math.max(0, math.floor(tonumber(bonusRow and bonusRow.value or 0) or 0))
            daily.stealLimit = (deps_.dailyStealLimit or 5) + bonus
            ReadQuotaFromUidCandidates(uid, "daily_steal_ad", function(adRows)
                local adRow = adRows and adRows[1]
                daily.stealAdCount = math.max(0, math.floor(tonumber(adRow and adRow.value or 0) or 0))
                ReadQuotaFromUidCandidates(uid, "daily_seed_pack_ad", function(packRows)
                    local packRow = packRows and packRows[1]
                    daily.seedPackAdCount = math.max(0, math.floor(tonumber(packRow and packRow.value or 0) or 0))
                    ReadQuotaFromUidCandidates(uid, "daily_mature_ad", function(matureRows)
                        local matureRow = matureRows and matureRows[1]
                        daily.matureAdCount = math.max(0, math.floor(tonumber(matureRow and matureRow.value or 0) or 0))
                        ReadQuotaFromUidCandidates(uid, "daily_seed_gift", function(giftRows)
                            local giftRow = giftRows and giftRows[1]
                            daily.giftSentCount = math.max(0, math.floor(tonumber(giftRow and giftRow.value or 0) or 0))
                            done(daily)
                        end)
                    end)
                end)
            end)
        end)
    end)
end

local function FetchGiftTargets(uid, done)
    local today = DayKey()
    ReadListFromUidCandidates(uid, Shared().KEYS.GIFT_SENT_TARGETS, function(rows)
        local targets = {}
        for _, row in ipairs(rows or {}) do
            local value = row.value or row
            if type(value) == "table" and value.targetUserId ~= nil and tostring(value.day or today) == today then
                targets[tostring(value.targetUserId)] = true
            end
        end
        done(targets)
    end)
end

function SocialServer.FetchGardenProfiles(userIds, done)
    return FetchGardenProfiles(userIds, done)
end

function SocialServer.GetPlayerGardenAvatar(uid, done)
    local normalized = NormalizeUserId(uid)
    if normalized == nil then
        if done ~= nil then done(nil) end
        return
    end
    ReadTargetScoreFromUidCandidates(UserId.ForRankCloud(normalized) or normalized, Shared().KEYS.GARDEN_SNAPSHOT, function(garden)
        if type(garden) ~= "table" or not SnapshotBelongsToTarget(garden, normalized) then
            if done ~= nil then done(nil) end
            return
        end
        if done ~= nil then done(NormalizeAvatar(garden.avatar)) end
    end)
end

function SocialServer.RequestSocialState(uid, connection)
    local shared = Shared()

    local function ContinueWithSocialSave(socialSave)
        socialSave = type(socialSave) == "table" and socialSave or { visitablePlotIndex = 1 }
        FetchStealLogs(uid, function(stealLogs)
            FetchRecentVisitors(uid, function(recentVisitors)
                FetchFriends(uid, function(friends)
                    FetchFriendRequests(uid, friends, function(friendRequests)
                        FetchSocialNotices(uid, function(socialNotices)
                            serverCloud:GetRankList(shared.KEYS.TOUR_RANK, 1, 12, {
                                ok = function(rankList)
                                    local userIds = {}
                                    local recommended = {}
                                    local seen = { [tostring(uid)] = true }

                                    for _, friend in ipairs(friends) do
                                        if friend.userId ~= nil then
                                            seen[tostring(friend.userId)] = true
                                            userIds[#userIds + 1] = friend.userId
                                        end
                                    end

                                    for _, request in ipairs(friendRequests) do
                                        if request.fromUserId ~= nil then userIds[#userIds + 1] = request.fromUserId end
                                    end

                                    for _, notice in ipairs(socialNotices) do
                                        local profileUserId = GetSocialNoticeActorUserId(notice)
                                        if profileUserId ~= nil then userIds[#userIds + 1] = profileUserId end
                                    end

                                    for _, row in ipairs(recentVisitors) do
                                        local userId = row.userId or row.thiefUserId or row.targetUserId
                                        if userId ~= nil then
                                            userIds[#userIds + 1] = userId
                                            if not seen[tostring(userId)] then
                                                seen[tostring(userId)] = true
                                                recommended[#recommended + 1] = { userId = userId, score = 0, source = row.direction == "visited" and "recent_visit" or "recent_visitor" }
                                            end
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

                                    GetNicknameMap(userIds, function(nickMap)
                                        FetchGardenProfiles(userIds, function(profileMap)
                                            for _, entry in ipairs(friends) do
                                                SocialProfile.ApplyDisplayProfile(entry, entry.userId, profileMap, nickMap, entry.nickname)
                                            end
                                            for _, entry in ipairs(recommended) do
                                                SocialProfile.ApplyDisplayProfile(entry, entry.userId, profileMap, nickMap, entry.nickname)
                                            end
                                            for _, request in ipairs(friendRequests) do
                                                local fallbackNickname = request.profileTrusted == true and request.fromNickname or nil
                                                local ownerNickname = SocialProfile.LookupNickname(nickMap, uid)
                                                if fallbackNickname ~= nil and ownerNickname ~= nil and tostring(fallbackNickname) == tostring(ownerNickname) then
                                                    fallbackNickname = nil
                                                end
                                                SocialProfile.ApplyDisplayProfile(request, request.fromUserId, profileMap, nickMap, fallbackNickname)
                                                request.fromNickname = request.nickname
                                            end
                                            for _, notice in ipairs(socialNotices) do
                                                local profileUserId = GetSocialNoticeActorUserId(notice)
                                                SocialProfile.ApplyDisplayProfile(notice, profileUserId, profileMap, nickMap, notice.fromNickname)
                                                if notice.type == "friend_request_sent" then
                                                    notice.targetNickname = notice.nickname
                                                else
                                                    notice.fromNickname = notice.nickname
                                                end
                                            end
                                            for _, row in ipairs(stealLogs) do
                                                SocialProfile.ApplyDisplayProfile(row, row.thiefUserId, profileMap, nickMap, row.thiefNickname)
                                                row.thiefNickname = row.nickname
                                            end
                                            for _, row in ipairs(recentVisitors) do
                                                SocialProfile.ApplyDisplayProfile(row, row.userId, profileMap, nickMap, row.nickname)
                                            end

                                            local filteredRecommended = {}
                                            for _, entry in ipairs(recommended) do
                                                if entry.profileResolved == true or not SocialProfile.IsUnresolvedDisplay(entry) then
                                                    filteredRecommended[#filteredRecommended + 1] = entry
                                                end
                                            end

                                            FetchDailyQuota(uid, function(daily)
                                                FetchGiftTargets(uid, function(giftTargets)
                                                    Send(connection, shared.EVENTS.SOCIAL_STATE_RESPONSE, {
                                                        success = true,
                                                        socialSave = socialSave,
                                                        friends = friends,
                                                        friendRequests = friendRequests,
                                                        socialNotices = socialNotices,
                                                        stealLogs = stealLogs,
                                                        recentVisitors = recentVisitors,
                                                        recommendedPlayers = filteredRecommended,
                                                        giftedTargets = giftTargets,
                                                        daily = daily,
                                                    })
                                                end)
                                            end)
                                        end)
                                    end)
                                end,
                                error = function()
                                    FetchDailyQuota(uid, function(daily)
                                        FetchGiftTargets(uid, function(giftTargets)
                                            Send(connection, shared.EVENTS.SOCIAL_STATE_RESPONSE, {
                                                success = true,
                                                socialSave = socialSave,
                                                friends = friends,
                                                friendRequests = friendRequests,
                                                socialNotices = socialNotices,
                                                stealLogs = stealLogs,
                                                recentVisitors = recentVisitors,
                                                recommendedPlayers = {},
                                                giftedTargets = giftTargets,
                                                daily = daily,
                                            })
                                        end)
                                    end)
                                end,
                            })
                        end)
                    end)
                end)
            end)
        end)
    end

    local function ContinueWithResolvedSocialSave(socialSave, sourceKey)
        socialSave = type(socialSave) == "table" and socialSave or { visitablePlotIndex = 1 }
        socialSave.visitablePlotIndex = math.max(1, math.floor(tonumber(socialSave.visitablePlotIndex or 1) or 1))
        local canonicalUid = GetCanonicalUidKey(uid)
        if sourceKey ~= nil and not UserId.Same(sourceKey, canonicalUid) then
            print(string.format("[存档兼容] 社交存档命中历史 uid key=%s，迁移到当前 key=%s", tostring(sourceKey), tostring(canonicalUid)))
            ServerCloudStore.SetScore(canonicalUid, shared.KEYS.SOCIAL_SAVE, socialSave)
        end
        ContinueWithSocialSave(socialSave)
    end

    ReadScoreFromUidCandidates(uid, shared.KEYS.SOCIAL_SAVE, function(socialSave, socialKey)
        if type(socialSave) == "table" then
            ContinueWithResolvedSocialSave(socialSave, socialKey)
            return
        end
        ReadScoreFromUidCandidates(uid, shared.KEYS.GARDEN_SNAPSHOT, function(garden, gardenKey)
            local fallback = { visitablePlotIndex = type(garden) == "table" and garden.visitablePlotIndex or 1 }
            ContinueWithResolvedSocialSave(fallback, type(garden) == "table" and gardenKey or nil)
        end)
    end)
end

function SocialServer.LikeGarden(uid, targetUid, connection, requestId, requestRecordKey)
    local shared = Shared()
    local fromUid = NormalizeUserId(uid)
    local toUid = NormalizeUserId(targetUid)
    local fromCloudUid = fromUid or uid
    local toCloudUid = toUid
    if fromUid == nil or toUid == nil then
        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "花园不存在", requestId = requestId })
        return
    end
    if fromUid == toUid then
        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, { success = false, message = "不能给自己的花园点赞", requestId = requestId })
        return
    end
    local recordKey = BuildLikeRecordKey(toUid)
    ServerCloudStore.ListGet(fromCloudUid, recordKey, {
        ok = function(records)
            if records ~= nil and #records > 0 then
                ServerCloudStore.Get(toCloudUid, shared.KEYS.LIKE_COUNT, {
                    ok = function(scores, iscores)
                        local likeScores = iscores or scores or {}
                        local response = {
                            success = false,
                            alreadyLiked = true,
                            message = "已经点赞过这个花园了",
                            targetUserId = toUid,
                            requestId = requestId,
                            likeCount = tonumber(likeScores[shared.KEYS.LIKE_COUNT] or 0) or 0,
                        }
                        deps_.RequestGuard.Record(uid, requestRecordKey, response)
                        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                    end,
                    error = function()
                        local response = { success = false, alreadyLiked = true, message = "已经点赞过这个花园了", targetUserId = toUid, requestId = requestId }
                        deps_.RequestGuard.Record(uid, requestRecordKey, response)
                        Send(connection, shared.EVENTS.LIKE_GARDEN_RESPONSE, response)
                    end,
                })
                return
            end
            local response = {
                success = true,
                message = "已点赞这个花园",
                targetUserId = toUid,
                requestId = requestId,
            }
            local c = serverCloud:BatchCommit("点赞花园")
            c:QuotaAdd(fromCloudUid, recordKey, 1, 1)
            c:ListAdd(fromCloudUid, recordKey, { targetUserId = toUid, likedAt = Now() })
            c:ScoreAddInt(UserId.ForRankCloud(toCloudUid) or toCloudUid, shared.KEYS.LIKE_COUNT, 1)
            c:Commit({
                ok = function()
                    ServerCloudStore.Get(toCloudUid, shared.KEYS.LIKE_COUNT, {
                        ok = function(scores, iscores)
                            local likeScores = iscores or scores or {}
                            response.likeCount = tonumber(likeScores[shared.KEYS.LIKE_COUNT] or 0) or 0
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

local function PendingRequestMatches(value, fromUid, targetUid)
    if type(value) ~= "table" or not (value.status == nil or value.status == "pending") then return false end
    local senderUserId = NormalizeFriendRequestFromUserId(value)
    local receiverUserId = NormalizeFriendRequestTargetUserId(value)
    return SameUserId(senderUserId, fromUid) and SameUserId(receiverUserId, targetUid)
end

local function HasPendingRequest(rows, fromUid, targetUid)
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if PendingRequestMatches(value, fromUid, targetUid) then return true end
    end
    return false
end

local function CollectPendingRequestDeletes(rows, leftUid, rightUid)
    local deletes = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if PendingRequestMatches(value, leftUid, rightUid) or PendingRequestMatches(value, rightUid, leftUid) then
            deletes[#deletes + 1] = row
        end
    end
    return deletes
end

local function AddDeleteRowsToCommit(commit, rows)
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        local listId = NormalizeListId(row.list_id or row.listId or (type(value) == "table" and value.listId or nil))
        local deleteId = ListDeleteId(listId)
        if deleteId ~= nil then commit:ListDelete(deleteId) end
    end
end

local function IsFriend(uid, targetUid, done)
    ServerCloudStore.ListGet(uid, Shared().KEYS.FRIENDS, {
        ok = function(rows)
            for _, row in ipairs(rows or {}) do
                local value = row.value or row
                if type(value) == "table" and SameUserId(value.userId or value.friendUserId, targetUid) then
                    done(true)
                    return
                end
            end
            done(false)
        end,
        error = function()
            done(false)
        end,
    })
end

local function CheckFriendLimit(uid, done)
    ServerCloudStore.ListGet(uid, Shared().KEYS.FRIENDS, {
        ok = function(rows)
            local count = CountFriends(rows, uid)
            done(count < GetFriendLimit(), count, rows)
        end,
        error = function()
            done(false, 0, {})
        end,
    })
end

local function CheckBothFriendLimits(leftUid, rightUid, done)
    CheckFriendLimit(leftUid, function(leftAvailable, leftCount)
        if leftAvailable ~= true then
            done(false, "你的好友数量已达上限", leftCount, nil)
            return
        end
        CheckFriendLimit(rightUid, function(rightAvailable, _, rightRows)
            if rightAvailable ~= true then
                done(false, "对方好友数量已达上限", leftCount, rightRows)
                return
            end
            done(true, nil, leftCount, rightRows)
        end)
    end)
end

function SocialServer.SendFriendRequest(uid, targetUid, connection, requestId, requestRecordKey, profile)
    local shared = Shared()
    profile = type(profile) == "table" and profile or {}
    local fromUid = NormalizeUserId(uid)
    local toUid = NormalizeUserId(targetUid)
    local fromCloudUid = CloudUid(fromUid)
    local toCloudUid = CloudUid(toUid)
    if fromUid == nil or toUid == nil then
        Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "玩家 ID 无效", requestId = requestId })
        return
    end
    if fromUid == toUid then
        Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "不能添加自己为好友", requestId = requestId })
        return
    end
    IsFriend(fromCloudUid, toUid, function(alreadyFriend)
        if alreadyFriend then
            Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "你们已经是好友了", requestId = requestId })
            return
        end
        CheckBothFriendLimits(fromCloudUid, toCloudUid, function(limitOk, limitMessage)
            if limitOk ~= true then
                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = limitMessage or "好友数量已达上限", requestId = requestId })
                return
            end
            ServerCloudStore.ListGet(toCloudUid, shared.KEYS.FRIEND_REQUESTS, {
                ok = function(targetRequestRows)
                    if HasPendingRequest(targetRequestRows, fromUid, toUid) then
                        Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请已发送，等待对方处理", requestId = requestId })
                        return
                    end
                    if HasPendingRequest(targetRequestRows, toUid, fromUid) then
                        Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "对方已向你发送好友申请，请先处理", requestId = requestId })
                        return
                    end
                    ServerCloudStore.ListGet(fromCloudUid, shared.KEYS.FRIEND_REQUESTS, {
                        ok = function(selfRequestRows)
                            if HasPendingRequest(selfRequestRows, toUid, fromUid) then
                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "对方已向你发送好友申请，请先处理", requestId = requestId })
                                return
                            end
                            if HasPendingRequest(selfRequestRows, fromUid, toUid) then
                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请已发送，等待对方处理", requestId = requestId })
                                return
                            end
                            local now = Now()
                            GetNicknameMap({ fromUid }, function(nickMap)
                                local fromNickname = ChooseDisplayNickname(SocialProfile.LookupNickname(nickMap, fromUid), profile.nickname) or tostring(fromUid)
                                local request = {
                                    ownerUserId = toUid,
                                    receiverUserId = toUid,
                                    targetUserId = toUid,
                                    senderUserId = fromUid,
                                    fromUserId = fromUid,
                                    fromNickname = fromNickname,
                                    avatar = NormalizeAvatar(profile.avatar),
                                    status = "pending",
                                    sentAt = now,
                                    time = now,
                                }
                                local response = { success = true, message = "好友申请已发送", requestId = requestId, targetUserId = toUid }
                                local c = serverCloud:BatchCommit("发送好友申请")
                                c:ListAdd(toCloudUid, shared.KEYS.FRIEND_REQUESTS, request)
                                if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response) end
                                c:Commit({
                                    ok = function()
                                        local noticeCommit = serverCloud:BatchCommit("记录好友申请发送")
                                        noticeCommit:ListAdd(fromCloudUid, shared.KEYS.SOCIAL_NOTICES, {
                                            type = "friend_request_sent",
                                            senderUserId = fromUid,
                                            targetUserId = toUid,
                                            time = now,
                                        })
                                        noticeCommit:Commit({
                                            ok = function()
                                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
                                            end,
                                            error = function(_, reason)
                                                print(string.format("[社交] 好友申请已发送但发件通知写入失败 uid=%s reason=%s", tostring(fromUid), tostring(reason)))
                                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
                                            end,
                                        })
                                    end,
                                    error = function(_, reason)
                                        Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请发送失败: " .. tostring(reason), requestId = requestId })
                                    end,
                                })
                            end)
                        end,
                        error = function(_, reason)
                            Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请读取失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end)
    end)
end

function SocialServer.RespondFriendRequest(uid, friendRequestId, fromUserId, accepted, connection, requestId, requestRecordKey)
    local shared = Shared()
    local targetUid = NormalizeUserId(uid)
    local requesterUid = NormalizeUserId(fromUserId)
    local targetCloudUid = CloudUid(targetUid)
    local requesterCloudUid = CloudUid(requesterUid)
    if targetUid == nil or requesterUid == nil then
        Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请无效", requestId = requestId })
        return
    end
    if SameUserId(targetUid, requesterUid) then
        ServerCloudStore.ListGet(targetCloudUid, shared.KEYS.FRIEND_REQUESTS, {
            ok = function(rows)
                local selfRequestDeletes = {}
                for _, row in ipairs(rows or {}) do
                    local value = row.value or row
                    if PendingRequestMatches(value, targetUid, targetUid) then
                        selfRequestDeletes[#selfRequestDeletes + 1] = row
                    end
                end
                CommitListDeletes("清理异常自我好友申请", selfRequestDeletes, function(cleaned)
                    if cleaned then
                        print(string.format("[社交健康] 已清理自我好友申请 uid=%s count=%d", tostring(targetUid), #selfRequestDeletes))
                    end
                    Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "不能添加自己为好友", requestId = requestId })
                end)
            end,
            error = function()
                Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "不能添加自己为好友", requestId = requestId })
            end,
        })
        return
    end
    ServerCloudStore.ListGet(targetCloudUid, shared.KEYS.FRIEND_REQUESTS, {
        ok = function(rows)
            local requestRow = nil
            local listId = friendRequestId
            for _, row in ipairs(rows or {}) do
                local value = row.value or row
                local rowId = row.list_id or row.listId or value.listId
                if (friendRequestId ~= nil and tostring(rowId) == tostring(friendRequestId)) or SameUserId(NormalizeFriendRequestFromUserId(value), requesterUid) then
                    if value.status == nil or value.status == "pending" then
                        requestRow = value
                        listId = rowId
                        break
                    end
                end
            end
            if requestRow == nil or listId == nil then
                Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请不存在或已处理", requestId = requestId })
                return
            end
            local now = Now()
            local response = {
                success = true,
                requestId = requestId,
                accepted = accepted == true,
                fromUserId = requesterUid,
                targetUserId = targetUid,
            }
            local targetRequestDeletes = CollectPendingRequestDeletes(rows, requesterUid, targetUid)
            local function ContinueWithRequesterRequests(requesterRequestRows)
                local requesterRequestDeletes = CollectPendingRequestDeletes(requesterRequestRows, requesterUid, targetUid)
                local function CommitResponse(targetProfile, requesterProfile, alreadyFriend, nickMap)
                    nickMap = nickMap or {}
                    targetProfile = MergeResolvedProfile(targetProfile, SocialProfile.LookupNickname(nickMap, targetUid), nil)
                    requesterProfile = MergeResolvedProfile(requesterProfile, SocialProfile.LookupNickname(nickMap, requesterUid) or requestRow.fromNickname, requestRow.avatar)
                    local function SendFailure(message)
                        Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, {
                            success = false,
                            message = message,
                            requestId = requestId,
                            fromUserId = requesterUid,
                            accepted = accepted == true,
                        })
                    end
                    local function SendSuccess()
                        if requestRecordKey ~= nil then deps_.RequestGuard.Record(uid, requestRecordKey, response) end
                        Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, response)
                    end
                    local function CommitRequesterAccept(resolvedTargetProfile)
                        local requesterCommit = serverCloud:BatchCommit("同意好友申请-发起方")
                        AddDeleteRowsToCommit(requesterCommit, requesterRequestDeletes)
                        requesterCommit:ListAdd(requesterCloudUid, shared.KEYS.FRIENDS, {
                            userId = targetUid,
                            nickname = resolvedTargetProfile.nickname,
                            avatar = NormalizeAvatar(resolvedTargetProfile.avatar),
                            score = resolvedTargetProfile.score or 0,
                            addedAt = now,
                            time = now,
                        })
                        requesterCommit:ListAdd(requesterCloudUid, shared.KEYS.SOCIAL_NOTICES, {
                            type = "friend_request_accepted",
                            fromUserId = targetUid,
                            time = now,
                        })
                        if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(requesterCommit, uid, requestRecordKey, response) end
                        requesterCommit:Commit({
                            ok = SendSuccess,
                            error = function(_, reason) SendFailure("处理好友申请失败: " .. tostring(reason)) end,
                        })
                    end
                    if accepted ~= true then
                        response.message = "已拒绝好友申请"
                        local rejectCommit = serverCloud:BatchCommit("拒绝好友申请")
                        AddDeleteRowsToCommit(rejectCommit, targetRequestDeletes)
                        AddDeleteRowsToCommit(rejectCommit, requesterRequestDeletes)
                        rejectCommit:ListAdd(requesterCloudUid, shared.KEYS.SOCIAL_NOTICES, {
                            type = "friend_request_rejected",
                            fromUserId = targetUid,
                            time = now,
                        })
                        if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(rejectCommit, uid, requestRecordKey, response) end
                        rejectCommit:Commit({
                            ok = SendSuccess,
                            error = function(_, reason) SendFailure("处理好友申请失败: " .. tostring(reason)) end,
                        })
                        return
                    end
                    if alreadyFriend == true then
                        response.message = "已是好友，申请已清理"
                        local cleanupCommit = serverCloud:BatchCommit("已是好友-清理申请")
                        AddDeleteRowsToCommit(cleanupCommit, targetRequestDeletes)
                        AddDeleteRowsToCommit(cleanupCommit, requesterRequestDeletes)
                        cleanupCommit:Commit({
                            ok = SendSuccess,
                            error = function(_, reason) SendFailure("处理好友申请失败: " .. tostring(reason)) end,
                        })
                        return
                    end
                    response.message = "已添加好友"
                    local targetCommit = serverCloud:BatchCommit("同意好友申请-接收方")
                    AddDeleteRowsToCommit(targetCommit, targetRequestDeletes)
                    targetCommit:QuotaAdd(targetCloudUid, BuildFriendPairKey(targetUid, requesterUid), 1, 1)
                    targetCommit:ListAdd(targetCloudUid, shared.KEYS.FRIENDS, {
                        userId = requesterUid,
                        nickname = requesterProfile.nickname,
                        avatar = NormalizeAvatar(requesterProfile.avatar),
                        score = requesterProfile.score or 0,
                        addedAt = now,
                        time = now,
                    })
                    targetCommit:Commit({
                        ok = function()
                            CommitRequesterAccept(targetProfile)
                        end,
                        error = function(_, reason)
                            SendFailure("处理好友申请失败: " .. tostring(reason))
                        end,
                    })
                end
                if accepted == true then
                    IsFriend(targetCloudUid, requesterUid, function(alreadyFriend)
                        if alreadyFriend == true then
                            GetNicknameMap({ targetUid, requesterUid }, function(nickMap)
                                CommitResponse(nil, nil, true, nickMap)
                            end)
                            return
                        end
                        CheckBothFriendLimits(targetCloudUid, requesterCloudUid, function(limitOk, limitMessage)
                            if limitOk ~= true then
                                Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = limitMessage or "好友数量已达上限", requestId = requestId })
                                return
                            end
                            GetNicknameMap({ targetUid, requesterUid }, function(nickMap)
                                FetchGardenProfiles({ targetUid, requesterUid }, function(profileMap)
                                    CommitResponse(profileMap[targetUid], profileMap[requesterUid], false, nickMap)
                                end)
                            end)
                        end)
                    end)
                else
                    CommitResponse(nil, nil, false)
                end
            end
            ServerCloudStore.ListGet(requesterCloudUid, shared.KEYS.FRIEND_REQUESTS, {
                ok = function(requesterRequestRows)
                    ContinueWithRequesterRequests(requesterRequestRows)
                end,
                error = function()
                    ContinueWithRequesterRequests({})
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请读取失败: " .. tostring(reason), requestId = requestId })
        end,
    })
end

local function DeleteRowsFromList(commit, rows)
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        local listId = NormalizeListId(row.list_id or row.listId or (type(value) == "table" and (value.listId or value.giftId) or nil))
        if listId ~= nil then commit:ListDelete(listId) end
    end
end

function SocialServer.RemoveFriend(uid, friendUserId, connection, requestId, requestRecordKey)
    local shared = Shared()
    local selfUid = NormalizeUserId(uid)
    local targetUid = NormalizeUserId(friendUserId)
    local selfCloudUid = CloudUid(selfUid)
    local targetCloudUid = CloudUid(targetUid)
    if selfUid == nil or targetUid == nil then
        Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "好友 ID 无效", requestId = requestId, friendUserId = friendUserId })
        return
    end
    ServerCloudStore.ListGet(selfCloudUid, shared.KEYS.FRIENDS, {
        ok = function(selfRows)
            local selfDeletes = {}
            for _, row in ipairs(selfRows or {}) do
                local value = row.value or row
                if type(value) == "table" and SameUserId(value.userId or value.friendUserId, targetUid) then
                    selfDeletes[#selfDeletes + 1] = row
                end
            end
            if #selfDeletes == 0 then
                Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "好友不存在", requestId = requestId, friendUserId = targetUid })
                return
            end
            ServerCloudStore.ListGet(targetCloudUid, shared.KEYS.FRIENDS, {
                ok = function(targetRows)
                    local targetDeletes = {}
                    for _, row in ipairs(targetRows or {}) do
                        local value = row.value or row
                        if type(value) == "table" and SameUserId(value.userId or value.friendUserId, selfUid) then
                            targetDeletes[#targetDeletes + 1] = row
                        end
                    end
                    local response = { success = true, message = "已删除好友", requestId = requestId, friendUserId = targetUid }
                    CommitListDeletesSequential("删除好友", {
                        { label = "自己", rows = selfDeletes },
                        { label = "对方", rows = targetDeletes },
                    }, function(cleaned)
                        if cleaned ~= true then
                            Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "删除好友失败", requestId = requestId, friendUserId = targetUid })
                            return
                        end
                        if requestRecordKey ~= nil then deps_.RequestGuard.Record(uid, requestRecordKey, response) end
                        Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, response)
                    end)
                end,
                error = function(_, reason)
                    Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "好友数据读取失败: " .. tostring(reason), requestId = requestId, friendUserId = targetUid })
                end,
            })
        end,
        error = function(_, reason)
            Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "好友数据读取失败: " .. tostring(reason), requestId = requestId, friendUserId = targetUid })
        end,
    })
end

local function IsValidSeedGiftRow(row)
    local value = row and (row.value or row) or nil
    if type(value) ~= "table" then return false end
    if NormalizeListId(row.list_id or row.listId or value.listId or value.giftId) == nil then return false end
    local seedId = tonumber(value.seedId)
    if seedId == nil or math.floor(seedId) ~= seedId then return false end
    if deps_.normalizePlantIndex ~= nil and deps_.normalizePlantIndex(seedId) == nil then return false end
    local count = math.floor(tonumber(value.count or 1) or 1)
    return count >= 1
end

local function CollectInvalidGiftRows(uid, rows, done)
    local invalid = {}
    local index = 1
    local function Step()
        if index > #(rows or {}) then
            done(invalid)
            return
        end
        local row = rows[index]
        index = index + 1
        if not IsValidSeedGiftRow(row) then
            invalid[#invalid + 1] = row
            Step()
            return
        end
        local value = row.value or row
        local giftId = NormalizeListId(row.list_id or row.listId or value.listId or value.giftId)
        ServerCloudStore.ListGet(uid, "claimed_gift_" .. tostring(giftId), {
            ok = function(claimRows)
                if claimRows ~= nil and #claimRows > 0 then
                    invalid[#invalid + 1] = row
                end
                Step()
            end,
            error = function()
                Step()
            end,
        })
    end
    Step()
end

function SocialServer.ClearSocialMessages(uid, connection, requestId, requestRecordKey)
    local shared = Shared()
    FetchFriends(uid, function(friends)
        FetchFriendRequests(uid, friends, function(friendRequests)
            ServerCloudStore.ListGet(uid, shared.KEYS.RECENT_VISITORS, {
                ok = function(visitorRows)
                    ServerCloudStore.ListGet(uid, shared.KEYS.STEAL_LOGS, {
                        ok = function(stealRows)
                            ServerCloudStore.ListGet(uid, shared.KEYS.SOCIAL_NOTICES, {
                                ok = function(noticeRows)
                                    ServerCloudStore.ListGet(uid, shared.KEYS.SEED_REWARDS, {
                                        ok = function(giftRows)
                                            CollectInvalidGiftRows(uid, giftRows, function(invalidGiftRows)
                                                local response = { success = true, message = "消息已清除", requestId = requestId, friendRequests = friendRequests }
                                                local c = serverCloud:BatchCommit("清除社交消息")
                                                DeleteRowsFromList(c, visitorRows)
                                                DeleteRowsFromList(c, stealRows)
                                                DeleteRowsFromList(c, noticeRows)
                                                DeleteRowsFromList(c, invalidGiftRows)
                                                if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response) end
                                                c:Commit({
                                                    ok = function()
                                                        Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, response)
                                                    end,
                                                    error = function(_, reason)
                                                        Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "消息清除失败: " .. tostring(reason), requestId = requestId })
                                                    end,
                                                })
                                            end)
                                        end,
                                        error = function(_, reason)
                                            Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "礼物消息读取失败: " .. tostring(reason), requestId = requestId })
                                        end,
                                    })
                                end,
                                error = function(_, reason)
                                    Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "消息读取失败: " .. tostring(reason), requestId = requestId })
                                end,
                            })
                        end,
                        error = function(_, reason)
                            Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "偷菜消息读取失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    Send(connection, shared.EVENTS.CLEAR_SOCIAL_MESSAGES_RESPONSE, { success = false, message = "拜访消息读取失败: " .. tostring(reason), requestId = requestId })
                end,
            })
        end)
    end)
end

return SocialServer
