-- ============================================================================
-- 服务端奖励与成长系统
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的经验成长、广告奖励、每日奖励、种子包合成、天赋解锁和扩地逻辑。
-- ============================================================================

local ServerRewards = {}

local deps_ = {}

local TALENT_LEVEL_EXP_TABLE = {
    [1]  = 30, [2]  = 50, [3]  = 80, [4]  = 120, [5]  = 170,
    [6]  = 230, [7]  = 300, [8]  = 380, [9]  = 470, [10] = 570,
    [11] = 680, [12] = 800, [13] = 940, [14] = 1100, [15] = 1280,
    [16] = 1480, [17] = 1700, [18] = 1950, [19] = 2230, [20] = 2550,
    [21] = 2900, [22] = 3280, [23] = 3700, [24] = 4160, [25] = 4660,
    [26] = 5200, [27] = 5780, [28] = 6400, [29] = 7060,
}
local TALENT_MAX_LEVEL = 30
local RARITY_BASE_EXP = { ["普通"] = 5, ["罕见"] = 10, ["稀有"] = 18, ["史诗"] = 30, ["传奇"] = 50 }
local TALENT_CONFIG = {
    { id = "drop_rate_1", cost = 1, goldCost = 500, requires = nil }, { id = "drop_rate_2", cost = 1, goldCost = 2000, requires = "drop_rate_1" }, { id = "drop_rate_3", cost = 2, goldCost = 8000, requires = "drop_rate_2" }, { id = "drop_rate_4", cost = 2, goldCost = 30000, requires = "drop_rate_3" }, { id = "drop_rate_5", cost = 3, goldCost = 100000, requires = "drop_rate_4" },
    { id = "grow_speed_1", cost = 1, goldCost = 800, requires = nil }, { id = "grow_speed_2", cost = 1, goldCost = 3000, requires = "grow_speed_1" }, { id = "grow_speed_3", cost = 2, goldCost = 12000, requires = "grow_speed_2" }, { id = "grow_speed_4", cost = 2, goldCost = 50000, requires = "grow_speed_3" }, { id = "grow_speed_5", cost = 3, goldCost = 160000, requires = "grow_speed_4" },
    { id = "sell_bonus_1", cost = 1, goldCost = 1000, requires = nil }, { id = "sell_bonus_2", cost = 1, goldCost = 4000, requires = "sell_bonus_1" }, { id = "sell_bonus_3", cost = 2, goldCost = 16000, requires = "sell_bonus_2" }, { id = "sell_bonus_4", cost = 2, goldCost = 70000, requires = "sell_bonus_3" }, { id = "sell_bonus_5", cost = 3, goldCost = 220000, requires = "sell_bonus_4" },
    { id = "mutation_1", cost = 1, goldCost = 1200, requires = nil }, { id = "mutation_2", cost = 1, goldCost = 5000, requires = "mutation_1" }, { id = "mutation_3", cost = 2, goldCost = 20000, requires = "mutation_2" }, { id = "mutation_4", cost = 2, goldCost = 90000, requires = "mutation_3" }, { id = "mutation_5", cost = 3, goldCost = 300000, requires = "mutation_4" },
    { id = "bag_capacity_1", cost = 1, goldCost = 600, requires = nil }, { id = "bag_capacity_2", cost = 1, goldCost = 2500, requires = "bag_capacity_1" }, { id = "bag_capacity_3", cost = 2, goldCost = 10000, requires = "bag_capacity_2" }, { id = "bag_capacity_4", cost = 2, goldCost = 40000, requires = "bag_capacity_3" }, { id = "bag_capacity_5", cost = 3, goldCost = 120000, requires = "bag_capacity_4" },
}
local DAILY_REWARD_PACK_WEIGHTS = {
    { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 32 },
    { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 9 },
    { packId = "pack_legendary", weight = 2 },
}
local SYNTHESIS_MAP = { pack_common = "pack_uncommon", pack_uncommon = "pack_rare", pack_rare = "pack_epic", pack_epic = "pack_legendary" }

ServerRewards.TALENT_MAX_LEVEL = TALENT_MAX_LEVEL

