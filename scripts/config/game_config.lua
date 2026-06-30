-- ============================================================================
-- 游戏配置模块 (Game Config)
-- Grow A Garden
-- ============================================================================
-- 只存放静态配置与数值表，避免主流程、UI、业务逻辑直接耦合在 main.lua 中。
-- ============================================================================

local GameConfig = {}

GameConfig.CONFIG = {
    Title = "Grow A Garden 核心玩法原型",
    GridCols = 3,
    GridRows = 3,
    VisiblePlots = 9,
    InitialUnlockedPlots = 1,
    PlotSpacing = 3.05,
    PlotSize = 2.0,
    PlantableHalf = 0.60,
    ScatterRadius = 0.68,
    SeedMinDistance = 0.22,
    MaxCropsPerPlot = 10,
    SeedVisualY = 0.52,
    StartMoney = 150,
    FarmViewDistance = 12.0,
    FarmViewMinDistance = 8.0,
    FarmViewMaxDistance = 22.0,
    FarmViewYaw = -28.0,
    FarmViewPitch = 38.0,
    PlantViewDistance = 7.8,
    PlantViewMinDistance = 4.8,
    PlantViewMaxDistance = 11.5,
    PlantViewYaw = 0.0,
    PlantViewPitch = 55.0,
}

GameConfig.CROP_SCALE_RULES = {
    NaturalScaleMin = 0.54,
    NaturalScaleMax = 1.38,
    WeightScaleMin = 0.20,
    LightWeightScaleMax = 0.90,
    NormalWeightScaleMax = 1.20,
    LargeWeightScaleMax = 2.00,
    WeightScaleMax = 3.50,
    VisualWeightExponent = 0.62,
    PriceMultiplierMin = 0.04,
    PriceMultiplierMax = 12.0,
}

GameConfig.RARITY_COLORS = {
    ["普通"] = Color(0.50, 0.48, 0.42, 1.0),
    ["罕见"] = Color(0.30, 0.72, 0.38, 1.0),
    ["稀有"] = Color(0.30, 0.55, 0.88, 1.0),
    ["史诗"] = Color(0.62, 0.38, 0.82, 1.0),
    ["传奇"] = Color(0.88, 0.55, 0.15, 1.0),
}

