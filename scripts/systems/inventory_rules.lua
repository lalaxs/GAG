-- ============================================================================
-- 背包系统规则配置
-- Grow A Garden
-- ============================================================================
-- 只保存纯规则数据和通用权重抽取函数，避免 inventory_system.lua 继续堆积常量。
-- ============================================================================

local InventoryRules = {}

-- 种子包合成配置：3 个同级别包合成 1 个更高级别包
InventoryRules.SYNTHESIS_MAP = {
    pack_common   = "pack_uncommon",
    pack_uncommon = "pack_rare",
    pack_rare     = "pack_epic",
    pack_epic     = "pack_legendary",
}

-- 保底配置：每个品级连续开多少次没出跨级种子则必出
InventoryRules.PITY_THRESHOLDS = {
    pack_common   = 10,  -- 10 次没出罕见 → 保底
    pack_uncommon = 12,  -- 12 次没出稀有 → 保底
    pack_rare     = 15,  -- 15 次没出史诗 → 保底
    pack_epic     = 20,  -- 20 次没出传奇 → 保底
}

-- 每日任务奖励随机种子包品级的权重（最高稀有品质）
InventoryRules.DAILY_REWARD_PACK_WEIGHTS = {
    { packId = "pack_common",   weight = 60 },
    { packId = "pack_uncommon", weight = 30 },
    { packId = "pack_rare",     weight = 10 },
}

-- 收获掉落种子包的基础概率（按来源作物品级）
InventoryRules.HARVEST_DROP_RATES_BY_RARITY = {
    ["普通"] = 0.010,
    ["罕见"] = 0.020,
    ["稀有"] = 0.035,
    ["史诗"] = 0.050,
    ["传奇"] = 0.080,
}

-- 收获掉落种子包的品级权重（按来源作物品级）
InventoryRules.HARVEST_DROP_PACK_WEIGHTS_BY_RARITY = {
    ["普通"] = {
        { packId = "pack_common", weight = 90 },
        { packId = "pack_uncommon", weight = 10 },
    },
    ["罕见"] = {
        { packId = "pack_common", weight = 65 },
        { packId = "pack_uncommon", weight = 30 },
        { packId = "pack_rare", weight = 5 },
    },
    ["稀有"] = {
        { packId = "pack_common", weight = 30 },
        { packId = "pack_uncommon", weight = 50 },
        { packId = "pack_rare", weight = 18 },
        { packId = "pack_epic", weight = 2 },
    },
    ["史诗"] = {
        { packId = "pack_common", weight = 10 },
        { packId = "pack_uncommon", weight = 35 },
        { packId = "pack_rare", weight = 40 },
        { packId = "pack_epic", weight = 14 },
        { packId = "pack_legendary", weight = 1 },
    },
    ["传奇"] = {
        { packId = "pack_uncommon", weight = 15 },
        { packId = "pack_rare", weight = 35 },
        { packId = "pack_epic", weight = 40 },
        { packId = "pack_legendary", weight = 10 },
    },
}

-- 收获掉落种子包的品级权重（兜底）
InventoryRules.HARVEST_DROP_PACK_WEIGHTS = {
    { packId = "pack_common",   weight = 70 },
    { packId = "pack_uncommon", weight = 20 },
    { packId = "pack_rare",     weight = 8 },
    { packId = "pack_epic",     weight = 2 },
}

function InventoryRules.RollWeighted(pool)
    local totalWeight = 0
    for _, item in ipairs(pool) do
        totalWeight = totalWeight + item.weight
    end
    local roll = math.random() * totalWeight
    local cursor = 0
    for _, item in ipairs(pool) do
        cursor = cursor + item.weight
        if roll <= cursor then
            return item
        end
    end
    return pool[#pool]
end

return InventoryRules
