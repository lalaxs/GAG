-- ============================================================================
-- 作物图鉴 UI 视图 (Codex View)
-- Grow A Garden
-- ============================================================================
-- 负责作物图鉴网格与作物详情弹窗。
-- 未解锁作物复用原作物图标，并通过 imageTint 覆盖为黑色剪影。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local Format = require("utils.format")

local CodexView = {}

local deps_ = {}
local codexModal_ = nil
local detailModal_ = nil
local activeTab_ = "base"
local tabButtonRefs_ = {}
local progressPercentLabel_ = nil
local progressFill_ = nil
local progressCountLabel_ = nil
local cardGrid_ = nil

local RARITY_COLORS = {
    ["普通"] = {120, 105, 82, 255},
    ["罕见"] = {78, 172, 96, 255},
    ["稀有"] = {72, 132, 210, 255},
    ["史诗"] = {154, 92, 205, 255},
    ["传奇"] = {225, 142, 42, 255},
}

function CodexView.Init(deps)
    deps_ = deps or {}
end

local function GetPlantIconPath(plantIndex)
    return string.format("image/plants/plants (%d).png", plantIndex)
end

local function IsPlantDiscovered(plantIndex)
    local collected = deps_.collectedPlants or {}
    return collected[plantIndex] == true
end

local function IsActivityPlant(plant)
    return plant ~= nil and (plant.limited == true or plant.activityTag ~= nil)
end

local function IsPlantInActiveTab(plant)
    local isActivity = IsActivityPlant(plant)
    if activeTab_ == "activity" then
        return isActivity
    end
    return not isActivity
end

local function CountDiscoveredPlants(tab)
    local plants = deps_.plants or {}
    local count = 0
    for i, plant in ipairs(plants) do
        local isActivity = IsActivityPlant(plant)
        local include = (tab == "activity") and isActivity or not isActivity
        if include and IsPlantDiscovered(i) then
            count = count + 1
        end
    end
    return count
end

local function CountPlantsInTab(tab)
    local plants = deps_.plants or {}
    local count = 0
    for _, plant in ipairs(plants) do
        local isActivity = IsActivityPlant(plant)
        if ((tab == "activity") and isActivity) or ((tab ~= "activity") and not isActivity) then
            count = count + 1
        end
    end
    return count
end

local function BuildStatRow(label, value, valueColor)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 9,
        paddingBottom = 9,
        paddingLeft = 13,
        paddingRight = 13,
        backgroundColor = {255, 250, 238, 225},
        borderRadius = 12,
        children = {
            UI.Label { text = label, fontSize = 14, fontColor = {115, 88, 65, 255} },
            UI.Label { text = value, fontSize = 16, fontWeight = "bold", fontColor = valueColor or {76, 150, 88, 255}, textAlign = "right" },
        },
    }
end

local function CloseDetailModal()
    if detailModal_ ~= nil then
        detailModal_:Close()
        detailModal_ = nil
    end
end

