-- ============================================================================
-- 天赋系统 (Talent System)
-- Grow A Garden
-- ============================================================================
-- 玩家收获作物获得经验值，升级获得天赋点，点亮天赋获得永久增益。
-- 天赋效果通过 GetBonus(key) 查询，由外部系统（CropSystem、出售等）调用。
-- ============================================================================

local TalentSystem = {}

-- ============================================================================
-- 天赋配置
-- ============================================================================

TalentSystem.TALENTS = {
    { id = "drop_rate_1", name = "拾穗", desc = "收获掉包率提高 10%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.10, cost = 1, goldCost = 500, requires = nil },
    { id = "drop_rate_2", name = "丰收之手", desc = "收获掉包率提高 20%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.10, cost = 1, goldCost = 2000, requires = "drop_rate_1" },
    { id = "drop_rate_3", name = "大地恩赐", desc = "收获掉包率提高 35%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.15, cost = 2, goldCost = 8000, requires = "drop_rate_2" },
    { id = "drop_rate_4", name = "幸运之手", desc = "收获掉包率提高 50%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.15, cost = 2, goldCost = 30000, requires = "drop_rate_3" },
    { id = "drop_rate_5", name = "黄金手气", desc = "收获掉包率提高 75%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.25, cost = 3, goldCost = 100000, requires = "drop_rate_4" },

    { id = "grow_speed_1", name = "催熟", desc = "成熟时间缩短 5%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 1, goldCost = 800, requires = nil },
    { id = "grow_speed_2", name = "光合加速", desc = "成熟时间缩短 10%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 1, goldCost = 3000, requires = "grow_speed_1" },
    { id = "grow_speed_3", name = "时光催化", desc = "成熟时间缩短 15%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 2, goldCost = 12000, requires = "grow_speed_2" },
    { id = "grow_speed_4", name = "春风化雨", desc = "成熟时间缩短 20%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 2, goldCost = 50000, requires = "grow_speed_3" },
    { id = "grow_speed_5", name = "瞬息绽放", desc = "成熟时间缩短 30%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.10, cost = 3, goldCost = 160000, requires = "grow_speed_4" },

    { id = "sell_bonus_1", name = "精明商人", desc = "出售价格提高 5%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 1, goldCost = 1000, requires = nil },
    { id = "sell_bonus_2", name = "定价大师", desc = "出售价格提高 10%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 1, goldCost = 4000, requires = "sell_bonus_1" },
    { id = "sell_bonus_3", name = "黄金触感", desc = "出售价格提高 16%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.06, cost = 2, goldCost = 16000, requires = "sell_bonus_2" },
    { id = "sell_bonus_4", name = "点石成金", desc = "出售价格提高 23%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.07, cost = 2, goldCost = 70000, requires = "sell_bonus_3" },
    { id = "sell_bonus_5", name = "财神降临", desc = "出售价格提高 35%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.12, cost = 3, goldCost = 220000, requires = "sell_bonus_4" },

    { id = "mutation_1", name = "基因启蒙", desc = "变异概率提高 10%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.10, cost = 1, goldCost = 1200, requires = nil },
    { id = "mutation_2", name = "双螺旋", desc = "变异概率提高 20%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.10, cost = 1, goldCost = 5000, requires = "mutation_1" },
    { id = "mutation_3", name = "基因突变", desc = "变异概率提高 35%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.15, cost = 2, goldCost = 20000, requires = "mutation_2" },
    { id = "mutation_4", name = "进化压力", desc = "变异概率提高 50%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.15, cost = 2, goldCost = 90000, requires = "mutation_3" },
    { id = "mutation_5", name = "造物主", desc = "变异概率提高 75%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.25, cost = 3, goldCost = 300000, requires = "mutation_4" },

    { id = "bag_capacity_1", name = "布袋扩容", desc = "收获背包容量提高到 35 格", category = "bag", bonusKey = "bagCapacity", bonusValue = 15, cost = 1, goldCost = 600, requires = nil },
    { id = "bag_capacity_2", name = "藤篮收纳", desc = "收获背包容量提高到 50 格", category = "bag", bonusKey = "bagCapacity", bonusValue = 15, cost = 1, goldCost = 2500, requires = "bag_capacity_1" },
    { id = "bag_capacity_3", name = "仓储达人", desc = "收获背包容量提高到 65 格", category = "bag", bonusKey = "bagCapacity", bonusValue = 15, cost = 2, goldCost = 10000, requires = "bag_capacity_2" },
    { id = "bag_capacity_4", name = "丰收仓库", desc = "收获背包容量提高到 80 格", category = "bag", bonusKey = "bagCapacity", bonusValue = 15, cost = 2, goldCost = 40000, requires = "bag_capacity_3" },
    { id = "bag_capacity_5", name = "无限整理术", desc = "收获背包容量提高到 100 格", category = "bag", bonusKey = "bagCapacity", bonusValue = 20, cost = 3, goldCost = 120000, requires = "bag_capacity_4" },
}

-- ============================================================================
-- 等级经验配置
-- 2-15 级每次升级获得 1 天赋点，16-30 级每次升级获得 2 天赋点。
-- 初始 1 点 + 升级总计 44 点 = 45 点，可点满当前 5 条天赋链。
-- ============================================================================

TalentSystem.LEVEL_EXP_TABLE = {
    [1]  = 30,
    [2]  = 50,
    [3]  = 80,
    [4]  = 120,
    [5]  = 170,
    [6]  = 230,
    [7]  = 300,
    [8]  = 380,
    [9]  = 470,
    [10] = 570,
    [11] = 680,
    [12] = 800,
    [13] = 940,
    [14] = 1100,
    [15] = 1280,
    [16] = 1480,
    [17] = 1700,
    [18] = 1950,
    [19] = 2230,
    [20] = 2550,
    [21] = 2900,
    [22] = 3280,
    [23] = 3700,
    [24] = 4160,
    [25] = 4660,
    [26] = 5200,
    [27] = 5780,
    [28] = 6400,
    [29] = 7060,
}

TalentSystem.MAX_LEVEL = 30

TalentSystem.RARITY_BASE_EXP = {
    ["普通"] = 5,
    ["罕见"] = 10,
    ["稀有"] = 18,
    ["史诗"] = 30,
    ["传奇"] = 50,
}

local state_ = {
    unlockedTalents = {},
    talentPoints = 0,
    level = 1,
    exp = 0,
}

local callbacks_ = {}

local function IsClientRuntime()
    return IsClientMode ~= nil and IsClientMode()
end

local function CanMutateLocalState(actionName)
    if IsClientRuntime() then
        print("[天赋] 已阻止客户端本地权威写入: " .. tostring(actionName or "unknown"))
        return false
    end
    return true
end

function TalentSystem.Init(callbacks)
    callbacks_ = callbacks or {}
    state_ = {
        unlockedTalents = {},
        talentPoints = 1,
        level = 1,
        exp = 0,
    }
end

function TalentSystem.GetLevelUpTalentPoints(level)
    if level >= 16 then
        return 2
    end
    return 1
end

function TalentSystem.GetLevel()
    return state_.level
end

function TalentSystem.GetExp()
    return state_.exp
end

function TalentSystem.GetExpToNextLevel()
    return TalentSystem.LEVEL_EXP_TABLE[state_.level] or 9999
end

function TalentSystem.GetExpProgress()
    local needed = TalentSystem.GetExpToNextLevel()
    return state_.exp / needed
end

function TalentSystem.IsMaxLevel()
    return state_.level >= TalentSystem.MAX_LEVEL
end

---@param rarity string
---@param priceMultiplier number
---@return number
function TalentSystem.AddHarvestExp(rarity, priceMultiplier)
    if not CanMutateLocalState("AddHarvestExp") then return 0 end
    if TalentSystem.IsMaxLevel() then return 0 end

    local baseExp = TalentSystem.RARITY_BASE_EXP[rarity] or 5
    local mutBonus = math.min(priceMultiplier or 1.0, 5.0)
    local exp = math.floor(baseExp * mutBonus + 0.5)
    exp = math.max(1, exp)

    state_.exp = state_.exp + exp

    if callbacks_.onHarvestExp then
        callbacks_.onHarvestExp(exp)
    end

    local leveled = false
    local totalPointGain = 0
    while not TalentSystem.IsMaxLevel() do
        local needed = TalentSystem.LEVEL_EXP_TABLE[state_.level]
        if needed == nil or state_.exp < needed then break end
        state_.exp = state_.exp - needed
        state_.level = state_.level + 1
        local pointGain = TalentSystem.GetLevelUpTalentPoints(state_.level)
        state_.talentPoints = state_.talentPoints + pointGain
        totalPointGain = totalPointGain + pointGain
        leveled = true
        print(string.format("[天赋] 升级! 等级 %d，获得 %d 天赋点（可用: %d）", state_.level, pointGain, state_.talentPoints))
    end

    if TalentSystem.IsMaxLevel() then
        state_.exp = 0
    end

    if leveled and callbacks_.onLevelUp then
        callbacks_.onLevelUp(state_.level, totalPointGain)
    end

    return exp
end

function TalentSystem.GetState()
    return state_
end

function TalentSystem.GetTalentPoints()
    return state_.talentPoints
end

function TalentSystem.IsTalentUnlocked(talentId)
    return state_.unlockedTalents[talentId] == true
end

function TalentSystem.CanUnlockTalent(talentId)
    local talent = TalentSystem.FindTalent(talentId)
    if talent == nil then return false end
    if state_.unlockedTalents[talentId] then return false end
    if state_.talentPoints < talent.cost then return false end
    if talent.requires ~= nil and not state_.unlockedTalents[talent.requires] then return false end
    if talent.goldCost and talent.goldCost > 0 then
        if callbacks_.getGold and callbacks_.getGold() < talent.goldCost then
            return false
        end
    end
    return true
end

function TalentSystem.HasUnlockableTalent()
    if state_.talentPoints <= 0 then return false end
    for _, talent in ipairs(TalentSystem.TALENTS) do
        if TalentSystem.CanUnlockTalent(talent.id) then
            return true
        end
    end
    return false
end

function TalentSystem.FindTalent(talentId)
    for _, t in ipairs(TalentSystem.TALENTS) do
        if t.id == talentId then return t end
    end
    return nil
end

---@param bonusKey string
---@return number
function TalentSystem.GetBonus(bonusKey)
    local total = 0
    for _, talent in ipairs(TalentSystem.TALENTS) do
        if talent.bonusKey == bonusKey and state_.unlockedTalents[talent.id] then
            total = total + talent.bonusValue
        end
    end
    return total
end

function TalentSystem.UnlockTalent(talentId)
    if not CanMutateLocalState("UnlockTalent") then return false end
    if not TalentSystem.CanUnlockTalent(talentId) then return false end
    local talent = TalentSystem.FindTalent(talentId)
    state_.talentPoints = state_.talentPoints - talent.cost
    if talent.goldCost and talent.goldCost > 0 and callbacks_.spendGold then
        callbacks_.spendGold(talent.goldCost)
    end
    state_.unlockedTalents[talentId] = true
    print(string.format("[天赋] 点亮: %s (%s +%.2f) 消耗金币 %d", talent.name, talent.bonusKey, talent.bonusValue, talent.goldCost or 0))
    return true
end

function TalentSystem.GetSaveData()
    return {
        unlockedTalents = state_.unlockedTalents,
        talentPoints = state_.talentPoints,
        level = state_.level,
        exp = state_.exp,
    }
end

function TalentSystem.LoadSaveData(data)
    if data == nil then return end
    state_.unlockedTalents = data.unlockedTalents or {}
    state_.talentPoints = data.talentPoints or 0
    state_.level = data.level or 1
    state_.exp = data.exp or 0
end

return TalentSystem
