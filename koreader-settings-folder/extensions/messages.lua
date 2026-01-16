
local require = require

local Font = require("extensions/modules/font")
local KOR = require("extensions/kor")
local Notification = require("extensions/widgets/notification")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_text = has_text
local tostring = tostring

--- @class Messages
local Messages = WidgetContainer:extend{
    patience_message = nil,
}

function Messages:cancelPatience(message)
    if self.patience_message then
        UIManager:close(self.patience_message)
        self.patience_message = nil
    end
    if has_text(message) then
        KOR.dialogs:alertInfo(message)
    end
end

--* timeout 0 lets the notification remain on the screen:
function Messages:notify(message, timeout, dont_inhibit_input, at_right_top)
    message = tostring(message)

    if not KOR.registry:getOnce("notify_case_sensitive") then
        message = message:lower()
    end

    --* to prevent inadvertent cancellation of the notification because of a hold action:
    if not dont_inhibit_input then
        KOR.system:inhibitInputOnHold()
    end
    if not timeout then
        timeout = 2
    end
    local face
    if DX.s.is_mobile_device then
        face = Font:getFace("x_smallinfofont", 26)
    else
        face = at_right_top and Font:getFace("x_smallinfofont", 12) or Font:getFace("x_smallinfofont")
    end

    local notification = Notification:new{
        face = face,
        at_right_top = at_right_top,
        text = message,
        timeout = timeout,
        modal = KOR.registry:getOnce("modal"),
    }
    --* prevent app not responding messages under Android?:
    Trapper:wrap(function()
        UIManager:show(notification)
    end)
    return notification
end

function Messages:notifyPatience(message)
    --* arg 0 = let the notificaton remain on screen; remove with ((cancelPatience)):
    if message then
        self.patience_message = self:notify(message, 0)
    else
        self.patience_message = self:notify("even geduld a.u.b...", 0)
    end
    return self.patience_message
end

return Messages
