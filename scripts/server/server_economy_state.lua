-- ============================================================================
-- 服务端经济状态
-- Grow A Garden
-- ============================================================================
-- 从 server_main.lua 拆出的经济/天赋/成长/每日任务/活动状态归一化与排行榜提交逻辑。
-- ============================================================================

local ServerEconomyState = {}

local deps_ = {}

function ServerEconomyState.Init(deps)
    deps_ = deps or {}
end

local function Now()
    return deps_.Now()
end

local function CopyNumericKeyMap(source)
    return deps_.CopyNumericKeyMap(source)
end

local function RecalculateAuthoritativeItemPrice(item)
    deps_.RecalculateAuthoritativeItemPrice(item)
end

local function CalculateAuthFarmTourValue(farmState)
    return deps_.CalculateAuthFarmTourValue(farmState)
end

local function GetActivityRankInfo(activityId, cycleInfo)
    return deps_.GetActivityRankInfo(activityId, cycleInfo)
end

local function GetIncomeRankInfo(now)
    return deps_.GetIncomeRankInfo(now)
end

function ServerEconomyState.NormalizeTalentState(talent)
    talent = type(talent) == "table" and talent or {}
    talent.unlockedTalents = type(talent.unlockedTalents) == "table" and talent.unlockedTalents or {}
    talent.talentPoints = math.max(0, math.floor(tonumber(talent.talentPoints or 1) or 1))
    talent.level = Clamp(math.floor(tonumber(talent.level or 1) or 1), 1, deps_.talentMaxLevel)
    talent.exp = math.max(0, math.floor(tonumber(talent.exp or 0) or 0))
    return talent
end

function ServerEconomyState.NormalizeProgressionState(progression)
    progression = type(progression) == "table" and progression or {}
    progression.unlockedPlotCount = Clamp(math.floor(tonumber(progression.unlockedPlotCount or 1) or 1), 1, (deps_.GameConfig.CONFIG.GridCols or 1) * (deps_.GameConfig.CONFIG.GridRows or 1))
    progression.gardenLevel = math.max(1, math.floor(tonumber(progression.gardenLevel or progression.unlockedPlotCount) or progression.unlockedPlotCount))
    progression.currentTourValue = math.max(0, math.floor(tonumber(progression.currentTourValue or 0) or 0))
    progression.bestTourValue = math.max(tonumber(progression.bestTourValue or 0) or 0, progression.currentTourValue)
    return progression
end

function ServerEconomyState.NormalizeDailyTaskState(daily)
    daily = type(daily) == "table" and daily or {}
    daily.progress = type(daily.progress) == "table" and daily.progress or { plant = 0, harvest = 0, sell = 0 }
    daily.progress.plant = math.max(0, math.floor(tonumber(daily.progress.plant or 0) or 0))
    daily.progress.harvest = math.max(0, math.floor(tonumber(daily.progress.harvest or 0) or 0))
    daily.progress.sell = math.max(0, math.floor(tonumber(daily.progress.sell or 0) or 0))
    daily.rewardClaimed = daily.rewardClaimed == true
    return daily
end

function ServerEconomyState.NewActivityState(cycleInfo)
    cycleInfo = cycleInfo or (deps_.GameConfig.GetActivityCycleInfo and deps_.GameConfig.GetActivityCycleInfo(Now())) or {}
    return {
        cycleId = cycleInfo.cycleId or "unknown_0",
        activeId = cycleInfo.activityId or "sweet",
        sweet = { value = 0, submitted = 0, exchanged = {} },
        alien = { genes = 0, totalGenes = 0, drawCount = 0 },
        dark = { devourHarvestCount = 0, darkSeedDrops = 0 },
    }
end

function ServerEconomyState.NormalizeActivityState(activity)
    local cycleInfo = deps_.GameConfig.GetActivityCycleInfo and deps_.GameConfig.GetActivityCycleInfo(Now()) or { activityId = "sweet", cycleId = "sweet_0" }
    activity = type(activity) == "table" and activity or {}
    if activity.cycleId ~= cycleInfo.cycleId then
        activity = ServerEconomyState.NewActivityState(cycleInfo)
    end
    activity.cycleId = cycleInfo.cycleId
    activity.activeId = cycleInfo.activityId
    activity.sweet = type(activity.sweet) == "table" and activity.sweet or {}
    activity.sweet.value = math.max(0, math.floor(tonumber(activity.sweet.value or 0) or 0))
    activity.sweet.submitted = math.max(0, math.floor(tonumber(activity.sweet.submitted or 0) or 0))
    activity.sweet.exchanged = type(activity.sweet.exchanged) == "table" and activity.sweet.exchanged or {}
    activity.alien = type(activity.alien) == "table" and activity.alien or {}
    activity.alien.genes = math.max(0, math.floor(tonumber(activity.alien.genes or 0) or 0))
    activity.alien.totalGenes = math.max(0, math.floor(tonumber(activity.alien.totalGenes or 0) or 0))
    activity.alien.drawCount = math.max(0, math.floor(tonumber(activity.alien.drawCount or 0) or 0))
    activity.dark = type(activity.dark) == "table" and activity.dark or {}
    activity.dark.devourHarvestCount = math.max(0, math.floor(tonumber(activity.dark.devourHarvestCount or 0) or 0))
    activity.dark.darkSeedDrops = math.max(0, math.floor(tonumber(activity.dark.darkSeedDrops or 0) or 0))
    return activity
