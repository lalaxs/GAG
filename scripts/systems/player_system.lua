-- ============================================================================
-- 玩家资料系统 (Player Profile System)
-- Grow A Garden
-- ============================================================================
-- 管理玩家显示昵称、Tap 默认昵称、头像选择与本地资料保存。
-- ============================================================================

local PlayerSystem = {}

local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")
local GameConfig = require("config.game_config")
local Shared = require("network.shared")
local UserId = require("utils.user_id")

local SAVE_PATH = "player_profile.json"
local NICKNAME_MIN_LENGTH = 2
local NICKNAME_MAX_LENGTH = 12

local NICKNAME_BLOCK_WORDS = {
    "官方", "系统", "管理员", "客服", "gm", "taptap", "tap", "平台", "开发者",
    "外挂", "作弊", "代充", "充值返利", "诈骗", "广告", "qq群", "微信", "wx", "qq",
}

local function ColorToRgba(color)
    if color == nil then return {112, 190, 118, 255} end
    return {
        math.floor(color.r * 255),
        math.floor(color.g * 255),
        math.floor(color.b * 255),
        math.floor((color.a or 1.0) * 255),
    }
end

local function BuildAvatarList()
    local list = {}
    for i, plant in ipairs(GameConfig.PLANTS or {}) do
        table.insert(list, {
            id = "plant_" .. i,
            visualId = plant.visual,
            plantIndex = i,
            name = plant.name,
            rarity = plant.rarity,
            image = string.format("image/plants/plants (%d).png", i),
            color = ColorToRgba(plant.color),
        })
    end
    return list
end

local AVATARS = BuildAvatarList()
local DEFAULT_UNLOCKED_AVATAR_INDICES = { 1, 2, 3 }

local function BuildDefaultUnlockedAvatars()
    local unlocked = {}
    for _, index in ipairs(DEFAULT_UNLOCKED_AVATAR_INDICES) do
        local avatar = AVATARS[index]
        if avatar ~= nil then
            unlocked[avatar.id] = true
        end
    end
    return unlocked
end

local state_ = {
    userId = nil,
    tapNickname = "Tap玩家",
    customNickname = "",
    selectedAvatar = 1,
    unlockedAvatars = BuildDefaultUnlockedAvatars(),
    powerSaveMode = false,
}

local callbacks_ = {}
local subscribedProfileEvent_ = false
local nicknameFetchAttempts_ = 0
local nicknameRetryTimer_ = 0
local serverUserIdCertified_ = false
local MAX_NICKNAME_FETCH_ATTEMPTS = 5

local function NotifyChanged()
    EventBus.Emit(UIEvents.PLAYER_CHANGED, { reason = "profile_changed" })
    if callbacks_.onChanged then
        callbacks_.onChanged()
    end
end

local function FindAvatarIndexById(avatarId)
    if avatarId == nil then return nil end
    for i, avatar in ipairs(AVATARS) do
        if avatar.id == avatarId or avatar.visualId == avatarId or avatar.name == avatarId then
            return i
        end
    end
    return nil
end

local function FindAvatarIndex(avatarRef)
    if type(avatarRef) == "number" then
        local index = math.floor(avatarRef)
        if AVATARS[index] ~= nil then return index end
        return nil
    end
    local textRef = tostring(avatarRef or "")
    local numericRef = tonumber(textRef)
    if numericRef ~= nil then
        local index = math.floor(numericRef)
        if AVATARS[index] ~= nil then return index end
    end
    return FindAvatarIndexById(textRef)
end

local function IsAvatarUnlockedIndex(index)
    local avatar = AVATARS[index]
    return avatar ~= nil and state_.unlockedAvatars[avatar.id] == true
end

local function EnsureSelectedAvatarUnlocked()
    if IsAvatarUnlockedIndex(state_.selectedAvatar) then return end
    for i = 1, #AVATARS do
        if IsAvatarUnlockedIndex(i) then
            state_.selectedAvatar = i
            return
        end
    end
    state_.unlockedAvatars = BuildDefaultUnlockedAvatars()
    state_.selectedAvatar = 1
