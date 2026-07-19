-- ============================================================================
-- 广告奖励动作入口
-- Grow A Garden
-- ============================================================================
-- 只承接 main.lua 原有广告奖励入口逻辑，不改变限制判断、请求参数和提示文案。
-- ============================================================================

local AdRewardActions = {}

local deps_ = {}

function AdRewardActions.Init(deps)
    deps_ = deps or {}
end

local function ShowToast(text, silent)
    if deps_.showToast ~= nil then
        deps_.showToast(text, silent)
    end
end

local function GetSelectedPlotIndex()
    if deps_.getSelectedPlotIndex ~= nil then return deps_.getSelectedPlotIndex() end
    return 1
end

local function GetSelectedPlot()
    if deps_.getSelectedPlot ~= nil then return deps_.getSelectedPlot() end
    local plots = deps_.getPlots ~= nil and deps_.getPlots() or {}
    return plots[GetSelectedPlotIndex()]
end

local function CanStartAdReward()
    if deps_.EconomyCloudSystem.HasPendingAdReward ~= nil
        and deps_.EconomyCloudSystem.HasPendingAdReward() then
        ShowToast("上一笔广告奖励仍在确认中，请稍后")
        return false
    end
    return true
end

function AdRewardActions.ShowPrompt(title, message, rewardType, extra)
    if not CanStartAdReward() then return false end
    return deps_.AdRewardSystem.ConfirmAndShow({
        title = title,
        message = message,
        onSuccess = function()
            if deps_.EconomyCloudSystem.RequestAdReward(rewardType, extra or {}) then
                ShowToast("广告观看完成，正在发放奖励...")
            end
        end,
    })
end

function AdRewardActions.RequestStealAttempts()
    if not CanStartAdReward() then return false end
    return deps_.AdRewardSystem.Show({
        onSuccess = function()
            if deps_.EconomyCloudSystem.RequestAdReward("steal_attempts", {}) then
                ShowToast("广告观看完成，正在发放奖励...")
            end
        end,
    })
end

function AdRewardActions.RequestRareSeedPack()
    return AdRewardActions.ShowPrompt("领取稀有种子包", "观看广告后，获得稀有种子包 x5。", "rare_seed_pack")
end

function AdRewardActions.RequestMaturePlot()
    local socialState = deps_.SocialGardenSystem.GetState and deps_.SocialGardenSystem.GetState() or {}
    local daily = socialState.daily or {}
    local matureAdCount = math.max(0, math.floor(tonumber(daily.matureAdCount or 0) or 0))
    local matureAdLimit = math.max(5, math.floor(tonumber(daily.matureAdLimit or 5) or 5))
    if matureAdCount >= matureAdLimit then
        ShowToast("今日快速成熟广告已达上限")
        return false
    end
    local plot = GetSelectedPlot()
    if plot == nil or plot.plants == nil or #plot.plants == 0 then
        ShowToast("当前地块没有作物")
        return false
    end
    local hasImmature = false
    for _, crop in ipairs(plot.plants) do
        if crop.mature ~= true and crop.harvested ~= true then
            hasImmature = true
            break
        end
    end
    if not hasImmature then
        ShowToast("该地块作物已经成熟")
        return false
    end
    return AdRewardActions.ShowPrompt("全部成熟", "观看广告后，当前地块作物将全部成熟。", "mature_plot", { plotIndex = GetSelectedPlotIndex() })
end

return AdRewardActions