local function ShowPlantDetail(plantIndex)
    CloseDetailModal()

    local plants = deps_.plants or {}
    local plant = plants[plantIndex]
    if plant == nil then return end

    local discovered = IsPlantDiscovered(plantIndex)
    local rarityColor = RARITY_COLORS[plant.rarity] or {120, 105, 82, 255}
    local title = discovered and plant.name or "未发现的作物"
    local stats = (deps_.codexStats or {})[plantIndex] or {}

    detailModal_ = UI.Modal {
        title = title,
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 16, 16},
        onClose = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            detailModal_ = nil
        end,
    }

    local iconPanel = UI.Panel {
        width = 158,
        height = 158,
        backgroundImage = GetPlantIconPath(plantIndex),
        backgroundFit = "contain",
        imageTint = discovered and {255, 255, 255, 255} or {0, 0, 0, 235},
        opacity = discovered and 1.0 or 0.82,
    }

    local detailRows = {}
    if discovered then
        local maxWeight = stats.maxWeight or 0
        local maxWeightText = maxWeight > 0 and string.format("%.2fkg", maxWeight) or "暂无记录"
        local harvestCount = stats.harvestCount or 0
        local maxPrice = stats.maxPrice or 0
        local maxPriceText = maxPrice > 0 and (Format.Gold(maxPrice) .. " 金币") or "暂无记录"

        table.insert(detailRows, BuildStatRow("稀有度", plant.rarity or "普通", rarityColor))
        table.insert(detailRows, BuildStatRow("基础成熟时间", tostring(plant.growTime or 0) .. " 秒", {70, 145, 95, 255}))
        table.insert(detailRows, BuildStatRow("基础售价", Format.Gold(plant.fruitPrice or 0) .. " 金币", {185, 125, 38, 255}))
        table.insert(detailRows, BuildStatRow("种子价格", Format.Gold(plant.seedPrice or 0) .. " 金币", {185, 125, 38, 255}))
        table.insert(detailRows, BuildStatRow("历史最大重量", maxWeightText, {86, 132, 190, 255}))
        table.insert(detailRows, BuildStatRow("累计收获", tostring(harvestCount) .. " 次", {76, 150, 88, 255}))
        table.insert(detailRows, BuildStatRow("历史最高售价", maxPriceText, {200, 120, 45, 255}))
    else
        table.insert(detailRows, BuildStatRow("名称", "？？？", {90, 82, 72, 255}))
        table.insert(detailRows, BuildStatRow("状态", "尚未收获", {150, 90, 72, 255}))
        table.insert(detailRows, UI.Panel {
            paddingTop = 16,
            paddingBottom = 16,
            paddingLeft = 16,
            paddingRight = 16,
            backgroundColor = {245, 236, 220, 245},
            borderRadius = 16,
            borderWidth = 2,
            borderColor = {190, 168, 132, 220},
            gap = 8,
            children = {
                UI.Label {
                    text = "收获该作物后解锁详细信息。",
                    fontSize = 16,
                    fontWeight = "bold",
                    fontColor = {100, 82, 65, 255},
                    textAlign = "center",
                },
                UI.Label {
                    text = "继续购买种子、种植并完成收获，就能点亮这条图鉴。",
                    fontSize = 13,
                    fontColor = {130, 106, 82, 235},
                    textAlign = "center",
                },
            },
        })
    end

    detailModal_:AddContent(UI.Panel {
        paddingTop = 12,
        paddingBottom = 14,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = {255, 248, 226, 245},
        borderRadius = 24,
        gap = 13,
        children = {
            UI.Panel {
                height = 190,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = discovered and {255, 253, 245, 255} or {225, 220, 205, 245},
                borderRadius = 22,
                borderWidth = 2,
                borderColor = discovered and {132, 202, 150, 225} or {150, 140, 125, 220},
                overflow = "hidden",
                children = {
                    UI.Panel { position = "absolute", left = 28, right = 28, bottom = 28, height = 28, borderRadius = 14, backgroundColor = discovered and {90, 160, 100, 36} or {30, 25, 20, 45} },
                    iconPanel,
                    UI.Panel { width = 0, height = 0 },
                },
            },
            UI.Panel { gap = 8, children = detailRows },
            UI.Button {
                text = "关闭",
                width = "100%",
                height = 46,
                fontSize = 17,
                fontWeight = "bold",
                variant = "primary",
                borderRadius = 16,
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    CloseDetailModal()
                end,
            },
        },
    })

    ModalAnim.Apply(detailModal_, { fixedHeight = discovered and 760 or 590 })
    detailModal_:Open()
end

local RefreshCodexTabContent

local function BuildTabButton(tab, text, count)
    local selected = activeTab_ == tab
    local button = UI.Button {
        text = string.format("%s %d", text, count or 0),
        width = 136,
        height = 42,
        fontSize = 15,
        fontWeight = "bold",
        variant = selected and "primary" or "secondary",
        borderRadius = 16,
        onClick = function()
            if activeTab_ == tab then return end
            activeTab_ = tab
            if RefreshCodexTabContent ~= nil then
                RefreshCodexTabContent()
            end
        end,
    }
    tabButtonRefs_[tab] = { button = button, text = text }
    return button
end

local function BuildCodexCard(plantIndex, plant)
    local discovered = IsPlantDiscovered(plantIndex)
    local rarityColor = RARITY_COLORS[plant.rarity] or {170, 145, 105, 255}

    return UI.Panel {
        width = 102,
        height = 138,
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 7,
        paddingRight = 7,
        marginBottom = 9,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = discovered and {255, 253, 245, 255} or {228, 222, 208, 245},
        borderRadius = 16,
        borderWidth = 2,
        borderColor = discovered and rarityColor or {155, 145, 130, 210},
        overflow = "hidden",
        onClick = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            ShowPlantDetail(plantIndex)
        end,
        children = {
            UI.Panel {
                width = 82,
                height = 72,
                marginBottom = 7,
                backgroundImage = GetPlantIconPath(plantIndex),
                backgroundFit = "contain",
                imageTint = discovered and {255, 255, 255, 255} or {0, 0, 0, 235},
                opacity = discovered and 1.0 or 0.82,
            },
            UI.Panel { width = 0, height = 0 },
            UI.Label {
                text = discovered and plant.name or "？？？",
                fontSize = 13,
                fontWeight = "bold",
                fontColor = discovered and {80, 60, 42, 255} or {92, 82, 72, 255},
                textAlign = "center",
            },
            UI.Panel { width = 0, height = 0 },
        },
    }
end

