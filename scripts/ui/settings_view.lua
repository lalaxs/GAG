-- ============================================================================
-- 设置面板视图 (Settings View)
-- Grow A Garden
-- ============================================================================
-- 右上角设置按钮 → Modal 弹窗，可调节音乐/音效音量，并切换地块显示模式。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ModalAnim = require("ui.modal_anim")

local SettingsView = {}

local deps_ = {}
local settingsModal_ = nil
local musicVolume_ = 80
local sfxVolume_ = 80

function SettingsView.Init(deps)
    deps_ = deps or {}
    -- 读取引擎当前音量（0~1 → 0~100）
    musicVolume_ = math.floor(audio:GetMasterGain(SOUND_MUSIC) * 100 + 0.5)
    sfxVolume_ = math.floor(audio:GetMasterGain(SOUND_EFFECT) * 100 + 0.5)
end

function SettingsView.IsOpen()
    return settingsModal_ ~= nil
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
        onClick = onClick,
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

function SettingsView.Close()
    if settingsModal_ ~= nil then
        settingsModal_:Close()
        settingsModal_ = nil
    end
end

--- 构建右上角设置入口，以及入口下方的地块显示切换按钮
function SettingsView.BuildButton()
    return UI.Panel {
        position = "absolute",
        top = 132,
        right = 14,
        gap = 8,
        alignItems = "flex-end",
        children = {
            UI.Button {
                text = "设置",
                width = 56,
                height = 56,
                fontSize = 15,
                fontWeight = "bold",
                backgroundColor = {255, 250, 240, 245},
                fontColor = {78, 155, 100, 255},
                borderRadius = 18,
                onClick = function()
                    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                    SettingsView.Open()
                end,
            },
            UI.Panel {
                width = 56,
                gap = 8,
                alignItems = "flex-end",
                children = {
                    BuildModeButton("全部", GetPlotDisplayMode() ~= "single", function()
                        if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                        if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("all") end
                    end),
                    BuildModeButton("单个", GetPlotDisplayMode() == "single", function()
                        if deps_.suppressWorldTap then deps_.suppressWorldTap() end
                        if deps_.setPlotDisplayMode then deps_.setPlotDisplayMode("single") end
                    end),
                    GetPlotDisplayMode() == "single" and UI.Button {
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
                },
            },
        },
    }
end

--- 构建弹窗覆盖层（Modal 自行管理渲染，此处返回空占位）
function SettingsView.BuildOverlay()
    return UI.Panel { width = 0, height = 0 }
end

return SettingsView
