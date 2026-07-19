-- ============================================================================
-- 统一玩家存档 Assemble
-- ============================================================================
-- 将旧拆分档（经济 + 农场 + ledger/mirror）合成为 garden_player_state_v1。
-- 冲突裁决禁止「种子多赢」；作物永远信农场。
-- ============================================================================

local ServerEconomyState = require("server.server_economy_state")
local PlayerStateCodec = require("network.player_state_codec")

local PlayerSaveAssemble = {}

PlayerSaveAssemble.UNIFIED_SCHEMA_VERSION = 1

local function Rev(value)
    return math.max(0, math.floor(tonumber(value or 0) or 0))
end

local function FarmHasCrops(farm)
    if type(farm) ~= "table" or type(farm.plots) ~= "table" then return false end
    for _, plot in pairs(farm.plots) do
        if type(plot) == "table" and type(plot.plants) == "table" and #plot.plants > 0 then
            return true
        end
    end
    return false
end

--- 从拆分档合成统一档。
---@return table doc
---@return table meta
function PlayerSaveAssemble.AssembleFromSplit(economy, farm, ledger, options)
    options = options or {}
    economy = type(economy) == "table" and economy or {}
    farm = type(farm) == "table" and farm or { version = 1, revision = 0, plots = {} }

    local repairSuspect = false
    local appliedLedger = false
    local appliedMirror = false

    local ecoRev = Rev(economy.revision)
    local ledgerRev = type(ledger) == "table" and Rev(ledger.revision) or 0
    local mirror = type(farm.economyMirror) == "table" and farm.economyMirror or nil
    local mirrorRev = type(mirror) == "table" and Rev(mirror.revision) or 0

    if ledgerRev > ecoRev then
        local didApply
        economy, didApply = ServerEconomyState.ApplyEconomyLedger(economy, ledger)
        appliedLedger = didApply == true
        ecoRev = Rev(economy.revision)
    end
    if type(mirror) == "table" and mirrorRev > ecoRev then
        local didApply
        economy, didApply = ServerEconomyState.ApplyEconomyLedger(economy, mirror)
        appliedMirror = didApply == true
        ecoRev = Rev(economy.revision)
    end

    local pairedEco = Rev(farm.pairedEconomyRevision)
    if pairedEco > ecoRev and not appliedLedger and not appliedMirror then
        repairSuspect = true
        print(string.format(
            "[PlayerSaveAssemble] repairSuspect pairedEco=%s ecoRev=%s farmHasCrops=%s",
            tostring(pairedEco),
            tostring(ecoRev),
            tostring(FarmHasCrops(farm))
        ))
    end

    local farmRev = Rev(farm.revision)
    local unifiedRevision = math.max(ecoRev, farmRev, pairedEco, ledgerRev, mirrorRev)
    if unifiedRevision < 1 then unifiedRevision = 1 end

    local now = options.now
    if type(now) ~= "number" then
        now = os and os.time and os.time() or 0
    end

    economy.pairedFarmRevision = nil
    farm.pairedEconomyRevision = nil
    farm.economyMirror = nil

    local doc = {
        saveSchemaVersion = PlayerSaveAssemble.UNIFIED_SCHEMA_VERSION,
        revision = unifiedRevision,
        updatedAt = math.max(Rev(economy.updatedAt), Rev(farm.updatedAt), now),
        ownerUserId = economy.ownerUserId or farm.ownerUserId,
        userId = economy.userId or farm.userId,
        profile = type(options.profile) == "table" and options.profile or nil,
        economy = economy,
        farm = farm,
        migratedFrom = {
            economyRevision = ecoRev,
            farmRevision = farmRev,
            source = "v1_split",
            repairSuspect = repairSuspect == true or nil,
            appliedLedger = appliedLedger == true or nil,
            appliedMirror = appliedMirror == true or nil,
        },
    }

    return doc, {
        repairSuspect = repairSuspect,
        appliedLedger = appliedLedger,
        appliedMirror = appliedMirror,
        unifiedRevision = unifiedRevision,
    }
end

function PlayerSaveAssemble.SplitViews(doc)
    if type(doc) ~= "table" then
        return nil, nil, 0
    end
    local economy = type(doc.economy) == "table" and PlayerStateCodec.HydrateEconomy(doc.economy) or {}
    if type(doc.profile) == "table" then economy.profile = doc.profile end
    local farm = type(doc.farm) == "table" and PlayerStateCodec.HydrateFarm(doc.farm) or { version = 1, revision = 0, plots = {} }
    return economy, farm, Rev(doc.revision)
end

function PlayerSaveAssemble.BuildDoc(economy, farm, revision, ownerUid)
    if type(economy) == "table" then
        economy.pairedFarmRevision = nil
    end
    if type(farm) == "table" then
        farm.pairedEconomyRevision = nil
        farm.economyMirror = nil
    end
    local ecoRev = Rev(economy and economy.revision)
    local farmRev = Rev(farm and farm.revision)
    local unifiedRev = math.max(Rev(revision), ecoRev, farmRev)
    return {
        saveSchemaVersion = PlayerSaveAssemble.UNIFIED_SCHEMA_VERSION,
        codecVersion = PlayerStateCodec.VERSION,
        revision = unifiedRev,
        updatedAt = math.max(Rev(economy and economy.updatedAt), Rev(farm and farm.updatedAt), 0),
        ownerUserId = ownerUid or (economy and economy.ownerUserId),
        userId = ownerUid or (economy and economy.userId),
        profile = type(economy and economy.profile) == "table" and economy.profile or nil,
        economy = PlayerStateCodec.CompactEconomy(economy),
        farm = PlayerStateCodec.CompactFarm(farm),
    }
end

function PlayerSaveAssemble.NeedsCompaction(doc)
    return PlayerStateCodec.NeedsCompaction(doc)
end

function PlayerSaveAssemble.IsUnifiedDoc(value)
    return type(value) == "table"
        and type(value.economy) == "table"
        and type(value.farm) == "table"
        and Rev(value.saveSchemaVersion) >= 1
end

return PlayerSaveAssemble
