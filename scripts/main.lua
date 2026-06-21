require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local Shop = require("shop")
local SeedVisual = require("seed_visual")

-- ═══════ 天空盒背景 ═══════
local SkyUtils = require "urhox-libs.Rendering.SkyUtils"
-- ═══════════════════════════════

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Widget|nil
local moneyLabel_ = nil
---@type Widget|nil
local seedLabel_ = nil
---@type Widget|nil
local plotLabel_ = nil
---@type Widget|nil
local actionLabel_ = nil
---@type Widget|nil
local actionButton_ = nil
---@type Widget|nil
local inventoryLabel_ = nil
---@type Widget|nil
local helpLabel_ = nil
---@type Widget|nil
local toastLabel_ = nil
---@type Widget|nil
local seedPackBadgeLabel_ = nil
local seedButtons_ = {}

local CONFIG = {
    Title = "Grow A Garden 核心玩法原型",
    GridCols = 1,
    GridRows = 1,
    VisiblePlots = 1,
    InitialUnlockedPlots = 1,
    PlotSpacing = 2.8,
    PlotSize = 2.0,
    ScatterRadius = 0.68,
    SeedMinDistance = 0.22,
    MaxCropsPerPlot = 10,
    SeedVisualY = 0.52,
    StartMoney = 100000,
    FarmViewDistance = 12.0,
    FarmViewMinDistance = 8.0,
    FarmViewMaxDistance = 22.0,
    FarmViewYaw = -28.0,
    FarmViewPitch = 38.0,
    PlantViewDistance = 7.8,
    PlantViewYaw = 0.0,
    PlantViewPitch = 55.0,
}

local RARITY_COLORS = {
    ["普通"] = Color(0.92, 0.92, 0.88, 1.0),
    ["罕见"] = Color(0.25, 0.95, 0.35, 1.0),
    ["稀有"] = Color(0.25, 0.55, 1.0, 1.0),
    ["史诗"] = Color(0.75, 0.35, 1.0, 1.0),
    ["传奇"] = Color(1.0, 0.58, 0.08, 1.0),
}

local PLANTS = {
    { name = "胡萝卜", rarity = "普通", seedPrice = 10, fruitPrice = 20, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 8, visual = "root", color = Color(1.0, 0.42, 0.08, 1.0) },
    { name = "番茄", rarity = "普通", seedPrice = 20, fruitPrice = 40, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 10, visual = "vine", color = Color(0.95, 0.08, 0.05, 1.0) },
    { name = "草莓", rarity = "罕见", seedPrice = 50, fruitPrice = 100, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 12, visual = "berry", color = Color(0.9, 0.05, 0.12, 1.0) },
    { name = "花椰菜", rarity = "罕见", seedPrice = 100, fruitPrice = 200, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 14, visual = "cluster", color = Color(0.86, 0.93, 0.72, 1.0) },
    { name = "南瓜", rarity = "罕见", seedPrice = 200, fruitPrice = 400, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 16, visual = "gourd", color = Color(1.0, 0.45, 0.02, 1.0) },
    { name = "凤梨", rarity = "罕见", seedPrice = 500, fruitPrice = 1000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 18, visual = "pineapple", color = Color(0.95, 0.75, 0.18, 1.0) },
    { name = "郁金香", rarity = "稀有", seedPrice = 500, fruitPrice = 1000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 18, visual = "flower", color = Color(0.9, 0.18, 0.45, 1.0) },
    { name = "西瓜", rarity = "稀有", seedPrice = 800, fruitPrice = 1600, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 20, visual = "melon", color = Color(0.08, 0.55, 0.16, 1.0) },
    { name = "蘑菇", rarity = "稀有", seedPrice = 1000, fruitPrice = 2000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 21, visual = "mushroom", color = Color(0.82, 0.18, 0.16, 1.0) },
    { name = "仙人掌", rarity = "稀有", seedPrice = 1200, fruitPrice = 2400, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 22, visual = "cactus", color = Color(0.12, 0.58, 0.22, 1.0) },
    { name = "波斯菊", rarity = "史诗", seedPrice = 1500, fruitPrice = 3000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 24, visual = "cosmos", color = Color(1.0, 0.35, 0.75, 1.0) },
    { name = "向日葵", rarity = "史诗", seedPrice = 1800, fruitPrice = 3600, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 25, visual = "sunflower", color = Color(1.0, 0.82, 0.08, 1.0) },
    { name = "辣椒", rarity = "史诗", seedPrice = 2000, fruitPrice = 4000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 26, visual = "pepper", color = Color(0.95, 0.03, 0.03, 1.0) },
    { name = "百合", rarity = "史诗", seedPrice = 2500, fruitPrice = 5000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 28, visual = "lily", color = Color(0.95, 0.88, 1.0, 1.0) },
    { name = "三色堇", rarity = "传奇", seedPrice = 3000, fruitPrice = 6000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 30, visual = "pansy", color = Color(0.45, 0.2, 0.95, 1.0) },
    { name = "玫瑰", rarity = "传奇", seedPrice = 3500, fruitPrice = 7000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 32, visual = "rose", color = Color(0.9, 0.02, 0.12, 1.0) },
    { name = "蒲公英", rarity = "传奇", seedPrice = 3500, fruitPrice = 7000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 32, visual = "dandelion", color = Color(1.0, 0.93, 0.18, 1.0) },
    { name = "风信子", rarity = "传奇", seedPrice = 5000, fruitPrice = 10000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 35, visual = "hyacinth", color = Color(0.38, 0.35, 1.0, 1.0) },
    { name = "绣球花", rarity = "传奇", seedPrice = 5000, fruitPrice = 10000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 35, visual = "hydrangea", color = Color(0.35, 0.65, 1.0, 1.0) },
    { name = "杨桃", rarity = "传奇", seedPrice = 10000, fruitPrice = 20000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 40, visual = "starfruit", color = Color(1.0, 0.9, 0.12, 1.0) },
    { name = "玉米", rarity = "普通", seedPrice = 15, fruitPrice = 30, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 9, visual = "corn", color = Color(0.95, 0.85, 0.2, 1.0) },
    { name = "葡萄", rarity = "普通", seedPrice = 25, fruitPrice = 50, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 11, visual = "grape", color = Color(0.4, 0.1, 0.55, 1.0) },
    { name = "芒果", rarity = "罕见", seedPrice = 80, fruitPrice = 160, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 14, visual = "mango", color = Color(1.0, 0.7, 0.1, 1.0) },
    { name = "香蕉", rarity = "罕见", seedPrice = 150, fruitPrice = 300, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 15, visual = "banana", color = Color(0.95, 0.9, 0.2, 1.0) },
    { name = "竹子", rarity = "稀有", seedPrice = 600, fruitPrice = 1200, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 19, visual = "bamboo", color = Color(0.3, 0.7, 0.25, 1.0) },
    { name = "椰子", rarity = "稀有", seedPrice = 900, fruitPrice = 1800, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 20, visual = "coconut", color = Color(0.45, 0.3, 0.15, 1.0) },
    { name = "杜鹃", rarity = "史诗", seedPrice = 1600, fruitPrice = 3200, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 25, visual = "azalea", color = Color(0.95, 0.2, 0.45, 1.0) },
    { name = "玉兰", rarity = "史诗", seedPrice = 2200, fruitPrice = 4400, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 27, visual = "magnolia", color = Color(0.98, 0.95, 0.92, 1.0) },
    { name = "牡丹", rarity = "传奇", seedPrice = 8000, fruitPrice = 16000, volumeProb = 0.05, colorProb = 0.05, specialProb = 0.01, growTime = 36, visual = "peony", color = Color(0.95, 0.4, 0.6, 1.0) },
}

local PLANT_BASE_WEIGHTS = {
    0.40, 0.30, 0.20, 1.20, 8.00, 1.50, 0.25, 6.00, 0.35, 2.00,
    0.20, 0.80, 0.15, 0.25, 0.18, 0.25, 0.10, 0.20, 0.50, 0.35,
    0.45, 0.25, 0.60, 0.70, 3.00, 1.20, 0.35, 0.45, 0.60,
}

for i, weight in ipairs(PLANT_BASE_WEIGHTS) do
    if PLANTS[i] ~= nil then
        PLANTS[i].baseWeight = weight
    end
end

local RARITY_ORDER = {
    ["普通"] = 1,
    ["罕见"] = 2,
    ["稀有"] = 3,
    ["史诗"] = 4,
    ["传奇"] = 5,
}

local RARITY_PLANT_INDICES = {
    ["普通"] = { 1, 2, 21, 22 },
    ["罕见"] = { 3, 4, 5, 6, 23, 24 },
    ["稀有"] = { 7, 8, 9, 10, 25, 26 },
    ["史诗"] = { 11, 12, 13, 14, 27, 28 },
    ["传奇"] = { 15, 16, 17, 18, 19, 20, 29 },
}

local SEED_PACK_CONFIG = {
    daily_basic = {
        packId = "daily_basic",
        packName = "日常普通种子礼包",
        packType = "daily",
        getWay = "每日任务",
        onceOpenCount = 5,
        seedBuff = 0,
        stackMax = 999,
        themeColor = {245, 232, 198, 255},
        weightPool = {
            { seedId = 1, weight = 150 }, { seedId = 2, weight = 150 }, { seedId = 21, weight = 150 }, { seedId = 22, weight = 150 },
            { seedId = 3, weight = 58 }, { seedId = 4, weight = 58 }, { seedId = 5, weight = 58 }, { seedId = 6, weight = 58 }, { seedId = 23, weight = 59 }, { seedId = 24, weight = 59 },
            { seedId = 7, weight = 8 }, { seedId = 8, weight = 8 }, { seedId = 9, weight = 8 }, { seedId = 10, weight = 8 }, { seedId = 25, weight = 9 }, { seedId = 26, weight = 9 },
        },
    },
    silver_common = {
        packId = "silver_common",
        packName = "银质・普通礼包",
        packType = "silver_普通",
        getWay = "普通收集成就",
        onceOpenCount = 3,
        seedBuff = 0.01,
        stackMax = 999,
        themeColor = {205, 205, 195, 255},
        weightPool = { { seedId = 1, weight = 260 }, { seedId = 21, weight = 260 }, { seedId = 2, weight = 240 }, { seedId = 22, weight = 240 } },
    },
    silver_uncommon = {
        packId = "silver_uncommon",
        packName = "银质・罕见礼包",
        packType = "silver_罕见",
        getWay = "罕见收集成就",
        onceOpenCount = 3,
        seedBuff = 0.01,
        stackMax = 999,
        themeColor = {170, 220, 175, 255},
        weightPool = { { seedId = 3, weight = 170 }, { seedId = 4, weight = 170 }, { seedId = 5, weight = 160 }, { seedId = 6, weight = 160 }, { seedId = 23, weight = 170 }, { seedId = 24, weight = 170 } },
    },
    silver_rare = {
        packId = "silver_rare",
        packName = "银质・稀有礼包",
        packType = "silver_稀有",
        getWay = "稀有收集成就",
        onceOpenCount = 3,
        seedBuff = 0.01,
        stackMax = 999,
        themeColor = {160, 190, 240, 255},
        weightPool = { { seedId = 7, weight = 165 }, { seedId = 8, weight = 165 }, { seedId = 9, weight = 170 }, { seedId = 10, weight = 165 }, { seedId = 25, weight = 165 }, { seedId = 26, weight = 170 } },
    },
    silver_epic = {
        packId = "silver_epic",
        packName = "银质・史诗礼包",
        packType = "silver_史诗",
        getWay = "史诗收集成就",
        onceOpenCount = 3,
        seedBuff = 0.01,
        stackMax = 999,
        themeColor = {205, 165, 240, 255},
        weightPool = { { seedId = 11, weight = 167 }, { seedId = 12, weight = 167 }, { seedId = 13, weight = 167 }, { seedId = 14, weight = 167 }, { seedId = 27, weight = 166 }, { seedId = 28, weight = 166 } },
    },
    silver_legendary = {
        packId = "silver_legendary",
        packName = "银质・传奇礼包",
        packType = "silver_传奇",
        getWay = "传奇收集成就",
        onceOpenCount = 3,
        seedBuff = 0.01,
        stackMax = 999,
        themeColor = {245, 185, 95, 255},
        weightPool = { { seedId = 15, weight = 143 }, { seedId = 16, weight = 143 }, { seedId = 17, weight = 143 }, { seedId = 18, weight = 143 }, { seedId = 19, weight = 143 }, { seedId = 20, weight = 143 }, { seedId = 29, weight = 142 } },
    },
}

local SILVER_PACK_BY_RARITY = {
    ["普通"] = "silver_common",
    ["罕见"] = "silver_uncommon",
    ["稀有"] = "silver_rare",
    ["史诗"] = "silver_epic",
    ["传奇"] = "silver_legendary",
}

local DAILY_TASK_CONFIG = {
    { key = "plant", title = "播种 3 颗种子", target = 3 },
    { key = "harvest", title = "收获 3 株成熟作物", target = 3 },
    { key = "sell", title = "出售 1 次背包作物", target = 1 },
}

local SEED_STACK_MAX = 999

local COLOR_MUTATIONS = {
    { key = "yellow", name = "黄色", color = Color(1.0, 0.88, 0.08, 1.0), prefixes = { "琥珀", "日耀", "鎏金", "圣辉", "光铸" } },
    { key = "red", name = "红色", color = Color(1.0, 0.05, 0.02, 1.0), prefixes = { "熔岩", "猩红", "朱砂", "血怒", "赤狱" } },
    { key = "purple", name = "紫色", color = Color(0.58, 0.18, 1.0, 1.0), prefixes = { "暮光", "水晶", "幽影", "虚空", "暗裔" } },
    { key = "blue", name = "蓝色", color = Color(0.12, 0.45, 1.0, 1.0), prefixes = { "冰海", "钴蓝", "苍穹", "霜魂", "星穹" } },
    { key = "white", name = "白色", color = Color(0.96, 0.96, 1.0, 1.0), prefixes = { "骨白", "月霜", "珍珠", "圣洁", "灵魄" } },
    { key = "black", name = "黑色", color = Color(0.02, 0.02, 0.035, 1.0), prefixes = { "暗烬", "墨玉", "永夜", "湮灭", "影噬" } },
}

local SPECIAL_MUTATIONS = {
    { key = "rainbow", name = "彩虹变异", multiplier = 8, timeMultiplier = 1.35, prefixes = { "虹霓", "幻光", "棱镜", "虹彩", "神谕" } },
    { key = "glow", name = "荧光变异", multiplier = 5, timeMultiplier = 1.2, prefixes = { "磷光", "夜辉", "萤火", "鬼火", "邪光" } },
    { key = "wet", name = "潮湿变异", multiplier = 2, timeMultiplier = 1.08, prefixes = { "露浸", "泽地", "潮涌", "海裔", "深渊" } },
    { key = "stardust", name = "星尘变异", multiplier = 5, timeMultiplier = 1.25, prefixes = { "星屑", "彗尾", "银河", "星轨", "天坠" } },
    { key = "gold", name = "黄金变异", multiplier = 10, timeMultiplier = 1.45, prefixes = { "镀金", "钱袋", "耀金", "神铸", "王权" } },
    { key = "frozen", name = "冷冻变异", multiplier = 2, timeMultiplier = 1.1, prefixes = { "寒霜", "冰棱", "凛冬", "霜脉", "永冻" } },
    { key = "cloud", name = "云朵变异", multiplier = 2, timeMultiplier = 1.08, prefixes = { "积云", "羽絮", "棉糖", "天穹" } },
    { key = "chocolate", name = "巧克力变异", multiplier = 2, timeMultiplier = 1.05, prefixes = { "可可", "熔浆", "糖壳", "丝滑" } },
    { key = "ceramic", name = "陶瓷变异", multiplier = 2, timeMultiplier = 1.1, prefixes = { "青瓷", "素烧", "裂纹", "珐琅" } },
    { key = "pollen", name = "花粉变异", multiplier = 2, timeMultiplier = 1.05, prefixes = { "粉雾", "授粉", "蜜腺", "蝶吻" } },
    { key = "void", name = "虚空变异", multiplier = 8, timeMultiplier = 1.35, prefixes = { "裂隙", "以太", "吞噬", "低语" } },
}

local materials_ = {}
local plots_ = {}
local selectedPlot_ = 1
local selectedSeed_ = 1
local money_ = CONFIG.StartMoney
local seedBag_ = {}
local seedBagBuffs_ = {}
local harvested_ = {}
local seedPacks_ = {}
local collectedPlants_ = {}
local silverRewardClaimed_ = {}
local dailyTaskState_ = {
    progress = { plant = 0, harvest = 0, sell = 0 },
    rewardClaimed = false,
}
local seedPackModal_ = nil
local taskModal_ = nil
local seedPackReveal_ = nil
local seedPackPanelOpen_ = false
local seedPackResultTitle_ = nil
local seedPackResultItems_ = nil
local selectedBagItem_ = nil
local ViewMode = {
    FARM = 1,
    PLANT = 2,
}
local viewMode_ = ViewMode.FARM
local cameraYaw_ = CONFIG.FarmViewYaw
local cameraPitch_ = CONFIG.FarmViewPitch
local cameraDistance_ = CONFIG.FarmViewDistance
local unlockedPlotCount_ = CONFIG.InitialUnlockedPlots
local uiRefreshTimer_ = 0
local uiInitialized_ = false
local plantTab_ = "seed"  -- "seed" | "harvest" | "bag"
local gameTime_ = 0
local toastTimer_ = 0
local suppressNextWorldTap_ = false
local touchGestureActive_ = false
local lastPinchDistance_ = 0
local RefreshUI = nil
local ShowToast = nil
local RebuildUI = nil
local SelectPlotByDelta = nil
local ClearBagPreview = nil
local OpenSeedPackHub = nil
local OpenTaskPanel = nil

