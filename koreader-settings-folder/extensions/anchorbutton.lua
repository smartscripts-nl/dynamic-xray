
--* register props of a computed anchorbutton, with which to position a popup menu via ((MovableContainer#moveToAnchor))

local require = require

local KOR = require("extensions/kor")
local Size = require("extensions/modules/size")
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

function AnchorButton:setAnchorButtonCoordinates(button_no, popup_menu)

    --* this var was set in ((NavigatorBox#registerAnchorButtonYPos)):
    local computed_y_pos = KOR.registry:get("anchor_button_y_pos")
    local scale_factor = DX.s.PN_popup_menu_y_offset
    computed_y_pos = computed_y_pos - (popup_menu.inner_width or popup_menu:getSize().h) - Screen:scaleBySize(scale_factor)

    local x = button_no * self.width
    --* Ubuntu is a bit wacky in its handling of positions:
    if DX.s.is_ubuntu then
        --* Size.line.medium is the width of the separator lines in the ButtonTable:
        x = x - button_no * Size.line.medium
    end

    self.button = {
        x = x,
        y = computed_y_pos,
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

return AnchorButton
