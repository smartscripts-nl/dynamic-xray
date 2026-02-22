
--[[--
Widget that shows a message and cancel/choice1/choice2 buttons

Example:

    UIManager:show(MultiConfirmBox:new{
        text = T( _("Set %1 as fallback font?"), face),
        choice1_text = _("Default"),
        choice1_callback = function()
            -- set as default font
        end,
        choice2_text = _("Fallback"),
        choice2_callback = function()
            -- set as fallback font
        end,
    })
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
local MovableContainer = require("extensions/widgets/container/movablecontainer")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Input = require("extensions/modules/input")
local Screen = require("device").screen

local DX = DX
local math = math

--- @class MultiConfirmBox
local MultiConfirmBox = InputContainer:extend{
    modal = true,
    text = _("no text"),
    face = Font:getFace("infofont"),
    choice1_icon = nil,
    choice1_text = _("Choice 1"),
    choice1_text_func = nil,
    choice2_icon = nil,
    choice2_text = _("Choice 2"),
    choice2_text_func = nil,
    cancel_text = _("Cancel"),
    choice1_callback = function() end,
    choice2_callback = function() end,
    cancel_callback = function() end,
    choice1_enabled = true,
    choice2_enabled = true,
    margin = Size.margin.default,
    padding = Size.padding.default,
    dismissable = true, -- set to false if any button callback is required

    show_icon = true,
    icon = "notice-question-rounded",
    icon_size = Screen:scaleBySize(27),
    -- alternative for using cumbersome choice1_callback etc.:
    buttons = nil,
    next_item_callback = nil,
    prev_item_callback = nil,
    overlay_close_callback = nil,
    wide_dialog = false,
    width_factor = nil,

    alpha = nil,
    pos = nil,
    modal = true,
}

function MultiConfirmBox:init()
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
            self.key_events = {
                PrevItem = { { Input.group.PgBack } },
                NextItem = { { Input.group.PgFwd } },
                ForcePrevItemWithShiftSpace = Input.group.ShiftSpace,
                -- #((activate tabs by left and right keys for MultiConfirmBox))
                ForcePrevItem = { { Input.group.TabPrevious } },
                ForceNextItem = { { Input.group.TabNext } },
                Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
            }
        end
    end

    local content
    local width_factor = self.width_factor
    if not width_factor then
        width_factor = self.wide_dialog and 7/8 or 2/3
    end
    local line_height = 0.13
    if self.wide_dialog then
        self.face, line_height = Font:setFontByTextLength(self.text)
    end
    local text_widget = self.wide_dialog and ScrollTextWidget:new{
        text = self.text,
        face = self.face,
        line_height = line_height,
        alignment = "left",
        justified = false,
        dialog = self,
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * width_factor),
        height = math.floor(Screen:getHeight() * 0.8),
    }
    or TextBoxWidget:new{
        text = self.text,
        face = self.face,
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * width_factor),
    }

    if self.show_icon then
        content = HorizontalGroup:new{
            align = "center",
            IconWidget:new{
                icon = self.icon,
                width = self.icon_size,
                height = self.icon_size,
            },
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            text_widget
        }
    else
        content = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            text_widget
        }
    end

    local buttons = self.buttons and self.buttons or {
        {
            {
                text = self.cancel_text,
                callback = function()
                    self.cancel_callback()
                    UIManager:close(self)
                end,
            },
            {
                icon = self.choice1_icon,
                text = self.choice1_text,
                text_func = self.choice1_text_func,
                enabled = self.choice1_enabled,
                callback = function()
                    self.choice1_callback()
                    UIManager:close(self)
                end,
            },
            {
                icon = self.choice2_icon,
                text = self.choice2_text,
                text_func = self.choice2_text_func,
                enabled = self.choice2_enabled,
                callback = function()
                    self.choice2_callback()
                    UIManager:close(self)
                end,
            },
        },
    }

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local movable = MovableContainer:new{
        alpha = self.alpha,
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            margin = self.margin,
            radius = Size.radius.window,
            padding = self.padding,
            padding_bottom = 0, -- no padding below buttontable
            VerticalGroup:new{
                align = "left",
                content,
                -- Add same vertical space after than before content
                VerticalSpan:new{ width = self.margin + self.padding },
                button_table,
            }
        }
    }
    local dimen = Screen:getSize()
    if self.pos and self.pos == "rock-bottom-center" then
        self[1] = CenterContainer:new{
            dimen = dimen,
            BottomContainer:new{
                dimen = dimen,
                movable,
            }
        }
    elseif self.pos and self.pos == "top-center" then
        self[1] = CenterContainer:new{
            dimen = dimen,
            TopContainer:new{
                dimen = dimen,
                movable,
            }
        }
    else
        self[1] = CenterContainer:new{
            dimen = dimen,
            movable,
        }
    end
end

function MultiConfirmBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen -- i.e., MovableContainer
    end)
end

function MultiConfirmBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function MultiConfirmBox:onClose()
    if self.overlay_close_callback then
        self:overlay_close_callback()
    else
        KOR.dialogs:closeOverlay()
    end
    UIManager:close(self)
    return true
end

function MultiConfirmBox:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        self:onClose()
        self.garbage = arg
        return true
    end
    return false
end

-- ================= SMARTSCRIPTS =======================

function MultiConfirmBox:onNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    return true
end

function MultiConfirmBox:onPrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    return true
end

function MultiConfirmBox:onForceNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    return true
end

function MultiConfirmBox:onForcePrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    return true
end

function MultiConfirmBox:onForcePrevItemWithShiftSpace()
    return self:onForcePrevItem()
end

function MultiConfirmBox:onSelect()
    logger.dbg("selected:", self.selected.x)
    if self.selected.x == 1 then
        self:choice1_callback()
    elseif self.selected.x == 2 then
        self:choice2_callback()
    elseif self.selected.x == 0 then
        self:cancle_callback()
    end
    UIManager:close(self)
    return true
end

return MultiConfirmBox
