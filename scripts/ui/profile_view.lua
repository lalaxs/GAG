-- ============================================================================
-- 玩家资料 UI 视图 (Profile View)
-- Grow A Garden
-- ============================================================================
-- 头像入口、个人名片、昵称修改弹窗与头像修改弹窗。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Format = require("utils.format")
local ModalAnim = require("ui.modal_anim")

local ProfileView = {}

local deps_ = {}
local profileModal_ = nil
local nicknameModal_ = nil
local avatarModal_ = nil
local nicknameDraft_ = ""

local RARITY_COLORS = {
    ["普通"] = {132, 126, 110, 255},
    ["罕见"] = {78, 172, 110, 255},
    ["稀有"] = {80, 135, 225, 255},
    ["史诗"] = {155, 105, 210, 255},
    ["传奇"] = {224, 142, 48, 255},
}

function ProfileView.Init(deps)
    deps_ = deps or {}
end

function ProfileView.IsOpen()
    return profileModal_ ~= nil or nicknameModal_ ~= nil or avatarModal_ ~= nil
end

local function GetLevel()
    if deps_.getLevel then return deps_.getLevel() end
    return 1
end

local function GetExp()
    if deps_.getExp then return deps_.getExp() end
    return 0
end

local function GetExpToNextLevel()
    if deps_.getExpToNextLevel then return deps_.getExpToNextLevel() end
    return 1
end

local function GetExpProgress()
    local need = math.max(1, GetExpToNextLevel())
    return Clamp(GetExp() / need, 0, 1)
end

local function GetTourValue()
    if deps_.getTourValue then return deps_.getTourValue() end
    return 0
end

local function GetBestTourValue()
    if deps_.getBestTourValue then return deps_.getBestTourValue() end
    return GetTourValue()
end

local function GetUserId()
    if deps_.getUserId then return deps_.getUserId() end
    return nil
end

local function GetDisplayName()
    if deps_.getDisplayName then return deps_.getDisplayName() end
    return "Tap玩家"
end

local function GetAvatars()
    if deps_.getAvatars then return deps_.getAvatars() end
    return {}
end

local function GetSelectedAvatarIndex()
    if deps_.getSelectedAvatarIndex then return deps_.getSelectedAvatarIndex() end
    return 1
end

local function GetSelectedAvatar()
    if deps_.getSelectedAvatar then return deps_.getSelectedAvatar() end
    return { name = "胡萝卜", rarity = "普通", image = "image/plants/plants (1).png", color = {255, 150, 80, 255} }
end

local function GetRarityColor(rarity)
    return RARITY_COLORS[rarity or "普通"] or RARITY_COLORS["普通"]
end

local function BuildAvatarFace(size, avatar)
    avatar = avatar or GetSelectedAvatar()
    return UI.Panel {
        width = size,
        height = size,
        overflow = "visible",
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = size,
                height = size,
                borderRadius = math.floor(size / 2),
                backgroundColor = avatar.color or {112, 190, 118, 255},
                borderWidth = 4,
                borderColor = {255, 252, 235, 255},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = math.floor(size * 0.78),
                        height = math.floor(size * 0.78),
                        backgroundImage = avatar.image,
                        backgroundFit = "contain",
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                right = -4,
                bottom = -4,
                minWidth = math.floor(size * 0.42),
                height = math.floor(size * 0.30),
                paddingLeft = 6,
                paddingRight = 6,
                borderRadius = math.floor(size * 0.15),
                backgroundColor = {78, 172, 110, 255},
                borderWidth = 3,
                borderColor = {255, 252, 235, 255},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "LV" .. GetLevel(),
                        fontSize = math.max(10, math.floor(size * 0.16)),
                        fontWeight = "bold",
                        fontColor = {255, 255, 255, 255},
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

local function BuildExpBar(height)
    return UI.Panel {
        height = height or 10,
        borderRadius = math.floor((height or 10) / 2),
        backgroundColor = {226, 214, 186, 220},
        children = {
            UI.Panel {
                width = tostring(math.floor(GetExpProgress() * 100)) .. "%",
                height = height or 10,
                borderRadius = math.floor((height or 10) / 2),
                backgroundColor = {78, 172, 110, 255},
            },
        },
    }
end

local function BuildModifyButton(onClick)
    return UI.Button {
        text = "修改",
        width = 58,
        height = 30,
        fontSize = 13,
        fontWeight = "bold",
        backgroundColor = {78, 172, 110, 255},
        fontColor = {255, 255, 255, 255},
        borderRadius = 14,
        onClick = onClick,
    }
end

local function BuildInfoLine(label, value)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                fontColor = {118, 92, 65, 230},
            },
            UI.Label {
                text = value,
                fontSize = 14,
                fontWeight = "bold",
                fontColor = {76, 58, 40, 255},
                textAlign = "right",
            },
        },
    }
