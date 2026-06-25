-- ============================================================================
-- 玩家资料系统 (Player Profile System)
-- Grow A Garden
-- ============================================================================
-- 管理玩家显示昵称、Tap 默认昵称、头像选择与本地资料保存。
-- ============================================================================

local PlayerSystem = {}

local GameConfig = require("config.game_config")

local SAVE_PATH = "player_profile.json"

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
            id = plant.visual or ("plant_" .. i),
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

local state_ = {
    userId = nil,
    tapNickname = "Tap玩家",
    customNickname = "",
    selectedAvatar = 1,
}

local callbacks_ = {}

local function NotifyChanged()
    if callbacks_.onChanged then
        callbacks_.onChanged()
    end
end

local function TrimName(name)
    name = tostring(name or "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if #name > 24 then
        name = string.sub(name, 1, 24)
    end
    return name
end

local function GetCurrentUserId()
    if common ~= nil and common.get_user_id ~= nil then
        local ok, userId = pcall(common.get_user_id)
        if ok and userId ~= nil and userId ~= 0 then
            return userId
        end
    end
    local lobbyService = rawget(_G, "lobby")
    if lobbyService ~= nil and lobbyService.GetMyUserId ~= nil then
        local ok, userId = pcall(function() return lobbyService:GetMyUserId() end)
        if ok and userId ~= nil and userId ~= 0 then
            return userId
        end
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
    state_.selectedAvatar = Clamp(tonumber(data.selectedAvatar or 1) or 1, 1, #AVATARS)
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
    }))
    file:Close()
    return true
end

local function FetchTapNickname()
    local userId = GetCurrentUserId()
    state_.userId = userId
    if userId == nil then
        print("[玩家资料] 当前无法获取 Tap 用户 ID，使用默认昵称")
        NotifyChanged()
        return
    end

    if GetUserNickname == nil then
        print("[玩家资料] 当前环境不支持昵称查询，使用默认昵称")
        NotifyChanged()
        return
    end

    GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if type(nicknames) == "table" then
                for _, info in ipairs(nicknames) do
                    if info.userId == userId and info.nickname ~= nil and info.nickname ~= "" then
                        state_.tapNickname = TrimName(info.nickname)
                        print("[玩家资料] 已读取 Tap 昵称: " .. state_.tapNickname)
                        NotifyChanged()
                        return
                    end
                end
            end
            print("[玩家资料] 未查询到 Tap 昵称，使用默认昵称")
            NotifyChanged()
        end,
        onError = function(errorCode)
            print("[玩家资料] 查询 Tap 昵称失败: " .. tostring(errorCode))
            NotifyChanged()
        end,
    })
end

function PlayerSystem.Init(callbacks)
    callbacks_ = callbacks or {}
    state_ = {
        userId = nil,
        tapNickname = "Tap玩家",
        customNickname = "",
        selectedAvatar = 1,
    }
    LoadLocalProfile()
    FetchTapNickname()
end

function PlayerSystem.GetUserId()
    return state_.userId
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
    state_.customNickname = TrimName(name)
    SaveLocalProfile()
    NotifyChanged()
    return state_.customNickname
end

function PlayerSystem.ClearCustomNickname()
    state_.customNickname = ""
    SaveLocalProfile()
    NotifyChanged()
end

function PlayerSystem.GetAvatars()
    return AVATARS
end

function PlayerSystem.GetSelectedAvatarIndex()
    return state_.selectedAvatar
end

function PlayerSystem.GetSelectedAvatar()
    return AVATARS[state_.selectedAvatar] or AVATARS[1]
end

function PlayerSystem.SelectAvatar(index)
    state_.selectedAvatar = Clamp(index or 1, 1, #AVATARS)
    SaveLocalProfile()
    NotifyChanged()
end

function PlayerSystem.GetSaveData()
    return {
        customNickname = state_.customNickname,
        selectedAvatar = state_.selectedAvatar,
    }
end

function PlayerSystem.LoadSaveData(data)
    if data == nil then return end
    state_.customNickname = TrimName(data.customNickname or state_.customNickname)
    state_.selectedAvatar = Clamp(tonumber(data.selectedAvatar or state_.selectedAvatar) or 1, 1, #AVATARS)
    SaveLocalProfile()
    NotifyChanged()
end

return PlayerSystem
