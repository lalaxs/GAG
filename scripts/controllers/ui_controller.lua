-- ============================================================================
-- UI 编排控制器
-- Grow A Garden
-- ============================================================================
-- 负责 UI 初始化、根 UI 重建、HUD 标签刷新和 Toast 计时。
-- 不修改任何 View 文件中的 UI 样式、布局和交互。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Format = require("utils.format")
local MainView = require("ui.main_view")
local PlantPanelView = require("ui.plant_panel_view")
local BagDetailView = require("ui.bag_detail_view")

local UIController = {}

local deps_ = {}
local labels_ = {}
local uiInitialized_ = false
local uiRefreshTimer_ = 0
local toastTimer_ = 0
local modalInputGuardInstalled_ = false

local function InstallModalInputGuard()
    if modalInputGuardInstalled_ then return end
    modalInputGuardInstalled_ = true

    local Modal = UI.Modal
    if Modal == nil or Modal.OnPointerDown == nil then return end
    local originalModalPointerDown = Modal.OnPointerDown
    local originalHandleGestureEvent = UI.HandleGestureEvent
    local originalHandlePointerUp = UI.HandlePointerUp
    local originalHandlePointerCancel = UI.HandlePointerCancel
    local GestureEvent = UI.GestureEvent
    local suppressTapByPointer = {}

    local function ShouldSuppressModalTap(modal, event)
        if modal == nil or event == nil or not modal.isOpen_ then return false end

        local cbl = modal.closeButtonLayout_
        if cbl ~= nil and event.x >= cbl.x and event.x <= cbl.x + cbl.w
            and event.y >= cbl.y and event.y <= cbl.y + cbl.h then
            return true
        end

        local ml = modal.modalLayout_
        if ml == nil then return false end
        local insideModal = event.x >= ml.x and event.x <= ml.x + ml.w
            and event.y >= ml.y and event.y <= ml.y + ml.h
        return not insideModal and modal.closeOnOverlay_ == true
    end

    function Modal:OnPointerDown(event)
        if ShouldSuppressModalTap(self, event) then
            suppressTapByPointer[event.pointerId or 0] = true
            if event.StopPropagation then event:StopPropagation() end
        end
        return originalModalPointerDown(self, event)
    end

    function UI.HandleGestureEvent(event)
        if event ~= nil and GestureEvent ~= nil then
            local pointerId = event.pointerId or 0
            local eventType = event.type
            if suppressTapByPointer[pointerId]
                and (eventType == GestureEvent.Types.Tap or eventType == GestureEvent.Types.DoubleTap) then
                suppressTapByPointer[pointerId] = nil
                if event.StopPropagation then event:StopPropagation() end
                return
            end
        end
        return originalHandleGestureEvent(event)
    end

    function UI.HandlePointerUp(event)
        if event ~= nil then
            suppressTapByPointer[event.pointerId or 0] = nil
        end
        return originalHandlePointerUp(event)
    end

    function UI.HandlePointerCancel(event)
        if event ~= nil then
            suppressTapByPointer[event.pointerId or 0] = nil
        end
        return originalHandlePointerCancel(event)
    end
end

local function EnsureUIInitialized()
    if uiInitialized_ then return end
    local ACNHTheme = require("ui.theme_acnh")
    UI.Init({
        theme = ACNHTheme.theme,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/ResourceHanRoundedCN-Bold.ttf",
                bold = "Fonts/ResourceHanRoundedCN-Bold.ttf",
            } },
        },
        scale = UI.Scale.DEFAULT,
    })
    InstallModalInputGuard()
    uiInitialized_ = true
end

local function BuildPlantTabContent()
    return PlantPanelView.BuildContent()
end

function UIController.Init(deps)
    deps_ = deps or {}
    labels_ = {}
    -- 保留 uiInitialized_：ShowLoading 可能已调用 UI.Init，此处仅注入 deps。
    uiRefreshTimer_ = 0
    toastTimer_ = 0
end

function UIController.GetLabel(name)
    return labels_[name]
end

function UIController.ShowToast(text)
    toastTimer_ = 2.0
    if labels_.toastLabel ~= nil then
        labels_.toastLabel:SetText(text)
    end
    print(text)
end

