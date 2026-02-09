--[[--
A button dialog widget that shows a grid of buttons.

    @usage
    local button_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = "First row, left side",
                    callback = function() end,
                    hold_callback = function() end
                },
                {
                    text = "First row, middle",
                    callback = function() end
                },
                {
                    text = "First row, right side",
                    callback = function() end
                }
            },
            {
                {
                    text = "Second row, full span",
                    callback = function() end
                }
            },
            {
                {
                    text = "Third row, left side",
                    callback = function() end
                },
                {
                    text = "Third row, right side",
                    callback = function() end
                }
            }
        }
    }
--]]

local require = require

local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("extensions/modules/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = require("device").screen

local math = math
local type = type

--- @class ButtonDialog
local ButtonDialog = InputContainer:extend{
    buttons = nil,

    --* this will be the color of the FrameContainer:
    bordercolor = nil,
    borderradius = nil,
    font_weight = "bold",
    button_width = 0.25,
    button_font_face = "infofont",
    button_font_size = 14,
    button_font_bold = true,
    pos = nil,
    after_close_callback = nil,
    modal = true,

    tap_close_callback = nil,
    alpha = nil, -- passed to MovableContainer
    -- If scrolling, prefers using this/these numbers of buttons rows per page
    -- (depending on what the screen height allows) to compute the height.
    rows_per_page = nil, -- number or array of numbers

    readonly = false,
    button_lines = 2,

    forced_width = nil,
    -- (with the first one we can use the standard dialog or otherwise my adapted version):
    width_is_dependent_on_button_count = false,
    button_width = 0.25,
    inner_height = nil,
    ui = nil,
}

function ButtonDialog:init()
    if not self.width then
        if not self.width_factor then
            self.width_factor = 0.9 -- default if no width specified
        end
        self.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * self.width_factor)
    end
    KOR.keyevents:addHotkeysForButtonDialog(self)
    if not self.readonly and Device:isTouchDevice() then
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

    local iwidth, button_font_face, button_font_size = self:setDynamicButtonProps()

    self.buttontable = ButtonTable:new{

        width = iwidth,

        button_font_face = button_font_face,
        button_font_size = button_font_size,
        button_lines = self.button_lines,
        button_font_weight = self.font_weight,

        buttons = self.buttons,
        shrink_unneeded_width = self.shrink_unneeded_width,
        shrink_min_width = self.shrink_min_width,
        show_parent = self,
    }
    -- If the ButtonTable ends up being taller than the screen, wrap it inside a ScrollableContainer.
    -- Ensure some small top and bottom padding, so the scrollbar stand out, and some outer margin
    -- so the this dialog does not take the full height and stand as a popup.
    local max_height = Screen:getHeight() - 2 * Size.padding.buttontable - 2 * Size.margin.default
    local height = self.buttontable:getSize().h
    local scontainer
    if height > max_height then
        -- Adjust the ScrollableContainer to an integer multiple of the row height
        -- (assuming all rows get the same height), so when scrolling per page,
        -- we always end up seeing full rows.
        self.buttontable:setupGridScrollBehaviour()
        local step_scroll_grid = self.buttontable:getStepScrollGrid()
        local row_height = step_scroll_grid[1].bottom + 1 - step_scroll_grid[1].top
        local fit_rows = math.floor(max_height / row_height)
        if self.rows_per_page then
            if type(self.rows_per_page) == "number" then
                if fit_rows > self.rows_per_page then
                    fit_rows = self.rows_per_page
                end
            else
                local nb
                for i = 1, #self.rows_per_page do
                    nb = self.rows_per_page[i]
                    if fit_rows >= nb then
                        fit_rows = nb
                        break
                    end
                end
            end
        end
        -- (Comment the next line to test ScrollableContainer behaviour when things do not fit)
        max_height = row_height * fit_rows
        self.cropping_widget = ScrollableContainer:new{
            dimen = Geom:new{
                -- We'll be exceeding the provided width in this case (let's not bother
                -- ensuring it, we'd need to re-setup the ButtonTable...)
                w = self.buttontable:getSize().w + ScrollableContainer:getScrollbarWidth(),
                h = max_height,
            },
            show_parent = self,
            step_scroll_grid = step_scroll_grid,
            self.buttontable,
        }
        scontainer = VerticalGroup:new{
            VerticalSpan:new{ width = Size.padding.buttontable },
            self.cropping_widget,
            VerticalSpan:new{ width = Size.padding.buttontable },
        }
    end
    self.movable = MovableContainer:new{
            alpha = self.alpha,
            FrameContainer:new{
                scontainer or self.buttontable,
                background = not self.readonly and KOR.colors.background or KOR.colors.black,
                bordersize = Size.border.window,
                color = self.bordercolor,
                radius = self.borderradius or Size.radius.window,
                padding = Size.padding.button,
                -- No padding at top or bottom to make all buttons
                -- look the same size
                padding_top = 0,
                padding_bottom = 0,
            }
    }
    local button_table_height = self.buttontable:getSize().h + 2 * Size.border.window
    self.inner_height = scontainer and scontainer:getSize().h or button_table_height

    -- #((set button_dialog_table_height))
    --! very hacky, this is needed to position the Page Navigator popup menu correctly upon first call; consumed in ((MovableContainer#moveToAnchor)):
    KOR.registry:set("button_dialog_table_height", button_table_height)

    self:positionButtonTable()

    -- make ButtonDialog dialogs closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)

    return self
end

function ButtonDialog:getButtonById(id)
    return self.buttontable:getButtonById(id)
end

function ButtonDialog:getScrolledOffset()
    if self.cropping_widget then
        return self.cropping_widget:getScrolledOffset()
    end
end

function ButtonDialog:setScrolledOffset(offset_point)
    if offset_point and self.cropping_widget then
        return self.cropping_widget:setScrolledOffset(offset_point)
    end
end

function ButtonDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ButtonDialog:onCloseWidget()
    if self.after_close_callback then
        self:after_close_callback()
    end
    if not KOR.registry:get("infilemanager") then
        KOR.dialogs:closeAllOverlays()
    end
    UIManager:setDirty(nil, function()
        return "flashui", self.movable.dimen
    end)
end

function ButtonDialog:onTapClose()
    KOR.dialogs:closeAllOverlays()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialog:onClose()
    self:onTapClose()
    return true
end

function ButtonDialog:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self.movable.dimen
end

--* ==================== SMARTSCRIPTS =====================

function ButtonDialog:positionButtonTable()
    local dimen = Screen:getSize()
    if type(self.pos) == "table" then


    -- bottom center of screen:
    elseif self.pos == "bottom-center" then

        self[1] = CenterContainer:new{
            dimen = dimen,
            BottomContainer:new{
                dimen = dimen,
                VerticalGroup:new{
                    align = "center",
                    self.movable,
                    -- vertical spacer:
                    TextWidget:new{
                        text = " ",
                        face = Font:getFace("x_smallinfofont", 50),
                    },
                }
            }
        }

    elseif self.pos == "rock-bottom-center" then

        self[1] = CenterContainer:new{
            dimen = dimen,
            BottomContainer:new{
                dimen = dimen,
                self.movable,
            }
        }

    --* center of screen:
    else
        self[1] = CenterContainer:new{
            dimen = dimen,
            self.movable,
        }
    end
end

function ButtonDialog:setDynamicButtonProps()
    --* make width of dialog dependent on button count of first row:
    local iwidth
    if self.forced_width then
        iwidth = self.forced_width
    elseif self.width_is_dependent_on_button_count then
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
    else
        iwidth = math.floor(Screen:getWidth() * 0.83)
    end

    local button_font_face = "cfont"
    local button_font_size = 20
    if self.font_weight == "normal" then
        button_font_face = "infofont"
        button_font_size = 16
    end
    return iwidth, button_font_face, button_font_size
end

return ButtonDialog
