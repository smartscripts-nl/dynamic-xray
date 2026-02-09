
--* register props of a computed anchorbutton, with which to position a popup menu via ((MovableContainer#moveToAnchor))

local require = require

local KOR = require("extensions/kor")
local Size = require("extensions/modules/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local DX = DX
local math_ceil = math.ceil

--- @class AnchorButton
local AnchorButton = WidgetContainer:extend{
    button = nil,
    button_no = nil,
    buttons_count = nil,
    height = nil,
    parent_y = 0,
    width = nil,
}

--* button_no registers the sequence number of the button in the ButtonTable with buttons_count buttons:
--* don't call this method "init", because then it would be wrongly called by the KOR initialisation:
function AnchorButton:initButtonProps(button_no, buttons_count)
    self.parent_y = 0
    self.button_no = button_no
    self.buttons_count = buttons_count
end

function AnchorButton:increaseParentYposWith(elements_height)
    self.parent_y = self.parent_y + elements_height
end

function AnchorButton:setAnchorButtonCoordinates(popup_menu, popup_buttons_count)

    local index = "anchor_button_y_pos"
    local computed_y_pos = KOR.registry:get(index)

    local x = self.button_no * self.width
    --* Ubuntu is a bit wacky in its handling of positions:
    if DX.s.is_ubuntu then
        --* Size.line.medium is the width of the separator lines in the ButtonTable:
        x = x - self.button_no * Size.line.medium
    end

    if not computed_y_pos then
        local popup_menu_height = popup_menu.inner_width or popup_menu:getSize().h
        --* "button_tap_pos" was set in ((Button#onTapSelectButton)):
        --* but when menu called with hotkey "M", fallback to self.parent_y:
        local was_tapped = KOR.registry:get("button_tap_pos")
        local parent_y = was_tapped and was_tapped.y or self.parent_y

        --* this computed "button" will be used as anchor point by ((MovableContainer#moveToAnchor)):
        local single_button_height = math_ceil(popup_menu_height / popup_buttons_count)
        local factor = was_tapped and 2 or 2.8
        computed_y_pos = parent_y - math_ceil(popup_menu_height / factor) - single_button_height - Screen:scaleBySize(2)

        KOR.registry:set(index, computed_y_pos)
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
