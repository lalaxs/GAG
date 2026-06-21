-- ============================================================================
-- 音频系统 (Audio System)
-- Grow A Garden
-- ============================================================================
-- 管理 BGM 随机列表循环播放与播放完成切歌。
-- ============================================================================

local AudioSystem = {}

local BGM_TRACKS = {
    "audio/music_1781979156772.ogg",
    "audio/music_1781979661883.ogg",
    "audio/music_1782020682333.ogg",
    "audio/music_1782020930957.ogg",
}

local bgmPlaylist_ = {}
local bgmCurrentIndex_ = 0
---@type SoundSource|nil
local bgmSource_ = nil
---@type Node|nil
local bgmNode_ = nil

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

function AudioSystem.HandleSoundFinished(eventData)
    local finishedSource = eventData["SoundSource"]:GetPtr("SoundSource")
    if finishedSource == bgmSource_ then
        AudioSystem.PlayNextBGM()
    end
end

return AudioSystem