end

local function BuildAvatarCard(index, avatar)
    local selected = index == GetSelectedAvatarIndex()
    return UI.Panel {
        width = "31%",
        minHeight = 114,
        paddingTop = 8,
        paddingBottom = 8,
        paddingLeft = 6,
        paddingRight = 6,
        alignItems = "center",
        gap = 5,
        borderRadius = 18,
        backgroundColor = selected and {232, 248, 224, 255} or {255, 250, 236, 245},
        borderWidth = selected and 3 or 2,
        borderColor = selected and {78, 172, 110, 255} or {224, 196, 150, 190},
        onClick = function()
            if deps_.selectAvatar then deps_.selectAvatar(index) end
            if deps_.showToast then deps_.showToast("已切换头像: " .. (avatar.name or "头像")) end
            if avatarModal_ ~= nil then
                avatarModal_:Close()
                avatarModal_ = nil
            end
            ProfileView.RebuildProfileContent()
        end,
        children = {
            BuildAvatarFace(selected and 58 or 52, avatar),
            UI.Label {
                text = avatar.name or "头像",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = {80, 62, 44, 255},
                textAlign = "center",
            },
            UI.Panel {
                minWidth = 42,
                height = 20,
                paddingLeft = 6,
                paddingRight = 6,
                borderRadius = 10,
                backgroundColor = selected and {78, 172, 110, 255} or GetRarityColor(avatar.rarity),
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = selected and "使用中" or (avatar.rarity or "普通"),
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = {255, 255, 255, 255},
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

function ProfileView.RebuildProfileContent()
    if profileModal_ == nil then return end
    profileModal_:ClearContent()
    local selectedAvatar = GetSelectedAvatar()
    local userId = GetUserId()

    profileModal_:AddContent(UI.Panel {
        gap = 12,
        children = {
            UI.Panel {
                paddingTop = 14,
                paddingBottom = 14,
                paddingLeft = 14,
                paddingRight = 14,
                borderRadius = 24,
                backgroundColor = {249, 226, 180, 255},
                borderWidth = 2,
                borderColor = {226, 188, 126, 220},
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 104,
                                alignItems = "center",
                                gap = 8,
                                children = {
                                    BuildAvatarFace(92, selectedAvatar),
                                    UI.Button {
                                        text = "修改",
                                        width = 72,
                                        height = 28,
                                        fontSize = 13,
                                        fontWeight = "bold",
                                        backgroundColor = {132, 126, 110, 255},
                                        fontColor = {255, 255, 255, 255},
                                        borderRadius = 14,
                                        onClick = function()
                                            ProfileView.OpenAvatarPage()
                                        end,
                                    },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                flexShrink = 1,
                                gap = 8,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 8,
                                        children = {
                                            UI.Label {
                                                text = "Lv." .. GetLevel() .. "  " .. GetDisplayName(),
                                                fontSize = 20,
                                                fontWeight = "bold",
                                                fontColor = {70, 50, 34, 255},
                                                flexGrow = 1,
                                                flexShrink = 1,
                                            },
                                            BuildModifyButton(function()
                                                ProfileView.OpenNicknameEditor()
                                            end),
                                        },
                                    },
                                    BuildExpBar(12),
                                    UI.Label {
                                        text = string.format("经验 %d / %d", GetExp(), GetExpToNextLevel()),
                                        fontSize = 12,
                                        fontColor = {94, 74, 54, 235},
                                    },
                                    UI.Panel {
                                        height = 1,
                                        backgroundColor = {226, 188, 126, 180},
                                    },
                                    BuildInfoLine("Tap ID", userId ~= nil and tostring(userId) or "未登录"),
                                },
                            },
                        },
                    },
                },
            },
            UI.Panel {
                paddingTop = 12,
                paddingBottom = 12,
                paddingLeft = 14,
                paddingRight = 14,
                borderRadius = 20,
                backgroundColor = {255, 250, 236, 245},
                borderWidth = 2,
                borderColor = {224, 199, 158, 170},
                gap = 8,
                children = {
                    BuildInfoLine("当前花园观光值", Format.Gold(GetTourValue())),
                    BuildInfoLine("历史最高观光值", Format.Gold(GetBestTourValue())),
                },
            },
        },
    })
end

function ProfileView.SaveNickname()
    if deps_.setNickname then
        local savedName = deps_.setNickname(nicknameDraft_)
        nicknameDraft_ = savedName or nicknameDraft_
    end
    if deps_.showToast then deps_.showToast("昵称已更新") end
    if nicknameModal_ ~= nil then
        nicknameModal_:Close()
        nicknameModal_ = nil
    end
    ProfileView.RebuildProfileContent()
