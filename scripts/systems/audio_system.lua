-- ============================================================================
-- 音频系统 (Audio System)
-- Grow A Garden
-- ============================================================================
-- 管理 BGM 随机列表循环播放、音效播放与环境音循环。
-- ============================================================================

local AudioSystem = {}

local BGM_TRACKS = {
    "audio/music_1781979156772.ogg",
    "audio/music_1781979661883.ogg",
    "audio/music_1782020682333.ogg",
    "audio/music_1782020930957.ogg",
}

AudioSystem.SFX = {
    ui_click = "audio/sfx/ui_click.ogg",
    ui_modal_open = "audio/sfx/ui_modal_open.ogg",
    ui_modal_close = "audio/sfx/ui_modal_close.ogg",
    toast_notice = "audio/sfx/toast_notice.ogg",
    error_denied = "audio/sfx/error_denied.ogg",
    plant_seed = "audio/sfx/plant_seed.ogg",
    harvest_crop = "audio/sfx/harvest_crop.ogg",
    buy_seed = "audio/sfx/buy_seed.ogg",
    sell_success = "audio/sfx/sell_success.ogg",
    plot_select = "audio/sfx/plot_select.ogg",
    crop_sprout = "audio/sfx/crop_sprout.ogg",
    crop_mature = "audio/sfx/crop_mature.ogg",
    level_up = "audio/sfx/level_up.ogg",
    talent_unlock = "audio/sfx/talent_unlock.ogg",
    land_unlock = "audio/sfx/land_unlock.ogg",
    commission_complete = "audio/sfx/commission_complete.ogg",
    harvest_pack_drop = "audio/sfx/harvest_pack_drop.ogg",
    collection_reward = "audio/sfx/collection_reward.ogg",
    bag_select_item = "audio/sfx/bag_select_item.ogg",
    tab_switch = "audio/sfx/tab_switch.ogg",
    seed_pack_open_start = "audio/sfx/seed_pack_open_start.ogg",
    seed_pack_roll = "audio/sfx/seed_pack_roll.ogg",
    seed_pack_reveal_common = "audio/sfx/seed_pack_reveal_common.ogg",
    seed_pack_reveal_rare = "audio/sfx/seed_pack_reveal_rare.ogg",
    seed_pack_reveal_epic = "audio/sfx/seed_pack_reveal_epic.ogg",
    seed_pack_reveal_legendary = "audio/sfx/seed_pack_reveal_legendary.ogg",
    mutation_color = "audio/sfx/mutation_color.ogg",
    mutation_special = "audio/sfx/mutation_special.ogg",
    camera_zoom = "audio/sfx/camera_zoom.ogg",
    settings_slider = "audio/sfx/settings_slider.ogg",
    ambient_farm_day = "audio/sfx/ambient_farm_day.ogg",
    ambient_magic_plants = "audio/sfx/ambient_magic_plants.ogg",
}

local bgmPlaylist_ = {}
local bgmCurrentIndex_ = 0
---@type SoundSource|nil
local bgmSource_ = nil
---@type Node|nil
local bgmNode_ = nil
---@type Node|nil
local sfxRootNode_ = nil
local activeSfxSources_ = {}
local ambientSources_ = {}
local lastPlayTime_ = {}
local currentTime_ = 0

local SFX_DEFAULT_GAIN = {
    ui_click = 0.28,
    toast_notice = 0.45,
    crop_mature = 0.42,
    crop_sprout = 0.45,
    plant_seed = 0.65,
    mutation_color = 0.45,
    mutation_special = 0.48,
}

local SFX_MIN_INTERVAL = {
    ui_click = 0.10,
    toast_notice = 0.35,
    error_denied = 0.25,
    crop_sprout = 0.30,
    crop_mature = 0.80,
    plant_seed = 0.12,
    mutation_color = 0.40,
    mutation_special = 0.40,
    camera_zoom = 0.18,
    settings_slider = 0.08,
}

local function ShuffleBGMPlaylist()
    bgmPlaylist_ = {}
    for i = 1, #BGM_TRACKS do
        bgmPlaylist_[i] = i
    end
    for i = #bgmPlaylist_, 2, -1 do
        local j = math.random(1, i)
        bgmPlaylist_[i], bgmPlaylist_[j] = bgmPlaylist_[j], bgmPlaylist_[i]
    end
    bgmCurrentIndex_ = 0
