-- ============================================================================
-- 种植玩法动作控制器
-- Grow A Garden
-- ============================================================================
-- 统一管理播种、收获、购买、出售和种子选择动作。
-- 只迁移 main.lua 中原有动作编排，不改变判断顺序、提示文案和数值。
-- ============================================================================

local FloatingToast = require("ui.floating_toast")
local AudioSystem = require("systems.audio_system")
local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local NetworkClient = require("client.network_client")

local PlantActionController = {}

local deps_ = {}
local requestSeq_ = 0

local function EmitInventoryAndWalletChanged(reason)
    EventBus.Emit(UIEvents.INVENTORY_CHANGED, { reason = reason })
    EventBus.Emit(UIEvents.WALLET_CHANGED, { reason = reason })
end

local function NextRequestId(prefix)
    requestSeq_ = requestSeq_ + 1
    return tostring(prefix or "req") .. "_" .. tostring(os.time()) .. "_" .. tostring(requestSeq_)
end

local function EncodeLocalPos(localPos)
    return { x = localPos and localPos.x or 0, z = localPos and localPos.z or 0 }
end

local function DecodeLocalPos(data)
    data = data or {}
    return Vector3(tonumber(data.x or 0) or 0, 0, tonumber(data.z or 0) or 0)
end

local function EncodeCropForServer(crop)
    if crop == nil then return nil end
    return {
        name = crop.name,
        price = crop.price,
        sightValue = crop.sightValue,
        rarity = crop.config and crop.config.rarity or crop.rarity,
        plantIndex = crop.plantIndex,
        weight = crop.weight,
        baseWeight = crop.baseWeight,
        weightTier = crop.weightTier,
        weightMultiplier = crop.weightMultiplier,
        mutation = crop.mutation,
        localPos = crop.localPos and { x = crop.localPos.x, z = crop.localPos.z } or { x = 0, z = 0 },
    }
end

local function FormatGrowCountdown(seconds)
    seconds = math.max(0, math.ceil(tonumber(seconds or 0) or 0))
    if seconds <= 0 then return "可收获" end
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format("%d:%02d:%02d", h, m, s)
    elseif seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d:%02d", m, s)
    end
    return tostring(seconds) .. "秒"
end

local function GetCropRemainingSeconds(crop)
    if crop == nil or crop.mature then return 0 end
    local growTime = tonumber(crop.growTime or 0) or 0
    local elapsed = tonumber(crop.elapsed or 0) or 0
    return math.max(0, math.ceil(growTime - elapsed))
end

function PlantActionController.Init(deps)
    deps_ = deps or {}
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then
        deps_.showToast(text, silent)
    end
end

local function RefreshUI(force)
    if deps_.refreshUI ~= nil then
        deps_.refreshUI(force)
    end
end

local function RebuildUI()
    if deps_.rebuildUI ~= nil then
        deps_.rebuildUI()
    end
end

local function RefreshTourValue()
    if deps_.refreshTourValue ~= nil then
        deps_.refreshTourValue()
    end
end

local function GetPlants()
    return deps_.plants
end

local function GetSeedBag()
    return deps_.seedBag
end

local function GetSelectedSeed()
    return deps_.getSelectedSeed()
end

local function SetSelectedSeed(index)
    deps_.setSelectedSeed(index)
end

local function GetSelectedPlot()
    return deps_.getSelectedPlot()
end

local function SetSelectedPlot(index)
    deps_.setSelectedPlot(index)
end

local function GetPlots()
    return deps_.getPlots()
end

local function IsAuthoritativeClient()
    return NetworkClient.IsRawConnected()
end

local function RequireServerUnavailable(reason)
    ShowToast(reason or "正在连接服务器，请稍后")
    return false, "server_unavailable"
end

local function ShowPlotFullMessage()
    local text = "这块田地已满"
    ShowToast(text)
    FloatingToast.Show(text, { fontSize = 20, duration = 1.5, yRatio = 0.38, priority = 8 })
end