GameConfig.PLANTS = {
    { name = "胡萝卜", rarity = "普通", seedPrice = 10, fruitPrice = 18, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 20, visual = "root", color = Color(1.0, 0.42, 0.08, 1.0) },
    { name = "番茄", rarity = "普通", seedPrice = 50, fruitPrice = 48, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 60, visual = "vine", color = Color(0.95, 0.08, 0.05, 1.0) },
    { name = "草莓", rarity = "罕见", seedPrice = 500, fruitPrice = 165, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 100, visual = "berry", color = Color(0.9, 0.05, 0.12, 1.0) },
    { name = "花椰菜", rarity = "罕见", seedPrice = 1000, fruitPrice = 260, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 150, visual = "cluster", color = Color(0.86, 0.93, 0.72, 1.0) },
    { name = "南瓜", rarity = "罕见", seedPrice = 1500, fruitPrice = 500, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 200, visual = "gourd", color = Color(1.0, 0.45, 0.02, 1.0) },
    { name = "凤梨", rarity = "罕见", seedPrice = 2000, fruitPrice = 850, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 250, visual = "pineapple", color = Color(0.95, 0.75, 0.18, 1.0) },
    { name = "郁金香", rarity = "稀有", seedPrice = 2300, fruitPrice = 3000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 360, visual = "flower", color = Color(0.9, 0.18, 0.45, 1.0) },
    { name = "西瓜", rarity = "稀有", seedPrice = 2500, fruitPrice = 4700, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 350, visual = "melon", color = Color(0.08, 0.55, 0.16, 1.0) },
    { name = "蘑菇", rarity = "稀有", seedPrice = 2800, fruitPrice = 6800, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 580, visual = "mushroom", color = Color(0.82, 0.18, 0.16, 1.0) },
    { name = "仙人掌", rarity = "稀有", seedPrice = 3000, fruitPrice = 8900, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 600, visual = "cactus", color = Color(0.12, 0.58, 0.22, 1.0) },
    { name = "波斯菊", rarity = "史诗", seedPrice = 7200, fruitPrice = 20500, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 1800, visual = "cosmos", color = Color(1.0, 0.35, 0.75, 1.0) },
    { name = "向日葵", rarity = "史诗", seedPrice = 7800, fruitPrice = 28000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 2100, visual = "sunflower", color = Color(1.0, 0.82, 0.08, 1.0) },
    { name = "辣椒", rarity = "史诗", seedPrice = 8200, fruitPrice = 38000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 2400, visual = "pepper", color = Color(0.95, 0.03, 0.03, 1.0) },
    { name = "百合", rarity = "史诗", seedPrice = 8500, fruitPrice = 48000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 2700, visual = "lily", color = Color(0.95, 0.88, 1.0, 1.0) },
    { name = "三色堇", rarity = "传奇", seedPrice = 50000, fruitPrice = 42500, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 7200, visual = "pansy", color = Color(0.45, 0.2, 0.95, 1.0) },
    { name = "玫瑰", rarity = "传奇", seedPrice = 66000, fruitPrice = 50000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 8400, visual = "rose", color = Color(0.9, 0.02, 0.12, 1.0) },
    { name = "蒲公英", rarity = "传奇", seedPrice = 68000, fruitPrice = 58500, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 9600, visual = "dandelion", color = Color(1.0, 0.93, 0.18, 1.0) },
    { name = "风信子", rarity = "传奇", seedPrice = 72000, fruitPrice = 67000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 10800, visual = "hyacinth", color = Color(0.38, 0.35, 1.0, 1.0) },
    { name = "绣球花", rarity = "传奇", seedPrice = 78000, fruitPrice = 75000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 12000, visual = "hydrangea", color = Color(0.35, 0.65, 1.0, 1.0) },
    { name = "杨桃", rarity = "传奇", seedPrice = 85000, fruitPrice = 81000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 12000, visual = "starfruit", color = Color(1.0, 0.9, 0.12, 1.0) },
    { name = "玉米", rarity = "普通", seedPrice = 100, fruitPrice = 28, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 400, visual = "corn", color = Color(0.95, 0.85, 0.2, 1.0) },
    { name = "葡萄", rarity = "普通", seedPrice = 200, fruitPrice = 70, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 300, visual = "grape", color = Color(0.4, 0.1, 0.55, 1.0) },
    { name = "芒果", rarity = "罕见", seedPrice = 2100, fruitPrice = 1250, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 280, visual = "mango", color = Color(1.0, 0.7, 0.1, 1.0) },
    { name = "香蕉", rarity = "罕见", seedPrice = 2200, fruitPrice = 1800, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 300, visual = "banana", color = Color(0.95, 0.9, 0.2, 1.0) },
    { name = "竹子", rarity = "稀有", seedPrice = 3300, fruitPrice = 12800, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 700, visual = "bamboo", color = Color(0.3, 0.7, 0.25, 1.0) },
    { name = "椰子", rarity = "稀有", seedPrice = 3500, fruitPrice = 17800, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 800, visual = "coconut", color = Color(0.45, 0.3, 0.15, 1.0) },
    { name = "杜鹃", rarity = "史诗", seedPrice = 9200, fruitPrice = 62000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 3000, visual = "azalea", color = Color(0.95, 0.2, 0.45, 1.0) },
    { name = "玉兰", rarity = "史诗", seedPrice = 9500, fruitPrice = 72000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 3300, visual = "magnolia", color = Color(0.98, 0.95, 0.92, 1.0) },
    { name = "牡丹", rarity = "传奇", seedPrice = 99000, fruitPrice = 89000, volumeProb = 0.0, colorProb = 0.09, specialProb = 0.025, growTime = 13200, visual = "peony", color = Color(0.95, 0.4, 0.6, 1.0) },

    -- 甜蜜蜜限定作物：糖果生态与蜂蜜魔法主题
    { name = "糖晶铃兰", rarity = "稀有", seedPrice = 3900, fruitPrice = 29000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.035, growTime = 900, visual = "lily", visualTheme = "crystal_sweet", activityTag = "sweet", limited = true, baseWeight = 0.42, sightBase = 520, color = Color(1.0, 0.64, 0.86, 1.0) },
    { name = "蜂巢曼德拉", rarity = "史诗", seedPrice = 9900, fruitPrice = 57000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.04, growTime = 3600, visual = "root", visualTheme = "honey_hive", activityTag = "sweet", limited = true, baseWeight = 1.35, sightBase = 940, color = Color(1.0, 0.72, 0.16, 1.0) },
    { name = "梦糖龙葵", rarity = "传奇", seedPrice = 85000, fruitPrice = 80000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.045, growTime = 13200, visual = "grape", visualTheme = "dream_candy", activityTag = "sweet", limited = true, baseWeight = 0.86, sightBase = 1780, color = Color(0.78, 0.34, 1.0, 1.0) },
    { name = "棉云莓塔", rarity = "稀有", seedPrice = 4200, fruitPrice = 33000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.036, growTime = 1000, visual = "berry", visualTheme = "cotton_berry", activityTag = "sweet", limited = true, baseWeight = 0.36, sightBase = 680, color = Color(1.0, 0.74, 0.94, 1.0) },
    { name = "焦糖星果", rarity = "史诗", seedPrice = 11000, fruitPrice = 65000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.042, growTime = 3900, visual = "starfruit", visualTheme = "caramel_star", activityTag = "sweet", limited = true, baseWeight = 0.72, sightBase = 1260, color = Color(1.0, 0.58, 0.16, 1.0) },
    { name = "圣代绣球", rarity = "传奇", seedPrice = 89000, fruitPrice = 87000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.048, growTime = 13200, visual = "hydrangea", visualTheme = "sundae_hydrangea", activityTag = "sweet", limited = true, baseWeight = 0.98, sightBase = 2300, color = Color(0.96, 0.82, 1.0, 1.0) },

    -- 外星基因限定作物：异星生态与发光器官主题
    { name = "脉冲孢子塔", rarity = "稀有", seedPrice = 4500, fruitPrice = 25000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.035, growTime = 1100, visual = "mushroom", visualTheme = "alien_pulse", activityTag = "alien", limited = true, baseWeight = 0.68, sightBase = 560, color = Color(0.36, 1.0, 0.42, 1.0) },
    { name = "异瞳星蕨", rarity = "史诗", seedPrice = 10500, fruitPrice = 56000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.04, growTime = 4200, visual = "flower", visualTheme = "alien_eye", activityTag = "alien", limited = true, baseWeight = 0.54, sightBase = 1120, color = Color(0.22, 0.62, 1.0, 1.0) },
    { name = "零重力胚果", rarity = "传奇", seedPrice = 78000, fruitPrice = 78000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.045, growTime = 14400, visual = "starfruit", visualTheme = "zero_gravity", activityTag = "alien", limited = true, baseWeight = 1.05, sightBase = 2100, color = Color(0.68, 0.92, 1.0, 1.0) },
    { name = "量子竹节", rarity = "稀有", seedPrice = 4800, fruitPrice = 29000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.036, growTime = 1200, visual = "bamboo", visualTheme = "quantum_bamboo", activityTag = "alien", limited = true, baseWeight = 0.82, sightBase = 720, color = Color(0.18, 1.0, 0.76, 1.0) },
    { name = "棱镜脑菇", rarity = "史诗", seedPrice = 13000, fruitPrice = 65000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.043, growTime = 4500, visual = "mushroom", visualTheme = "prism_brain", activityTag = "alien", limited = true, baseWeight = 0.64, sightBase = 1460, color = Color(0.56, 0.42, 1.0, 1.0) },
    { name = "星舰椰果", rarity = "传奇", seedPrice = 88000, fruitPrice = 85000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.05, growTime = 15600, visual = "coconut", visualTheme = "starship_coconut", activityTag = "alien", limited = true, baseWeight = 1.30, sightBase = 2700, color = Color(0.48, 0.88, 1.0, 1.0) },

    -- 黑暗来临限定作物：月影、幽灯与星蚀奇观主题
    { name = "月影莲", rarity = "稀有", seedPrice = 5500, fruitPrice = 37000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.04, growTime = 1300, visual = "lily", visualTheme = "moon_shadow_lotus", activityTag = "dark", limited = true, baseWeight = 0.48, sightBase = 640, color = Color(0.42, 0.36, 0.82, 1.0) },
    { name = "幽灯龙胆", rarity = "史诗", seedPrice = 12000, fruitPrice = 70000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.045, growTime = 4800, visual = "flower", visualTheme = "ghost_lantern", activityTag = "dark", limited = true, baseWeight = 0.58, sightBase = 1280, color = Color(0.24, 0.72, 0.92, 1.0) },
    { name = "星蚀王冠", rarity = "传奇", seedPrice = 85000, fruitPrice = 91000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.05, growTime = 16800, visual = "peony", visualTheme = "eclipse_crown", activityTag = "dark", limited = true, baseWeight = 0.90, sightBase = 2450, color = Color(0.74, 0.56, 1.0, 1.0) },
    { name = "夜露风信子", rarity = "稀有", seedPrice = 6500, fruitPrice = 41000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.041, growTime = 1500, visual = "hyacinth", visualTheme = "night_dew_hyacinth", activityTag = "dark", limited = true, baseWeight = 0.52, sightBase = 760, color = Color(0.32, 0.38, 0.92, 1.0) },
    { name = "影纱玫瑰", rarity = "史诗", seedPrice = 13500, fruitPrice = 76000, volumeProb = 0.0, colorProb = 0.10, specialProb = 0.046, growTime = 5100, visual = "rose", visualTheme = "shadow_veil_rose", activityTag = "dark", limited = true, baseWeight = 0.62, sightBase = 1580, color = Color(0.44, 0.12, 0.42, 1.0) },
    { name = "冥河杨桃", rarity = "传奇", seedPrice = 92000, fruitPrice = 96000, volumeProb = 0.0, colorProb = 0.11, specialProb = 0.052, growTime = 18000, visual = "starfruit", visualTheme = "styx_starfruit", activityTag = "dark", limited = true, baseWeight = 1.02, sightBase = 3000, color = Color(0.18, 0.22, 0.42, 1.0) },
}

