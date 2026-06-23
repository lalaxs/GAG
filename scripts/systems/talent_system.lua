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
    -- 收获掉落种子包概率（5级，累计 2%→4%→6%→8%→10%）
    { id = "drop_rate_1", name = "拾穗", desc = "收获时 2% 概率掉落种子包", category = "harvest", bonusKey = "dropRate", bonusValue = 0.02, cost = 1, goldCost = 2000, requires = nil },
    { id = "drop_rate_2", name = "丰收之手", desc = "掉包概率提升至 4%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.02, cost = 1, goldCost = 5000, requires = "drop_rate_1" },
    { id = "drop_rate_3", name = "大地恩赐", desc = "掉包概率提升至 6%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.02, cost = 2, goldCost = 20000, requires = "drop_rate_2" },
    { id = "drop_rate_4", name = "幸运之手", desc = "掉包概率提升至 8%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.02, cost = 2, goldCost = 60000, requires = "drop_rate_3" },
    { id = "drop_rate_5", name = "黄金手气", desc = "掉包概率提升至 10%", category = "harvest", bonusKey = "dropRate", bonusValue = 0.02, cost = 3, goldCost = 200000, requires = "drop_rate_4" },

    -- 缩短成熟时间（5级，累计 5%→10%→15%→20%→25%）
    { id = "grow_speed_1", name = "催熟", desc = "成熟时间缩短 5%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 1, goldCost = 2000, requires = nil },
    { id = "grow_speed_2", name = "光合加速", desc = "成熟时间缩短 10%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 1, goldCost = 5000, requires = "grow_speed_1" },
    { id = "grow_speed_3", name = "时光催化", desc = "成熟时间缩短 15%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 2, goldCost = 20000, requires = "grow_speed_2" },
    { id = "grow_speed_4", name = "春风化雨", desc = "成熟时间缩短 20%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 2, goldCost = 60000, requires = "grow_speed_3" },
    { id = "grow_speed_5", name = "瞬息绽放", desc = "成熟时间缩短 25%", category = "growth", bonusKey = "growSpeed", bonusValue = 0.05, cost = 3, goldCost = 200000, requires = "grow_speed_4" },

    -- 出售金币加成（5级，累计 5%→10%→15%→20%→25%）
    { id = "sell_bonus_1", name = "精明商人", desc = "出售价格提高 5%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 1, goldCost = 2000, requires = nil },
    { id = "sell_bonus_2", name = "定价大师", desc = "出售价格提高 10%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 1, goldCost = 5000, requires = "sell_bonus_1" },
    { id = "sell_bonus_3", name = "黄金触感", desc = "出售价格提高 15%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 2, goldCost = 20000, requires = "sell_bonus_2" },
    { id = "sell_bonus_4", name = "点石成金", desc = "出售价格提高 20%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 2, goldCost = 60000, requires = "sell_bonus_3" },
    { id = "sell_bonus_5", name = "财神降临", desc = "出售价格提高 25%", category = "economy", bonusKey = "sellBonus", bonusValue = 0.05, cost = 3, goldCost = 200000, requires = "sell_bonus_4" },

    -- 变异概率提高（5级，累计 1%→2%→3%→4%→5%）
    { id = "mutation_1", name = "基因启蒙", desc = "变异概率提高 1%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.01, cost = 1, goldCost = 2000, requires = nil },
    { id = "mutation_2", name = "双螺旋", desc = "变异概率提高 2%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.01, cost = 1, goldCost = 5000, requires = "mutation_1" },
    { id = "mutation_3", name = "基因突变", desc = "变异概率提高 3%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.01, cost = 2, goldCost = 20000, requires = "mutation_2" },
    { id = "mutation_4", name = "进化压力", desc = "变异概率提高 4%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.01, cost = 2, goldCost = 60000, requires = "mutation_3" },
    { id = "mutation_5", name = "造物主", desc = "变异概率提高 5%", category = "mutation", bonusKey = "mutationBonus", bonusValue = 0.01, cost = 3, goldCost = 200000, requires = "mutation_4" },
}

-- ============================================================================
-- 等级经验配置
-- 每次升级获得 1 天赋点，经验需求递增
-- ============================================================================

-- 每级所需经验（索引 = 当前等级，值 = 升到下一级需要的经验）
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
}

TalentSystem.MAX_LEVEL = 20

-- 收获经验公式参数
-- 基础经验 = 植物稀有度基础 × 变异倍率加成
TalentSystem.RARITY_BASE_EXP = {
    ["普通"] = 5,
    ["罕见"] = 10,
    ["稀有"] = 18,
    ["史诗"] = 30,
    ["传奇"] = 50,
}

-- ============================================================================
-- 状态
-- ============================================================================

local state_ = {
    unlockedTalents = {},   -- { [talentId] = true }
    talentPoints = 0,       -- 可用天赋点
    level = 1,              -- 当前等级
    exp = 0,                -- 当前经验值
}

local callbacks_ = {}

-- ============================================================================
-- 初始化
-- ============================================================================

function TalentSystem.Init(callbacks)
    callbacks_ = callbacks or {}
    state_ = {
        unlockedTalents = {},
        talentPoints = 1, -- 初始赠送 1 点
        level = 1,
        exp = 0,
    }
end

-- ============================================================================
-- 等级/经验查询
-- ============================================================================

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

-- ============================================================================
-- 经验获取与升级
-- ============================================================================

--- 收获作物时调用，根据作物信息计算经验
---@param rarity string 作物稀有度
---@param priceMultiplier number 变异倍率
---@return number 获得的经验值
function TalentSystem.AddHarvestExp(rarity, priceMultiplier)
    if TalentSystem.IsMaxLevel() then return 0 end

    local baseExp = TalentSystem.RARITY_BASE_EXP[rarity] or 5
    -- 变异作物给予额外经验加成（倍率越高经验越多，但有上限）
    local mutBonus = math.min(priceMultiplier or 1.0, 5.0)
    local exp = math.floor(baseExp * mutBonus + 0.5)
    exp = math.max(1, exp)

    state_.exp = state_.exp + exp

    if callbacks_.onHarvestExp then
        callbacks_.onHarvestExp(exp)
    end

    -- 检查升级
    local leveled = false
    while not TalentSystem.IsMaxLevel() do
        local needed = TalentSystem.LEVEL_EXP_TABLE[state_.level]
        if needed == nil or state_.exp < needed then break end
        state_.exp = state_.exp - needed
        state_.level = state_.level + 1
        state_.talentPoints = state_.talentPoints + 1
        leveled = true
        print(string.format("[天赋] 升级! 等级 %d，获得 1 天赋点（可用: %d）", state_.level, state_.talentPoints))
    end

    -- 满级时经验不再溢出
    if TalentSystem.IsMaxLevel() then
        state_.exp = 0
    end

    if leveled and callbacks_.onLevelUp then
        callbacks_.onLevelUp(state_.level)
    end

    return exp
end

-- ============================================================================
-- 天赋查询接口
-- ============================================================================

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
    -- 检查金币是否足够
    if talent.goldCost and talent.goldCost > 0 then
        if callbacks_.getGold and callbacks_.getGold() < talent.goldCost then
            return false
        end
    end
    return true
end

function TalentSystem.FindTalent(talentId)
    for _, t in ipairs(TalentSystem.TALENTS) do
        if t.id == talentId then return t end
    end
    return nil
end

--- 获取某个 bonusKey 的总加成值（累加所有已点亮的相关天赋）
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

-- ============================================================================
-- 天赋操作
-- ============================================================================

function TalentSystem.UnlockTalent(talentId)
    if not TalentSystem.CanUnlockTalent(talentId) then return false end
    local talent = TalentSystem.FindTalent(talentId)
    -- 扣除天赋点
    state_.talentPoints = state_.talentPoints - talent.cost
    -- 扣除金币
    if talent.goldCost and talent.goldCost > 0 and callbacks_.spendGold then
        callbacks_.spendGold(talent.goldCost)
    end
    state_.unlockedTalents[talentId] = true
    print(string.format("[天赋] 点亮: %s (%s +%.2f) 消耗金币 %d", talent.name, talent.bonusKey, talent.bonusValue, talent.goldCost or 0))
    return true
end

--- 集齐品级时调用（仍保留，奖励额外天赋点）
function TalentSystem.OnRarityCollected(rarity)
    state_.talentPoints = state_.talentPoints + 1
    print(string.format("[天赋] 集齐 %s 品级全种子，奖励 1 天赋点!", rarity))
end

-- ============================================================================
-- 存档接口
-- ============================================================================

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
