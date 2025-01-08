--[[--
A button widget that shows text or an icon and handles callback when tapped.

@usage
    local Button = require("ui/widget/button")
    local button = Button:new{
        text = _("Press me!"),
        enabled = false, -- defaults to true
        callback = some_callback_function,
        width = Screen:scaleBySize(50),
        max_width = Screen:scaleBySize(100),
        bordersize = Screen:scaleBySize(3),
        margin = 0,
        padding = Screen:scaleBySize(2),
    }
--]]

local InputContainer = require("ui/widget/container/inputcontainer")

--- @class Button
local Button = InputContainer:extend{
    -- [...]
}

-- [...]

function Button:_undoFeedbackHighlight(is_translucent)
    -- [...]
end

-- pos can be used for ((Dialogs#alertInfo)), to show the info alert directly below a clicked button:
-- see ((MOVE MOVABLES TO Y POSITION)) for more info:
function Button:onTapSelectButton(irr, pos)
    irr = pos
    if self.enabled or self.allow_tap_when_disabled then
        if self.callback then
            if G_reader_settings:isFalse("flash_ui") then
                self.callback(pos, self.field_no)
            else
                -- [...]

                -- Callback
                --
                self.callback(pos, self.field_no)

                -- [...]
            end

            -- [...]

        elseif self.tap_input then
            -- [...]
        end
    end

    -- [...]
end

-- [...]

return Button
