-- ============================================================================
-- 游戏存档系统 (Game Save System)
-- Grow A Garden
-- ============================================================================
-- 统一负责整局游戏进度的本地读写，并在 WASM/预览环境下使用 clientCloud 作为持久化兜底。
-- 玩家名片资料仍由 PlayerSystem 独立保存，清除游戏存档不会清除 Tap 昵称、自定义昵称和头像选择。
-- ============================================================================

local SaveSystem = {}

local SAVE_PATH = "game_save.json"
local CLOUD_SAVE_KEY = "game_save"
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

local function NormalizeLoadedData(data, source)
    if type(data) ~= "table" then
        return nil, false
    end
    if data.cleared == true then
        print("[存档] " .. source .. "存档已标记清除，创建新档")
        return nil, false
    end
    print("[存档] 已读取" .. source .. "游戏存档 version=" .. tostring(data.version or 0))
    return data, true
end

local function DecodeSave(raw, source)
    if raw == nil or raw == "" then return nil, false end
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then
        print("[存档] " .. source .. "游戏存档解析失败，创建新档")
        return nil, false
    end
    return NormalizeLoadedData(data, source)
end

function SaveSystem.Load()
    local data, ok = DecodeSave(ReadAllText(SAVE_PATH), "本地")
    if ok then return data, true end
    print("[存档] 未找到本地游戏存档，等待云端存档")
    return nil, false
end

function SaveSystem.LoadCloud(callbacks)
    callbacks = callbacks or {}
    if clientCloud == nil then
        if callbacks.miss then callbacks.miss() end
        return false
    end
    clientCloud:Get(CLOUD_SAVE_KEY, {
        ok = function(values, _iscores)
            local data, ok = NormalizeLoadedData(values and values[CLOUD_SAVE_KEY], "云端")
            if ok then
                local encodedOk, encoded = pcall(cjson.encode, data)
                if encodedOk and encoded ~= nil then
                    WriteAllText(SAVE_PATH, encoded)
                end
                if callbacks.ok then callbacks.ok(data) end
            else
                print("[存档] 未找到云端游戏存档，创建新档")
                if callbacks.miss then callbacks.miss() end
            end
        end,
        error = function(_code, reason)
            print("[存档] 云端读取失败: " .. tostring(reason))
            if callbacks.error then callbacks.error(reason) end
        end,
        timeout = function()
            print("[存档] 云端读取超时")
            if callbacks.error then callbacks.error("timeout") end
        end,
    })
    return true
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

    if clientCloud ~= nil then
        clientCloud:Set(CLOUD_SAVE_KEY, data, {
            ok = function()
                print("[存档] 游戏进度已同步云端")
            end,
            error = function(_code, reason)
                print("[存档] 云端保存失败: " .. tostring(reason))
            end,
            timeout = function()
                print("[存档] 云端保存超时")
            end,
        })
    end

    return written or clientCloud ~= nil
end

function SaveSystem.Clear()
    local payload = {
        version = SAVE_VERSION,
        cleared = true,
        savedAt = os and os.time and os.time() or 0,
    }
    local ok, encoded = pcall(cjson.encode, payload)
    if not ok or encoded == nil then return false end
    local written = WriteAllText(SAVE_PATH, encoded)
    local verified = false
    if written then
        local raw = ReadAllText(SAVE_PATH)
        local decodeOk, decoded = pcall(cjson.decode, raw or "")
        verified = decodeOk and type(decoded) == "table" and decoded.cleared == true
        if verified then
            print("[存档] 游戏存档已清除并验证")
        else
            print("[存档] 游戏存档清除验证失败")
        end
    end
    if clientCloud ~= nil then
        clientCloud:Set(CLOUD_SAVE_KEY, payload, {
            ok = function() print("[存档] 云端游戏存档已清除") end,
            error = function(_code, reason) print("[存档] 云端清除失败: " .. tostring(reason)) end,
        })
    end
    return verified or clientCloud ~= nil
end

return SaveSystem
