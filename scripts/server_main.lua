-- ============================================================================
-- 社交花园服务端入口
-- ============================================================================
-- 服务端权威处理：花园快照、作物成熟与可偷状态、排行榜、拜访、偷菜日志、种子赠送。
-- 客户端只上传可视快照；作物 ID、种植时间、成熟、被偷状态与奖励发放由服务端合并保存。
-- ============================================================================

local Shared = require("network.shared")
local GameConfig = require("config.game_config")
local InventoryRules = require("systems.inventory_rules")
local RequestGuard = require("server.request_guard")
local GiftServer = require("server.gift_server")
local SocialServer = require("server.social_server")
local ServerUtils = require("server.server_utils")
local ServerShop = require("server.server_shop")
local ServerCropRules = require("server.server_crop_rules")
local ServerFarmState = require("server.server_farm_state")
local ServerEconomyState = require("server.server_economy_state")
local ServerCommission = require("server.server_commission")
local ServerActivity = require("server.server_activity")
local ServerRewards = require("server.server_rewards")
local ServerEconomyActions = require("server.server_economy_actions")
local ServerLeaderboard = require("server.server_leaderboard")
local ServerSteal = require("server.server_steal")
local ServerEventHandlers = require("server.server_event_handlers")
ServerUtils.Init({ GameConfig = GameConfig })

local scene_ = nil
local connections_ = {}
local connectionUsers_ = {}

local DAILY_STEAL_LIMIT = 5
local DAILY_STEAL_AD_LIMIT = 5
local DAILY_SEED_PACK_AD_LIMIT = 5
local DAILY_MATURE_AD_LIMIT = 5
local AD_STEAL_BONUS = 5
local AD_RARE_PACK_COUNT = 5
local DAILY_GIFT_LIMIT = 5
local MAX_SOCIAL_ROWS = 20
local START_GOLD = 150
local MAX_OPEN_PACK_COUNT = 50
local MAX_GIFT_COUNT = 1
local GLOBAL_SHOP_UID = 858557875
local SEED_SHOP_REFRESH_INTERVAL = 300
local INCOME_RANK_REFRESH_INTERVAL = 7 * 24 * 60 * 60
local ACTIVITY_RANK_REWARD_TOP = 20
local function Now()
    return ServerUtils.Now()
end

local function GetConnectionKey(connection)
    return ServerUtils.GetConnectionKey(connection)
end

local function GetConnectionUserId(connection)
    return ServerUtils.GetConnectionUserId(connection)
end

local function NormalizeUserId(userId)
    return ServerUtils.NormalizeUserId(userId)
end

local function GetRequestUserId(connection, data)
    return ServerUtils.GetRequestUserId(connection, data)
end

local function SameUserId(left, right)
    return ServerUtils.SameUserId(left, right)
end

local function GetNicknameRows(response)
    return ServerUtils.GetNicknameRows(response)
end

local function GetNicknameMap(userIds, done)
    ServerUtils.GetNicknameMap(userIds, done)
end

local function SeedShopRefreshId(now)
    return ServerShop.SeedShopRefreshId(now)
end

local function SeedShopRefreshRemaining(now)
    return ServerShop.SeedShopRefreshRemaining(now)
end

local function GetIncomeRankInfo(now)
    return ServerLeaderboard.GetIncomeRankInfo(now)
end

local function GetActivityRankInfo(activityId, cycleInfo)
    return ServerLeaderboard.GetActivityRankInfo(activityId, cycleInfo)
end

local function BuildSeedShopQuotaKey(refreshId, plantIndex)
    return ServerShop.BuildSeedShopQuotaKey(refreshId, plantIndex)
end

local function FindPlantIndexByName(name)
    return ServerShop.FindPlantIndexByName(name)
end

local function NormalizeSeedShopState(shop)
    return ServerShop.NormalizeSeedShopState(shop)
end

local function BuildSeedShopState(now)
    return ServerShop.BuildSeedShopState(now)
end

local function AddSeedShopResponseFields(shop, now)
    return ServerShop.AddSeedShopResponseFields(shop, now)
end

local function EnsureSeedShopState(callback)
    ServerShop.EnsureSeedShopState(callback)
end

local DeepCopy

local function RebuildSeedShopItemsFromStock(shop)
    ServerShop.RebuildSeedShopItemsFromStock(shop)
end

local function FetchSeedShopAvailableState(shop, callback)
    ServerShop.FetchSeedShopAvailableState(shop, callback)
end

local function Send(connection, eventName, data)
    Shared.SendToClient(connection, eventName, data)
end

local function BroadcastSeedShopState(shop)
    ServerShop.BroadcastSeedShopState(shop)
end

local function SendFullAvailableSeedShop(connection, eventName, baseData)
    ServerShop.SendFullAvailableSeedShop(connection, eventName, baseData)
end

local function BroadcastFullAvailableSeedShop()
    ServerShop.BroadcastFullAvailableSeedShop()
end

