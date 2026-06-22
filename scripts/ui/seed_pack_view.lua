-- ============================================================================
-- 种子礼包 UI 视图 (Seed Pack View)
-- Grow A Garden
-- ============================================================================
-- 只负责种子礼包相关 UI 构建，不持有游戏业务状态。
-- ============================================================================

local UI = require("urhox-libs/UI")

local SeedPackView = {}

local deps_ = {}
local selectedPackId_ = nil
local packModal_ = nil

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
                    backgroundImage = string.format("image/icons_3d/seed (%d).png", seedId),
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
        local ra = deps_.rarityOrder[a.cfg.packRarity or "普通"] or 0
        local rb = deps_.rarityOrder[b.cfg.packRarity or "普通"] or 0
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
                    backgroundImage = string.format("image/plants/plants (%d).png", seedId),
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
                    UI.Button {
                        text = "打开",
                        width = 80,
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
        seedBuff = baseResult ~= nil and baseResult.seedBuff or 0,
        isNew = false,
    }
end

local function BuildRollingCards(results, targetResult, isSelected)
    local cardW = 105
    local plantCount = #deps_.plants
    local halfCard = 47  -- 94/2

    -- 预生成种子序列：12个随机 + 目标在最后
    local stripCount = 13
    local strip = {}
    for i = 1, stripCount - 1 do
        local seedId = ((i * 7 + 3) % plantCount) + 1
        strip[i] = seedId
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
        local plant = deps_.plants[seedId]
        local rarityColor = deps_.getUiRarityColor(plant.rarity)
        local scaleH = selected and 130 or 112
        slot.panel:SetStyle({
            marginLeft = -halfCard + x,
            height = scaleH,
            marginTop = -scaleH / 2,
        })
        slot.icon:SetBackgroundImage(string.format("image/icons_3d/seed (%d).png", seedId))
        slot.icon:SetStyle({ width = selected and 76 or 66, height = selected and 76 or 66 })
        slot.name:SetText(plant.name)
        slot.name:SetStyle({ fontColor = rarityColor, fontSize = selected and 14 or 12 })
    end

    for slotIndex = 1, visibleCount do
        local seedId = isSelected and (slotIndex == 3 and targetResult.seedId or getStripSeed(stripCount - 3 + slotIndex)) or getStripSeed(slotIndex)
        local plant = deps_.plants[seedId]
        local rarityColor = deps_.getUiRarityColor(plant.rarity)
        local selected = isSelected and slotIndex == 3
        local scaleH = selected and 130 or 112
        local icon = UI.Panel { width = selected and 76 or 66, height = selected and 76 or 66, backgroundImage = string.format("image/icons_3d/seed (%d).png", seedId), backgroundFit = "contain" }
        local nameLabel = UI.Label { text = plant.name, fontSize = selected and 14 or 12, fontWeight = "bold", fontColor = rarityColor, textAlign = "center" }
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
    local currentPlant = deps_.plants[current.seedId]
    local rarityColor = deps_.getUiRarityColor(currentPlant.rarity)
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
            isSelected and UI.Label { text = currentPlant.name, fontSize = 16, fontWeight = "bold", fontColor = rarityColor, marginBottom = 10 } or UI.Label { text = " ", fontSize = 16 },
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
    packModal_:Open()
end

--- 重建 Modal 内部内容
function SeedPackView.RebuildModalContent()
    if packModal_ == nil then return end
    packModal_:ClearContent()
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
