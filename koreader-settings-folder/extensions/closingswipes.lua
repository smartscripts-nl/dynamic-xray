
local require = require

local BD = require("ui/bidi")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

--- @class ClosingSwipes
local ClosingSwipes = WidgetContainer:extend{
    closing_gesture_information_html_DX = _([[<p class="noindent"><strong>Closing fullscreen DX dialogs with gestures</strong></p>
<p> </p>
<ul>
<li>You can close fullscreen(!) DX dialogs by swiping <i>diagonally</i> on them.</li>
<li>This can also be done by swiping <i>horizontally</i> on them, <i>unless</i> the dialog allows you to navigate to the next or previous item or page. In that case swiping horizontally will take you to the next or previous item or page.</li>
<li><strong>Exception</strong>: the Items List can only be closed by swiping <i>vertically</i>.</li>
<li>Non-fullscreen DX dialogs will be moved when you swipe on them.</li>
</ul>]])
}

function ClosingSwipes:handle(parent, arg, ges)
    if parent.movable then
        --* Let our MovableContainer handle swipe outside of definition
        return parent.movable:onMovableSwipe(arg, ges)
    end

    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)

    local is_navigation_swipe = parent.next_item_callback and parent.prev_item_callback
    if direction == "northeast" or direction == "northwest" or direction == "southwest" or direction == "southeast" then
        parent:onClose()
        return true
    elseif not is_navigation_swipe and (direction == "west" or direction == "east") then
        parent:onClose()
        return true
    elseif not is_navigation_swipe then
        return false
    end

    if direction == "west" then
        parent:next_item_callback()
        return true
    elseif direction == "east" then
        parent:prev_item_callback()
        return true
    end
    --* trigger a full-screen HQ flashing refresh
    UIManager:setDirty(nil, "full")
    --* a long diagonal swipe may also be used for taking a screenshot,
    --* so let it propagate
    return false
end

return ClosingSwipes
