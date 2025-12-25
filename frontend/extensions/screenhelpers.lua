
local require = require

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

function ScreenHelpers:refreshDialog()
    -- refresh dialog, so e.g. no shadows of dialog lines remain:
    UIManager:setDirty(nil, "ui")
end

function ScreenHelpers:refreshScreen()
    -- refresh the screen, so e.g. no shadows of dialog lines remain:
    UIManager:setDirty(nil, "full")
end

function ScreenHelpers:refreshScreenFlash()
    -- refresh the screen with a flash, so e.g. no image shadows remain:
    UIManager:setDirty(nil, "flashui")
end

-- same as ScreenHelpers:refreshScreen(), but without flash:
function ScreenHelpers:refreshUI()
    UIManager:setDirty(nil, function()
        return "ui", Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
    end)
end


return ScreenHelpers
