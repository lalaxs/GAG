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

local function BuildGiftClaimRecordKey(giftId)
    return "claimed_gift_" .. tostring(giftId or "unknown")
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
                seedId = value.seedId,
                count = value.count or 1,
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

function GiftServer.SendSeedGift(uid, targetUid, seedId, count, connection, requestId, requestRecordKey)
    local Shared = deps_.Shared
    targetUid = tonumber(targetUid or 0) or 0
    seedId = deps_.normalizePlantIndex(seedId)
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
                seedId = seedId,
                count = count,
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
            local c = serverCloud:BatchCommit("发送种子礼物")
            c:ListAdd(targetUid, Shared.KEYS.SEED_REWARDS, gift)
            c:ListAdd(uid, Shared.KEYS.GIFT_SENT_TARGETS, { targetUserId = targetUid, seedId = seedId, time = now, day = today })
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
end

function GiftServer.RequestGifts(uid, connection)
    local Shared = deps_.Shared
    serverCloud.list:Get(uid, Shared.KEYS.SEED_REWARDS, {
        ok = function(rows)
            Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = true, gifts = NormalizeGiftRows(rows) })
        end,
        error = function(_, reason)
            Send(connection, Shared.EVENTS.GIFTS_RESPONSE, { success = false, message = "礼物读取失败: " .. tostring(reason) })
        end,
    })
end

function GiftServer.ClaimGift(uid, giftId, _seedId, _count, connection, requestId, requestRecordKey)
    local Shared = deps_.Shared
    if giftId == nil or giftId == "" then
        SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "INVALID_GIFT", "礼物不存在", { requestId = requestId, giftId = giftId })
        return
    end
    local claimRecordKey = BuildGiftClaimRecordKey(giftId)
    serverCloud.list:Get(uid, claimRecordKey, {
        ok = function(claimRows)
            if claimRows ~= nil and #claimRows > 0 then
                SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "GIFT_ALREADY_CLAIMED", "礼物已领取", { requestId = requestId, giftId = giftId })
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
                    local count = NormalizePositiveCount(found.count or 1, deps_.seedStackMax)
                    if seedId == nil then
                        SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "INVALID_GIFT_CONTENT", "礼物内容无效", { requestId = requestId, giftId = giftId })
                        return
                    end
                    serverCloud:Get(uid, Shared.KEYS.ECONOMY_STATE, {
                        ok = function(scores)
                            local state = deps_.normalizeEconomyState(scores[Shared.KEYS.ECONOMY_STATE] or deps_.buildInitialEconomyState())
                            local owned = tonumber(state.seedBag[seedId] or 0) or 0
                            if owned + count > deps_.seedStackMax then
                                SendError(connection, Shared.EVENTS.CLAIM_GIFT_RESPONSE, "SEED_STACK_FULL", "种子背包空间不足", { requestId = requestId, state = state })
                                return
                            end
                            state.seedBag[seedId] = owned + count
                            state.updatedAt = Now()
                            deps_.nextRevision(state)
                            local reward = { type = "seed", seedId = seedId, count = count }
                            local response = { success = true, message = "好友种子已领取", requestId = requestId, gift = reward, state = state }
                            local c = serverCloud:BatchCommit("领取种子礼物")
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
