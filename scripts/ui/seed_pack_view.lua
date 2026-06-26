-- ============================================================================
-- 种子礼包 UI 视图 (Seed Pack View)
-- Grow A Garden
-- ============================================================================
-- 只负责种子礼包相关 UI 构建，不持有游戏业务状态。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local FloatingToast = require("ui.floating_toast")

local deps_ = {}

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

local function IsLimitedSeed(seedId)
    local plant = deps_.plants and deps_.plants[seedId]
    return plant ~= nil and (plant.limited == true or plant.activityTag ~= nil)
end

local function GetPackRollDisplayPool(packId)
    local packCfg = deps_.seedPackConfig and deps_.seedPackConfig[packId]
    local pool = {}
    if packCfg ~= nil then
        for _, item in ipairs(packCfg.weightPool or {}) do
            if packCfg.allowLimitedSeeds == true or not IsLimitedSeed(item.seedId) then
                table.insert(pool, item.seedId)
            end
        end
    end
    if #pool == 0 then
        for seedId, plant in ipairs(deps_.plants or {}) do
            if plant ~= nil and not IsLimitedSeed(seedId) then
                table.insert(pool, seedId)
            end
        end
    end
    if #pool == 0 then
        pool[1] = 1
    end
    return pool
end

local function GetPlantImagePath(index)
    return string.format("image/plants/plants (%d).png", GetPlantImageIndex(index) or 1)
end

local SeedPackView = {}

local selectedPackId_ = nil
local packModal_ = nil
local batchResultModal_ = nil

function SeedPackView.Init(deps)
    deps_ = deps or {}
end

-- Modal 函数前向声明（实现在文件末尾，因为依赖后面定义的 BuildPackCardGrid 等）

