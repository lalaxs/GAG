-- ============================================================================
-- 客户端主循环
-- Grow A Garden
-- ============================================================================

local GameLoop = {}

local deps_ = {}

function GameLoop.Init(deps)
    deps_ = deps or {}
end

function GameLoop.HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    deps_.updateNetworkClient(dt)
    deps_.updateNetworkRecovery(dt)

    if not deps_.isInitialUiReady() then
        deps_.PlayerSystem.Update(dt)
        deps_.EconomyCloudSystem.Update(dt)
        deps_.AdRewardSystem.Update(dt)
        deps_.SocialGardenSystem.Update(dt)
        deps_.LeaderboardSystem.Update(dt)
        if deps_.EconomyCloudSystem.IsInitialAuthorityDegraded ~= nil and deps_.EconomyCloudSystem.IsInitialAuthorityDegraded() then
            local errorText = "服务器数据同步失败，暂时无法进入游戏。请检查网络后重试。"
            if deps_.EconomyCloudSystem.GetInitialSyncErrorText ~= nil then
                errorText = deps_.EconomyCloudSystem.GetInitialSyncErrorText() or errorText
            end
            if deps_.UIController.ShowLoadingError ~= nil then
                deps_.UIController.ShowLoadingError("同步失败", errorText)
            else
                deps_.UIController.ShowLoading(errorText)
            end
        elseif deps_.NetworkRecovery.UpdateLoading(dt) then
            if deps_.PlayerSystem.TryApplyConnectionIdentity ~= nil then
                deps_.PlayerSystem.TryApplyConnectionIdentity()
            end
            if deps_.EconomyCloudSystem.IsInitialSyncReady ~= nil and deps_.EconomyCloudSystem.IsInitialSyncReady() then
                if deps_.PlayerSystem.RetryFetchTapProfile ~= nil then
                    deps_.PlayerSystem.RetryFetchTapProfile()
                end
                if deps_.SocialGardenSystem.HasSocialStateSynced ~= nil and not deps_.SocialGardenSystem.HasSocialStateSynced() then
                    deps_.UIController.ShowLoading("正在同步社交数据...")
                    if deps_.SocialGardenSystem.RequestSocialState ~= nil then
                        deps_.SocialGardenSystem.RequestSocialState({ force = true, reason = "loading_timeout" })
                    end
                end
            else
                local loadingMessage = "服务器响应较慢，正在重试同步..."
                if deps_.NetworkRecovery.GetLoadingMessage ~= nil then
                    loadingMessage = deps_.NetworkRecovery.GetLoadingMessage()
                end
                deps_.UIController.ShowLoading(loadingMessage)
                if deps_.NetworkRecovery.HasRawServerConnection == nil or deps_.NetworkRecovery.HasRawServerConnection() then
                    deps_.requestNetworkRecoverySync("loading_timeout")
                end
            end
        end
        deps_.ensureInitialUiReady()
        deps_.FloatingToast.Update(dt)
        deps_.UIController.Update(dt)
        deps_.AudioSystem.Update(dt)
        return
    end

    if not deps_.ModelPreviewSystem.IsOpen() then
        deps_.handleInput(dt)
        deps_.updateTouchCameraGesture()
    end
    deps_.updatePlotBounceAnimation(dt)
    deps_.updatePlants(dt)
    deps_.updateSeedPackOpening(dt)
    deps_.ModelPreviewSystem.Update(dt)
    deps_.Shop.Update(dt)
    deps_.PlayerSystem.Update(dt)
    deps_.EconomyCloudSystem.Update(dt)
    deps_.AdRewardSystem.Update(dt)
    deps_.SocialGardenSystem.Update(dt)
    deps_.LeaderboardSystem.Update(dt)
    deps_.CommissionSystem.Update(dt)
    deps_.FloatingToast.Update(dt)
    deps_.UIController.Update(dt)
    deps_.flushPendingRebuildUI(dt)
    deps_.AudioSystem.Update(dt)
    deps_.refreshUI(false)
end

return GameLoop