function ServerRewards.Init(deps)
    deps_ = deps or {}
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

local function NormalizeEconomyState(state)
    return deps_.NormalizeEconomyState(state)
end

local function NormalizeFarmState(state)
    return deps_.NormalizeFarmState(state)
end

local function BuildInitialEconomyState()
    return deps_.BuildInitialEconomyState()
end

local function GetFarmPlot(state, plotIndex)
    return deps_.GetFarmPlot(state, plotIndex)
end

local function SyncProgressionTourValueFromFarm(state, farmState)
    return deps_.SyncProgressionTourValueFromFarm(state, farmState)
end

local function AddTourRankCommit(commit, uid, state)
    deps_.AddTourRankCommit(commit, uid, state)
end

local function NextRevision(state)
    deps_.NextRevision(state)
end

local function RollWeighted(pool)
    return deps_.RollWeighted(pool)
end

local function NormalizePlotIndex(value)
    return deps_.NormalizePlotIndex(value)
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
    payload = payload or {}
    local rewardType = tostring(payload.rewardType or "")
    if rewardType == "steal_attempts" then
        serverCloud.quota:Get(uid, "daily_steal_ad", {
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
                c:Commit({
                    ok = function() Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, response); deps_.SocialServer.RequestSocialState(uid, connection) end,
                    error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "奖励发放失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "rare_seed_pack" then
        serverCloud.quota:Get(uid, "daily_seed_pack_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= deps_.dailySeedPackAdLimit then
                    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日广告种子包已领取完", requestId = payload.requestId, rewardType = rewardType, daily = { seedPackAdCount = watched, seedPackAdLimit = deps_.dailySeedPackAdLimit } })
                    return
                end
                serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
                    ok = function(scores)
                        local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                        state.seedPacks.pack_rare = (tonumber(state.seedPacks.pack_rare or 0) or 0) + deps_.adRarePackCount
                        state.updatedAt = Now()
                        NextRevision(state)
                        local response = { success = true, message = "获得稀有种子包 x" .. tostring(deps_.adRarePackCount), requestId = payload.requestId, rewardType = rewardType, state = state, rewards = { { packId = "pack_rare", count = deps_.adRarePackCount } }, daily = { seedPackAdCount = watched + 1, seedPackAdLimit = deps_.dailySeedPackAdLimit } }
                        local c = serverCloud:BatchCommit("广告奖励：稀有种子包")
                        c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                        c:QuotaAdd(uid, "daily_seed_pack_ad", 1, deps_.dailySeedPackAdLimit, "day", 1)
                        deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                        c:Commit({
                            ok = function() Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, response); deps_.SocialServer.RequestSocialState(uid, connection) end,
                            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "奖励发放失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, state = state }) end,
                        })
                    end,
                    error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    if rewardType == "mature_plot" then
        local plotIndex = NormalizePlotIndex(payload.plotIndex)
        serverCloud.quota:Get(uid, "daily_mature_ad", {
            ok = function(rows)
                local row = rows and rows[1]
                local watched = math.max(0, math.floor(tonumber(row and row.value or 0) or 0))
                if watched >= deps_.dailyMatureAdLimit then
                    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, code = "AD_LIMIT_REACHED", message = "今日快速成熟广告已达上限", requestId = payload.requestId, rewardType = rewardType, daily = { matureAdCount = watched, matureAdLimit = deps_.dailyMatureAdLimit } })
                    return
                end
                serverCloud:Get(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
                    ok = function(farmScores)
                        local farmState = NormalizeFarmState(farmScores[deps_.Shared.KEYS.AUTH_FARM_STATE])
                        local changed = ServerRewards.MatureAllCropsInPlot(farmState, plotIndex)
                        if changed <= 0 then
                            Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "该地块没有可加速成熟的作物", requestId = payload.requestId, rewardType = rewardType, farm = farmState, daily = { matureAdCount = watched, matureAdLimit = deps_.dailyMatureAdLimit } })
                            return
                        end
                        serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
                            ok = function(scores)
                                local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
                                SyncProgressionTourValueFromFarm(state, farmState)
                                farmState.updatedAt = Now()
                                NextRevision(farmState)
                                state.updatedAt = Now()
                                NextRevision(state)
                                local response = { success = true, message = "地块作物已全部成熟", requestId = payload.requestId, rewardType = rewardType, plotIndex = plotIndex, maturedCount = changed, farm = farmState, state = state, daily = { matureAdCount = watched + 1, matureAdLimit = deps_.dailyMatureAdLimit } }
                                local c = serverCloud:BatchCommit("广告奖励：快速成熟")
                                c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                                c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                                c:QuotaAdd(uid, "daily_mature_ad", 1, deps_.dailyMatureAdLimit, "day", 1)
                                AddTourRankCommit(c, uid, state)
                                deps_.RequestGuard.AddToCommit(c, uid, payload._requestRecordKey, response)
                                c:Commit({
                                    ok = function() Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, response) end,
                                    error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "快速成熟失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, farm = farmState }) end,
                                })
                            end,
                            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType, farm = farmState }) end,
                        })
                    end,
                    error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "读取农场失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
                })
            end,
            error = function(_, reason) Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告次数读取失败: " .. tostring(reason), requestId = payload.requestId, rewardType = rewardType }) end,
        })
        return
    end

    Send(connection, deps_.Shared.EVENTS.AD_REWARD_RESPONSE, { success = false, message = "广告奖励类型无效", requestId = payload.requestId, rewardType = rewardType })