local function BuildResultCards(results)
    local cards = {}
    local counts = deps_.countPackResults(results)
    local sorted = {}
    for seedId, count in pairs(counts) do
        table.insert(sorted, seedId)
    end
    table.sort(sorted, function(a, b)
        local plants = deps_.plants
        local rarityOrder = deps_.rarityOrder
        local ra = rarityOrder[plants[a].rarity] or 1
        local rb = rarityOrder[plants[b].rarity] or 1
        if ra == rb then return a < b end
        return ra < rb
    end)

    for _, seedId in ipairs(sorted) do
        local plant = deps_.plants[seedId]
        local plantName = plant.name
        local rarity = plant.rarity
        local count = counts[seedId] or 0
        local rarityColor = deps_.getUiRarityColor(rarity)
        local newFlag = false
        local silverFlag = false
        for _, result in ipairs(results) do
            if result.seedId == seedId then
                newFlag = newFlag or result.isNew
                silverFlag = silverFlag or result.seedBuff > 0
            end
        end
        table.insert(cards, UI.Panel {
            width = "46%",
            minHeight = 104,
            padding = 8,
            marginBottom = 8,
            alignItems = "center",
            backgroundColor = silverFlag and {245, 248, 255, 255} or {255, 253, 245, 255},
            borderRadius = 12,
            borderWidth = silverFlag and 3 or 2,
            borderColor = silverFlag and {190, 195, 215, 255} or rarityColor,
            children = {
                UI.Panel {
                    width = 50,
                    height = 44,
                    marginBottom = 4,
                    backgroundImage = GetSeedIconPath(seedId),
                    backgroundFit = "contain",
                },
                UI.Label { text = string.format("%s x%d", plantName, count), fontSize = 12, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center" },
                UI.Label { text = rarity, fontSize = 10, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" },
                newFlag and UI.Label { text = "新品", fontSize = 10, fontWeight = "bold", fontColor = {220, 55, 45, 255}, textAlign = "center" } or UI.Panel { height = 0 },
                silverFlag and UI.Label { text = "银种 +1%", fontSize = 9, fontColor = {90, 100, 130, 255}, textAlign = "center" } or UI.Panel { height = 0 },
            },
        })
    end
    return cards
end

local function BuildCompactResultCards(results)
    local cards = {}
    local counts = deps_.countPackResults(results)
    local sorted = {}
    for seedId, _ in pairs(counts) do
        table.insert(sorted, seedId)
    end
    table.sort(sorted, function(a, b)
        local plants = deps_.plants
        local rarityOrder = deps_.rarityOrder
        local ra = rarityOrder[plants[a].rarity] or 1
        local rb = rarityOrder[plants[b].rarity] or 1
        if ra == rb then return a < b end
        return ra > rb
    end)

    for _, seedId in ipairs(sorted) do
        local plant = deps_.plants[seedId]
        local count = counts[seedId] or 0
        local rarityColor = deps_.getUiRarityColor(plant.rarity)
        table.insert(cards, UI.Panel {
            width = "46%",
            minHeight = 150,
            padding = 6,
            marginBottom = 10,
            alignItems = "center",
            backgroundColor = {0, 0, 0, 0},
            children = {
                UI.Panel {
                    width = 96,
                    height = 88,
                    marginBottom = 6,
                    backgroundImage = GetSeedIconPath(seedId),
                    backgroundFit = "contain",
                },
                UI.Label { text = plant.name .. "种子包", width = 150, fontSize = 14, fontWeight = "bold", fontColor = rarityColor, textAlign = "center", maxLines = 2 },
                UI.Label { text = "x" .. tostring(count), width = 150, fontSize = 13, fontWeight = "bold", fontColor = {100, 82, 60, 230}, textAlign = "center", marginTop = 4 },
            },
        })
    end
    return cards
end

local function ComputePackProbabilities(cfg)
    local rarityWeights = {}
    local totalWeight = 0
    local rarityOrder = deps_.rarityOrder
    local plants = deps_.plants
    for _, entry in ipairs(cfg.weightPool) do
        local plant = plants[entry.seedId]
        if plant ~= nil then
            local rarity = plant.rarity
            rarityWeights[rarity] = (rarityWeights[rarity] or 0) + entry.weight
            totalWeight = totalWeight + entry.weight
        end
    end
    local probList = {}
    for rarity, w in pairs(rarityWeights) do
        local pct = math.floor(w / totalWeight * 100 + 0.5)
        table.insert(probList, { rarity = rarity, pct = pct, order = rarityOrder[rarity] or 0 })
    end
    table.sort(probList, function(a, b) return a.order > b.order end)
    return probList
end

local function GetPackSortOrder(cfg)
    if cfg.allowLimitedSeeds then return 100 + (deps_.rarityOrder[cfg.packRarity or "普通"] or 0) end
    return deps_.rarityOrder[cfg.packRarity or "普通"] or 0
end

local function BuildPackCardGrid()
    local cards = {}
    local seedPacks = deps_.seedPacks
    local sortedPacks = {}
    for packId, cfg in pairs(deps_.seedPackConfig) do
        local owned = seedPacks[packId] or 0
        if owned > 0 then
            table.insert(sortedPacks, { packId = packId, cfg = cfg, owned = owned })
        end
    end
    table.sort(sortedPacks, function(a, b)
        local ra = GetPackSortOrder(a.cfg)
        local rb = GetPackSortOrder(b.cfg)
        if ra == rb then return a.packId < b.packId end
        return ra < rb
    end)

    if selectedPackId_ == nil and #sortedPacks > 0 then
        selectedPackId_ = sortedPacks[1].packId
    end

    for _, item in ipairs(sortedPacks) do
        local packId = item.packId
        local cfg = item.cfg
        local owned = item.owned
        local isSelected = (packId == selectedPackId_)
        local iconPath = cfg.packIcon or "image/seedpack_icon/seedpack_0.png"
        local selectColors = {
            ["普通"] = {195, 195, 185, 255},
            ["罕见"] = {150, 210, 160, 255},
            ["稀有"] = {140, 180, 235, 255},
            ["史诗"] = {180, 140, 220, 255},
            ["传奇"] = {225, 175, 80, 255},
        }
        local selBg = isSelected and (selectColors[cfg.packRarity] or {195, 195, 185, 255}) or {0, 0, 0, 0}

        table.insert(cards, UI.Panel {
            width = 130,
            alignItems = "center",
            marginBottom = 14,
            marginRight = 10,
            children = {
                UI.Panel {
                    width = 124,
                    height = 148,
                    justifyContent = "center",
                    alignItems = "center",
                    borderRadius = 18,
                    backgroundColor = selBg,
                    children = {
                        UI.Panel {
                            width = 114,
                            height = 136,
                            backgroundImage = iconPath,
                            backgroundFit = "contain",
                        },
                        -- 右下角数量角标
                        UI.Panel {
                            position = "absolute",
                            right = 2,
                            bottom = 2,
                            minWidth = 24,
                            height = 24,
                            paddingLeft = 5,
                            paddingRight = 5,
                            borderRadius = 12,
                            backgroundColor = {50, 50, 50, 210},
                            justifyContent = "center",
                            alignItems = "center",
                            children = {
                                UI.Label { text = tostring(owned), fontSize = 12, fontWeight = "bold", fontColor = {255, 255, 255, 255} },
                            },
                        },
                    },
                    onClick = function()
                        deps_.suppressWorldTap()
                        selectedPackId_ = packId
                        if packModal_ then
                            SeedPackView.RebuildModalContent()
                        else
                            deps_.rebuildUI()
                        end
                    end,
                },
            },
        })
    end

    if #cards == 0 then
        return { UI.Label { text = "暂无可开启的种子包", fontSize = 14, fontColor = {120, 100, 80, 220}, textAlign = "center", marginTop = 30 } }
    end
    return cards
end

local function BuildPackDetailSection()
    if selectedPackId_ == nil then
        return UI.Panel { height = 0 }
    end
    local cfg = deps_.seedPackConfig[selectedPackId_]
    if cfg == nil then return UI.Panel { height = 0 } end
    local owned = deps_.seedPacks[selectedPackId_] or 0
    if owned <= 0 then
        selectedPackId_ = deps_.getFirstAvailablePackId()
        if selectedPackId_ == nil then return UI.Panel { height = 0 } end
        cfg = deps_.seedPackConfig[selectedPackId_]
        owned = deps_.seedPacks[selectedPackId_] or 0
    end

    local probList = ComputePackProbabilities(cfg)
    local probTexts = {}
    for _, p in ipairs(probList) do
        if p.pct > 0 then
            table.insert(probTexts, p.pct .. "%" .. p.rarity)
        end
    end
    local probStr = table.concat(probTexts, "  ")

    local previewSeeds = {}
    local seen = {}
    for _, entry in ipairs(cfg.weightPool) do
        if not seen[entry.seedId] then
            seen[entry.seedId] = true
            table.insert(previewSeeds, entry.seedId)
        end
        if #previewSeeds >= 5 then break end
    end

    local previewIcons = {}
    for _, seedId in ipairs(previewSeeds) do
        table.insert(previewIcons, UI.Panel {
            width = 44,
            height = 50,
            marginRight = 5,
            backgroundColor = {245, 245, 242, 255},
            borderRadius = 8,
            borderWidth = 1,
            borderColor = {210, 210, 205, 255},
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel {
                    width = 36,
                    height = 40,
                    backgroundImage = GetPlantImagePath(seedId),
                    backgroundFit = "contain",
                },
            },
        })
    end

    return UI.Panel {
        paddingTop = 14,
        paddingBottom = 24,
        paddingLeft = 12,
        paddingRight = 12,
        marginTop = 6,
        borderTopWidth = 2,
        borderColor = {220, 215, 205, 255},
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 6,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label { text = cfg.packName, fontSize = 16, fontWeight = "bold", fontColor = {50, 45, 40, 255} },
                            UI.Label { text = probStr, fontSize = 11, fontColor = {100, 95, 85, 230}, marginTop = 2 },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button {
                                text = "全开",
                                width = 76,
                                height = 38,
                                fontSize = 14,
                                fontWeight = "bold",
                                backgroundColor = {95, 165, 105, 255},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 10,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    if deps_.openAllSeedPacks then
                                        deps_.openAllSeedPacks(selectedPackId_)
                                    end
                                end,
                            },
                            UI.Button {
                                text = "打开",
                                width = 76,
                                height = 38,
                                fontSize = 14,
                                fontWeight = "bold",
                                backgroundColor = {240, 155, 60, 255},
                                fontColor = {255, 255, 255, 255},
                                borderRadius = 10,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    deps_.openSeedPack(selectedPackId_, 1)
                                end,
                            },
                        },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                marginTop = 6,
                children = previewIcons,
            },
        },
    }
