-- ============================================================================
-- 限时活动系统 (Activity System)
-- Grow A Garden
-- ============================================================================
-- 管理 3 日循环活动、活动货币、限定兑换、活动抽包、收获事件奖励。
-- ============================================================================

local ActivitySystem = {}

local cfg_ = nil
local inventory_ = nil
local callbacks_ = {}

local SECONDS_PER_DAY = 86400

local state_ = {
    sweet = {
        value = 0,
        submitted = 0,
        exchanged = {},
    },
    alien = {
        genes = 0,
        totalGenes = 0,
        drawCount = 0,
    },
    dark = {
        devourHarvestCount = 0,
        darkSeedDrops = 0,
    },
}

local function RollWeighted(pool)
    if pool == nil or #pool == 0 then return nil end
    local total = 0
    for _, item in ipairs(pool) do
        total = total + (item.weight or 0)
    end
    if total <= 0 then return pool[1] end
    local r = math.random() * total
    local acc = 0
    for _, item in ipairs(pool) do
        acc = acc + (item.weight or 0)
        if r <= acc then
            return item
        end
    end
    return pool[#pool]
end

local function FindSpecialConfig(key)
    for _, special in ipairs(cfg_.SPECIAL_MUTATIONS or {}) do
        if special.key == key then
            return special
        end
    end
    return nil
end

local function HasSpecial(mutation, key)
    if mutation == nil or mutation.specials == nil then return false end
    for _, special in ipairs(mutation.specials) do
        if special.key == key then return true end
    end
    return false
end

local function AddSpecial(mutation, key)
    if mutation == nil or HasSpecial(mutation, key) then return false end
    local special = FindSpecialConfig(key)
    if special == nil then return false end
    table.insert(mutation.specials, special)
    mutation.priceMultiplier = mutation.priceMultiplier * (special.multiplier or 1.0)
    mutation.timeMultiplier = mutation.timeMultiplier * (special.timeMultiplier or 1.0)
    return true
end

local function GetRarityOrder(rarity)
    return (cfg_.RARITY_ORDER or {})[rarity or "普通"] or 1
end

local function GetActivityConfig(activityId)
    return ((cfg_.ACTIVITY_CONFIG or {}).activities or {})[activityId]
end

local function GetActivityState(activityId)
    return state_[activityId]
end

function ActivitySystem.Init(config, inventorySystem, callbacks)
    cfg_ = config
    inventory_ = inventorySystem
    callbacks_ = callbacks or {}
end

function ActivitySystem.GetState()
    return state_
end

function ActivitySystem.GetActiveActivityId()
    local activityConfig = cfg_.ACTIVITY_CONFIG or {}
    local sequence = activityConfig.sequence or { "sweet", "alien", "dark" }
    local cycleDays = activityConfig.cycleDays or 3
    local now = os and os.time and os.time() or 0
    local slot = math.floor(now / (cycleDays * SECONDS_PER_DAY)) % #sequence + 1
    return sequence[slot]
end

function ActivitySystem.GetActiveActivity()
    local id = ActivitySystem.GetActiveActivityId()
    return id, GetActivityConfig(id), GetActivityState(id)
end

function ActivitySystem.GetTimeLeftText()
    local activityConfig = cfg_.ACTIVITY_CONFIG or {}
    local cycleDays = activityConfig.cycleDays or 3
    local duration = cycleDays * SECONDS_PER_DAY
    local now = os and os.time and os.time() or 0
    local left = duration - (now % duration)
    local days = math.floor(left / SECONDS_PER_DAY)
    local hours = math.floor((left % SECONDS_PER_DAY) / 3600)
    if days > 0 then
        return string.format("剩余 %d天%d小时", days, hours)
    end
    return string.format("剩余 %d小时", math.max(1, hours))
end

function ActivitySystem.ApplyPlantingMutation(plant, mutation)
    local id, activity = ActivitySystem.GetActiveActivity()
    if activity == nil or mutation == nil then return nil end

    local added = nil
    if id == "sweet" then
        if math.random() <= (activity.candyChance or 0.08) then
            added = AddSpecial(mutation, "candy") and "candy" or added
        end
        if math.random() <= (activity.honeyChance or 0.055) then
            added = AddSpecial(mutation, "honey") and "honey" or added
        end
    elseif id == "dark" then
        if math.random() <= (activity.devourChance or 0.05) then
            added = AddSpecial(mutation, "devour") and "devour" or added
        end
        if math.random() <= (activity.extraVoidChance or 0.035) then
            added = AddSpecial(mutation, "void") and "void" or added
        end
    end

    mutation.priceMultiplier = math.min(mutation.priceMultiplier, 80.0)
    mutation.timeMultiplier = math.min(mutation.timeMultiplier, 2.7)
    return added
end

function ActivitySystem.OnCropHarvested(crop)
    local id, activity = ActivitySystem.GetActiveActivity()
    if crop == nil or activity == nil then return nil end

    if id == "alien" then
        local rarityOrder = GetRarityOrder(crop.config and crop.config.rarity)
        local chance = ({ 0.30, 0.40, 0.55, 0.70, 1.0 })[rarityOrder] or 0.30
        if math.random() <= chance then
            local minValue = math.max(1, rarityOrder)
            local maxValue = math.max(minValue, rarityOrder + 2)
            local amount = math.random(minValue, maxValue)
            if crop.mutation ~= nil and crop.mutation.specials ~= nil and #crop.mutation.specials > 0 then
                amount = amount + 1
            end
            state_.alien.genes = state_.alien.genes + amount
            state_.alien.totalGenes = state_.alien.totalGenes + amount
            if callbacks_.showToast then callbacks_.showToast("获得外星基因 x" .. amount) end
            return { type = "alien_gene", amount = amount }
        end
    elseif id == "dark" and HasSpecial(crop.mutation, "devour") then
        state_.dark.devourHarvestCount = state_.dark.devourHarvestCount + 1
        local rarityOrder = GetRarityOrder(crop.config and crop.config.rarity)
        local rates = activity.darkSeedDropRates or { 0.08, 0.12, 0.18, 0.28, 0.45 }
        if math.random() <= (rates[rarityOrder] or 0.08) then
            local pool = activity.darkSeedPool or { 36, 37, 38 }
            local plantIndex = pool[math.random(1, #pool)]
            inventory_.AddSeedToBag(plantIndex, 1, 0)
            state_.dark.darkSeedDrops = state_.dark.darkSeedDrops + 1
            local plant = cfg_.PLANTS[plantIndex]
            if callbacks_.showToast then callbacks_.showToast("黑暗来临掉落: " .. (plant and plant.name or "限定种子")) end
            return { type = "dark_seed", plantIndex = plantIndex }
        end
    end
    return nil
end

function ActivitySystem.GetSweetSubmitValue(item)
    if item == nil then return 0 end
    local mutation = item.mutation
    if not HasSpecial(mutation, "candy") and not HasSpecial(mutation, "honey") then return 0 end
    local rarityOrder = GetRarityOrder(item.rarity)
    local base = 8 + rarityOrder * 6 + math.floor((item.price or 0) / 900)
    if HasSpecial(mutation, "honey") then base = math.floor(base * 1.3 + 0.5) end
    if item.weightTier == "Giant" then base = math.floor(base * 1.2 + 0.5) end
    return math.max(5, base)
end

function ActivitySystem.GetSweetSubmitItems()
    local items = {}
    for _, item in ipairs(inventory_.GetHarvested()) do
        local value = ActivitySystem.GetSweetSubmitValue(item)
        if value > 0 then
            table.insert(items, { item = item, value = value })
        end
    end
    return items
end

function ActivitySystem.SubmitSweetCrop(item)
    local id = ActivitySystem.GetActiveActivityId()
    if id ~= "sweet" then return false, "当前不是甜蜜蜜活动" end
    local value = ActivitySystem.GetSweetSubmitValue(item)
    if value <= 0 then return false, "请选择糖果或蜂蜜变异作物" end
    if not inventory_.ConsumeHarvestedItem(item) then return false, "作物不在背包中" end
    state_.sweet.value = state_.sweet.value + value
    state_.sweet.submitted = state_.sweet.submitted + value
    if callbacks_.showToast then callbacks_.showToast("上交成功，甜蜜值 +" .. value) end
    return true, value
end

function ActivitySystem.ExchangeSweetReward(rewardId)
    local id, activity = ActivitySystem.GetActiveActivity()
    if id ~= "sweet" or activity == nil then return false, "当前不是甜蜜蜜活动" end
    local reward = nil
    for _, item in ipairs(activity.exchangeRewards or {}) do
        if item.id == rewardId then reward = item break end
    end
    if reward == nil then return false, "奖励不存在" end
    local claimed = state_.sweet.exchanged[rewardId] or 0
    if reward.limit ~= nil and claimed >= reward.limit then return false, "已兑换完" end
    if state_.sweet.value < reward.cost then return false, "甜蜜值不足" end

    state_.sweet.value = state_.sweet.value - reward.cost
    state_.sweet.exchanged[rewardId] = claimed + 1
    if reward.type == "seed" then
        inventory_.AddSeedToBag(reward.plantIndex, reward.count or 1, 0)
    elseif reward.type == "pack" then
        inventory_.AddSeedPack(reward.packId, reward.count or 1)
    end
    if callbacks_.showToast then callbacks_.showToast("兑换成功: " .. reward.name) end
    return true
end

function ActivitySystem.DrawAlienPack(count)
    local id, activity = ActivitySystem.GetActiveActivity()
    if id ~= "alien" or activity == nil then return false, "当前不是外星基因活动" end
    count = count or 1
    local cost = count >= 10 and (activity.drawCostTen or 95) or (activity.drawCost or 10)
    local drawCount = count >= 10 and 10 or 1
    if state_.alien.genes < cost then return false, "外星基因不足" end
    state_.alien.genes = state_.alien.genes - cost
    state_.alien.drawCount = state_.alien.drawCount + drawCount

    local rewards = {}
    for _ = 1, drawCount do
        local picked = RollWeighted(activity.drawPool)
        if picked ~= nil then
            if picked.type == "pack" then
                inventory_.AddSeedPack(picked.packId, picked.count or 1)
                table.insert(rewards, picked.name or (cfg_.SEED_PACK_CONFIG[picked.packId] and cfg_.SEED_PACK_CONFIG[picked.packId].packName) or "种子包")
            elseif picked.type == "seed" then
                inventory_.AddSeedToBag(picked.plantIndex, picked.count or 1, 0)
                local plant = cfg_.PLANTS[picked.plantIndex]
                table.insert(rewards, picked.name or (plant and plant.name) or "限定种子")
            end
        end
    end
    if callbacks_.showToast then callbacks_.showToast("基因抽取完成: " .. table.concat(rewards, "、")) end
    return true, rewards
end

function ActivitySystem.GetLeaderboard(activityId)
    activityId = activityId or ActivitySystem.GetActiveActivityId()
    local score = 0
    if activityId == "sweet" then
        score = state_.sweet.submitted
    elseif activityId == "alien" then
        score = state_.alien.totalGenes
    elseif activityId == "dark" then
        score = state_.dark.darkSeedDrops * 120 + state_.dark.devourHarvestCount * 18
    end

    local activity = GetActivityConfig(activityId) or {}
    local base = activity.leaderboardBase or 120
    local rows = {
        { name = "你", score = score, self = true },
        { name = "糖霜园丁", score = base + 73 },
        { name = "星环农夫", score = base + 41 },
        { name = "夜幕采集者", score = base + 19 },
        { name = "青藤学徒", score = math.max(0, base - 25) },
    }
    table.sort(rows, function(a, b) return a.score > b.score end)
    return rows
end

return ActivitySystem
