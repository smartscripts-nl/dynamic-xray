
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
-- ! use KOR.dialogs instead of Dialogs!
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScreenHelpers = require("extensions/screenhelpers")
local Screen = Device.screen

--- @class InfoMessage
local InfoMessage = InputContainer:extend{
    -- [...]

    move_to_top = false,
    move_to_y_pos = nil,
}

function InfoMessage:init()
    -- init KOR.dialogs (must be done here, because we show a dialog upon opening KOReader):
    KOR.dialogs = extension("dialogs")

    -- [...]

    self.movable = MovableContainer:new{
        frame, -- set by original KOReader code
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
    if not self.height then
        -- [...]
    end

    -- #((move InfoMessage to y pos))
    if self.move_to_top then
        ScreenHelpers:moveMovableToYpos(self.movable, 0)
    elseif self.move_to_y_pos then
        ScreenHelpers:moveMovableToYpos(self.movable, self.move_to_y_pos)
    end

    if self.show_delay then
        -- Don't have UIManager setDirty us yet
        self.invisible = true
    end
end

-- [...]

return InfoMessage