end

function SeedPackView.BuildPackOverlay(isOpen)
    -- Modal 模式下此函数不再渲染弹窗，始终返回空面板
    return UI.Panel { width = 0, height = 0 }
end

function SeedPackView.BuildResultOverlay(title, results)
    if results == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    local newNames = {}
    for _, result in ipairs(results) do
        if result.isNew then
            local name = deps_.plants[result.seedId].name
            local exists = false
            for _, item in ipairs(newNames) do
                if item == name then exists = true; break end
            end
            if not exists then table.insert(newNames, name) end
        end
    end

    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 110,
        backgroundColor = {0, 0, 0, 130},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 500,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Label { text = title or "开包结果", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center", marginBottom = 8 },
                    #newNames > 0 and UI.Panel {
                        padding = 7,
                        marginBottom = 8,
                        backgroundColor = {255, 235, 232, 255},
                        borderRadius = 10,
                        borderWidth = 2,
                        borderColor = {220, 70, 60, 255},
                        children = { UI.Label { text = "解锁新品种：" .. table.concat(newNames, "、"), fontSize = 12, fontWeight = "bold", fontColor = {210, 55, 45, 255}, textAlign = "center" } },
                    } or UI.Panel { height = 0 },
                    UI.ScrollView {
                        height = 300,
                        scrollY = true,
                        showScrollbar = true,
                        children = {
                            UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 8, children = BuildResultCards(results) },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 10,
                        children = {
                            deps_.countSeedPacks() > 0 and UI.Button {
                                text = "下一包",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "primary",
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    local packId = deps_.getFirstAvailablePackId()
                                    if packId ~= nil then
                                        deps_.openSeedPack(packId, 1)
                                    end
                                end,
                            } or UI.Panel { width = 0, height = 0 },
                            UI.Button {
                                text = "关闭",
                                flexGrow = 1,
                                height = 38,
                                fontSize = 13,
                                variant = "secondary",
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    deps_.closeResultPanel()
                                    deps_.rebuildUI()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

local function MakeRollResult(seedId, baseResult)
    return {
        seedId = seedId,
        packId = baseResult ~= nil and baseResult.packId or nil,
        rollPackId = baseResult ~= nil and baseResult.rollPackId or nil,
        seedBuff = baseResult ~= nil and baseResult.seedBuff or 0,
        isNew = false,
    }
end

local function BuildRollingCards(results, targetResult, isSelected)
    local cardW = 105
    local rollPool = GetPackRollDisplayPool(targetResult and (targetResult.rollPackId or targetResult.packId))
    local halfCard = 47  -- 94/2

    -- 预生成种子序列：12个对应礼包池的展示种子 + 目标在最后
    local stripCount = 13
    local strip = {}
    for i = 1, stripCount - 1 do
        local poolIndex = ((i * 7 + 3) % #rollPool) + 1
        strip[i] = rollPool[poolIndex]
    end
    strip[stripCount] = targetResult.seedId  -- 目标放在最后

    -- 可见槽位（5个）
    local visibleCount = 5
    local slots = {}
    local cards = {}

    local function getStripSeed(index)
        -- 循环取序列中的种子
        local i = ((index - 1) % stripCount) + 1
        return strip[i]
    end

    local function applySlot(slot, seedId, x, selected)
        local plant = deps_.plants[seedId] or { name = "种子", rarity = "普通" }
        local rarityColor = deps_.getUiRarityColor(plant.rarity or "普通")
        local plantName = tostring(plant.name or "种子")
        local scaleH = selected and 130 or 112
        slot.panel:SetStyle({
            marginLeft = -halfCard + x,
            height = scaleH,
            marginTop = -scaleH / 2,
        })
        slot.icon:SetBackgroundImage(GetSeedIconPath(seedId))
        slot.icon:SetStyle({ width = selected and 76 or 66, height = selected and 76 or 66 })
        slot.name:SetText(plantName)
        slot.name:SetStyle({ fontColor = rarityColor, fontSize = selected and 14 or 12 })
    end

    for slotIndex = 1, visibleCount do
        local seedId = isSelected and (slotIndex == 3 and targetResult.seedId or getStripSeed(stripCount - 3 + slotIndex)) or getStripSeed(slotIndex)
        local plant = deps_.plants[seedId] or { name = "种子", rarity = "普通" }
        local rarityColor = deps_.getUiRarityColor(plant.rarity or "普通")
        local plantName = tostring(plant.name or "种子")
        local selected = isSelected and slotIndex == 3
        local scaleH = selected and 130 or 112
        local icon = UI.Panel { width = selected and 76 or 66, height = selected and 76 or 66, backgroundImage = GetSeedIconPath(seedId), backgroundFit = "contain" }
        local nameLabel = UI.Label { text = plantName, fontSize = selected and 14 or 12, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" }
        local panel = UI.Panel {
            position = "absolute",
            left = "50%",
            top = "50%",
            width = 94,
            height = scaleH,
            marginLeft = -halfCard + (slotIndex - 3) * cardW,
            marginTop = -scaleH / 2,
            alignItems = "center",
            justifyContent = "center",
            borderRadius = 12,
            children = {
                icon,
                nameLabel,
            },
        }
        local slot = { panel = panel, icon = icon, name = nameLabel }
        slots[slotIndex] = slot
        cards[slotIndex] = panel
    end

    -- 总滚动距离：从序列开头滚到目标（第stripCount个）出现在中间
    -- 目标在中间 = 需滚过 (stripCount - 3) 个卡片宽度
    local totalTravel = (stripCount - 3) * cardW

    local function update(scrollProgress)
        -- scrollProgress: 0~1，0=起始位置，1=目标在中间
        local offset = scrollProgress * totalTravel
        local baseIndex = math.floor(offset / cardW)
        local fractional = (offset % cardW)

        for slotIndex = 1, visibleCount do
            local stripIdx = baseIndex + slotIndex
            local seedId = getStripSeed(stripIdx)
            local x = (slotIndex - 3) * cardW - fractional
            local selected = (scrollProgress >= 1) and (slotIndex == 3)
            applySlot(slots[slotIndex], seedId, x, selected)
        end
    end

    return cards, update, totalTravel
end

function SeedPackView.BuildOpeningOverlay(opening, stage, revealIndex, timer, scrollOffset)
    if opening == nil then
        return UI.Panel { width = 0, height = 0 }
    end
    local results = opening.results or {}
    if #results == 0 then
        return UI.Panel { width = 0, height = 0 }
    end

    local currentIndex = math.max(1, math.min(revealIndex or 1, #results))
    local current = results[currentIndex]
    local currentPlant = deps_.plants[current.seedId] or { name = "种子", rarity = "普通" }
    local rarityColor = deps_.getUiRarityColor(currentPlant.rarity or "普通")
    local currentPlantName = tostring(currentPlant.name or "种子")
    local isSelected = stage == "selected"
    local isUnseal = stage == "unseal"

    local rollingCards, updateRollingCards, _ = BuildRollingCards(results, current, isSelected)

    -- 底部固定区域（高度恒定，避免UI跳动）
    local bottomSection = UI.Panel {
        height = 80,
        alignItems = "center",
        justifyContent = "center",
        marginTop = 10,
        children = {
            isSelected and UI.Label { text = currentPlantName, fontSize = 16, fontWeight = "bold", fontColor = rarityColor, marginBottom = 10 } or UI.Label { text = " ", fontSize = 16 },
            UI.Button {
                text = isSelected and "确认" or "跳过",
                width = isSelected and 120 or 68,
                height = isSelected and 42 or 32,
                fontSize = isSelected and 15 or 12,
                fontWeight = "bold",
                backgroundColor = isSelected and {60, 170, 130, 255} or {200, 200, 195, 255},
                fontColor = isSelected and {255, 255, 255, 255} or {80, 80, 75, 255},
                borderRadius = isSelected and 12 or 8,
                onClick = function()
                    deps_.suppressWorldTap()
                    deps_.skipOpening()
                end,
            },
        },
    }

    local overlay = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 115,
        backgroundColor = {0, 0, 0, 140},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "88%",
                paddingTop = 14,
                paddingBottom = 16,
                paddingLeft = 14,
                paddingRight = 14,
                backgroundColor = {255, 252, 242, 255},
                borderRadius = 18,
                borderWidth = 2,
                borderColor = {220, 200, 160, 255},
                children = {
                    -- 标题
                    UI.Label { text = "开启种子包", fontSize = 18, fontWeight = "bold", fontColor = {75, 55, 40, 255}, textAlign = "center", marginBottom = 12 },
                    -- 滚动区域（水平）
                    UI.Panel {
                        height = 180,
                        width = "100%",
                        overflow = "hidden",
                        backgroundColor = {250, 248, 238, 255},
                        borderRadius = 14,
                        borderWidth = 1,
                        borderColor = {225, 215, 190, 255},
                        children = {
                            -- 中间选中框
                            UI.Panel { position = "absolute", left = "50%", top = "50%", width = 100, height = 138, marginLeft = -50, marginTop = -69, borderRadius = 14, backgroundColor = isSelected and {255, 250, 225, 200} or {255, 255, 255, 80}, borderWidth = isSelected and 3 or 2, borderColor = isSelected and rarityColor or {235, 235, 228, 200} },
                            -- 左右渐隐遮罩
                            UI.Panel { position = "absolute", left = 0, top = 0, bottom = 0, width = 40, backgroundColor = {250, 248, 238, 230} },
                            UI.Panel { position = "absolute", right = 0, top = 0, bottom = 0, width = 40, backgroundColor = {250, 248, 238, 230} },
                            table.unpack(rollingCards),
                        },
                    },
                    -- 底部固定区域
                    bottomSection,
                },
            },
        },
    }

    overlay.rollTime_ = timer or 0
    overlay.rollStage_ = stage
    if isSelected then
        updateRollingCards(1.0)
    end
    overlay.Update = function(self, dt)
        if self.rollStage_ ~= "rolling" then return end
        self.rollTime_ = self.rollTime_ + dt
        local duration = 1.8
        local t = math.min(self.rollTime_ / duration, 1.0)
        -- cubic ease-out: 先快后慢自然减速
        local eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
        updateRollingCards(eased)
    end
    return overlay
end

-- ============================================================================
-- Modal 模式（带弹出动效，参考商店弹窗）
-- ============================================================================

-- ============================================================================
-- 合成种子包弹窗
-- ============================================================================

local synthesisModal_ = nil
local synthSelectedSource_ = nil  -- 选中的源包 ID
local synthQuantity_ = 1          -- 合成数量
local BuildSynthesisModalContent   -- 前向声明

--- 合成规则说明：3个同品级种子包 → 1个更高品级种子包
local SYNTHESIS_COST = 3

--- 获取可合成的源包列表（拥有的、且有升级目标的）
local function GetSynthesizablePacks()
    local result = {}
    local seedPackConfig = deps_.seedPackConfig
    local seedPacks = deps_.seedPacks
    local rarityOrder = deps_.rarityOrder

    for packId, cfg in pairs(seedPackConfig) do
        local targetId = deps_.getSynthesisTarget and deps_.getSynthesisTarget(packId) or nil
        if targetId ~= nil then
            table.insert(result, {
                packId = packId,
                cfg = cfg,
                targetId = targetId,
                targetCfg = seedPackConfig[targetId],
                owned = seedPacks[packId] or 0,
            })
        end
    end

    table.sort(result, function(a, b)
        local ra = rarityOrder[a.cfg.packRarity or "普通"] or 0
        local rb = rarityOrder[b.cfg.packRarity or "普通"] or 0
        return ra < rb
    end)
    return result
end

local function BuildSynthesisContent()
    local packs = GetSynthesizablePacks()

    -- 如果没有选中默认选第一个
    if synthSelectedSource_ == nil and #packs > 0 then
        synthSelectedSource_ = packs[1].packId
    end

    -- 源包选择标签（品质颜色区分）
    local packTabs = {}
    for _, item in ipairs(packs) do
        local isSelected = (item.packId == synthSelectedSource_)
        local rarityColor = deps_.getUiRarityColor(item.cfg.packRarity or "普通")
        -- 未选中时用浅色版本
        local unselectedBg = {
            math.floor(rarityColor[1] * 0.3 + 235 * 0.7),
            math.floor(rarityColor[2] * 0.3 + 232 * 0.7),
            math.floor(rarityColor[3] * 0.3 + 228 * 0.7),
            255
        }
        table.insert(packTabs, UI.Panel {
            paddingLeft = 14, paddingRight = 14, paddingTop = 10, paddingBottom = 10,
            marginRight = 10, marginBottom = 8,
            backgroundColor = isSelected and rarityColor or unselectedBg,
            borderRadius = 12,
            onClick = function()
                deps_.suppressWorldTap()
                synthSelectedSource_ = item.packId
                synthQuantity_ = 1
                BuildSynthesisModalContent()
            end,
            children = {
                UI.Label {
                    text = item.cfg.packName,
                    fontSize = 14, fontWeight = "bold",
                    fontColor = isSelected and {255, 255, 255, 255} or {60, 50, 40, 255},
                },
            },
        })
    end

    -- 选中包的合成详情
    local detailSection = UI.Panel { height = 0 }
    if synthSelectedSource_ ~= nil then
        local sourceInfo = nil
        for _, item in ipairs(packs) do
            if item.packId == synthSelectedSource_ then
                sourceInfo = item
                break
            end
        end

        if sourceInfo ~= nil then
            local owned = sourceInfo.owned
            local maxCraft = math.floor(owned / SYNTHESIS_COST)
            local canCraft = maxCraft >= 1
            synthQuantity_ = math.max(1, math.min(synthQuantity_, math.max(1, maxCraft)))

            local needed = SYNTHESIS_COST * synthQuantity_
            local isSatisfied = owned >= needed

            local sourceIcon = sourceInfo.cfg.packIcon or "image/seedpack_icon/seedpack_0.png"
            local targetIcon = sourceInfo.targetCfg and sourceInfo.targetCfg.packIcon or "image/seedpack_icon/seedpack_0.png"
            local targetName = sourceInfo.targetCfg and sourceInfo.targetCfg.packName or "高级种子包"
            local targetRarityColor = deps_.getUiRarityColor(sourceInfo.targetCfg and sourceInfo.targetCfg.packRarity or "罕见")

            detailSection = UI.Panel {
                marginTop = 16, paddingTop = 20, paddingBottom = 20, paddingLeft = 16, paddingRight = 16,
                backgroundColor = {250, 248, 240, 255},
                borderRadius = 16,
                alignItems = "center",
                children = {
                    -- 合成公式展示：源包x3 → 目标包x1
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", marginBottom = 20, gap = 16,
                        children = {
                            -- 源包
                            UI.Panel {
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 80, height = 96, backgroundImage = sourceIcon, backgroundFit = "contain" },
                                    UI.Label { text = "x" .. SYNTHESIS_COST, fontSize = 16, fontWeight = "bold", fontColor = {80, 65, 45, 255}, marginTop = 4 },
                                },
                            },
                            -- 箭头
                            UI.Label { text = "→", fontSize = 28, fontWeight = "bold", fontColor = {160, 145, 120, 255} },
                            -- 目标包
                            UI.Panel {
                                alignItems = "center",
                                children = {
                                    UI.Panel { width = 80, height = 96, backgroundImage = targetIcon, backgroundFit = "contain" },
                                    UI.Label { text = "x1", fontSize = 16, fontWeight = "bold", fontColor = targetRarityColor, marginTop = 4 },
                                },
                            },
                        },
                    },
                    -- 需求信息
                    UI.Label {
                        text = string.format("需要: %s x%d  (持有 %d)", sourceInfo.cfg.packName, needed, owned),
                        fontSize = 14,
                        fontColor = isSatisfied and {70, 130, 80, 255} or {180, 80, 60, 255},
                        marginBottom = 14,
                    },
                    -- 数量选择器
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 16, marginBottom = 18,
                        children = {
                            UI.Button {
                                text = "−", width = 42, height = 42, fontSize = 20, fontWeight = "bold",
                                borderRadius = 12,
                                backgroundColor = synthQuantity_ > 1 and {210, 200, 185, 255} or {230, 228, 222, 255},
                                fontColor = synthQuantity_ > 1 and {60, 50, 35, 255} or {170, 165, 155, 255},
                                disabled = synthQuantity_ <= 1,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    synthQuantity_ = math.max(1, synthQuantity_ - 1)
                                    BuildSynthesisModalContent()
                                end,
                            },
                            UI.Label {
                                text = tostring(synthQuantity_),
                                fontSize = 22, fontWeight = "bold", fontColor = {60, 48, 32, 255},
                            },
                            UI.Button {
                                text = "+", width = 42, height = 42, fontSize = 20, fontWeight = "bold",
                                borderRadius = 12,
                                backgroundColor = synthQuantity_ < maxCraft and {210, 200, 185, 255} or {230, 228, 222, 255},
                                fontColor = synthQuantity_ < maxCraft and {60, 50, 35, 255} or {170, 165, 155, 255},
                                disabled = synthQuantity_ >= maxCraft or maxCraft <= 0,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    synthQuantity_ = math.min(maxCraft, synthQuantity_ + 1)
                                    BuildSynthesisModalContent()
                                end,
                            },
                        },
                    },
                    -- 合成按钮
                    UI.Button {
                        text = isSatisfied and ("合成 " .. targetName .. " x" .. synthQuantity_) or "材料不足",
                        width = "85%", height = 46, fontSize = 15, fontWeight = "bold",
                        borderRadius = 14,
                        backgroundColor = isSatisfied and {105, 185, 110, 255} or {200, 195, 185, 255},
                        fontColor = isSatisfied and {255, 255, 255, 255} or {140, 130, 115, 255},
                        disabled = not isSatisfied,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if deps_.synthesizePack then
                                local totalSuccess = 0
                                for _ = 1, synthQuantity_ do
                                    local ok = deps_.synthesizePack(synthSelectedSource_)
                                    if ok then
                                        totalSuccess = totalSuccess + 1
                                    else
                                        break
                                    end
                                end
                                if totalSuccess > 0 then
                                    -- 浮动飘字（NanoVG渲染，在Modal之上）
                                    FloatingToast.Show(string.format("合成成功! 获得 %s x%d", targetName, totalSuccess))
                                    -- 刷新合成弹窗内容
                                    BuildSynthesisModalContent()
                                    -- 刷新种子包弹窗
                                    if packModal_ then SeedPackView.RebuildModalContent() end
                                end
                            end
                        end,
                    },
                },
            }
        end
    end

    return UI.Panel {
        padding = 14,
        children = {
            UI.Label { text = "选择要合成的种子包", fontSize = 16, fontWeight = "bold", fontColor = {60, 48, 35, 255}, marginBottom = 14 },
            UI.Panel {
                flexDirection = "row", flexWrap = "wrap",
                children = packTabs,
            },
            detailSection,
        },
    }
