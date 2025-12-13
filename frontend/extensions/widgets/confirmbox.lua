--[[--
Widget that shows a confirmation alert with a message and Cancel/OK buttons.

Example:

    UIManager:show(ConfirmBox:new{
        text = _("Save the document?"),
        ok_text = _("Save"),  --* ok_text defaults to _("OK")
        ok_callback = function()
            --* save document
        end,
    })

It is strongly recommended to set a custom `ok_text` describing the action to be
confirmed, as demonstrated in the example above. No ok_text should be specified
if the resulting phrase would be longer than three words.

]]

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Input = require("extensions/modules/input")
local Screen = Device.screen

local DX = DX
local ipairs = ipairs
local math = math
local table = table

--- @class ConfirmBox
local ConfirmBox = InputContainer:extend{
    modal = true,
    keep_dialog_open = false,
    text = _("no text"),
    face = Font:getFace("infofont"),
    icon = "notice-question",
    ok_icon = "yes",
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
    cancel_icon = "back",
    ok_callback = function() end,
    cancel_callback = function() end,
    buttons = nil,
    other_buttons = nil,
    other_buttons_first = false, --* set to true to place other buttons above Cancel-OK row
    margin = Size.margin.default,
    show_icon = true,
    padding = Size.padding.default,
    dismissable = true, --* set to false if any button callback is required
    flush_events_on_show = false, --* set to true when it might be displayed after
                                  --* some processing, to avoid accidental dismissal

    wide_dialog = false,
    alpha = nil,
    pos = nil,
}

function ConfirmBox:init()

    KOR.registry:set("use_bigger_buttons", true)

    if self.dismissable then
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
        if Device:hasKeys() then
            self.key_events.Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
            self.key_events.Confirm = DX.s.is_ubuntu and {{ "/" }} or { { Input.group.Confirm } }
        end
    end
    local width_factor = self.wide_dialog and 7/8 or 2/3
    local line_height = 0.13
    if self.wide_dialog then
        self.face, line_height = Font:setFontByTextLength(self.text)
    end

    --* needed for ConfirmBox:getAddedWidgetAvailableWidth():
    self.text_widget_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * width_factor)

    local text_widget = self.wide_dialog and ScrollTextWidget:new{
        text = self.text,
        face = self.face,
        line_height = line_height,
        alignment = "left",
        justified = false,
        dialog = self,
        width = self.text_widget_width,
        height = math.floor(Screen:getHeight() * 0.8),
    }
     or TextBoxWidget:new{
        text = self.text,
        face = self.face,
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * width_factor),
    }
    local content = self.show_icon and HorizontalGroup:new{
        align = "center",
        IconWidget:new{
            icon = self.icon,
            alpha = true,
        },
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        text_widget,
    }
    or
    HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        text_widget,
    }

    local buttons = self.buttons or {{
        icon = self.cancel_icon or "back",
        icon_size_ratio = 0.7,
        callback = function()
            self.cancel_callback()
            UIManager:close(self)
        end,
    },
    {
         callback = function()
             self.ok_callback()
             if self.keep_dialog_open then
                 return
             end
             UIManager:close(self)
         end,
     }}
    if not self.buttons then
        if self.ok_icon then
            buttons[2].icon = self.ok_icon
            buttons[2].icon_size_ratio = 0.6
        elseif self.ok_text:match("^icon_") then
            buttons[2].icon = self.ok_text:gsub("^icon_", "")
            buttons[2].icon_size_ratio = 0.6
        else
            buttons[2].text = self.ok_text
        end
        buttons = { buttons } --* single row
    end

    if self.other_buttons ~= nil then
        --* additional rows
        local rownum = self.other_buttons_first and 0 or 1
        for i, buttons_row in ipairs(self.other_buttons) do
            local row = {}
            table.insert(buttons, rownum + i, row)
            for ___, button in ipairs(buttons_row) do
                table.insert(row, {
                    text = button.text,
                    callback = function()
                        self.garbage = ___
                        if button.callback ~= nil then
                            button.callback()
                        end
                        if self.keep_dialog_open then return end
                        UIManager:close(self)
                    end,
                })
            end
        end
    end

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        margin = self.margin,
        radius = Size.radius.window,
        padding = self.padding,
        padding_bottom = 0, --* no padding below buttontable
        VerticalGroup:new{
            align = "left",
            content,
            --* Add same vertical space after than before content
            VerticalSpan:new{ width = self.margin + self.padding },
            button_table,
        }
    }
    self.movable = MovableContainer:new{
        alpha = self.alpha,
        frame,
    }
    local dimen = Screen:getSize()
    if self.pos and self.pos == "rock-bottom-center" then
        self[1] = CenterContainer:new{
            dimen = dimen,
            modal = true,
            BottomContainer:new{
                dimen = dimen,
                self.movable,
            }
        }
    elseif self.pos and self.pos == "top-center" then
        self[1] = CenterContainer:new{
            dimen = dimen,
            modal = true,
            TopContainer:new{
                dimen = dimen,
                self.movable,
            }
        }
    else
        self[1] = CenterContainer:new{
            modal = true,
            dimen = dimen,
            self.movable,
        }
    end

    --* Reduce font size until widget fit screen height if needed
    local cur_size = frame:getSize()
    if cur_size and cur_size.h > 0.95 * Screen:getHeight() then
        local orig_font = text_widget.face.orig_font
        local orig_size = text_widget.face.orig_size
        local real_size = text_widget.face.size
        if orig_size > 10 then --* don't go too small
            while true do
                orig_size = orig_size - 1
                self.face = Font:getFace(orig_font, orig_size)
                --* scaleBySize() in ((Font#getFace)) may give the same
                --* real font size even if we decreased orig_size,
                --* so check we really got a smaller real font size
                if self.face.size < real_size then
                    break
                end
            end
            --* re-init this widget
            self:free()
            self:init()
        end
    end
end

function ConfirmBox:getAddedWidgetAvailableWidth()
    return self.text_widget_width
end

function ConfirmBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
    if self.flush_events_on_show then
        --* Discard queued and upcoming input events to avoid accidental dismissal
        Input:inhibitInputUntil(true)
    end
end

function ConfirmBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function ConfirmBox:onClose()
    --* Call cancel_callback, parent may expect a choice
    self.cancel_callback()
    UIManager:close(self)
    return true
end

function ConfirmBox:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
        self.garbage = arg
    end
    --* Don't let it propagate to underlying widgets
    return true
end

function ConfirmBox:onConfirm()
    if self.buttons then
        local last_button = self.buttons[1][#self.buttons[1]]
        last_button.callback()
    else
        self.ok_callback()
    end
    UIManager:close(self)
    return true
end

return ConfirmBox