function UIController.Refresh(force)
    uiRefreshTimer_ = uiRefreshTimer_ + 0.016
    if not force and uiRefreshTimer_ < 0.1 then return end
    uiRefreshTimer_ = 0

    local selectedSeed = deps_.getSelectedSeed()
    local plants = deps_.plants
    local seedBag = deps_.seedBag
    local plots = deps_.getPlots()
    local selectedPlot = plots[deps_.getSelectedPlotIndex()]
    local _seed = plants[selectedSeed]
    local _owned = seedBag[selectedSeed] or 0
    local _actionText = ""
    if deps_.isFarmView() then
        _actionText = "点击田地查看状态，点击下方按钮开始种植"
    elseif selectedPlot ~= nil and deps_.countMaturePlants(selectedPlot) > 0 then
        _actionText = "点击成熟作物收获，点击空位继续播种"
    elseif selectedPlot ~= nil and deps_.countPlotPlants(selectedPlot) < deps_.config.MaxCropsPerPlot then
        _actionText = "点击空位播种，种子会完全落在点击位置"
    else
        _actionText = "田地已满，等待成熟后收获"
    end

    if labels_.moneyLabel ~= nil then
        labels_.moneyLabel:SetText(Format.Gold(deps_.getMoney()))
    end
    if labels_.seedLabel ~= nil then
        labels_.seedLabel:SetText(Format.Gold(deps_.getTourValue()))
    end
    if labels_.plotLabel ~= nil then
        labels_.plotLabel:SetText("LV" .. deps_.getTalentLevel())
    end
    if labels_.talentBadge ~= nil then
        local hasUnlockableTalent = deps_.hasUnlockableTalent ~= nil and deps_.hasUnlockableTalent()
        labels_.talentBadge:SetVisible(hasUnlockableTalent == true)
    end

    if labels_.helpLabel ~= nil then
        labels_.helpLabel:SetText(string.format("已解锁区域 %d/%d", deps_.getUnlockedPlotCount(), #plots))
    end
    if labels_.actionButton ~= nil then
        if deps_.isVisitMode and deps_.isVisitMode() then
            labels_.actionButton:SetText("返回我的花园")
        elseif deps_.isFarmView() then
            labels_.actionButton:SetText("开始种植")
        else
            labels_.actionButton:SetText("返回花园")
        end
    end
    if labels_.seedPackBadgeLabel ~= nil then
        labels_.seedPackBadgeLabel:SetText(tostring(deps_.countSeedPacks()))
    end
end

function UIController.RefreshPlantContent()
    local host = UI.FindById("plantContentHost")
    if host == nil then return false end
    host:ClearChildren()
    host:AddChild(BuildPlantTabContent())
    UIController.Refresh(true)
    return true
end

function UIController.RefreshBagDetail()
    local host = UI.FindById("bagDetailHost")
    if host == nil then return false end
    host:ClearChildren()
    host:AddChild(BagDetailView.Build(deps_.getSelectedBagItem(), deps_.isPlantView()))
    return true
end

function UIController.RefreshInventoryPanels()
    local plantOk = UIController.RefreshPlantContent()
    local bagOk = UIController.RefreshBagDetail()
    return plantOk or bagOk
end

function UIController.ShowLoading(text)
    EnsureUIInitialized()
    labels_ = {}
    local loadingText = text or "正在同步花园数据..."
    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {232, 242, 226, 255},
        children = {
            UI.Panel {
                width = 270,
                paddingTop = 28,
                paddingBottom = 28,
                paddingLeft = 24,
                paddingRight = 24,
                borderRadius = 24,
                backgroundColor = {255, 252, 240, 248},
                borderWidth = 3,
                borderColor = {224, 190, 122, 235},
                alignItems = "center",
                boxShadow = { { x = 0, y = 8, blur = 20, spread = 0, color = {65, 46, 28, 60} } },
                children = {
                    UI.Label {
                        text = "加载中",
                        fontSize = 30,
                        fontWeight = "bold",
                        fontColor = {86, 57, 31, 255},
                        textAlign = "center",
                        marginBottom = 12,
                    },
                    UI.Label {
                        text = loadingText,
                        fontSize = 16,
                        fontColor = {116, 92, 58, 235},
                        textAlign = "center",
                    },
                    UI.Panel {
                        width = 96,
                        height = 8,
                        marginTop = 20,
                        borderRadius = 4,
                        backgroundColor = {118, 181, 98, 235},
                    },
                },
            },
        },
    })
end

function UIController.Rebuild()
    local previewItem = deps_.getSelectedBagItem()

    EnsureUIInitialized()

    local labels = MainView.CreateLabels()
    labels_ = labels

    local root = MainView.BuildRoot(labels, {
        plantContent = BuildPlantTabContent(),
        bagDetail = BagDetailView.Build(deps_.getSelectedBagItem(), deps_.isPlantView()),
        seedPackOverlay = deps_.buildSeedPackOverlay(),
        seedPackOpeningOverlay = deps_.buildSeedPackOpeningOverlay(),
    })
    UI.SetRoot(root)
    if previewItem ~= nil and deps_.createBagPreview ~= nil then
        deps_.createBagPreview(previewItem)
    end
    UIController.Refresh(true)
end

function UIController.Update(dt)
    if toastTimer_ > 0 then
        toastTimer_ = toastTimer_ - dt
        if toastTimer_ <= 0 and labels_.toastLabel ~= nil then
            labels_.toastLabel:SetText("")
        end
    end
end

return UIController