end

function ServerRewards.ClaimDailyRewardAuthority(uid, payload, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local daily = NormalizeDailyTaskState(state.dailyTaskState)
            local completed = (daily.progress.plant or 0) >= 3 and (daily.progress.harvest or 0) >= 3 and (daily.progress.sell or 0) >= 1
            if not completed or daily.rewardClaimed then
                Send(connection, deps_.Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = daily.rewardClaimed and "今日奖励已领取" or "每日任务未完成", requestId = payload.requestId, state = state })
                return
            end
            daily.rewardClaimed = true
            local rewards = {}
            for _ = 1, 3 do
                local picked = RollWeighted(DAILY_REWARD_PACK_WEIGHTS)
                state.seedPacks[picked.packId] = (tonumber(state.seedPacks[picked.packId] or 0) or 0) + 1
                rewards[#rewards + 1] = picked.packId
            end
            state.dailyTaskState = daily
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "每日奖励已领取", requestId = payload.requestId, rewards = rewards, state = state }
            serverCloud:Set(uid, deps_.Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, deps_.Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = "领取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.CLAIM_DAILY_REWARD_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

function ServerRewards.SynthesizePackAuthority(uid, payload, connection)
    local packId = tostring(payload.packId or "")
    local targetId = SYNTHESIS_MAP[packId]
    local requestedCount = math.max(1, math.floor(tonumber(payload.count or 1) or 1))
    if targetId == nil then
        Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "该种子包不可合成", requestId = payload.requestId })
        return
    end
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local owned = tonumber(state.seedPacks[packId] or 0) or 0
            local maxCount = math.floor(owned / 3)
            local synthCount = math.min(requestedCount, maxCount)
            if synthCount <= 0 then
                Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "需要 3 个同品级种子包", requestId = payload.requestId, state = state })
                return
            end
            local consumeCount = synthCount * 3
            state.seedPacks[packId] = owned - consumeCount
            state.seedPacks[targetId] = (tonumber(state.seedPacks[targetId] or 0) or 0) + synthCount
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "合成成功 x" .. synthCount, requestId = payload.requestId, packId = packId, targetId = targetId, count = synthCount, state = state }
            serverCloud:Set(uid, deps_.Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "合成失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.SYNTHESIZE_PACK_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

function ServerRewards.UnlockTalentAuthority(uid, payload, connection)
    local talentId = tostring(payload.talentId or "")
    local talentCfg = ServerRewards.FindTalentConfig(talentId)
    if talentCfg == nil then
        Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋不存在", requestId = payload.requestId })
        return
    end
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local talent = NormalizeTalentState(state.talent)
            if talent.unlockedTalents[talentId] == true then
                Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋已解锁", requestId = payload.requestId, state = state })
                return
            end
            if talentCfg.requires ~= nil and talent.unlockedTalents[talentCfg.requires] ~= true then
                Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "需要先解锁前置天赋", requestId = payload.requestId, state = state })
                return
            end
            if talent.talentPoints < talentCfg.cost then
                Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "天赋点不足", requestId = payload.requestId, state = state })
                return
            end
            if state.gold < (talentCfg.goldCost or 0) then
                Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "金币不足", requestId = payload.requestId, state = state })
                return
            end
            talent.talentPoints = talent.talentPoints - talentCfg.cost
            talent.unlockedTalents[talentId] = true
            state.gold = state.gold - (talentCfg.goldCost or 0)
            state.talent = talent
            state.updatedAt = Now()
            NextRevision(state)
            local response = { success = true, message = "天赋已解锁", requestId = payload.requestId, talentId = talentId, state = state }
            serverCloud:Set(uid, deps_.Shared.KEYS.ECONOMY_STATE, state, {
                ok = function() Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, response) end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "解锁失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.UNLOCK_TALENT_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

function ServerRewards.ExpandPlotAuthority(uid, payload, connection)
    serverCloud:Get(uid, deps_.Shared.KEYS.ECONOMY_STATE, {
        ok = function(scores)
            local state = NormalizeEconomyState(scores[deps_.Shared.KEYS.ECONOMY_STATE] or BuildInitialEconomyState())
            local progression = NormalizeProgressionState(state.progression)
            local maxPlots = (deps_.GameConfig.CONFIG.GridCols or 1) * (deps_.GameConfig.CONFIG.GridRows or 1)
            if progression.unlockedPlotCount >= maxPlots then
                Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "已扩展到最大地块", requestId = payload.requestId, state = state })
                return
            end
            local nextPlot = progression.unlockedPlotCount + 1
            local requirement = ServerRewards.BuildExpansionRequirement(nextPlot)
            if (state.talent.level or 1) < requirement.level then
                Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "等级不足", requestId = payload.requestId, state = state })
                return
            end
            if state.gold < requirement.gold then
                Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "金币不足", requestId = payload.requestId, state = state })
                return
            end
            serverCloud:Get(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, {
                ok = function(farmScores)
                    local farmState = NormalizeFarmState(farmScores[deps_.Shared.KEYS.AUTH_FARM_STATE])
                    SyncProgressionTourValueFromFarm(state, farmState)
                    progression = NormalizeProgressionState(state.progression)
                    if (progression.bestTourValue or progression.currentTourValue or 0) < requirement.tour then
                        Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "观光值不足", requestId = payload.requestId, state = state })
                        return
                    end
                    state.gold = state.gold - requirement.gold
                    progression.unlockedPlotCount = nextPlot
                    progression.gardenLevel = math.max(progression.gardenLevel or 1, nextPlot)
                    state.progression = progression
                    state.updatedAt = Now()
                    NextRevision(state)
                    GetFarmPlot(farmState, nextPlot)
                    farmState.updatedAt = Now()
                    NextRevision(farmState)
                    local response = { success = true, message = "扩地成功", requestId = payload.requestId, plotIndex = nextPlot, state = state, farm = farmState }
                    local c = serverCloud:BatchCommit("权威扩地")
                    c:ScoreSet(uid, deps_.Shared.KEYS.ECONOMY_STATE, state)
                    AddTourRankCommit(c, uid, state)
                    c:ScoreSet(uid, deps_.Shared.KEYS.AUTH_FARM_STATE, farmState)
                    c:Commit({
                        ok = function() Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, response) end,
                        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "扩地失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
                    })
                end,
                error = function(_, reason) Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "农场数据读取失败: " .. tostring(reason), requestId = payload.requestId, state = state }) end,
            })
        end,
        error = function(_, reason) Send(connection, deps_.Shared.EVENTS.EXPAND_PLOT_RESPONSE, { success = false, message = "经济数据读取失败: " .. tostring(reason), requestId = payload.requestId }) end,
    })
end

return ServerRewards
