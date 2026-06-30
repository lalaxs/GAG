-- ============================================================================
-- UI 事件绑定与 Modal Guard 注册
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有 UI 事件订阅、取消订阅和 Modal Guard 注册逻辑。
-- 不改变事件响应顺序、刷新时机和弹窗判断。
-- ============================================================================

local UiEventBindings = {}

local deps_ = {}
local unsubscribeSocialChanged_ = nil
local unsubscribeSeedPackChanged_ = nil
local unsubscribeCommissionChanged_ = nil
local unsubscribeActivityChanged_ = nil
local unsubscribeTaskChanged_ = nil
local unsubscribeTalentChanged_ = nil
local unsubscribeWalletChanged_ = nil
local unsubscribeInventoryChanged_ = nil
local unsubscribeFarmChanged_ = nil
local unsubscribePlayerChanged_ = nil

function UiEventBindings.Init(deps)
    deps_ = deps or {}
end

local function RefreshUI(force)
    if deps_.refreshUI ~= nil then deps_.refreshUI(force) end
end

local function RebuildUI()
    if deps_.rebuildUI ~= nil then deps_.rebuildUI() end
end

function UiEventBindings.Subscribe()
    if unsubscribeSocialChanged_ == nil then
        unsubscribeSocialChanged_ = deps_.EventBus.On(deps_.UIEvents.SOCIAL_CHANGED, function()
            if not deps_.SocialView.IsOpen() and deps_.rebuildUI ~= nil then
                RebuildUI()
            end
        end)
    end
    if unsubscribeSeedPackChanged_ == nil then
        unsubscribeSeedPackChanged_ = deps_.EventBus.On(deps_.UIEvents.SEEDPACK_CHANGED, function()
            if deps_.SeedPackView.IsOpen() then
                deps_.SeedPackView.RebuildModalContent()
            end
            deps_.UIController.RefreshInventoryPanels()
            RefreshUI(true)
        end)
    end
    if unsubscribeCommissionChanged_ == nil then
        unsubscribeCommissionChanged_ = deps_.EventBus.On(deps_.UIEvents.COMMISSION_CHANGED, function()
            if deps_.CommissionView.IsOpen() then
                deps_.CommissionView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeActivityChanged_ == nil then
        unsubscribeActivityChanged_ = deps_.EventBus.On(deps_.UIEvents.ACTIVITY_CHANGED, function()
            if deps_.ActivityView.IsOpen() then
                deps_.ActivityView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeTaskChanged_ == nil then
        unsubscribeTaskChanged_ = deps_.EventBus.On(deps_.UIEvents.TASK_CHANGED, function()
            if deps_.TaskView.IsOpen() then
                deps_.TaskView.RefreshContent()
            else
                RefreshUI(true)
            end
        end)
    end
    if unsubscribeTalentChanged_ == nil then
        unsubscribeTalentChanged_ = deps_.EventBus.On(deps_.UIEvents.TALENT_CHANGED, function(payload)
            if deps_.TalentView.IsOpen() then
                local successText = payload ~= nil and payload.successText or nil
                deps_.TalentView.RefreshContent(successText)
            end
            RefreshUI(true)
        end)
    end
    if unsubscribeWalletChanged_ == nil then
        unsubscribeWalletChanged_ = deps_.EventBus.On(deps_.UIEvents.WALLET_CHANGED, function()
            RefreshUI(true)
        end)
    end
    if unsubscribeInventoryChanged_ == nil then
        unsubscribeInventoryChanged_ = deps_.EventBus.On(deps_.UIEvents.INVENTORY_CHANGED, function()
            if not deps_.UIController.RefreshInventoryPanels() and deps_.rebuildUI ~= nil then
                RebuildUI()
            end
            RefreshUI(true)
        end)
    end
    if unsubscribeFarmChanged_ == nil then
        unsubscribeFarmChanged_ = deps_.EventBus.On(deps_.UIEvents.FARM_CHANGED, function()
            if not deps_.UIController.RefreshPlantContent() and deps_.rebuildUI ~= nil then
                RebuildUI()
            end
            RefreshUI(true)
        end)
    end
    if unsubscribePlayerChanged_ == nil then
        unsubscribePlayerChanged_ = deps_.EventBus.On(deps_.UIEvents.PLAYER_CHANGED, function()
            if deps_.ProfileView.IsOpen() then
                deps_.ProfileView.RebuildProfileContent()
            end
            if deps_.rebuildUI ~= nil then
                RebuildUI()
            else
                RefreshUI(true)
            end
        end)
    end
end

function UiEventBindings.Unsubscribe()
    if unsubscribeSocialChanged_ ~= nil then
        unsubscribeSocialChanged_()
        unsubscribeSocialChanged_ = nil
    end
    if unsubscribeSeedPackChanged_ ~= nil then
        unsubscribeSeedPackChanged_()
        unsubscribeSeedPackChanged_ = nil
    end
    if unsubscribeCommissionChanged_ ~= nil then
        unsubscribeCommissionChanged_()
        unsubscribeCommissionChanged_ = nil
    end
    if unsubscribeActivityChanged_ ~= nil then
        unsubscribeActivityChanged_()
        unsubscribeActivityChanged_ = nil
    end
    if unsubscribeTaskChanged_ ~= nil then
        unsubscribeTaskChanged_()
        unsubscribeTaskChanged_ = nil
    end
    if unsubscribeTalentChanged_ ~= nil then
        unsubscribeTalentChanged_()
        unsubscribeTalentChanged_ = nil
    end
    if unsubscribeWalletChanged_ ~= nil then
        unsubscribeWalletChanged_()
        unsubscribeWalletChanged_ = nil
    end
    if unsubscribeInventoryChanged_ ~= nil then
        unsubscribeInventoryChanged_()
        unsubscribeInventoryChanged_ = nil
    end
    if unsubscribeFarmChanged_ ~= nil then
        unsubscribeFarmChanged_()
        unsubscribeFarmChanged_ = nil
    end
    if unsubscribePlayerChanged_ ~= nil then
        unsubscribePlayerChanged_()
        unsubscribePlayerChanged_ = nil
    end
end

function UiEventBindings.RegisterModalGuards()
    deps_.ModalRegistry.Register("social", function() return deps_.SocialView.IsOpen() end)
    deps_.ModalRegistry.Register("leaderboard", function() return deps_.LeaderboardView.IsOpen() end)
    deps_.ModalRegistry.Register("seedPack", function() return deps_.SeedPackView.IsOpen() end)
    deps_.ModalRegistry.Register("task", function() return deps_.TaskView.IsOpen() end)
    deps_.ModalRegistry.Register("modelPreview", function() return deps_.ModelPreviewSystem.IsOpen() end)
    deps_.ModalRegistry.Register("activity", function() return deps_.ActivityView.IsOpen() end)
    deps_.ModalRegistry.Register("profile", function() return deps_.ProfileView.IsOpen() end)
    deps_.ModalRegistry.Register("settings", function() return deps_.SettingsView.IsOpen() end)
    deps_.ModalRegistry.Register("shop", function() return deps_.Shop.IsOpen() end)
    deps_.ModalRegistry.Register("commission", function() return deps_.CommissionView.IsOpen() end)
    deps_.ModalRegistry.Register("expansion", function() return deps_.ExpansionView.IsOpen() end)
    deps_.ModalRegistry.Register("talent", function() return deps_.TalentView.IsOpen() end)
    deps_.ModalRegistry.Register("bulkSell", function() return deps_.BulkSellView.IsOpen() end)
    deps_.ModalRegistry.Register("codex", function() return deps_.CodexView.IsOpen() end)
end

return UiEventBindings