-- 成熟时间平衡表。
-- 单位：秒。播种时还会叠加变异、天赋和地块加速修正。
GameConfig.GROW_A_GARDEN_GROW_TIMES = {
    ["胡萝卜"] = 20,
    ["番茄"] = 60,
    ["草莓"] = 100,
    ["花椰菜"] = 150,
    ["南瓜"] = 200,
    ["凤梨"] = 250,
    ["郁金香"] = 360,
    ["西瓜"] = 350,
    ["蘑菇"] = 580,
    ["仙人掌"] = 600,
    ["波斯菊"] = 1800,
    ["向日葵"] = 2100,
    ["辣椒"] = 2400,
    ["百合"] = 2700,
    ["三色堇"] = 7200,
    ["玫瑰"] = 8400,
    ["蒲公英"] = 9600,
    ["风信子"] = 10800,
    ["绣球花"] = 12000,
    ["杨桃"] = 12000,
    ["玉米"] = 400,
    ["葡萄"] = 300,
    ["芒果"] = 280,
    ["香蕉"] = 300,
    ["竹子"] = 700,
    ["椰子"] = 800,
    ["杜鹃"] = 3000,
    ["玉兰"] = 3300,
    ["牡丹"] = 13200,
    ["糖晶铃兰"] = 900,
    ["蜂巢曼德拉"] = 3600,
    ["梦糖龙葵"] = 13200,
    ["棉云莓塔"] = 1000,
    ["焦糖星果"] = 3900,
    ["圣代绣球"] = 13200,
    ["脉冲孢子塔"] = 1100,
    ["异瞳星蕨"] = 4200,
    ["零重力胚果"] = 14400,
    ["量子竹节"] = 1200,
    ["棱镜脑菇"] = 4500,
    ["星舰椰果"] = 15600,
    ["月影莲"] = 1300,
    ["幽灯龙胆"] = 4800,
    ["星蚀王冠"] = 16800,
    ["夜露风信子"] = 1500,
    ["影纱玫瑰"] = 5100,
    ["冥河杨桃"] = 18000,
}