local function RandItem(list)
    return list[math.random(1, #list)]
end

local function RandomRange(minValue, maxValue)
    return minValue + math.random() * (maxValue - minValue)
end

local function RollCropWeightScale()
    local r = math.random()
    if r < 0.25 then
        return RandomRange(0.45, 0.8), "Light"
    elseif r < 0.80 then
        return RandomRange(0.8, 1.25), "Normal"
    elseif r < 0.97 then
        return RandomRange(1.25, 2.5), "Large"
    end
    return RandomRange(3.0, 6.0), "Giant"
end

local function GetWeightBonusForPlot(plotIndex)
    return 1.0
end

local function AddSeedToBag(plantIndex, count, buff)
    if plantIndex == nil or PLANTS[plantIndex] == nil then return 0 end
    count = count or 1
    buff = buff or 0
    local current = seedBag_[plantIndex] or 0
    local addCount = math.min(count, SEED_STACK_MAX - current)
    if addCount <= 0 then return 0 end
    seedBag_[plantIndex] = current + addCount
    if buff > 0 then
        seedBagBuffs_[plantIndex] = (seedBagBuffs_[plantIndex] or 0) + addCount
    end
    return addCount
end

local function RemoveSeedFromBag(plantIndex)
    local owned = seedBag_[plantIndex] or 0
    if owned <= 0 then return 0 end
    seedBag_[plantIndex] = owned - 1
    local buffCount = seedBagBuffs_[plantIndex] or 0
    if buffCount > 0 then
        seedBagBuffs_[plantIndex] = buffCount - 1
        return 0.01
    end
    return 0
end

local function CountSeedPacks()
    local total = 0
    for packId, count in pairs(seedPacks_) do
        if SEED_PACK_CONFIG[packId] ~= nil then
            total = total + count
        end
    end
    return total
end

local function AddSeedPack(packId, count)
    local cfg = SEED_PACK_CONFIG[packId]
    if cfg == nil then return false end
    count = count or 1
    local current = seedPacks_[packId] or 0
    seedPacks_[packId] = math.min(cfg.stackMax or 999, current + count)
    print(string.format("[种子包] 获得 %s x%d", cfg.packName, count))
    return true
end

local function RollSeedFromPack(packCfg)
    local totalWeight = 0
    for _, item in ipairs(packCfg.weightPool) do
        totalWeight = totalWeight + item.weight
    end
    local roll = math.random() * totalWeight
    local cursor = 0
    for _, item in ipairs(packCfg.weightPool) do
        cursor = cursor + item.weight
        if roll <= cursor then
            return item.seedId
        end
    end
    return packCfg.weightPool[#packCfg.weightPool].seedId
end

local function IsTaskCompleted(taskCfg)
    return (dailyTaskState_.progress[taskCfg.key] or 0) >= taskCfg.target
end

local function AreAllDailyTasksCompleted()
    for _, task in ipairs(DAILY_TASK_CONFIG) do
        if not IsTaskCompleted(task) then
            return false
        end
    end
    return true
end

local function AddDailyProgress(key, amount)
    if dailyTaskState_.progress[key] == nil then return end
    amount = amount or 1
    dailyTaskState_.progress[key] = math.min(99, dailyTaskState_.progress[key] + amount)
end

local function IsRarityCollected(rarity)
    local list = RARITY_PLANT_INDICES[rarity]
    if list == nil then return false end
    for _, plantIndex in ipairs(list) do
        if not collectedPlants_[plantIndex] then
            return false
        end
    end
    return true
end

local function CheckSilverPackRewards()
    for rarity, packId in pairs(SILVER_PACK_BY_RARITY) do
        if not silverRewardClaimed_[rarity] and IsRarityCollected(rarity) then
            silverRewardClaimed_[rarity] = true
            AddSeedPack(packId, 1)
            ShowToast("完成" .. rarity .. "收集，获得" .. SEED_PACK_CONFIG[packId].packName)
        end
    end
end

local function HasSpecial(mutation, key)
    for _, item in ipairs(mutation.specials) do
        if item.key == key then
            return true
        end
    end
    return false
end

local function CreateMaterial(name, color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.55, 0.55, 0.55, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.55))
    if emissive ~= nil then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    materials_[name] = mat
    return mat
end

local function CreateTransparentMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.8, 0.8, 0.8, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    materials_[name] = mat
    return mat
end

local function CreateUnlitMaterial(name, color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    materials_[name] = mat
    return mat
end

local function AddModel(parent, name, modelPath, position, scale, material)
    local node = parent:CreateChild(name)
    node.position = position
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", modelPath))
    model:SetMaterial(material)
    model.castShadows = true
    return node
end

local function InitMaterials()
    CreateMaterial("grass", Color(0.12, 0.42, 0.16, 1.0), 0.0, 0.9)
    CreateMaterial("grassTop", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.55)
    CreateMaterial("soilSide", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.78)
    CreateMaterial("soil", Color(0.45, 0.28, 0.12, 1.0), 0.0, 0.72)
    CreateMaterial("soilLocked", Color(0.34, 0.37, 0.34, 1.0), 0.0, 0.85)
    CreateMaterial("soilSelected", Color(0.67, 0.42, 0.2, 1.0), 0.0, 0.58)
    CreateMaterial("seed", Color(0.32, 0.18, 0.075, 1.0), 0.0, 0.62)
    CreateMaterial("path", Color(0.48, 0.36, 0.22, 1.0), 0.0, 0.8)
    CreateMaterial("stem", Color(0.14, 0.55, 0.18, 1.0), 0.0, 0.65)
    CreateMaterial("leaf", Color(0.08, 0.72, 0.19, 1.0), 0.0, 0.55)
    CreateMaterial("wood", Color(0.45, 0.25, 0.1, 1.0), 0.0, 0.72)
    CreateMaterial("gold", Color(1.0, 0.68, 0.12, 1.0), 1.0, 0.18, Color(0.25, 0.15, 0.02, 1.0))
    CreateMaterial("frozen", Color(0.55, 0.88, 1.0, 1.0), 0.0, 0.08, Color(0.04, 0.16, 0.25, 1.0))
    CreateMaterial("glow", Color(0.45, 0.15, 1.0, 1.0), 0.0, 0.18, Color(0.55, 0.12, 1.2, 1.0))
    CreateMaterial("chocolate", Color(0.24, 0.1, 0.035, 1.0), 0.0, 0.38)
    CreateMaterial("ceramic", Color(0.9, 0.92, 0.86, 1.0), 0.0, 0.08)
    CreateMaterial("void", Color(0.01, 0.006, 0.02, 1.0), 0.0, 0.4, Color(0.14, 0.02, 0.35, 1.0))
    CreateUnlitMaterial("select", Color(0.46, 0.82, 0.42, 1.0))
    CreateTransparentMaterial("waterDrop", Color(0.2, 0.65, 1.0, 0.62))
    CreateTransparentMaterial("cloud", Color(0.92, 0.95, 1.0, 0.5))
    CreateUnlitMaterial("star", Color(1.0, 0.9, 0.3, 1.0))
    CreateUnlitMaterial("pollen", Color(1.0, 0.82, 0.12, 1.0))
end

local function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.48, 0.52, 0.48)
    zone.fogColor = Color(0.75, 0.88, 0.72, 1.0)  -- 与天空盒地平线色一致，远处自然过渡
    zone.fogStart = 55.0
    zone.fogEnd = 120.0

    local lightNode = scene_:CreateChild("Sun")
    lightNode.direction = Vector3(0.45, -1.0, 0.55)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.94, 0.82)
    light.castShadows = true
    light.shadowBias = BiasParameters(0.00025, 0.5)
    light.shadowCascade = CascadeParameters(10.0, 30.0, 90.0, 0.0, 0.8)

    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.1
    camera_.farClip = 300.0
    camera_.fov = 45.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))
    renderer.hdrRendering = true
end

-- ═══════ 天空盒背景（程序化渐变） ═══════
local function CreateSkybox()
    if scene_ == nil then return end

    -- 动物森友会风格：柔和的浅绿→白→浅绿渐变
    SkyUtils.CreateGradientSky(scene_, {
        zenith   = Color(0.55, 0.78, 0.58),  -- 天顶：柔和绿色
        horizon  = Color(0.75, 0.88, 0.72),  -- 地平线：浅绿白（与 fogColor 一致）
        ground   = Color(0.55, 0.72, 0.52),  -- 地面：稍深绿色
        skyExp   = 0.6,                       -- 渐变柔和
        hdrBoost = 2.0,                       -- 补偿 ACES 色调映射
    })

    print("[BG] 渐变天空盒已创建")
end
-- ═══════════════════════════════

local function UpdateCamera()
    if cameraNode_ == nil then return end
    local yaw = math.rad(cameraYaw_)
    local pitch = math.rad(cameraPitch_)
    -- 种植模式下注视点下移，让地块在屏幕中偏上显示
    local targetY = viewMode_ == ViewMode.PLANT and -0.3 or 0.7
    local target = Vector3(0, targetY, 0)
    local x = math.sin(yaw) * math.cos(pitch) * cameraDistance_
    local y = math.sin(pitch) * cameraDistance_
    local z = -math.cos(yaw) * math.cos(pitch) * cameraDistance_
    cameraNode_.position = target + Vector3(x, y, z)
    cameraNode_:LookAt(target)
end

local function EnterPlantView()
    viewMode_ = ViewMode.PLANT
    cameraYaw_ = CONFIG.PlantViewYaw
    cameraPitch_ = CONFIG.PlantViewPitch
    cameraDistance_ = CONFIG.PlantViewDistance
    UpdateCamera()
    ShowToast("进入种植模式，点击田地播种或收获")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function EnterFarmView()
    viewMode_ = ViewMode.FARM
    selectedBagItem_ = nil
    if ClearBagPreview ~= nil then
        ClearBagPreview()
    end
    cameraYaw_ = CONFIG.FarmViewYaw
    cameraPitch_ = CONFIG.FarmViewPitch
    cameraDistance_ = CONFIG.FarmViewDistance
    UpdateCamera()
    ShowToast("自由查看农场")
    if RebuildUI ~= nil then RebuildUI() end
    RefreshUI(true)
end

local function PlotWorldPosition(index)
    local col = ((index - 1) % CONFIG.GridCols) + 1
    local row = math.floor((index - 1) / CONFIG.GridCols) + 1
    local startX = -((CONFIG.GridCols - 1) * CONFIG.PlotSpacing) * 0.5
    local startZ = -((CONFIG.GridRows - 1) * CONFIG.PlotSpacing) * 0.5
    return Vector3(startX + (col - 1) * CONFIG.PlotSpacing, 0.42, startZ + (row - 1) * CONFIG.PlotSpacing)
end

local function CreateSelectionFrame(plot)
    local root = plot.node:CreateChild("SelectionFrame")
    root.enabled = false
    plot.selection = root
end

