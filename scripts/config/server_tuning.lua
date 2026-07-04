-- ============================================================================
-- 服务端静态配置 (Server Tuning)
-- Grow A Garden — 纯服务器权威模式的统一数值源
-- ============================================================================

local ServerConfig = {}

ServerConfig.Tuning = {
    dailyStealLimit = 5,
    dailyStealAdLimit = 5,
    dailySeedPackAdLimit = 5,
    dailyMatureAdLimit = 5,
    adStealBonus = 5,
    adRarePackCount = 5,
    dailyGiftLimit = 5,
    maxSocialRows = 20,
    friendLimit = 50,
    startGold = 150,
    maxOpenPackCount = 50,
    maxGiftCount = 1,
    globalShopUid = 858557875,
    seedShopRefreshInterval = 300,
    incomeRankRefreshInterval = 7 * 24 * 60 * 60,
    activityRankRewardTop = 20,
}

ServerConfig.Talent = {
    MAX_LEVEL = 30,
    LEVEL_EXP_TABLE = {
        [1]  = 30, [2]  = 50, [3]  = 80, [4]  = 120, [5]  = 170,
        [6]  = 230, [7]  = 300, [8]  = 380, [9]  = 470, [10] = 570,
        [11] = 680, [12] = 800, [13] = 940, [14] = 1100, [15] = 1280,
        [16] = 1480, [17] = 1700, [18] = 1950, [19] = 2230, [20] = 2550,
        [21] = 2900, [22] = 3280, [23] = 3700, [24] = 4160, [25] = 4660,
        [26] = 5200, [27] = 5780, [28] = 6400, [29] = 7060,
    },
    RARITY_BASE_EXP = { ["普通"] = 5, ["罕见"] = 10, ["稀有"] = 18, ["史诗"] = 30, ["传奇"] = 50 },
    CONFIG = {
        { id = "drop_rate_1", cost = 1, goldCost = 500, requires = nil }, { id = "drop_rate_2", cost = 1, goldCost = 2000, requires = "drop_rate_1" }, { id = "drop_rate_3", cost = 2, goldCost = 8000, requires = "drop_rate_2" }, { id = "drop_rate_4", cost = 2, goldCost = 30000, requires = "drop_rate_3" }, { id = "drop_rate_5", cost = 3, goldCost = 100000, requires = "drop_rate_4" },
        { id = "grow_speed_1", cost = 1, goldCost = 800, requires = nil }, { id = "grow_speed_2", cost = 1, goldCost = 3000, requires = "grow_speed_1" }, { id = "grow_speed_3", cost = 2, goldCost = 12000, requires = "grow_speed_2" }, { id = "grow_speed_4", cost = 2, goldCost = 50000, requires = "grow_speed_3" }, { id = "grow_speed_5", cost = 3, goldCost = 160000, requires = "grow_speed_4" },
        { id = "sell_bonus_1", cost = 1, goldCost = 1000, requires = nil }, { id = "sell_bonus_2", cost = 1, goldCost = 4000, requires = "sell_bonus_1" }, { id = "sell_bonus_3", cost = 2, goldCost = 16000, requires = "sell_bonus_2" }, { id = "sell_bonus_4", cost = 2, goldCost = 70000, requires = "sell_bonus_3" }, { id = "sell_bonus_5", cost = 3, goldCost = 220000, requires = "sell_bonus_4" },
        { id = "mutation_1", cost = 1, goldCost = 1200, requires = nil }, { id = "mutation_2", cost = 1, goldCost = 5000, requires = "mutation_1" }, { id = "mutation_3", cost = 2, goldCost = 20000, requires = "mutation_2" }, { id = "mutation_4", cost = 2, goldCost = 90000, requires = "mutation_3" }, { id = "mutation_5", cost = 3, goldCost = 300000, requires = "mutation_4" },
        { id = "bag_capacity_1", cost = 1, goldCost = 600, requires = nil }, { id = "bag_capacity_2", cost = 1, goldCost = 2500, requires = "bag_capacity_1" }, { id = "bag_capacity_3", cost = 2, goldCost = 10000, requires = "bag_capacity_2" }, { id = "bag_capacity_4", cost = 2, goldCost = 40000, requires = "bag_capacity_3" }, { id = "bag_capacity_5", cost = 3, goldCost = 120000, requires = "bag_capacity_4" },
    },
}

ServerConfig.DailyReward = {
    PACK_WEIGHTS = {
        { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 32 },
        { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 9 },
        { packId = "pack_legendary", weight = 2 },
    },
    SYNTHESIS_MAP = {
        pack_common = "pack_uncommon",
        pack_uncommon = "pack_rare",
        pack_rare = "pack_epic",
        pack_epic = "pack_legendary",
    },
}

ServerConfig.Commission = {
    STATE_KEY = "garden_commission_state_v1",
    REFRESH_INTERVAL = 30 * 60,
    COUNT = 4,
    CUSTOMERS = { "露露", "阿麦", "青木", "莓莓", "小枫", "云朵商人", "花园旅人", "星屑收藏家" },
    COLOR_REQUIREMENTS = { "yellow", "blue", "red", "white", "purple", "black" },
    SPECIAL_REQUIREMENTS = { "wet", "frozen", "cloud", "chocolate", "pollen", "glow", "stardust", "ceramic", "rainbow", "void", "gold" },
    PACK_DIFFICULTY = {
        pack_common = { mutationKinds = { "basic" }, minWeightScale = { 0.90, 1.20 } },
        pack_uncommon = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.00, 1.40 } },
        pack_rare = { mutationKinds = { "color", "basic" }, minWeightScale = { 1.05, 1.55 } },
        pack_epic = { mutationKinds = { "color", "special" }, minWeightScale = { 1.35, 2.20 } },
        pack_legendary = { mutationKinds = { "special", "giant" }, minWeightScale = { 2.00, 3.60 } },
    },
    REWARD_POOLS = {
        ["普通"] = { { packId = "pack_common", weight = 94 }, { packId = "pack_uncommon", weight = 6 } },
        ["罕见"] = { { packId = "pack_common", weight = 35 }, { packId = "pack_uncommon", weight = 55 }, { packId = "pack_rare", weight = 10 } },
        ["稀有"] = { { packId = "pack_common", weight = 18 }, { packId = "pack_uncommon", weight = 30 }, { packId = "pack_rare", weight = 45 }, { packId = "pack_epic", weight = 7 } },
        ["史诗"] = { { packId = "pack_common", weight = 8 }, { packId = "pack_uncommon", weight = 18 }, { packId = "pack_rare", weight = 32 }, { packId = "pack_epic", weight = 38 }, { packId = "pack_legendary", weight = 4 } },
        ["传奇"] = { { packId = "pack_common", weight = 3 }, { packId = "pack_uncommon", weight = 10 }, { packId = "pack_rare", weight = 22 }, { packId = "pack_epic", weight = 40 }, { packId = "pack_legendary", weight = 25 } },
    },
}

return ServerConfig