for _, plant in ipairs(GameConfig.PLANTS) do
    local growTime = GameConfig.GROW_A_GARDEN_GROW_TIMES[plant.name]
    if growTime ~= nil then
        plant.growTime = growTime
    end
end

GameConfig.PLANT_BASE_WEIGHTS = {
    0.40, 0.30, 0.20, 1.20, 8.00, 1.50, 0.25, 6.00, 0.35, 2.00,
    0.20, 0.80, 0.15, 0.25, 0.18, 0.25, 0.10, 0.20, 0.50, 0.35,
    0.45, 0.25, 0.60, 0.70, 3.00, 1.20, 0.35, 0.45, 0.60,
}

-- 观光值：普通、标准重量、无变异作物的基础观赏价值。
-- 胡萝卜以 17 作为新手锚点；后续作物按稀有度、体积和视觉表现递增。
GameConfig.PLANT_SIGHT_BASE_VALUES = {
    17, 28, 48, 55, 75, 90, 140, 160, 170, 180,
    300, 360, 330, 390, 650, 760, 850, 950, 1100, 1250,
    22, 32, 100, 110, 210, 230, 430, 470, 1600,
}

GameConfig.SIGHT_SIZE_MULTIPLIERS = {
    Light = 0.85,
    Normal = 1.0,
    Large = 1.08,
    Giant = 1.18,
}

GameConfig.SIGHT_GROWTH_MULTIPLIERS = {
    seed = 0.1,
    sprout = 0.3,
    growing = 0.6,
    mature = 1.0,
}

GameConfig.LAND_UNLOCK_REQUIREMENTS = {
    [2] = { level = 2, gold = 600, tour = 180 },
    [3] = { level = 4, gold = 2200, tour = 550 },
    [4] = { level = 6, gold = 7500, tour = 1300 },
    [5] = { level = 9, gold = 25000, tour = 3000 },
    [6] = { level = 12, gold = 85000, tour = 6500 },
    [7] = { level = 16, gold = 260000, tour = 13000 },
    [8] = { level = 21, gold = 780000, tour = 25000 },
    [9] = { level = 26, gold = 2200000, tour = 45000 },
}
GameConfig.CONFIG.LAND_UNLOCK_REQUIREMENTS = GameConfig.LAND_UNLOCK_REQUIREMENTS