local function CreateRoundedPlotSurface(plotNode, material)
    local moundModels = {}

    local function addPiece(name, modelPath, position, scale, pieceMaterial, collect)
        local node = plotNode:CreateChild(name)
        node.position = position
        node.scale = scale
        local model = node:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", modelPath))
        model:SetMaterial(pieceMaterial)
        model.castShadows = false
        if collect then
            table.insert(moundModels, model)
        end
    end

    local function addRoundedRect(prefix, y, h, w, d, r, pieceMaterial, collect)
        local ox = w * 0.5 - r
        local oz = d * 0.5 - r
        addPiece(prefix .. "CoreLong", "Models/Box.mdl", Vector3(0, y, 0), Vector3(w - r * 2.0, h, d), pieceMaterial, collect)
        addPiece(prefix .. "CoreWide", "Models/Box.mdl", Vector3(0, y, 0), Vector3(w, h, d - r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerNE", "Models/Cylinder.mdl", Vector3(ox, y, oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerNW", "Models/Cylinder.mdl", Vector3(-ox, y, oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSE", "Models/Cylinder.mdl", Vector3(ox, y, -oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
        addPiece(prefix .. "CornerSW", "Models/Cylinder.mdl", Vector3(-ox, y, -oz), Vector3(r * 2.0, h, r * 2.0), pieceMaterial, collect)
    end

    addRoundedRect("Base", -0.18, 0.48, 1.30, 1.30, 0.20, materials_.soilSide, false)
    addRoundedRect("GrassTop", 0.18, 0.24, 1.42, 1.42, 0.20, materials_.grassTop, false)
    addRoundedRect("DirtMound", 0.40, 0.20, 1.20, 1.20, 0.18, material, true)

    return moundModels
end

local function SetPlotMaterial(plot, material)
    if plot.soilModels ~= nil then
        for _, model in ipairs(plot.soilModels) do
            model:SetMaterial(material)
        end
    elseif plot.soilModel ~= nil then
        plot.soilModel:SetMaterial(material)
    end
end

local function CreateFarm()
    for i = 1, CONFIG.GridCols * CONFIG.GridRows do
        local plotNode = scene_:CreateChild("Plot" .. i)
        plotNode.position = PlotWorldPosition(i)
        plotNode.scale = Vector3(CONFIG.PlotSize, 1.0, CONFIG.PlotSize)
        local unlocked = i <= unlockedPlotCount_
        local baseMaterial = materials_.soilLocked
        if unlocked then
            baseMaterial = materials_.soil
        end
        local models = CreateRoundedPlotSurface(plotNode, baseMaterial)

        local plot = {
            node = plotNode,
            soilModel = nil,
            soilModels = models,
            plants = {},
            plant = nil,
            selection = nil,
            unlocked = unlocked,
            lockNode = nil,
        }
        if not unlocked then
            plot.lockNode = nil
        end
        plots_[i] = plot
        CreateSelectionFrame(plot)
    end

end

local function RefreshSelection()
    for i, plot in ipairs(plots_) do
        if plot.selection ~= nil then
            plot.selection.enabled = (i == selectedPlot_)
        end
        if not plot.unlocked then
            SetPlotMaterial(plot, materials_.soilLocked)
        elseif i == selectedPlot_ then
            SetPlotMaterial(plot, materials_.soilSelected)
        else
            SetPlotMaterial(plot, materials_.soil)
        end
    end
end

local function RollMutation(plant, seedBuff)
    seedBuff = seedBuff or 0
    local mutation = {
        sizeScale = 1.0,
        sizePrefix = nil,
        colorMutation = nil,
        specials = {},
        priceMultiplier = 1.0,
        timeMultiplier = 1.0,
        seedBuff = seedBuff,
    }

    if math.random() < plant.volumeProb + seedBuff then
        mutation.sizeScale = 1.5 + math.random() * 1.5
        mutation.priceMultiplier = mutation.priceMultiplier * mutation.sizeScale * 2.0
        mutation.timeMultiplier = mutation.timeMultiplier * 1.15
        if mutation.sizeScale < 2.0 then
            mutation.sizePrefix = RandItem({ "丰硕的", "敦实的", "饱满的" })
        elseif mutation.sizeScale < 2.5 then
            mutation.sizePrefix = RandItem({ "巨型的", "膨胀的", "山峦般的" })
        else
            mutation.sizePrefix = RandItem({ "泰坦", "巨神", "穹顶" })
        end
    end

    if math.random() < plant.colorProb + seedBuff then
        mutation.colorMutation = RandItem(COLOR_MUTATIONS)
    end

    for _, special in ipairs(SPECIAL_MUTATIONS) do
        if math.random() < plant.specialProb + seedBuff then
            table.insert(mutation.specials, special)
            mutation.priceMultiplier = mutation.priceMultiplier * special.multiplier
            mutation.timeMultiplier = mutation.timeMultiplier * special.timeMultiplier
        end
    end

    return mutation
end

local function BuildCropName(plant, mutation)
    local prefixes = {}
    if mutation.sizePrefix ~= nil then
        table.insert(prefixes, mutation.sizePrefix)
    end
    if mutation.colorMutation ~= nil then
        table.insert(prefixes, RandItem(mutation.colorMutation.prefixes))
    end
    for _, special in ipairs(mutation.specials) do
        table.insert(prefixes, RandItem(special.prefixes))
    end
    if #prefixes == 0 then
        return plant.name
    end
    return table.concat(prefixes, "") .. plant.name
end

local function ResolvePlantMaterial(plant, mutation)
    if HasSpecial(mutation, "gold") then
        return materials_.gold
    end
    if HasSpecial(mutation, "frozen") then
        return materials_.frozen
    end
    if HasSpecial(mutation, "glow") then
        return materials_.glow
    end
    if HasSpecial(mutation, "chocolate") then
        return materials_.chocolate
    end
    if HasSpecial(mutation, "ceramic") then
        return materials_.ceramic
    end
    if HasSpecial(mutation, "void") then
        return materials_.void
    end

    local color = plant.color
    if mutation.colorMutation ~= nil then
        color = mutation.colorMutation.color
    end
    local key = "plant_" .. plant.name .. tostring(math.random(100000, 999999))
    return CreateMaterial(key, color, 0.0, 0.42)
end

local function CreateLeaves(parent, count, height, radius)
    for i = 1, count do
        local angle = (i - 1) * (360 / count)
        local rad = math.rad(angle)
        local leaf = AddModel(parent, "LeafBlock", "Models/Box.mdl", Vector3(math.cos(rad) * radius, height, math.sin(rad) * radius), Vector3(0.16, 0.08, 0.28), materials_.leaf)
        leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(12, Vector3.RIGHT)
    end
    AddModel(parent, "LeafCoreBlock", "Models/Box.mdl", Vector3(0, height + 0.04, 0), Vector3(0.18, 0.1, 0.18), materials_.leaf)
end

local function CreateBlockStem(parent, height, width)
    AddModel(parent, "StemBlock", "Models/Box.mdl", Vector3(0, height * 0.5, 0), Vector3(width, height, width), materials_.stem)
end

local function CreateBlockFruit(parent, name, position, scale, material)
    AddModel(parent, name, "Models/Box.mdl", position, scale, material)
end

local function CreateBlockFlowerHead(parent, material, y, petalCount)
    local centerMat = CreateMaterial("center" .. tostring(math.random(100000, 999999)), Color(0.32, 0.18, 0.06, 1.0), 0.0, 0.6)
    AddModel(parent, "FlowerCenterBlock", "Models/Box.mdl", Vector3(0, y, 0), Vector3(0.2, 0.2, 0.12), centerMat)
    for i = 1, petalCount do
        local angle = (i - 1) * (360 / petalCount)
        local rad = math.rad(angle)
        local petal = AddModel(parent, "PetalBlock", "Models/Box.mdl", Vector3(math.cos(rad) * 0.22, y, math.sin(rad) * 0.22), Vector3(0.16, 0.12, 0.16), material)
        petal.rotation = Quaternion(angle, Vector3.UP)
    end
end

local function CreatePlantVisual(parent, plant, mutation, material)
    local visual = parent:CreateChild("Visual")
    local stageScale = 0.42
    visual.scale = Vector3(stageScale, stageScale, stageScale) * mutation.sizeScale

    if plant.visual == "root" then
        -- 胡萝卜：锥形橙色身体 + 绿叶冠
        CreateBlockFruit(visual, "RootBlock", Vector3(0, 0.24, 0), Vector3(0.28, 0.46, 0.28), material)
        CreateBlockFruit(visual, "RootMid", Vector3(0, 0.02, 0), Vector3(0.22, 0.12, 0.22), material)
        CreateBlockFruit(visual, "RootTip", Vector3(0, -0.08, 0), Vector3(0.14, 0.12, 0.14), material)
        CreateLeaves(visual, 5, 0.55, 0.15)

    elseif plant.visual == "vine" then
        -- 番茄：竹竿支架 + 圆润红果实挂在藤上
        CreateBlockStem(visual, 0.72, 0.08)
        CreateLeaves(visual, 4, 0.55, 0.2)
        CreateBlockFruit(visual, "TomatoA", Vector3(0.2, 0.62, 0.06), Vector3(0.26, 0.26, 0.26), material)
        CreateBlockFruit(visual, "TomatoB", Vector3(-0.18, 0.46, -0.1), Vector3(0.22, 0.22, 0.22), material)
        -- 番茄顶部绿色蒂
        local tomatoCapMat = CreateMaterial("tCap" .. tostring(math.random(100000, 999999)), Color(0.2, 0.5, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "CapA", Vector3(0.2, 0.77, 0.06), Vector3(0.12, 0.04, 0.12), tomatoCapMat)
        CreateBlockFruit(visual, "CapB", Vector3(-0.18, 0.59, -0.1), Vector3(0.1, 0.04, 0.1), tomatoCapMat)

    elseif plant.visual == "berry" then
        -- 草莓：低矮匍匐 + 三角形红果 + 绿叶铺地
        CreateBlockStem(visual, 0.3, 0.06)
        CreateLeaves(visual, 5, 0.28, 0.26)
        -- 草莓果实：上宽下窄
        CreateBlockFruit(visual, "BerryTop", Vector3(0.18, 0.38, 0.05), Vector3(0.18, 0.12, 0.18), material)
        CreateBlockFruit(visual, "BerryBot", Vector3(0.18, 0.28, 0.05), Vector3(0.12, 0.1, 0.12), material)
        CreateBlockFruit(visual, "BerryB", Vector3(-0.14, 0.34, -0.08), Vector3(0.16, 0.1, 0.16), material)
        CreateBlockFruit(visual, "BerryBBot", Vector3(-0.14, 0.26, -0.08), Vector3(0.1, 0.08, 0.1), material)
        -- 草莓顶部小绿叶
        local berryCapMat = CreateMaterial("bCap" .. tostring(math.random(100000, 999999)), Color(0.2, 0.55, 0.12, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "BerryCapA", Vector3(0.18, 0.45, 0.05), Vector3(0.1, 0.03, 0.1), berryCapMat)

    elseif plant.visual == "cluster" then
        -- 花椰菜：粗短茎 + 半球形白绿花球（多层堆叠）
        local stemMat = CreateMaterial("cfStem" .. tostring(math.random(100000, 999999)), Color(0.6, 0.72, 0.4, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "ThickStem", Vector3(0, 0.18, 0), Vector3(0.18, 0.36, 0.18), stemMat)
        -- 外围大叶包裹
        CreateLeaves(visual, 6, 0.38, 0.3)
        -- 花球：密集堆叠的方块
        CreateBlockFruit(visual, "HeadCenter", Vector3(0, 0.52, 0), Vector3(0.32, 0.22, 0.32), material)
        CreateBlockFruit(visual, "HeadTop", Vector3(0, 0.66, 0), Vector3(0.22, 0.14, 0.22), material)
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90 + 45)
            CreateBlockFruit(visual, "HeadSide" .. i, Vector3(math.cos(angle) * 0.18, 0.52, math.sin(angle) * 0.18), Vector3(0.14, 0.18, 0.14), material)
        end

    elseif plant.visual == "gourd" then
        -- 南瓜：扁圆橙色体 + 竖向瓣状条纹 + 顶部绿蒂
        CreateBlockFruit(visual, "PumpkinCore", Vector3(0, 0.3, 0), Vector3(0.5, 0.38, 0.5), material)
        -- 两侧凸起的瓣
        local darkMat = CreateMaterial("pDark" .. tostring(math.random(100000, 999999)), Color(0.85, 0.35, 0.02, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "RibL", Vector3(-0.22, 0.3, 0), Vector3(0.1, 0.32, 0.36), darkMat)
        CreateBlockFruit(visual, "RibR", Vector3(0.22, 0.3, 0), Vector3(0.1, 0.32, 0.36), darkMat)
        CreateBlockFruit(visual, "RibF", Vector3(0, 0.3, -0.22), Vector3(0.36, 0.32, 0.1), darkMat)
        CreateBlockFruit(visual, "RibB", Vector3(0, 0.3, 0.22), Vector3(0.36, 0.32, 0.1), darkMat)
        -- 顶部绿蒂+卷叶
        local stemGreen = CreateMaterial("pStem" .. tostring(math.random(100000, 999999)), Color(0.25, 0.5, 0.1, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "PumpStem", Vector3(0, 0.54, 0), Vector3(0.08, 0.14, 0.08), stemGreen)
        CreateBlockFruit(visual, "PumpLeaf", Vector3(0.1, 0.52, 0), Vector3(0.14, 0.04, 0.08), stemGreen)

    elseif plant.visual == "melon" then
        -- 西瓜：椭圆绿体 + 深绿色条纹
        CreateBlockFruit(visual, "MelonCore", Vector3(0, 0.32, 0), Vector3(0.52, 0.44, 0.44), material)
        -- 深绿条纹
        local stripeMat = CreateMaterial("mStripe" .. tostring(math.random(100000, 999999)), Color(0.02, 0.35, 0.08, 1.0), 0.0, 0.45)
        CreateBlockFruit(visual, "Stripe1", Vector3(0, 0.32, -0.23), Vector3(0.44, 0.38, 0.04), stripeMat)
        CreateBlockFruit(visual, "Stripe2", Vector3(0, 0.32, 0.23), Vector3(0.44, 0.38, 0.04), stripeMat)
        CreateBlockFruit(visual, "Stripe3", Vector3(-0.27, 0.32, 0), Vector3(0.04, 0.38, 0.36), stripeMat)
        CreateBlockFruit(visual, "Stripe4", Vector3(0.27, 0.32, 0), Vector3(0.04, 0.38, 0.36), stripeMat)
        -- 顶部小卷蔓
        local vineMat = CreateMaterial("mVine" .. tostring(math.random(100000, 999999)), Color(0.3, 0.6, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "MelonVine", Vector3(0.06, 0.56, 0), Vector3(0.12, 0.04, 0.04), vineMat)

    elseif plant.visual == "pineapple" then
        -- 凤梨：菱形纹路身体（多层交错方块）+ 皇冠状叶
        -- 身体：三层交错堆叠，暗色格子纹
        local darkGold = CreateMaterial("paDark" .. tostring(math.random(100000, 999999)), Color(0.7, 0.5, 0.05, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "PineBot", Vector3(0, 0.16, 0), Vector3(0.3, 0.22, 0.3), material)
        CreateBlockFruit(visual, "PineMid", Vector3(0, 0.36, 0), Vector3(0.34, 0.22, 0.34), material)
        CreateBlockFruit(visual, "PineTop", Vector3(0, 0.56, 0), Vector3(0.28, 0.2, 0.28), material)
        -- 菱形格纹（交错小块）
        for i = 1, 4 do
            local angle = math.rad((i - 1) * 90)
            CreateBlockFruit(visual, "Grid" .. i, Vector3(math.cos(angle) * 0.14, 0.36, math.sin(angle) * 0.14), Vector3(0.08, 0.08, 0.08), darkGold)
        end
        -- 皇冠叶：向上散开的硬叶
        local crownMat = CreateMaterial("paCrown" .. tostring(math.random(100000, 999999)), Color(0.2, 0.6, 0.1, 1.0), 0.0, 0.4)
        for i = 1, 5 do
            local angle = (i - 1) * 72
            local rad = math.rad(angle)
            local leaf = AddModel(visual, "CrownLeaf" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.08, 0.74, math.sin(rad) * 0.08), Vector3(0.06, 0.22, 0.14), crownMat)
            leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(-20, Vector3.RIGHT)
        end

    elseif plant.visual == "flower" then
        -- 郁金香：单茎 + 杯状花苞（花瓣内收）
        CreateBlockStem(visual, 0.7, 0.07)
        CreateLeaves(visual, 2, 0.35, 0.12)
        -- 杯状花苞：中心柱 + 内收花瓣
        CreateBlockFruit(visual, "BudCore", Vector3(0, 0.78, 0), Vector3(0.12, 0.24, 0.12), material)
        for i = 1, 4 do
            local angle = (i - 1) * 90
            local rad = math.rad(angle)
            local petal = AddModel(visual, "TulipPetal" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.1, 0.78, math.sin(rad) * 0.1), Vector3(0.14, 0.26, 0.06), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(10, Vector3.RIGHT)
        end

    elseif plant.visual == "cosmos" then
        -- 波斯菊：茎 + 紧凑花头（花瓣紧贴中心）
        CreateBlockStem(visual, 0.65, 0.07)
        CreateLeaves(visual, 2, 0.38, 0.14)
        -- 黄色花盘中心
        local centerMat = CreateMaterial("cosCenter" .. tostring(math.random(100000, 999999)), Color(0.95, 0.85, 0.15, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "CosCenter", Vector3(0, 0.74, 0), Vector3(0.14, 0.12, 0.14), centerMat)
        -- 8 片花瓣紧贴中心排列
        for i = 1, 8 do
            local angle = (i - 1) * 45
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "CosPetal" .. i, Vector3(math.cos(rad) * 0.12, 0.74, math.sin(rad) * 0.12), Vector3(0.1, 0.04, 0.1), material)
        end

    elseif plant.visual == "lily" then
        -- 百合：优雅长茎 + 喇叭形大花（花瓣长而优雅向外卷曲 + 突出花蕊）
        CreateBlockStem(visual, 0.75, 0.07)
        CreateLeaves(visual, 2, 0.35, 0.14)
        -- 花蕊（中心几根细长黄色柱体）
        local stamenMat = CreateMaterial("lilyS" .. tostring(math.random(100000, 999999)), Color(0.85, 0.7, 0.15, 1.0), 0.0, 0.4)
        for i = 1, 3 do
            local angle = (i - 1) * 120
            local rad = math.rad(angle)
            AddModel(visual, "Stamen" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.04, 0.86, math.sin(rad) * 0.04), Vector3(0.025, 0.16, 0.025), stamenMat)
        end
        -- 6 片长花瓣（交替两层，外层更展开）
        for i = 1, 3 do
            local angle = (i - 1) * 120
            local rad = math.rad(angle)
            local petal = AddModel(visual, "LilyInner" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.14, 0.78, math.sin(rad) * 0.14), Vector3(0.1, 0.05, 0.26), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
        end
        for i = 1, 3 do
            local angle = (i - 1) * 120 + 60
            local rad = math.rad(angle)
            local petal = AddModel(visual, "LilyOuter" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.2, 0.74, math.sin(rad) * 0.2), Vector3(0.1, 0.05, 0.28), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(50, Vector3.RIGHT)
        end

    elseif plant.visual == "pansy" then
        -- 三色堇：矮茎 + 扁平正面朝前的大脸花
        CreateBlockStem(visual, 0.4, 0.06)
        CreateLeaves(visual, 4, 0.3, 0.18)
        -- 大平面花脸（上2下3花瓣）
        local darkCenter = CreateMaterial("pansyC" .. tostring(math.random(100000, 999999)), Color(0.15, 0.05, 0.25, 1.0), 0.0, 0.5)
        AddModel(visual, "PansyCenter", "Models/Box.mdl", Vector3(0, 0.52, 0), Vector3(0.1, 0.1, 0.06), darkCenter)
        -- 上部两片
        CreateBlockFruit(visual, "PansyTopL", Vector3(-0.1, 0.6, 0), Vector3(0.14, 0.12, 0.06), material)
        CreateBlockFruit(visual, "PansyTopR", Vector3(0.1, 0.6, 0), Vector3(0.14, 0.12, 0.06), material)
        -- 下部三片（稍大）
        CreateBlockFruit(visual, "PansyBotL", Vector3(-0.12, 0.46, 0), Vector3(0.12, 0.1, 0.06), material)
        CreateBlockFruit(visual, "PansyBotR", Vector3(0.12, 0.46, 0), Vector3(0.12, 0.1, 0.06), material)
        CreateBlockFruit(visual, "PansyBotM", Vector3(0, 0.42, 0), Vector3(0.14, 0.12, 0.06), material)

    elseif plant.visual == "mushroom" then
        -- 蘑菇：白色粗茎 + 红色宽帽 + 白色斑点块
        local stemMat = CreateMaterial("mushStem" .. tostring(math.random(100000, 999999)), Color(0.92, 0.88, 0.8, 1.0), 0.0, 0.55)
        CreateBlockFruit(visual, "MushStem", Vector3(0, 0.22, 0), Vector3(0.18, 0.44, 0.18), stemMat)
        CreateBlockFruit(visual, "MushCap", Vector3(0, 0.52, 0), Vector3(0.52, 0.16, 0.52), material)
        -- 白色斑点
        local spotMat = CreateMaterial("mushSpot" .. tostring(math.random(100000, 999999)), Color(0.98, 0.98, 0.95, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "Spot1", Vector3(0.12, 0.62, 0.08), Vector3(0.08, 0.04, 0.08), spotMat)
        CreateBlockFruit(visual, "Spot2", Vector3(-0.1, 0.62, -0.1), Vector3(0.07, 0.04, 0.07), spotMat)
        CreateBlockFruit(visual, "Spot3", Vector3(0.04, 0.62, -0.14), Vector3(0.06, 0.04, 0.06), spotMat)

    elseif plant.visual == "cactus" then
        -- 仙人掌：粗柱体 + 两臂 + 小花
        CreateBlockFruit(visual, "CactusBody", Vector3(0, 0.5, 0), Vector3(0.24, 0.9, 0.24), material)
        CreateBlockFruit(visual, "CactusArmL", Vector3(-0.26, 0.55, 0), Vector3(0.14, 0.38, 0.14), material)
        CreateBlockFruit(visual, "ArmLUp", Vector3(-0.26, 0.78, 0), Vector3(0.14, 0.14, 0.14), material)
        CreateBlockFruit(visual, "CactusArmR", Vector3(0.26, 0.72, 0), Vector3(0.14, 0.3, 0.14), material)
        CreateBlockFruit(visual, "ArmRUp", Vector3(0.26, 0.9, 0), Vector3(0.14, 0.14, 0.14), material)
        -- 顶部小花
        local flowerMat = CreateMaterial("cacFlower" .. tostring(math.random(100000, 999999)), Color(1.0, 0.4, 0.6, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "CacFlower", Vector3(0, 0.98, 0), Vector3(0.1, 0.08, 0.1), flowerMat)

    elseif plant.visual == "sunflower" then
        -- 向日葵：粗壮高茎 + 大叶 + 实心花头（中心棕块 + 周围紧贴花瓣块）
        CreateBlockStem(visual, 0.9, 0.1)
        CreateLeaves(visual, 3, 0.45, 0.22)
        -- 棕色中心种子区
        local diskMat = CreateMaterial("sfDisk" .. tostring(math.random(100000, 999999)), Color(0.35, 0.2, 0.05, 1.0), 0.0, 0.6)
        CreateBlockFruit(visual, "SunDisk", Vector3(0, 1.0, 0), Vector3(0.22, 0.22, 0.12), diskMat)
        -- 内圈花瓣（4 片，紧贴中心）
        for i = 1, 4 do
            local angle = (i - 1) * 90
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "SunIn" .. i, Vector3(math.cos(rad) * 0.16, 1.0, math.sin(rad) * 0.16), Vector3(0.16, 0.18, 0.1), material)
        end
        -- 外圈花瓣（8 片，紧贴内圈）
        for i = 1, 8 do
            local angle = (i - 1) * 45 + 22
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "SunOut" .. i, Vector3(math.cos(rad) * 0.28, 1.0, math.sin(rad) * 0.28), Vector3(0.14, 0.14, 0.08), material)
        end

    elseif plant.visual == "pepper" then
        -- 辣椒：茎 + 向下悬挂的细长尖椒
        CreateBlockStem(visual, 0.58, 0.07)
        CreateLeaves(visual, 4, 0.48, 0.18)
        -- 辣椒果实：上粗下细，向下挂
        CreateBlockFruit(visual, "PepperTop", Vector3(0.14, 0.48, 0.04), Vector3(0.12, 0.14, 0.12), material)
        CreateBlockFruit(visual, "PepperMid", Vector3(0.14, 0.36, 0.04), Vector3(0.1, 0.14, 0.1), material)
        CreateBlockFruit(visual, "PepperTip", Vector3(0.14, 0.26, 0.04), Vector3(0.06, 0.1, 0.06), material)
        -- 第二根辣椒
        CreateBlockFruit(visual, "Pepper2Top", Vector3(-0.12, 0.44, -0.06), Vector3(0.1, 0.12, 0.1), material)
        CreateBlockFruit(visual, "Pepper2Tip", Vector3(-0.12, 0.34, -0.06), Vector3(0.06, 0.1, 0.06), material)

    elseif plant.visual == "rose" then
        -- 玫瑰：茎 + 紧密层叠花苞（三层由内向外渐大，模拟玫瑰卷瓣）
        CreateBlockStem(visual, 0.68, 0.08)
        CreateLeaves(visual, 3, 0.42, 0.18)
        -- 花苞核心
        CreateBlockFruit(visual, "RoseCore", Vector3(0, 0.78, 0), Vector3(0.12, 0.16, 0.12), material)
        -- 内层花瓣（4片，紧贴核心，略高）
        for i = 1, 4 do
            local angle = (i - 1) * 90 + 20
            local rad = math.rad(angle)
            local p = AddModel(visual, "RoseIn" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.1, 0.8, math.sin(rad) * 0.1), Vector3(0.1, 0.14, 0.05), material)
            p.rotation = Quaternion(angle, Vector3.UP) * Quaternion(15, Vector3.RIGHT)
        end
        -- 外层花瓣（5片，稍大稍低，微微外翻）
        for i = 1, 5 do
            local angle = (i - 1) * 72 + 10
            local rad = math.rad(angle)
            local p = AddModel(visual, "RoseOut" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.18, 0.75, math.sin(rad) * 0.18), Vector3(0.12, 0.12, 0.05), material)
            p.rotation = Quaternion(angle, Vector3.UP) * Quaternion(-10, Vector3.RIGHT)
        end

    elseif plant.visual == "dandelion" then
        -- 蒲公英：细茎 + 饱满球形绒球（核心+中层+外层，整体感强）
        CreateBlockStem(visual, 0.6, 0.05)
        local seedMat = CreateMaterial("dandSeed" .. tostring(math.random(100000, 999999)), Color(0.98, 0.98, 0.95, 1.0), 0.0, 0.3)
        local ballY = 0.72
        -- 核心大块（填充球心）
        CreateBlockFruit(visual, "DandCore", Vector3(0, ballY, 0), Vector3(0.18, 0.18, 0.18), seedMat)
        -- 中层（6 方向填充）
        local midDirs = {
            Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0),
            Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)
        }
        for i, d in ipairs(midDirs) do
            CreateBlockFruit(visual, "DandMid" .. i, Vector3(d.x * 0.12, ballY + d.y * 0.12, d.z * 0.12), Vector3(0.12, 0.12, 0.12), seedMat)
        end
        -- 外层（8 角方向，略小）
        for i = 1, 8 do
            local phi = math.acos(1 - 2 * (i - 0.5) / 8)
            local theta = math.pi * (1 + math.sqrt(5)) * i
            local r = 0.2
            local x = r * math.sin(phi) * math.cos(theta)
            local y = r * math.cos(phi)
            local z = r * math.sin(phi) * math.sin(theta)
            CreateBlockFruit(visual, "DandOut" .. i, Vector3(x, ballY + y, z), Vector3(0.08, 0.08, 0.08), seedMat)
        end
        -- 茎顶部小黄点
        CreateBlockFruit(visual, "DandCenter", Vector3(0, ballY - 0.12, 0), Vector3(0.06, 0.06, 0.06), material)

    elseif plant.visual == "hyacinth" then
        -- 风信子：粗茎 + 沿茎垂直排列的多层小花
        CreateBlockStem(visual, 0.8, 0.1)
        CreateLeaves(visual, 3, 0.25, 0.16)
        -- 沿茎堆叠 4 层小花
        for layer = 1, 4 do
            local ly = 0.45 + (layer - 1) * 0.14
            for i = 1, 4 do
                local angle = math.rad((i - 1) * 90 + layer * 45)
                CreateBlockFruit(visual, "HyaFlower" .. layer .. i, Vector3(math.cos(angle) * 0.12, ly, math.sin(angle) * 0.12), Vector3(0.1, 0.1, 0.1), material)
            end
        end

    elseif plant.visual == "hydrangea" then
        -- 绣球花：粗茎 + 大叶 + 饱满球形花簇（密集排列，外层大内层小）
        CreateBlockStem(visual, 0.55, 0.1)
        CreateLeaves(visual, 4, 0.42, 0.3)
        -- 球形花簇核心（大块填充中心）
        local ballY = 0.75
        CreateBlockFruit(visual, "HydCore", Vector3(0, ballY, 0), Vector3(0.22, 0.22, 0.22), material)
        -- 中层（6个方向）
        local dirs = {
            Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0),
            Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)
        }
        for i, d in ipairs(dirs) do
            CreateBlockFruit(visual, "HydMid" .. i, Vector3(d.x * 0.16, ballY + d.y * 0.16, d.z * 0.16), Vector3(0.14, 0.14, 0.14), material)
        end
        -- 外层（12个方块，均匀分布球面）
        for i = 1, 12 do
            local phi = math.acos(1 - 2 * (i - 0.5) / 12)
            local theta = math.pi * (1 + math.sqrt(5)) * i
            local r = 0.26
            local x = r * math.sin(phi) * math.cos(theta)
            local y = r * math.cos(phi)
            local z = r * math.sin(phi) * math.sin(theta)
            CreateBlockFruit(visual, "HydOut" .. i, Vector3(x, ballY + y, z), Vector3(0.1, 0.1, 0.1), material)
        end

    elseif plant.visual == "starfruit" then
        -- 杨桃：茎 + 五角星截面的果实（5 个方块辐射排列）
        CreateBlockStem(visual, 0.55, 0.07)
        CreateLeaves(visual, 4, 0.44, 0.18)
        -- 五角星果实
        local fruitY = 0.6
        CreateBlockFruit(visual, "StarCore", Vector3(0, fruitY, 0), Vector3(0.14, 0.28, 0.14), material)
        for i = 1, 5 do
            local angle = math.rad((i - 1) * 72)
            local wing = AddModel(visual, "StarWing" .. i, "Models/Box.mdl", Vector3(math.cos(angle) * 0.12, fruitY, math.sin(angle) * 0.12), Vector3(0.12, 0.24, 0.05), material)
            wing.rotation = Quaternion((i - 1) * 72, Vector3.UP)
        end

    elseif plant.visual == "corn" then
        -- 玉米：粗茎居中 + 大玉米棒贴茎（棒身黄色 + 底部绿色苞叶包裹）
        CreateBlockStem(visual, 0.8, 0.1)
        CreateLeaves(visual, 2, 0.35, 0.18)
        -- 玉米棒（大而醒目，贴着茎）
        CreateBlockFruit(visual, "CornCob", Vector3(0, 0.6, 0.1), Vector3(0.18, 0.4, 0.18), material)
        -- 苞叶包裹下半部分
        local huskMat = CreateMaterial("husk" .. tostring(math.random(100000, 999999)), Color(0.3, 0.6, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "HuskL", Vector3(-0.08, 0.52, 0.1), Vector3(0.04, 0.3, 0.16), huskMat)
        CreateBlockFruit(visual, "HuskR", Vector3(0.08, 0.52, 0.1), Vector3(0.04, 0.3, 0.16), huskMat)
        CreateBlockFruit(visual, "HuskB", Vector3(0, 0.52, 0.18), Vector3(0.14, 0.26, 0.04), huskMat)

    elseif plant.visual == "grape" then
        -- 葡萄：藤蔓茎 + 叶子 + 一串紫色圆果（倒三角形排列）
        CreateBlockStem(visual, 0.55, 0.07)
        CreateLeaves(visual, 2, 0.5, 0.18)
        -- 葡萄串（倒三角形：上宽下窄）
        -- 第一排（3 颗）
        CreateBlockFruit(visual, "Grape1", Vector3(-0.1, 0.46, 0), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape2", Vector3(0.02, 0.46, 0.08), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape3", Vector3(0.1, 0.46, -0.04), Vector3(0.1, 0.1, 0.1), material)
        -- 第二排（2 颗）
        CreateBlockFruit(visual, "Grape4", Vector3(-0.04, 0.36, 0.04), Vector3(0.1, 0.1, 0.1), material)
        CreateBlockFruit(visual, "Grape5", Vector3(0.08, 0.36, -0.02), Vector3(0.1, 0.1, 0.1), material)
        -- 第三排（1 颗，底部）
        CreateBlockFruit(visual, "Grape6", Vector3(0.02, 0.27, 0.02), Vector3(0.09, 0.09, 0.09), material)

    elseif plant.visual == "mango" then
        -- 芒果：短枝 + 大叶 + 肾形大芒果（上宽下窄，侧面有弧度）
        CreateBlockStem(visual, 0.45, 0.08)
        CreateLeaves(visual, 3, 0.42, 0.18)
        -- 芒果主体（3 段组成肾形：上圆中宽下尖）
        CreateBlockFruit(visual, "MangoWide", Vector3(0.02, 0.46, 0), Vector3(0.26, 0.16, 0.2), material)
        CreateBlockFruit(visual, "MangoMid", Vector3(0, 0.36, 0), Vector3(0.22, 0.12, 0.18), material)
        CreateBlockFruit(visual, "MangoTip", Vector3(-0.02, 0.28, 0), Vector3(0.14, 0.1, 0.12), material)
        -- 顶部微红晕（芒果特征：顶部偏红）
        local blushMat = CreateMaterial("mBlush" .. tostring(math.random(100000, 999999)), Color(0.9, 0.35, 0.1, 1.0), 0.0, 0.42)
        CreateBlockFruit(visual, "MangoBlush", Vector3(0.06, 0.52, 0), Vector3(0.12, 0.08, 0.12), blushMat)

    elseif plant.visual == "banana" then
        -- 香蕉：粗茎 + 大叶 + 一挂弯曲香蕉（向上弯曲的月牙形，从中心柄放射）
        CreateBlockStem(visual, 0.55, 0.12)
        CreateLeaves(visual, 2, 0.48, 0.26)
        -- 中心果柄
        local stalkMat = CreateMaterial("bStalk" .. tostring(math.random(100000, 999999)), Color(0.5, 0.38, 0.12, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "BananaStalk", Vector3(0, 0.6, 0), Vector3(0.08, 0.1, 0.08), stalkMat)
        -- 5 根香蕉从果柄向外弯曲展开（月牙形：用两段方块模拟弧度）
        for i = 1, 5 do
            local angle = (i - 1) * 72
            local rad = math.rad(angle)
            -- 内段（靠近柄，竖直）
            local bx = math.cos(rad) * 0.08
            local bz = math.sin(rad) * 0.08
            CreateBlockFruit(visual, "BanIn" .. i, Vector3(bx, 0.54, bz), Vector3(0.07, 0.16, 0.07), material)
            -- 外段（远离柄，向外倾斜）
            local ox = math.cos(rad) * 0.14
            local oz = math.sin(rad) * 0.14
            CreateBlockFruit(visual, "BanOut" .. i, Vector3(ox, 0.46, oz), Vector3(0.06, 0.14, 0.06), material)
        end

    elseif plant.visual == "bamboo" then
        -- 竹子：分节绿色方柱（多段叠加）+ 顶部小叶
        -- 竹竿（3 段分节）
        CreateBlockFruit(visual, "Seg1", Vector3(0, 0.2, 0), Vector3(0.12, 0.36, 0.12), material)
        CreateBlockFruit(visual, "Seg2", Vector3(0, 0.55, 0), Vector3(0.11, 0.32, 0.11), material)
        CreateBlockFruit(visual, "Seg3", Vector3(0, 0.86, 0), Vector3(0.1, 0.28, 0.1), material)
        -- 节环（深色）
        local nodeMat = CreateMaterial("bNode" .. tostring(math.random(100000, 999999)), Color(0.2, 0.5, 0.15, 1.0), 0.0, 0.5)
        CreateBlockFruit(visual, "Node1", Vector3(0, 0.38, 0), Vector3(0.14, 0.04, 0.14), nodeMat)
        CreateBlockFruit(visual, "Node2", Vector3(0, 0.7, 0), Vector3(0.13, 0.04, 0.13), nodeMat)
        -- 顶部竹叶
        CreateLeaves(visual, 3, 0.98, 0.12)

    elseif plant.visual == "coconut" then
        -- 椰子：弯曲棕色树干 + 棕色椰果 + 绿色棕榈叶
        local trunkMat = CreateMaterial("cTrunk" .. tostring(math.random(100000, 999999)), Color(0.5, 0.35, 0.18, 1.0), 0.0, 0.6)
        CreateBlockFruit(visual, "Trunk1", Vector3(0, 0.25, 0), Vector3(0.14, 0.45, 0.14), trunkMat)
        CreateBlockFruit(visual, "Trunk2", Vector3(0.04, 0.62, 0), Vector3(0.12, 0.3, 0.12), trunkMat)
        -- 椰果（2-3 颗棕色圆果）
        CreateBlockFruit(visual, "Coco1", Vector3(0.06, 0.78, 0.06), Vector3(0.12, 0.12, 0.12), material)
        CreateBlockFruit(visual, "Coco2", Vector3(-0.04, 0.78, -0.04), Vector3(0.1, 0.1, 0.1), material)
        -- 棕榈叶（向外展开）
        for i = 1, 4 do
            local angle = (i - 1) * 90 + 45
            local rad = math.rad(angle)
            local leaf = AddModel(visual, "PalmLeaf" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.14, 0.86, math.sin(rad) * 0.14), Vector3(0.08, 0.04, 0.24), materials_.leaf)
            leaf.rotation = Quaternion(angle, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
        end

    elseif plant.visual == "azalea" then
        -- 杜鹃：短茎 + 大团花簇（几乎全是花，少量绿叶点缀）
        CreateBlockStem(visual, 0.28, 0.09)
        -- 花团主体（多个花块紧密排列，覆盖整个顶部）
        CreateBlockFruit(visual, "FlowerCore", Vector3(0, 0.5, 0), Vector3(0.26, 0.22, 0.26), material)
        CreateBlockFruit(visual, "FlowerL", Vector3(-0.16, 0.48, 0.06), Vector3(0.16, 0.18, 0.16), material)
        CreateBlockFruit(visual, "FlowerR", Vector3(0.14, 0.5, -0.04), Vector3(0.16, 0.18, 0.16), material)
        CreateBlockFruit(visual, "FlowerF", Vector3(0.02, 0.52, 0.16), Vector3(0.14, 0.16, 0.14), material)
        CreateBlockFruit(visual, "FlowerTop", Vector3(0, 0.66, 0), Vector3(0.18, 0.14, 0.18), material)
        -- 少量绿叶从底部露出
        local bushMat = CreateMaterial("bush" .. tostring(math.random(100000, 999999)), Color(0.2, 0.55, 0.18, 1.0), 0.0, 0.45)
        CreateBlockFruit(visual, "LeafL", Vector3(-0.2, 0.38, 0), Vector3(0.1, 0.08, 0.14), bushMat)
        CreateBlockFruit(visual, "LeafR", Vector3(0.18, 0.36, 0.08), Vector3(0.1, 0.08, 0.12), bushMat)

    elseif plant.visual == "magnolia" then
        -- 玉兰：粗枝 + 大杯状白花（花瓣厚实微张）
        CreateBlockStem(visual, 0.65, 0.1)
        CreateLeaves(visual, 2, 0.38, 0.16)
        -- 花苞核心
        local centerMat = CreateMaterial("magC" .. tostring(math.random(100000, 999999)), Color(0.9, 0.85, 0.3, 1.0), 0.0, 0.4)
        CreateBlockFruit(visual, "MagCore", Vector3(0, 0.76, 0), Vector3(0.1, 0.14, 0.1), centerMat)
        -- 6 片厚实白色花瓣（杯状微张）
        for i = 1, 6 do
            local angle = (i - 1) * 60
            local rad = math.rad(angle)
            local petal = AddModel(visual, "MagPetal" .. i, "Models/Box.mdl", Vector3(math.cos(rad) * 0.12, 0.76, math.sin(rad) * 0.12), Vector3(0.12, 0.18, 0.06), material)
            petal.rotation = Quaternion(angle, Vector3.UP) * Quaternion(12, Vector3.RIGHT)
        end

    elseif plant.visual == "peony" then
        -- 牡丹：粗茎 + 超大密集层叠花球（比玫瑰更大更蓬松）
        CreateBlockStem(visual, 0.6, 0.1)
        CreateLeaves(visual, 3, 0.4, 0.22)
        -- 花球核心
        CreateBlockFruit(visual, "PeonyCore", Vector3(0, 0.74, 0), Vector3(0.18, 0.18, 0.18), material)
        -- 内层花瓣（6 片紧贴）
        for i = 1, 6 do
            local angle = (i - 1) * 60
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "PeonyIn" .. i, Vector3(math.cos(rad) * 0.12, 0.75, math.sin(rad) * 0.12), Vector3(0.12, 0.14, 0.06), material)
        end
        -- 外层花瓣（8 片稍大）
        for i = 1, 8 do
            local angle = (i - 1) * 45 + 22
            local rad = math.rad(angle)
            CreateBlockFruit(visual, "PeonyOut" .. i, Vector3(math.cos(rad) * 0.22, 0.72, math.sin(rad) * 0.22), Vector3(0.12, 0.12, 0.06), material)
        end

    else
        -- 通用花卉 fallback
        CreateBlockStem(visual, 0.74, 0.08)
        CreateLeaves(visual, 4, 0.5, 0.18)
        CreateBlockFlowerHead(visual, material, 0.84, 6)
    end

    return visual
end

local function CreateOrbitEffect(parent, name, material, count, radius, y, scale)
    local root = parent:CreateChild(name)
    for i = 1, count do
        local angle = math.rad((i - 1) * (360 / count))
        AddModel(root, name .. i, "Models/Sphere.mdl", Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius), scale, material)
    end
    return root
end

local function CreateSpecialEffects(plantData)
    local root = plantData.root
    plantData.effectNodes = {}
    local mutation = plantData.mutation

    if HasSpecial(mutation, "wet") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "WaterDrops", materials_.waterDrop, 8, 0.55 * mutation.sizeScale, 0.8, Vector3(0.055, 0.11, 0.055)))
    end
    if HasSpecial(mutation, "stardust") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Stars", materials_.star, 10, 0.75 * mutation.sizeScale, 1.2, Vector3(0.06, 0.06, 0.06)))
    end
    if HasSpecial(mutation, "cloud") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Clouds", materials_.cloud, 5, 0.5 * mutation.sizeScale, 0.95, Vector3(0.2, 0.12, 0.14)))
    end
    if HasSpecial(mutation, "pollen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "Pollen", materials_.pollen, 12, 0.65 * mutation.sizeScale, 0.9, Vector3(0.035, 0.035, 0.035)))
    end
    if HasSpecial(mutation, "void") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "VoidRing", materials_.void, 14, 0.8 * mutation.sizeScale, 0.9, Vector3(0.045, 0.045, 0.045)))
    end
    if HasSpecial(mutation, "frozen") then
        table.insert(plantData.effectNodes, CreateOrbitEffect(root, "ColdMist", materials_.cloud, 6, 0.42 * mutation.sizeScale, 0.35, Vector3(0.12, 0.05, 0.12)))
    end