local function SendSeedShopState(connection)
    ServerShop.SendSeedShopState(connection)
end

local function SendError(connection, eventName, code, message, extra)
    local data = extra or {}
    data.success = false
    data.code = code
    data.message = message
    Send(connection, eventName, data)
end

local function NormalizePlantIndex(value)
    return ServerUtils.NormalizePlantIndex(value)
end

local function NormalizePlotIndex(value)
    return ServerUtils.NormalizePlotIndex(value)
end

local function NormalizePositiveCount(value, maxValue)
    return ServerUtils.NormalizePositiveCount(value, maxValue)
end

local function NormalizeLocalPos(value)
    return ServerUtils.NormalizeLocalPos(value)
end

local function IsValidPackId(packId)
    return ServerUtils.IsValidPackId(packId)
end

local function IsValidSellMode(mode)
    return ServerUtils.IsValidSellMode(mode)
end

local function NextRevision(state)
    ServerUtils.NextRevision(state)
end

local function GetMaxCropsPerPlot()
    return ServerUtils.GetMaxCropsPerPlot()
end

local function CheckRequestId(...)
    return RequestGuard.Check(...)
end

local function RecordRequestId(...)
    return RequestGuard.Record(...)
end

local function AddRequestRecordToCommit(...)
    return RequestGuard.AddToCommit(...)
end

DeepCopy = function(value)
    return ServerUtils.DeepCopy(value)
end

local function CopyNumericKeyMap(source)
    return ServerUtils.CopyNumericKeyMap(source)
end

local function RollWeighted(pool)
    return ServerUtils.RollWeighted(pool)
end

local function IsLimitedSeed(seedId)
    return ServerCropRules.IsLimitedSeed(seedId)
end

local function GetPackRollPool(packCfg)
    return ServerCropRules.GetPackRollPool(packCfg)
end

local function RollSeedFromPack(packCfg)
    return ServerCropRules.RollSeedFromPack(packCfg)
end

local function RollRareSeedId()
    return ServerCropRules.RollRareSeedId()
end

local function RollHarvestDropPack(rarity)
    return ServerCropRules.RollHarvestDropPack(rarity)
end

local function RandomRange(minValue, maxValue)
    return ServerUtils.RandomRange(minValue, maxValue)
end

local function GetCropScaleRules()
    return ServerCropRules.GetCropScaleRules()
end

local function ClampValue(value, minValue, maxValue)
    return ServerUtils.ClampValue(value, minValue, maxValue)
end

local function ClampCropWeightScale(weightScale)
    return ServerCropRules.ClampCropWeightScale(weightScale)
end

local function GetWeightMultiplierFromRatio(weightRatio)
    return ServerCropRules.GetWeightMultiplierFromRatio(weightRatio)
end

local function RollCropWeightScale()
    return ServerCropRules.RollCropWeightScale()
end

local function RandItem(list)
    return ServerUtils.RandItem(list)
end

local function SerializeColor(color)
    return ServerCropRules.SerializeColor(color)
end

local function CloneColorMutation(item)
    return ServerCropRules.CloneColorMutation(item)
end

local function CloneSpecialMutation(item)
    return ServerCropRules.CloneSpecialMutation(item)
end

local function FindSpecialMutationConfig(key)
    return ServerCropRules.FindSpecialMutationConfig(key)
end

local function HasMutationSpecial(mutation, key)
    return ServerCropRules.HasMutationSpecial(mutation, key)
end

local function AddServerSpecialMutation(mutation, key)
    return ServerCropRules.AddServerSpecialMutation(mutation, key)
end

local function ApplyServerActivityPlantingMutation(mutation, mutationBonus)
    ServerCropRules.ApplyServerActivityPlantingMutation(mutation, mutationBonus)
end

local function RollServerMutation(plant, seedBuff, mutationBonus)
    return ServerCropRules.RollServerMutation(plant, seedBuff, mutationBonus)
end

local function BuildAuthCropName(plant, mutation)
    return ServerCropRules.BuildAuthCropName(plant, mutation)
end

local function CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
    return ServerCropRules.CalculateAuthoritativeCropPrice(plant, weightMultiplier, mutation)
end

local function RecalculateAuthoritativeItemPrice(item)
    ServerCropRules.RecalculateAuthoritativeItemPrice(item)
end

local function BuildAuthoritativeCrop(uid, payload, seedBuff, mutationBonus)
    return ServerCropRules.BuildAuthoritativeCrop(uid, payload, seedBuff, mutationBonus)
end

local function NormalizeFarmState(state)
    return ServerFarmState.NormalizeFarmState(state)
end

local function GetFarmPlot(state, plotIndex)
    return ServerFarmState.GetFarmPlot(state, plotIndex)
end

local function FindFarmCrop(state, cropId)
    return ServerFarmState.FindFarmCrop(state, cropId)
end

local function FindFarmCropFromHarvestPayload(state, payload)
    return ServerFarmState.FindFarmCropFromHarvestPayload(state, payload)