GameConfig.LAND_UNLOCK_SIGHT_REQUIREMENTS = {}
for plotIndex, requirement in pairs(GameConfig.LAND_UNLOCK_REQUIREMENTS) do
    GameConfig.LAND_UNLOCK_SIGHT_REQUIREMENTS[plotIndex] = requirement.tour
end
GameConfig.CONFIG.LAND_UNLOCK_SIGHT_REQUIREMENTS = GameConfig.LAND_UNLOCK_SIGHT_REQUIREMENTS

for i, weight in ipairs(GameConfig.PLANT_BASE_WEIGHTS) do
    if GameConfig.PLANTS[i] ~= nil then
        if GameConfig.PLANTS[i].baseWeight == nil then
            GameConfig.PLANTS[i].baseWeight = weight
        end
        if GameConfig.PLANTS[i].sightBase == nil then
            GameConfig.PLANTS[i].sightBase = GameConfig.PLANT_SIGHT_BASE_VALUES[i] or math.max(1, math.floor((GameConfig.PLANTS[i].fruitPrice or 10) * 0.5))
        end
    end
end

GameConfig.RARITY_ORDER = {
    ["普通"] = 1,
    ["罕见"] = 2,
    ["稀有"] = 3,
    ["史诗"] = 4,
    ["传奇"] = 5,
}

GameConfig.RARITY_PLANT_INDICES = {
    ["普通"] = { 1, 2, 21, 22 },
    ["罕见"] = { 3, 4, 5, 6, 23, 24 },
    ["稀有"] = { 7, 8, 9, 10, 25, 26, 30, 33, 36, 39, 42, 45 },
    ["史诗"] = { 11, 12, 13, 14, 27, 28, 31, 34, 37, 40, 43, 46 },
    ["传奇"] = { 15, 16, 17, 18, 19, 20, 29, 32, 35, 38, 41, 44, 47 },
}