end

local function MergeUnlockedAvatars(saved)
    local unlocked = BuildDefaultUnlockedAvatars()
    if type(saved) == "table" then
        for key, value in pairs(saved) do
            if value == true then
                local index = FindAvatarIndex(key)
                if index ~= nil then unlocked[AVATARS[index].id] = true end
            elseif type(value) == "string" or type(value) == "number" then
                local index = FindAvatarIndex(value)
                if index ~= nil then unlocked[AVATARS[index].id] = true end
            end
        end
    end
    return unlocked
end

local function TrimName(name)
    name = tostring(name or "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    return name
end

local function NormalizeUserId(userId)
    return UserId.Normalize(userId)
end

local function SameUserId(left, right)
    return UserId.Same(left, right)
end

local function GetNicknameRows(response)
    if type(response) ~= "table" then return {} end
    if type(response.nicknames) == "table" then return response.nicknames end
    return response
end

local function GetTextLength(text)
    local ok, length = pcall(utf8.len, text or "")
    if ok and length ~= nil then
        return length
    end
    return #(text or "")
end

local function NormalizeNicknameForCheck(name)
    local normalized = string.lower(name or "")
    normalized = string.gsub(normalized, "%s+", "")
    normalized = string.gsub(normalized, "[%.%-_]+", "")
    return normalized
end

function PlayerSystem.ValidateNickname(name)
    local trimmed = TrimName(name)
    local length = GetTextLength(trimmed)
    if length <= 0 then
        return false, "昵称不能为空", trimmed
    end
    if length < NICKNAME_MIN_LENGTH then
        return false, string.format("昵称至少 %d 个字符", NICKNAME_MIN_LENGTH), trimmed
    end
    if length > NICKNAME_MAX_LENGTH then
        return false, string.format("昵称最多 %d 个字符", NICKNAME_MAX_LENGTH), trimmed
    end

    local normalized = NormalizeNicknameForCheck(trimmed)
    for _, word in ipairs(NICKNAME_BLOCK_WORDS) do
        if string.find(normalized, NormalizeNicknameForCheck(word), 1, true) ~= nil then
            return false, "昵称包含不可用词", trimmed
        end
    end

    return true, nil, trimmed
end

local function GetCurrentUserId()
    if clientCloud ~= nil and clientCloud.userId ~= nil and clientCloud.userId ~= 0 and clientCloud.userId ~= "" then
        return UserId.Normalize(clientCloud.userId)
    end
    local lobbyService = rawget(_G, "lobby")
    if lobbyService ~= nil and lobbyService.GetMyUserId ~= nil then
        local ok, userId = pcall(function() return lobbyService:GetMyUserId() end)
        if ok then return UserId.Normalize(userId) end
    end
    if common ~= nil and common.get_user_id ~= nil then
        local ok, userId = pcall(common.get_user_id)
        if ok then return UserId.Normalize(userId) end
    end
    return nil
end

local function LoadLocalProfile()
    if fileSystem == nil or not fileSystem:FileExists(SAVE_PATH) then return end
    local file = File(SAVE_PATH, FILE_READ)
    if file == nil or not file:IsOpen() then return end

    local raw = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then
        print("[玩家资料] 本地资料解析失败，使用默认资料")
        return
    end

    state_.customNickname = TrimName(data.customNickname or "")
    state_.unlockedAvatars = MergeUnlockedAvatars(data.unlockedAvatars)
    state_.selectedAvatar = Clamp(tonumber(data.selectedAvatar or 1) or 1, 1, #AVATARS)
    state_.powerSaveMode = data.powerSaveMode == true
    EnsureSelectedAvatarUnlocked()
end

local function SaveLocalProfile()
    local file = File(SAVE_PATH, FILE_WRITE)
    if file == nil or not file:IsOpen() then
        print("[玩家资料] 保存失败：无法打开本地文件")
        return false
    end

    file:WriteString(cjson.encode({
        customNickname = state_.customNickname,
        selectedAvatar = state_.selectedAvatar,
        unlockedAvatars = state_.unlockedAvatars,
        powerSaveMode = state_.powerSaveMode,
    }))
    file:Close()
    return true
end

local function IsDefaultAvatarProfile(avatar)
    if type(avatar) ~= "table" then return true end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    if plantIndex ~= nil then return math.floor(plantIndex) == 1 end
    return tostring(avatar.image or "") == "image/plants/plants (1).png"
end

local function ResolveAvatarIndexFromProfile(avatar)
    if type(avatar) ~= "table" then return nil end
    local index = FindAvatarIndex(avatar.plantIndex or avatar.selectedAvatar or avatar.index or avatar.avatarId or avatar.visualId)
    if index ~= nil then return index end
    local image = tostring(avatar.image or "")
    local plantNumber = string.match(image, "plants %((%d+)%)%.png")
    if plantNumber ~= nil then return FindAvatarIndex(tonumber(plantNumber)) end
    return nil
end

local function ApplyCloudAvatar(avatar, source)
    local index = ResolveAvatarIndexFromProfile(avatar)
    if index == nil then return false end

    local avatarEntry = AVATARS[index]
    if avatarEntry == nil then return false end

    local cloudIsDefault = IsDefaultAvatarProfile(avatar)
    local localIsDefault = IsDefaultAvatarProfile({ plantIndex = state_.selectedAvatar })
    local changed = false

    if not IsAvatarUnlockedIndex(index) then
        state_.unlockedAvatars[avatarEntry.id] = true
        changed = true
    end

    if cloudIsDefault and not localIsDefault then
        if changed then
            EnsureSelectedAvatarUnlocked()
            SaveLocalProfile()
            NotifyChanged()
        end
        return changed
    end

    if index ~= state_.selectedAvatar then
        state_.selectedAvatar = index
        changed = true
    end

    if changed then
        EnsureSelectedAvatarUnlocked()
        SaveLocalProfile()
        NotifyChanged()
        print(string.format("[玩家资料] 已从%s同步头像: %s", source or "云端", avatarEntry.name or tostring(index)))
    end
    return changed
end

local function FetchTapNickname()
    local userId = GetCurrentUserId()
    if serverUserIdCertified_ ~= true then
        state_.userId = UserId.Normalize(userId)
    end
    nicknameFetchAttempts_ = nicknameFetchAttempts_ + 1
    if userId == nil then
        if nicknameFetchAttempts_ >= MAX_NICKNAME_FETCH_ATTEMPTS then
            print("[玩家资料] 客户端暂未获得 Tap 用户 ID，等待服务器认证资料")
        end
        return false
    end

    if GetUserNickname == nil then
        if nicknameFetchAttempts_ >= MAX_NICKNAME_FETCH_ATTEMPTS then
            print("[玩家资料] 当前环境不支持客户端昵称查询，等待服务器认证资料")
        end
        return false
    end

    GetUserNickname({
        userIds = { userId },
        onSuccess = function(response)
            for _, info in ipairs(GetNicknameRows(response)) do
                if SameUserId(info.userId, userId) and info.nickname ~= nil and info.nickname ~= "" then
                    state_.tapNickname = TrimName(info.nickname)
                    print("[玩家资料] 已读取 Tap 账号: " .. tostring(state_.userId) .. " / " .. state_.tapNickname)
                    NotifyChanged()
                    return
                end
            end
            print("[玩家资料] 未查询到 Tap 昵称，使用默认昵称，userId=" .. tostring(state_.userId))
            NotifyChanged()
        end,
        onError = function(errorCode)
            print("[玩家资料] 查询 Tap 昵称失败: " .. tostring(errorCode) .. ", userId=" .. tostring(userId))
            NotifyChanged()
        end,
    })
    return true
end

local function ApplyServerProfile(data)
    if type(data) ~= "table" or data.success == false then return false end
    local userId = data.userId
    if userId == nil or userId == 0 or userId == "" then return false end
    local nickname = state_.tapNickname
    if data.nickname ~= nil and data.nickname ~= "" then
        nickname = TrimName(data.nickname)
    end
    if nickname == "Tap玩家" and state_.tapNickname ~= nil and state_.tapNickname ~= "" and state_.tapNickname ~= "Tap玩家" then
        nickname = state_.tapNickname
    end
    local avatarChanged = false
    if data.avatar ~= nil then
        avatarChanged = ApplyCloudAvatar(data.avatar, "服务器")
    end
    if SameUserId(state_.userId, userId) and state_.tapNickname == nickname and not avatarChanged then
        return true
    end
    state_.userId = UserId.Normalize(userId)
    serverUserIdCertified_ = true
    state_.tapNickname = nickname
    print("[玩家资料] 已从服务器认证资料读取 Tap 账号: " .. tostring(state_.userId) .. " / " .. tostring(state_.tapNickname))
    NotifyChanged()
    return true
end

function HandlePlayerProfileResponse(eventType, eventData)
    ApplyServerProfile(Shared.ReadEventData(eventData))
end

function PlayerSystem.Init(callbacks)
    callbacks_ = callbacks or {}
    nicknameFetchAttempts_ = 0
    nicknameRetryTimer_ = 0
    serverUserIdCertified_ = false
    state_ = {
        userId = nil,
        tapNickname = "Tap玩家",
        customNickname = "",
        selectedAvatar = 1,
        unlockedAvatars = BuildDefaultUnlockedAvatars(),
        powerSaveMode = false,
    }
    LoadLocalProfile()
    if subscribedProfileEvent_ ~= true and network ~= nil and IsClientMode ~= nil and IsClientMode() then
        network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_PROFILE)
        SubscribeToEvent(Shared.EVENTS.PLAYER_PROFILE, "HandlePlayerProfileResponse")
        subscribedProfileEvent_ = true
    end
    FetchTapNickname()
end

function PlayerSystem.Update(dt)
    if (state_.userId ~= nil and state_.tapNickname ~= "Tap玩家") or nicknameFetchAttempts_ >= MAX_NICKNAME_FETCH_ATTEMPTS then return end
    nicknameRetryTimer_ = nicknameRetryTimer_ + (dt or 0)
    if nicknameRetryTimer_ < 1.0 then return end
    nicknameRetryTimer_ = 0
    FetchTapNickname()
end

function PlayerSystem.RetryFetchTapProfile()
    if state_.userId ~= nil and state_.tapNickname ~= "Tap玩家" then return true end
    return FetchTapNickname()
end

function PlayerSystem.GetUserId()
    return state_.userId
end

function PlayerSystem.IsServerUserIdCertified()
    return serverUserIdCertified_ == true
end

function PlayerSystem.GetTapNickname()
    return state_.tapNickname
end

function PlayerSystem.GetCustomNickname()
    return state_.customNickname
end

function PlayerSystem.GetDisplayName()
    if state_.customNickname ~= nil and state_.customNickname ~= "" then
        return state_.customNickname
    end
    return state_.tapNickname or "Tap玩家"
end

function PlayerSystem.SetNickname(name)
    local valid, message, trimmed = PlayerSystem.ValidateNickname(name)
    if not valid then
        return nil, message
    end
    state_.customNickname = trimmed
    SaveLocalProfile()
    NotifyChanged()
    return state_.customNickname, nil
end

function PlayerSystem.ClearCustomNickname()
    state_.customNickname = ""
    SaveLocalProfile()
    NotifyChanged()
end

function PlayerSystem.ClearSave()
    state_.customNickname = ""
    state_.selectedAvatar = 1
    state_.unlockedAvatars = BuildDefaultUnlockedAvatars()
    EnsureSelectedAvatarUnlocked()
    local ok = SaveLocalProfile()
    NotifyChanged()
    return ok
end

function PlayerSystem.IsPowerSaveMode()
    return state_.powerSaveMode == true
end

function PlayerSystem.SetPowerSaveMode(enabled)
    local nextValue = enabled == true
    if state_.powerSaveMode == nextValue then return true end
    state_.powerSaveMode = nextValue
    return SaveLocalProfile()
end

function PlayerSystem.IsMatureCropRotationEnabled()
    return state_.powerSaveMode ~= true
end

function PlayerSystem.GetAvatars()
    local list = {}
    for i, avatar in ipairs(AVATARS) do
        local copy = {}
        for key, value in pairs(avatar) do
            copy[key] = value
        end
        copy.unlocked = IsAvatarUnlockedIndex(i)
        copy.unlockHint = copy.unlocked and "已解锁" or "通过活动或奖励获取"
        table.insert(list, copy)
    end
    return list
end

function PlayerSystem.IsAvatarUnlocked(avatarRef)
    local index = FindAvatarIndex(avatarRef)
    return index ~= nil and IsAvatarUnlockedIndex(index)
end

function PlayerSystem.GetSelectedAvatarIndex()
    EnsureSelectedAvatarUnlocked()
    return state_.selectedAvatar
end

function PlayerSystem.GetSelectedAvatar()
    EnsureSelectedAvatarUnlocked()
    return AVATARS[state_.selectedAvatar] or AVATARS[1]
end

function PlayerSystem.GetSelectedAvatarProfile()
    EnsureSelectedAvatarUnlocked()
    local avatar = AVATARS[state_.selectedAvatar] or AVATARS[1]
    if avatar == nil then return nil end
    return {
        selectedAvatar = state_.selectedAvatar,
        avatarId = avatar.id,
        visualId = avatar.visualId,
        plantIndex = avatar.plantIndex,
        name = avatar.name,
        rarity = avatar.rarity,
        image = avatar.image,
        color = avatar.color,
    }
end

function PlayerSystem.SelectAvatar(index)
    index = Clamp(index or 1, 1, #AVATARS)
    if not IsAvatarUnlockedIndex(index) then
        local avatar = AVATARS[index]
        return false, string.format("%s头像尚未解锁", avatar and avatar.name or "该")
    end
    state_.selectedAvatar = index
    SaveLocalProfile()
    NotifyChanged()
    return true, nil
end

function PlayerSystem.UnlockAvatarReward(avatarRef)
    local index = FindAvatarIndex(avatarRef)
    if index == nil then
        return false, "头像奖励不存在", nil
    end

    local avatar = AVATARS[index]
    if state_.unlockedAvatars[avatar.id] == true then
        return false, "头像已拥有", avatar
    end

    state_.unlockedAvatars[avatar.id] = true
    SaveLocalProfile()
    NotifyChanged()
    return true, nil, avatar
end

function PlayerSystem.GrantReward(reward)
    if type(reward) ~= "table" then
        return false, "奖励配置无效"
    end
    if reward.type == "avatar" then
        return PlayerSystem.UnlockAvatarReward(reward.avatarId or reward.avatarIndex or reward.index or reward.id)
    end
    return false, "不支持的奖励类型"
end

function PlayerSystem.GetUnlockedAvatarMap()
    local map = {}
    for key, value in pairs(state_.unlockedAvatars) do
        map[key] = value
    end
    return map
end

function PlayerSystem.GetSaveData()
    return {
        customNickname = state_.customNickname,
        selectedAvatar = state_.selectedAvatar,
        unlockedAvatars = state_.unlockedAvatars,
        powerSaveMode = state_.powerSaveMode,
    }
end

function PlayerSystem.LoadSaveData(data)
    if data == nil then return end
    state_.customNickname = TrimName(data.customNickname or state_.customNickname)
    state_.unlockedAvatars = MergeUnlockedAvatars(data.unlockedAvatars or state_.unlockedAvatars)
    state_.selectedAvatar = Clamp(tonumber(data.selectedAvatar or state_.selectedAvatar) or 1, 1, #AVATARS)
    state_.powerSaveMode = data.powerSaveMode == true
    EnsureSelectedAvatarUnlocked()
    SaveLocalProfile()
    NotifyChanged()
end

function PlayerSystem.ApplyCloudAvatarProfile(avatar, source)
    return ApplyCloudAvatar(avatar, source)
end

return PlayerSystem
