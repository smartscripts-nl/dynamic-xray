--[[
Widget that displays an informational message.

It vanishes on key press or after a given timeout.

Example:
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local sample
    sample = InfoMessage:new{
        text = _("Some message"),
        --* Usually the hight of a InfoMessage is self-adaptive. If this field is actively set, a
        --* scrollbar may be shown. This variable is usually helpful to display a large chunk of text
        --* which may exceed the height of the screen.
        height = Screen:scaleBySize(400),
        --* Set to false to hide the icon, and also the span between the icon and text.
        show_icon = false,
        timeout = 5,  --* This widget will vanish in 5 seconds.
    }
    UIManager:show(sample)
]]

local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("extensions/widgets/container/movablecontainer")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local UIManager = require("ui/uimanager")
--! don't use Utils here!
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local math = math

--- @class InfoMessage
local InfoMessage = InputContainer:extend{
    face = nil,
    --* added by Alex:
    title = "",
    title_added = false,
    text = "",
    timeout = nil, --* in seconds
    width = nil,  --* The width of the InfoMessage. Keep it nil to use default value.
    height = nil,  --* The height of the InfoMessage. If this field is set, a scrollbar may be shown.
    --* The image shows at the left of the InfoMessage. Image data will be freed
    --* by InfoMessage, caller should not manage its lifecycle
    image = nil,
    image_width = nil,  --* The image width if image is used. Keep it nil to use original width.
    image_height = nil,  --* The image height if image is used. Keep it nil to use original height.
    --* Whether the icon should be shown. If it is false, self.image will be ignored.
    show_icon = true,
    icon = "notice-info",
    icon_size_ratio = 1,
    alpha = nil, --* if image or icon have an alpha channel (default to true for icons, false for images
    dismissable = true,
    dismiss_callback = nil,
    --* Passed to TextBoxWidget
    alignment = "left",
    --* In case we'd like to use it to display some text we know a few more things about:
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = nil,
    --* Don't call setDirty when closing the widget
    no_refresh_on_close = nil,
    --* Only have it painted after this delay (dismissing still works before it's shown)
    show_delay = nil,
    --* Set to true when it might be displayed after some processing, to avoid accidental dismissal
    flush_events_on_show = false,

    --* Alex:
    face_adaptation_activated = false,
    --* this can be set upon starting KOReader, from ((ReaderUI#showReaderCoroutine)):
    forced_face = nil,
    --* at end of ((InfoMessage#init)) modal is set to true for the movable container...
    modal = true,
    move_to_top = false,
    move_to_y_pos = nil,
}

function InfoMessage:init()
    --* init KOR.dialogs (must be done here, because we show a dialog upon opening KOReader):
    KOR.dialogs = require("extensions/dialogs")

    --* default font was Font:getFace("infofont", 18):
    --* the size of this face can yet be adapted in ((adapt font size for height)), when the height of the info message would be too great for available screen height:
    if not self.face_adaptation_activated then
        --self.face = Font:getFace("infofont", 18)
        if self.face_name and self.face_size then
            self.face = Font:getFace(self.face_name, self.face_size)

        elseif not self.forced_face then
            self.face = Font:getFace(self.face_name, self.face_size)

        else
            self.face = self.forced_face
        end
    end
    if self.dismissable then
        if Device:hasKeys() then
            self.key_events.AnyKeyPressed = { { Input.group.Any } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end

    local image_widget
    if self.show_icon then
        --- @todo remove self.image support, only used in filemanagersearch
        --* this requires self.image's lifecycle to be managed by ImageWidget
        --* instead of caller, which is easy to introduce bugs
        if self.image then
            image_widget = ImageWidget:new{
                image = self.image,
                width = self.image_width,
                height = self.image_height,
                alpha = self.alpha ~= nil and self.alpha or false, --* default to false
            }
        else
            local icon_height, icon_width = KOR.dialogs:getIconDims(self.icon_size_ratio)
            image_widget = IconWidget:new{
                icon = self.icon,
                width = icon_width,
                height = icon_height,
                alpha = self.alpha == nil and true or self.alpha, --* default to true
            }
        end
    else
        image_widget = WidgetContainer:new()
    end

    local text_width
    if self.width == nil then
        text_width = math.floor(Screen:getWidth() * 2/3)
    else
        text_width = self.width - image_widget:getSize().w
        if text_width < 0 then
            text_width = 0
        end
    end

    --* first condition: prevent strange duplication
    --* of title in some cases:
    if not self.title_added and self.title and self.title ~= "" then
        self.title = self.title:upper()
        self.text = self.title .. "\n\n" .. self.text
        self.title_added = true
    end

    local text_widget
    if self.height then
        text_widget = ScrollTextWidget:new{
            text = self.text,
            face = self.face,
            width = text_width,
            height = self.height,
            alignment = self.alignment,
            dialog = self,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    else
        text_widget = TextBoxWidget:new{
            text = self.text,
            face = self.face,
            --face = Font:getFace("infofont", 18),
            width = text_width,
            alignment = self.alignment,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    end
    local frame = FrameContainer:new{
        background = KOR.colors.background,
        radius = Size.radius.window,
        modal = true,
        HorizontalGroup:new{
            align = "center",
            image_widget,
            HorizontalSpan:new{ width = (self.show_icon and Size.span.horizontal_default or 0) },
            text_widget,
        }
    }
    self.movable = MovableContainer:new{
        frame,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
    if not self.height then
        --* Reduce font size until widget fit screen height if needed
        local cur_size = frame:getSize()
        if cur_size and cur_size.h > 0.95 * Screen:getHeight() then
            -- #((adapt font size for height))
            --local orig_font = text_widget.face.orig_font
            self.face_adaptation_activated = true
            --* self.face was set in ((InfoMessage#init)) > ((Font#getDefaultFontFace)):
            local real_size = text_widget.face.size
            local max_loops = 100
            local current_loop = 0
            if self.face_size > 10 then --* don't go too small
                while true do
                    current_loop = current_loop + 1
                    self.face_size = self.face_size - 1
                    self.face = Font:getFace(self.face_name, self.face_size)
                    --* scaleBySize() in ((Font#getFace)) may give the same
                    --* real font size even if we decreased orig_size,
                    --* so check we really got a smaller real font size
                    if self.face.size < real_size or current_loop > max_loops then
                        break
                    end
                end
                --* re-init this widget
                self:free()
                self:init()
                return

            --* window too high, but font to small to be further shrunk, so now show a textBox with scrollbar instead:
            elseif not self.forced_face then
                self:free()
                self[1] = nil
                KOR.dialogs:unregisterWidget(self)
                return KOR.dialogs:textBox({
                    title = "Ter informatie",
                    info = self.text,
                    height = math.floor(Screen:getHeight() * 9 / 10),
                    no_buttons_row = true,
                    no_overlay = true,
                })
            end
        end
    end

    -- #((move InfoMessage to y pos))
    if self.move_to_top then
        self.movable:moveToYPos(0)
    elseif self.move_to_y_pos then
        self.movable:moveToYPos(self.move_to_y_pos)
    end

    if self.show_delay then
        --* Don't have UIManager setDirty us yet
        self.invisible = true
    end

    --* make InfoMessage dialogs closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
end

function InfoMessage:onCloseWidget()
    if self._delayed_show_action then
        UIManager:unschedule(self._delayed_show_action)
        self._delayed_show_action = nil
    end
    if self.invisible then
        --* Still invisible, no setDirty needed
        return
    end
    if self.no_refresh_on_close then
        return
    end

    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function InfoMessage:onShow()
    --* triggered by the UIManager after we got successfully show()'n (not yet painted)
    if self.show_delay and self.invisible then
        --* Let us be shown after this delay
        self._delayed_show_action = function()
            self._delayed_show_action = nil
            self.invisible = false
            self:onShow()
        end
        UIManager:scheduleIn(self.show_delay, self._delayed_show_action)
        return true
    end
    --* set our region to be dirty, so UImanager will call our paintTo()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
    if self.flush_events_on_show then
        --* Discard queued and upcoming input events to avoid accidental dismissal
        Input:inhibitInputUntil(true)
    end
    --* schedule us to close ourself if timeout provided
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function()
            --* In case we're provided with dismiss_callback, also call it
            --* on timeout
            if self.dismiss_callback then
                self.dismiss_callback()
                self.dismiss_callback = nil
            end
            UIManager:close(self)
        end)
    end
    return true
end

function InfoMessage:getVisibleArea()
    if not self.invisible then
        return self.movable.dimen
    end
end

function InfoMessage:paintTo(bb, x, y)
    if self.invisible then
        return
    end
    InputContainer.paintTo(self, bb, x, y)
end

function InfoMessage:dismiss()
    if self._delayed_show_action then
        UIManager:unschedule(self._delayed_show_action)
        self._delayed_show_action = nil
    end
    if self.dismiss_callback then
        self.dismiss_callback()
        self.dismiss_callback = nil
    end
    UIManager:close(self)
end

function InfoMessage:onTapClose()
    self:dismiss()
    if self.readonly ~= true then
        return true
    end
end
InfoMessage.onAnyKeyPressed = InfoMessage.onTapClose

--* ==================== SMARTSCRIPTS =====================

function InfoMessage:onAnyKeyPressed()
    self:dismiss()
    if self.readonly ~= true then
        return true
    end
end

return InfoMessage
