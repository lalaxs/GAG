-- ============================================================================
-- 游戏存档系统 (Game Save System)
-- Grow A Garden
-- ============================================================================
-- 统一负责整局游戏进度的本地读写。玩家名片资料仍由 PlayerSystem 独立保存，
-- 清除游戏存档不会清除 Tap 昵称、自定义昵称和头像选择。
-- ============================================================================

local SaveSystem = {}

local SAVE_PATH = "game_save.json"
local SAVE_VERSION = 1

local function ReadAllText(path)
    if fileSystem == nil or not fileSystem:FileExists(path) then
        return nil
    end
    local file = File(path, FILE_READ)
    if file == nil or not file:IsOpen() then
        return nil
    end
    local raw = file:ReadString()
    file:Close()
    return raw
end

local function WriteAllText(path, text)
    local file = File(path, FILE_WRITE)
    if file == nil or not file:IsOpen() then
        print("[存档] 写入失败：无法打开 " .. path)
        return false
    end
    file:WriteString(text or "")
    file:Close()
    return true
end

function SaveSystem.Load()
    local raw = ReadAllText(SAVE_PATH)
    if raw == nil or raw == "" then
        print("[存档] 未找到游戏存档，创建新档")
        return nil, false
    end

    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then
        print("[存档] 游戏存档解析失败，创建新档")
        return nil, false
    end
    if data.cleared == true then
        print("[存档] 存档已标记清除，创建新档")
        return nil, false
    end

    print("[存档] 已读取游戏存档 version=" .. tostring(data.version or 0))
    return data, true
end

function SaveSystem.Save(data)
    if type(data) ~= "table" then return false end
    data.version = SAVE_VERSION
    data.savedAt = os and os.time and os.time() or 0

    local ok, encoded = pcall(cjson.encode, data)
    if not ok or encoded == nil then
        print("[存档] 序列化失败")
        return false
    end

    local written = WriteAllText(SAVE_PATH, encoded)
    if written then
        print("[存档] 游戏进度已保存")
    end
    return written
end

function SaveSystem.Clear()
    local ok, encoded = pcall(cjson.encode, {
        version = SAVE_VERSION,
        cleared = true,
        savedAt = os and os.time and os.time() or 0,
    })
    if not ok or encoded == nil then return false end
    local written = WriteAllText(SAVE_PATH, encoded)
    if written then
        print("[存档] 游戏存档已清除")
    end
    return written
end

return SaveSystem