function PlantActionController.PlantSeedAt(plotIndex, plantIndex, centerLocalPos, options)
    options = options or {}
    local plot = GetPlots()[plotIndex]
    if plot ~= nil and plot.plants ~= nil and #plot.plants >= deps_.config.MaxCropsPerPlot then
        ShowPlotFullMessage()
        return false, "plot_full"
    end
    if options.serverConfirmed ~= true and deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.PlantSeed ~= nil then
        if deps_.EconomyCloudSystem.IsPlantPending ~= nil and deps_.EconomyCloudSystem.IsPlantPending() then
            return false, "plant_pending"
        end
        local requestId = NextRequestId("plant")
        print(string.format("[播种请求] 准备发送 requestId=%s plot=%s plant=%s local=(%.3f,%.3f)",
            tostring(requestId),
            tostring(plotIndex),
            tostring(plantIndex),
            centerLocalPos and centerLocalPos.x or 0,
            centerLocalPos and centerLocalPos.z or 0))
        local requested = deps_.EconomyCloudSystem.PlantSeed({
            requestId = requestId,
            plotIndex = plotIndex,
            plantIndex = plantIndex,
            localPos = EncodeLocalPos(centerLocalPos or Vector3(0, 0, 0)),
        })
        if requested then
            print(string.format("[播种请求] 已发送 requestId=%s", tostring(requestId)))
            return true, "pending_server"
        end
        print(string.format("[播种请求] 发送被阻止 requestId=%s", tostring(requestId)))
        return RequireServerUnavailable("同步中")
    end
    if options.serverConfirmed ~= true then
        return RequireServerUnavailable("同步中")
    end
    local success, reason = deps_.CropSystem.PlantSeedAt(GetPlots(), plotIndex, plantIndex, centerLocalPos, {
        skipSeedConsume = options.serverConfirmed == true,
        seedBuff = options.seedBuff or 0,
    })
    if success then
        RefreshTourValue()
        if options.serverConfirmed ~= true then
            if deps_.markDirty then deps_.markDirty() end
            EmitInventoryAndWalletChanged("plant_seed")
            EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "plant_seed" })
        end
    end
    return success, reason
end

function PlantActionController.HarvestNearestMature(plotIndex, localPos, options)
    options = options or {}
    if options.serverConfirmed ~= true and deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.HarvestCrop ~= nil then
        local plot = GetPlots()[plotIndex]
        local crop, cropIndex = nil, nil
        if plot ~= nil and localPos ~= nil then
            crop, cropIndex = deps_.findPlantAtLocalPosition(plot, localPos, true)
        end
        if crop == nil and plot ~= nil and localPos == nil then
            for i, item in ipairs(plot.plants or {}) do
                if item.mature then crop = item; cropIndex = i; break end
            end
        end
        if crop == nil then
            print(string.format("[收获请求] 未找到可收获作物 plot=%s localPos=%s", tostring(plotIndex), localPos ~= nil and string.format("%.2f,%.2f", localPos.x, localPos.z) or "nil"))
            return false
        end
        local requestId = NextRequestId("harvest")
        print(string.format("[收获请求] 准备发送 requestId=%s plot=%d cropIndex=%s cropId=%s mature=%s elapsed=%.2f growTime=%.2f local=(%.2f,%.2f)",
            requestId,
            plotIndex,
            tostring(cropIndex),
            tostring(crop.cropId or crop.serverCropId),
            tostring(crop.mature),
            tonumber(crop.elapsed or 0) or 0,
            tonumber(crop.growTime or 0) or 0,
            crop.localPos and crop.localPos.x or 0,
            crop.localPos and crop.localPos.z or 0))
        local requested = deps_.EconomyCloudSystem.HarvestCrop({
            requestId = requestId,
            plotIndex = plotIndex,
            cropIndex = cropIndex,
            cropId = crop.cropId or crop.serverCropId,
            localPos = EncodeLocalPos(crop.localPos or localPos),
            crop = EncodeCropForServer(crop),
        })
        if requested then return true, { name = crop.name, exp = 0, pendingServer = true } end
        return RequireServerUnavailable("同步中")
    end
    if options.serverConfirmed ~= true then
        return RequireServerUnavailable("同步中")
    end
    local success, harvestInfo = deps_.CropSystem.HarvestNearestMature(GetPlots(), plotIndex, localPos, {
        skipAddHarvested = options.serverConfirmed == true,
    })
    if success then
        RefreshTourValue()
        if options.serverConfirmed ~= true then
            if deps_.markDirty then deps_.markDirty() end
            EmitInventoryAndWalletChanged("harvest_crop")
            EventBus.Emit(UIEvents.FARM_CHANGED, { reason = "harvest_crop" })
        end
    end
    return success, harvestInfo