end

ClearBagPreview = function()
end

local function CreateBagPreview(item)
end

local function CloseBagItemDetail()
    selectedBagItem_ = nil
    ClearBagPreview()
    if RebuildUI ~= nil then RebuildUI() end
end

local function OpenBagItemDetail(item)
    if item == nil then return end
    selectedBagItem_ = item
    CreateBagPreview(item)
    if RebuildUI ~= nil then RebuildUI() end
end


local function ClampToPlot(localPos)
    -- DirtMound 本地半宽 = 1.10/2 = 0.55，留边距后约 0.46
    local half = 0.46
    return Vector3(Clamp(localPos.x, -half, half), 0, Clamp(localPos.z, -half, half))
end

local function RandomScatterOffset()
    local angle = math.random() * math.pi * 2.0
    -- 散布范围限制在种植土本地半径内
    local radius = math.sqrt(math.random()) * 0.38
    return Vector3(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function FindPlantAtLocalPosition(plot, localPos, matureOnly)
    if plot == nil or plot.plants == nil then return nil, nil end
    local bestIndex = nil
    local bestCrop = nil
    local bestDist = 9999
    for i, crop in ipairs(plot.plants) do
        if (not matureOnly) or crop.mature then
            local dx = crop.localPos.x - localPos.x
            local dz = crop.localPos.z - localPos.z
            local dist = dx * dx + dz * dz
            local radius = math.max(0.55, crop.pickRadius or 0.55)
            if dist <= radius * radius and dist < bestDist then
                bestDist = dist
                bestIndex = i
                bestCrop = crop
            end
        end
    end
    return bestCrop, bestIndex
end

local function IsSeedPositionUsable(plot, localPos)
    if plot == nil or plot.plants == nil then return false end
    for _, crop in ipairs(plot.plants) do
        local dx = crop.localPos.x - localPos.x
        local dz = crop.localPos.z - localPos.z
        local minDist = math.max(CONFIG.SeedMinDistance, ((crop.seedRadius or 0.12) + 0.07) * 0.72)
        if dx * dx + dz * dz < minDist * minDist then
            return false
        end
    end
    return true
end

local function ResolveSeedLocalPosition(plot, centerLocalPos)
    local basePos = ClampToPlot(centerLocalPos)
    if IsSeedPositionUsable(plot, basePos) then
        return basePos
    end

    for i = 1, 10 do
        local angle = (i - 1) * (math.pi * 2.0 / 10.0)
        local radius = CONFIG.SeedMinDistance * (0.8 + i * 0.08)
        local candidate = ClampToPlot(basePos + Vector3(math.cos(angle) * radius, 0, math.sin(angle) * radius))
        if IsSeedPositionUsable(plot, candidate) then
            return candidate
        end
    end
    return basePos
end

local function CreateSeedVisual(root, plant, seedRadius)
    -- 使用方块风种子模型
    local naturalScale = (seedRadius / 0.09)
    local seed = SeedVisual.Create(root, plant, naturalScale)
    return seed
end

local function PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    local plot = plots_[plotIndex]
    if plot == nil or not plot.unlocked then return false end
    if plot.plants == nil then plot.plants = {} end
    if #plot.plants >= CONFIG.MaxCropsPerPlot then
        ShowToast("这块田地已经很满了")
        return false
    end

    local plant = PLANTS[plantIndex]
    if seedBag_[plantIndex] == nil or seedBag_[plantIndex] <= 0 then
        return false
    end

    local localPos = ResolveSeedLocalPosition(plot, centerLocalPos)
    local seedBuff = RemoveSeedFromBag(plantIndex)
    local mutation = RollMutation(plant, seedBuff)
    local naturalScale = 0.78 + math.random() * 0.62
    local weightScale, weightTier = RollCropWeightScale()
    local weightBonus = GetWeightBonusForPlot(plotIndex)
    local baseWeight = plant.baseWeight or 1.0
    local weight = baseWeight * weightScale * weightBonus
    local visualWeightScale = (weightScale * weightBonus) ^ 0.35
    mutation.sizeScale = mutation.sizeScale * naturalScale * visualWeightScale
    local seedRadius = (0.09 + math.random() * 0.055) * naturalScale
    local seedHeight = 0.010 + math.random() * 0.008
    local cropName = BuildCropName(plant, mutation)
    local root = plot.node:CreateChild("PlantRoot")
    root.position = Vector3(localPos.x, CONFIG.SeedVisualY, localPos.z)
    root.rotation = Quaternion(math.random() * 360.0, Vector3.UP)

    local seedVisual = CreateSeedVisual(root, plant, seedRadius)
    local material = ResolvePlantMaterial(plant, mutation)

    local weightRatio = weight / baseWeight
    local weightMultiplier = weightRatio * weightRatio
    local price = math.floor(plant.fruitPrice * weightMultiplier * mutation.priceMultiplier + 0.5)
    local growTime = plant.growTime * mutation.timeMultiplier
    local crop = {
        config = plant,
        plantIndex = plantIndex,
        root = root,
        seedVisual = seedVisual,
        visual = nil,
        material = material,
        mutation = mutation,
        effectNodes = {},
        name = cropName,
        price = price,
        weight = weight,
        baseWeight = baseWeight,
        weightScale = weightScale,
        weightTier = weightTier,
        weightBonus = weightBonus,
        weightMultiplier = weightMultiplier,
        elapsed = 0,
        growTime = growTime,
        mature = false,
        sprouted = false,
        localPos = localPos,
        seedRadius = seedRadius,
        seedHeight = seedHeight,
        pickRadius = math.max(0.55, 0.42 * mutation.sizeScale),
    }
    table.insert(plot.plants, crop)
    AddDailyProgress("plant", 1)
    print(string.format("散点播种: 田地%d %s 位置(%.2f, %.2f)，重量 %.2fkg[%s]，成熟时间 %.1fs，预估售价 %d", plotIndex, cropName, localPos.x, localPos.z, weight, weightTier, growTime, price))
    return true
end

local function HarvestNearestMature(plotIndex, localPos)
    local plot = plots_[plotIndex]
    if plot == nil or plot.plants == nil then return false end
    local crop, cropIndex = nil, nil
    if localPos ~= nil then
        crop, cropIndex = FindPlantAtLocalPosition(plot, localPos, true)
    end
    if crop == nil then
        for i, item in ipairs(plot.plants) do
            if item.mature then
                crop = item
                cropIndex = i
                break
            end
        end
    end
    if crop == nil or cropIndex == nil then return false end
    table.insert(harvested_, {
        name = crop.name,
        price = crop.price,
        rarity = crop.config.rarity,
        plantIndex = crop.plantIndex,
        weight = crop.weight,
        baseWeight = crop.baseWeight,
        weightTier = crop.weightTier,
        weightMultiplier = crop.weightMultiplier,
        mutation = crop.mutation,
    })
    crop.root:Remove()
    table.remove(plot.plants, cropIndex)
    collectedPlants_[crop.plantIndex] = true
    AddDailyProgress("harvest", 1)
    CheckSilverPackRewards()
    print("收获: " .. crop.name .. " 价值 " .. crop.price)
    return true
end

local function PlantSeed(plotIndex, plantIndex)
    return PlantSeedAt(plotIndex, plantIndex, Vector3(0, 0, 0))
end

local function BuySelectedSeed()
    local plant = PLANTS[selectedSeed_]
    if money_ < plant.seedPrice then
        print("金币不足，无法购买: " .. plant.name)
        return false
    end
    money_ = money_ - plant.seedPrice
    AddSeedToBag(selectedSeed_, 1, 0)
    print("购买种子: " .. plant.name .. "，剩余金币 " .. money_)
    return true
end

local function SellAllHarvested()
    if #harvested_ == 0 then
        print("背包没有可出售作物")
        return 0
    end
    local total = 0
    for _, item in ipairs(harvested_) do
        total = total + item.price
    end
    harvested_ = {}
    selectedBagItem_ = nil
    if ClearBagPreview ~= nil then
        ClearBagPreview()
    end
    money_ = money_ + total
    AddDailyProgress("sell", 1)
    print("出售全部作物，获得金币 " .. total)
    return total
end

local function SellBagItem(item)
    if item == nil then return 0 end
    for i = 1, #harvested_ do
        if harvested_[i] == item then
            local earned = item.price or 0
            table.remove(harvested_, i)
            selectedBagItem_ = nil
            if ClearBagPreview ~= nil then
                ClearBagPreview()
            end
            money_ = money_ + earned
            AddDailyProgress("sell", 1)
            print("出售作物 " .. (item.name or "作物") .. "，获得金币 " .. earned)
            return earned
        end
    end
    return 0
end

local function CountPlotPlants(plot)
    if plot == nil or plot.plants == nil then return 0 end
    return #plot.plants
end

local function CountMaturePlants(plot)
    if plot == nil or plot.plants == nil then return 0 end
    local count = 0
    for _, crop in ipairs(plot.plants) do
        if crop.mature then
            count = count + 1
        end
    end
    return count
end

local function GetPlotText(plot)
    if plot == nil then
        return "未知田地"
    end
    if not plot.unlocked then
        return "未解锁"
    end
    local cropCount = CountPlotPlants(plot)
    if cropCount == 0 then
        return "空田地，可自由散点播种"
    end
    local matureCount = CountMaturePlants(plot)
    if matureCount > 0 then
        return string.format("%d株作物，%d株已成熟 | 点击成熟作物附近收获", cropCount, matureCount)
    end
    local minRemain = 9999
    for _, crop in ipairs(plot.plants) do
        minRemain = math.min(minRemain, math.max(0, crop.growTime - crop.elapsed))
    end
    return string.format("%d株生长中 | 最近 %.1fs 成熟", cropCount, minRemain)
end

local function CountHarvestedValue()
    local value = 0
    for _, item in ipairs(harvested_) do
        value = value + item.price
    end
    return value
end

ShowToast = function(text)
    toastTimer_ = 2.0
    if toastLabel_ ~= nil then
        toastLabel_:SetText(text)
    end
    print(text)
end

local function RefreshSeedButtons()
    for i, button in ipairs(seedButtons_) do
        local plant = PLANTS[i]
        local owned = seedBag_[i] or 0
        if i == selectedSeed_ then
            button:SetText(string.format("%s  x%d", plant.name, owned))
        else
            button:SetText(string.format("%s\n%d金", plant.name, plant.seedPrice))
        end
    end
end

local function GetUiRarityColor(rarity)
    local c = RARITY_COLORS[rarity]
    if c == nil then return {200, 200, 200, 255} end
    return { math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), 255 }
