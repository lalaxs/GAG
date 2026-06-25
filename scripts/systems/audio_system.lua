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
    plant_seed = "audio/sfx/plant_seed.ogg",
    harvest_crop = "audio/sfx/harvest_crop.ogg",
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
local lastPlayTime_ = {}
local currentTime_ = 0

local SFX_DEFAULT_GAIN = {
    plant_seed = 0.65,
}

local SFX_MIN_INTERVAL = {
    plant_seed = 0.12,
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

local ENABLED_SFX = {
    plant_seed = true,
    harvest_crop = true,
}

function AudioSystem.PlaySFX(idOrPath, gain, minInterval)
    if not ENABLED_SFX[idOrPath] then return end
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
