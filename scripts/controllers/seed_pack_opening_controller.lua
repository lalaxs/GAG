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

function SeedPackOpeningController.Init(deps)
    deps_ = deps or {}
    panelOpen_ = false
    opening_ = nil
    openingTimer_ = 0
    openingStage_ = "closed"
    revealIndex_ = 0
end

function SeedPackOpeningController.ClosePanel()
    panelOpen_ = false
end

function SeedPackOpeningController.StartOpening(title, results)
    panelOpen_ = false
    opening_ = { title = title, results = results }
    openingStage_ = "unseal"
    openingTimer_ = 0
    revealIndex_ = 1
    RebuildUI()
end

function SeedPackOpeningController.FinishOpening()
    if opening_ == nil then return end
    local opening = opening_
    SeedPackSystem.ConfirmResults(opening.results)
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
    local results, err, title, openedCount = SeedPackSystem.OpenAllPacks(packId)
    if results == nil then
        if err ~= nil then ShowToast(err) end
        return
    end
    SeedPackView.ShowBatchResultModal(title, results, openedCount)
    RefreshUI(true)
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
