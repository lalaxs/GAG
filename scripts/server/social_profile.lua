-- ============================================================================
-- 社交/排行榜玩家资料查找（服务端）
-- ============================================================================

local UserId = require("utils.user_id")

local SocialProfile = {}

local PLACEHOLDER_NICKNAME = "Tap玩家"

function SocialProfile.IsPlaceholderNickname(nickname)
    nickname = tostring(nickname or "")
    if nickname == "" then return true end
    return nickname == PLACEHOLDER_NICKNAME
end

function SocialProfile.HasDisplayAvatar(avatar)
    if type(avatar) ~= "table" then return false end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    local image = avatar.image
    return plantIndex ~= nil or (image ~= nil and image ~= "")
end

function SocialProfile.IsProfileForUser(profile, userId)
    if type(profile) ~= "table" then return false end
    if profile.userId == nil then return false end
    return UserId.Same(profile.userId, userId)
end

function SocialProfile.IsUnresolvedDisplay(entry)
    if type(entry) ~= "table" then return true end
    return SocialProfile.IsPlaceholderNickname(entry.nickname)
        and SocialProfile.HasDisplayAvatar(entry.avatar) ~= true
end

function SocialProfile.LookupProfile(profileMap, userId)
    if type(profileMap) ~= "table" then return nil end
    local canonical = UserId.Normalize(userId)
    if canonical ~= nil then
        local profile = profileMap[canonical]
            or profileMap[tostring(canonical)]
            or profileMap[tonumber(canonical)]
        if type(profile) == "table" then return profile end
    end
    return profileMap[userId] or profileMap[tostring(userId or "")] or profileMap[tonumber(userId)]
end

function SocialProfile.LookupNickname(nickMap, userId)
    if type(nickMap) ~= "table" then return nil end
    local canonical = UserId.Normalize(userId)
    if canonical ~= nil then
        local nickname = nickMap[canonical] or nickMap[tostring(canonical)] or nickMap[tonumber(canonical)]
        if nickname ~= nil and nickname ~= "" and not SocialProfile.IsPlaceholderNickname(nickname) then return nickname end
    end
    local nickname = nickMap[userId] or nickMap[tostring(userId or "")]
    if nickname ~= nil and nickname ~= "" and not SocialProfile.IsPlaceholderNickname(nickname) then return nickname end
    return nil
end

function SocialProfile.StoreProfile(profileMap, userId, profile)
    if type(profileMap) ~= "table" or type(profile) ~= "table" then return end
    local canonical = UserId.Normalize(userId)
    if canonical == nil then return end
    profile.userId = canonical
    profileMap[canonical] = profile
    profileMap[tostring(canonical)] = profile
    local numeric = tonumber(canonical)
    if numeric ~= nil then profileMap[numeric] = profile end
end

function SocialProfile.ApplyDisplayProfile(entry, userId, profileMap, nickMap, fallbackNickname)
    if type(entry) ~= "table" then return entry end
    userId = UserId.Normalize(userId) or userId
    if userId ~= nil then entry.userId = userId end

    local storedNickname = fallbackNickname or entry.nickname
    local storedAvatar = entry.avatar

    local rawProfile = SocialProfile.LookupProfile(profileMap, userId)
    local profile = SocialProfile.IsProfileForUser(rawProfile, userId) and rawProfile or nil
    local tapNickname = SocialProfile.LookupNickname(nickMap, userId)

    entry.nickname = tapNickname
        or (profile and profile.nickname)
        or storedNickname
        or PLACEHOLDER_NICKNAME

    if profile and type(profile.avatar) == "table" then
        entry.avatar = profile.avatar
    else
        entry.avatar = storedAvatar
    end

    entry.profileResolved = tapNickname ~= nil or profile ~= nil

    if entry.score == nil then
        entry.score = profile and profile.score or 0
    end

    return entry
end

return SocialProfile
