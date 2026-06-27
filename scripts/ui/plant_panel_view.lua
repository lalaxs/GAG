-- ============================================================================
-- 种植面板 UI 视图 (Plant Panel View)
-- Grow A Garden
-- ============================================================================
-- 负责种植模式三 Tab 内容区：播种 / 收获 / 背包。
-- 外层底部面板与 Tab 按钮暂留 main.lua，避免一次迁移过大。
-- ============================================================================

local UI = require("urhox-libs/UI")

local function GetFallbackSeedIndex(index)
    if index == nil then return nil end
    return ((index - 1) % 29) + 1
end

local function GetPlantImageIndex(index)
    if index == nil then return nil end
    if index >= 1 and index <= 47 then return index end
    return ((index - 1) % 29) + 1
end

local function GetSeedIconPath(index)
    return string.format("image/icons_3d/seed (%d).png", GetFallbackSeedIndex(index) or 1)
end

local function GetPlantImagePath(index)
    return string.format("image/plants/plants (%d).png", GetPlantImageIndex(index) or 1)
end

local PlantPanelView = {}

local deps_ = {}

function PlantPanelView.Init(deps)
    deps_ = deps or {}
end

local function RefreshPanel()
    if deps_.refreshPanel ~= nil then
        deps_.refreshPanel()
    elseif deps_.rebuildUI ~= nil then
        deps_.rebuildUI()
    end
end

local function GetOwnedSeedIndices()
    local list = {}
    local plants = deps_.plants
    local seedBag = deps_.seedBag
    for i = 1, #plants do
        if (seedBag[i] or 0) > 0 then
            table.insert(list, i)
        end
    end
    return list
end