end

function PlantActionController.PlantSeed(plotIndex, plantIndex)
    return PlantActionController.PlantSeedAt(plotIndex, plantIndex, Vector3(0, 0, 0))
end

function PlantActionController.BuySelectedSeed()
    local selectedSeed = GetSelectedSeed()
    local plant = GetPlants()[selectedSeed]
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.BuySeed ~= nil then
        if deps_.EconomyCloudSystem.BuySeed(selectedSeed, plant.seedPrice) then
            print("请求服务器购买种子: " .. plant.name)
            return true
        end
    end
    ShowToast("同步中")
    return false
end

function PlantActionController.SellAllHarvested()
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.SellAllHarvested ~= nil then
        if deps_.EconomyCloudSystem.SellAllHarvested() then
            deps_.setSelectedBagItem(nil)
            if deps_.clearBagPreview ~= nil then deps_.clearBagPreview() end
            return true
        end
    end
    ShowToast("同步中")
    return 0
end

function PlantActionController.SellBagItem(item)
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.SellBagItem ~= nil then
        if deps_.EconomyCloudSystem.SellBagItem(item) then
            deps_.setSelectedBagItem(nil)
            if deps_.clearBagPreview ~= nil then deps_.clearBagPreview() end
            return true
        end
    end
    ShowToast("同步中")
    return 0
end

function PlantActionController.SellHarvestedByFilter(filter)
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.SellHarvestedByFilter ~= nil then
        if deps_.EconomyCloudSystem.SellHarvestedByFilter(filter) then
            deps_.setSelectedBagItem(nil)
            if deps_.clearBagPreview ~= nil then deps_.clearBagPreview() end
            return true, 0
        end
    end
    ShowToast("同步中")
    return 0, 0
end

