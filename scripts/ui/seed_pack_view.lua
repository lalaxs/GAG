-- ============================================================================
-- 种子礼包 UI 视图 (Seed Pack View)
-- Grow A Garden
-- ============================================================================
-- 只负责种子礼包相关 UI 构建，不持有游戏业务状态。
-- ============================================================================

local UI = require("urhox-libs/UI")

local SeedPackView = {}

local deps_ = {}

function SeedPackView.Init(deps)
    deps_ = deps or {}
end

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

local function BuildSeedPackRows()
    local rows = {}
    local seedPacks = deps_.seedPacks
    for packId, cfg in pairs(deps_.seedPackConfig) do
        local owned = seedPacks[packId] or 0
        if owned > 0 then
            table.insert(rows, UI.Panel {
                flexDirection = "column",
                alignItems = "stretch",
                padding = 8,
                marginBottom = 8,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 14,
                borderWidth = 2,
                borderColor = cfg.themeColor,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Panel {
                                width = 42,
                                height = 42,
                                marginRight = 8,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = cfg.themeColor,
                                borderRadius = 12,
                                children = { UI.Label { text = cfg.seedBuff > 0 and "银" or "袋", fontSize = 18, fontWeight = "bold", fontColor = {255, 255, 255, 255} } },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                gap = 2,
                                children = {
                                    UI.Label { text = cfg.packName .. " x" .. owned, fontSize = 14, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                                    UI.Label { text = cfg.getWay .. " | 每包 " .. cfg.onceOpenCount .. " 颗种子", fontSize = 10, fontColor = {120, 100, 80, 220} },
                                },
                            },
                        },
                    },
                    cfg.seedBuff > 0 and UI.Label { text = "银质种子：播种时体型/颜色/特殊变异概率 +1%", fontSize = 10, fontColor = {90, 100, 130, 240}, marginBottom = 6 } or UI.Panel { height = 0 },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button { text = "开1包", flexGrow = 1, height = 32, fontSize = 12, variant = "primary", onClick = function() deps_.suppressWorldTap(); deps_.openSeedPack(packId, 1) end },
                            UI.Button { text = "全开", flexGrow = 1, height = 32, fontSize = 12, variant = "secondary", onClick = function() deps_.suppressWorldTap(); deps_.openSeedPack(packId, owned) end },
                        },
                    },
                },
            })
        end
    end
    if #rows == 0 then
        table.insert(rows, UI.Label { text = "暂无可开启的种子包", fontSize = 14, fontColor = {120, 100, 80, 220}, textAlign = "center" })
    end
    return rows
end

function SeedPackView.BuildPackOverlay(isOpen)
    if not isOpen then
        return UI.Panel { width = 0, height = 0 }
    end
    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        zIndex = 100,
        backgroundColor = {0, 0, 0, 120},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "100%",
                marginLeft = 18,
                marginRight = 18,
                maxHeight = 430,
                paddingTop = 10,
                paddingBottom = 12,
                paddingLeft = 10,
                paddingRight = 10,
                backgroundColor = {255, 253, 245, 255},
                borderRadius = 18,
                borderWidth = 3,
                borderColor = {195, 180, 150, 230},
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Label { text = "种子礼包", fontSize = 17, fontWeight = "bold", fontColor = {75, 55, 40, 255} },
                            UI.Button {
                                text = "×",
                                width = 34,
                                height = 30,
                                fontSize = 18,
                                fontWeight = "bold",
                                backgroundColor = {255, 250, 240, 0},
                                fontColor = {120, 90, 70, 255},
                                borderRadius = 12,
                                onClick = function()
                                    deps_.suppressWorldTap()
                                    deps_.closePackPanel()
                                    deps_.rebuildUI()
                                end,
                            },
                        },
                    },
                    UI.ScrollView {
                        height = 350,
                        scrollY = true,
                        showScrollbar = true,
                        children = BuildSeedPackRows(),
                    },
                },
            },
        },
    }
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

return SeedPackView