end

local function CountPackResults(results)
    local counts = {}
    for _, result in ipairs(results) do
        counts[result.seedId] = (counts[result.seedId] or 0) + 1
    end
    return counts
end

local function CanReceivePackResults(results)
    local counts = CountPackResults(results)
    for seedId, count in pairs(counts) do
        if (seedBag_[seedId] or 0) + count > SEED_STACK_MAX then
            return false
        end
    end
    return true
end

local function BuildSeedPackResults(packCfg, packCount)
    local results = {}
    for _ = 1, packCount do
        for _ = 1, packCfg.onceOpenCount do
            local seedId = RollSeedFromPack(packCfg)
            table.insert(results, {
                seedId = seedId,
                packId = packCfg.packId,
                seedBuff = packCfg.seedBuff or 0,
                isNew = not collectedPlants_[seedId],
            })
        end
    end
    return results
end

local function ApplyPackResults(results)
    for _, result in ipairs(results) do
        AddSeedToBag(result.seedId, 1, result.seedBuff)
    end
end

local function GetFirstAvailablePackId()
    for packId, cfg in pairs(SEED_PACK_CONFIG) do
        if (seedPacks_[packId] or 0) > 0 then
            return cfg.packId
        end
    end
    return nil
end

local function BuildResultCards(results)
    local cards = {}
    local counts = CountPackResults(results)
    local sorted = {}
    for seedId, count in pairs(counts) do
        table.insert(sorted, seedId)
    end
    table.sort(sorted, function(a, b)
        local ra = RARITY_ORDER[PLANTS[a].rarity] or 1
        local rb = RARITY_ORDER[PLANTS[b].rarity] or 1
        if ra == rb then return a < b end
        return ra < rb
    end)

    for _, seedId in ipairs(sorted) do
        local plant = PLANTS[seedId]
        local plantName = plant.name
        local rarity = plant.rarity
        local count = counts[seedId] or 0
        local rarityColor = GetUiRarityColor(rarity)
        local newFlag = false
        local silverFlag = false
        for _, result in ipairs(results) do
            if result.seedId == seedId then
                newFlag = newFlag or result.isNew
                silverFlag = silverFlag or result.seedBuff > 0
            end
        end
        table.insert(cards, UI.Panel {
            width = "46%",
            minHeight = 104,
            padding = 8,
            marginBottom = 8,
            alignItems = "center",
            backgroundColor = silverFlag and {245, 248, 255, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = silverFlag and 3 or 2,
            borderColor = silverFlag and {190, 195, 215, 255} or rarityColor,
            children = {
                UI.Panel {
                    width = 50,
                    height = 44,
                    marginBottom = 4,
                    backgroundImage = string.format("image/icons_3d/seed (%d).png", seedId),
                    backgroundFit = "contain",
                },
                UI.Label { text = string.format("%s x%d", plantName, count), fontSize = 12, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center" },
                UI.Label { text = rarity, fontSize = 10, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" },
                newFlag and UI.Label { text = "新品", fontSize = 10, fontWeight = "bold", fontColor = {220, 55, 45, 255}, textAlign = "center" } or UI.Panel { height = 0 },
                silverFlag and UI.Label { text = "银种 +1%", fontSize = 9, fontColor = {90, 100, 130, 255}, textAlign = "center" } or UI.Panel { height = 0 },
            },
        })
    end
    return cards
end

local function OpenSeedPackResultModal(title, results)
    seedPackPanelOpen_ = false
    seedPackResultTitle_ = title
    seedPackResultItems_ = results
    if RebuildUI ~= nil then RebuildUI() end
end

local function OpenSeedPack(packId, packCount)
    local cfg = SEED_PACK_CONFIG[packId]
    local owned = seedPacks_[packId] or 0
    packCount = math.min(packCount or 1, owned)
    if cfg == nil or packCount <= 0 then return end

    local results = BuildSeedPackResults(cfg, packCount)
    if not CanReceivePackResults(results) then
        ShowToast("背包空间不足，无法开启礼包")
        return
    end
    seedPacks_[packId] = owned - packCount
    ApplyPackResults(results)
    RefreshUI(true)
    OpenSeedPackResultModal(packCount > 1 and (cfg.packName .. " x" .. packCount) or cfg.packName, results)
end

local function BuildSeedPackRows()
    local rows = {}
    for packId, cfg in pairs(SEED_PACK_CONFIG) do
        local owned = seedPacks_[packId] or 0
        if owned > 0 then
            table.insert(rows, UI.Panel {
                flexDirection = "column",
                alignItems = "stretch",
                padding = 8,
                marginBottom = 8,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 14,
                borderWidth = 2,
                borderColor = cfg.themeColor,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Panel {
                                width = 42,
                                height = 42,
                                marginRight = 8,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = cfg.themeColor,
                                borderRadius = 12,
                                children = { UI.Label { text = cfg.seedBuff > 0 and "银" or "袋", fontSize = 18, fontWeight = "bold", fontColor = {255, 255, 255, 255} } },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                gap = 2,
                                children = {
                                    UI.Label { text = cfg.packName .. " x" .. owned, fontSize = 14, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                    UI.Label { text = cfg.getWay .. " | 每包 " .. cfg.onceOpenCount .. " 颗种子", fontSize = 10, fontColor = {120, 100, 80, 220} },
                                },
                            },
                        },
                    },
                    cfg.seedBuff > 0 and UI.Label { text = "银质种子：播种时体型/颜色/特殊变异概率 +1%", fontSize = 10, fontColor = {90, 100, 130, 240}, marginBottom = 6 } or UI.Panel { height = 0 },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button { text = "开1包", flexGrow = 1, height = 32, fontSize = 12, variant = "primary", onClick = function() suppressNextWorldTap_ = true; OpenSeedPack(packId, 1) end },
                            UI.Button { text = "全开", flexGrow = 1, height = 32, fontSize = 12, variant = "secondary", onClick = function() suppressNextWorldTap_ = true; OpenSeedPack(packId, owned) end },
                        },
                    },
                },
            })
        end
    end
    if #rows == 0 then
        table.insert(rows, UI.Label { text = "暂无可开启的种子包", fontSize = 14, fontColor = {120, 100, 80, 220}, textAlign = "center" })
    end
    return rows