end

function ProfileView.OpenProfile()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
    if profileModal_ ~= nil then profileModal_:Close() end

    profileModal_ = UI.Modal {
        title = "我的名片",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {12, 16, 18, 16},
        contentGap = 10,
        onClose = function()
            profileModal_ = nil
            if deps_.rebuildUI then deps_.rebuildUI() end
        end,
    }

    ProfileView.RebuildProfileContent()
    ModalAnim.Apply(profileModal_, { fixedHeight = 560 })
    profileModal_:Open()
end

function ProfileView.OpenNicknameEditor()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
    if nicknameModal_ ~= nil then nicknameModal_:Close() end
    nicknameDraft_ = GetDisplayName()

    nicknameModal_ = UI.Modal {
        title = "修改昵称",
        size = "sm",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {16, 20, 18, 20},
        onClose = function()
            nicknameModal_ = nil
        end,
    }

    nicknameModal_:AddContent(UI.Panel {
        gap = 14,
        children = {
            UI.Label {
                text = "输入新的玩家昵称",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = {76, 58, 40, 255},
            },
            UI.TextField {
                value = nicknameDraft_,
                placeholder = "请输入昵称",
                height = 44,
                maxLength = 12,
                fontSize = 16,
                borderRadius = 16,
                backgroundColor = {255, 252, 242, 255},
                borderColor = {216, 190, 146, 230},
                focusedBorderColor = {78, 172, 110, 255},
                onChange = function(_, value)
                    nicknameDraft_ = value or ""
                end,
                onSubmit = function()
                    ProfileView.SaveNickname()
                end,
            },
            UI.Panel {
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "保存修改",
                        width = 128,
                        height = 44,
                        fontSize = 16,
                        fontWeight = "bold",
                        variant = "primary",
                        borderRadius = 18,
                        onClick = function()
                            ProfileView.SaveNickname()
                        end,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(nicknameModal_, { fixedHeight = 260 })
    nicknameModal_:Open()
end

function ProfileView.OpenAvatarPage()
    if deps_.suppressWorldTap then deps_.suppressWorldTap() end
    if avatarModal_ ~= nil then avatarModal_:Close() end

    local cards = {}
    for i, avatar in ipairs(GetAvatars()) do
        table.insert(cards, BuildAvatarCard(i, avatar))
    end

    avatarModal_ = UI.Modal {
        title = "修改头像",
        size = "md",
        closeOnOverlay = true,
        showCloseButton = true,
        contentPadding = {14, 18, 18, 18},
        onClose = function()
            avatarModal_ = nil
        end,
    }

    avatarModal_:AddContent(UI.Panel {
        gap = 12,
        children = {
            UI.Label {
                text = "选择一个作物作为头像",
                fontSize = 14,
                fontColor = {118, 92, 65, 225},
                textAlign = "center",
            },
            UI.ScrollView {
                height = 390,
                scrollY = true,
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 8,
                        children = cards,
                    },
                },
            },
        },
    })

    ModalAnim.Apply(avatarModal_, { fixedHeight = 560 })
    avatarModal_:Open()
end

function ProfileView.Close()
    if profileModal_ ~= nil then
        profileModal_:Close()
        profileModal_ = nil
    end
    if nicknameModal_ ~= nil then
        nicknameModal_:Close()
        nicknameModal_ = nil
    end
    if avatarModal_ ~= nil then
        avatarModal_:Close()
        avatarModal_ = nil
    end
end

function ProfileView.BuildHudAvatar()
    local avatar = GetSelectedAvatar()
    return UI.Panel {
        width = 220,
        height = 78,
        flexDirection = "row",
        alignItems = "center",
        gap = 10,
        paddingLeft = 9,
        paddingRight = 14,
        paddingTop = 8,
        paddingBottom = 8,
        backgroundColor = {255, 250, 240, 245},
        borderRadius = 24,
        borderWidth = 2,
        borderColor = {226, 204, 165, 210},
        overflow = "visible",
        onClick = function()
            ProfileView.OpenProfile()
        end,
        children = {
            BuildAvatarFace(58, avatar),
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 3,
                children = {
                    UI.Label {
                        text = GetDisplayName(),
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = {70, 55, 38, 255},
                    },
                    BuildExpBar(8),
                    UI.Label {
                        text = string.format("经验 %d/%d", GetExp(), GetExpToNextLevel()),
                        fontSize = 10,
                        fontColor = {130, 108, 82, 220},
                    },
                },
            },
        },
    }
end

return ProfileView
