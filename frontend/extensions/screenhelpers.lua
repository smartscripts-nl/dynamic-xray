
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

--- @class ScreenHelpers
local ScreenHelpers = WidgetContainer:extend{}

function ScreenHelpers:isLandscapeScreen()
    return Screen:getScreenMode() == "landscape"
end

function ScreenHelpers:isPortraitScreen()
    return Screen:getScreenMode() == "portrait"
end

-- #((move ButtonDialogTitle to top))
--- @param moveable MovableContainer
function ScreenHelpers:moveMovableToYpos(moveable, target_y_pos)
    if not target_y_pos then
        target_y_pos = 0
    end
    moveable.dimen = moveable:getSize()

    moveable._orig_y = math.floor((Screen:getHeight() - moveable.dimen.h) / 2)
    moveable._orig_x = math.floor((Screen:getWidth() - moveable.dimen.w) / 2)

    local move_by = 0 - moveable._orig_y + target_y_pos
    moveable:_moveBy(0, move_by, "restrict_to_screen")
    end

function ScreenHelpers:refreshScreen()
    -- refresh the screen, so e.g. no shadows of dialog lines remain:
    UIManager:setDirty(nil, "full")
end

function ScreenHelpers:refreshUI()
    UIManager:setDirty(nil, function()
        return "ui", Geom:new {
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
    end)
end

return ScreenHelpers
