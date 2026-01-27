
--* register props of an anchorbutton, with which to call and position a popup menu
--* for usage with ((MovableContainer#moveToAnchor))

local require = require

local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local DX = DX

--- @class AnchorButton
local AnchorButton = WidgetContainer:extend{
    button = nil,
    button_no = nil,
    buttons_count = nil,
    height = nil,
    parent_y = 0,
    width = nil,
}

function AnchorButton:increaseParentYposWith(elements_height)
    self.parent_y = self.parent_y + elements_height
end

function AnchorButton:setAnchorButtonFromPopupMenuHeight(popup_menu_height)
    local parent_y = self.parent_y - (self.buttons_count - 1) * self.height
    local x = self.button_no * self.width
    --* Ubuntu is a bit wacky with handling positions:
    if DX.s.is_ubuntu then
        --* Size.line.medium is the width of the separator lines in the ButtonTable:
        x = x - self.button_no * Size.line.medium
    end
    local correction_factor = DX.s.is_ubuntu and 1 or 2

    --* this computed "button" will be used as anchor point by ((MovableContainer#moveToAnchor)):
    self.button = {
        x = x,
        y = parent_y - popup_menu_height + correction_factor * self.height - Screen:scaleBySize(2),
        w = self.width,
        h = self.height,
    }
end

function AnchorButton:setHeight(height)
    self.height = height
end

function AnchorButton:setWidth(width)
    self.width = width
end

--* button_no registers the sequence number of the button in the ButtonTable with buttons_count buttons:
function AnchorButton:init(button_no, buttons_count)
    self.parent_y = 0
    self.button_no = button_no
    self.buttons_count = buttons_count
end

return AnchorButton