end

OpenSeedPackHub = function()
    if CountSeedPacks() <= 0 then
        ShowToast("暂无可开启的种子包")
        return
    end
    seedPackResultTitle_ = nil
    seedPackResultItems_ = nil
    seedPackPanelOpen_ = true
    if RebuildUI ~= nil then RebuildUI() end
end

local function BuildSeedPackOverlay()
    if not seedPackPanelOpen_ then
        return UI.Panel { width = 0, height = 0 }
    end
    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 100,
        backgroundColor = {0, 0, 0, 120},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 430,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Label { text = "种子礼包", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                            UI.Button {
                                text = "×",
                                width = 34,
                                height = 30,
                                fontSize = 18,
                                fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 0},
                                fontColor = {120, 90, 70, 255},
                                borderRadius = 12,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    seedPackPanelOpen_ = false
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                    UI.ScrollView {
                        height = 350,
                        scrollY = true,
                        showScrollbar = true,
                        children = BuildSeedPackRows(),
                    },
                },
            },
        },
    }
end

local function BuildSeedPackResultOverlay()
    if seedPackResultItems_ == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    local results = seedPackResultItems_
    local newNames = {}
    for _, result in ipairs(results) do
        if result.isNew then
            local name = PLANTS[result.seedId].name
            local exists = false
            for _, item in ipairs(newNames) do
                if item == name then exists = true; break end
            end
            if not exists then table.insert(newNames, name) end
        end
    end

    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 110,
        backgroundColor = {0, 0, 0, 130},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 500,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Label { text = seedPackResultTitle_ or "开包结果", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center", marginBottom = 8 },
                    #newNames > 0 and UI.Panel {
                        padding = 7,
                        marginBottom = 8,
                        backgroundColor = {255, 235, 232, 255},
                        borderRadius = 10,
                        borderWidth = 2,
                        borderColor = {220, 70, 60, 255},
                        children = { UI.Label { text = "解锁新品种：" .. table.concat(newNames, "、"), fontSize = 12, fontWeight = "bold", fontColor = {210, 55, 45, 255}, textAlign = "center" } },
                    } or UI.Panel { height = 0 },
                    UI.ScrollView {
                        height = 300,
                        scrollY = true,
                        showScrollbar = true,
                        children = {
                            UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 8, children = BuildResultCards(results) },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 10,
                        children = {
                            CountSeedPacks() > 0 and UI.Button {
                                text = "下一包",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "primary",
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    local packId = GetFirstAvailablePackId()
                                    if packId ~= nil then
                                        local cfg = SEED_PACK_CONFIG[packId]
                                        local nextResults = BuildSeedPackResults(cfg, 1)
                                        if CanReceivePackResults(nextResults) then
                                            seedPacks_[packId] = (seedPacks_[packId] or 0) - 1
                                            ApplyPackResults(nextResults)
                                            OpenSeedPackResultModal(cfg.packName, nextResults)
                                        else
                                            ShowToast("背包空间不足，无法开启礼包")
                                        end
                                    end
                                end,
                            } or UI.Panel { width = 0, height = 0 },
                            UI.Button {
                                text = "关闭",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "secondary",
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    seedPackResultTitle_ = nil
                                    seedPackResultItems_ = nil
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

OpenTaskPanel = function()
    if taskModal_ ~= nil then
        taskModal_:Close()
    end
    local rows = {}
    for _, task in ipairs(DAILY_TASK_CONFIG) do
        local progress = math.min(dailyTaskState_.progress[task.key] or 0, task.target)
        local done = progress >= task.target
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            padding = 10,
            marginBottom = 6,
            backgroundColor = done and {232, 246, 232, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = 1,
            borderColor = done and {94, 194, 131, 255} or {195, 180, 150, 180},
            children = {
                UI.Label { text = done and "完成" or "进行中", width = 54, fontSize = 12, fontWeight = "bold", fontColor = done and {70, 160, 90, 255} or {130, 110, 85, 255} },
                UI.Label { text = task.title, flexGrow = 1, fontSize = 13, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                UI.Label { text = progress .. "/" .. task.target, width = 48, fontSize = 13, fontWeight = "bold", fontColor = {90, 150, 100, 255}, textAlign = "right" },
            },
        })
    end

    local canClaim = AreAllDailyTasksCompleted() and not dailyTaskState_.rewardClaimed
    taskModal_ = UI.Modal {
        title = "每日任务",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        onClose = function() taskModal_ = nil end,
    }
    taskModal_:AddContent(UI.Panel {
        padding = 10,
        gap = 10,
        children = {
            UI.Panel { children = rows },
            UI.Label { text = dailyTaskState_.rewardClaimed and "今日奖励已领取" or "全部完成可领取日常普通种子礼包 x1", fontSize = 12, fontColor = {120, 100, 80, 220}, textAlign = "center" },
            UI.Button {
                text = dailyTaskState_.rewardClaimed and "已领取" or "领取礼包",
                height = 40,
                fontSize = 14,
                variant = "primary",
                disabled = not canClaim,
                onClick = function()
                    suppressNextWorldTap_ = true
                    if canClaim then
                        dailyTaskState_.rewardClaimed = true
                        AddSeedPack("daily_basic", 1)
                        ShowToast("获得日常普通种子礼包")
                        if taskModal_ ~= nil then taskModal_:Close(); taskModal_ = nil end
                        RebuildUI()
                    end
                end,
            },
        },
    })
    taskModal_:Open()
end


local function PerformPlotAction(plotIndex, localPos)
    selectedPlot_ = plotIndex
    RefreshSelection()
    local plot = plots_[selectedPlot_]
    if plot == nil then return end

    if not plot.unlocked then
        ShowToast("这块田地尚未解锁")
        RefreshUI(true)
        return
    end

    if viewMode_ ~= ViewMode.PLANT then
        ShowToast("当前是查看状态，请先点击下方“开始种植”")
        RefreshUI(true)
        return
    end

    -- 根据当前 Tab 决定操作
    if plantTab_ == "seed" then
        -- 播种模式：点击土地播种
        if CountPlotPlants(plot) >= CONFIG.MaxCropsPerPlot then
            ShowToast("这块田地已满")
        elseif PlantSeedAt(selectedPlot_, selectedSeed_, localPos or Vector3(0, 0, 0)) then
            ShowToast("已播种 " .. PLANTS[selectedSeed_].name)
        else
            ShowToast("没有该种子，前往商店购买")
        end
    elseif plantTab_ == "harvest" then
        -- 收获模式：点击成熟作物收获
        if CountMaturePlants(plot) <= 0 then
            ShowToast("当前地块暂无成熟作物")
        else
            local crop = nil
            if localPos ~= nil then
                crop = FindPlantAtLocalPosition(plot, localPos, true)
            end
            if crop ~= nil then
                local cropName = crop.name
                if HarvestNearestMature(selectedPlot_, localPos) then
                    ShowToast("收获 " .. cropName)
                end
            else
                if HarvestNearestMature(selectedPlot_, nil) then
                    ShowToast("收获成功")
                end
            end
        end
    else
        ShowToast("切换到播种或收获进行操作")
    end
    if RebuildUI then RebuildUI() end
end

local function SelectSeedIndex(index)
    selectedSeed_ = Clamp(index, 1, #PLANTS)
    ShowToast("已选择 " .. PLANTS[selectedSeed_].name)
    RefreshUI(true)
end

RefreshUI = function(force)
    uiRefreshTimer_ = uiRefreshTimer_ + 0.016
    if not force and uiRefreshTimer_ < 0.1 then return end
    uiRefreshTimer_ = 0

    local seed = PLANTS[selectedSeed_]
    local owned = seedBag_[selectedSeed_] or 0
    local selectedPlot = plots_[selectedPlot_]
    local actionText = ""
    if viewMode_ == ViewMode.FARM then
        actionText = "点击田地查看状态，点击下方按钮开始种植"
    elseif selectedPlot ~= nil and CountMaturePlants(selectedPlot) > 0 then
        actionText = "点击成熟作物收获，点击空位继续播种"
    elseif selectedPlot ~= nil and CountPlotPlants(selectedPlot) < CONFIG.MaxCropsPerPlot then
        actionText = "点击田地播种，种子会在附近散开"
    else
        actionText = "田地已满，等待成熟后收获"
    end

    if moneyLabel_ ~= nil then
        moneyLabel_:SetText("金币 " .. money_)
    end
    if seedLabel_ ~= nil then
        seedLabel_:SetText("观光 0")  -- 观光值暂未实装
    end
    if plotLabel_ ~= nil then
        plotLabel_:SetText("LV" .. unlockedPlotCount_)
    end
    if helpLabel_ ~= nil then
        helpLabel_:SetText(string.format("已解锁区域 %d/%d", unlockedPlotCount_, #plots_))
    end
    if actionButton_ ~= nil then
        if viewMode_ == ViewMode.FARM then
            actionButton_:SetText("开始种植")
        else
            actionButton_:SetText("返回花园")
        end
    end
    if seedPackBadgeLabel_ ~= nil then
        seedPackBadgeLabel_:SetText(tostring(CountSeedPacks()))
    end
    RefreshSeedButtons()
end

--- 获取拥有种子的索引列表
local function GetOwnedSeedIndices()
    local list = {}
    for i = 1, #PLANTS do
        if (seedBag_[i] or 0) > 0 then
            table.insert(list, i)
        end
    end
    return list
end

--- 构建种植模式 Tab 内容（动森配色）
local function BuildPlantTabContent()
    local plot = plots_[selectedPlot_]
    local COL_TXT = {75, 55, 40, 255}      -- 深棕文字
    local COL_SUB = {130, 110, 85, 220}    -- 次要提示文字
    local CONTENT_H = 200                   -- 统一内容区高度

    if plantTab_ == "seed" then
        -- 播种 Tab：中间放大选中，两侧缩小（显示3张）
        local ownedList = GetOwnedSeedIndices()

        if #ownedList == 0 then
            return UI.Panel {
                height = CONTENT_H,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "暂无种子，前往商店购买", fontSize = 14, fontColor = COL_SUB },
                },
            }
        end

        -- 找到当前选中在列表中的位置
        local curIdx = 1
        for i, v in ipairs(ownedList) do
            if v == selectedSeed_ then curIdx = i; break end
        end

        -- 构建卡片：1 个种子显示 1 张，2 个显示 2 张，3 个及以上显示左/中/右 3 张
        local cards = {}
        local positions = {}
        if #ownedList == 1 then
            positions = { curIdx }
        elseif #ownedList == 2 then
            positions = { curIdx, curIdx == 1 and 2 or 1 }
        else
            positions = { curIdx - 1, curIdx, curIdx + 1 }
        end

        for _, pos in ipairs(positions) do
            local actualIdx = pos
            if actualIdx < 1 then actualIdx = #ownedList end
            if actualIdx > #ownedList then actualIdx = 1 end
            local isCenter = (actualIdx == curIdx)

            local plantIndex = ownedList[actualIdx]
            local plant = PLANTS[plantIndex]
            local owned = seedBag_[plantIndex] or 0
            local iconPath = string.format("image/icons_3d/seed (%d).png", plantIndex)
            local cardW = isCenter and 137 or 107
            local cardH = isCenter and 137 or 107
            local iconW = isCenter and 102 or 78
            local iconH = isCenter and 88 or 68

            table.insert(cards, UI.Panel {
                width = cardW, height = cardH,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 12,
                borderWidth = isCenter and 3 or 1,
                borderColor = isCenter and {94, 194, 131, 255} or {195, 180, 150, 200},
                overflow = "visible",
                onClick = function()
                    suppressNextWorldTap_ = true
                    selectedSeed_ = plantIndex
                    RebuildUI()
                end,
                children = {
                    UI.Panel {
                        width = iconW,
                        height = iconH,
                        marginBottom = 2,
                        backgroundImage = iconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = plant.name .. "种子", fontSize = isCenter and 12 or 10, fontColor = COL_TXT, textAlign = "center" },
                    UI.Panel {
                        position = "absolute",
                        right = -4, bottom = -4,
                        width = 30, height = 30,
                        borderRadius = 15,
                        zIndex = 2,
                        backgroundColor = {94, 194, 131, 255},
                        borderWidth = 2,
                        borderColor = {255, 253, 245, 255},
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label { text = tostring(owned), fontSize = owned >= 100 and 9 or 12, fontWeight = "bold", fontColor = {255, 255, 255, 255}, textAlign = "center" },
                        },
                    },
                },
            })
        end

        -- 左右切换按钮
        local function switchSeed(delta)
            local newIdx = curIdx + delta
            if newIdx < 1 then newIdx = #ownedList end
            if newIdx > #ownedList then newIdx = 1 end
            selectedSeed_ = ownedList[newIdx]
            RebuildUI()
        end

        return UI.Panel {
            height = CONTENT_H,
            gap = 6,
            children = {
                UI.Label { text = "选择种子后点击上方土地进行播种", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT, textAlign = "center" },
                UI.Panel {
                    justifyContent = "center",
                    alignItems = "center",
                    flexGrow = 1,
                    children = {
                        -- 卡片居中
                        UI.Panel {
                            flexDirection = "row",
                            justifyContent = "center",
                            alignItems = "center",
                            gap = 15,
                            flexGrow = 1,
                            children = { cards[1], cards[2], cards[3] },
                        },
                        -- 左箭头（悬浮靠左）
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            left = 0,
                            text = "<", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() suppressNextWorldTap_ = true; switchSeed(-1) end,
                        } or UI.Panel { width = 0, height = 0 },
                        -- 右箭头（悬浮靠右）
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            right = 0,
                            text = ">", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() suppressNextWorldTap_ = true; switchSeed(1) end,
                        } or UI.Panel { width = 0, height = 0 },
                    },
                },
            },
        }

    elseif plantTab_ == "harvest" then
        -- 收获 Tab：成熟作物卡片
        local harvestCards = {}
        if plot ~= nil and plot.plants ~= nil then
            for _, crop in ipairs(plot.plants) do
                if crop.mature then
                    local tags = {}
                    if crop.mutation and crop.mutation.specials then
                        for _, sp in ipairs(crop.mutation.specials) do
                            table.insert(tags, UI.Panel {
                                paddingTop = 2, paddingBottom = 2, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = {94, 194, 131, 255}, borderRadius = 4,
                                children = { UI.Label { text = sp.name or sp.key, fontSize = 9, fontColor = {255, 255, 255, 255} } },
                            })
                        end
                    end
                    table.insert(harvestCards, UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        padding = 10,
                        marginBottom = 6,
                        backgroundColor = {255, 253, 245, 255},
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = {195, 180, 150, 200},
                        children = {
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1, gap = 4,
                                children = {
                                    UI.Label { text = crop.name, fontSize = 13, fontWeight = "bold", fontColor = COL_TXT },
                                    #tags > 0 and UI.Panel { flexDirection = "row", gap = 4, flexWrap = "wrap", children = tags } or UI.Panel { height = 0 },
                                },
                            },
                            UI.Button {
                                text = "收获", width = 52, height = 30, fontSize = 12,
                                backgroundColor = {94, 194, 131, 255}, fontColor = {255, 255, 255, 255}, borderRadius = 8,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    HarvestNearestMature(selectedPlot_, crop.localPos)
                                    RebuildUI()
                                end,
                            },
                        },
                    })
                end
            end
        end

        if #harvestCards > 0 then
            return UI.Panel {
                height = CONTENT_H,
                gap = 6,
                children = {
                    UI.Label { text = "点击土地中成熟的作物收获", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT },
                    UI.ScrollView {
                        scrollY = true, flexGrow = 1, flexBasis = 0,
                        children = harvestCards,
                    },
                },
            }
        else
            return UI.Panel {
                height = CONTENT_H,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "当前地块暂无成熟作物", fontSize = 14, fontColor = COL_SUB },
                },
            }
        end

    else
        -- 背包 Tab：更大的 2行×4列物品卡片
        local slots = {}
        for i = 1, 10 do
            local item = harvested_[i]
            local itemIconPath = item and item.plantIndex and string.format("image/plants/plants (%d).png", item.plantIndex) or nil
            local weightText = item and item.weight and string.format("%.2fkg", item.weight) or ""
            local isGiant = item ~= nil and item.weightTier == "Giant"
            table.insert(slots, UI.Panel {
                width = "18%",
                height = 98,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 8,
                borderWidth = 1,
                borderColor = {195, 180, 150, 200},
                onClick = function()
                    suppressNextWorldTap_ = true
                    if item ~= nil then
                        OpenBagItemDetail(item)
                    end
                end,
                children = item and {
                    UI.Panel {
                        width = 56,
                        height = 46,
                        marginBottom = 3,
                        backgroundImage = itemIconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = item.name, fontSize = 10, fontWeight = "bold", fontColor = COL_TXT, textAlign = "center" },
                    UI.Label { text = weightText, fontSize = 10, fontWeight = "bold", fontColor = isGiant and {220, 80, 70, 255} or {94, 160, 100, 255}, textAlign = "center" },
                    isGiant and UI.Panel {
                        position = "absolute",
                        top = 2,
                        right = 2,
                        paddingLeft = 3,
                        paddingRight = 3,
                        paddingTop = 1,
                        paddingBottom = 1,
                        borderRadius = 4,
                        backgroundColor = {220, 80, 70, 235},
                        children = {
                            UI.Label { text = "G", fontSize = 7, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
                        },
                    } or UI.Panel { width = 0, height = 0 },
                } or {},
            })
        end

        return UI.Panel {
            height = CONTENT_H + 110,
            children = {
                UI.ScrollView {
                    scrollY = true,
                    showScrollbar = false,
                    flexGrow = 1,
                    flexBasis = 0,
                    children = {
                        UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 8, justifyContent = "flex-start", children = slots },
                    },
                },
            },
        }
    end
