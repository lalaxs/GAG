-- ============================================================================
-- 服务端奖励与成长系统
-- Grow A Garden
-- ============================================================================
-- 奖励/成长经济写入统一修改 PlayerStateService 内存状态。
-- ============================================================================

local ServerRewards = {}

local deps_ = {}
local ServerConfig = require("config.server_tuning")
local ServerCloudStore = require("server.server_cloud_store")

local TALENT_LEVEL_EXP_TABLE = ServerConfig.Talent.LEVEL_EXP_TABLE
local TALENT_MAX_LEVEL = ServerConfig.Talent.MAX_LEVEL
local RARITY_BASE_EXP = ServerConfig.Talent.RARITY_BASE_EXP
local TALENT_CONFIG = ServerConfig.Talent.CONFIG
local DAILY_REWARD_PACK_WEIGHTS = ServerConfig.DailyReward.PACK_WEIGHTS
local SYNTHESIS_MAP = ServerConfig.DailyReward.SYNTHESIS_MAP

ServerRewards.TALENT_MAX_LEVEL = TALENT_MAX_LEVEL

function ServerRewards.Init(deps)
    deps_ = deps or {}
end

local function CloudUid(uid)
    return ServerCloudStore.CloudPlayerId(uid) or ServerCloudStore.CanonicalUid(uid)
end

local function Now()
    return deps_.Now()
end

local function Send(connection, eventName, data)
    deps_.Send(connection, eventName, data)
end

local function NormalizeTalentState(talent)
    return deps_.NormalizeTalentState(talent)
end

local function NormalizeProgressionState(progression)
    return deps_.NormalizeProgressionState(progression)
end

local function NormalizeDailyTaskState(daily)
    return deps_.NormalizeDailyTaskState(daily)
end

local function GetFarmPlot(state, plotIndex)
    return deps_.GetFarmPlot(state, plotIndex)
end

local function SyncProgressionTourValueFromFarm(state, farmState)
    return deps_.SyncProgressionTourValueFromFarm(state, farmState)
end

local function RollWeighted(pool)
    return deps_.RollWeighted(pool)
end

local function NormalizePlotIndex(value)
    return deps_.NormalizePlotIndex(value)
end

local function RecordResponse(uid, key, response)
    if deps_.RequestGuard ~= nil and deps_.RequestGuard.Record ~= nil then
        deps_.RequestGuard.Record(uid, key, response)
    end
end

local function SendMutationResult(connection, eventName, result, requestId)
    if type(result) == "table" and type(result.response) == "table" then
        Send(connection, eventName, result.response)
        return
    end
    Send(connection, eventName, {
        success = false,
        message = type(result) == "table" and result.message or "同步失败",
        retryable = type(result) == "table" and result.retryable == true,
        requestId = requestId,
    })
end

local function CommitTourRank(uid, state)
    local c = serverCloud:BatchCommit("观光排行更新")
    deps_.AddTourRankCommit(c, uid, state)
    c:Commit({ ok = function() end, error = function(_, reason) print("[奖励] 观光排行更新失败: " .. tostring(reason)) end })
end

function ServerRewards.FindTalentConfig(talentId)
    for _, talent in ipairs(TALENT_CONFIG) do
        if talent.id == talentId then return talent end
    end
    return nil
end

function ServerRewards.GetLevelUpTalentPoints(level)
    return level >= 16 and 2 or 1
end

function ServerRewards.AddServerHarvestExp(state, rarity, priceMultiplier)
    state.talent = NormalizeTalentState(state.talent)
    local talent = state.talent
    if talent.level >= TALENT_MAX_LEVEL then return 0 end
    local baseExp = RARITY_BASE_EXP[rarity] or 5
    local exp = math.max(1, math.floor(baseExp * math.min(priceMultiplier or 1.0, 5.0) + 0.5))
    talent.exp = talent.exp + exp
    while talent.level < TALENT_MAX_LEVEL do
        local needed = TALENT_LEVEL_EXP_TABLE[talent.level]
        if needed == nil or talent.exp < needed then break end
        talent.exp = talent.exp - needed
        talent.level = talent.level + 1
        talent.talentPoints = talent.talentPoints + ServerRewards.GetLevelUpTalentPoints(talent.level)
    end
    if talent.level >= TALENT_MAX_LEVEL then talent.exp = 0 end
    state.progression = NormalizeProgressionState(state.progression)
    state.progression.gardenLevel = math.max(state.progression.gardenLevel or 1, talent.level)
    return exp
