-- ============================================================================
-- 种子礼包系统 (Seed Pack System)
-- Grow A Garden
-- ============================================================================
-- 封装种子礼包开启、结果统计、可用礼包查询等流程。
-- UI 展示仍由 main.lua 负责，避免改动现有 UI 排版与交互。
-- ============================================================================

local SeedPackSystem = {}

local config_ = nil
local inventory_ = nil

function SeedPackSystem.Init(config, inventorySystem)
    config_ = config
    inventory_ = inventorySystem
end

function SeedPackSystem.CountResults(results)
    return inventory_.CountPackResults(results)
end

function SeedPackSystem.CanReceiveResults(results)
    return inventory_.CanReceivePackResults(results)
end

function SeedPackSystem.BuildResults(packCfg, packCount)
    return inventory_.BuildSeedPackResults(packCfg, packCount)
end

function SeedPackSystem.ApplyResults(results)
    inventory_.ApplyPackResults(results)
end

function SeedPackSystem.GetFirstAvailablePackId()
    return inventory_.GetFirstAvailablePackId()
end

function SeedPackSystem.OpenPack(packId, packCount)
    local cfg = config_.SEED_PACK_CONFIG[packId]
    if cfg == nil then return nil, nil, nil end

    local state = inventory_.GetState()
    local owned = state.seedPacks[packId] or 0
    packCount = math.min(packCount or 1, owned)
    local results, err = inventory_.OpenSeedPack(packId, packCount)
    if results == nil then
        return nil, err, nil
    end

    local title = packCount > 1 and (cfg.packName .. " x" .. packCount) or cfg.packName
    return results, nil, title
end

return SeedPackSystem