end

local function RefreshAuthCrop(crop)
    ServerFarmState.RefreshAuthCrop(crop)
end

local function CalculateAuthCropSightValue(crop)
    return ServerFarmState.CalculateAuthCropSightValue(crop)
end

local function CalculateAuthFarmTourValue(farmState)
    return ServerFarmState.CalculateAuthFarmTourValue(farmState)
end

local function BuildVisitGardenFromAuthFarm(uid, nickname, farmState, snapshot)
    return ServerFarmState.BuildVisitGardenFromAuthFarm(uid, nickname, farmState, snapshot)
end

local function NormalizeTalentState(talent)
    return ServerEconomyState.NormalizeTalentState(talent)
end

local function NormalizeProgressionState(progression)
    return ServerEconomyState.NormalizeProgressionState(progression)
end

local function NormalizeDailyTaskState(daily)
    return ServerEconomyState.NormalizeDailyTaskState(daily)
end

local function NormalizeActivityState(activity)
    return ServerEconomyState.NormalizeActivityState(activity)
end

local function NormalizeEconomyState(state)
    return ServerEconomyState.NormalizeEconomyState(state)
end

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
local COMMISSION_STATE_KEY = "garden_commission_state_v1"
local COMMISSION_REFRESH_INTERVAL = 30 * 60
local COMMISSION_COUNT = 4
local COMMISSION_CUSTOMERS = { "露露", "阿麦", "青木", "莓莓", "小枫", "云朵商人", "花园旅人", "星屑收藏家" }
local COMMISSION_COLOR_REQUIREMENTS = { "yellow", "blue", "red", "white", "purple", "black" }
local COMMISSION_SPECIAL_REQUIREMENTS = { "wet", "frozen", "cloud", "chocolate", "pollen", "glow", "stardust", "ceramic", "rainbow", "void", "gold" }
local COMMISSION_PACK_DIFFICULTY = {
    pack_common = { mutationKinds = { "basic" }, minWeightScale = { 0.90, 1.20 } },
    pack_uncommon = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.00, 1.40 } },
    pack_rare = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.05, 1.55 } },
    pack_epic = { mutationKinds = { "color", "special" }, minWeightScale = { 1.35, 2.20 } },
    pack_legendary = { mutationKinds = { "special", "giant" }, minWeightScale = { 2.00, 3.60 } },
}
local COMMISSION_REWARD_POOLS = {
    ["普通"] = { { packId = "pack_common", weight = 94 }, { packId = "pack_uncommon", weight = 6 } },
    ["罕见"] = { { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 55 }, { packId = "pack_rare", weight = 10 } },
    ["稀有"] = { { packId = "pack_common", weight = 18 }, { packId = "pack_uncommon", weight = 30 }, { packId = "pack_rare", weight = 45 }, { packId = "pack_epic", weight = 7 } },
    ["史诗"] = { { packId = "pack_common", weight = 8 }, { packId = "pack_uncommon", weight = 18 }, { packId = "pack_rare", weight = 32 }, { packId = "pack_epic", weight = 38 }, { packId = "pack_legendary", weight = 4 } },
    ["传奇"] = { { packId = "pack_common", weight = 3 }, { packId = "pack_uncommon", weight = 10 }, { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 40 }, { packId = "pack_legendary", weight = 25 } },
}

local function BuildInitialEconomyState()
    return ServerEconomyState.BuildInitialEconomyState()
end

local SERVER_MUTATION_TALENT_BONUSES = {
    mutation_1 = 0.10,
    mutation_2 = 0.10,
    mutation_3 = 0.15,
    mutation_4 = 0.15,
    mutation_5 = 0.25,
}

local function GetServerMutationTalentBonus(state)
    return ServerEconomyState.GetServerMutationTalentBonus(state)
end

local DEFAULT_HARVEST_BAG_CAPACITY = 20
local MAX_HARVEST_BAG_CAPACITY = 100
local BAG_CAPACITY_BONUSES = {
    bag_capacity_1 = 15,
    bag_capacity_2 = 15,
    bag_capacity_3 = 15,
    bag_capacity_4 = 15,
    bag_capacity_5 = 20,
}

local function GetHarvestBagCapacityFromState(state)
    return ServerEconomyState.GetHarvestBagCapacityFromState(state)
end

local function SyncProgressionTourValueFromFarm(state, farmState)
    return ServerEconomyState.SyncProgressionTourValueFromFarm(state, farmState)
end

local function AddTourRankCommit(commit, uid, state)
    ServerEconomyState.AddTourRankCommit(commit, uid, state)
end

local function GetActivityRankScore(activityId, activity)
    return ServerEconomyState.GetActivityRankScore(activityId, activity)
end

local function AddActivityRankCommit(commit, uid, state)
    ServerEconomyState.AddActivityRankCommit(commit, uid, state)
end

local function AddIncomeRankCommit(commit, uid, amount)
    ServerEconomyState.AddIncomeRankCommit(commit, uid, amount)