function PlantPanelView.BuildContent()
    local plot = deps_.getSelectedPlot()
    local plantTab = deps_.getPlantTab()
    local selectedSeed = deps_.getSelectedSeed()
    local COL_TXT = {75, 55, 40, 255}
    local COL_SUB = {130, 110, 85, 220}
    local CONTENT_H = 200
    local HARVEST_CONTENT_H = 309

    if plantTab == "seed" then
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

        local curIdx = 1
        for i, v in ipairs(ownedList) do
            if v == selectedSeed then curIdx = i; break end
        end

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
            local plant = deps_.plants[plantIndex]
            local owned = deps_.seedBag[plantIndex] or 0
            local iconPath = GetSeedIconPath(plantIndex)
            local cardW = isCenter and 137 or 107
            local cardH = isCenter and 137 or 107
            local iconW = isCenter and 102 or 78
            local iconH = isCenter and 88 or 68
            local rarityColor = deps_.getUiRarityColor and deps_.getUiRarityColor(plant.rarity or "普通") or COL_TXT

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
                    deps_.suppressWorldTap()
                    deps_.setSelectedSeed(plantIndex)
                    RefreshPanel()
                end,
                children = {
                    UI.Panel {
                        width = iconW,
                        height = iconH,
                        marginBottom = 2,
                        backgroundImage = iconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = plant.name .. "种子", fontSize = isCenter and 12 or 10, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" },
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

        local function switchSeed(delta)
            local newIdx = curIdx + delta
            if newIdx < 1 then newIdx = #ownedList end
            if newIdx > #ownedList then newIdx = 1 end
            deps_.setSelectedSeed(ownedList[newIdx])
            RefreshPanel()
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
                        UI.Panel {
                            flexDirection = "row",
                            justifyContent = "center",
                            alignItems = "center",
                            gap = 15,
                            flexGrow = 1,
                            children = { cards[1], cards[2], cards[3] },
                        },
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            left = 0,
                            text = "<", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() deps_.suppressWorldTap(); switchSeed(-1) end,
                        } or UI.Panel { width = 0, height = 0 },
                        #ownedList > 1 and UI.Button {
                            position = "absolute",
                            right = 0,
                            text = ">", width = 28, height = 44, fontSize = 18,
                            backgroundColor = {0, 0, 0, 0}, fontColor = {100, 80, 60, 255}, borderRadius = 6,
                            onClick = function() deps_.suppressWorldTap(); switchSeed(1) end,
                        } or UI.Panel { width = 0, height = 0 },
                    },
                },
            },
        }

    elseif plantTab == "harvest" then
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
                                    deps_.suppressWorldTap()
                                    deps_.harvestNearestMature(deps_.getSelectedPlotIndex(), crop.localPos)
                                end,
                            },
                        },
                    })
                end
            end
        end

        if #harvestCards > 0 then
            return UI.Panel {
                height = HARVEST_CONTENT_H,
                gap = 6,
                children = {
                    UI.Label { text = "点击土地中成熟的作物收获", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT },
                    UI.ScrollView {
                        scrollY = true, showScrollbar = false, flexGrow = 1, flexBasis = 0,
                        children = harvestCards,
                    },
                },
            }
        else
            return UI.Panel {
                height = HARVEST_CONTENT_H,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "当前地块暂无成熟作物", fontSize = 14, fontColor = COL_SUB },
                },
            }
        end

    else
        local capacity = deps_.getHarvestBagCapacity and deps_.getHarvestBagCapacity() or 20
        local slotW = "19.0%"
        local slotH = 90
        local iconW = 54
        local iconH = 45
        local gridGap = 4

        local slots = {}
        for i = 1, capacity do
            local item = deps_.harvested[i]
            local itemIconPath = item and item.plantIndex and GetPlantImagePath(item.plantIndex) or nil
            local weightText = item and item.weight and string.format("%.2fkg", item.weight) or ""
            local isGiant = item ~= nil and item.weightTier == "Giant"
            table.insert(slots, UI.Panel {
                width = slotW,
                height = slotH,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 8,
                borderWidth = 1,
                borderColor = {195, 180, 150, 200},
                onClick = function()
                    deps_.suppressWorldTap()
                    if item ~= nil then
                        deps_.openBagItemDetail(item)
                    end
                end,
                children = item and {
                    UI.Panel {
                        width = iconW,
                        height = iconH,
                        marginBottom = 2,
                        backgroundImage = itemIconPath,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = item.name, fontSize = 9, fontWeight = "bold", fontColor = COL_TXT, textAlign = "center" },
                    UI.Label { text = weightText, fontSize = 8, fontWeight = "bold", fontColor = isGiant and {220, 80, 70, 255} or {94, 160, 100, 255}, textAlign = "center" },
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
            gap = 6,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label { text = "收获背包", fontSize = 12, fontWeight = "bold", fontColor = COL_TXT },
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 8,
                            children = {
                                UI.Label { text = string.format("%d/%d", #deps_.harvested, capacity), fontSize = 12, fontWeight = "bold", fontColor = #deps_.harvested >= capacity and {220, 80, 70, 255} or COL_SUB },
                                UI.Button {
                                    text = "一键出售",
                                    width = 88,
                                    height = 32,
                                    fontSize = 13,
                                    fontWeight = "bold",
                                    borderRadius = 12,
                                    backgroundColor = {255, 238, 190, 255},
                                    fontColor = {115, 82, 45, 255},
                                    borderWidth = 1,
                                    borderColor = {220, 175, 90, 230},
                                    onClick = function()
                                        deps_.suppressWorldTap()
                                        if deps_.openBulkSell then
                                            deps_.openBulkSell()
                                        end
                                    end,
                                },
                            },
                        },
                    },
                },
                UI.ScrollView {
                    scrollY = true,
                    showScrollbar = false,
                    flexGrow = 1,
                    flexBasis = 0,
                    children = {
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            flexWrap = "wrap",
                            gap = gridGap,
                            justifyContent = "flex-start",
                            children = slots,
                        },
                    },
                },
            },
        }
    end
end

return PlantPanelView
