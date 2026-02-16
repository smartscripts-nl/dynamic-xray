
local require = require

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TitleBar = require("extensions/widgets/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
local Input = require("extensions/modules/input")
local Screen = Device.screen

local DX = DX
local math = math

--- @class ButtonDialogTitle
local ButtonDialogTitle = InputContainer:extend{
    after_close_callback = nil,
    title = nil,
    title_align = nil,
    title_face = nil,
    title_padding = Size.padding.large,
    title_margin = Size.margin.title,
    width = nil,
    width_factor = nil, --* number between 0 and 1, factor to the smallest of screen width and height
    --* (with the first one we can use the standard dialog or otherwise my adapted version):
    width_is_dependent_on_button_count = false,
    use_info_style = true, --* set to false to have bold font style of the title
    info_face = nil,
    info_padding = Size.padding.default,
    info_margin = Size.margin.default,

    subtitle = nil,
    middle_padding = Size.padding.small,
    move_to_top = false,
    move_to_y_pos = nil,
    small_padding = Size.padding.tiny,
    button_lines = 2,
    title_face_middle = nil,
    use_low_title = false,
    use_middle_title = false,
    alpha = nil, --* passed to MovableContainer
    pos = nil,
    modal = true,

    buttons = nil,
    tap_close_callback = nil,
    dismissable = true, --* set to false if any button callback is required

    font_weight = "bold",
    button_width = 0.25,
    button_font_face = "infofont",
    button_font_size = 14,
    button_font_bold = true,
    button_font_size_force = nil,
    ui = nil,

    top_buttons_left = nil,
    top_buttons_right = nil,
}

function ButtonDialogTitle:init()

    self.title_face = Font:getFace("x_smalltfont", 18)
    self.title_face_middle = Font:getFace("x_smalltfont", 24)

    self.info_face = self.title_face_middle

    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if not self.width then
        if not self.width_factor then
            self.width_factor = 0.9 --* default if no width specified
        end
        self.width = math.floor(math.min(self.screen_width, self.screen_height) * self.width_factor)
    end
    local has_keys = Device:hasKeys()
    if self.dismissable then
        if has_keys then
            self.key_events.Close = { { Input.group.CloseDialog } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0,
                        y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                }
            }
        end
    end

    local iwidth, face, button_font_face, button_font_size = self:setDynamicProps()
    if self.width == self.screen_width then
        local width_correction = DX.s.is_ubuntu and 20 or 40
        iwidth = self.width - width_correction
    end
    if self.button_font_size_force then
        button_font_size = self.button_font_size_force
    end

    local titlebar = TitleBar:new{
        align = self.title_align or "center",
        title = self.title,
        width = iwidth,
        title_top_padding = Screen:scaleBySize(6),
        button_padding = Screen:scaleBySize(5),
        title_face = face,
        top_buttons_left = self.top_buttons_left,
        top_buttons_right = self.top_buttons_right,
    }

    -- #((show context dialog subtitle))
    local font_size = 16
    local header_config = self.subtitle and {
        --padding = title_padding,
        --margin = self.use_info_style and self.info_margin or self.title_margin,
        padding = 0,
        margin = 0,
        bordersize = 0,
        padding_bottom = Size.padding.fullscreen,
        VerticalGroup:new{
            titlebar,
            TextBoxWidget:new{
                text = self.subtitle,
                face = Font:getFace("x_smallinfofont", font_size),
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8),
                alignment = self.title_align or "center",
            }
        },
    }
    or
    {
        --padding = title_padding,
        --margin = self.use_info_style and self.info_margin or self.title_margin,
        padding = 0,
        margin = 0,
        bordersize = 0,
        titlebar,
    }
    local top_frame = VerticalGroup:new{
        align = "center",
        FrameContainer:new(header_config),
        ButtonTable:new{
            width = iwidth,
            button_font_face = button_font_face,
            button_font_size = button_font_size,
            button_font_weight = self.font_weight,
            button_lines = self.button_lines,

            buttons = self.buttons,
            zero_sep = true,
            show_parent = self,
        },
    }
    self.movable = MovableContainer:new{
        alpha = self.alpha,
        FrameContainer:new{
            top_frame,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.button,
            padding_bottom = 0, --* no padding below buttontable
        }
    }

    self:positionButtonTable()

    --* make ButtonDialogTitle dialogs closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
    --* prevent footer showing through upon showing a ButtonDialogTitle instance. Footer will obe made visible again in ((ButtonDialogTitle#onCloseWidget)):
end

function ButtonDialogTitle:setTitle(title)
    self.title = title
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
end

function ButtonDialogTitle:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function ButtonDialogTitle:onCloseWidget()
    if self.after_close_callback then
        self:after_close_callback()
    end
    KOR.dialogs:closeContextOverlay()
    --[[UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)]]
end

function ButtonDialogTitle:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialogTitle:onClose()
    self:onTapClose()
    return true
end

function ButtonDialogTitle:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen --* FrameContainer
end

--* ==================== SMARTSCRIPTS =====================

function ButtonDialogTitle:setDynamicProps()
    --* make width of dialog dependent on button count of first row:
    local iwidth
    if self.width_is_dependent_on_button_count then
        local factor = #self.buttons[1]
        local button_count = factor
        local orientation = Screen:getScreenMode()
        local button_width = self.button_width
        if orientation == 'portrait' then
            button_width = button_width + 0.07
        end
        if factor > 3 then
            factor = 3
        end
        if orientation ~= 'portrait' and button_count > 4 then
            factor = 3.5
        end
        iwidth = math.floor(Screen:getWidth() * button_width * factor)
    elseif self.width then
        iwidth = self.width
    else
        iwidth = math.floor(Screen:getWidth() * 0.83)
    end

    local button_font_face = "cfont"
    local button_font_size = 16
    if self.font_weight == "normal" then
        button_font_face = "infofont"
    end
    local face

    if self.use_low_title then
        self.use_info_style = false
        face = self.title_face
    elseif self.use_middle_title then
        self.use_info_style = false
        face = self.title_face_middle

    elseif self.use_info_style then
        face = self.info_face
    else
        face = self.title_face
    end

    return iwidth, face, button_font_face, button_font_size
end

function ButtonDialogTitle:positionButtonTable()

    -- #((ButtonDialogTitle move to top))
    if self.move_to_top then
        self.movable:moveToYPos(0)
    elseif self.move_to_y_pos then
        self.movable:moveToYPos(self.move_to_y_pos)
    end

    local dimen = Screen:getSize()
    self[1] = CenterContainer:new{
        dimen = dimen,
        ignore_if_over = "height",
        self.movable,
    }
end

return ButtonDialogTitle
