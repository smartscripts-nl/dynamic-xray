
local Font = require("ui/font")
local Notification = require("ui/widget/notification")
local System = require("extensions/system")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class Messages
local Messages = WidgetContainer:extend{}

-- timeout 0 lets the notification remain on the screen:
function Messages:notify(message, timeout, dont_inhibit_input, at_right_top)
    message = message:lower()
    -- to prevent inadvertent cancellation of the notification because of a hold action:
    if not dont_inhibit_input then
        System:inhibitInput(0.8)
    end
    if not timeout then
        timeout = 2
    end
    local notification = Notification:new{
        face = Font:getFace("x_smallinfofont"),
        at_right_top = at_right_top,
        text = message,
        timeout = timeout,
    }
    UIManager:show(notification)
    return notification
end

return Messages
