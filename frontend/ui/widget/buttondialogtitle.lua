
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
-- ! use KOR.dialogs instead of Dialogs!
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScreenHelpers = require("extensions/screenhelpers")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
-- ! use KOR.xrayhelpers instead of XrayHelpers!
local Screen = Device.screen

--- @class ButtonDialogTitle
local ButtonDialogTitle = InputContainer:extend{
    -- [...]

    move_to_top = false,
    move_to_y_pos = nil,
    no_overlay = false,
    top_buttons_left = nil,
    top_buttons_right = nil,
    button_font_face = "infofont",
    button_font_size = 14,
}

function ButtonDialogTitle:init()

    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()

    -- [...]

    local title_padding = self.use_info_style and self.info_padding or self.title_padding
    local title_margin = self.use_info_style and self.info_margin or self.title_margin
    local title_width = self.width - 2 * (Size.border.window + Size.padding.button + title_padding + title_margin)

    -- ! use TitleBar for title bar, instead of TextBox widget in original KOReader code:
    local titlebar = TitleBar:new{
        align = self.title_align or "center",
        title = self.title,
        width = title_width,
        title_top_padding = Screen:scaleBySize(6),
        button_padding = Screen:scaleBySize(5),
        title_face = self.use_info_style and self.info_face or self.title_face,
        top_buttons_left = self.top_buttons_left,
        top_buttons_right = self.top_buttons_right,
    }

    local header_config = {
        padding = 0,
        margin = 0,
        bordersize = 0,
        titlebar,
    }
    local top_frame = VerticalGroup:new{
        align = "center",
        FrameContainer:new(header_config),
        ButtonTable:new{

            -- SmartScripts:
            width = title_width,
            button_font_face = self.button_font_face,
            button_font_size = self.button_font_size,
            button_font_weight = self.font_weight,

            buttons = self.buttons,
            zero_sep = true,
            show_parent = self,
        },
    }
    local movable = MovableContainer:new{
        FrameContainer:new{
            top_frame,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.button,
            padding_bottom = 0, -- no padding below buttontable
        }
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        ignore_if_over = "height",
        movable,
    }

    -- #((ButtonDialogTitle move to top))
    if self.move_to_top then
        ScreenHelpers:moveMovableToYpos(movable, 0)
    elseif self.move_to_y_pos then
        ScreenHelpers:moveMovableToYpos(movable, self.move_to_y_pos)
    end

    if not self.no_overlay then
        KOR.dialogs:showOverlay(nil, "close_previous_instance")
    end
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
    KOR.dialogs:closeOverlay()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
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
    self.dimen = self[1][1].dimen -- FrameContainer
end

-- ================== ADDED ===================

function ButtonDialogTitle:addMoreButton(buttons, props)
    local extra_buttons_count = #props.source_items - props.max_total_buttons + 1
    table.insert(buttons[props.current_row], {
        text = "[+" .. extra_buttons_count .. "]",
        font_bold = false,
        callback = function()
            self:handleMoreButtonClick(props, extra_buttons_count)
        end,
    })
end

function ButtonDialogTitle:handleMoreButtonClick(props, extra_buttons_count)
    local source_items = props.source_items
    local popup_buttons = {}
    local popup_viewer
    local max_total_buttons = props.max_total_buttons
    local mprops = {}

    -- here popup buttons are generated; if we want to limit them with a more button again, we have to point back to and use the arguments - nr add_more_button max_total_buttons source_items callback extra_item_callback needle_for_bold - needed for ((XrayHelpers#addButton))
    local shifted_source_items = {}
    -- first make sure we copy ALL the not yet shown items, before optionally updating max_total_buttons in the next code block:
    for nr = max_total_buttons, #source_items do
        table.insert(shifted_source_items, source_items[nr])
    end
    -- popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons; for example see ((XrayItems#addContextButtons)):
    if props.max_total_buttons_after_first_popup then
        max_total_buttons = props.max_total_buttons_after_first_popup
    end
    mprops.add_more_button = #shifted_source_items > max_total_buttons
    for nr = 1, #shifted_source_items do
        local item = shifted_source_items[nr]

        -- modify a copy of the parent props:
        mprops.add_more_button = #shifted_source_items > max_total_buttons
        mprops.nr = nr
        mprops.max_total_buttons = max_total_buttons
        mprops.max_buttons_per_row = props.max_buttons_per_row
        mprops.needle_for_bold = props.needle_for_bold
        mprops.source_items = shifted_source_items
        mprops.callback = function()
            UIManager:close(popup_viewer)
            props.item_callback(item)
        end
        mprops.extra_item_callback = function(citem)
            props.extra_item_callback(citem)
        end
        local icon = props.icon_generator and props.icon_generator:getIcon(item) .. " " or ""
        mprops.hold_callback = function()
            props.item_hold_callback(item, icon)
        end
        local more_button_added = KOR.xrayhelpers:addButton(popup_buttons, item, mprops)
        if more_button_added then
            break
        end
    end
    popup_viewer = self:new{
        title = extra_buttons_count .. props.title,
        title_align = "center",
        use_low_title = true,
        no_overlay = true,
        buttons = popup_buttons,
    }
    UIManager:show(popup_viewer)
end


return ButtonDialogTitle