RefreshCodexTabContent = function()
    if cardGrid_ == nil then return end

    local plants = deps_.plants or {}
    local discoveredCount = CountDiscoveredPlants(activeTab_)
    local totalCount = CountPlantsInTab(activeTab_)
    local baseCount = CountPlantsInTab("base")
    local activityCount = CountPlantsInTab("activity")
    local progressRatio = totalCount > 0 and (discoveredCount / totalCount) or 0
    local progressPercent = math.floor(progressRatio * 100 + 0.5)

    for tab, ref in pairs(tabButtonRefs_) do
        if ref.button ~= nil then
            local count = tab == "activity" and activityCount or baseCount
            ref.button:SetText(string.format("%s %d", ref.text, count))
            ref.button:SetStyle({ variant = activeTab_ == tab and "primary" or "secondary" })
        end
    end

    if progressPercentLabel_ ~= nil then
        progressPercentLabel_:SetText(string.format("%d%%", progressPercent))
    end
    if progressFill_ ~= nil then
        progressFill_:SetStyle({ width = tostring(progressPercent) .. "%" })
    end
    if progressCountLabel_ ~= nil then
        progressCountLabel_:SetText(string.format("已点亮 %d / %d", discoveredCount, totalCount))
    end

    cardGrid_:RemoveAllChildren()
    for i, plant in ipairs(plants) do
        if IsPlantInActiveTab(plant) then
            cardGrid_:AddChild(BuildCodexCard(i, plant))
        end
    end
end

function CodexView.Show()
    if codexModal_ ~= nil then
        codexModal_:Close()
    end
    CloseDetailModal()

    tabButtonRefs_ = {}
    progressPercentLabel_ = nil
    progressFill_ = nil
    progressCountLabel_ = nil
    cardGrid_ = nil

    local plants = deps_.plants or {}
    local discoveredCount = CountDiscoveredPlants(activeTab_)
    local totalCount = CountPlantsInTab(activeTab_)
    local baseCount = CountPlantsInTab("base")
    local activityCount = CountPlantsInTab("activity")
    local progressRatio = totalCount > 0 and (discoveredCount / totalCount) or 0
    local progressPercent = math.floor(progressRatio * 100 + 0.5)
    local cards = {}
    for i, plant in ipairs(plants) do
        if IsPlantInActiveTab(plant) then
            table.insert(cards, BuildCodexCard(i, plant))
        end
    end

    progressPercentLabel_ = UI.Label {
        text = string.format("%d%%", progressPercent),
        fontSize = 18,
        fontWeight = "bold",
        fontColor = {78, 155, 100, 255},
    }

    progressFill_ = UI.Panel {
        width = tostring(progressPercent) .. "%",
        height = "100%",
        borderRadius = 6,
        backgroundColor = {94, 194, 131, 255},
    }

    progressCountLabel_ = UI.Label {
        text = string.format("已点亮 %d / %d", discoveredCount, totalCount),
        fontSize = 12,
        fontColor = {106, 136, 88, 235},
        textAlign = "center",
    }

    cardGrid_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 5,
        justifyContent = "flex-start",
        children = cards,
    }

    codexModal_ = UI.Modal {
        title = "作物图鉴",
        size = "lg",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 14, 16, 14},
        onClose = function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            codexModal_ = nil
            tabButtonRefs_ = {}
            progressPercentLabel_ = nil
            progressFill_ = nil
            progressCountLabel_ = nil
            cardGrid_ = nil
            CloseDetailModal()
        end,
    }

    codexModal_:AddContent(UI.Panel {
        paddingTop = 10,
        paddingBottom = 12,
        paddingLeft = 10,
        paddingRight = 10,
        gap = 12,
        backgroundColor = {255, 248, 226, 245},
        borderRadius = 24,
        children = {
            UI.Panel {
                paddingTop = 12,
                paddingBottom = 12,
                paddingLeft = 14,
                paddingRight = 14,
                backgroundColor = {238, 249, 232, 245},
                borderRadius = 18,
                borderWidth = 2,
                borderColor = {128, 196, 132, 210},
                gap = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label { text = "收藏进度", fontSize = 15, fontWeight = "bold", fontColor = {74, 120, 70, 255} },
                            progressPercentLabel_,
                        },
                    },
                    UI.Panel {
                        height = 12,
                        borderRadius = 6,
                        backgroundColor = {218, 232, 206, 255},
                        overflow = "hidden",
                        children = {
                            progressFill_,
                        },
                    },
                    progressCountLabel_,
                },
            },
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 10,
                children = {
                    BuildTabButton("base", "基础", baseCount),
                    BuildTabButton("activity", "活动", activityCount),
                },
            },
            UI.ScrollView {
                height = 460,
                scrollY = true,
                showScrollbar = false,
                children = {
                    cardGrid_,
                },
            },
        },
    })

    ModalAnim.Apply(codexModal_, { fixedHeight = 680 })
    codexModal_:Open()
end

function CodexView.Hide()
    if codexModal_ ~= nil then
        codexModal_:Close()
    end
    CloseDetailModal()
end

function CodexView.IsOpen()
    return codexModal_ ~= nil or detailModal_ ~= nil
end

return CodexView
