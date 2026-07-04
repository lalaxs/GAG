-- ============================================================================
-- 社交花园快照构建
-- ============================================================================

local SocialSnapshot = {}

local UserId = require("utils.user_id")

function SocialSnapshot.create(deps, state, helpers)
    helpers = helpers or {}

    local function GetNow()
        return helpers.getNow and helpers.getNow() or 0
    end

    local function GetDisplayName()
        if deps.getDisplayName then return deps.getDisplayName() end
        return "Tap玩家"
    end

    local function GetUserId()
        if deps.getUserId then return UserId.Normalize(deps.getUserId()) end
        if clientCloud ~= nil and clientCloud.userId ~= nil then return UserId.Normalize(clientCloud.userId) end
        return nil
    end

    local function GetAvatarProfile()
        if deps.getAvatarProfile then return deps.getAvatarProfile() end
        return nil
    end

    local function ClampPlotIndex(index)
        if helpers.clampPlotIndex then return helpers.clampPlotIndex(index) end
        return tonumber(index or 1) or 1
    end

    local function BuildCropId(plotIndex, cropIndex, crop)
        local x = crop and crop.localPos and crop.localPos.x or 0
        local z = crop and crop.localPos and crop.localPos.z or 0
        return string.format(
            "p%d_c%d_%d_%d_%d",
            plotIndex,
            cropIndex,
            tonumber(crop and crop.plantIndex or 0) or 0,
            math.floor(x * 1000),
            math.floor(z * 1000)
        )
    end

    local function CloneCropForSnapshot(crop, plotIndex, cropIndex)
        if crop == nil then return nil end
        local cropId = BuildCropId(plotIndex or 1, cropIndex or 1, crop)
        return {
            cropId = cropId,
            plantIndex = crop.plantIndex,
            name = crop.name,
            price = crop.price,
            sightValue = crop.sightValue,
            weight = crop.weight,
            baseWeight = crop.baseWeight,
            weightScale = crop.weightScale,
            weightTier = crop.weightTier,
            weightBonus = crop.weightBonus,
            weightMultiplier = crop.weightMultiplier,
            elapsed = crop.elapsed,
            growTime = crop.growTime,
            mature = crop.mature,
            sprouted = crop.sprouted,
            localPos = crop.localPos and { x = crop.localPos.x, z = crop.localPos.z } or { x = 0, z = 0 },
            seedRadius = crop.seedRadius,
            seedHeight = crop.seedHeight,
            pickRadius = crop.pickRadius,
            mutation = crop.mutation,
            rarity = crop.config and crop.config.rarity or crop.rarity,
        }
    end

    local function BuildPlotSnapshot(plotIndex, plot)
        local plants = {}
        if plot ~= nil and plot.plants ~= nil then
            for cropIndex, crop in ipairs(plot.plants) do
                local data = CloneCropForSnapshot(crop, plotIndex, cropIndex)
                if data ~= nil then table.insert(plants, data) end
            end
        end
        return {
            plotIndex = plotIndex,
            plants = plants,
        }
    end

    local function BuildSnapshot()
        local plots = deps.getPlots and deps.getPlots() or {}
        local plotIndex = ClampPlotIndex(state.visitablePlotIndex)
        local plot = plots[plotIndex]
        return {
            version = 1,
            userId = GetUserId(),
            nickname = GetDisplayName(),
            avatar = GetAvatarProfile(),
            visitablePlotIndex = plotIndex,
            unlockedPlotCount = deps.getUnlockedPlotCount and deps.getUnlockedPlotCount() or 1,
            tourValue = deps.getTourValue and deps.getTourValue() or 0,
            bestTourValue = deps.getBestTourValue and deps.getBestTourValue() or 0,
            likeCount = 0,
            updatedAt = GetNow(),
            plot = BuildPlotSnapshot(plotIndex, plot),
        }
    end

    return {
        BuildSnapshot = BuildSnapshot,
    }
end

return SocialSnapshot
