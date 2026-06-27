-- ============================================================================
-- 种子包开启动画控制器
-- Grow A Garden
-- ============================================================================
-- 只管理开包流程状态，不改变 SeedPackView 的 UI 构建与交互表现。
-- ============================================================================

local SeedPackSystem = require("systems.seed_pack_system")
local SeedPackView = require("ui.seed_pack_view")

local SeedPackOpeningController = {}

local deps_ = {}
local panelOpen_ = false
local opening_ = nil
local openingTimer_ = 0
local openingStage_ = "closed"
local revealIndex_ = 0
local pendingOpenAll_ = false

local function RebuildUI()
    if deps_.rebuildUI ~= nil then
        deps_.rebuildUI()
    end
end

local function RefreshUI(force)
    if deps_.refreshUI ~= nil then
        deps_.refreshUI(force)
    end
end

local function ShowToast(text)
    if deps_.showToast ~= nil then
        deps_.showToast(text)
    end
end

local function GetHighestResultRarity(results)
    local highest = "common"
    local highestOrder = 1
    local rarityOrder = deps_.rarityOrder or {}
    local plants = deps_.plants or {}
    for _, result in ipairs(results or {}) do
        local plant = plants[result.seedId]
        local rarity = plant and plant.rarity or "普通"
        local order = rarityOrder[rarity] or 1
        if order > highestOrder then
            highestOrder = order
            highest = rarity == "传奇" and "legendary" or rarity == "史诗" and "epic" or rarity == "稀有" and "rare" or "common"
        end
    end
    return highest
end

function SeedPackOpeningController.Init(deps)
    deps_ = deps or {}
    panelOpen_ = false
    opening_ = nil
    openingTimer_ = 0
    openingStage_ = "closed"
    revealIndex_ = 0
    pendingOpenAll_ = false
end

function SeedPackOpeningController.ClosePanel()
    panelOpen_ = false
end

function SeedPackOpeningController.StartOpening(title, results, serverAuthoritative)
    panelOpen_ = false
    opening_ = { title = title, results = results, serverAuthoritative = serverAuthoritative == true }
    openingStage_ = "unseal"
    openingTimer_ = 0
    revealIndex_ = 1
    RebuildUI()
end

function SeedPackOpeningController.FinishOpening()
    if opening_ == nil then return end
    local opening = opening_
    if opening.serverAuthoritative ~= true then
        SeedPackSystem.ConfirmResults(opening.results)
    end
    opening_ = nil
    openingStage_ = "closed"
    openingTimer_ = 0
    revealIndex_ = 0
    panelOpen_ = true
    RebuildUI()
    SeedPackView.OpenPackModal()
end

function SeedPackOpeningController.SkipOpening()
    SeedPackOpeningController.FinishOpening()
end

function SeedPackOpeningController.OpenPack(packId)
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.OpenSeedPack ~= nil then
        if deps_.EconomyCloudSystem.OpenSeedPack(packId, 1, false) then
            ShowToast("正在请求服务器开启种子包...")
            return
        end
    end
    local results, err, title = SeedPackSystem.PreviewPack(packId, 1)
    if results == nil then
        if err ~= nil then ShowToast(err) end
        return
    end
    SeedPackView.ClosePackModal()
    SeedPackOpeningController.StartOpening(title, results)
    RefreshUI(true)
end

function SeedPackOpeningController.OpenAllPacks(packId)
    if deps_.EconomyCloudSystem ~= nil and deps_.EconomyCloudSystem.OpenSeedPack ~= nil then
        if deps_.EconomyCloudSystem.OpenSeedPack(packId, 1, true) then
            ShowToast("正在请求服务器批量开启种子包...")
            return
        end
    end
    local results, err, title, openedCount = SeedPackSystem.OpenAllPacks(packId)
    if results == nil then
        if err ~= nil then ShowToast(err) end
        return
    end
    local rarity = GetHighestResultRarity(results)
    SeedPackView.ShowBatchResultModal(title, results, openedCount)
    RefreshUI(true)
end

function SeedPackOpeningController.ApplyServerOpenResult(data)
    if data == nil or data.results == nil then return false end
    SeedPackView.ClosePackModal()
    if data.openAll == true or (tonumber(data.openedCount or 1) or 1) > 1 then
        SeedPackView.ShowBatchResultModal(data.title or "种子包", data.results, data.openedCount or 1)
    else
        SeedPackOpeningController.StartOpening(data.title or "种子包", data.results, true)
    end
    RefreshUI(true)
    return true
end

function SeedPackOpeningController.OpenHub()
    if deps_.countSeedPacks == nil or deps_.countSeedPacks() <= 0 then
        ShowToast("暂无可开启的种子包")
        return
    end
    panelOpen_ = true
    SeedPackView.OpenPackModal()
end

function SeedPackOpeningController.BuildPackOverlay()
    return SeedPackView.BuildPackOverlay(panelOpen_)
end

function SeedPackOpeningController.BuildOpeningOverlay()
    return SeedPackView.BuildOpeningOverlay(opening_, openingStage_, revealIndex_, openingTimer_)
end

function SeedPackOpeningController.Update(dt)
    if opening_ == nil then return end
    openingTimer_ = openingTimer_ + dt

    if openingStage_ == "unseal" and openingTimer_ >= 0.3 then
        openingStage_ = "rolling"
        openingTimer_ = 0
        RebuildUI()
    elseif openingStage_ == "rolling" and openingTimer_ >= 1.8 then
        openingStage_ = "selected"
        openingTimer_ = 0
        RebuildUI()
    elseif openingStage_ == "selected" then
        -- 停在 selected 等用户点确认
    end
end

return SeedPackOpeningController
