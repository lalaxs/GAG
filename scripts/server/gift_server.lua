-- ============================================================================
-- 礼物服务端模块
-- ============================================================================
-- 处理种子礼物发送、列表读取、领取与领取幂等。
-- ============================================================================

local GiftServer = {}

local deps_ = {}

local function Now()
    return os and os.time and os.time() or 0
end

local function NormalizeUserId(userId)
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

local function Send(connection, eventName, data)
    deps_.Shared.SendToClient(connection, eventName, data)
end

local function SendError(connection, eventName, code, message, extra)
    local data = extra or {}
    data.success = false
    data.code = code
    data.message = message
    Send(connection, eventName, data)
end

local function NormalizePositiveCount(value, maxValue)
    local count = math.floor(tonumber(value or 1) or 1)
    if count < 1 then count = 1 end
    if maxValue ~= nil then count = math.min(count, maxValue) end
    return count
end

local function GetSeedName(seedId)
    if deps_.getSeedName ~= nil then
        return deps_.getSeedName(seedId)
    end
    return "种子"
end

local function BuildReward(seedId, count)
    seedId = deps_.normalizePlantIndex(seedId)
    count = NormalizePositiveCount(count or 1)
    if seedId == nil then return nil end
    return {
        type = "seed",
        seedId = seedId,
        count = count,
        name = GetSeedName(seedId),
        description = GetSeedName(seedId) .. "种子 x" .. tostring(count),
    }
end

local function BuildGiftClaimRecordKey(giftId)
    return "claimed_gift_" .. tostring(giftId or "unknown")
end

local function BuildGiftTargetRecordKey(targetUid, day)
    return "gift_sent_target_" .. tostring(day or "unknown") .. "_" .. tostring(targetUid or "unknown")
end

local function SameUserId(left, right)
    local leftId = NormalizeUserId(left)
    local rightId = NormalizeUserId(right)
    return leftId ~= nil and rightId ~= nil and leftId == rightId
end

