-- ============================================================================
-- 商店系统门面 (Shop Facade)
-- Grow A Garden - 种子商店 & 工具商店
-- ============================================================================

local SeedShopSystem = require("systems.seed_shop_system")
local ShopView = require("ui.shop_view")

local Shop = {}

function Shop.Init(opts)
    SeedShopSystem.Init(opts)
    ShopView.Init({
        system = SeedShopSystem,
        onRebuild = function()
            ShopView.RebuildShopContent()
        end,
    })
end

function Shop.Open()
    ShopView.Open()
end

function Shop.Close()
    ShopView.Close()
end

function Shop.Update(dt)
    local refreshFlags = SeedShopSystem.UpdateLogic(dt)
    ShopView.UpdatePresentation(dt, refreshFlags)
end

function Shop.IsOpen()
    return ShopView.IsOpen()
end

function Shop.SetAdTickets(count)
    SeedShopSystem.SetAdTickets(count)
end

function Shop.GetAdTickets()
    return SeedShopSystem.GetAdTickets()
end

function Shop.CreateEntryButton(opts)
    return ShopView.CreateEntryButton(opts)
end

function Shop.ApplyServerSeedShop(data)
    if SeedShopSystem.ApplyServerSeedShop(data) then
        ShopView.RefreshAfterServerSync()
        return true
    end
    return false
end

function Shop.RebuildShopContent()
    ShopView.RebuildShopContent()
end

return Shop
