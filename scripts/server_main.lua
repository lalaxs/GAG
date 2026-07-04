-- ============================================================================
-- 社交花园服务端入口
-- ============================================================================
-- 服务端权威处理：花园快照、作物成熟与可偷状态、排行榜、拜访、偷菜日志、种子赠送。
-- 客户端只上传可视快照；作物 ID、种植时间、成熟、被偷状态与奖励发放由服务端合并保存。
-- ============================================================================

local Shared = require("network.shared")
local GameConfig = require("config.game_config")
local ServerConfig = require("config.server_tuning")
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
local ServerGlobals = require("runtime.server_globals")
local ServerBootstrap = require("runtime.server_bootstrap")
ServerUtils.Init({ GameConfig = GameConfig })

local scene_ = nil
local connections_ = {}
local connectionUsers_ = {}

local ServerTuning = ServerConfig.Tuning
local function Now()
    return ServerUtils.Now()
end

local function GetConnectionKey(connection)
    return ServerUtils.GetConnectionKey(connection)
end

local function GetConnectionUserId(connection)
    return ServerUtils.GetConnectionUserId(connection)
end

local function ReadConnectionIdentity(connection)
    return ServerUtils.ReadConnectionIdentity(connection)
end

local function RegisterConnectionUserId(connection, uid)
    return ServerUtils.RegisterConnectionUserId(connection, uid)
end

local function ClearConnectionUserId(connection)
    ServerUtils.ClearConnectionUserId(connection)
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

local function BuildInitialEconomyState(options)
    return ServerEconomyState.BuildInitialEconomyState(options)
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

local function MatureAllCropsInPlot(farmState, plotIndex)
    return ServerRewards.MatureAllCropsInPlot(farmState, plotIndex)
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

local function PickLockedAvatar(unlocked)
    return ServerLeaderboard.PickLockedAvatar(unlocked)
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