local function CheckFriendship(uid, targetUid, done)
    serverCloud.list:Get(uid, deps_.Shared.KEYS.FRIENDS, {
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

local function PickRandomGiftSeedId()
    if deps_.pickGiftSeedId ~= nil then
        return deps_.pickGiftSeedId()
    end
    return deps_.normalizePlantIndex(1)
end

local function DayKey(time)
    return os and os.date and os.date("%Y%m%d", time or Now()) or "unknown"
end

local function NormalizeGiftRows(rows)
    local gifts = {}
    for _, row in ipairs(rows or {}) do
        local value = row.value or row
        if type(value) == "table" then
            gifts[#gifts + 1] = {
                giftId = row.list_id or row.listId or value.giftId,
                listId = row.list_id or row.listId or value.listId,
                fromUserId = value.fromUserId,
                fromNickname = value.fromNickname,
                seedId = value.seedId,
                count = value.count or 1,
                reward = value.reward or BuildReward(value.seedId, value.count or 1),
                sentAt = value.sentAt or value.time,
                claimed = false,
            }
        end
    end
    table.sort(gifts, function(a, b)
        return tonumber(a.sentAt or 0) > tonumber(b.sentAt or 0)
    end)
    return gifts
end

function GiftServer.Init(deps)
    deps_ = deps or {}
end

function GiftServer.SendSeedGift(uid, targetUid, _seedId, count, connection, requestId, requestRecordKey, profile)
    local Shared = deps_.Shared
    profile = type(profile) == "table" and profile or {}
    targetUid = tonumber(targetUid or 0) or 0
    local seedId = PickRandomGiftSeedId()
    count = NormalizePositiveCount(count, deps_.maxGiftCount)
    if targetUid <= 0 then
        SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "INVALID_TARGET", "好友玩家 ID 无效", { requestId = requestId })
        return
    end
    if seedId == nil then
        SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "INVALID_PLANT", "种子配置不存在", { requestId = requestId })
        return
    end
    if tostring(uid) == tostring(targetUid) then
        SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "SELF_GIFT", "不能给自己赠送种子", { requestId = requestId })
        return
    end

    local now = Now()
    local today = DayKey(now)
    local giftTargetRecordKey = BuildGiftTargetRecordKey(targetUid, today)
    CheckFriendship(uid, targetUid, function(isFriend)
        if isFriend ~= true then
            SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "NOT_FRIEND", "只能给好友赠送种子", { requestId = requestId, targetUserId = targetUid })
            return
        end
        serverCloud.list:Get(uid, giftTargetRecordKey, {
            ok = function(targetRows)
                if targetRows ~= nil and #targetRows > 0 then
                    SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "GIFT_ALREADY_SENT", "今天已经给这位好友送过礼了", { requestId = requestId, targetUserId = targetUid })
                    return
                end
                serverCloud.list:Get(uid, Shared.KEYS.GIFT_SENT_TARGETS, {
                    ok = function(rows)
                        for _, row in ipairs(rows or {}) do
                            local value = row.value or row
                            if type(value) == "table" and tostring(value.targetUserId) == tostring(targetUid) and tostring(value.day or today) == today then
                                SendError(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, "GIFT_ALREADY_SENT", "今天已经给这位好友送过礼了", { requestId = requestId, targetUserId = targetUid })
                                return
                            end
                        end
                        local gift = {
                            fromUserId = uid,
                            fromNickname = profile.nickname,
                            seedId = seedId,
                            count = count,
                            reward = BuildReward(seedId, count),
                            sentAt = now,
                            time = now,
                        }
                        local response = {
                            success = true,
                            message = "种子已送给好友",
                            requestId = requestId,
                            targetUserId = targetUid,
                            daily = { giftSentDelta = 1, limit = deps_.dailyGiftLimit },
                        }
                        local sentRecord = { targetUserId = targetUid, seedId = seedId, time = now, day = today }
                        local c = serverCloud:BatchCommit("发送种子礼物")
                        c:ListAdd(targetUid, Shared.KEYS.SEED_REWARDS, gift)
                        c:ListAdd(uid, giftTargetRecordKey, sentRecord)
                        c:ListAdd(uid, Shared.KEYS.GIFT_SENT_TARGETS, sentRecord)
                        c:QuotaAdd(uid, "daily_seed_gift", 1, deps_.dailyGiftLimit, "day", 1)
                        deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                        c:Commit({
                            ok = function()
                                serverCloud.quota:Get(uid, "daily_seed_gift", {
                                    ok = function(quotaRows)
                                        local row = quotaRows and quotaRows[1]
                                        response.daily.giftSentCount = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                                        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, response)
                                    end,
                                    error = function()
                                        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, response)
                                    end,
                                })
                            end,
                            error = function(_, reason)
                                Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "赠送失败: " .. tostring(reason), requestId = requestId, targetUserId = targetUid })
                            end,
                        })
                    end,
                    error = function(_, reason)
                        Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "赠送记录读取失败: " .. tostring(reason), requestId = requestId, targetUserId = targetUid })
                    end,
                })
            end,
            error = function(_, reason)
                Send(connection, Shared.EVENTS.SEND_SEED_GIFT_RESPONSE, { success = false, message = "赠送记录读取失败: " .. tostring(reason), requestId = requestId, targetUserId = targetUid })
            end,
        })
    end)
end

function GiftServer.RequestGifts(uid, connection)
    local Shared = deps_.Shared
    serverCloud.list:Get(uid, Shared.KEYS.SEED_REWARDS, {
        ok = function(rows)
            local gifts = NormalizeGiftRows(rows)
            local userIds = {}
            for _, gift in ipairs(gifts) do
                userIds[#userIds + 1] = gift.fromUserId
            end
            GetNicknameMap(userIds, function(nickMap)
                for _, gift in ipairs(gifts) do
                    local normalized = NormalizeUserId(gift.fromUserId)
                    gift.fromNickname = gift.fromNickname or nickMap[normalized] or nickMap[gift.fromUserId] or nickMap[tostring(gift.fromUserId)] or "Tap玩家"
                end
                Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = true, gifts = gifts })
            end)
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = false, message = "礼物读取失败: " .. tostring(reason) })
        end,
    })