GameConfig.SEED_PACK_CONFIG = {
    pack_common = {
        packId = "pack_common",
        packName = "普通种子包",
        packRarity = "普通",
        onceOpenCount = 1,
        seedBuff = 0,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_0.png",
        themeColor = {235, 235, 225, 255},
        weightPool = {
            { seedId = 1, weight = 205 }, { seedId = 2, weight = 205 }, { seedId = 21, weight = 205 }, { seedId = 22, weight = 205 },
            { seedId = 3, weight = 28 }, { seedId = 4, weight = 28 }, { seedId = 5, weight = 28 }, { seedId = 6, weight = 28 }, { seedId = 23, weight = 29 }, { seedId = 24, weight = 29 },
            { seedId = 7, weight = 2 }, { seedId = 8, weight = 2 }, { seedId = 9, weight = 2 }, { seedId = 10, weight = 2 }, { seedId = 25, weight = 1 }, { seedId = 26, weight = 1 },
        },
    },
    pack_uncommon = {
        packId = "pack_uncommon",
        packName = "罕见种子包",
        packRarity = "罕见",
        onceOpenCount = 1,
        seedBuff = 0,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_1.png",
        themeColor = {170, 220, 175, 255},
        weightPool = {
            { seedId = 1, weight = 63 }, { seedId = 2, weight = 63 }, { seedId = 21, weight = 62 }, { seedId = 22, weight = 62 },
            { seedId = 3, weight = 109 }, { seedId = 4, weight = 109 }, { seedId = 5, weight = 108 }, { seedId = 6, weight = 108 }, { seedId = 23, weight = 108 }, { seedId = 24, weight = 108 },
            { seedId = 7, weight = 15 }, { seedId = 8, weight = 15 }, { seedId = 9, weight = 15 }, { seedId = 10, weight = 15 }, { seedId = 25, weight = 15 }, { seedId = 26, weight = 15 },
            { seedId = 11, weight = 2 }, { seedId = 12, weight = 2 }, { seedId = 13, weight = 2 }, { seedId = 14, weight = 2 }, { seedId = 27, weight = 1 }, { seedId = 28, weight = 1 },
        },
    },
    pack_rare = {
        packId = "pack_rare",
        packName = "稀有种子包",
        packRarity = "稀有",
        onceOpenCount = 1,
        seedBuff = 0,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_2.png",
        themeColor = {160, 190, 240, 255},
        weightPool = {
            { seedId = 3, weight = 42 }, { seedId = 4, weight = 42 }, { seedId = 5, weight = 42 }, { seedId = 6, weight = 42 }, { seedId = 23, weight = 41 }, { seedId = 24, weight = 41 },
            { seedId = 7, weight = 100 }, { seedId = 8, weight = 100 }, { seedId = 9, weight = 100 }, { seedId = 10, weight = 100 }, { seedId = 25, weight = 100 }, { seedId = 26, weight = 100 },
            { seedId = 11, weight = 22 }, { seedId = 12, weight = 22 }, { seedId = 13, weight = 22 }, { seedId = 14, weight = 22 }, { seedId = 27, weight = 21 }, { seedId = 28, weight = 21 },
            { seedId = 15, weight = 3 }, { seedId = 16, weight = 3 }, { seedId = 17, weight = 3 }, { seedId = 18, weight = 3 }, { seedId = 19, weight = 3 }, { seedId = 20, weight = 3 }, { seedId = 29, weight = 2 },
        },
    },
    pack_epic = {
        packId = "pack_epic",
        packName = "史诗种子包",
        packRarity = "史诗",
        onceOpenCount = 1,
        seedBuff = 0,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_3.png",
        themeColor = {205, 165, 240, 255},
        weightPool = {
            { seedId = 7, weight = 34 }, { seedId = 8, weight = 34 }, { seedId = 9, weight = 33 }, { seedId = 10, weight = 33 }, { seedId = 25, weight = 33 }, { seedId = 26, weight = 33 },
            { seedId = 11, weight = 117 }, { seedId = 12, weight = 117 }, { seedId = 13, weight = 117 }, { seedId = 14, weight = 117 }, { seedId = 27, weight = 116 }, { seedId = 28, weight = 116 },
            { seedId = 15, weight = 15 }, { seedId = 16, weight = 15 }, { seedId = 17, weight = 14 }, { seedId = 18, weight = 14 }, { seedId = 19, weight = 14 }, { seedId = 20, weight = 14 }, { seedId = 29, weight = 14 },
        },
    },
    pack_legendary = {
        packId = "pack_legendary",
        packName = "传奇种子包",
        packRarity = "传奇",
        onceOpenCount = 1,
        seedBuff = 0,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_4.png",
        themeColor = {245, 185, 95, 255},
        weightPool = {
            { seedId = 11, weight = 59 }, { seedId = 12, weight = 59 }, { seedId = 13, weight = 58 }, { seedId = 14, weight = 58 }, { seedId = 27, weight = 58 }, { seedId = 28, weight = 58 },
            { seedId = 15, weight = 93 }, { seedId = 16, weight = 93 }, { seedId = 17, weight = 93 }, { seedId = 18, weight = 93 }, { seedId = 19, weight = 93 }, { seedId = 20, weight = 93 }, { seedId = 29, weight = 92 },
        },
    },
    pack_alien_gene = {
        packId = "pack_alien_gene",
        packName = "外星基因种子包",
        packRarity = "传奇",
        onceOpenCount = 1,
        seedBuff = 0.01,
        allowLimitedSeeds = true,
        stackMax = 999,
        packIcon = "image/seedpack_icon/seedpack_4.png",
        themeColor = {155, 245, 215, 255},
        weightPool = {
            { seedId = 36, weight = 38 }, { seedId = 37, weight = 23 }, { seedId = 38, weight = 7 },
            { seedId = 39, weight = 22 }, { seedId = 40, weight = 12 }, { seedId = 41, weight = 4 },
            { seedId = 30, weight = 8 }, { seedId = 42, weight = 8 },
        },
    },
}

GameConfig.SEED_PACK_BY_RARITY = {
    ["普通"] = "pack_common",
    ["罕见"] = "pack_uncommon",
    ["稀有"] = "pack_rare",
    ["史诗"] = "pack_epic",
    ["传奇"] = "pack_legendary",
}

GameConfig.DAILY_TASK_CONFIG = {
    { key = "plant", title = "播种 3 颗种子", target = 3 },
    { key = "harvest", title = "收获 3 株成熟作物", target = 3 },
    { key = "sell", title = "出售 1 次背包作物", target = 1 },
}

GameConfig.COLOR_MUTATIONS = {
    { key = "yellow", name = "黄色", color = Color(1.0, 0.88, 0.08, 1.0), multiplier = 1.3, sightMultiplier = 1.5, timeMultiplier = 1.03, prefixes = { "琥珀", "日耀", "鎏金", "圣辉", "光铸" } },
    { key = "blue", name = "蓝色", color = Color(0.12, 0.45, 1.0, 1.0), multiplier = 1.5, sightMultiplier = 1.6, timeMultiplier = 1.05, prefixes = { "冰海", "钴蓝", "苍穹", "霜魂", "星穹" } },
    { key = "red", name = "红色", color = Color(1.0, 0.05, 0.02, 1.0), multiplier = 1.7, sightMultiplier = 1.7, timeMultiplier = 1.06, prefixes = { "熔岩", "猩红", "朱砂", "血怒", "赤狱" } },
    { key = "white", name = "白色", color = Color(0.96, 0.96, 1.0, 1.0), multiplier = 1.8, sightMultiplier = 1.8, timeMultiplier = 1.08, prefixes = { "骨白", "月霜", "珍珠", "圣洁", "灵魄" } },
    { key = "purple", name = "紫色", color = Color(0.58, 0.18, 1.0, 1.0), multiplier = 2.0, sightMultiplier = 2.0, timeMultiplier = 1.10, prefixes = { "暮光", "水晶", "幽影", "虚空", "暗裔" } },
    { key = "black", name = "黑色", color = Color(0.02, 0.02, 0.035, 1.0), multiplier = 2.5, sightMultiplier = 2.5, timeMultiplier = 1.15, prefixes = { "暗烬", "墨玉", "永夜", "湮灭", "影噬" } },
}

