-- ============================================================================
-- 钱包系统 (Wallet System)
-- Grow A Garden
-- ============================================================================
-- 管理金币余额、收入与支出。后续多货币、折扣、流水统计可在这里扩展。
-- ============================================================================

local WalletSystem = {}

local balance_ = 0

function WalletSystem.Init(startMoney)
    balance_ = startMoney or 0
end

function WalletSystem.GetBalance()
    return balance_
end

function WalletSystem.CanAfford(cost)
    return balance_ >= (cost or 0)
end

function WalletSystem.Spend(cost)
    cost = cost or 0
    if balance_ < cost then
        return false
    end
    balance_ = balance_ - cost
    return true
end

function WalletSystem.Add(amount)
    amount = amount or 0
    if amount <= 0 then return 0 end
    balance_ = balance_ + amount
    return amount
end

function WalletSystem.GetSaveData()
    return {
        balance = balance_,
    }
end

function WalletSystem.LoadSaveData(data)
    if data == nil then return end
    balance_ = math.max(0, tonumber(data.balance or balance_) or balance_)
end

return WalletSystem