end

function ServerRewards.BuildExpansionRequirement(plotIndex)
    local requirements = deps_.GameConfig.CONFIG and deps_.GameConfig.CONFIG.LAND_UNLOCK_REQUIREMENTS or nil
    if requirements ~= nil and requirements[plotIndex] ~= nil then
        return requirements[plotIndex]
    end
    local sightReq = deps_.GameConfig.CONFIG and deps_.GameConfig.CONFIG.LAND_UNLOCK_SIGHT_REQUIREMENTS or nil
    local tableReq = {
        [2] = { level = 2, gold = 600, tour = sightReq and sightReq[2] or 180 }, [3] = { level = 4, gold = 2200, tour = sightReq and sightReq[3] or 550 },
        [4] = { level = 6, gold = 7500, tour = sightReq and sightReq[4] or 1300 }, [5] = { level = 9, gold = 25000, tour = sightReq and sightReq[5] or 3000 },
        [6] = { level = 12, gold = 85000, tour = sightReq and sightReq[6] or 6500 }, [7] = { level = 16, gold = 260000, tour = sightReq and sightReq[7] or 13000 },
        [8] = { level = 21, gold = 780000, tour = sightReq and sightReq[8] or 25000 }, [9] = { level = 26, gold = 2200000, tour = sightReq and sightReq[9] or 45000 },
    }
    return tableReq[plotIndex] or { level = math.max(1, plotIndex), gold = 3000 * plotIndex * plotIndex, tour = 600 * plotIndex * plotIndex }
end

function ServerRewards.MatureAllCropsInPlot(farmState, plotIndex)
    local plot = GetFarmPlot(farmState, plotIndex)
    local changed = 0
    local now = Now()
    for _, crop in ipairs(plot.plants or {}) do
        if crop.harvested ~= true and crop.mature ~= true then
            crop.elapsed = math.max(tonumber(crop.growTime or 1) or 1, 1)
            crop.mature = true
            crop.matureAt = now
            crop.stealable = crop.stolen ~= true
            changed = changed + 1
        end
    end
    return changed
end