end

RebuildUI = function()
    local previewItem = selectedBagItem_

    local ACNHTheme = require("ui_theme_acnh")

    if not uiInitialized_ then
        UI.Init({
            theme = ACNHTheme.theme,
            fonts = {
                { family = "sans", weights = {
                    normal = "Fonts/ResourceHanRoundedCN-Bold.ttf",
                    bold = "Fonts/ResourceHanRoundedCN-Bold.ttf",
                } },
            },
            scale = UI.Scale.DEFAULT,
        })
        uiInitialized_ = true
    end

    -- === 颜色常量（动物森友会风格 v2） ===
    local COL_CREAM      = {255, 253, 245, 255}     -- 奶油白正文
    local COL_MONEY      = {255, 210, 50, 255}      -- 日光黄金币（饱和度更高）
    local COL_BROWN      = {75, 50, 40, 255}        -- 深棕主文字（更深更实）
    local COL_BROWN_SOFT = {115, 85, 65, 255}       -- 柔棕次文字
    local COL_GREEN_DARK = {38, 90, 45, 255}        -- 暗绿辅助
    local COL_LEAF       = {80, 185, 120, 255}      -- 叶子绿
    local COL_SAND       = {195, 155, 90, 255}      -- 暖沙棕（更饱和）

    -- === Labels ===
    moneyLabel_ = UI.Label {
        text = "金币 0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    seedLabel_ = UI.Label {
        text = "观光 0",
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {95, 75, 55, 255},
    }
    seedPackBadgeLabel_ = UI.Label {
        text = "0",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
        textAlign = "center",
    }
    plotLabel_ = UI.Label {
        text = "LV1",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
    }
    actionLabel_ = UI.Label {
        text = "点击田地播种或收获",
        fontSize = 12,
        fontColor = {255, 250, 235, 220},
    }
    inventoryLabel_ = UI.Label {
        text = "背包 --",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COL_MONEY,
    }
    toastLabel_ = UI.Label {
        text = "当前为查看状态，点击下方开始种植",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COL_GREEN_DARK,
        textAlign = "center",
    }
    helpLabel_ = UI.Label {
        text = "已解锁区域 1/9",
        fontSize = 14,
        fontColor = {80, 80, 80, 255},
        textAlign = "center",
    }

    -- === 主操作按钮 ===
    actionButton_ = UI.Button {
        text = "开始种植",
        variant = "primary",
        height = 90,
        width = 228,
        fontSize = 26,
        fontWeight = "bold",
        borderRadius = 28,
        onClick = function()
            suppressNextWorldTap_ = true
            if viewMode_ == ViewMode.FARM then
                EnterPlantView()
            else
                EnterFarmView()
            end
        end,
    }

    -- === 种子切换按钮（暖沙棕次按钮） ===
    local prevSeedButton = UI.Button {
        text = "上一种",
        variant = "secondary",
        height = 46,
        fontSize = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ - 1
            if selectedSeed_ < 1 then selectedSeed_ = #PLANTS end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    local nextSeedButton = UI.Button {
        text = "下一种",
        variant = "secondary",
        height = 46,
        fontSize = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            selectedSeed_ = selectedSeed_ + 1
            if selectedSeed_ > #PLANTS then selectedSeed_ = 1 end
            SelectSeedIndex(selectedSeed_)
        end,
    }

    -- === 购买/出售按钮 ===
    local buyButton = UI.Button {
        text = "购买种子",
        variant = "primary",
        height = 50,
        fontSize = 15,
        onClick = function()
            suppressNextWorldTap_ = true
            if BuySelectedSeed() then
                ShowToast("购买 " .. PLANTS[selectedSeed_].name)
            else
                ShowToast("金币不足")
            end
            RefreshUI(true)
        end,
    }

    local sellButton = UI.Button {
        text = "出售背包",
        variant = "secondary",
        height = 50,
        fontSize = 15,
        onClick = function()
            suppressNextWorldTap_ = true
            local earned = SellAllHarvested()
            if earned > 0 then
                ShowToast("出售获得 " .. earned .. " 金币")
            else
                ShowToast("背包为空")
            end
            RefreshUI(true)
        end,
    }

    -- === 视角控制按钮（轮廓风格） ===
    local rotateLeftButton = UI.Button {
        text = "左转",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraYaw_ = cameraYaw_ - 22.5
            UpdateCamera()
        end,
    }

    local rotateRightButton = UI.Button {
        text = "右转",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraYaw_ = cameraYaw_ + 22.5
            UpdateCamera()
        end,
    }

    local zoomInButton = UI.Button {
        text = "放大",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraDistance_ = math.max(CONFIG.FarmViewMinDistance, cameraDistance_ - 1.0)
            UpdateCamera()
        end,
    }

    local zoomOutButton = UI.Button {
        text = "缩小",
        height = 40,
        fontSize = 12,
        backgroundColor = {255, 250, 235, 0},
        borderWidth = 3,
        borderColor = COL_SAND,
        fontColor = COL_BROWN,
        borderRadius = 14,
        onClick = function()
            suppressNextWorldTap_ = true
            cameraDistance_ = math.min(CONFIG.FarmViewMaxDistance, cameraDistance_ + 1.0)
            UpdateCamera()
        end,
    }

    -- === 根面板布局 ===
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- ▼ 顶部信息栏（动森风格：奶油底 + 柔绿描边）
            UI.Panel {
                position = "absolute",
                top = 14,
                left = 12,
                right = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                pointerEvents = "box-none",
                children = {
                    -- 等级标签（叶子绿底）
                    UI.Panel {
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 14, paddingRight = 14,
                        backgroundColor = {78, 172, 110, 255},
                        borderRadius = 14,
                        children = {
                            plotLabel_,
                        },
                    },
                    -- 观光值（奶油底无描边 + 紫色宝石图标）
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 7,
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 10, paddingRight = 14,
                        backgroundColor = {255, 250, 240, 240},
                        borderRadius = 14,
                        children = {
                            -- 观光图标（淡紫色圆底 + 白色星星）
                            UI.Panel {
                                width = 22, height = 22,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {190, 160, 230, 255} },
                                    UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {155, 120, 210, 255} },
                                    UI.Label { position = "absolute", text = "★", fontSize = 11, fontColor = {245, 240, 255, 255} },
                                },
                            },
                            seedLabel_,
                        },
                    },
                    -- 金币（奶油底无描边 + 金币$图标）
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 7,
                        paddingTop = 7, paddingBottom = 7,
                        paddingLeft = 10, paddingRight = 14,
                        backgroundColor = {255, 250, 240, 240},
                        borderRadius = 14,
                        children = {
                            -- 金币图标（金圆 + $符号）
                            UI.Panel {
                                width = 22, height = 22,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 22, height = 22, borderRadius = 11, backgroundColor = {255, 205, 60, 255} },
                                    UI.Panel { position = "absolute", width = 14, height = 14, borderRadius = 7, backgroundColor = {230, 175, 30, 255} },
                                    UI.Label { position = "absolute", text = "$", fontSize = 11, fontWeight = "bold", fontColor = {255, 245, 200, 255} },
                                },
                            },
                            moneyLabel_,
                        },
                    },
                },
            },

            -- ▼ Toast 提示条（浅绿底 + 粗叶子绿边框）
            UI.Panel {
                position = "absolute",
                top = 145,
                left = 28,
                right = 28,
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        paddingTop = 12,
                        paddingBottom = 12,
                        paddingLeft = 20,
                        paddingRight = 20,
                        backgroundColor = {228, 243, 230, 242},
                        borderColor = {70, 170, 100, 210},
                        borderWidth = 3,
                        borderRadius = 16,
                        children = { toastLabel_ },
                    },
                },
            },

            -- ▼ 底部操作面板
            viewMode_ == ViewMode.FARM and UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 60,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "flex-end",
                gap = 16,
                pointerEvents = "box-none",
                children = {
                    -- 商店按钮（白底+绿字）
                    UI.Button {
                        text = "商店",
                        width = 90,
                        height = 90,
                        fontSize = 22,
                        fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 245},
                        fontColor = {78, 155, 100, 255},
                        borderRadius = 28,
                        onClick = function()
                            suppressNextWorldTap_ = true
                            Shop.Open()
                        end,
                    },
                    -- 开始种植
                    actionButton_,
                    -- 任务按钮与种子包入口
                    UI.Panel {
                        width = 90,
                        height = 142,
                        alignItems = "center",
                        justifyContent = "flex-end",
                        overflow = "visible",
                        children = {
                            CountSeedPacks() > 0 and UI.Button {
                                position = "absolute",
                                top = 0,
                                text = "礼包",
                                width = 68,
                                height = 42,
                                fontSize = 15,
                                fontWeight = "bold",
                                backgroundColor = {245, 232, 198, 250},
                                fontColor = {125, 88, 45, 255},
                                borderRadius = 18,
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 240},
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    OpenSeedPackHub()
                                end,
                            } or UI.Panel { width = 0, height = 0 },
                            CountSeedPacks() > 0 and UI.Panel {
                                position = "absolute",
                                top = -6,
                                right = 4,
                                width = 24,
                                height = 24,
                                borderRadius = 12,
                                backgroundColor = {225, 55, 45, 255},
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 255},
                                justifyContent = "center",
                                alignItems = "center",
                                children = { seedPackBadgeLabel_ },
                            } or UI.Panel { width = 0, height = 0 },
                            UI.Button {
                                text = "任务",
                                width = 90,
                                height = 90,
                                fontSize = 22,
                                fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 245},
                                fontColor = {78, 155, 100, 255},
                                borderRadius = 28,
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    OpenTaskPanel()
                                end,
                            },
                        },
                    },
                },
            } or UI.Panel {
                -- 种植模式：三Tab面板（动森风格）
                position = "absolute",
                left = 0, right = 0, bottom = 0,
                paddingTop = 12, paddingBottom = 125,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = {250, 245, 235, 252},
                borderRadius = {22, 22, 0, 0},
                children = {
                    -- Tab 按钮行（等高、动森配色）
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginBottom = 10,
                        children = {
                            UI.Button {
                                text = "播种", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "seed" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "seed" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; selectedBagItem_ = nil; if ClearBagPreview ~= nil then ClearBagPreview() end; plantTab_ = "seed"; RebuildUI() end,
                            },
                            UI.Button {
                                text = "收获", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "harvest" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "harvest" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; selectedBagItem_ = nil; if ClearBagPreview ~= nil then ClearBagPreview() end; plantTab_ = "harvest"; RebuildUI() end,
                            },
                            UI.Button {
                                text = "背包", flexGrow = 1, height = 40, fontSize = 14, fontWeight = "bold",
                                backgroundColor = plantTab_ == "bag" and {94, 194, 131, 255} or {195, 230, 205, 255},
                                fontColor = plantTab_ == "bag" and {255, 255, 255, 255} or {70, 130, 85, 255},
                                borderRadius = 12,
                                onClick = function() suppressNextWorldTap_ = true; plantTab_ = "bag"; RebuildUI() end,
                            },
                        },
                    },
                    -- Tab 内容区
                    BuildPlantTabContent(),
                },
            },

            -- ▼ 收起按钮（种植模式，右下角独立）
            viewMode_ == ViewMode.PLANT and UI.Panel {
                position = "absolute",
                bottom = plantTab_ == "bag" and 520 or 410,
                right = 12,
                children = {
                    UI.Button {
                        text = "▼ 收起", width = 90, height = 34, fontSize = 12, fontWeight = "bold",
                        backgroundColor = {255, 250, 240, 240}, fontColor = {120, 100, 75, 255},
                        borderRadius = 16, borderWidth = 2, borderColor = {185, 165, 130, 220},
                        onClick = function()
                            suppressNextWorldTap_ = true
                            EnterFarmView()
                        end,
                    },
                },
            } or UI.Panel { width = 0, height = 0 },
            -- ▼ 背包详情弹窗
            selectedBagItem_ ~= nil and UI.Panel {
                position = "absolute",
                left = 0,
                right = 0,
                top = 0,
                bottom = 0,
                backgroundColor = {0, 0, 0, 120},
                justifyContent = "center",
                alignItems = "center",
                paddingLeft = 20,
                paddingRight = 20,
                paddingTop = 90,
                paddingBottom = viewMode_ == ViewMode.PLANT and 330 or 90,
                children = {
                    UI.Panel {
                        width = "100%",
                        maxWidth = 340,
                        paddingTop = 18,
                        paddingBottom = 18,
                        paddingLeft = 16,
                        paddingRight = 16,
                        backgroundColor = {255, 253, 245, 248},
                        borderRadius = 24,
                        borderWidth = 3,
                        borderColor = {94, 194, 131, 235},
                        boxShadow = { { x = 0, y = 8, blur = 20, spread = 0, color = {0, 0, 0, 70} } },
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                marginBottom = 12,
                                children = {
                                    UI.Panel {
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        children = {
                                            UI.Label { text = selectedBagItem_.name or "作物", fontSize = 24, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                            UI.Label { text = "作物详情", fontSize = 12, fontColor = {130, 110, 85, 230} },
                                        },
                                    },
                                    UI.Button {
                                        text = "×", width = 38, height = 34, fontSize = 20, fontWeight = "bold",
                                        backgroundColor = {255, 250, 240, 0}, fontColor = {120, 90, 70, 255}, borderRadius = 14,
                                        onClick = function()
                                            suppressNextWorldTap_ = true
                                            CloseBagItemDetail()
                                        end,
                                    },
                                },
                            },
                            UI.Panel {
                                height = 218,
                                width = "100%",
                                marginBottom = 14,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = {255, 253, 245, 255},
                                borderRadius = 22,
                                borderWidth = 2,
                                borderColor = {132, 202, 150, 225},
                                overflow = "hidden",
                                children = {
                                    UI.Panel { position = "absolute", left = 26, right = 26, bottom = 28, height = 28, borderRadius = 14, backgroundColor = {90, 160, 100, 36} },
                                    UI.Panel {
                                        width = 176,
                                        height = 176,
                                        backgroundImage = selectedBagItem_.plantIndex and string.format("image/plants/plants (%d).png", selectedBagItem_.plantIndex) or nil,
                                        backgroundFit = "contain",
                                    },
                                },
                            },
                            UI.Panel {
                                gap = 8,
                                marginBottom = 14,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        paddingTop = 10,
                                        paddingBottom = 10,
                                        paddingLeft = 14,
                                        paddingRight = 14,
                                        backgroundColor = {255, 250, 240, 220},
                                        borderRadius = 12,
                                        children = {
                                            UI.Label { text = "重量", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                            UI.Label { text = string.format("%.2fkg", selectedBagItem_.weight or 0), fontSize = 19, fontWeight = "bold", fontColor = selectedBagItem_.weightTier == "Giant" and {220, 80, 70, 255} or {94, 160, 100, 255} },
                                        },
                                    },
                                    UI.Panel {
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        paddingTop = 10,
                                        paddingBottom = 10,
                                        paddingLeft = 14,
                                        paddingRight = 14,
                                        backgroundColor = {255, 250, 240, 220},
                                        borderRadius = 12,
                                        children = {
                                            UI.Label { text = "售价", fontSize = 15, fontColor = {115, 85, 65, 255} },
                                            UI.Label { text = string.format("%d 金币", selectedBagItem_.price or 0), fontSize = 19, fontWeight = "bold", fontColor = {190, 130, 40, 255} },
                                        },
                                    },
                                },
                            },
                            UI.Button {
                                text = "出售",
                                width = "100%",
                                height = 48,
                                fontSize = 18,
                                fontWeight = "bold",
                                backgroundColor = {94, 194, 131, 255},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 16,
                                borderWidth = 2,
                                borderColor = {255, 255, 255, 230},
                                onClick = function()
                                    suppressNextWorldTap_ = true
                                    local item = selectedBagItem_
                                    local earned = SellBagItem(item)
                                    if earned > 0 then
                                        ShowToast("出售获得 " .. earned .. " 金币")
                                    end
                                    RebuildUI()
                                end,
                            },
                        },
                    },
                },
            } or UI.Panel { width = 0, height = 0 },
            BuildSeedPackOverlay(),
            BuildSeedPackResultOverlay(),

        }
    }
    UI.SetRoot(root)
    if previewItem ~= nil then
        CreateBagPreview(previewItem)
    end
    RefreshUI(true)
