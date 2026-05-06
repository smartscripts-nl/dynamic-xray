
local require = require

local Geom = require("ui/geometry")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local DX = DX

--- @class ScreenHelpers
local ScreenHelpers = WidgetContainer:extend{}

function ScreenHelpers:isLandscapeScreen()
    return Screen:getScreenMode() == "landscape"
end

function ScreenHelpers:isPortraitScreen()
    return Screen:getScreenMode() == "portrait"
end

function ScreenHelpers:refreshDialog()
    --* refresh dialog, so e.g. no shadows of dialog lines remain:
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

function ScreenHelpers:getHorizontalSpacerWidth(fullscreen, for_close_button)
    if DX.s.is_mobile_device then
        return Size.padding.fullscreen
    end
    if for_close_button and fullscreen then
        return Size.padding.buttonvertical
    end

    return Size.padding.titlebar
end

return ScreenHelpers
