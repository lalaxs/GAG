local EventBus = require("utils.event_bus")
local UIEvents = require("utils.ui_events")

local ModalRegistry = {}

local entries_ = {}

function ModalRegistry.Register(name, isOpen)
    if name == nil or isOpen == nil then return end
    entries_[name] = isOpen
end

function ModalRegistry.Unregister(name)
    entries_[name] = nil
end

function ModalRegistry.AnyOpen()
    for _, isOpen in pairs(entries_) do
        if isOpen() then return true end
    end
    return false
end

function ModalRegistry.NotifyClosed()
    EventBus.Emit(UIEvents.MODAL_CLOSED)
end

return ModalRegistry
