-- ============================================================================
-- 排行榜条目校验（仅过滤展示，读取时不写 cloud）
-- ============================================================================
-- 过滤无效 UID、观光/点赞榜无花园快照头像的幽灵条目。
-- 不在读取时 ScoreDeleteInt，避免误删真实上榜数据。
-- ============================================================================

local UserId = require("utils.user_id")
local SocialProfile = require("server.social_profile")

local LeaderboardSanitize = {}

function LeaderboardSanitize.HasValidAvatar(avatar)
    if type(avatar) ~= "table" then return false end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    local image = avatar.image
    return plantIndex ~= nil or (image ~= nil and image ~= "")
end

function LeaderboardSanitize.IsDefaultAvatar(avatar)
    if type(avatar) ~= "table" then return true end
    local plantIndex = tonumber(avatar.plantIndex or avatar.selectedAvatar or avatar.index)
    if plantIndex ~= nil then return math.floor(plantIndex) == 1 end
    local image = tostring(avatar.image or "")
    return image == "" or image == "image/plants/plants (1).png"
end

function LeaderboardSanitize.HasDefaultProfile(entry)
    if type(entry) ~= "table" then return true end
    return SocialProfile.IsPlaceholderNickname(entry.nickname)
        and LeaderboardSanitize.IsDefaultAvatar(entry.avatar)
end

function LeaderboardSanitize.ResolveRankUserId(item)
    if type(item) ~= "table" then return nil end
    return UserId.Normalize(item.userId or item.player)
end

function LeaderboardSanitize.EnrichEntry(entry, requesterUid, profileMap, nickMap)
    SocialProfile.ApplyDisplayProfile(entry, entry.userId, profileMap, nickMap, entry.nickname)
    entry.isMe = UserId.Same(entry.userId, requesterUid)
    return entry
end

function LeaderboardSanitize.ShouldHideEntry(entry, options)
    options = options or {}
    if UserId.Normalize(entry.userId) == nil then
        return true, "invalid_uid"
    end
    if entry.isMe == true then
        return false, nil
    end
    if options.hideDefaultProfile == true and LeaderboardSanitize.HasDefaultProfile(entry) then
        return true, "default_profile"
    end
    if options.requireAvatar == true and LeaderboardSanitize.HasValidAvatar(entry.avatar) ~= true then
        return true, "missing_avatar"
    end
    if options.hideUnresolved == true and SocialProfile.IsUnresolvedDisplay(entry) then
        return true, "unresolved_display"
    end
    return false, nil
end

local function SanitizeOptionsForKind(kind)
    kind = tostring(kind or "")
    local requireAvatar = kind == "tour" or kind == "like"
    return {
        kind = kind,
        requireAvatar = requireAvatar,
        hideUnresolved = requireAvatar,
        hideDefaultProfile = true,
    }
end

--- 过滤榜单展示条目（不写 cloud）。
---@param requesterUid any
---@param entries table
---@param profileMap table
---@param nickMap table|nil
---@param kindOrOptions string|table|nil
---@return table filtered
function LeaderboardSanitize.FilterForDisplay(requesterUid, entries, profileMap, nickMap, kindOrOptions)
    entries = entries or {}
    profileMap = profileMap or {}
    local options = type(kindOrOptions) == "table" and kindOrOptions or SanitizeOptionsForKind(kindOrOptions)
    local filtered = {}
    local rankSeen = {}

    for _, entry in ipairs(entries) do
        LeaderboardSanitize.EnrichEntry(entry, requesterUid, profileMap, nickMap)
        local canonical = UserId.Normalize(entry.userId)
        local shouldHide, reason = LeaderboardSanitize.ShouldHideEntry(entry, options)

        if shouldHide then
            if reason == "invalid_uid" then
                print("[排行榜] 隐藏无效 UID 条目 uid=" .. tostring(entry.userId))
            elseif reason == "default_profile" then
                print(string.format("[排行榜] 隐藏默认资料条目 uid=%s", tostring(canonical or entry.userId)))
            elseif reason == "unresolved_display" then
                print(string.format("[排行榜] 隐藏未解析资料条目 uid=%s", tostring(canonical or entry.userId)))
            else
                print(string.format("[排行榜] 隐藏无头像条目 uid=%s nickname=%s", tostring(canonical or entry.userId), tostring(entry.nickname)))
            end
        elseif canonical ~= nil and rankSeen[canonical] == true then
            print("[排行榜] 隐藏重复 UID 条目 uid=" .. tostring(canonical))
        else
            if canonical ~= nil then
                rankSeen[canonical] = true
            end
            filtered[#filtered + 1] = entry
        end
    end

    for index, entry in ipairs(filtered) do
        entry.rank = index
    end

    return filtered
end

-- 兼容旧调用名
LeaderboardSanitize.FilterAndPurge = LeaderboardSanitize.FilterForDisplay

return LeaderboardSanitize