local function SendPlayerProfile(uid, connection)
    if uid == nil then return end

    local function deliverProfile(nickname, avatar)
        Send(connection, Shared.EVENTS.PLAYER_PROFILE, {
            success = true,
            userId = uid,
            nickname = nickname or "Tap玩家",
            avatar = avatar,
        })
    end

    SocialServer.GetPlayerGardenAvatar(uid, function(avatar)
        if GetUserNickname == nil then
            deliverProfile("Tap玩家", avatar)
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
                deliverProfile(nickname, avatar)
            end,
            onError = function(errorCode)
                print("[玩家资料] 服务端昵称查询失败: " .. tostring(errorCode))
                deliverProfile("Tap玩家", avatar)
            end,
        })
    end)
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
    ServerBootstrap.Start({
        Shared = Shared,
        GameConfig = GameConfig,
        ServerTuning = ServerTuning,
        ServerConfig = ServerConfig,
        InventoryRules = InventoryRules,
        RequestGuard = RequestGuard,
        ServerShop = ServerShop,
        ServerCropRules = ServerCropRules,
        ServerFarmState = ServerFarmState,
        ServerEconomyState = ServerEconomyState,
        ServerCommission = ServerCommission,
        ServerActivity = ServerActivity,
        ServerLeaderboard = ServerLeaderboard,
        ServerRewards = ServerRewards,
        ServerEconomyActions = ServerEconomyActions,
        ServerSteal = ServerSteal,
        GiftServer = GiftServer,
        SocialServer = SocialServer,
        ServerEventHandlers = ServerEventHandlers,
        ServerGlobals = ServerGlobals,
        SERVER_MUTATION_TALENT_BONUSES = SERVER_MUTATION_TALENT_BONUSES,
        DEFAULT_HARVEST_BAG_CAPACITY = DEFAULT_HARVEST_BAG_CAPACITY,
        MAX_HARVEST_BAG_CAPACITY = MAX_HARVEST_BAG_CAPACITY,
        BAG_CAPACITY_BONUSES = BAG_CAPACITY_BONUSES,
        connections = connections_,
        connectionUsers = connectionUsers_,
        setScene = function(scene) scene_ = scene end,
        getScene = function() return scene_ end,
        Send = Send,
        Now = Now,
        DeepCopy = DeepCopy,
        PickGiftSeedId = PickGiftSeedId,
        NormalizePlantIndex = NormalizePlantIndex,
        NormalizePlotIndex = NormalizePlotIndex,
        NormalizeLocalPos = NormalizeLocalPos,
        NormalizePositiveCount = NormalizePositiveCount,
        NormalizeUserId = NormalizeUserId,
        NormalizeEconomyState = NormalizeEconomyState,
        NormalizeFarmState = NormalizeFarmState,
        NormalizeActivityState = NormalizeActivityState,
        NormalizeTalentState = NormalizeTalentState,
        NormalizeProgressionState = NormalizeProgressionState,
        NormalizeDailyTaskState = NormalizeDailyTaskState,
        BuildInitialEconomyState = BuildInitialEconomyState,
        NextRevision = NextRevision,
        RollWeighted = RollWeighted,
        RandomRange = RandomRange,
        RandItem = RandItem,
        CopyNumericKeyMap = CopyNumericKeyMap,
        RecalculateAuthoritativeItemPrice = RecalculateAuthoritativeItemPrice,
        CalculateAuthFarmTourValue = CalculateAuthFarmTourValue,
        GetActivityRankInfo = GetActivityRankInfo,
        GetIncomeRankInfo = GetIncomeRankInfo,
        GetCurrentActivityCycleInfo = GetCurrentActivityCycleInfo,
        GetPreviousActivityCycleInfo = GetPreviousActivityCycleInfo,
        GetActivityConfig = GetActivityConfig,
        GetNicknameMap = GetNicknameMap,
        AddActivityRankCommit = AddActivityRankCommit,
        AddTourRankCommit = AddTourRankCommit,
        AddIncomeRankCommit = AddIncomeRankCommit,
        EnsureSeedShopState = EnsureSeedShopState,
        SendFullAvailableSeedShop = SendFullAvailableSeedShop,
        BroadcastFullAvailableSeedShop = BroadcastFullAvailableSeedShop,
        BuildSeedShopQuotaKey = BuildSeedShopQuotaKey,
        SendSeedShopState = SendSeedShopState,
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
        BuildVisitGardenFromAuthFarm = BuildVisitGardenFromAuthFarm,
        GetFarmPlot = GetFarmPlot,
        FindFarmCrop = FindFarmCrop,
        SendError = SendError,
        SendPlayerProfile = SendPlayerProfile,
        RequestEconomyState = ServerEconomyActions.RequestEconomyState,
        RequestAuthFarmState = ServerFarmState.RequestAuthFarmState,
        RequestLeaderboardAuthority = ServerLeaderboard.RequestLeaderboardAuthority,
        ClaimActivityRankRewardAuthority = ServerLeaderboard.ClaimActivityRankRewardAuthority,
        RequestSteal = ServerSteal.RequestSteal,
        GrantAdReward = ServerRewards.GrantAdReward,
        BuySeed = ServerEconomyActions.BuySeed,
        ClearPlayerSave = ServerEconomyActions.ClearPlayerSave,
        PlantSeedAuthority = ServerEconomyActions.PlantSeedAuthority,
        HarvestCropAuthority = ServerEconomyActions.HarvestCropAuthority,
        OpenSeedPackAuthority = ServerEconomyActions.OpenSeedPackAuthority,
        SellHarvested = ServerEconomyActions.SellHarvested,
        RequestCommissionsAuthority = ServerCommission.RequestCommissionsAuthority,
        CompleteCommissionAuthority = ServerCommission.CompleteCommissionAuthority,
        SubmitActivityCropAuthority = ServerActivity.SubmitActivityCropAuthority,
        ExchangeActivityRewardAuthority = ServerActivity.ExchangeActivityRewardAuthority,
        DrawActivityPackAuthority = ServerActivity.DrawActivityPackAuthority,
        ClaimDailyRewardAuthority = ServerRewards.ClaimDailyRewardAuthority,
        SynthesizePackAuthority = ServerRewards.SynthesizePackAuthority,
        UnlockTalentAuthority = ServerRewards.UnlockTalentAuthority,
        ExpandPlotAuthority = ServerRewards.ExpandPlotAuthority,
        GetConnectionKey = GetConnectionKey,
        GetConnectionUserId = GetConnectionUserId,
        ReadConnectionIdentity = ReadConnectionIdentity,
        RegisterConnectionUserId = RegisterConnectionUserId,
        ClearConnectionUserId = ClearConnectionUserId,
        GetRequestUserId = GetRequestUserId,
        ReadRequest = ReadRequest,
    })
end