GameConfig.SPECIAL_MUTATIONS = {
    { key = "wet", name = "潮湿变异", multiplier = 2.0, sightMultiplier = 2.4, timeMultiplier = 1.05, prefixes = { "露浸", "泽地", "潮涌", "海裔", "深渊" } },
    { key = "frozen", name = "冷冻变异", multiplier = 2.5, sightMultiplier = 2.8, timeMultiplier = 1.08, prefixes = { "寒霜", "冰棱", "凛冬", "霜脉", "永冻" } },
    { key = "cloud", name = "云朵变异", multiplier = 3.0, sightMultiplier = 3.0, timeMultiplier = 1.10, prefixes = { "积云", "羽絮", "棉糖", "天穹" } },
    { key = "chocolate", name = "巧克力变异", multiplier = 3.5, sightMultiplier = 3.2, timeMultiplier = 1.12, prefixes = { "可可", "熔浆", "糖壳", "丝滑" } },
    { key = "pollen", name = "花粉变异", multiplier = 4.0, sightMultiplier = 3.8, timeMultiplier = 1.15, prefixes = { "粉雾", "授粉", "蜜腺", "蝶吻" } },
    { key = "candy", name = "糖果变异", multiplier = 4.5, sightMultiplier = 4.0, timeMultiplier = 1.16, prefixes = { "糖晶", "蜜糖", "霜甜", "软糖" } },
    { key = "honey", name = "蜂蜜变异", exclusiveActivity = "sweet", multiplier = 5.5, sightMultiplier = 4.8, timeMultiplier = 1.18, prefixes = { "流蜜", "蜂巢", "金蜜", "蜜蜡" } },
    { key = "glow", name = "荧光变异", multiplier = 5.0, sightMultiplier = 4.2, timeMultiplier = 1.20, prefixes = { "磷光", "夜辉", "萤火", "鬼火", "邪光" } },
    { key = "stardust", name = "星尘变异", multiplier = 6.0, sightMultiplier = 10.0, timeMultiplier = 1.25, prefixes = { "星屑", "彗尾", "银河", "星轨", "天坠" } },
    { key = "ceramic", name = "陶瓷变异", multiplier = 7.0, sightMultiplier = 5.0, timeMultiplier = 1.30, prefixes = { "青瓷", "素烧", "裂纹", "珐琅" } },
    { key = "rainbow", name = "彩虹变异", multiplier = 10.0, sightMultiplier = 6.0, timeMultiplier = 1.40, prefixes = { "虹霓", "幻光", "棱镜", "虹彩", "神谕" } },
    { key = "devour", name = "吞噬变异", exclusiveActivity = "dark", multiplier = 9.0, sightMultiplier = 9.0, timeMultiplier = 1.38, prefixes = { "噬光", "裂口", "深渊", "饥夜" } },
    { key = "void", name = "虚空变异", multiplier = 12.0, sightMultiplier = 12.0, timeMultiplier = 1.45, prefixes = { "裂隙", "以太", "吞噬", "低语" } },
    { key = "gold", name = "黄金变异", multiplier = 15.0, sightMultiplier = 8.0, timeMultiplier = 1.50, prefixes = { "镀金", "钱袋", "耀金", "神铸", "王权" } },
}

