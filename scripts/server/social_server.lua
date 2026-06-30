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

local function NormalizeUserId(userId)
    if deps_.normalizeUserId ~= nil then return deps_.normalizeUserId(userId) end
    if userId == nil or userId == 0 or userId == "" then return nil end
    local text = tostring(userId)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "0" then return nil end
    local integerText = string.match(text, "^(%-?%d+)%.0+$")
    if integerText ~= nil then return integerText end
    local numericId = tonumber(text)
    if numericId ~= nil and numericId == math.floor(numericId) and math.abs(numericId) < 9007199254740992 then
        return string.format("%.0f", numericId)
    end
    return text
end

local function BuildUidKeyCandidates(uid)
    if deps_.buildUidKeyCandidates ~= nil then return deps_.buildUidKeyCandidates(uid) end
    return { uid }
end

local function GetCanonicalUidKey(uid)
    if deps_.getCanonicalUidKey ~= nil then return deps_.getCanonicalUidKey(uid) end
    return NormalizeUserId(uid) or uid
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

local function GetNicknameMap(userIds, done)
    local map = {}
    local clean = {}
    local seen = {}
    for _, uid in ipairs(userIds or {}) do
        local normalized = NormalizeUserId(uid)
        if normalized ~= nil and not seen[normalized] then
            seen[normalized] = true
            clean[#clean + 1] = normalized
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
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1
    local fallbackRows = nil
    local fallbackKey = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done(fallbackRows or {}, fallbackKey)
            return
        end
        serverCloud.list:Get(key, listKey, {
            ok = function(rows)
                if rows ~= nil and #rows > 0 then
                    done(rows, key)
                    return
                end
                fallbackRows = fallbackRows or rows
                fallbackKey = fallbackKey or key
                readNext()
            end,
            error = function()
                readNext()
            end,
        })
    end

    readNext()
end

local function ReadQuotaFromUidCandidates(uid, quotaKey, done)
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done({})
            return
        end
        serverCloud.quota:Get(key, quotaKey, {
            ok = function(rows)
                if rows ~= nil and #rows > 0 then
                    done(rows, key)
                    return
                end
                readNext()
            end,
            error = function()
                readNext()
            end,
        })
    end

    readNext()
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

local function NormalizeFriendRows(rows)
    local result = {}
    local seen = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
            local userId = NormalizeUserId(value.userId or value.friendUserId)
            if userId ~= nil and not seen[userId] then
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

local function NormalizeFriendRequestRows(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" and (value.status == nil or value.status == "pending") then
            result[#result + 1] = {
                listId = row.list_id or row.listId or value.listId,
                requestId = row.list_id or row.listId or value.requestId,
                fromUserId = NormalizeUserId(value.fromUserId),
                fromNickname = value.fromNickname,
                avatar = NormalizeAvatar(value.avatar),
                targetUserId = NormalizeUserId(value.targetUserId),
                sentAt = value.sentAt or value.time,
                time = value.time or value.sentAt,
                status = "pending",
            }
        end
    end
    table.sort(result, function(a, b)
        return tonumber(a.sentAt or a.time or 0) > tonumber(b.sentAt or b.time or 0)
    end)
    return result
end

local function NormalizeNoticeRows(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
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
    ReadListFromUidCandidates(uid, Shared().KEYS.FRIENDS, function(rows) done(NormalizeFriendRows(rows)) end)
end

local function FetchFriendRequests(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.FRIEND_REQUESTS, function(rows) done(NormalizeFriendRequestRows(rows)) end)
end

local function FetchSocialNotices(uid, done)
    ReadListFromUidCandidates(uid, Shared().KEYS.SOCIAL_NOTICES, function(rows) done(NormalizeNoticeRows(rows)) end)
end

local function ReadScoreFromUidCandidates(uid, scoreKey, done)
    local canonicalUid = GetCanonicalUidKey(uid)
    local candidates = BuildUidKeyCandidates(uid)
    local index = 1
    local fallbackError = nil

    local function readNext()
        local key = candidates[index]
        index = index + 1
        if key == nil then
            done(nil, canonicalUid, fallbackError)
            return
        end
        serverCloud:Get(key, scoreKey, {
            ok = function(scores)
                local value = scores and scores[scoreKey]
                if type(value) == "table" then
                    done(value, key, nil)
                    return
                end
                readNext()
            end,
            error = function(_, reason)
                fallbackError = reason
                readNext()
            end,
        })
    end

    readNext()
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
        local cloudUid = tonumber(userId) or userId
        ReadScoreFromUidCandidates(cloudUid, Shared().KEYS.GARDEN_SNAPSHOT, function(garden)
            if type(garden) == "table" then
                profiles[userId] = {
                    nickname = garden.nickname,
                    avatar = NormalizeAvatar(garden.avatar),
                    score = garden.tourValue or 0,
                }
            end
            nextOne()
        end)
    end
    nextOne()
end

local function BuildLikeRecordKey(targetUid)
    return "liked_garden_" .. tostring(targetUid)
end

local function SaveCanonicalGardenSnapshot(uid, snapshot, farmState, connection, saveLabel)
    local shared = Shared()
    local saveUid = GetCanonicalUidKey(uid)
    local canonical = deps_.buildVisitGardenFromAuthFarm(saveUid, snapshot.nickname, farmState, snapshot)
    canonical.nickname = snapshot.nickname or canonical.nickname
    canonical.avatar = NormalizeAvatar(snapshot.avatar or canonical.avatar)
    canonical.unlockedPlotCount = math.max(1, tonumber(snapshot.unlockedPlotCount or canonical.unlockedPlotCount or 1) or 1)
    local score = math.max(0, math.floor(tonumber(canonical.tourValue or 0) or 0))
    serverCloud:BatchSet(saveUid)
        :Set(shared.KEYS.GARDEN_SNAPSHOT, canonical)
        :Set(shared.KEYS.SOCIAL_SAVE, {
            visitablePlotIndex = canonical.visitablePlotIndex,
            updatedAt = Now(),
        })
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

    ReadScoreFromUidCandidates(uid, shared.KEYS.AUTH_FARM_STATE, function(farmState)
        SaveCanonicalGardenSnapshot(uid, snapshot, farmState, connection, farmState ~= nil and "保存权威社交花园" or "首次保存权威社交花园")
    end)
end

function SocialServer.RequestGardenSnapshot(requesterUid, targetUid, connection, requestId, requestRecordKey)
    local shared = Shared()
    local function SendGardenResponse(response)
        response.requestId = requestId
        if requestRecordKey ~= nil and response.success == true then
            deps_.RequestGuard.Record(requesterUid, requestRecordKey, response)
        end
        Send(connection, shared.EVENTS.GARDEN_RESPONSE, response)
    end
    if targetUid == nil or targetUid <= 0 then
        SendGardenResponse({ success = false, message = "玩家 ID 无效" })
        return
    end

    local function SendGardenWithLikes(resolvedGarden)
        local function SendWithLikedState()
            if requesterUid ~= nil and tostring(requesterUid) ~= tostring(targetUid) then
                serverCloud.list:Get(requesterUid, BuildLikeRecordKey(targetUid), {
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
                resolvedGarden.likedByMe = tostring(requesterUid) == tostring(targetUid)
                SendGardenResponse({ success = true, garden = resolvedGarden })
            end
        end
        serverCloud:Get(targetUid, shared.KEYS.LIKE_COUNT, {
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
        if requesterUid == nil or tostring(requesterUid) == tostring(targetUid) then
            if done then done() end
            return
        end
        local profile = type(visitorProfile) == "table" and visitorProfile or {}
        local visitKey = BuildVisitRecordKey(requesterUid)
        serverCloud.list:Get(targetUid, shared.KEYS.RECENT_VISITORS, {
            ok = function(rows)
                local c = serverCloud:BatchCommit("记录花园拜访")
                for _, row in ipairs(rows or {}) do
                    local value = row.value or row
                    if type(value) == "table" and (value.visitKey == visitKey or SameUserId(value.userId, requesterUid)) then
                        local listId = row.list_id or row.listId or value.listId
                        if listId ~= nil then c:ListDelete(listId) end
                    end
                end
                local now = Now()
                c:ListAdd(targetUid, shared.KEYS.RECENT_VISITORS, {
                    userId = requesterUid,
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

    ReadScoreFromUidCandidates(targetUid, shared.KEYS.GARDEN_SNAPSHOT, function(garden)
        if type(garden) == "table" and garden.plot ~= nil then
            RefreshRuntimeSnapshot(garden)
        else
            garden = { nickname = "Tap玩家", visitablePlotIndex = 1, unlockedPlotCount = 1 }
        end
        GetNicknameMap({ requesterUid }, function(nickMap)
            FetchGardenProfiles({ requesterUid }, function(profileMap)
                local profile = profileMap[tostring(requesterUid)] or {}
                local visitorProfile = {
                    nickname = profile.nickname or nickMap[requesterUid] or nickMap[tostring(requesterUid)] or "Tap玩家",
                    avatar = profile.avatar,
                }
                RecordVisit(visitorProfile, function()
                    ReadScoreFromUidCandidates(targetUid, shared.KEYS.AUTH_FARM_STATE, function(farmState, farmKey, farmError)
                        if type(farmState) == "table" then
                            if farmKey ~= GetCanonicalUidKey(targetUid) then
                                print(string.format("[存档兼容] 拜访花园使用历史权威农场 key=%s target=%s", tostring(farmKey), tostring(targetUid)))
                            end
                            local authGarden = deps_.buildVisitGardenFromAuthFarm(targetUid, garden.nickname, farmState, garden)
                            SendGardenWithLikes(authGarden)
                        elseif garden.plot ~= nil then
                            SendGardenWithLikes(garden)
                        else
                            SendGardenResponse({ success = false, message = "读取花园失败: " .. tostring(farmError or "该玩家尚未开放花园") })
                        end
                    end)
                end)
            end)
        end)
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

function SocialServer.RequestSocialState(uid, connection)
    local shared = Shared()

    local function ContinueWithSocialSave(socialSave)
        socialSave = type(socialSave) == "table" and socialSave or { visitablePlotIndex = 1 }
        FetchStealLogs(uid, function(stealLogs)
            FetchRecentVisitors(uid, function(recentVisitors)
                FetchFriends(uid, function(friends)
                    FetchFriendRequests(uid, function(friendRequests)
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
                                        if notice.fromUserId ~= nil then userIds[#userIds + 1] = notice.fromUserId end
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
                                                local profile = profileMap[tostring(entry.userId)] or {}
                                                entry.nickname = profile.nickname or nickMap[entry.userId] or nickMap[tostring(entry.userId)] or entry.nickname or "Tap玩家"
                                                entry.avatar = profile.avatar or entry.avatar
                                                entry.score = profile.score or entry.score or 0
                                            end
                                            for _, entry in ipairs(recommended) do
                                                local profile = profileMap[tostring(entry.userId)] or {}
                                                entry.nickname = profile.nickname or nickMap[entry.userId] or nickMap[tostring(entry.userId)] or "Tap玩家"
                                                entry.avatar = profile.avatar or entry.avatar
                                                entry.score = profile.score or entry.score or 0
                                            end
                                            for _, request in ipairs(friendRequests) do
                                                local profile = profileMap[tostring(request.fromUserId)] or {}
                                                request.fromNickname = profile.nickname or nickMap[request.fromUserId] or nickMap[tostring(request.fromUserId)] or request.fromNickname or "Tap玩家"
                                                request.avatar = profile.avatar or request.avatar
                                            end
                                            for _, notice in ipairs(socialNotices) do
                                                local profile = profileMap[tostring(notice.fromUserId)] or {}
                                                notice.fromNickname = profile.nickname or nickMap[notice.fromUserId] or nickMap[tostring(notice.fromUserId)] or notice.fromNickname or "Tap玩家"
                                                notice.avatar = profile.avatar or notice.avatar
                                            end
                                            for _, row in ipairs(stealLogs) do
                                                local profile = profileMap[tostring(row.thiefUserId)] or {}
                                                row.thiefNickname = profile.nickname or nickMap[row.thiefUserId] or nickMap[tostring(row.thiefUserId)] or "Tap玩家"
                                                row.avatar = profile.avatar or row.avatar
                                            end
                                            for _, row in ipairs(recentVisitors) do
                                                local profile = profileMap[tostring(row.userId)] or {}
                                                row.nickname = profile.nickname or nickMap[row.userId] or nickMap[tostring(row.userId)] or row.nickname or "Tap玩家"
                                                row.avatar = profile.avatar or row.avatar
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
                                                        recommendedPlayers = recommended,
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
        if sourceKey ~= nil and sourceKey ~= canonicalUid then
            print(string.format("[存档兼容] 社交存档命中历史 uid key=%s，迁移到当前 key=%s", tostring(sourceKey), tostring(canonicalUid)))
            serverCloud:Set(canonicalUid, shared.KEYS.SOCIAL_SAVE, socialSave)
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
                    ok = function(scores, iscores)
                        local likeScores = iscores or scores or {}
                        local response = {
                            success = false,
                            alreadyLiked = true,
                            message = "已经点赞过这个花园了",
                            targetUserId = targetUid,
                            requestId = requestId,
                            likeCount = tonumber(likeScores[shared.KEYS.LIKE_COUNT] or 0) or 0,
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
    return SameUserId(value.fromUserId, fromUid) and SameUserId(value.targetUserId, targetUid)
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
        local listId = row.list_id or row.listId
        if listId ~= nil then commit:ListDelete(listId) end
    end
end

local function IsFriend(uid, targetUid, done)
    serverCloud.list:Get(uid, Shared().KEYS.FRIENDS, {
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

function SocialServer.SendFriendRequest(uid, targetUid, connection, requestId, requestRecordKey, profile)
    local shared = Shared()
    profile = type(profile) == "table" and profile or {}
    local fromUid = NormalizeUserId(uid)
    local toUid = NormalizeUserId(targetUid)
    local fromCloudUid = tonumber(fromUid or "") or uid
    local toCloudUid = tonumber(toUid or "") or targetUid
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
        serverCloud.list:Get(toCloudUid, shared.KEYS.FRIEND_REQUESTS, {
            ok = function(targetRequestRows)
                if HasPendingRequest(targetRequestRows, fromUid, toUid) then
                    Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请已发送，等待对方处理", requestId = requestId })
                    return
                end
                if HasPendingRequest(targetRequestRows, toUid, fromUid) then
                    Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "对方已向你发送好友申请，请先处理", requestId = requestId })
                    return
                end
                serverCloud.list:Get(fromCloudUid, shared.KEYS.FRIEND_REQUESTS, {
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
                        local request = {
                            fromUserId = fromUid,
                            fromNickname = profile.nickname,
                            avatar = NormalizeAvatar(profile.avatar),
                            targetUserId = toUid,
                            status = "pending",
                            sentAt = now,
                            time = now,
                        }
                        local response = { success = true, message = "好友申请已发送", requestId = requestId, targetUserId = toUid }
                        local c = serverCloud:BatchCommit("发送好友申请")
                        c:ListAdd(toCloudUid, shared.KEYS.FRIEND_REQUESTS, request)
                        c:ListAdd(fromCloudUid, shared.KEYS.SOCIAL_NOTICES, {
                            type = "friend_request_sent",
                            targetUserId = toUid,
                            fromUserId = toUid,
                            time = now,
                        })
                        if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response) end
                        c:Commit({
                            ok = function()
                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, response)
                            end,
                            error = function(_, reason)
                                Send(connection, shared.EVENTS.SEND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请发送失败: " .. tostring(reason), requestId = requestId })
                            end,
                        })
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
end

function SocialServer.RespondFriendRequest(uid, friendRequestId, fromUserId, accepted, connection, requestId, requestRecordKey)
    local shared = Shared()
    local targetUid = NormalizeUserId(uid)
    local requesterUid = NormalizeUserId(fromUserId)
    local targetCloudUid = tonumber(targetUid or "") or uid
    local requesterCloudUid = tonumber(requesterUid or "") or fromUserId
    if targetUid == nil or requesterUid == nil then
        Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "好友申请无效", requestId = requestId })
        return
    end
    serverCloud.list:Get(targetCloudUid, shared.KEYS.FRIEND_REQUESTS, {
        ok = function(rows)
            local requestRow = nil
            local listId = friendRequestId
            for _, row in ipairs(rows or {}) do
                local value = row.value or row
                local rowId = row.list_id or row.listId or value.listId
                if (friendRequestId ~= nil and tostring(rowId) == tostring(friendRequestId)) or SameUserId(value.fromUserId, requesterUid) then
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
            local response = { success = true, requestId = requestId, accepted = accepted == true }
            local targetRequestDeletes = CollectPendingRequestDeletes(rows, requesterUid, targetUid)
            local function ContinueWithRequesterRequests(requesterRequestRows)
                local requesterRequestDeletes = CollectPendingRequestDeletes(requesterRequestRows, requesterUid, targetUid)
                local function CommitResponse(targetProfile, requesterProfile, alreadyFriend)
                    targetProfile = targetProfile or {}
                    requesterProfile = requesterProfile or {}
                    requesterProfile.nickname = requesterProfile.nickname or requestRow.fromNickname
                    requesterProfile.avatar = NormalizeAvatar(requesterProfile.avatar or requestRow.avatar)
                    local c = serverCloud:BatchCommit(accepted and "同意好友申请" or "拒绝好友申请")
                    AddDeleteRowsToCommit(c, targetRequestDeletes)
                    AddDeleteRowsToCommit(c, requesterRequestDeletes)
                    if accepted == true then
                        if alreadyFriend == true then
                            response.message = "已是好友，申请已清理"
                        else
                            c:ListAdd(targetCloudUid, shared.KEYS.FRIENDS, {
                                userId = requesterUid,
                                nickname = requesterProfile.nickname,
                                avatar = NormalizeAvatar(requesterProfile.avatar),
                                score = requesterProfile.score or 0,
                                addedAt = now,
                                time = now,
                            })
                            c:ListAdd(requesterCloudUid, shared.KEYS.FRIENDS, {
                                userId = targetUid,
                                nickname = targetProfile.nickname,
                                avatar = NormalizeAvatar(targetProfile.avatar),
                                score = targetProfile.score or 0,
                                addedAt = now,
                                time = now,
                            })
                            c:ListAdd(requesterCloudUid, shared.KEYS.SOCIAL_NOTICES, { type = "friend_request_accepted", fromUserId = targetUid, time = now })
                            response.message = "已添加好友"
                        end
                    else
                        c:ListAdd(requesterCloudUid, shared.KEYS.SOCIAL_NOTICES, { type = "friend_request_rejected", fromUserId = targetUid, time = now })
                        response.message = "已拒绝好友申请"
                    end
                    if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response) end
                    c:Commit({
                        ok = function()
                            Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, shared.EVENTS.RESPOND_FRIEND_REQUEST_RESPONSE, { success = false, message = "处理好友申请失败: " .. tostring(reason), requestId = requestId })
                        end,
                    })
                end
                if accepted == true then
                    IsFriend(targetCloudUid, requesterUid, function(alreadyFriend)
                        if alreadyFriend == true then
                            CommitResponse(nil, nil, true)
                            return
                        end
                        FetchGardenProfiles({ targetUid, requesterUid }, function(profileMap)
                            CommitResponse(profileMap[targetUid], profileMap[requesterUid], false)
                        end)
                    end)
                else
                    CommitResponse(nil, nil, false)
                end
            end
            serverCloud.list:Get(requesterCloudUid, shared.KEYS.FRIEND_REQUESTS, {
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
    local selfCloudUid = tonumber(selfUid or "") or uid
    local targetCloudUid = tonumber(targetUid or "") or friendUserId
    if selfUid == nil or targetUid == nil then
        Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "好友 ID 无效", requestId = requestId, friendUserId = friendUserId })
        return
    end
    serverCloud.list:Get(selfCloudUid, shared.KEYS.FRIENDS, {
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
            serverCloud.list:Get(targetCloudUid, shared.KEYS.FRIENDS, {
                ok = function(targetRows)
                    local c = serverCloud:BatchCommit("删除好友")
                    DeleteRowsFromList(c, selfDeletes)
                    local targetDeletes = {}
                    for _, row in ipairs(targetRows or {}) do
                        local value = row.value or row
                        if type(value) == "table" and SameUserId(value.userId or value.friendUserId, selfUid) then
                            targetDeletes[#targetDeletes + 1] = row
                        end
                    end
                    DeleteRowsFromList(c, targetDeletes)
                    local response = { success = true, message = "已删除好友", requestId = requestId, friendUserId = targetUid }
                    if requestRecordKey ~= nil then deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response) end
                    c:Commit({
                        ok = function()
                            Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, response)
                        end,
                        error = function(_, reason)
                            Send(connection, shared.EVENTS.REMOVE_FRIEND_RESPONSE, { success = false, message = "删除好友失败: " .. tostring(reason), requestId = requestId, friendUserId = targetUid })
                        end,
                    })
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
        serverCloud.list:Get(uid, "claimed_gift_" .. tostring(giftId), {
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
    FetchFriendRequests(uid, function(friendRequests)
        serverCloud.list:Get(uid, shared.KEYS.RECENT_VISITORS, {
            ok = function(visitorRows)
                serverCloud.list:Get(uid, shared.KEYS.STEAL_LOGS, {
                    ok = function(stealRows)
                        serverCloud.list:Get(uid, shared.KEYS.SOCIAL_NOTICES, {
                            ok = function(noticeRows)
                                serverCloud.list:Get(uid, shared.KEYS.SEED_REWARDS, {
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
end

return SocialServer
