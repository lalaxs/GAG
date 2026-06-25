-- ============================================================================
-- 种植玩法动作控制器
-- Grow A Garden
-- ============================================================================
-- 统一管理播种、收获、购买、出售和种子选择动作。
-- 只迁移 main.lua 中原有动作编排，不改变判断顺序、提示文案和数值。
-- ============================================================================

local FloatingToast = require("ui.floating_toast")
local AudioSystem = require("systems.audio_system")

local PlantActionController = {}

local deps_ = {}

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

function PlantActionController.PlantSeedAt(plotIndex, plantIndex, centerLocalPos)
    local success, reason = deps_.CropSystem.PlantSeedAt(GetPlots(), plotIndex, plantIndex, centerLocalPos)
    if success then
        RefreshTourValue()
    end
    return success, reason
end

function PlantActionController.HarvestNearestMature(plotIndex, localPos)
    local success, harvestInfo = deps_.CropSystem.HarvestNearestMature(GetPlots(), plotIndex, localPos)
    if success then
        RefreshTourValue()
    end
    return success, harvestInfo
end

function PlantActionController.PlantSeed(plotIndex, plantIndex)
    return PlantActionController.PlantSeedAt(plotIndex, plantIndex, Vector3(0, 0, 0))
end

function PlantActionController.BuySelectedSeed()
    local selectedSeed = GetSelectedSeed()
    local plant = GetPlants()[selectedSeed]
    if not deps_.WalletSystem.Spend(plant.seedPrice) then
        AudioSystem.PlaySFX("error_denied")
        print("金币不足，无法购买: " .. plant.name)
        return false
    end
    deps_.addSeedToBag(selectedSeed, 1, 0)
    AudioSystem.PlaySFX("buy_seed")
    print("购买种子: " .. plant.name .. "，剩余金币 " .. deps_.WalletSystem.GetBalance())
    return true
end

function PlantActionController.SellAllHarvested()
    local total = deps_.InventorySystem.SellAllHarvested()
    if total > 0 then
        deps_.setSelectedBagItem(nil)
        if deps_.clearBagPreview ~= nil then
            deps_.clearBagPreview()
        end
        deps_.WalletSystem.Add(total)
        AudioSystem.PlaySFX("sell_success")
    end
    return total
end

function PlantActionController.SellBagItem(item)
    local earned = deps_.InventorySystem.SellBagItem(item)
    if earned > 0 then
        deps_.setSelectedBagItem(nil)
        if deps_.clearBagPreview ~= nil then
            deps_.clearBagPreview()
        end
        deps_.WalletSystem.Add(earned)
        AudioSystem.PlaySFX("sell_success")
    end
    return earned
end

function PlantActionController.SellHarvestedByFilter(filter)
    local count, total = deps_.InventorySystem.SellHarvestedByFilter(filter)
    if count > 0 then
        deps_.setSelectedBagItem(nil)
        if deps_.clearBagPreview ~= nil then
            deps_.clearBagPreview()
        end
        deps_.WalletSystem.Add(total)
        AudioSystem.PlaySFX("sell_success")
    end
    return count, total
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

function PlantActionController.PerformPlotAction(plotIndex, localPos)
    SetSelectedPlot(plotIndex)
    deps_.refreshSelection()
    local plot = GetPlots()[GetSelectedPlot()]
    if plot == nil then return end

    if not plot.unlocked then
        AudioSystem.PlaySFX("error_denied")
        ShowToast("这块田地尚未解锁")
        RefreshUI(true)
        return
    end

    if not deps_.isPlantView() then
        AudioSystem.PlaySFX("error_denied")
        ShowToast("当前是查看状态，请先点击下方“开始种植”")
        RefreshUI(true)
        return
    end

    -- 根据当前 Tab 决定操作
    if deps_.getPlantTab() == "seed" then
        -- 播种模式：点击土地播种
        if deps_.countPlotPlants(plot) >= deps_.config.MaxCropsPerPlot then
            AudioSystem.PlaySFX("error_denied")
            ShowToast("这块田地已满")
        elseif not PlantActionController.EnsureSelectedSeedAvailable() then
            AudioSystem.PlaySFX("error_denied")
            ShowToast("没有可用种子，前往商店购买")
        else
            local plantedSeed = GetSelectedSeed()
            local success, reason = PlantActionController.PlantSeedAt(GetSelectedPlot(), plantedSeed, localPos or Vector3(0, 0, 0))
            if success then
                AudioSystem.PlaySFX("plant_seed")
                ShowToast("已播种 " .. GetPlants()[plantedSeed].name, true)
                PlantActionController.SelectNextOwnedSeedIfEmpty(plantedSeed)
            elseif reason == "occupied" then
                AudioSystem.PlaySFX("error_denied")
                local text = "请换个地方播种"
                ShowToast(text)
                FloatingToast.Show(text)
            else
                AudioSystem.PlaySFX("error_denied")
                ShowToast("没有该种子，前往商店购买")
            end
        end
    elseif deps_.getPlantTab() == "harvest" then
        -- 收获模式：点击成熟作物收获
        if deps_.countMaturePlants(plot) <= 0 then
            AudioSystem.PlaySFX("error_denied")
            ShowToast("当前地块暂无成熟作物")
        else
            local crop = nil
            if localPos ~= nil then
                crop = deps_.findPlantAtLocalPosition(plot, localPos, true)
            end
            if crop ~= nil then
                local success, harvestInfo = PlantActionController.HarvestNearestMature(GetSelectedPlot(), localPos)
                if success then
                    AudioSystem.PlaySFX("harvest_crop")
                    local cropName = harvestInfo and harvestInfo.name or crop.name
                    local exp = harvestInfo and harvestInfo.exp or 0
                    local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
                    ShowToast(text, true)
                    FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
                end
            else
                local success, harvestInfo = PlantActionController.HarvestNearestMature(GetSelectedPlot(), nil)
                if success then
                    AudioSystem.PlaySFX("harvest_crop")
                    local cropName = harvestInfo and harvestInfo.name or "作物"
                    local exp = harvestInfo and harvestInfo.exp or 0
                    local text = "收获了" .. cropName .. "，获得了" .. exp .. "经验"
                    ShowToast(text, true)
                    FloatingToast.Show(text, { fontSize = 19, duration = 1.6, yRatio = 0.42, priority = 0 })
                end
            end
        end
    else
        AudioSystem.PlaySFX("error_denied")
        ShowToast("切换到播种或收获进行操作")
    end
    RebuildUI()
end

function PlantActionController.SelectSeedIndex(index)
    PlantActionController.SetSelectedSeedIndex(index)
    AudioSystem.PlaySFX("bag_select_item")
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
