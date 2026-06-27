local EventBus = {}

local listeners_ = {}

function EventBus.On(eventName, handler)
    if eventName == nil or handler == nil then return nil end
    local list = listeners_[eventName]
    if list == nil then
        list = {}
        listeners_[eventName] = list
    end
    list[#list + 1] = handler
    return function()
        EventBus.Off(eventName, handler)
    end
end

function EventBus.Off(eventName, handler)
    local list = listeners_[eventName]
    if list == nil then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            return
        end
    end
end

function EventBus.Emit(eventName, payload)
    local list = listeners_[eventName]
    if list == nil then return end
    local snapshot = {}
    for i, handler in ipairs(list) do
        snapshot[i] = handler
    end
    for _, handler in ipairs(snapshot) do
        handler(payload)
    end
end

return EventBus