end

BuildSynthesisModalContent = function()
    if synthesisModal_ == nil then return end
    synthesisModal_:ClearContent()
    synthesisModal_:AddContent(BuildSynthesisContent())
end

--- 打开合成弹窗（同时隐藏种子包弹窗）
local function OpenSynthesisModal()
    synthSelectedSource_ = nil
    synthQuantity_ = 1

    -- 隐藏种子包弹窗
    if packModal_ then
        packModal_:Hide()
    end

    synthesisModal_ = UI.Modal {
        title = "合成种子包",
        size = "fullscreen",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {8, 14, 8, 14},
        onClose = function()
            synthesisModal_ = nil
            -- 恢复种子包弹窗
            if packModal_ then
                packModal_:Show()
            end
        end,
    }

    BuildSynthesisModalContent()
    ModalAnim.Apply(synthesisModal_)
    synthesisModal_:Open()
end

function SeedPackView.ShowBatchResultModal(title, results, openedCount)
    if results == nil then return end

    if packModal_ then
        packModal_:Close()
        packModal_ = nil
    end
    if batchResultModal_ ~= nil then
        batchResultModal_:Close()
        batchResultModal_ = nil
    end

    batchResultModal_ = UI.Modal {
        size = "fullscreen",
        closeOnOverlay = false,
        showCloseButton = false,
        contentPadding = {8, 14, 8, 14},
        onClose = function()
            batchResultModal_ = nil
            selectedPackId_ = nil
            if deps_.closePackPanel then deps_.closePackPanel() end
            if deps_.rebuildUI then deps_.rebuildUI() end
        end,
    }

    batchResultModal_:AddContent(UI.Panel {
        height = 560,
        paddingTop = 20,
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "拆包结算",
                width = "100%",
                fontSize = 19,
                fontWeight = "bold",
                fontColor = {75, 55, 40, 255},
                textAlign = "center",
                marginBottom = 18,
            },
            UI.ScrollView {
                height = 410,
                scrollY = true,
                showScrollbar = true,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "flex-start",
                        gap = 2,
                        paddingTop = 2,
                        paddingBottom = 4,
                        children = BuildCompactResultCards(results),
                    },
                },
            },
            UI.Panel {
                height = 58,
                justifyContent = "center",
                alignItems = "center",
                marginTop = 4,
                children = {
                    UI.Button {
                        text = "确认",
                        width = 120,
                        height = 42,
                        fontSize = 16,
                        fontWeight = "bold",
                        backgroundColor = {95, 165, 105, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 12,
                        onClick = function()
                            deps_.suppressWorldTap()
                            if batchResultModal_ ~= nil then
                                batchResultModal_:Close()
                            end
                        end,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(batchResultModal_, { fixedHeight = 610 })
    batchResultModal_:Open()
end

-- ============================================================================
-- Modal 模式（带弹出动效，参考商店弹窗）
-- ============================================================================

--- 打开种子包弹窗（Modal 模式，带动效）
function SeedPackView.OpenPackModal()
    selectedPackId_ = nil

    packModal_ = UI.Modal {
        title = "种子包",
        size = "fullscreen",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {6, 10, 6, 10},
        contentGap = 0,
        onClose = function()
            packModal_ = nil
            selectedPackId_ = nil
            deps_.closePackPanel()
            deps_.rebuildUI()
        end,
    }

    SeedPackView.RebuildModalContent()
    ModalAnim.Apply(packModal_)
    packModal_:Open()
end

--- 重建 Modal 内部内容
function SeedPackView.RebuildModalContent()
    if packModal_ == nil then return end
    packModal_:ClearContent()

    -- 合成入口按钮（放在种子包列表上方）
    packModal_:AddContent(UI.Panel {
        flexDirection = "row", justifyContent = "flex-end", paddingRight = 6, paddingTop = 4, marginBottom = 2,
        children = {
            UI.Button {
                text = "合成种子包",
                height = 32, fontSize = 12, fontWeight = "bold",
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = {165, 198, 160, 255},
                fontColor = {40, 65, 40, 255},
                borderRadius = 10,
                onClick = function()
                    deps_.suppressWorldTap()
                    OpenSynthesisModal()
                end,
            },
        },
    })

    packModal_:AddContent(UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 380,
        scrollY = true,
        showScrollbar = false,
        children = {
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "flex-start",
                paddingTop = 8,
                paddingBottom = 8,
                paddingLeft = 6,
                children = BuildPackCardGrid(),
            },
        },
    })
    packModal_:AddContent(BuildPackDetailSection())
end

--- 关闭种子包弹窗
function SeedPackView.ClosePackModal()
    if packModal_ ~= nil then
        packModal_:Close()
        packModal_ = nil
    end
    selectedPackId_ = nil
end

--- 获取 Modal 实例（供外部 Update 调用）
function SeedPackView.GetModal()
    return packModal_
end

return SeedPackView
