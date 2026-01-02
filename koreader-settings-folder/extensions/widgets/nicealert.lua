
--* this widget is derived from ((WordInfoDialog)) for the VocabBuilder plugin
--* NiceAlert widget will be registered to KOR in ((Dialogs#init)) and used in ((Dialogs#niceAlert))

local require = require

local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Input = require("extensions/modules/input")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TextWidget = require("extensions/widgets/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DX = DX
local has_content = has_content
local math = math
local table = table

--- @class NiceAlert
--- @field show_parent ReaderUI
--- @field ui ReaderUI
local NiceAlert = InputContainer:extend {
    dismissable = true, --* set to false if any button callback is required
    info_buttons = nil,
    info_popup_face = Font:getFace("x_smallinfofont"),
    info_text = nil,
    info_textbox = nil,
    info_window_was_resized = false,
    margin = Size.margin.title,
    --* make sure the dialog is always at the top, even above an active keyboard:
    modal = true,
    mono_face = false,
    padding = Size.padding.large,
    show_parent = nil,
    tap_close_callback = nil,
    title = nil,
    ui = nil,
    width = nil,
}

function NiceAlert:init()
    self:setDialogWidth()
    self:initTouch()
    self:registerKeyEvents()
    self:generateWidget()
end

--- @private
function NiceAlert:generateWidget()
    self.info_window_was_resized = false
    self:generateTextboxWidget(self.info_text, self.width)
    self[1] = self:generatePopupCallbackDialogWidget(self.info_text, self.width)
end

--- @private
function NiceAlert:setDialogWidth()
    if self.width then
        return
    end

    local screen_width = math.min(Screen:getWidth(), Screen:getHeight())
    self.width = math.floor(screen_width * 0.7)
end

--- @private
function NiceAlert:generateTextboxWidget(info, width, height)
    if has_content(info) then

        local face
        if self.mono_face then
            face = Font:getFace("mono")
        -- #((NiceAlert fontsize for Bigme))
        elseif DX.s.is_mobile_device then
            face = self.info_text
            and
            Font:getFace("x_smallinfofont", 22)
            or
            Font:getFace("largeffont")
        else
            face = self.info_text
            and
            Font:getFace("x_smallinfofont", 19)
            or
            Font:getFace("smallffont")
        end

        if not height then
            self.info_textbox = TextBoxWidget:new{
                text = info,
                width = width,
                face = face,
                alignment = self.title_align or "left",
            }
            return
        end
        self.info_textbox = ScrollTextWidget:new{
            text = info,
            width = width,
            height = height,
            dialog = self,
            face = face,
            alignment = self.title_align or "left",
        }
    end
end

--- @private
function NiceAlert:generatePopupCallbackDialogWidget(info, width)

    local separator = LineWidget:new{
        background = KOR.colors.tabs_table_separators,
        dimen = Geom:new{
            w = width + self.padding + self.margin,
            h = Screen:scaleBySize(1),
        }
    }
    local content = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            TextWidget:new{
                text = self.title,
                max_width = width - Size.padding.default,
                face = self.info_popup_face,
                bold = true,
                alignment = self.title_align or "left",
            }
        },
        separator,
        VerticalSpan:new{ width = Size.padding.default },
        self.info_textbox or VerticalSpan:new{ width = Size.padding.default },
        VerticalSpan:new{ width = Size.padding.default },
    }
    if self.info_buttons then
        local button_table = self:generateFooterButtons(width)
        table.insert(content, separator)
        table.insert(content, button_table)
    end
    local content_group = VerticalGroup:new{
        align = "center",
        FrameContainer:new{
            padding = self.padding,
            padding_top = Size.padding.buttontable,
            padding_bottom = Size.padding.buttontable,
            margin = self.margin,
            bordersize = 0,
            content,
        },
    }
    local widget = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{
            FrameContainer:new{
                content_group,
                background = KOR.colors.background,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = 0
            }
        }
    }
    local screen_height = Screen:getHeight()
    local widget_height = content_group:getSize().h
    if self.info_window_was_resized or widget_height <= screen_height then
        return widget
    end
    widget:free()
    self.info_window_was_resized = true

    local box_height = math.floor(screen_height * 0.7)
    self:generateTextboxWidget(info, width, box_height)

    return self:generatePopupCallbackDialogWidget(info, width)
end

--- @private
function NiceAlert:generateFooterButtons(width)
    return ButtonTable:new{
        width = width,
        buttons = self.info_buttons,
        show_parent = self,
    }
end

--- @private
function NiceAlert:initTouch()
    if self.dismissable then
        if Device:isTouchDevice() then
            self.ges_events.Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0,
                        y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end
end

--- @private
function NiceAlert:registerKeyEvents()
    if Device:hasKeys() then
        self.key_events = {
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
        }
    end
end

function NiceAlert:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self[1][1].dimen --* i.e., MovableContainer
    end)
end

function NiceAlert:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function NiceAlert:onClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function NiceAlert:onTap(_, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        --* Tap outside closes widget
        self:onClose()
        return true
    end
end

function NiceAlert:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen --* FrameContainer
end

return NiceAlert