end

function GiftServer.ClaimGift(uid, giftId, fallbackSeedId, fallbackCount, connection, requestId, requestRecordKey)
    local Shared = deps_.Shared
    if giftId == nil or giftId == "" then
        SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "INVALID_GIFT", "礼物不存在", { requestId = requestId, giftId = giftId })
        return
    end
    local claimRecordKey = BuildGiftClaimRecordKey(giftId)
    serverCloud.list:Get(uid, claimRecordKey, {
        ok = function(claimRows)
            if claimRows ~= nil and #claimRows > 0 then
                local record = claimRows[1].value or claimRows[1]
                local response = {
                    success = true,
                    alreadyClaimed = true,
                    message = "礼物已领取",
                    requestId = requestId,
                    giftId = giftId,
                    gift = record and record.reward or nil,
                }
                deps_.RequestGuard.Record(uid, requestRecordKey, response)
                Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, response)
                return
            end
            serverCloud.list:Get(uid, Shared.KEYS.SEED_REWARDS, {
                ok = function(rows)
                    local found = nil
                    local listId = nil
                    for _, row in ipairs(rows or {}) do
                        local rowId = row.list_id or row.listId
                        if tostring(rowId) == tostring(giftId) then
                            found = row.value or row
                            listId = rowId
                            break
                        end
                    end
                    if found == nil or listId == nil then
                        SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "GIFT_NOT_FOUND", "礼物不存在或已领取", { requestId = requestId, giftId = giftId })
                        return
                    end
                    local seedId = deps_.normalizePlantIndex(found.seedId)
                    local count = NormalizePositiveCount(found.count or 1)
                    if seedId == nil then
                        SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "INVALID_GIFT_CONTENT", "礼物内容无效", { requestId = requestId, giftId = giftId })
                        return
                    end
                    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                        ok = function(scores)
                            local state = deps_.normalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or deps_.buildInitialEconomyState())
                            local owned = tonumber(state.seedBag[seedId] or 0) or 0
                            state.seedBag[seedId] = owned + count
                            state.updatedAt = Now()
                            deps_.nextRevision(state)
                            local reward = BuildReward(seedId, count)
                            local response = { success = true, message = "已领取" .. reward.description, requestId = requestId, giftId = giftId, gift = reward, state = state }
                            local c = serverCloud:BatchCommit("领取种子礼物")
                            c:QuotaAdd(uid, claimRecordKey, 1, 1)
                            c:ScoreSet(uid, Shared.KEYS.ECONOMY_STATE, state)
                            c:ListAdd(uid, claimRecordKey, { giftId = giftId, reward = reward, claimedAt = Now() })
                            c:ListDelete(listId)
                            deps_.RequestGuard.AddToCommit(c, uid, requestRecordKey, response)
                            c:Commit({
                                ok = function()
                                    Send(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, response)
                                end,
                                error = function(_, reason)
                                    print("[礼物] 领取提交失败: " .. tostring(reason))
                                    SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "CLAIM_GIFT_FAILED", "领取失败", { requestId = requestId })
                                end,
                            })
                        end,
                        error = function(_, reason)
                            print("[礼物] 经济数据读取失败: " .. tostring(reason))
                            SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "ECONOMY_READ_FAILED", "网络异常，请稍后重试", { requestId = requestId })
                        end,
                    })
                end,
                error = function(_, reason)
                    print("[礼物] 礼物读取失败: " .. tostring(reason))
                    SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "GIFT_READ_FAILED", "礼物读取失败", { requestId = requestId })
                end,
            })
        end,
        error = function(_, reason)
            print("[礼物] 领取记录读取失败: " .. tostring(reason))
            SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "CLAIM_RECORD_READ_FAILED", "网络异常，请稍后重试", { requestId = requestId })
        end,
    })
end

return GiftServer
