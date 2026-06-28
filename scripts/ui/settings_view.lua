-- ============================================================================
-- 设置面板视图 (Settings View)
-- Grow A Garden
-- ============================================================================
-- 右上角设置按钮 → Modal 弹窗，可调节音乐/音效音量，并切换地块显示模式。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")
local AudioSystem = require("systems.audio_system")
local FloatingToast = require("ui.floating_toast")

local SettingsView = {}

local deps_ = {}
local settingsModal_ = nil
local clearSaveModal_ = nil
local musicVolume_ = 80
local sfxVolume_ = 80
local clearSavePending_ = false

function SettingsView.Init(deps)
    deps_ = deps or {}
    -- 读取引擎当前音量（0~1 → 0~100）
    musicVolume_ = math.floor(audio:GetMasterGain(SOUND_MUSIC) * 100 + 0.5)
    sfxVolume_ = math.floor(audio:GetMasterGain(SOUND_EFFECT) * 100 + 0.5)
end

function SettingsView.IsOpen()
    return settingsModal_ ~= nil or clearSaveModal_ ~= nil
end

function SettingsView.HandleClearSaveCompleted(success)
    clearSavePending_ = false
    if clearSaveModal_ ~= nil then
        clearSaveModal_:Close()
        clearSaveModal_ = nil
    end
    if success and deps_.onClearSaveSuccess then
        deps_.onClearSaveSuccess()
    end
end

local function GetPlotDisplayMode()
    if deps_.getPlotDisplayMode then
        return deps_.getPlotDisplayMode()
    end
    return "all"
end

local function BuildVolumeSection(title, value, soundType)
    return UI.Panel {
        gap = 8,
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = title,
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = {75, 55, 40, 255},
                    },
                    UI.Label {
                        text = value .. "%",
                        fontSize = 13,
                        fontColor = {120, 100, 75, 220},
                    },
                },
            },
            UI.Slider {
                value = value,
                min = 0,
                max = 100,
                height = 36,
                trackColor = {220, 235, 225, 255},
                fillColor = {78, 172, 110, 255},
                thumbColor = {255, 255, 255, 255},
                onChange = function(self, val)
                    local volume = math.floor(val + 0.5)
                    if soundType == SOUND_MUSIC then
                        musicVolume_ = volume
                    else
                        sfxVolume_ = volume
                    end
                    audio:SetMasterGain(soundType, volume / 100.0)
                    SettingsView.RebuildContent()
                end,
            },
        },
    }
end

local function BuildModeButton(text, active, onClick)
    return UI.Button {
        text = text,
        height = 40,
        flexGrow = 1,
        fontSize = 14,
        fontWeight = "bold",
        backgroundColor = active and {78, 172, 110, 255} or {245, 238, 220, 255},
        fontColor = active and {255, 255, 255, 255} or {92, 72, 48, 255},
        borderRadius = 14,
        onClick = function()
            onClick()
        end,
    }
end

local function BuildPlotDisplaySection()
    local mode = GetPlotDisplayMode()
    local isSingle = mode == "single"
    local currentIndex = 1
    local unlockedCount = 1
    if deps_.getFocusedPlotIndex then currentIndex = deps_.getFocusedPlotIndex() end
    if deps_.getUnlockedPlotCount then unlockedCount = deps_.getUnlockedPlotCount() end

    local children = {
        UI.Label {
            text = "地块显示",
            fontSize = 15,
            fontWeight = "bold",
            fontColor = {75, 55, 40, 255},
        },
        UI.Label {
            text = isSingle and string.format("当前仅显示第 %d 块地", currentIndex) or string.format("当前显示全部已拓展地块（%d块）", unlockedCount),
            fontSize = 12,
            fontColor = {120, 100, 75, 220},
        },
        UI.Panel {
            flexDirection = "row",
            gap = 10,
            children = {
                BuildModeButton("全部", not isSingle, function()
                    if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("all") end
                    SettingsView.RebuildContent()
                end),
                BuildModeButton("单个", isSingle, function()
                    if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("single") end
                    SettingsView.RebuildContent()
                end),
            },
        },
    }

    if isSingle then
        table.insert(children, UI.Button {
            text = "切换下一个地块",
            height = 42,
            fontSize = 14,
            fontWeight = "bold",
            backgroundColor = {255, 210, 110, 255},
            fontColor = {92, 62, 32, 255},
            borderRadius = 16,
            onClick = function()
                if deps_.switchNextPlot then deps_.switchNextPlot() end
                SettingsView.RebuildContent()
            end,
        })
    end

    return UI.Panel {
        gap = 10,
        children = children,
    }
end

local function BuildContent()
    return UI.Panel {
        gap = 20,
        children = {
            BuildVolumeSection("音乐音量", musicVolume_, SOUND_MUSIC),
            BuildVolumeSection("音效音量", sfxVolume_, SOUND_EFFECT),
        },
    }
end

function SettingsView.Open()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end

    settingsModal_ = UI.Modal {
        title = "设置",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {16, 20, 16, 20},
        contentGap = 18,
        onClose = function()
            settingsModal_ = nil
        end,
    }

    settingsModal_:AddContent(BuildContent())

    ModalAnim.Apply(settingsModal_)
    settingsModal_:Open()
end

function SettingsView.RebuildContent()
    if settingsModal_ == nil then return end
    settingsModal_:ClearContent()
    settingsModal_:AddContent(BuildContent())