end

local function NewActivityState(cycleInfo)
    return ServerEconomyState.NewActivityState(cycleInfo)
end

local function FindTalentConfig(talentId)
    return ServerRewards.FindTalentConfig(talentId)
end

local function GetLevelUpTalentPoints(level)
    return ServerRewards.GetLevelUpTalentPoints(level)
end

local function AddServerHarvestExp(state, rarity, priceMultiplier)
    return ServerRewards.AddServerHarvestExp(state, rarity, priceMultiplier)
end

local function GetActiveActivityId()
    return ServerActivity.GetActiveActivityId()
end

local function GetCurrentActivityCycleInfo()
    return ServerActivity.GetCurrentActivityCycleInfo()
end

local function GetPreviousActivityCycleInfo()
    return ServerActivity.GetPreviousActivityCycleInfo()
end

local function GetActivityConfig(activityId)
    return ServerActivity.GetActivityConfig(activityId)
end

local function HasSpecialMutation(item, key)
    return ServerActivity.HasSpecialMutation(item, key)
end

local function GetRarityOrder(rarity)
    return ServerActivity.GetRarityOrder(rarity)
end

local function GetSweetSubmitValue(item)
    return ServerActivity.GetSweetSubmitValue(item)
end

local function FindSweetReward(rewardId)
    return ServerActivity.FindSweetReward(rewardId)
end

local function GetDarkSeedWeight(plantIndex)
    return ServerActivity.GetDarkSeedWeight(plantIndex)
end

local function RollDarkSeed(activity)
    return ServerActivity.RollDarkSeed(activity)
end

local function ApplyActivityHarvestReward(state, crop)
    return ServerActivity.ApplyActivityHarvestReward(state, crop)
end

local function BuildExpansionRequirement(plotIndex)
    return ServerRewards.BuildExpansionRequirement(plotIndex)
end

local function RequestAuthFarmState(uid, connection)
    ServerFarmState.RequestAuthFarmState(uid, connection)
end

local function RequestEconomyState(uid, connection)
    ServerEconomyActions.RequestEconomyState(uid, connection)
end

local function BuySeed(uid, plantIndex, _price, connection, count, requestId, refreshId)
    ServerEconomyActions.BuySeed(uid, plantIndex, _price, connection, count, requestId, refreshId)
end

local function ClearPlayerSave(uid, connection)
    ServerEconomyActions.ClearPlayerSave(uid, connection)
end

local function PlantSeedAuthority(uid, payload, connection)
    ServerEconomyActions.PlantSeedAuthority(uid, payload, connection)
end

local function HarvestCropAuthority(uid, payload, connection)
    ServerEconomyActions.HarvestCropAuthority(uid, payload, connection)
end

local function OpenSeedPackAuthority(uid, payload, connection)
    ServerEconomyActions.OpenSeedPackAuthority(uid, payload, connection)
end

local function SellHarvested(uid, sellMode, payload, connection)
    ServerEconomyActions.SellHarvested(uid, sellMode, payload, connection)
end


local function FindMutationByKey(list, key)
    return ServerCommission.FindMutationByKey(list, key)
end

local function IsCommissionEligiblePlant(plant)
    return ServerCommission.IsCommissionEligiblePlant(plant)
end

local function PickCommissionPlantIndex(level)
    return ServerCommission.PickCommissionPlantIndex(level)
end

local function GetCommissionRewardPack(plant)
    return ServerCommission.GetCommissionRewardPack(plant)
end

local function BuildCommissionMutationRequirement(packId)
    return ServerCommission.BuildCommissionMutationRequirement(packId)
end

local function BuildCommission(index, level)
    return ServerCommission.BuildCommission(index, level)
end

local function NormalizeCommissionState(state, level)
    return ServerCommission.NormalizeCommissionState(state, level)
end

local function HasColorMutation(item, key)
    return ServerCommission.HasColorMutation(item, key)
end

local function HasBasicMutation(item)
    return ServerCommission.HasBasicMutation(item)
end

local function CommissionItemMatches(commission, item)
    return ServerCommission.CommissionItemMatches(commission, item)
end

local function RequestCommissionsAuthority(uid, payload, connection)
    ServerCommission.RequestCommissionsAuthority(uid, payload, connection)
end

local function CompleteCommissionAuthority(uid, payload, connection)
    ServerCommission.CompleteCommissionAuthority(uid, payload, connection)
end

local function SubmitActivityCropAuthority(uid, payload, connection)
    ServerActivity.SubmitActivityCropAuthority(uid, payload, connection)
end

local function ExchangeActivityRewardAuthority(uid, payload, connection)
    ServerActivity.ExchangeActivityRewardAuthority(uid, payload, connection)
end

local function DrawActivityPackAuthority(uid, payload, connection)
    ServerActivity.DrawActivityPackAuthority(uid, payload, connection)
end