function PlantActionController.FindNextOwnedSeedIndex(startIndex)
    local plants = GetPlants()
    local seedBag = GetSeedBag()
    if #plants <= 0 then return nil end
    local start = Clamp(startIndex or GetSelectedSeed(), 1, #plants)
    for offset = 1, #plants do
        local index = ((start - 1 + offset) % #plants) + 1
        if (seedBag[index] or 0) > 0 then
            return index
        end
    end
    return nil
end

function PlantActionController.EnsureSelectedSeedAvailable()
    local selectedSeed = GetSelectedSeed()
    local seedBag = GetSeedBag()
    local plants = GetPlants()
    if (seedBag[selectedSeed] or 0) > 0 then
        return true
    end
    local nextSeed = PlantActionController.FindNextOwnedSeedIndex(selectedSeed)
    if nextSeed ~= nil then
        SetSelectedSeed(nextSeed)
        print("自动切换到可用种子: " .. plants[nextSeed].name)
        return true
    end
    return false
end

function PlantActionController.SelectNextOwnedSeedIfEmpty(fromIndex)
    local selectedSeed = GetSelectedSeed()
    local seedBag = GetSeedBag()
    local plants = GetPlants()
    if (seedBag[selectedSeed] or 0) > 0 then
        return nil
    end
    local nextSeed = PlantActionController.FindNextOwnedSeedIndex(fromIndex or selectedSeed)
    if nextSeed ~= nil then
        SetSelectedSeed(nextSeed)
        print("种子用完，自动切换到: " .. plants[nextSeed].name)
        return nextSeed
    end
    return nil
end

function PlantActionController.SetSelectedSeedIndex(index)
    SetSelectedSeed(Clamp(index, 1, #GetPlants()))
    PlantActionController.EnsureSelectedSeedAvailable()
end

function PlantActionController.ApplyConfirmedPlantSeed(data)
    local patch = type(data.farmPatch) == "table" and data.farmPatch or nil
    local plotIndex = tonumber((patch and patch.plotIndex) or data.plotIndex or GetSelectedPlot()) or GetSelectedPlot()
    local plantIndex = tonumber(data.plantIndex or GetSelectedSeed()) or GetSelectedSeed()
    local cropData = (patch and patch.crop) or data.crop
    if cropData == nil or deps_.CropSystem.PlantCropFromServer == nil then
        ShowToast("服务器播种数据不完整，请重试")
        print("[播种] 服务端响应缺少 crop 字段，拒绝本地 Roll")
        return false
    end
    cropData.requestId = data.requestId
    local success = deps_.CropSystem.PlantCropFromServer(GetPlots(), plotIndex, cropData)
    if success then
        RefreshTourValue()
        AudioSystem.PlaySFX("plant_seed")
        ShowToast("已播种 " .. GetPlants()[plantIndex].name, true)
        PlantActionController.SelectNextOwnedSeedIfEmpty(plantIndex)
        if deps_.markDirty then deps_.markDirty() end
        RebuildUI()
        return true
    end
    ShowToast("播种失败")
    return false
end

function PlantActionController.ApplyConfirmedHarvestCrop(data)
    local patch = type(data.farmPatch) == "table" and data.farmPatch or nil
    local plotIndex = tonumber((patch and patch.plotIndex) or data.plotIndex or GetSelectedPlot()) or GetSelectedPlot()
    local cropIndex = tonumber((patch and patch.cropIndex) or data.cropIndex or 0) or 0
    local plot = GetPlots()[plotIndex]
    local crop = nil
    local removeIndex = nil
    local cropId = (patch and patch.cropId) or data.cropId or (data.crop and (data.crop.cropId or data.crop.serverCropId))

    if patch ~= nil and patch.type == "removeCrop" and deps_.CropSystem.RemoveCropFromServer ~= nil then
        local removed = deps_.CropSystem.RemoveCropFromServer(GetPlots(), plotIndex, cropId, cropIndex)
        if removed then
            RefreshTourValue()
            AudioSystem.PlaySFX("harvest_crop")
            local exp = tonumber(data.exp or 0) or 0
            local cropName = data.crop and data.crop.name or "作物"
            local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
            ShowToast(text, true)
            FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
            if data.droppedPackName ~= nil then
                local dropText = "掉落: " .. tostring(data.droppedPackName)
                ShowToast(dropText, true)
                FloatingToast.Show(dropText, { fontSize = 18, duration = 1.5, yRatio = 0.36, priority = 1 })
            end
            if data.activityReward ~= nil then
                local rewardText = data.activityReward.toastText or data.activityReward.message
                if rewardText == nil and data.activityReward.type == "alien_gene" then
                    rewardText = "获得外星基因 x" .. tostring(data.activityReward.amount or 0)
                elseif rewardText == nil and data.activityReward.type == "dark_seed" then
                    local plant = deps_.plants and deps_.plants[data.activityReward.plantIndex]
                    rewardText = "黑暗来临掉落: " .. (plant and (plant.name .. "种子") or "限定种子")
                end
                if rewardText ~= nil then
                    ShowToast(rewardText, true)
                    FloatingToast.Show(rewardText, { fontSize = 18, duration = 1.5, yRatio = 0.32, priority = 2 })
                end
            end
            if deps_.markDirty then deps_.markDirty() end
            RebuildUI()
            return true
        end
    end

    if data.farmSynced ~= true and plot ~= nil then
        if cropId ~= nil and cropId ~= "" then
            for index, item in ipairs(plot.plants or {}) do
                if item.cropId == cropId or item.serverCropId == cropId then
                    crop = item
                    removeIndex = index
                    break
                end
            end
        end
        if crop == nil and cropIndex > 0 then
            crop = plot.plants[cropIndex]
            removeIndex = cropIndex
        end
        if crop == nil and data.crop and data.crop.localPos then
            local localPos = DecodeLocalPos(data.crop.localPos)
            crop, removeIndex = deps_.findPlantAtLocalPosition(plot, localPos, false)
        end
    end

    local exp = tonumber(data.exp or 0) or 0
    local cropName = data.crop and data.crop.name or (crop and crop.name) or "作物"

    if crop ~= nil and removeIndex ~= nil then
        if crop.root ~= nil then crop.root:Remove() end
        table.remove(plot.plants, removeIndex)
        RefreshTourValue()
        AudioSystem.PlaySFX("harvest_crop")
        local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
        ShowToast(text, true)
        FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
        if data.droppedPackName ~= nil then
            local dropText = "掉落: " .. tostring(data.droppedPackName)
            ShowToast(dropText, true)
            FloatingToast.Show(dropText, { fontSize = 18, duration = 1.5, yRatio = 0.36, priority = 1 })
        end
        if data.activityReward ~= nil then
            local rewardText = data.activityReward.toastText or data.activityReward.message
            if rewardText == nil and data.activityReward.type == "alien_gene" then
                rewardText = "获得外星基因 x" .. tostring(data.activityReward.amount or 0)
            elseif rewardText == nil and data.activityReward.type == "dark_seed" then
                local plant = deps_.plants and deps_.plants[data.activityReward.plantIndex]
                rewardText = "黑暗来临掉落: " .. (plant and (plant.name .. "种子") or "限定种子")
            end
            if rewardText ~= nil then
                ShowToast(rewardText, true)
                FloatingToast.Show(rewardText, { fontSize = 18, duration = 1.5, yRatio = 0.32, priority = 2 })
            end
        end
        if deps_.markDirty then deps_.markDirty() end
        RebuildUI()
        return true
    end
    if data.farm ~= nil and deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.ForceSyncAuthFarm ~= nil then
        deps_.EconomyCloudSystem.ForceSyncAuthFarm(data.farm, "harvest_resync")
        AudioSystem.PlaySFX("harvest_crop")
        local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
        ShowToast(text, true)
        FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
        if deps_.markDirty then deps_.markDirty() end
        RebuildUI()
        return true
    end
    ShowToast("收获失败")
    return false
end

function PlantActionController.PerformPlotAction(plotIndex, localPos)
    SetSelectedPlot(plotIndex)
    deps_.refreshSelection()
    local plot = GetPlots()[GetSelectedPlot()]
    if plot == nil then return end

    if not plot.unlocked then
        ShowToast("这块田地尚未解锁")
        RefreshUI(true)
        return
    end

    if not deps_.isPlantView() then
        ShowToast("当前是查看状态，请先点击下方“开始种植”")
        RefreshUI(true)
        return
    end

    local clickedMatureCrop = nil
    local clickedCrop = nil
    if deps_.getPlantTab() == "harvest" and localPos ~= nil then
        clickedCrop = deps_.findPlantAtLocalPosition(plot, localPos, false)
        if clickedCrop ~= nil and clickedCrop.mature then
            clickedMatureCrop = clickedCrop
        end
    end
    if clickedCrop ~= nil and clickedMatureCrop == nil then
        ShowToast("还需 " .. FormatGrowCountdown(GetCropRemainingSeconds(clickedCrop)) .. " 成熟")
        RebuildUI()
        return
    end
    if clickedMatureCrop ~= nil then
        if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.IsHarvestPending ~= nil and deps_.EconomyCloudSystem.IsHarvestPending() then
            ShowToast("收获请求处理中，请稍后", true)
            RebuildUI()
            return
        end
        local success, harvestInfo = PlantActionController.HarvestNearestMature(GetSelectedPlot(), localPos)
        if success then
            if harvestInfo and harvestInfo.pendingServer then
                ShowToast("正在请求服务器收获...", true)
            else
                AudioSystem.PlaySFX("harvest_crop")
                local cropName = harvestInfo and harvestInfo.name or clickedMatureCrop.name
                local exp = harvestInfo and harvestInfo.exp or 0
                local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
                ShowToast(text, true)
                FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
            end
        end
        RebuildUI()
        return
    end

    -- 根据当前 Tab 决定操作
    if deps_.getPlantTab() == "seed" then
        -- 播种模式：点击土地播种
        if deps_.countPlotPlants(plot) >= deps_.config.MaxCropsPerPlot then
            ShowPlotFullMessage()
        elseif not PlantActionController.EnsureSelectedSeedAvailable() then
            ShowToast("没有可用种子，前往商店购买")
        else
            local plantedSeed = GetSelectedSeed()
            print(string.format("[播种动作] 点击有效 plot=%s seed=%s local=(%.3f,%.3f)",
                tostring(GetSelectedPlot()),
                tostring(plantedSeed),
                localPos and localPos.x or 0,
                localPos and localPos.z or 0))
            local success, reason = PlantActionController.PlantSeedAt(GetSelectedPlot(), plantedSeed, localPos or Vector3(0, 0, 0))
            print(string.format("[播种动作] PlantSeedAt 返回 success=%s reason=%s", tostring(success), tostring(reason)))
            if success and reason == "pending_server" then
                ShowToast("正在请求服务器播种...", true)
            elseif success then
                AudioSystem.PlaySFX("plant_seed")
                ShowToast("已播种 " .. GetPlants()[plantedSeed].name, true)
                PlantActionController.SelectNextOwnedSeedIfEmpty(plantedSeed)
            elseif reason == "plant_pending" then
                ShowToast("播种请求处理中，请稍后", true)
            elseif reason == "plant_cooldown" then
                -- 极短本地防抖只吞掉同一点击连发，不伪装成服务器请求。
            elseif reason == "occupied" then
                local text = "请换个地方播种"
                ShowToast(text)
                FloatingToast.Show(text)
            elseif reason == "server_unavailable" then
                ShowToast("同步中")
            else
                ShowToast("没有该种子，前往商店购买")
            end
        end
    elseif deps_.getPlantTab() == "harvest" then
        -- 收获模式：点击成熟作物收获，未成熟作物在页签中查看倒计时
        if deps_.countMaturePlants(plot) <= 0 then
            if deps_.countPlotPlants(plot) > 0 then
                ShowToast("作物还在生长，请查看收获页倒计时")
            else
                ShowToast("当前地块暂无作物")
            end
        else
            local crop = nil
            if localPos ~= nil then
                crop = deps_.findPlantAtLocalPosition(plot, localPos, true)
            end
            if crop ~= nil then
                local success, harvestInfo = PlantActionController.HarvestNearestMature(GetSelectedPlot(), localPos)
                if success then
                    if harvestInfo and harvestInfo.pendingServer then
                        ShowToast("正在请求服务器收获...", true)
                    else
                        AudioSystem.PlaySFX("harvest_crop")
                        local cropName = harvestInfo and harvestInfo.name or crop.name
                        local exp = harvestInfo and harvestInfo.exp or 0
                        local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
                        ShowToast(text, true)
                        FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
                    end
                end
            else
                local text = "请点击成熟作物本体进行收获"
                ShowToast(text)
                FloatingToast.Show(text)
            end
        end
    else
        ShowToast("切换到播种或收获进行操作")
    end
    RebuildUI()
end

function PlantActionController.SelectSeedIndex(index)
    PlantActionController.SetSelectedSeedIndex(index)
    ShowToast("已选择 " .. GetPlants()[GetSelectedSeed()].name)
    RefreshUI(true)
end

function PlantActionController.CycleSeed(delta)
    local plants = GetPlants()
    local seedBag = GetSeedBag()
    if #plants <= 0 then return end
    local direction = delta >= 0 and 1 or -1
    local selectedSeed = GetSelectedSeed()
    for step = 1, #plants do
        selectedSeed = selectedSeed + direction
        if selectedSeed < 1 then selectedSeed = #plants end
        if selectedSeed > #plants then selectedSeed = 1 end
        if (seedBag[selectedSeed] or 0) > 0 then
            break
        end
    end
    SetSelectedSeed(selectedSeed)
    RefreshUI(true)
end

return PlantActionController