end

function ServerEconomyState.NormalizeEconomyState(state)
    state = type(state) == "table" and state or {}
    state.gold = math.max(0, math.floor(tonumber(state.gold or deps_.startGold) or deps_.startGold))
    state.seedBag = CopyNumericKeyMap(state.seedBag)
    state.seedBagBuffs = CopyNumericKeyMap(state.seedBagBuffs)
    state.harvested = type(state.harvested) == "table" and state.harvested or {}
    for _, item in ipairs(state.harvested) do
        RecalculateAuthoritativeItemPrice(item)
    end
    state.seedPacks = type(state.seedPacks) == "table" and state.seedPacks or {}
    state.collectedPlants = CopyNumericKeyMap(state.collectedPlants)
    state.tutorial = type(state.tutorial) == "table" and state.tutorial or {}
    state.tutorial.plantGuideDone = state.tutorial.plantGuideDone == true
    state.dailyTaskState = ServerEconomyState.NormalizeDailyTaskState(state.dailyTaskState)
    state.talent = ServerEconomyState.NormalizeTalentState(state.talent)
    state.progression = ServerEconomyState.NormalizeProgressionState(state.progression)
    state.activity = ServerEconomyState.NormalizeActivityState(state.activity)
    state.updatedAt = Now()
    return state
end

function ServerEconomyState.BuildInitialEconomyState()
    return ServerEconomyState.NormalizeEconomyState({
        gold = deps_.startGold,
        seedBag = { [1] = 6, [21] = 4, [2] = 2 },
        seedBagBuffs = {},
        harvested = {},
        seedPacks = { pack_common = 1 },
        tutorial = { plantGuideDone = false },
        dailyTaskState = { progress = { plant = 0, harvest = 0, sell = 0 }, rewardClaimed = false },
        talent = { unlockedTalents = {}, talentPoints = 1, level = 1, exp = 0 },
        progression = { unlockedPlotCount = 1, gardenLevel = 1, currentTourValue = 0, bestTourValue = 0 },
        activity = nil,
    })
end

function ServerEconomyState.GetServerMutationTalentBonus(state)
    local talent = ServerEconomyState.NormalizeTalentState(state and state.talent)
    local bonus = 0
    for talentId, value in pairs(deps_.serverMutationTalentBonuses) do
        if talent.unlockedTalents[talentId] == true then
            bonus = bonus + value
        end
    end
    return bonus
end

function ServerEconomyState.GetHarvestBagCapacityFromState(state)
    local talent = ServerEconomyState.NormalizeTalentState(state and state.talent)
    local bonus = 0
    for talentId, value in pairs(deps_.bagCapacityBonuses) do
        if talent.unlockedTalents[talentId] == true then
            bonus = bonus + value
        end
    end
    return math.min(deps_.maxHarvestBagCapacity, deps_.defaultHarvestBagCapacity + bonus)
end

function ServerEconomyState.SyncProgressionTourValueFromFarm(state, farmState)
    if type(state) ~= "table" then return 0 end
    state.progression = ServerEconomyState.NormalizeProgressionState(state.progression)
    local tourValue = CalculateAuthFarmTourValue(farmState)
    state.progression.currentTourValue = tourValue
    state.progression.bestTourValue = math.max(tonumber(state.progression.bestTourValue or 0) or 0, tourValue)
    return tourValue
end

function ServerEconomyState.AddTourRankCommit(commit, uid, state)
    local progression = ServerEconomyState.NormalizeProgressionState(state and state.progression)
    local score = math.max(0, math.floor(tonumber(progression.currentTourValue or 0) or 0))
    commit:ScoreSetInt(uid, deps_.Shared.KEYS.TOUR_RANK, score)
end

function ServerEconomyState.GetActivityRankScore(activityId, activity)
    activity = ServerEconomyState.NormalizeActivityState(activity)
    if activityId == "sweet" then
        return math.max(0, math.floor(tonumber(activity.sweet and activity.sweet.submitted or 0) or 0))
    elseif activityId == "alien" then
        return math.max(0, math.floor(tonumber(activity.alien and activity.alien.totalGenes or 0) or 0))
    elseif activityId == "dark" then
        local dark = activity.dark or {}
        return math.max(0, math.floor(tonumber(dark.darkSeedDrops or 0) or 0))
    end
    return 0
end

function ServerEconomyState.AddActivityRankCommit(commit, uid, state)
    local activity = ServerEconomyState.NormalizeActivityState(state and state.activity)
    local activityId = activity.activeId or (deps_.GameConfig.GetActiveActivityId and deps_.GameConfig.GetActiveActivityId(Now())) or "sweet"
    local info = GetActivityRankInfo(activityId, { activityId = activityId, cycleId = activity.cycleId, timeLeft = 0 })
    commit:ScoreSetInt(uid, info.key, ServerEconomyState.GetActivityRankScore(activityId, activity))
end

function ServerEconomyState.AddIncomeRankCommit(commit, uid, amount)
    amount = math.max(0, math.floor(tonumber(amount or 0) or 0))
    if amount <= 0 then return end
    commit:ScoreAddInt(uid, GetIncomeRankInfo().key, amount)
end

return ServerEconomyState