local function MatureAllCropsInPlot(farmState, plotIndex)
    return ServerRewards.MatureAllCropsInPlot(farmState, plotIndex)
end

local function GrantAdReward(uid, payload, connection)
    ServerRewards.GrantAdReward(uid, payload, connection)
end

local function ClaimDailyRewardAuthority(uid, payload, connection)
    ServerRewards.ClaimDailyRewardAuthority(uid, payload, connection)
end

local function SynthesizePackAuthority(uid, payload, connection)
    ServerRewards.SynthesizePackAuthority(uid, payload, connection)
end

local function UnlockTalentAuthority(uid, payload, connection)
    ServerRewards.UnlockTalentAuthority(uid, payload, connection)
end

local function ExpandPlotAuthority(uid, payload, connection)
    ServerRewards.ExpandPlotAuthority(uid, payload, connection)
end

local function ReadRequest(eventData)
    return Shared.ReadEventData(eventData)
end

local function ResolveLeaderboardInfo(kind, activityId)
    return ServerLeaderboard.ResolveLeaderboardInfo(kind, activityId)
end

local function GetRankItemScore(item, key)
    return ServerLeaderboard.GetRankItemScore(item, key)
end

local function AddPreviousActivityRewardStatus(uid, data, done)
    ServerLeaderboard.AddPreviousActivityRewardStatus(uid, data, done)
end

local function SendLeaderboardWithMyRank(uid, connection, requestId, info, list)
    ServerLeaderboard.SendLeaderboardWithMyRank(uid, connection, requestId, info, list)
end

local function RequestLeaderboardAuthority(uid, payload, connection)
    ServerLeaderboard.RequestLeaderboardAuthority(uid, payload, connection)
end

local function PickLockedAvatar(unlocked)
    return ServerLeaderboard.PickLockedAvatar(unlocked)
end

local function ClaimActivityRankRewardAuthority(uid, payload, connection)
    ServerLeaderboard.ClaimActivityRankRewardAuthority(uid, payload, connection)
end

local function GetStealChance(crop)
    return ServerSteal.GetStealChance(crop)
end

local function RollStealReward(crop)
    return ServerSteal.RollStealReward(crop)
end

local function BuildStealRecordKey(targetUid, cropId)
    return ServerSteal.BuildStealRecordKey(targetUid, cropId)
end

local function BuildStealCropClaimKey(cropId)
    return ServerSteal.BuildStealCropClaimKey(cropId)
end

local function RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
    ServerSteal.RequestStealWithQuotaAvailable(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey, stealLimit)
end

local function RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
    ServerSteal.RequestSteal(uid, targetUid, cropIndex, cropId, connection, requestId, requestRecordKey)
end

local function SendPlayerProfile(uid, connection)
    if uid == nil then return end
    if GetUserNickname == nil then
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = "Tap玩家" })
        return
    end
    GetUserNickname({
        userIds = { uid },
        onSuccess = function(response)
            local nickname = "Tap玩家"
            for _, info in ipairs(GetNicknameRows(response)) do
                if SameUserId(info.userId, uid) and info.nickname ~= nil and info.nickname ~= "" then
                    nickname = info.nickname
                    break
                end
            end
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = nickname })
        end,
        onError = function(errorCode)
            print("[玩家资料] 服务端昵称查询失败: " .. tostring(errorCode))
            Send(connection, Shared.EVENTS.PLAYER_PROFILE, { success = true, userId = NormalizeUserId(uid) or uid, nickname = "Tap玩家" })
        end,
    })
end

function HandleClientConnected(eventType, eventData)
    ServerEventHandlers.HandleClientConnected(eventType, eventData)
end

function HandleClientIdentity(eventType, eventData)
    ServerEventHandlers.HandleClientIdentity(eventType, eventData)
end

function HandleClientDisconnected(eventType, eventData)
    ServerEventHandlers.HandleClientDisconnected(eventType, eventData)
end

function HandleGardenClientReady(eventType, eventData)
    ServerEventHandlers.HandleGardenClientReady(eventType, eventData)
end

function HandleGardenSaveSnapshot(eventType, eventData)
    ServerEventHandlers.HandleGardenSaveSnapshot(eventType, eventData)
end

