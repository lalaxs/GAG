-- ============================================================================
-- 服务端启动引导 (Server Bootstrap)
-- Grow A Garden
-- ============================================================================

local ServerConfig = require("config.server_tuning")
local ServerUtils = require("server.server_utils")
local SaveLoginReconcile = require("server.save_login_reconcile")
local SaveEconomyHealth = require("server.save_economy_health")

local ServerBootstrap = {}

function ServerBootstrap.Start(ctx)
    math.randomseed(os.time())
    ctx.setScene(Scene())
    ctx.ServerShop.Init({
        Shared = ctx.Shared,
        PlayerStateService = ctx.PlayerStateService,
        GameConfig = ctx.GameConfig,
        globalShopUid = ctx.ServerTuning.globalShopUid,
        refreshInterval = ctx.ServerTuning.seedShopRefreshInterval,
        getConnections = function() return ctx.connections end,
        send = ctx.Send,
        now = ctx.Now,
        deepCopy = ctx.DeepCopy,
    })
    ctx.ServerCropRules.Init({
        GameConfig = ctx.GameConfig,
        InventoryRules = ctx.InventoryRules,
        Now = ctx.Now,
        NormalizePlantIndex = ctx.NormalizePlantIndex,
        NormalizePlotIndex = ctx.NormalizePlotIndex,
        NormalizeLocalPos = ctx.NormalizeLocalPos,
        RollWeighted = ctx.RollWeighted,
        RandomRange = ctx.RandomRange,
        RandItem = ctx.RandItem,
        ClampValue = ServerUtils.ClampValue,
    })
    ctx.ServerFarmState.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        Send = ctx.Send,
        Now = ctx.Now,
        NormalizePlotIndex = ctx.NormalizePlotIndex,
        NormalizeLocalPos = ctx.NormalizeLocalPos,
        RecalculateAuthoritativeItemPrice = ctx.RecalculateAuthoritativeItemPrice,
        BuildUidKeyCandidates = ServerUtils.BuildUidKeyCandidates,
        GetCanonicalUidKey = ServerUtils.GetCanonicalUidKey,
    })
    ctx.ServerEconomyState.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        startGold = ctx.ServerTuning.startGold,
        talentMaxLevel = ctx.ServerConfig.Talent.MAX_LEVEL,
        serverMutationTalentBonuses = ctx.SERVER_MUTATION_TALENT_BONUSES,
        defaultHarvestBagCapacity = ctx.DEFAULT_HARVEST_BAG_CAPACITY,
        maxHarvestBagCapacity = ctx.MAX_HARVEST_BAG_CAPACITY,
        bagCapacityBonuses = ctx.BAG_CAPACITY_BONUSES,
        Now = ctx.Now,
        CopyNumericKeyMap = ctx.CopyNumericKeyMap,
        RecalculateAuthoritativeItemPrice = ctx.RecalculateAuthoritativeItemPrice,
        CalculateAuthFarmTourValue = ctx.CalculateAuthFarmTourValue,
        GetActivityRankInfo = ctx.GetActivityRankInfo,
        GetIncomeRankInfo = ctx.GetIncomeRankInfo,
    })
    ctx.ServerCommission.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        PlayerStateService = ctx.PlayerStateService,
        Send = ctx.Send,
        Now = ctx.Now,
        RandItem = ctx.RandItem,
        RandomRange = ctx.RandomRange,
        RollWeighted = ctx.RollWeighted,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        NormalizeUserId = ctx.NormalizeUserId,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
        NextRevision = ctx.NextRevision,
    })
    ctx.ServerActivity.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        Send = ctx.Send,
        Now = ctx.Now,
        NormalizeActivityState = ctx.NormalizeActivityState,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
        NormalizePositiveCount = ctx.NormalizePositiveCount,
        NormalizePlantIndex = ctx.NormalizePlantIndex,
        IsValidPackId = ctx.IsValidPackId,
        RollWeighted = ctx.RollWeighted,
        NextRevision = ctx.NextRevision,
        AddActivityRankCommit = ctx.AddActivityRankCommit,
    })
    ctx.ServerLeaderboard.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        SocialServer = ctx.SocialServer,
        Send = ctx.Send,
        Now = ctx.Now,
        GetCurrentActivityCycleInfo = ctx.GetCurrentActivityCycleInfo,
        GetPreviousActivityCycleInfo = ctx.GetPreviousActivityCycleInfo,
        GetActivityConfig = ctx.GetActivityConfig,
        NormalizePositiveCount = ctx.NormalizePositiveCount,
        NormalizeFarmState = ctx.NormalizeFarmState,
        ScoreFarmState = ctx.ServerFarmState.ScoreFarmState,
        FarmLooksEmpty = ctx.ServerFarmState.FarmLooksEmpty,
        CalculateAuthFarmTourValue = ctx.CalculateAuthFarmTourValue,
        GetNicknameMap = ctx.GetNicknameMap,
        incomeRankRefreshInterval = ctx.ServerTuning.incomeRankRefreshInterval,
        activityRankRewardTop = ctx.ServerTuning.activityRankRewardTop,
    })
    ctx.ServerRewards.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        SocialServer = ctx.SocialServer,
        Send = ctx.Send,
        Now = ctx.Now,
        NormalizeTalentState = ctx.NormalizeTalentState,
        NormalizeProgressionState = ctx.NormalizeProgressionState,
        NormalizeDailyTaskState = ctx.NormalizeDailyTaskState,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        NormalizeFarmState = ctx.NormalizeFarmState,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
        GetFarmPlot = ctx.GetFarmPlot,
        SyncProgressionTourValueFromFarm = ctx.SyncProgressionTourValueFromFarm,
        AddTourRankCommit = ctx.AddTourRankCommit,
        NextRevision = ctx.NextRevision,
        RollWeighted = ctx.RollWeighted,
        NormalizePlotIndex = ctx.NormalizePlotIndex,
        dailyStealLimit = ctx.ServerTuning.dailyStealLimit,
        dailyStealAdLimit = ctx.ServerTuning.dailyStealAdLimit,
        dailySeedPackAdLimit = ctx.ServerTuning.dailySeedPackAdLimit,
        dailyMatureAdLimit = ctx.ServerTuning.dailyMatureAdLimit,
        adStealBonus = ctx.ServerTuning.adStealBonus,
        adRarePackCount = ctx.ServerTuning.adRarePackCount,
    })
    ctx.ServerPlayerDataCache.Init({
        Now = ctx.Now,
    })
    ctx.PlayerStateService.Init({
        Shared = ctx.Shared,
        Now = ctx.Now,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        NormalizeFarmState = ctx.NormalizeFarmState,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
        ScoreEconomyRecord = ctx.ServerEconomyState.ScoreEconomyRecord,
        ScoreEconomyContent = ctx.ServerEconomyState.ScoreEconomyContent,
        ScoreFarmState = ctx.ServerFarmState.ScoreFarmState,
        FarmLooksEmpty = ctx.ServerFarmState.FarmLooksEmpty,
    })
    ctx.ServerEconomyActions.Init({
        Shared = ctx.Shared,
        GameConfig = ctx.GameConfig,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        PlayerDataCache = ctx.ServerPlayerDataCache,
        Send = ctx.Send,
        SendError = ctx.SendError,
        Now = ctx.Now,
        NormalizePlantIndex = ctx.NormalizePlantIndex,
        NormalizePositiveCount = ctx.NormalizePositiveCount,
        NormalizePlotIndex = ctx.NormalizePlotIndex,
        NormalizeLocalPos = ctx.NormalizeLocalPos,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
        NormalizeFarmState = ctx.NormalizeFarmState,
        GetFarmPlot = ctx.GetFarmPlot,
        NormalizeDailyTaskState = ctx.NormalizeDailyTaskState,
        NextRevision = ctx.NextRevision,
        AddTourRankCommit = ctx.AddTourRankCommit,
        AddActivityRankCommit = ctx.AddActivityRankCommit,
        AddIncomeRankCommit = ctx.AddIncomeRankCommit,
        EnsureSeedShopState = ctx.EnsureSeedShopState,
        SendFullAvailableSeedShop = ctx.SendFullAvailableSeedShop,
        BroadcastFullAvailableSeedShop = ctx.BroadcastFullAvailableSeedShop,
        BuildSeedShopQuotaKey = ctx.BuildSeedShopQuotaKey,
        globalShopUid = ctx.ServerTuning.globalShopUid,
        GetServerMutationTalentBonus = ctx.GetServerMutationTalentBonus,
        GetMaxCropsPerPlot = ctx.GetMaxCropsPerPlot,
        BuildAuthoritativeCrop = ctx.BuildAuthoritativeCrop,
        SyncProgressionTourValueFromFarm = ctx.SyncProgressionTourValueFromFarm,
        FindFarmCropFromHarvestPayload = ctx.FindFarmCropFromHarvestPayload,
        RefreshAuthCrop = ctx.RefreshAuthCrop,
        GetHarvestBagCapacityFromState = ctx.GetHarvestBagCapacityFromState,
        AddServerHarvestExp = ctx.AddServerHarvestExp,
        RollHarvestDropPack = ctx.RollHarvestDropPack,
        ApplyActivityHarvestReward = ctx.ApplyActivityHarvestReward,
        RollSeedFromPack = ctx.RollSeedFromPack,
        IsValidPackId = ctx.IsValidPackId,
        IsValidSellMode = ctx.IsValidSellMode,
        maxOpenPackCount = ctx.ServerTuning.maxOpenPackCount,
        BuildUidKeyCandidates = ServerUtils.BuildUidKeyCandidates,
        GetCanonicalUidKey = ServerUtils.GetCanonicalUidKey,
    })
    ctx.ServerSteal.Init({
        Shared = ctx.Shared,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        Send = ctx.Send,
        Now = ctx.Now,
        NormalizePlantIndex = ctx.NormalizePlantIndex,
        NormalizePositiveCount = ctx.NormalizePositiveCount,
        NormalizeUserId = ctx.NormalizeUserId,
        GetFarmPlot = ctx.GetFarmPlot,
        FindFarmCrop = ctx.FindFarmCrop,
        RefreshAuthCrop = ctx.RefreshAuthCrop,
        GetMaxCropsPerPlot = ctx.GetMaxCropsPerPlot,
        dailyStealLimit = ctx.ServerTuning.dailyStealLimit,
    })
    ctx.GiftServer.Init({
        Shared = ctx.Shared,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        dailyGiftLimit = ctx.ServerTuning.dailyGiftLimit,
        dailyStealLimit = ctx.ServerTuning.dailyStealLimit,
        dailySeedPackAdLimit = ctx.ServerTuning.dailySeedPackAdLimit,
        dailyMatureAdLimit = ctx.ServerTuning.dailyMatureAdLimit,
        maxGiftCount = ctx.ServerTuning.maxGiftCount,
        normalizePlantIndex = ctx.NormalizePlantIndex,
        normalizeEconomyState = ctx.NormalizeEconomyState,
        buildInitialEconomyState = ctx.BuildInitialEconomyState,
        nextRevision = ctx.NextRevision,
        pickGiftSeedId = ctx.PickGiftSeedId,
        getSeedName = function(seedId)
            local plant = ctx.GameConfig.PLANTS[tonumber(seedId or 0) or 0]
            return plant and plant.name or "神秘"
        end,
    })
    ctx.SocialServer.Init({
        Shared = ctx.Shared,
        RequestGuard = ctx.RequestGuard,
        PlayerStateService = ctx.PlayerStateService,
        maxSocialRows = ctx.ServerTuning.maxSocialRows,
        friendLimit = ctx.ServerTuning.friendLimit,
        dailyStealLimit = ctx.ServerTuning.dailyStealLimit,
        dailySeedPackAdLimit = ctx.ServerTuning.dailySeedPackAdLimit,
        dailyMatureAdLimit = ctx.ServerTuning.dailyMatureAdLimit,
        normalizePositiveCount = ctx.NormalizePositiveCount,
        normalizePlantIndex = ctx.NormalizePlantIndex,
        normalizeUserId = ctx.NormalizeUserId,
        buildUidKeyCandidates = ServerUtils.BuildUidKeyCandidates,
        getCanonicalUidKey = ServerUtils.GetCanonicalUidKey,
        buildVisitGardenFromAuthFarm = ctx.BuildVisitGardenFromAuthFarm,
    })

    SaveLoginReconcile.Init({
        Shared = ctx.Shared,
        NormalizeEconomyState = ctx.NormalizeEconomyState,
        NormalizeFarmState = ctx.ServerFarmState.NormalizeFarmState,
        FarmLooksEmpty = ctx.ServerFarmState.FarmLooksEmpty,
        NormalizeCommissionState = function(state)
            return ctx.ServerCommission.NormalizeCommissionState(state, 1)
        end,
        CommissionStateKey = ServerConfig.Commission.STATE_KEY,
    })
    SaveEconomyHealth.Init({
        Shared = ctx.Shared,
        BuildInitialEconomyState = ctx.BuildInitialEconomyState,
    })
    ctx.ServerEventHandlers.Init({
        Shared = ctx.Shared,
        RequestGuard = ctx.RequestGuard,
        SocialServer = ctx.SocialServer,
        GiftServer = ctx.GiftServer,
        connections = ctx.connections,
        connectionUsers = ctx.connectionUsers,
        scene = ctx.getScene(),
        GetConnectionKey = ctx.GetConnectionKey,
        GetConnectionUserId = ctx.GetConnectionUserId,
        ReadConnectionIdentity = ctx.ReadConnectionIdentity,
        RegisterConnectionUserId = ctx.RegisterConnectionUserId,
        ClearConnectionUserId = ctx.ClearConnectionUserId,
        GetRequestUserId = ctx.GetRequestUserId,
        NormalizeUserId = ctx.NormalizeUserId,
        ReadRequest = ctx.ReadRequest,
        Send = ctx.Send,
        SendSeedShopState = ctx.SendSeedShopState,
        SendPlayerProfile = ctx.SendPlayerProfile,
        PlayerStateService = ctx.PlayerStateService,
        SaveLoginReconcile = SaveLoginReconcile,
        RequestEconomyState = ctx.RequestEconomyState,
        RequestAuthFarmState = ctx.RequestAuthFarmState,
        RequestLeaderboardAuthority = ctx.RequestLeaderboardAuthority,
        ClaimActivityRankRewardAuthority = ctx.ClaimActivityRankRewardAuthority,
        RequestSteal = ctx.RequestSteal,
        GrantAdReward = ctx.GrantAdReward,
        BuySeed = ctx.BuySeed,
        ClearPlayerSave = ctx.ClearPlayerSave,
        PlantSeedAuthority = ctx.PlantSeedAuthority,
        HarvestCropAuthority = ctx.HarvestCropAuthority,
        OpenSeedPackAuthority = ctx.OpenSeedPackAuthority,
        SellHarvested = ctx.SellHarvested,
        RequestCommissionsAuthority = ctx.RequestCommissionsAuthority,
        CompleteCommissionAuthority = ctx.CompleteCommissionAuthority,
        SubmitActivityCropAuthority = ctx.SubmitActivityCropAuthority,
        ExchangeActivityRewardAuthority = ctx.ExchangeActivityRewardAuthority,
        DrawActivityPackAuthority = ctx.DrawActivityPackAuthority,
        ClaimDailyRewardAuthority = ctx.ClaimDailyRewardAuthority,
        SynthesizePackAuthority = ctx.SynthesizePackAuthority,
        UnlockTalentAuthority = ctx.UnlockTalentAuthority,
        ExpandPlotAuthority = ctx.ExpandPlotAuthority,
    })
    ctx.Shared.RegisterServerEvents()
    ctx.ServerGlobals.BindEventHandlers(ctx.ServerEventHandlers)
    _G.HandleServerPlayerStateUpdate = function(eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        ctx.PlayerStateService.Update(dt)
    end
    SubscribeToEvent("Update", "HandleServerPlayerStateUpdate")
    ctx.ServerEventHandlers.Register()
    print("[社交花园服务端] 权威农场服务已启动")
end

return ServerBootstrap
