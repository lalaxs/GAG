-- ============================================================================
-- 数值格式化工具 (Format Utils)
-- Grow A Garden
-- ============================================================================

local Format = {}

--- 格式化大数字：超过1万显示K，超过100万显示M
---@param value number
---@return string
function Format.Gold(value)
    if value == nil then return "0" end
    if value < 0 then return "-" .. Format.Gold(-value) end

    if value >= 1000000 then
        local m = value / 1000000
        if m >= 10 then
            return string.format("%dM", math.floor(m))
        else
            return string.format("%.1fM", m)
        end
    elseif value >= 10000 then
        local k = value / 1000
        if k >= 100 then
            return string.format("%dK", math.floor(k))
        elseif k >= 10 then
            return string.format("%dK", math.floor(k))
        else
            return string.format("%.1fK", k)
        end
    else
        return tostring(math.floor(value))
    end
end

return Format