end

local function GetSoundPath(idOrPath)
    return AudioSystem.SFX[idOrPath] or idOrPath
end

local function LoadSound(idOrPath, looped)
    local path = GetSoundPath(idOrPath)
    local sound = cache:GetResource("Sound", path)
    if sound == nil then
        print("[Audio] 加载失败: " .. path)
        return nil
    end
    sound.looped = looped == true
    return sound
end

function AudioSystem.PlayNextBGM()
    bgmCurrentIndex_ = bgmCurrentIndex_ + 1
    if bgmCurrentIndex_ > #bgmPlaylist_ then
        ShuffleBGMPlaylist()
        bgmCurrentIndex_ = 1
    end
    local trackIndex = bgmPlaylist_[bgmCurrentIndex_]
    local path = BGM_TRACKS[trackIndex]
    local sound = cache:GetResource("Sound", path)
    if sound == nil then
        print("[BGM] 加载失败: " .. path)
        return
    end
    sound.looped = false
    if bgmSource_ ~= nil then
        bgmSource_:Play(sound)
    end
    print("[BGM] 正在播放: " .. path)
end

---@param scene Scene|nil
function AudioSystem.InitBGM(scene)
    if scene == nil then return end
    bgmNode_ = scene:CreateChild("BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = SOUND_MUSIC
    bgmSource_.gain = 0.35
    ShuffleBGMPlaylist()
    AudioSystem.PlayNextBGM()
    SubscribeToEvent("SoundFinished", "HandleSoundFinished")
end

---@param scene Scene|nil
function AudioSystem.InitSFX(scene)
    if scene == nil then return end
    sfxRootNode_ = scene:CreateChild("SFX")
end

local DISABLED_SFX = {
    ui_click = true,
    ui_modal_open = true,
    ui_modal_close = true,
    tab_switch = true,
    bag_select_item = true,
    settings_slider = true,
    crop_sprout = true,
    crop_mature = true,
}

function AudioSystem.PlaySFX(idOrPath, gain, minInterval)
    if DISABLED_SFX[idOrPath] then return end
    if sfxRootNode_ == nil then return end
    local interval = minInterval or SFX_MIN_INTERVAL[idOrPath]
    if interval ~= nil then
        local lastTime = lastPlayTime_[idOrPath] or -999
        if currentTime_ - lastTime < interval then
            return
        end
        lastPlayTime_[idOrPath] = currentTime_
    end

    local sound = LoadSound(idOrPath, false)
    if sound == nil then return end

    local node = sfxRootNode_:CreateChild("SFX_" .. tostring(idOrPath))
    local source = node:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source.gain = gain or SFX_DEFAULT_GAIN[idOrPath] or 1.0
    source:Play(sound)
    table.insert(activeSfxSources_, source)
end

function AudioSystem.PlayAmbient(idOrPath, gain)
    if sfxRootNode_ == nil then return end
    if ambientSources_[idOrPath] ~= nil and ambientSources_[idOrPath]:IsPlaying() then
        return
    end

    local sound = LoadSound(idOrPath, true)
    if sound == nil then return end

    local node = sfxRootNode_:CreateChild("Ambient_" .. tostring(idOrPath))
    local source = node:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source.gain = gain or 0.35
    source:Play(sound)
    ambientSources_[idOrPath] = source
end

function AudioSystem.StopAmbient(idOrPath)
    local source = ambientSources_[idOrPath]
    if source == nil then return end
    local node = source.node
    source:Stop()
    if node ~= nil then
        node:Remove()
    end
    ambientSources_[idOrPath] = nil
end

function AudioSystem.Update(dt)
    currentTime_ = currentTime_ + dt
    for i = #activeSfxSources_, 1, -1 do
        local source = activeSfxSources_[i]
        if source == nil or not source:IsPlaying() then
            if source ~= nil and source.node ~= nil then
                source.node:Remove()
            end
            table.remove(activeSfxSources_, i)
        end
    end
end

function AudioSystem.HandleSoundFinished(eventData)
    local finishedSource = eventData["SoundSource"]:GetPtr("SoundSource")
    if finishedSource == bgmSource_ then
        AudioSystem.PlayNextBGM()
    end
end

return AudioSystem
