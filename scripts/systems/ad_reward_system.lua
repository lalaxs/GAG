-- ============================================================================
-- 激励广告播放封装
-- ============================================================================
-- 只负责展示确认弹窗、调用 sdk:ShowRewardVideoAd，并在完整观看后触发奖励回调。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")

local AdRewardSystem = {}

local deps_ = {}
local pending_ = false
local confirmModal_ = nil

local function ShowToast(text)
    if deps_.showToast ~= nil then deps_.showToast(text) end
end

local function CloseConfirmModal()
    if confirmModal_ ~= nil then
        confirmModal_:Close()
        confirmModal_ = nil
    end
end

function AdRewardSystem.Init(deps)
    deps_ = deps or {}
    pending_ = false
    confirmModal_ = nil
end

function AdRewardSystem.IsPending()
    return pending_ == true
end

function AdRewardSystem.Show(options)
    options = options or {}
    if pending_ then
        ShowToast("广告正在播放，请稍后")
        return false
    end
    local sdkApi = rawget(_G, "sdk")
    if sdkApi == nil or sdkApi.ShowRewardVideoAd == nil then
        ShowToast("当前环境不支持广告")
        if options.onFail ~= nil then options.onFail({ success = false, msg = "unsupported platform" }) end
        return false
    end
    pending_ = true
    sdkApi:ShowRewardVideoAd(function(result)
        pending_ = false
        result = result or { success = false, msg = "unknown" }
        if result.success == true then
            if options.onSuccess ~= nil then options.onSuccess(result) end
        else
            local msg = tostring(result.msg or "广告播放失败")
            if msg == "embed manual close" then
                ShowToast("需完整观看广告才能获得奖励")
            else
                ShowToast("广告播放失败: " .. msg)
            end
            if options.onFail ~= nil then options.onFail(result) end
        end
    end)
    return true
end

function AdRewardSystem.ConfirmAndShow(options)
    options = options or {}
    if pending_ then
        ShowToast("广告正在播放，请稍后")
        return false
    end
    CloseConfirmModal()
    confirmModal_ = UI.Modal {
        title = options.title or "观看广告",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {16, 20, 18, 20},
        contentGap = 14,
        onClose = function()
            confirmModal_ = nil
        end,
    }
    confirmModal_:AddContent(UI.Panel {
        gap = 16,
        children = {
            UI.Label {
                text = options.message or "是否观看广告领取奖励？",
                fontSize = 15,
                fontColor = {92, 70, 48, 255},
                textAlign = "center",
                whiteSpace = "normal",
            },
            UI.Panel {
                flexDirection = "row",
                gap = 10,
                children = {
                    UI.Button {
                        text = "取消",
                        height = 42,
                        flexGrow = 1,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = {245, 238, 220, 255},
                        fontColor = {92, 72, 48, 255},
                        borderRadius = 16,
                        onClick = function()
                            CloseConfirmModal()
                        end,
                    },
                    UI.Button {
                        text = "看广告",
                        height = 42,
                        flexGrow = 1,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = {94, 194, 131, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function()
                            CloseConfirmModal()
                            AdRewardSystem.Show(options)
                        end,
                    },
                },
            },
        },
    })
    ModalAnim.Apply(confirmModal_, { fixedHeight = 220 })
    confirmModal_:Open()
    return true
end

return AdRewardSystem