GameConfig.ACTIVITY_CONFIG = {
    cycleDays = 3,
    sequence = { "sweet", "alien", "dark" },
    activities = {
        sweet = {
            id = "sweet",
            name = "甜蜜蜜",
            badge = "甜蜜循环",
            desc = "活动期间播种作物可能出现糖果变异和蜂蜜变异，上交这两类变异作物获得甜蜜值，并兑换限定奇异作物种子。",
            candyChance = 0.045,
            honeyChance = 0.025,
            limitedSeeds = { 30, 31, 32, 33, 34, 35 },
            leaderboardBase = 180,
            backgroundColor = {255, 244, 228, 248},
            badgeColor = {255, 206, 158, 255},
            chipColor = {255, 224, 238, 255},
            exchangeRewards = {
                { id = "sweet_crystal", name = "糖晶铃兰种子 x1", type = "seed", plantIndex = 30, count = 1, cost = 65, limit = 8 },
                { id = "hive_mandra", name = "蜂巢曼德拉种子 x1", type = "seed", plantIndex = 31, count = 1, cost = 160, limit = 4 },
                { id = "dream_nightshade", name = "梦糖龙葵种子 x1", type = "seed", plantIndex = 32, count = 1, cost = 360, limit = 2 },
                { id = "cotton_berry", name = "棉云莓塔种子 x1", type = "seed", plantIndex = 33, count = 1, cost = 65, limit = 6 },
                { id = "caramel_star", name = "焦糖星果种子 x1", type = "seed", plantIndex = 34, count = 1, cost = 160, limit = 3 },
                { id = "sundae_hydrangea", name = "圣代绣球种子 x1", type = "seed", plantIndex = 35, count = 1, cost = 360, limit = 1 },
                { id = "sweet_pack", name = "稀有种子包 x1", type = "pack", packId = "pack_rare", count = 1, cost = 90, limit = 5 },
            },
        },
        alien = {
            id = "alien",
            name = "外星基因",
            badge = "基因抽取",
            desc = "活动期间收获作物可获得外星基因，消耗基因抽取种子包，有概率得到外星基因专属种子包和异星限定作物。",
            limitedSeeds = { 36, 37, 38, 39, 40, 41 },
            drawCost = 1,
            drawCostTen = 10,
            leaderboardBase = 150,
            backgroundColor = {232, 248, 238, 248},
            badgeColor = {170, 245, 190, 255},
            chipColor = {210, 245, 238, 255},
            drawPool = {
                { type = "pack", packId = "pack_common", weight = 42, name = "普通种子包" },
                { type = "pack", packId = "pack_uncommon", weight = 30, name = "罕见种子包" },
                { type = "pack", packId = "pack_rare", weight = 12, name = "稀有种子包" },
                { type = "pack", packId = "pack_alien_gene", weight = 7, name = "外星基因种子包" },
                { type = "seed", plantIndex = 36, weight = 4, name = "脉冲孢子塔种子" },
                { type = "seed", plantIndex = 37, weight = 2, name = "异瞳星蕨种子" },
                { type = "seed", plantIndex = 38, weight = 0.5, name = "零重力胚果种子" },
                { type = "seed", plantIndex = 39, weight = 2.5, name = "量子竹节种子" },
                { type = "seed", plantIndex = 40, weight = 1, name = "棱镜脑菇种子" },
                { type = "seed", plantIndex = 41, weight = 0.5, name = "星舰椰果种子" },
            },
        },
        dark = {
            id = "dark",
            name = "黑暗来临",
            badge = "永夜异变",
            desc = "活动期间会出现吞噬变异，虚空变异概率提高。收获吞噬变异作物时，有概率掉落月影、幽灯与星蚀主题的黑暗限定种子。",
            devourChance = 0.035,
            extraVoidChance = 0.022,
            limitedSeeds = { 42, 43, 44, 45, 46, 47 },
            darkSeedPool = { 42, 43, 44, 45, 46, 47 },
            darkSeedDropRates = { 0.008, 0.014, 0.024, 0.036, 0.05 },
            leaderboardBase = 130,
            backgroundColor = {232, 224, 240, 248},
            badgeColor = {204, 180, 235, 255},
            chipColor = {226, 214, 238, 255},
        },
    },
}

local SECONDS_PER_DAY = 86400

function GameConfig.GetActivityCycleInfo(now)
    local config = GameConfig.ACTIVITY_CONFIG or {}
    local sequence = config.sequence or { "sweet", "alien", "dark" }
    local cycleDays = math.max(1, math.floor(tonumber(config.cycleDays or 3) or 3))
    local duration = cycleDays * SECONDS_PER_DAY
    local currentTime = math.max(0, math.floor(tonumber(now or (os and os.time and os.time()) or 0) or 0))
    local cycleIndex = math.floor(currentTime / duration)
    local activityIndex = (cycleIndex % math.max(1, #sequence)) + 1
    local activityId = sequence[activityIndex] or sequence[1] or "sweet"
    local cycleStart = cycleIndex * duration
    local cycleEnd = cycleStart + duration
    return {
        activityId = activityId,
        cycleId = tostring(activityId) .. "_" .. tostring(cycleIndex),
        cycleIndex = cycleIndex,
        activityIndex = activityIndex,
        cycleStart = cycleStart,
        cycleEnd = cycleEnd,
        duration = duration,
        timeLeft = math.max(0, cycleEnd - currentTime),
    }
end

function GameConfig.GetActiveActivityId(now)
    return GameConfig.GetActivityCycleInfo(now).activityId
end

function GameConfig.GetActivityTimeLeftSeconds(now)
    return GameConfig.GetActivityCycleInfo(now).timeLeft
end

return GameConfig