end

SelectPlotByDelta = function(dx, dz)
    local col = ((selectedPlot_ - 1) % CONFIG.GridCols) + 1
    local row = math.floor((selectedPlot_ - 1) / CONFIG.GridCols) + 1
    col = Clamp(col + dx, 1, CONFIG.GridCols)
    row = Clamp(row + dz, 1, CONFIG.GridRows)
    selectedPlot_ = (row - 1) * CONFIG.GridCols + col
    RefreshSelection()
    RefreshUI(true)
end

local function CycleSeed(delta)
    selectedSeed_ = selectedSeed_ + delta
    if selectedSeed_ < 1 then selectedSeed_ = #PLANTS end
    if selectedSeed_ > #PLANTS then selectedSeed_ = 1 end
    RefreshUI(true)
end

local function IsWorldTapArea(x, y)
    local h = graphics:GetHeight()
    local bottomReserved = 86
    if viewMode_ == ViewMode.PLANT then
        bottomReserved = 260
    end
    return y > 170 and y < h - bottomReserved
end

local function PlotHitFromScreen(x, y)
    if camera_ == nil then return nil, nil end
    if not IsWorldTapArea(x, y) then return nil, nil end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local ray = camera_:GetScreenRay(x / w, y / h)
    if math.abs(ray.direction.y) < 0.001 then return nil, nil end

    -- 射线打到种植土表面世界高度 (plotNodeY 0.42 + DirtMound top 0.50 = 0.92)
    local surfaceY = 0.92
    local t = (surfaceY - ray.origin.y) / ray.direction.y
    if t <= 0 then return nil, nil end
    local hit = ray.origin + ray.direction * t

    local bestIndex = nil
    local bestDist = 9999
    local bestLocal = nil
    for i = 1, #plots_ do
        local pos = PlotWorldPosition(i)
        local dx = hit.x - pos.x
        local dz = hit.z - pos.z
        local dist = dx * dx + dz * dz
        if dist < bestDist then
            bestDist = dist
            bestIndex = i
            -- 将世界坐标差值转为 plotNode 本地坐标（父节点 scale=PlotSize）
            bestLocal = Vector3(dx / CONFIG.PlotSize, 0, dz / CONFIG.PlotSize)
        end
    end

    -- 判定范围：种植土本地半宽 0.55 的平方
    local halfSize = 0.55
    if bestIndex ~= nil and bestDist <= (halfSize * CONFIG.PlotSize) * (halfSize * CONFIG.PlotSize) then
        return bestIndex, ClampToPlot(bestLocal)
    end
    return nil, nil
end

local function HandleWorldTap(x, y)
    if suppressNextWorldTap_ then
        suppressNextWorldTap_ = false
        return
    end
    local plotIndex, localPos = PlotHitFromScreen(x, y)
    if plotIndex ~= nil then
        if viewMode_ == ViewMode.FARM then
            selectedPlot_ = plotIndex
            RefreshSelection()
            ShowToast("已选中田地，可查看状态；点击下方开始种植后操作")
            RefreshUI(true)
        else
            PerformPlotAction(plotIndex, localPos)
        end
    end
end

function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function HandleMouseMove(eventType, eventData)
    if viewMode_ ~= ViewMode.FARM then return end
    if not input:GetMouseButtonDown(MOUSEB_LEFT) then return end
    local y = eventData["Y"]:GetInt()
    if not IsWorldTapArea(eventData["X"]:GetInt(), y) then return end

    local dx = eventData["DX"]:GetInt()
    local dy = eventData["DY"]:GetInt()
    if math.abs(dx) > 0 or math.abs(dy) > 0 then
        cameraYaw_ = cameraYaw_ + dx * 0.16
        cameraPitch_ = Clamp(cameraPitch_ + dy * 0.08, 24.0, 68.0)
        UpdateCamera()
    end
end

function HandleMouseWheel(eventType, eventData)
    if viewMode_ ~= ViewMode.FARM then return end
    local wheel = eventData["Wheel"]:GetInt()
    if wheel == 0 then return end
    cameraDistance_ = Clamp(cameraDistance_ - wheel * 0.8, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
    UpdateCamera()
end

function HandleTouchBegin(eventType, eventData)
    HandleWorldTap(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function HandleTouchMove(eventType, eventData)
    touchGestureActive_ = true
end

local function UpdateTouchCameraGesture()
    if viewMode_ ~= ViewMode.FARM then
        lastPinchDistance_ = 0
        return
    end

    local touchCount = input.numTouches
    if touchCount == 1 then
        lastPinchDistance_ = 0
        local touch = input:GetTouch(0)
        if touch ~= nil and not touch.touchedElement then
            local dx = touch.delta.x
            local dy = touch.delta.y
            if math.abs(dx) > 0 or math.abs(dy) > 0 then
                touchGestureActive_ = true
                cameraYaw_ = cameraYaw_ - dx * 0.16
                cameraPitch_ = Clamp(cameraPitch_ + dy * 0.08, 24.0, 68.0)
                UpdateCamera()
            end
        end
    elseif touchCount >= 2 then
        local touch1 = input:GetTouch(0)
        local touch2 = input:GetTouch(1)
        if touch1 ~= nil and touch2 ~= nil and not touch1.touchedElement and not touch2.touchedElement then
            local dx = touch1.position.x - touch2.position.x
            local dy = touch1.position.y - touch2.position.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if lastPinchDistance_ > 0 then
                local delta = dist - lastPinchDistance_
                if math.abs(delta) > 0.5 then
                    touchGestureActive_ = true
                    cameraDistance_ = Clamp(cameraDistance_ - delta * 0.018, CONFIG.FarmViewMinDistance, CONFIG.FarmViewMaxDistance)
                    UpdateCamera()
                end
            end
            lastPinchDistance_ = dist
        end
    else
        lastPinchDistance_ = 0
        touchGestureActive_ = false
    end
end

local function HandleInput(dt)
    if input:GetKeyPress(KEY_LEFT) then SelectPlotByDelta(-1, 0) end
    if input:GetKeyPress(KEY_RIGHT) then SelectPlotByDelta(1, 0) end
    if input:GetKeyPress(KEY_UP) then SelectPlotByDelta(0, -1) end
    if input:GetKeyPress(KEY_DOWN) then SelectPlotByDelta(0, 1) end
    if input:GetKeyPress(KEY_Q) then CycleSeed(-1) end
    if input:GetKeyPress(KEY_E) then CycleSeed(1) end
    if input:GetKeyPress(KEY_B) then BuySelectedSeed(); RefreshUI(true) end
    if input:GetKeyPress(KEY_G) then SellAllHarvested(); RefreshUI(true) end

    if input:GetKeyPress(KEY_SPACE) then
        if viewMode_ == ViewMode.FARM then
            EnterPlantView()
        else
            local plot = plots_[selectedPlot_]
            if plot ~= nil and CountMaturePlants(plot) > 0 then
                HarvestNearestMature(selectedPlot_, nil)
            elseif plot ~= nil and CountPlotPlants(plot) < CONFIG.MaxCropsPerPlot then
                PlantSeed(selectedPlot_, selectedSeed_)
            end
            RefreshUI(true)
        end
    end

    if input:GetKeyDown(KEY_A) then
        cameraYaw_ = cameraYaw_ - 70.0 * dt
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_D) then
        cameraYaw_ = cameraYaw_ + 70.0 * dt
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_W) then
        cameraDistance_ = math.max(CONFIG.FarmViewMinDistance, cameraDistance_ - 8.0 * dt)
        UpdateCamera()
    end
    if input:GetKeyDown(KEY_S) then
        cameraDistance_ = math.min(CONFIG.FarmViewMaxDistance, cameraDistance_ + 8.0 * dt)
        UpdateCamera()
    end
end

local function SetVisualScaleByProgress(plantData)
    local progress = plantData.elapsed / plantData.growTime
    progress = Clamp(progress, 0.0, 1.0)
    if progress < 0.18 then
        if plantData.visual ~= nil then
            plantData.visual.enabled = false
        end
        return
    end

    if not plantData.sprouted then
        plantData.sprouted = true
        plantData.visual = CreatePlantVisual(plantData.root, plantData.config, plantData.mutation, plantData.material)
        if plantData.seedVisual ~= nil then
            plantData.seedVisual:Remove()
            plantData.seedVisual = nil
        end
        print("种子发芽，切换为作物模型: " .. plantData.name)
    end

    local growProgress = (progress - 0.18) / 0.82
    growProgress = Clamp(growProgress, 0.0, 1.0)
    local scale = (0.18 + 0.82 * growProgress) * plantData.mutation.sizeScale
    if plantData.visual ~= nil then
        plantData.visual.scale = Vector3(scale, scale, scale)
    end
end

local function RainbowColor(t)
    local r = 0.5 + 0.5 * math.sin(t)
    local g = 0.5 + 0.5 * math.sin(t + 2.094)
    local b = 0.5 + 0.5 * math.sin(t + 4.188)
    return Color(r, g, b, 1.0)
end

local function UpdatePlantEffects(plantData, dt)
    local mutation = plantData.mutation
    if HasSpecial(mutation, "rainbow") then
        local rainbow = RainbowColor(gameTime_ * 2.5)
        plantData.material:SetShaderParameter("MatDiffColor", Variant(rainbow))
        plantData.material:SetShaderParameter("MatEmissiveColor", Variant(Color(rainbow.r * 0.35, rainbow.g * 0.35, rainbow.b * 0.35, 1.0)))
    end

    for i, effect in ipairs(plantData.effectNodes) do
        effect:Rotate(Quaternion((25 + i * 18) * dt, Vector3.UP))
        local bob = math.sin(gameTime_ * (1.4 + i * 0.17)) * 0.035
        effect.position = Vector3(0, bob, 0)
    end
end

local function UpdatePlants(dt)
    gameTime_ = gameTime_ + dt
    for _, plot in ipairs(plots_) do
        if plot.plants ~= nil then
            for _, plantData in ipairs(plot.plants) do
                if not plantData.mature then
                    plantData.elapsed = plantData.elapsed + dt
                    SetVisualScaleByProgress(plantData)
                    if plantData.elapsed >= plantData.growTime then
                        plantData.mature = true
                        plantData.elapsed = plantData.growTime
                        if plantData.visual == nil then
                            plantData.visual = CreatePlantVisual(plantData.root, plantData.config, plantData.mutation, plantData.material)
                        end
                        if plantData.seedVisual ~= nil then
                            plantData.seedVisual:Remove()
                            plantData.seedVisual = nil
                        end
                        plantData.root:Translate(Vector3(0, 0.06, 0))
                        CreateSpecialEffects(plantData)
                        print("成熟: " .. plantData.name .. "，可收获")
                    end
                else
                    plantData.root:Rotate(Quaternion(12.0 * dt, Vector3.UP))
                end
                if plantData.sprouted or plantData.mature then
                    UpdatePlantEffects(plantData, dt)
                end
            end
        end
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    HandleInput(dt)
    UpdateTouchCameraGesture()
    UpdatePlants(dt)
    Shop.Update(dt)

    if toastTimer_ > 0 then
        toastTimer_ = toastTimer_ - dt
        if toastTimer_ <= 0 and toastLabel_ ~= nil then
            if viewMode_ == ViewMode.FARM then
                toastLabel_:SetText("当前为查看状态，点击下方开始种植")
            else
                toastLabel_:SetText("种植模式：点击田地播种或收获")
            end
        end
    end
    RefreshUI(false)
end

--- 获取花园等级（基于解锁田地数）
local function GetGardenLevel()
    -- 等级规则：每解锁1块田地 = 1级，初始1级
    return math.max(1, unlockedPlotCount_)
end

-- ═══════ BGM 随机列表循环播放 ═══════
local BGM_TRACKS = {
    "audio/music_1781979156772.ogg",
    "audio/music_1781979661883.ogg",
    "audio/music_1782020682333.ogg",
    "audio/music_1782020930957.ogg",
}
local bgmPlaylist_ = {}
local bgmCurrentIndex_ = 0
---@type SoundSource|nil
local bgmSource_ = nil
---@type Node|nil
local bgmNode_ = nil

local function ShuffleBGMPlaylist()
    bgmPlaylist_ = {}
    for i = 1, #BGM_TRACKS do
        bgmPlaylist_[i] = i
    end
    for i = #bgmPlaylist_, 2, -1 do
        local j = math.random(1, i)
        bgmPlaylist_[i], bgmPlaylist_[j] = bgmPlaylist_[j], bgmPlaylist_[i]
    end
    bgmCurrentIndex_ = 0
end

local function PlayNextBGM()
    bgmCurrentIndex_ = bgmCurrentIndex_ + 1
    if bgmCurrentIndex_ > #bgmPlaylist_ then
        ShuffleBGMPlaylist()
        bgmCurrentIndex_ = 1
    end
    local trackIndex = bgmPlaylist_[bgmCurrentIndex_]
    local path = BGM_TRACKS[trackIndex]
    local sound = cache:GetResource("Sound", path)
    if sound == nil then
        print("[BGM] 加载失败: " .. path)
        return
    end
    sound.looped = false
    if bgmSource_ ~= nil then
        bgmSource_:Play(sound)
    end
    print("[BGM] 正在播放: " .. path)
end

function InitBGM()
    if scene_ == nil then return end
    bgmNode_ = scene_:CreateChild("BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = SOUND_MUSIC
    bgmSource_.gain = 0.35
    ShuffleBGMPlaylist()
    PlayNextBGM()
    SubscribeToEvent("SoundFinished", "HandleSoundFinished")
end

function HandleSoundFinished(eventType, eventData)
    local finishedSource = eventData["SoundSource"]:GetPtr("SoundSource")
    if finishedSource == bgmSource_ then
        PlayNextBGM()
    end
end
-- ═══════════════════════════════

function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title
    math.randomseed(os.time())

    InitMaterials()
    CreateScene()
    CreateFarm()

    -- 初始化商店系统
    Shop.Init({
        PLANTS = PLANTS,
        getMoney = function() return money_ end,
        getGardenLevel = GetGardenLevel,
        onBuy = function(cost, plantIndex)
            money_ = money_ - cost
            if plantIndex ~= nil then
                AddSeedToBag(plantIndex, 1, 0)
            end
            RefreshUI(true)
        end,
        showToast = ShowToast,
    })

    AddSeedToBag(1, 4, 0)
    AddSeedToBag(2, 2, 0)
    AddSeedToBag(3, 1, 0)
    AddSeedPack("daily_basic", 3)
    AddSeedPack("silver_common", 2)
    AddSeedPack("silver_uncommon", 1)
    AddSeedPack("silver_rare", 1)

    RebuildUI()
    RefreshUI(true)

    RefreshSelection()
    UpdateCamera()
    CreateSkybox()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SampleInitMouseMode(MM_FREE)

    -- BGM 随机列表循环播放
    InitBGM()

    print("=== Grow A Garden 核心玩法原型启动 ===")
    print("已赠送胡萝卜x4、番茄x2、草莓x1，以及测试种子包：日常x3、银质普通x2、银质罕见x1、银质稀有x1。")
end

function Stop()
    UI.Shutdown()
end