function HandleGardenRequestSnapshot(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestSnapshot(eventType, eventData)
end

function HandleGardenRequestRank(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestRank(eventType, eventData)
end

function HandleGardenRequestLeaderboard(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestLeaderboard(eventType, eventData)
end

function HandleGardenClaimActivityRankReward(eventType, eventData)
    ServerEventHandlers.HandleGardenClaimActivityRankReward(eventType, eventData)
end

function HandleGardenRequestSteal(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestSteal(eventType, eventData)
end

function HandleGardenRequestSocialState(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestSocialState(eventType, eventData)
end

function HandleGardenRequestEconomyState(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestEconomyState(eventType, eventData)
end

function HandleGardenRequestSeedShop(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestSeedShop(eventType, eventData)
end

function HandleGardenRequestAuthFarm(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestAuthFarm(eventType, eventData)
end

function HandleGardenRequestAdReward(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestAdReward(eventType, eventData)
end

function HandleGardenBuySeed(eventType, eventData)
    ServerEventHandlers.HandleGardenBuySeed(eventType, eventData)
end

function HandleGardenClearSave(eventType, eventData)
    ServerEventHandlers.HandleGardenClearSave(eventType, eventData)
end

function HandleGardenPlantSeed(eventType, eventData)
    ServerEventHandlers.HandleGardenPlantSeed(eventType, eventData)
end

function HandleGardenHarvestCrop(eventType, eventData)
    ServerEventHandlers.HandleGardenHarvestCrop(eventType, eventData)
end

function HandleGardenOpenSeedPack(eventType, eventData)
    ServerEventHandlers.HandleGardenOpenSeedPack(eventType, eventData)
end

function HandleGardenSellHarvested(eventType, eventData)
    ServerEventHandlers.HandleGardenSellHarvested(eventType, eventData)
end

function HandleGardenRequestCommissions(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestCommissions(eventType, eventData)
end

function HandleGardenCompleteCommission(eventType, eventData)
    ServerEventHandlers.HandleGardenCompleteCommission(eventType, eventData)
end

function HandleGardenSubmitActivityCrop(eventType, eventData)
    ServerEventHandlers.HandleGardenSubmitActivityCrop(eventType, eventData)
end

function HandleGardenExchangeActivityReward(eventType, eventData)
    ServerEventHandlers.HandleGardenExchangeActivityReward(eventType, eventData)
end

function HandleGardenDrawActivityPack(eventType, eventData)
    ServerEventHandlers.HandleGardenDrawActivityPack(eventType, eventData)
end

function HandleGardenClaimDailyReward(eventType, eventData)
    ServerEventHandlers.HandleGardenClaimDailyReward(eventType, eventData)
end

function HandleGardenSynthesizePack(eventType, eventData)
    ServerEventHandlers.HandleGardenSynthesizePack(eventType, eventData)
end

function HandleGardenUnlockTalent(eventType, eventData)
    ServerEventHandlers.HandleGardenUnlockTalent(eventType, eventData)
end

function HandleGardenExpandPlot(eventType, eventData)
    ServerEventHandlers.HandleGardenExpandPlot(eventType, eventData)
end

function HandleGardenSendSeedGift(eventType, eventData)
    ServerEventHandlers.HandleGardenSendSeedGift(eventType, eventData)
end

function HandleGardenLikeGarden(eventType, eventData)
    ServerEventHandlers.HandleGardenLikeGarden(eventType, eventData)
end

function HandleGardenSendFriendRequest(eventType, eventData)
    ServerEventHandlers.HandleGardenSendFriendRequest(eventType, eventData)
end

function HandleGardenRespondFriendRequest(eventType, eventData)
    ServerEventHandlers.HandleGardenRespondFriendRequest(eventType, eventData)
end

function HandleGardenRemoveFriend(eventType, eventData)
    ServerEventHandlers.HandleGardenRemoveFriend(eventType, eventData)
end

function HandleGardenClearSocialMessages(eventType, eventData)
    ServerEventHandlers.HandleGardenClearSocialMessages(eventType, eventData)
end

function HandleGardenRequestGifts(eventType, eventData)
    ServerEventHandlers.HandleGardenRequestGifts(eventType, eventData)
end

function HandleGardenClaimGift(eventType, eventData)
    ServerEventHandlers.HandleGardenClaimGift(eventType, eventData)
end

local function PickGiftSeedId()
    local pool = {}
    local allowed = { ["普通"] = true, ["罕见"] = true, ["稀有"] = true, ["史诗"] = true }
    for seedId, plant in ipairs(GameConfig.PLANTS or {}) do
        if plant ~= nil and allowed[plant.rarity] == true then
            pool[#pool + 1] = seedId
        end
    end
    if #pool <= 0 then return 1 end
    return pool[math.random(1, #pool)]
end

function Start()
    math.randomseed(os.time())
    scene_ = Scene()
    ServerShop.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        globalShopUid = GLOBAL_SHOP_UID,
        refreshInterval = SEED_SHOP_REFRESH_INTERVAL,
        getConnections = function() return connections_ end,
        send = Send,
        now = Now,
        deepCopy = DeepCopy,
    })
    ServerCropRules.Init({
        GameConfig = GameConfig,
        InventoryRules = InventoryRules,
        Now = Now,
        NormalizePlantIndex = NormalizePlantIndex,
        NormalizePlotIndex = NormalizePlotIndex,
        NormalizeLocalPos = NormalizeLocalPos,
        RollWeighted = RollWeighted,
        RandomRange = RandomRange,
        RandItem = RandItem,
        ClampValue = ClampValue,
    })
    ServerFarmState.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        Send = Send,
        Now = Now,
        NormalizePlotIndex = NormalizePlotIndex,
        NormalizeLocalPos = NormalizeLocalPos,
        RecalculateAuthoritativeItemPrice = RecalculateAuthoritativeItemPrice,
    })
    ServerEconomyState.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        startGold = START_GOLD,
        talentMaxLevel = TALENT_MAX_LEVEL,
        serverMutationTalentBonuses = SERVER_MUTATION_TALENT_BONUSES,
        defaultHarvestBagCapacity = DEFAULT_HARVEST_BAG_CAPACITY,
        maxHarvestBagCapacity = MAX_HARVEST_BAG_CAPACITY,
        bagCapacityBonuses = BAG_CAPACITY_BONUSES,
        Now = Now,
        CopyNumericKeyMap = CopyNumericKeyMap,
        RecalculateAuthoritativeItemPrice = RecalculateAuthoritativeItemPrice,
        CalculateAuthFarmTourValue = CalculateAuthFarmTourValue,
        GetActivityRankInfo = GetActivityRankInfo,
        GetIncomeRankInfo = GetIncomeRankInfo,
    })
    ServerCommission.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        Send = Send,
        Now = Now,
        RandItem = RandItem,
        RandomRange = RandomRange,
        RollWeighted = RollWeighted,
        NormalizeEconomyState = NormalizeEconomyState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NextRevision = NextRevision,
    })
    ServerActivity.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        RequestGuard = RequestGuard,
        Send = Send,
        Now = Now,
        NormalizeActivityState = NormalizeActivityState,
        NormalizeEconomyState = NormalizeEconomyState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NormalizePositiveCount = NormalizePositiveCount,
        NormalizePlantIndex = NormalizePlantIndex,
        IsValidPackId = IsValidPackId,
        RollWeighted = RollWeighted,
        NextRevision = NextRevision,
        AddActivityRankCommit = AddActivityRankCommit,
    })
    ServerLeaderboard.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        RequestGuard = RequestGuard,
        SocialServer = SocialServer,
        Send = Send,
        Now = Now,
        GetCurrentActivityCycleInfo = GetCurrentActivityCycleInfo,
        GetPreviousActivityCycleInfo = GetPreviousActivityCycleInfo,
        GetActivityConfig = GetActivityConfig,
        NormalizePositiveCount = NormalizePositiveCount,
        GetNicknameMap = GetNicknameMap,
        incomeRankRefreshInterval = INCOME_RANK_REFRESH_INTERVAL,
        activityRankRewardTop = ACTIVITY_RANK_REWARD_TOP,
    })
    ServerRewards.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        RequestGuard = RequestGuard,
        SocialServer = SocialServer,
        Send = Send,
        Now = Now,
        NormalizeTalentState = NormalizeTalentState,
        NormalizeProgressionState = NormalizeProgressionState,
        NormalizeDailyTaskState = NormalizeDailyTaskState,
        NormalizeEconomyState = NormalizeEconomyState,
        NormalizeFarmState = NormalizeFarmState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        GetFarmPlot = GetFarmPlot,
        SyncProgressionTourValueFromFarm = SyncProgressionTourValueFromFarm,
        AddTourRankCommit = AddTourRankCommit,
        NextRevision = NextRevision,
        RollWeighted = RollWeighted,
        NormalizePlotIndex = NormalizePlotIndex,
        dailyStealLimit = DAILY_STEAL_LIMIT,
        dailyStealAdLimit = DAILY_STEAL_AD_LIMIT,
        dailySeedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT,
        dailyMatureAdLimit = DAILY_MATURE_AD_LIMIT,
        adStealBonus = AD_STEAL_BONUS,
        adRarePackCount = AD_RARE_PACK_COUNT,
    })
    ServerEconomyActions.Init({
        Shared = Shared,
        GameConfig = GameConfig,
        RequestGuard = RequestGuard,
        Send = Send,
        SendError = SendError,
        Now = Now,
        NormalizePlantIndex = NormalizePlantIndex,
        NormalizePositiveCount = NormalizePositiveCount,
        NormalizePlotIndex = NormalizePlotIndex,
        NormalizeLocalPos = NormalizeLocalPos,
        NormalizeEconomyState = NormalizeEconomyState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NormalizeFarmState = NormalizeFarmState,
        GetFarmPlot = GetFarmPlot,
        NormalizeDailyTaskState = NormalizeDailyTaskState,
        NextRevision = NextRevision,
        AddTourRankCommit = AddTourRankCommit,
        AddActivityRankCommit = AddActivityRankCommit,
        AddIncomeRankCommit = AddIncomeRankCommit,
        EnsureSeedShopState = EnsureSeedShopState,
        SendFullAvailableSeedShop = SendFullAvailableSeedShop,
        BroadcastFullAvailableSeedShop = BroadcastFullAvailableSeedShop,
        BuildSeedShopQuotaKey = BuildSeedShopQuotaKey,
        globalShopUid = GLOBAL_SHOP_UID,
        GetServerMutationTalentBonus = GetServerMutationTalentBonus,
        GetMaxCropsPerPlot = GetMaxCropsPerPlot,
        BuildAuthoritativeCrop = BuildAuthoritativeCrop,
        SyncProgressionTourValueFromFarm = SyncProgressionTourValueFromFarm,
        FindFarmCropFromHarvestPayload = FindFarmCropFromHarvestPayload,
        RefreshAuthCrop = RefreshAuthCrop,
        GetHarvestBagCapacityFromState = GetHarvestBagCapacityFromState,
        AddServerHarvestExp = AddServerHarvestExp,
        RollHarvestDropPack = RollHarvestDropPack,
        ApplyActivityHarvestReward = ApplyActivityHarvestReward,
        RollSeedFromPack = RollSeedFromPack,
        IsValidPackId = IsValidPackId,
        IsValidSellMode = IsValidSellMode,
        maxOpenPackCount = MAX_OPEN_PACK_COUNT,
    })
    ServerSteal.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        Send = Send,
        Now = Now,
        NormalizePlantIndex = NormalizePlantIndex,
        NormalizePositiveCount = NormalizePositiveCount,
        NormalizeEconomyState = NormalizeEconomyState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NormalizeFarmState = NormalizeFarmState,
        GetFarmPlot = GetFarmPlot,
        FindFarmCrop = FindFarmCrop,
        RefreshAuthCrop = RefreshAuthCrop,
        NextRevision = NextRevision,
        GetMaxCropsPerPlot = GetMaxCropsPerPlot,
        dailyStealLimit = DAILY_STEAL_LIMIT,
    })
    GiftServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        dailyGiftLimit = DAILY_GIFT_LIMIT,
        dailyStealLimit = DAILY_STEAL_LIMIT,
        dailySeedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT,
        dailyMatureAdLimit = DAILY_MATURE_AD_LIMIT,
        maxGiftCount = MAX_GIFT_COUNT,
        normalizePlantIndex = NormalizePlantIndex,
        normalizeEconomyState = NormalizeEconomyState,
        buildInitialEconomyState = BuildInitialEconomyState,
        nextRevision = NextRevision,
        pickGiftSeedId = PickGiftSeedId,
        getSeedName = function(seedId)
            local plant = GameConfig.PLANTS[tonumber(seedId or 0) or 0]
            return plant and plant.name or "神秘"
        end,
    })
    SocialServer.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        maxSocialRows = MAX_SOCIAL_ROWS,
        dailyStealLimit = DAILY_STEAL_LIMIT,
        dailySeedPackAdLimit = DAILY_SEED_PACK_AD_LIMIT,
        dailyMatureAdLimit = DAILY_MATURE_AD_LIMIT,
        normalizePositiveCount = NormalizePositiveCount,
        buildVisitGardenFromAuthFarm = BuildVisitGardenFromAuthFarm,
    })
    ServerEventHandlers.Init({
        Shared = Shared,
        RequestGuard = RequestGuard,
        SocialServer = SocialServer,
        GiftServer = GiftServer,
        connections = connections_,
        connectionUsers = connectionUsers_,
        scene = scene_,
        GetConnectionKey = GetConnectionKey,
        GetConnectionUserId = GetConnectionUserId,
        GetRequestUserId = GetRequestUserId,
        ReadRequest = ReadRequest,
        Send = Send,
        SendSeedShopState = SendSeedShopState,
        SendPlayerProfile = SendPlayerProfile,
        RequestEconomyState = RequestEconomyState,
        RequestAuthFarmState = RequestAuthFarmState,
        RequestLeaderboardAuthority = RequestLeaderboardAuthority,
        ClaimActivityRankRewardAuthority = ClaimActivityRankRewardAuthority,
        RequestSteal = RequestSteal,
        GrantAdReward = GrantAdReward,
        BuySeed = BuySeed,
        ClearPlayerSave = ClearPlayerSave,
        PlantSeedAuthority = PlantSeedAuthority,
        HarvestCropAuthority = HarvestCropAuthority,
        OpenSeedPackAuthority = OpenSeedPackAuthority,
        SellHarvested = SellHarvested,
        RequestCommissionsAuthority = RequestCommissionsAuthority,
        CompleteCommissionAuthority = CompleteCommissionAuthority,
        SubmitActivityCropAuthority = SubmitActivityCropAuthority,
        ExchangeActivityRewardAuthority = ExchangeActivityRewardAuthority,
        DrawActivityPackAuthority = DrawActivityPackAuthority,
        ClaimDailyRewardAuthority = ClaimDailyRewardAuthority,
        SynthesizePackAuthority = SynthesizePackAuthority,
        UnlockTalentAuthority = UnlockTalentAuthority,
        ExpandPlotAuthority = ExpandPlotAuthority,
    })
    Shared.RegisterServerEvents()
    ServerEventHandlers.Register()
    print("[社交花园服务端] 权威农场服务已启动")
end
