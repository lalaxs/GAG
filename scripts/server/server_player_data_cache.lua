-- ============================================================================
-- 服务端玩家数据短 TTL 缓存
-- Grow A Garden
-- ============================================================================
-- 目的：降低同一玩家连续播种/收获时对 ECONOMY_STATE / AUTH_FARM_STATE 的重复云读。
-- 这是短事务缓存，不是长期 session；成功写回云端后同步刷新缓存。
-- ============================================================================

local ServerCloudStore = require("server.server_cloud_store")

local ServerPlayerDataCache = {}

local deps_ = {}
local cache_ = {}

local ECONOMY_TTL = 3.0
local FARM_TTL = 3.0

local function Now()
    if deps_.Now ~= nil then return deps_.Now() end
    return os and os.time and os.time() or 0
end

local function CacheKey(uid)
    return tostring(ServerCloudStore.GetCanonicalUidKey(uid) or uid or "unknown")
end

local function Entry(uid)
    local key = CacheKey(uid)
    local entry = cache_[key]
    if entry == nil then
        entry = {}
        cache_[key] = entry
    end
    return entry
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return copy
end

local function IsFresh(stamp, ttl)
    return stamp ~= nil and Now() - stamp <= ttl
end

function ServerPlayerDataCache.Init(deps)
    deps_ = deps or {}
end

function ServerPlayerDataCache.Invalidate(uid)
    cache_[CacheKey(uid)] = nil
end

function ServerPlayerDataCache.SetEconomy(uid, state)
    if type(state) ~= "table" then return end
    local entry = Entry(uid)
    entry.economy = DeepCopy(state)
    entry.economyAt = Now()
end

function ServerPlayerDataCache.SetFarm(uid, farm)
    if type(farm) ~= "table" then return end
    local entry = Entry(uid)
    entry.farm = DeepCopy(farm)
    entry.farmAt = Now()
end

function ServerPlayerDataCache.Set(uid, state, farm)
    ServerPlayerDataCache.SetEconomy(uid, state)
    ServerPlayerDataCache.SetFarm(uid, farm)
end

function ServerPlayerDataCache.GetEconomy(uid, readFn, done)
    local entry = Entry(uid)
    if type(entry.economy) == "table" and IsFresh(entry.economyAt, ECONOMY_TTL) then
        done(DeepCopy(entry.economy), true, false)
        return
    end
    readFn(function(state, hadReadError, meta)
        if type(state) == "table" then
            ServerPlayerDataCache.SetEconomy(uid, state)
            done(DeepCopy(state), false, hadReadError == true, meta)
            return
        end
        if type(entry.economy) == "table" then
            print("[玩家缓存] 经济云读失败，使用短缓存 uid=" .. tostring(CacheKey(uid)))
            done(DeepCopy(entry.economy), true, true, meta)
            return
        end
        done(nil, false, hadReadError == true, meta)
    end)
end

function ServerPlayerDataCache.GetFarm(uid, readFn, done)
    local entry = Entry(uid)
    if type(entry.farm) == "table" and IsFresh(entry.farmAt, FARM_TTL) then
        done(DeepCopy(entry.farm), true, false)
        return
    end
    readFn(function(farm, hadReadError, meta)
        if type(farm) == "table" then
            ServerPlayerDataCache.SetFarm(uid, farm)
            done(DeepCopy(farm), false, hadReadError == true, meta)
            return
        end
        if type(entry.farm) == "table" then
            print("[玩家缓存] 农场云读失败，使用短缓存 uid=" .. tostring(CacheKey(uid)))
            done(DeepCopy(entry.farm), true, true, meta)
            return
        end
        done(nil, false, hadReadError == true, meta)
    end)
end

return ServerPlayerDataCache