end

function SettingsView.OpenClearSaveConfirm()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
    if clearSaveModal_ ~= nil then clearSaveModal_:Close() end

    clearSaveModal_ = UI.Modal {
        title = "清除存档",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {16, 20, 18, 20},
        contentGap = 14,
        onClose = function()
            clearSaveModal_ = nil
        end,
    }

    clearSaveModal_:AddContent(UI.Panel {
        gap = 16,
        children = {
            UI.Label {
                text = "确定要清除游戏存档吗？金币、背包、种植进度和活动进度都会重置。名片昵称和头像不会被清除。",
                fontSize = 14,
                fontColor = {92, 70, 48, 255},
                textAlign = "center",
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
                            if clearSaveModal_ ~= nil then
                                clearSaveModal_:Close()
                                clearSaveModal_ = nil
                            end
                        end,
                    },
                    UI.Button {
                        text = "确认清除",
                        height = 42,
                        flexGrow = 1,
                        fontSize = 15,
                        fontWeight = "bold",
                        backgroundColor = {205, 88, 70, 255},
                        fontColor = {255, 255, 255, 255},
                        borderRadius = 16,
                        onClick = function(self)
                            if clearSavePending_ then return end
                            local requested = true
                            if deps_.clearSave then requested = deps_.clearSave() end
                            if not requested then
                                SettingsView.HandleClearSaveCompleted(false)
                                local text = "清除存档失败，请稍后重试"
                                if deps_.showToast then
                                    deps_.showToast(text)
                                end
                                FloatingToast.Show(text, {
                                    fontSize = 20,
                                    duration = 1.6,
                                    yRatio = 0.38,
                                    priority = 10,
                                    stackable = false,
                                })
                                return
                            end
                            clearSavePending_ = true
                            self:SetDisabled(true)
                            self:SetText("清除中...")
                            local text = "正在清除存档..."
                            if deps_.showToast then deps_.showToast(text) end
                            FloatingToast.Show(text, {
                                fontSize = 20,
                                duration = 1.2,
                                yRatio = 0.38,
                                priority = 8,
                                stackable = false,
                            })
                        end,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(clearSaveModal_, { fixedHeight = 230 })
    clearSaveModal_:Open()
end

function SettingsView.Close()
    if settingsModal_ ~= nil then
        settingsModal_:Close()
        settingsModal_ = nil
    end
    if clearSaveModal_ ~= nil then
        clearSaveModal_:Close()
        clearSaveModal_ = nil
    end
    clearSavePending_ = false
end

--- 构建名片弹窗内的设置与清档入口
function SettingsView.BuildButton()
    return UI.Panel {
        flexDirection = "row",
        gap = 10,
        children = {
            UI.Button {
                text = "设置",
                height = 44,
                flexGrow = 1,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 250, 240, 245},
                fontColor = {78, 155, 100, 255},
                borderRadius = 16,
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    SettingsView.Open()
                end,
            },
            UI.Button {
                text = "清除存档",
                height = 44,
                flexGrow = 1,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 238, 226, 245},
                fontColor = {188, 82, 62, 255},
                borderRadius = 16,
                onClick = function()
                    SettingsView.OpenClearSaveConfirm()
                end,
            },
        },
    }
end

function SettingsView.BuildPlotDisplayButtons()
    local isPlantView = deps_.isPlantView and deps_.isPlantView() or false
    local showNextPlot = isPlantView or GetPlotDisplayMode() == "single"
    local children = {
        BuildModeButton("全部", GetPlotDisplayMode() ~= "single", function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("all") end
        end),
        BuildModeButton("单个", GetPlotDisplayMode() == "single", function()
            if deps_.suppressWorldTap then deps_.suppressWorldTap() end
            if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("single") end
        end),
        showNextPlot and UI.Button {
            text = "下一块",
            height = 40,
            fontSize = 14,
            fontWeight = "bold",
            backgroundColor = {255, 210, 110, 255},
            fontColor = {92, 62, 32, 255},
            borderRadius = 14,
            onClick = function()
                if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                if deps_.switchNextPlot then deps_.switchNextPlot() end
            end,
        } or UI.Panel { width = 0, height = 0 },
    }

    if isPlantView then
        table.insert(children, UI.Button {
            text = "放大",
            height = 40,
            fontSize = 14,
            fontWeight = "bold",
            backgroundColor = {255, 250, 240, 245},
            fontColor = {78, 155, 100, 255},
            borderRadius = 14,
            borderWidth = 2,
            borderColor = {185, 165, 130, 180},
            onClick = function()
                if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                if deps_.zoomPlantView then deps_.zoomPlantView(-1) end
            end,
        })
        table.insert(children, UI.Button {
            text = "缩小",
            height = 40,
            fontSize = 14,
            fontWeight = "bold",
            backgroundColor = {255, 250, 240, 245},
            fontColor = {78, 155, 100, 255},
            borderRadius = 14,
            borderWidth = 2,
            borderColor = {185, 165, 130, 180},
            onClick = function()
                if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                if deps_.zoomPlantView then deps_.zoomPlantView(1) end
            end,
        })
    end

    return UI.Panel {
        position = "absolute",
        top = 152,
        right = 14,
        width = 56,
        gap = 8,
        alignItems = "flex-end",
        children = children,
    }
end

function SettingsView.BuildOverlay()
    return UI.Panel { width = 0, height = 0 }
end

return SettingsView