function ServerRewards.GrantAdReward(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local rewardType = tostring(payload.rewardType or "")
    if rewardType == "steal_attempts" then
        ServerCloudStore.QuotaGet(uid, "daily_steal_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= deps_.dailyStealAdLimit then
                    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日偷取次数广告已达上限", requestId = payload.requestId, rewardType = rewardType, daily = { stealAdCount = watched, stealAdLimit = deps_.dailyStealAdLimit } })
                    return
                end
                local response = { success = true, message = "偷取次数 +" .. tostring(deps_.adStealBonus), requestId = payload.requestId, rewardType = rewardType, daily = { stealAdCount = watched + 1, stealAdLimit = deps_.dailyStealAdLimit, limit = deps_.dailyStealLimit + (watched + 1) * deps_.adStealBonus } }
                local c = serverCloud:BatchCommit("广告奖励：偷取次数")
                c:QuotaAdd(uid, "daily_steal_ad", 1, deps_.dailyStealAdLimit, "day", 1)
                c:QuotaAdd(uid, "daily_steal_ad_bonus", deps_.adStealBonus, deps_.dailyStealAdLimit * deps_.adStealBonus, "day", 1)
                deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                c:Commit({ ok = function() Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, response); deps_.SocialServer.RequestSocialState(uid, connection) end, error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "奖励发放失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end })
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "rare_seed_pack" then
        ServerCloudStore.QuotaGet(uid, "daily_seed_pack_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= deps_.dailySeedPackAdLimit then
                    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日广告种子包已领取完", requestId = payload.requestId, rewardType = rewardType, daily = { seedPackAdCount = watched, seedPackAdLimit = deps_.dailySeedPackAdLimit } })
                    return
                end
                deps_.PlayerStateService.MutateEconomy(uid, "ad_rare_seed_pack", function(state)
                    state.seedPacks.pack_rare = (tonumber(state.seedPacks.pack_rare or 0) or 0) + deps_.adRarePackCount
                    return { success = true, response = { success = true, message = "获得稀有种子包 x" .. tostring(deps_.adRarePackCount), requestId = payload.requestId, rewardType = rewardType, state = state, rewards = { { packId = "pack_rare", count = deps_.adRarePackCount } }, daily = { seedPackAdCount = watched + 1, seedPackAdLimit = deps_.dailySeedPackAdLimit } } }
                end, function(result)
                    if result ~= nil and result.success == true and type(result.response) == "table" then
                        local c = serverCloud:BatchCommit("广告次数：稀有种子包")
                        c:QuotaAdd(uid, "daily_seed_pack_ad", 1, deps_.dailySeedPackAdLimit, "day", 1)
                        deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, result.response)
                        c:Commit({ ok = function() end, error = function(_, reason) print("[奖励] 广告次数保存失败: " .. tostring(reason)) end })
                        deps_.SocialServer.RequestSocialState(uid, connection)
                    end
                    SendMutationResult(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, result, payload.requestId)
                end)
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "mature_plot" then
        local plotIndex = NormalizePlotIndex(payload.plotIndex)
        ServerCloudStore.QuotaGet(uid, "daily_mature_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= deps_.dailyMatureAdLimit then
                    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日快速成熟广告已达上限", requestId = payload.requestId, rewardType = rewardType, daily = { matureAdCount = watched, matureAdLimit = deps_.dailyMatureAdLimit } })
                    return
                end
                deps_.PlayerStateService.MutateEconomyAndFarm(uid, "ad_mature_plot", function(state, farmState)
                    local changed = ServerRewards.MatureAllCropsInPlot(farmState, plotIndex)
                    if changed <= 0 then
                        return { success = false, response = { success = false, message = "该地块没有可加速成熟的作物", requestId = payload.requestId, rewardType = rewardType, farm = farmState, state = state, daily = { matureAdCount = watched, matureAdLimit = deps_.dailyMatureAdLimit } } }
                    end
                    SyncProgressionTourValueFromFarm(state, farmState)
                    return { success = true, response = { success = true, message = "地块作物已全部成熟", requestId = payload.requestId, rewardType = rewardType, plotIndex = plotIndex, maturedCount = changed, farm = farmState, state = state, daily = { matureAdCount = watched + 1, matureAdLimit = deps_.dailyMatureAdLimit } } }
                end, function(result)
                    if result ~= nil and result.success == true and type(result.response) == "table" then
                        local c = serverCloud:BatchCommit("广告次数：快速成熟")
                        c:QuotaAdd(uid, "daily_mature_ad", 1, deps_.dailyMatureAdLimit, "day", 1)
                        deps_.AddTourRankCommit(c, uid, result.response.state)
                        deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, result.response)
                        c:Commit({ ok = function() end, error = function(_, reason) print("[奖励] 快速成熟附加提交失败: " .. tostring(reason)) end })
                    end
                    SendMutationResult(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, result, payload.requestId)
                end)
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告奖励类型无效", requestId = payload.requestId, rewardType = rewardType })
end

function ServerRewards.ClaimDailyRewardAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    deps_.PlayerStateService.MutateEconomy(uid, "claim_daily_reward", function(state)
        local daily = NormalizeDailyTaskState(state.dailyTaskState)
        local completed = (daily.progress.plant or 0) >= 3 and (daily.progress.harvest or 0) >= 3 and (daily.progress.sell or 0) >= 1
        if not completed or daily.rewardClaimed then
            return { success = false, response = { success = false, message = daily.rewardClaimed and "今日奖励已领取" or "每日任务未完成", requestId = payload.requestId, state = state } }
        end
        daily.rewardClaimed = true
        local rewards = {}
        for _ = 1, 3 do
            local picked = RollWeighted(DAILY_REWARD_PACK_WEIGHTS)
            state.seedPacks[picked.packId] = (tonumber(state.seedPacks[picked.packId] or 0) or 0) + 1
            rewards[#rewards + 1] = picked.packId
        end
        state.dailyTaskState = daily
        return { success = true, response = { success = true, message = "每日奖励已领取", requestId = payload.requestId, rewards = rewards, state = state } }
    end, function(result)
        SendMutationResult(connection, deps_.Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, result, payload.requestId)
    end)
end

function ServerRewards.SynthesizePackAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local packId = tostring(payload.packId or "")
    local targetId = SYNTHESIS_MAP[packId]
    local requestedCount = math.max(1, math.floor(tonumber(payload.count or 1) or 1))
    if targetId == nil then
        Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "该种子包不可合成", requestId = payload.requestId })
        return
    end
    deps_.PlayerStateService.MutateEconomy(uid, "synthesize_pack", function(state)
        local owned = tonumber(state.seedPacks[packId] or 0) or 0
        local synthCount = math.min(requestedCount, math.floor(owned / 3))
        if synthCount <= 0 then
            return { success = false, response = { success = false, message = "需要 3 个同品级种子包", requestId = payload.requestId, state = state } }
        end
        state.seedPacks[packId] = owned - synthCount * 3
        state.seedPacks[targetId] = (tonumber(state.seedPacks[targetId] or 0) or 0) + synthCount
        return { success = true, response = { success = true, message = "合成成功 x" .. synthCount, requestId = payload.requestId, packId = packId, targetId = targetId, count = synthCount, state = state } }
    end, function(result)
        SendMutationResult(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, result, payload.requestId)
    end)
end

function ServerRewards.UnlockTalentAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    local talentId = tostring(payload.talentId or "")
    local talentCfg = ServerRewards.FindTalentConfig(talentId)
    if talentCfg == nil then
        Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋不存在", requestId = payload.requestId })
        return
    end
    deps_.PlayerStateService.MutateEconomy(uid, "unlock_talent", function(state)
        local talent = NormalizeTalentState(state.talent)
        if talent.unlockedTalents[talentId] == true then return { success = false, response = { success = false, message = "天赋已解锁", requestId = payload.requestId, state = state } } end
        if talentCfg.requires ~= nil and talent.unlockedTalents[talentCfg.requires] ~= true then return { success = false, response = { success = false, message = "需要先解锁前置天赋", requestId = payload.requestId, state = state } } end
        if talent.talentPoints < talentCfg.cost then return { success = false, response = { success = false, message = "天赋点不足", requestId = payload.requestId, state = state } } end
        if state.gold < (talentCfg.goldCost or 0) then return { success = false, response = { success = false, message = "金币不足", requestId = payload.requestId, state = state } } end
        talent.talentPoints = talent.talentPoints - talentCfg.cost
        talent.unlockedTalents[talentId] = true
        state.gold = state.gold - (talentCfg.goldCost or 0)
        state.talent = talent
        return { success = true, response = { success = true, message = "天赋已解锁", requestId = payload.requestId, talentId = talentId, state = state } }
    end, function(result)
        SendMutationResult(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, result, payload.requestId)
    end)
end

function ServerRewards.ExpandPlotAuthority(uid, payload, connection)
    uid = CloudUid(uid)
    payload = payload or {}
    deps_.PlayerStateService.MutateEconomyAndFarm(uid, "expand_plot", function(state, farmState)
        local progression = NormalizeProgressionState(state.progression)
        local maxPlots = (deps_.GameConfig.CONFIG.GridCols or 1) * (deps_.GameConfig.CONFIG.GridRows or 1)
        if progression.unlockedPlotCount >= maxPlots then return { success = false, response = { success = false, message = "已扩展到最大地块", requestId = payload.requestId, state = state } } end
        local nextPlot = progression.unlockedPlotCount + 1
        local requirement = ServerRewards.BuildExpansionRequirement(nextPlot)
        if (state.talent.level or 1) < requirement.level then return { success = false, response = { success = false, message = "等级不足", requestId = payload.requestId, state = state } } end
        if state.gold < requirement.gold then return { success = false, response = { success = false, message = "金币不足", requestId = payload.requestId, state = state } } end
        SyncProgressionTourValueFromFarm(state, farmState)
        progression = NormalizeProgressionState(state.progression)
        if (progression.bestTourValue or progression.currentTourValue or 0) < requirement.tour then return { success = false, response = { success = false, message = "观光值不足", requestId = payload.requestId, state = state } } end
        state.gold = state.gold - requirement.gold
        progression.unlockedPlotCount = nextPlot
        progression.gardenLevel = math.max(progression.gardenLevel or 1, nextPlot)
        state.progression = progression
        GetFarmPlot(farmState, nextPlot)
        return { success = true, response = { success = true, message = "扩地成功", requestId = payload.requestId, plotIndex = nextPlot, state = state, farm = farmState } }
    end, function(result)
        if result ~= nil and result.success == true and type(result.response) == "table" then
            CommitTourRank(uid, result.response.state)
        end
        SendMutationResult(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, result, payload.requestId)
    end)
end

return ServerRewards
