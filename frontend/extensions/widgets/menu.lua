
local require = require

local BD = require("ui/bidi")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("extensions/widgets/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("extensions/widgets/titlebar")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local Utf8Proc = require("ffi/utf8proc")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Input = require("extensions/modules/input")
local Screen = Device.screen
local T = FFIUtil.template

local DX = DX
local G_reader_settings = G_reader_settings
local has_text = has_text
local math = math
local next = next
local table = table
local tonumber = tonumber
local string = string
local type = type

local count

--[[
Widget that displays a shortcut icon for menu item.
]]
local ItemShortCutIcon = WidgetContainer:extend{
    dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
    key = nil,
    bordersize = Size.border.default,
    radius = 0,
    style = "square",
}

function ItemShortCutIcon:init()
    if not self.key then
        return
    end

    local radius = 0
    local background = KOR.colors.background
    if self.style == "rounded_corner" then
        radius = math.floor(self.width / 2)
    elseif self.style == "grey_square" then
        background = KOR.colors.background_gray
    end

    --- @todo Calculate font size by icon size  01.05 2012 (houqp).
    local sc_face
    if self.key:len() > 1 then
        sc_face = Font:getFace("ffont", 14)
    else
        sc_face = Font:getFace("scfont", 22)
    end

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = self.bordersize,
        radius = radius,
        background = background,
        dimen = self.dimen:copy(),
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{
                text = self.key,
                face = sc_face,
            },
        },
    }
end

--[[
Widget that displays an item for menu
--]]
--- @class MenuItem
local MenuItem = InputContainer:extend{
    font = "cfont",
    multilines_forced = false, -- set to true to always use TextBoxWidget
    infont = "infont",
    text = nil,
    bidi_wrap_func = nil,
    show_parent = nil,
    detail = nil,
    font_size = 24,
    infont_size = 18,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    _underline_container = nil,
    linesize = Size.line.medium,
    single_line = false,
    multilines_show_more_text = false,
    --* Align text & mandatory baselines (only when single_line=true)
    align_baselines = false,
    --* Show a line of dots (also called tab or dot leaders) between text and mandatory
    with_dots = false,
}

function MenuItem:init()
    self.content_width = self.dimen.w - 2 * Size.padding.fullscreen
    local icon_width = math.floor(self.dimen.h * 4/5)
    local shortcut_icon_dimen = Geom:new{
        x = 0,
        y = 0,
        w = icon_width,
        h = icon_width,
    }
    if self.shortcut then
        self.content_width = self.content_width - shortcut_icon_dimen.w - Size.span.horizontal_default
    end

    self.detail = self.text

    --* we need this table per-instance, so we declare it here
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
            HoldSelect = {
                GestureRange:new{
                ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
                    range = self.dimen,
                },
            },
        }

    local max_item_height = self.dimen.h - 2 * self.linesize

    if not self.font_size then
        self.font_size = DX.s.is_mobile_device and 22 or 16
    end

    --* We want to show at least one line, so cap the provided font sizes
    local max_font_size = TextBoxWidget:getFontSizeToFitHeight(max_item_height, 1)
    if self.font_size > max_font_size then
        self.font_size = max_font_size
    end
    if self.infont_size > max_font_size then
        self.infont_size = max_font_size
    end
    if not self.single_line and not self.multilines_forced and not self.multilines_show_more_text then
        --* For non single line menus (File browser, Bookmarks), if the
        --* user provided font size is large and would not allow showing
        --* more than one line in our item height, just switch to single
        --* line mode. This allows, when truncating, to take the full
        --* width and cut inside a word to add the ellipsis - while in
        --* multilines modes, with TextBoxWidget, words are wrapped to
        --* follow line breaking rules, and the ellipsis might be placed
        --* way earlier than the full width.
        local min_font_size_2_lines = TextBoxWidget:getFontSizeToFitHeight(max_item_height, 2)
        if self.font_size > min_font_size_2_lines then
            self.single_line = true
        end
    end

    --* State button and indentation for tree expand/collapse (for TOC)
    local state_button = self.state or HorizontalSpan:new{}
    local state_indent = self.table.indent or 0
    local state_width = state_indent + self.state_w
    local state_container = LeftContainer:new{
        dimen = Geom:new{w = math.floor(self.content_width / 2), h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = state_indent,
            },
            state_button,
        }
    }

    --* Font for main text (may have its size decreased to make text fit)
    self.face = Font:getFace(self.font, self.font_size)
    --* Font for "mandatory" on the right
    self.info_face = Font:getFace(self.infont, self.infont_size)
    --* Font for post_text if any: for now, this is only used with TOC, showing
    --* the chapter length: if feels best to use the face of the main text, but
    --* with the size of the mandatory font (which shows some number too).
    if self.post_text then
        self.post_text_face = Font:getFace(self.font, self.infont_size)
    end

    --* "mandatory" is the text on the right: file size, page number...
    --* Padding before mandatory
    local text_mandatory_padding = 0
    local text_ellipsis_mandatory_padding = 0
    local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
    local mandatory_dim = self.mandatory_dim_func and self.mandatory_dim_func() or self.mandatory_dim
    if mandatory then
        text_mandatory_padding = Size.span.horizontal_default
        --* Smaller padding when ellipsis for better visual feeling
        text_ellipsis_mandatory_padding = Size.span.horizontal_small
    end
    mandatory = mandatory and ""..mandatory or ""
    local mandatory_widget = TextWidget:new{
        text = mandatory,
        face = self.info_face,
        bold = self.bold,
        fgcolor = mandatory_dim and KOR.colors.menu_mandatory_dim or nil,
    }
    local mandatory_w = mandatory_widget:getWidth()

    local available_width = self.content_width - state_width - text_mandatory_padding - mandatory_w
    local item_name

    --* Whether we show text on a single or multiple lines, we don't want it shortened
    --* because of some \n that would push the following text on another line that would
    --* overflow and not be displayed, or show a tofu char when displayed by TextWidget:
    --* get rid of any \n (which could be found in highlighted text in bookmarks).
    local text = self.text:gsub("\n", " ")

    --* Wrap text with provided bidi_wrap_func (only provided by FileChooser,
    --* to correctly display filenames and directories)
    if self.bidi_wrap_func then
        text = self.bidi_wrap_func(text)
    end

    --* Note: support for post_text is currently implemented only when single_line=true
    local post_text_widget
    local post_text_left_padding = Size.padding.large
    local post_text_right_padding = self.with_dots and 0 or Size.padding.large
    local dots_widget
    local dots_left_padding = Size.padding.small
    local dots_right_padding = Size.padding.small
    if self.single_line then  --* items only in single line
        if self.post_text then
            post_text_widget = TextWidget:new{
                text = self.post_text,
                face = self.post_text_face,
                bold = self.bold,
                fgcolor = self.dim and KOR.colors.menu_mandatory_dim or nil,
            }
            available_width = available_width - post_text_widget:getWidth() - post_text_left_padding - post_text_right_padding
        end
        --* No font size change: text will be truncated if it overflows
        item_name = TextWidget:new{
            text = text,
            face = self.face,
            bold = self.bold,
            truncate_left = self.truncate_left,
            fgcolor = self.dim and KOR.colors.menu_mandatory_dim or nil,
        }
        local w = item_name:getWidth()
        if w > available_width then
            local text_max_width_if_ellipsis = available_width
            --* We give it a little more room if truncated at the right for better visual
            --* feeling (which might make it no more truncated, but well...)
            if not self.truncate_left then
                text_max_width_if_ellipsis = text_max_width_if_ellipsis + text_mandatory_padding - text_ellipsis_mandatory_padding
            end
            item_name:setMaxWidth(text_max_width_if_ellipsis)
        else
            if self.with_dots then
                local dots_width = available_width + text_mandatory_padding - w - dots_left_padding - dots_right_padding
                if dots_width > 0 then
                    local dots_text, dots_min_width = self:getDotsText(self.info_face)
                    --* Don't show any dots if there would be less than 3
                    if dots_width >= dots_min_width then
                        dots_widget = TextWidget:new{
                            text = dots_text,
                            face = self.info_face, --* same as mandatory widget, to keep their baseline adjusted
                            max_width = dots_width,
                            truncate_with_ellipsis = false,
                        }
                    end
                end
            end
        end
        if self.align_baselines then --* Align baselines of text and mandatory
            --* The container widgets would additionally center these widgets,
            --* so make sure they all get a height=self.dimen.h so they don't
            --* risk being shifted later and becoming misaligned
            local name_baseline = item_name:getBaseline()
            local mdtr_baseline = mandatory_widget:getBaseline()
            local name_height = item_name:getSize().h
            local mdtr_height = mandatory_widget:getSize().h
            --* Make all the TextWidgets be self.dimen.h
            item_name.forced_height = self.dimen.h
            mandatory_widget.forced_height = self.dimen.h
            if dots_widget then
                dots_widget.forced_height = self.dimen.h
            end
            if post_text_widget then
                post_text_widget.forced_height = self.dimen.h
            end
            --* And adjust their baselines for proper centering and alignment
            --* (We made sure the font sizes wouldn't exceed self.dimen.h, so we
            --* get only non-negative pad_top here, and we're moving them down.)
            local name_missing_pad_top = math.floor( (self.dimen.h - name_height) / 2)
            local mdtr_missing_pad_top = math.floor( (self.dimen.h - mdtr_height) / 2)
            name_baseline = name_baseline + name_missing_pad_top
            mdtr_baseline = mdtr_baseline + mdtr_missing_pad_top
            local baselines_diff = Math.round(name_baseline - mdtr_baseline)
            if baselines_diff > 0 then
                mdtr_baseline = mdtr_baseline + baselines_diff
            else
                name_baseline = name_baseline - baselines_diff
            end
            item_name.forced_baseline = name_baseline
            mandatory_widget.forced_baseline = mdtr_baseline
            if dots_widget then
                dots_widget.forced_baseline = mdtr_baseline
            end
            if post_text_widget then
                post_text_widget.forced_baseline = mdtr_baseline
            end
        end

    elseif self.multilines_show_more_text then
        --* Multi-lines, with font size decrease if needed to show more of the text.
        --* It would be costly/slow with use_xtext if we were to try all
        --* font sizes from self.font_size to min_font_size.
        --* So, we try to optimize the search of the best font size.
        logger.dbg("multilines_show_more_text menu item font sizing start")
        local function make_item_name(font_size)
            if item_name then
                item_name:free()
            end
            logger.dbg("multilines_show_more_text trying font size", font_size)
            item_name = TextBoxWidget:new{
                text = text,
                face = Font:getFace(self.font, font_size),
                width = available_width,
                alignment = "left",
                bold = self.bold,
                fgcolor = self.dim and KOR.colors.menu_mandatory_dim or nil,
            }
            --* return true if we fit
            return item_name:getSize().h <= max_item_height
        end
        --* To keep item readable, do not decrease font size by more than 8 points
        --* relative to the specified font size, being not smaller than 12 absolute points.
        local min_font_size = math.max(12, self.font_size - 8)
        --* First, try with specified font size: short text might fit
        if not make_item_name(self.font_size) then
            --* It doesn't, try with min font size: very long text might not fit
            if not make_item_name(min_font_size) then
                --* Does not fit with min font size: keep widget with min_font_size, but
                --* impose a max height to show only the first lines up to where it fits
                item_name:free()
                item_name.height = max_item_height
                item_name.height_adjust = true
                item_name.height_overflow_show_ellipsis = true
                item_name:init()
            else
                --* Text fits with min font size: try to find some larger
                --* font size in between that make text fit, with some
                --* binary search to limit the number of checks.
                local bad_font_size = self.font_size
                local good_font_size = min_font_size
                local item_name_is_good = true
                while true do
                    local test_font_size = math.floor((good_font_size + bad_font_size) / 2)
                    if test_font_size == good_font_size then --* +1 would be bad_font_size
                        if not item_name_is_good then
                            make_item_name(good_font_size)
                        end
                        break
                    end
                    if make_item_name(test_font_size) then
                        good_font_size = test_font_size
                        item_name_is_good = true
                    else
                        bad_font_size = test_font_size
                        item_name_is_good = false
                    end
                end
            end
        end
    else
        --* Multi-lines, with fixed user provided font size
        item_name = TextBoxWidget:new{
            text = text,
            face = self.face,
            width = available_width,
            height = max_item_height,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            bold = self.bold,
            fgcolor = self.dim and KOR.colors.menu_mandatory_dim or nil,
        }
    end

    local text_container = LeftContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = state_width,
            },
            item_name,
            post_text_widget and HorizontalSpan:new{ width = post_text_left_padding },
            post_text_widget,
        }
    }

    if dots_widget then
        mandatory_widget = HorizontalGroup:new{
            dots_widget,
            HorizontalSpan:new{ width = dots_right_padding },
            mandatory_widget,
        }
    end
    local mandatory_container = RightContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        mandatory_widget,
    }

    self._underline_container = UnderlineContainer:new{
        color = self.line_color,
        linesize = self.linesize,
        vertical_align = "center",
        padding = 0,
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.content_width,
            h = self.dimen.h
        },
        HorizontalGroup:new{
            align = "center",
            OverlapGroup:new{
                dimen = Geom:new{w = self.content_width, h = self.dimen.h},
                state_container,
                text_container,
                mandatory_container,
            },
        }
    }
    local hgroup = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = self.items_padding or Size.padding.fullscreen },
    }
    if self.shortcut then
        table.insert(hgroup, ItemShortCutIcon:new{
            dimen = shortcut_icon_dimen,
            key = self.shortcut,
            style = self.shortcut_style,
        })
        table.insert(hgroup, HorizontalSpan:new{ width = Size.span.horizontal_default })
    end
    table.insert(hgroup, self._underline_container)
    table.insert(hgroup, HorizontalSpan:new{ width = Size.padding.fullscreen })

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        hgroup,
    }
end

local _dots_cached_info
function MenuItem:getDotsText(face)
    local screen_w = Screen:getWidth()
    if not _dots_cached_info or _dots_cached_info.screen_width ~= screen_w
                    or _dots_cached_info.face ~= face then
        local unit = "."
        local tmp = TextWidget:new{
            text = unit,
            face = face,
        }
        local unit_w = tmp:getSize().w
        tmp:free()
        --* (We assume/expect no kerning will happen between consecutive units)
        local nb_units = math.ceil(screen_w / unit_w)
        local min_width = unit_w * 3 --* have it not shown if smaller than this
        local text = unit:rep(nb_units)
        _dots_cached_info = {
            text = text,
            min_width = min_width,
            screen_width = screen_w,
            face = face,
        }
    end
    return _dots_cached_info.text, _dots_cached_info.min_width

end

function MenuItem:onFocus(initial_focus)
    if Device:isTouchDevice() then
        --* Devices which are Keys capable will get this onFocus called by
        --* updateItems(), which will toggle the underline color of first item.
        --* If the device is also Touch capable, let's not show the initial
        --* underline for a prettier display (it will be shown only when keys
        --* are used).
        if not initial_focus or self.menu.did_focus_with_keys then
            self._underline_container.color = KOR.colors.menu_underline
            self.menu.did_focus_with_keys = true
        end
    else
        self._underline_container.color = KOR.colors.menu_underline
    end
    return true
end

function MenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    return true
end

function MenuItem:onShowItemDetail()
    UIManager:show(InfoMessage:new{ text = self.detail, })
    return true
end

function MenuItem:getGesPosition(ges)
    local dimen = self[1].dimen
    return {
        x = (ges.pos.x - dimen.x) / dimen.w,
        y = (ges.pos.y - dimen.y) / dimen.h,
    }
end

function MenuItem:onTapSelect(arg, ges)
    --* Abort if the menu hasn't been painted yet.
    if not self[1].dimen then return end

    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuSelect(self.table, pos)
        self.garbage = arg
    else
        --* c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        --* Highlight

        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "fast", self[1].dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        --* Unhighlight

        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "ui", self[1].dimen)

        --* Callback
        self.menu:onMenuSelect(self.table, pos)

        UIManager:forceRePaint()
    end
    return true
end

function MenuItem:onHoldSelect(arg, ges)
    if not self[1].dimen then return end

    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.table, pos)
        self.garbage = arg
    else
        --* c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        --* Highlight

        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "fast", self[1].dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        --* Unhighlight

        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "ui", self[1].dimen)

        KOR.system:inhibitInputOnHold()
        self.menu:onMenuHold(self.table, pos)

        UIManager:forceRePaint()
    end
    return true
end

--- @class Menu
--- @field title_bar TitleBar
local Menu = FocusManager:extend{

    show_parent = nil,

    no_title = false,
    title = "Geen titel",
    subtitle = nil,
    show_path = nil, --* path in titlebar subtitle
    --* default width and height
    width = nil,
    --* height will be calculated according to item number if not given
    height = nil,
    header_padding = Size.padding.default,
    dimen = nil,

    hotkey_updater = nil,

    item_table = nil, --* NOT mandatory (will be empty)
    item_shortcuts = { --* const
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
        "Z", "X", "C", "V", "B", "N", "M", ".", "Sym",
    },
    item_table_stack = nil,
    is_enable_shortcut = false,

    item_dimen = nil,
    page = 1,

    item_group = nil,
    page_info = nil,
    page_return = nil,

    item_font = "smallinfofont",
    items_per_page_default = 14,
    items_per_page = nil,
    items_font_size = nil,
    items_mandatory_font_size = nil,
    multilines_show_more_text = nil,
        --* Global settings or default values will be used if not provided

    --* set this to true to not paint as popup menu
    is_borderless = false,
    --* if you want to embed the menu widget into another widget, set
    --* this to false
    is_popout = true,
    title_bar_fm_style = nil, --* set to true to build increased title bar like in FileManager

    top_buttons_left = nil,
    top_buttons_right = nil,

    title_tab_buttons_left = nil,
    title_tab_buttons_right = nil,
    higher_tab_buttons = false,
    title_submenu_buttontable = nil,

    --* for activating tabs with character hotkeys:
    tab_labels = nil,
    activate_tab_callback = nil,

    --* order for these buttons - generated with Button in the calling module! - is from the inside/center to the outside:
    --* max left footer buttons is 6:
    footer_buttons_left = nil,
    --* max right footer buttons is 5:
    footer_buttons_right = nil,

    --* close_callback is a function, which is executed when menu is closed
    --* it is usually set by the widget which creates the menu
    close_callback = nil,
    linesize = Size.line.medium,
    line_color = KOR.colors.menu_line,
    ui = nil,

    has_close_button = true,
    no_close_button = false,

    collection = nil,
    after_close_callback = nil,
    --* used for setting and retrieving active subpage; see ((Menu#storeActivePage)):
    module = nil,
    modal = true,

    filter = nil,
    show_filtered_count = false,
    enable_bold_words = false,
}

function Menu:_recalculateDimen()
    self.perpage = self.items_per_page or G_reader_settings:readSetting("items_per_page") or self.items_per_page_default
    self.span_width = 0
    local height_dim
    local bottom_height = 0
    local top_height = 0
    if self.page_return_arrow and self.page_info_text then
        bottom_height = math.max(self.page_return_arrow:getSize().h, self.page_info_text:getSize().h)
            + 2 * Size.padding.button
    end
    if self.title_bar and not self.no_title then
        top_height = self.title_bar:getHeight()
        if not self.title_bar_fm_style then
            top_height = top_height + self.header_padding
        end
    end
    height_dim = self.inner_dimen.h - bottom_height - top_height
    local item_height = math.floor(height_dim / self.perpage)
    self.span_width = math.floor((height_dim - (self.perpage * item_height)) / 2 - 1)
    self.item_dimen = Geom:new{
        x = 0, y = 0,
        w = self.inner_dimen.w,
        h = item_height,
    }
    self:calculatePageNum()
end

function Menu:init(restore_dialog)

    self:restoreTitleAfterScreenResize()

    self.show_parent = self.show_parent or self
    self.item_table = self.item_table or {}
    self.item_table_stack = {}

    self:detectAndSetFullscreenState()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width or self.screen_w, h = self.height or self.screen_h }
    if self.dimen.h > self.screen_h then
        self.dimen.h = self.screen_h
    end

    self.border_size = self.is_borderless and 0 or Size.border.window
    self.inner_dimen = Geom:new{
        w = self.dimen.w - 2 * self.border_size,
        h = self.dimen.h - 2 * self.border_size,
    }

    if self.module then
        self.page = KOR.registry:getMenuPage(self.module) or 1
    else
        self.page = 1
    end

    self.paths = {}  --* per instance table to trace navigation path

    -----------------------------------
    --* start to set up widget layout --
    -----------------------------------
    if self.show_path or not self.no_title then
        if self.subtitle == nil then
            if self.show_path then
                self.subtitle = BD.directory(filemanagerutil.abbreviate(self.path))
            elseif self.title_bar_fm_style then
                self.subtitle = ""
            end
        end

        -- #((TitleBar for Menu))
        --* compare ((TitleBar for TextViewer)):
        --left_icon_size_ratio = self.title_bar_fm_style and 1,
        if self.no_close_button then
            self.has_close_button = false
        end
        local title_bar_config = {
            width = self.dimen.w,
            fullscreen = self.fullscreen,
            align = "center",
            is_popout_dialog = self.is_popout,
            for_collection = self.collection,
            with_bottom_line = self.with_bottom_line,
            bottom_line_color = self.bottom_line_color,
            bottom_line_h_padding = self.bottom_line_h_padding,
            title = self.title,
            title_face = self.title_face,
            title_multilines = self.title_multilines,
            title_shrink_font_to_fit = true,
            subtitle = self.show_path and BD.directory(filemanagerutil.abbreviate(self.path)) or self.subtitle,
            subtitle_truncate_left = self.show_path,
            subtitle_fullwidth = self.show_path or self.subtitle,
            no_close_button = self.no_close_button,
            button_padding = self.title_bar_fm_style and Screen:scaleBySize(5),

            --* callbacks for these buttons defined as callback, to be converted to regular callbacks in ((TitleBar#init)):
            --* buttons in these three groups must be tables of real Buttons:
            top_buttons_left = self.top_buttons_left,
            top_buttons_right = self.top_buttons_right,
            tab_buttons_left = self.title_tab_buttons_left,
            tab_buttons_right = self.title_tab_buttons_right,
            higher_tab_buttons = self.higher_tab_buttons,
            submenu_buttontable = self.title_submenu_buttontable,
            --* to make menu instance availabe in callbacks of left or right titlebar icons:
            menu_instance = self,

            close_callback = (not self.no_close_button or self.has_close_button) and function()
                self:onClose()
            end or nil,
            show_parent = self.show_parent or self,
        }
        self.title_bar = TitleBar:new(title_bar_config)

    --* group for items
    self.item_group = VerticalGroup:new{}
    --* group for page info
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.page_info_left_chev = self.page_info_left_chev or Button:new{
        icon = chevron_left,
        callback = function() self:onPrevPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_right_chev = self.page_info_right_chev or Button:new{
        icon = chevron_right,
        callback = function() self:onNextPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_first_chev = self.page_info_first_chev or Button:new{
        icon = chevron_first,
        callback = function() self:onFirstPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_last_chev = self.page_info_last_chev or Button:new{
        icon = chevron_last,
        callback = function() self:onLastPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(16),
    }
    self.page_info_spacer_small = HorizontalSpan:new{
        width = Screen:scaleBySize(8),
    }
    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()

    local title_goto, type_goto, hint_func
    local buttons = {
        {
            {
                icon = "back",
                callback = function()
                    self.page_info_text:closeInputDialog()
                end,
            },
            KOR.buttoninfopopup:forMenuToAuthorLetter({
                callback = function()
                    self:gotoCharacter()
                end,
            }),
            KOR.buttoninfopopup:forMenuToAuthorLetterOrSubpage({
                is_enter_default = true,
                callback = function()
                    local input = self.page_info_text.input_dialog:getInputText():lower()
                    if input:match("[a-z]") then
                        self:gotoCharacter(input)
                        return
                    end
                    local page = tonumber(input)
                    if page and page >= 1 and page <= self.page_num then
                        self:onGotoPage(page)
                        self.page_info_text:closeInputDialog()
                    end
                end,
            }),
        },
    }

    if self.goto_letter then
        title_goto = _("Enter letter or page number")
        type_goto = "string"
        hint_func = function()
            --* @translators First group is the standard range for alphabetic searches, second group is a page number range
            return T(_("(a - z) or (1 - %1)"), self.page_num)
        end
        table.insert(buttons, 1, {
            KOR.buttoninfopopup:forMenuSearchItem({
                callback = function()
                    self.page_info_text:closeInputDialog()
                    UIManager:sendEvent(Event:new("ShowFileSearch", self.page_info_text.input_dialog:getInputText()))
                end,
            }),
            KOR.buttoninfopopup:forMenuToLetter({
                is_enter_default = true,
                callback = function()
                    local search_string = self.page_info_text.input_dialog:getInputText()
                    if search_string == "" then
                        return
                    end
                    search_string = Utf8Proc.lowercase(util.fixUtf8(search_string, "?"))
                    local v, i, filename
                    count = #self.item_table
                    for k = 1, count do
                        v = self.item_table[k]
                        filename = Utf8Proc.lowercase(util.fixUtf8(FFIUtil.basename(v.path), "?"))
                        i = filename:find(search_string)
                        if i == 1 and not v.is_go_up then
                            self:onGotoPage(math.ceil(k / self.perpage))
                            break
                        end
                    end
                    self.page_info_text:closeInputDialog()
                end,
            }),
        })
        table.insert(buttons, {
            KOR.buttoninfopopup:forRecentAdditions({
                callback = function()
                    self.page_info_text:closeInputDialog()
                    KOR.collection:showTiled("Aanwinsten")
                end,
            }),
            KOR.buttoninfopopup:forLeesplan({
                callback = function()
                    self.page_info_text:closeInputDialog()
                    KOR.collection:showTiled("Leesplan")
                end,
            }),
            KOR.buttoninfopopup:forNextBooksToRead({
                callback = function()
                    self.page_info_text:closeInputDialog()
                    KOR.collection:showTiled("Eerstvolgend")
                end,
            }),
        })
    else
        table.insert(buttons[1], 2, KOR.buttoninfopopup:forMenuGotoRandomPage({
            callback = function()
                local page = math.random(1, self.page_num)
                self:onGotoPage(page)
                self.page_info_text:closeInputDialog()
            end,
        }))
        title_goto = _("Enter page number")
        --* was number, but forced to string, because we also can enter first name of author:
        type_goto = "string"
        hint_func = function()
            return string.format("(1 - %s)", self.page_num)
        end
    end

    self.page_info_text = self.page_info_text or Button:new{
        text = "",
        hold_input = {
            title = title_goto,
            type = type_goto,
            hint_func = hint_func,
            buttons = buttons,
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = false,
    }
    local footer_nav_elems = {
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_spacer,
        self.page_info_text,
        self.page_info_spacer,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    --* here also filtered items counted, if applicable:
    self:injectFooterButtons(footer_nav_elems)
    self.page_info = HorizontalGroup:new(footer_nav_elems)

    --* return button
    self.page_return_arrow = self.page_return_arrow or Button:new{
        icon = "back.top",
        callback = function()
            if self.onReturn then self:onReturn() end
        end,
        hold_callback = function()
            if self.onHoldReturn then self:onHoldReturn() end
        end,
        bordersize = 0,
        show_parent = self.show_parent,
        readonly = self.return_arrow_propagation,
    }
    self.page_return_arrow:hide()
    self.return_button = HorizontalGroup:new{
        HorizontalSpan:new{
            width = Size.span.horizontal_small,
        },
        self.page_return_arrow,
    }
    end

    local body = self.item_group
    local footer = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        self.page_info,
    }
    local page_return = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        WidgetContainer:new{
            dimen = Geom:new{
                x = 0, y = 0,
                w = self.screen_w,
                h = self.page_return_arrow:getSize().h,
            },
            self.return_button,
        }
    }

    self:_recalculateDimen()
    self.content_group = self.no_title and VerticalGroup:new{
        align = "left",
        body,
    }
    or
    VerticalGroup:new{
        align = "left",
        self.title_bar,
        body,
    }
    local content = OverlapGroup:new{
        --* This unique allow_mirroring=false looks like it's enough
        --* to have this complex Menu, and all widgets based on it,
        --* be mirrored correctly with RTL languages
        allow_mirroring = false,
        dimen = self.inner_dimen:copy(),
        self.content_group,
        page_return,
        footer,
    }

    self[1] = FrameContainer:new{
        background = KOR.colors.background,
        bordersize = self.border_size,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w * (1/20)) or 0,
        content
    }

    ------------------------------------------
    --* start to set up input event callback --
    ------------------------------------------
    --* watch for outer region if it's a self contained widget
    if self.is_popout then
        self.ges_events.TapCloseAllMenus = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                w = self.screen_w,
                h = self.screen_h,
                }
            }
        }
    end
    --* delegate swipe gesture to GestureManager in filemanager
    if not self.filemanager then
        --* hotfix for swipes not being detected in KOReader's favorites view:
        local range = self.covers_fullscreen and Geom:new{
            x = 0, y = 0,
            w = self.screen_w,
            h = self.screen_h,
        } or self.dimen
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = range,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = range,
            }
        }
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        }
    end
    self.ges_events.Pan = { --* (for mousewheel scrolling support)
        GestureRange:new{
            ges = "pan",
            range = self.dimen,
        }
    }
    self.ges_events.Close = self.on_close_ges

    if not Device:hasKeyboard() then
        --* remove menu item shortcut for K4
        self.is_enable_shortcut = false
    end

    self:registerHotkeys()

    if Device:hasDPad() then
        --* we won't catch presses to "Right", leave that to MenuItem.
        self.key_events.FocusRight = nil
        --* shortcut icon is not needed for touch device
        if self.is_enable_shortcut then
            self.key_events.SelectByShortCut = { {self.item_shortcuts} }
        end
        self.key_events.Right = { { "Right" } }
    end

    if #self.item_table > 0 then
        --* if the table is not yet initialized, this call
        --* must be done manually:
        self.page = math.ceil((self.item_table.current or 1) / self.perpage)
    end
    if self.path_items then
        self:refreshPath()
    else
        self:updateItems()
    end

    --* make Menu instances closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
    --* only show overlay for non fullscreen dialogs; this prevents a lot of ghosts of older overlays which we couldn't close:
    -- #((show overlay for non fullscreen menus))
    if not restore_dialog and not self.fullscreen then
        KOR.dialogs:showOverlayReloaded()
    end
end

function Menu:onShowingReader()
    --* Clear the dither flag to prevent it from infecting the queue and re-inserting a full-screen refresh...
    self.dithered = nil
end
Menu.onSetupShowReader = Menu.onShowingReader

function Menu:onCloseWidget()
    KOR.registry:unset("restore_bookmarks_list")
    --- @fixme
    --* we cannot refresh regionally using the dimen field
    --* because some menus without menu title use VerticalGroup to include
    --* a text widget which is not calculated into the dimen.
    --* For example, it's a dirty hack to use two menus (one being this menu and
    --* the other touch menu) in the filemanager in order to capture tap gesture to popup
    --* the filemanager menu.
    --* NOTE: For the same reason, don't make it flash,
    --*       because that'll trigger when we close the FM and open a book...

    --* Don't do anything if we're in the process of tearing down FM or RD, or if we don't actually have a live instance of 'em...
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    if (FileManager.instance and not FileManager.instance.tearing_down) or (ReaderUI.instance and not ReaderUI.instance.tearing_down) then
        UIManager:setDirty(nil, "ui")
        --* alas, this is needed for fullscreen Menu instances:
        -- self:refreshScreenForFullscreenMenus()
    end

    KOR.dialogs:unregisterWidget(self)
    if self.after_close_callback then
        self:after_close_callback()
    end
    KOR.dialogs:closeOverlay()
end

function Menu:updatePageInfo(select_number)
    --* hotfix:
    self.perpage = tonumber(self.perpage)

    if #self.item_table > 0 then
        if Device:hasDPad() then
            --* reset focus manager accordingly
            self:moveFocusTo(1, select_number)
        end
        --* update page information
        self.page_info_text:setText(T(_("Page %1 of %2"), self.page, self.page_num))
        if self.page_num > 1 then
            self.page_info_text:enable()
        else
            self.page_info_text:disableWithoutDimming()
        end

        local hide_nav_arrows = #self.item_table <= self.perpage
        if not hide_nav_arrows then
            self.page_info_left_chev:show()
            self.page_info_right_chev:show()
            self.page_info_first_chev:show()
            self.page_info_last_chev:show()
        else
            self.page_info_left_chev:hide()
            self.page_info_right_chev:hide()
            self.page_info_first_chev:hide()
            self.page_info_last_chev:hide()
        end
        self.page_return_arrow:showHide(self.onReturn ~= nil)

        self.page_info_left_chev:enableDisable(self.page > 1)
        self.page_info_right_chev:enableDisable(self.page < self.page_num)
        self.page_info_first_chev:enableDisable(self.page > 1)
        self.page_info_last_chev:enableDisable(self.page < self.page_num)
        self.page_return_arrow:enableDisable(#self.paths > 0)
    else
        self.page_info_text:setText(_("No items"))
        self.page_info_text:disableWithoutDimming()

        self.page_info_left_chev:hide()
        self.page_info_right_chev:hide()
        self.page_info_first_chev:hide()
        self.page_info_last_chev:hide()
        self.page_return_arrow:showHide(self.onReturn ~= nil)
    end
end

function Menu:updateItems(select_number)

    local old_dimen = self.dimen and self.dimen:copy()
    --* self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self:_recalculateDimen()

    --* default to select the first item
    if not select_number then
        select_number = 1
    end

    self.font_size = self.items_font_size or G_reader_settings:readSetting("items_font_size")
         or Menu.getItemFontSize(self.perpage)
    local infont_size = self.items_mandatory_font_size or (self.font_size - 4)
    local multilines_show_more_text = self.multilines_show_more_text
    if multilines_show_more_text == nil then
        multilines_show_more_text = G_reader_settings:isTrue("items_multilines_show_more_text")
    end

    local i
    local item_shortcut, shortcut_style, item_tmp
    count = #self.item_table
    local idx_end = math.min(self.perpage, count)
    for idx = 1, idx_end do
        --* calculate index in item_table
        i = (self.page - 1) * self.perpage + idx
        if i <= count then
            self.item_table[i].idx = i --* index is valid only for items that have been displayed
            shortcut_style = "square"
            if self.is_enable_shortcut then
                --* give different shortcut_style to keys in different
                --* lines of keyboard
                if idx >= 11 and idx <= 20 then
                    --*shortcut_style = "rounded_corner"
                    shortcut_style = "grey_square"
                end
                item_shortcut = self.item_shortcuts[idx]
            end
            --local description = self:getAndStoreDescription(i)
            item_tmp = MenuItem:new{
                show_parent = self.show_parent,
                state = self.item_table[i].state,
                state_w = self.state_w or 0,
                text = Menu.getMenuText(self.item_table[i]),
                description = nil,
                bidi_wrap_func = self.item_table[i].bidi_wrap_func,
                post_text = self.item_table[i].post_text,
                mandatory = self.item_table[i].mandatory,
                mandatory_func = self.item_table[i].mandatory_func,
                mandatory_dim = self.item_table[i].mandatory_dim or self.item_table[i].dim,
                mandatory_dim_func = self.item_table[i].mandatory_dim_func,
                bold = self:isBoldItem(i),
                dim = self.item_table[i].dim,
                font = self.item_font,
                font_size = self.font_size,
                infont = "infont",
                infont_size = infont_size,
                --! this MUST be true to enable support for bold words via TextBoxWidget:
                multilines_forced = self.enable_bold_words,
                dimen = self.item_dimen:copy(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                table = self.item_table[i],
                menu = self,
                linesize = self.linesize,
                single_line = self.single_line,
                multilines_show_more_text = multilines_show_more_text,
                truncate_left = self.truncate_left,
                align_baselines = self.align_baselines,
                with_dots = self.with_dots,
                line_color = self.line_color,
                items_padding = self.items_padding,
                handle_hold_on_hold_release = self.handle_hold_on_hold_release,
            }
            table.insert(self.item_group, item_tmp)
            --* this is for focus manager
            table.insert(self.layout, {item_tmp})
        end --* if i <= self.item_table
    end --* for c=1, self.perpage

    self:updatePageInfo(select_number)
    if self.show_path then
        self.title_bar:setSubTitle(BD.directory(filemanagerutil.abbreviate(self.path)))
    end
    -- #((menu add titlebar))
    table.insert(self.layout, self.title)
    self.old_dimen = old_dimen
    self:refreshDialog()
end

--[[
    the itemnumber parameter determines menu page number after switching item table
    1. itemnumber >= 0
        the page number is calculated with items per page
    2. itemnumber == nil
        the page number is 1
    3. itemnumber is negative number
        the page number is not changed, used when item_table is appended with
        new entries

    alternatively, itemmatch may be provided as a {key = value} table,
    and the page number will be the page containing the first item for
    which item.key = value
--]]
function Menu:switchItemTable(new_title, new_item_table, select_number, itemmatch, new_subtitle)
    if select_number == nil then
        self.page = 1
    elseif select_number > 0 then
        self.page = math.ceil(select_number / self.perpage)
    else
        self.page = 1
    end

    if type(itemmatch) == "table" then

        local key, value = next(itemmatch)
        local has_item_filter = key == "filter" and type(value) == "table" and has_text(value.filter)
        local first_filtered_item_found = false

        local item, filter, target_key
        count = #new_item_table
        for num = 1, count do
            item = new_item_table[num]
            if key ~= "filter" and item[key] == value then
                self.page = math.floor((num-1) / self.perpage) + 1
                if not KOR.registry:get("dont_bolden_active_menu_items") then
                    item.bold = true
                end
                break
            elseif has_item_filter then
                filter = value.filter:lower()
                target_key = value.target_key
                if item[target_key]:lower():match(filter) then
                    if not first_filtered_item_found then
                        self.page = math.floor((num - 1) / self.perpage) + 1
                    end
                    first_filtered_item_found = true
                    item.bold = true
                else
                    item.bold = false
                end
            end
        end
    end

    if self.title_bar then
        if not new_title and self.show_filtered_count and self:isFilterActive() then
            new_title = self.title
        end
        if new_title then
            new_title = self:showFilteredItemsCountInTitle(new_title)
            self.title_bar:setTitle(new_title, true)
        end
        if new_subtitle then
            self.title_bar:setSubTitle(new_subtitle, true)
        end
    end

    --* make sure current page is in right page range
    if new_item_table then
        local max_pages = math.ceil(#new_item_table / self.perpage)
        if self.page > max_pages then
            self.page = max_pages
        end
        if self.page <= 0 then
            self.page = 1
        end

        self.item_table = new_item_table
    end
    --* upon first load of Menu, this prop also set in ((Menu#calculatePageNum)):
    KOR.registry:set("menu_active_page", self.page)
    self:updateItems()
end

function Menu:onScreenResize()
    KOR.dialogs:unregisterWidget(self)
    if self.fullscreen then
        self:init()
        return false
    end

    --* for non fullscreen Menus:
    KOR.dialogs:closeAllOverlays()
    self:init("restore_dialog")
    return false
end

function Menu:onSelectByShortCut(_, keyevent)
    local v
    count = #self.item_shortcuts
    for k = 1, count do
        v = self.item_shortcut[k]
        if k > self.perpage then
            break
        elseif v == keyevent.key then
            if self.item_table[(self.page - 1) * self.perpage + k] then
                self:onMenuSelect(self.item_table[(self.page - 1) * self.perpage + k])
            end
            break
        end
    end
    return true
end

function Menu:onShowGotoDialog()
    if self.page_info_text and self.page_info_text.hold_input then
        self.page_info_text:onInput(self.page_info_text.hold_input)
    end
    return true
end

function Menu:onWrapFirst()
    if self.page > 1 then
        self.page = self.page - 1
        local end_position = self.perpage
        if self.page == self.page_num then
            end_position = #self.item_table % self.perpage
        end
        self:updateItems(end_position)
    end
    return false
end

function Menu:onWrapLast()
    if self.page < self.page_num then
        self:onNextPage()
    end
    return false
end

--[[
override this function to process the item selected in a different manner
]]
function Menu:onMenuSelect(item)
    if item.sub_item_table == nil then
        if item.select_enabled == false then
            return true
        end
        if item.select_enabled_func then
            if not item.select_enabled_func() then
                return true
            end
        end
        self:onMenuChoice(item)
        if self.close_callback then
            self.close_callback()
        end
    else
        --* save menu title for later resume
        self.item_table.title = self.title
        table.insert(self.item_table_stack, self.item_table)
        self:switchItemTable(item.text, item.sub_item_table)
    end
    return true
end

--[[
    default to call item callback
    override this function to handle the choice
--]]
function Menu:onMenuChoice(item)
    if item.callback then
        KOR.registry:set("menu_select_number", self.page * self.perpage - 1)
        item.callback()
    end
    return true
end

--[[
override this function to process the item hold in a different manner
]]
function Menu:onMenuHold()
    return true
end

function Menu:onNextPage()

    if self.onNext and self.page == self.page_num - 1 then
        self:onNext()
    end

    if self.page < self.page_num then
        self.page = self.page + 1
        self:updateItems()
    elseif self.page == self.page_num then
        --* on the last page, we check if we're on the last item
        local end_position = #self.item_table % self.perpage
        if end_position == 0 then
            end_position = self.perpage
        end
        if end_position ~= self.selected.y then
            self:updateItems(end_position)
        end
        self.page = 1
        self:updateItems()
    end
    self:storeActivePage()
    self:refreshDialog()
    self:updateHotkeys()
    self:registerCollectionSubPage("register_collection_subpage")
    return true
end

function Menu:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
    elseif self.page == 1 then
        self.page = self.page_num
    end
    self:storeActivePage()
    self:updateItems()
    self:refreshDialog()
    self:updateHotkeys()
    self:registerCollectionSubPage("register_collection_subpage")
    return true
end

function Menu:onFirstPage()
    self.page = 1
    self:storeActivePage()
    self:updateItems()
    self:refreshDialog()
    self:updateHotkeys()
    self:registerCollectionSubPage("register_collection_subpage")
    return true
end

function Menu:onLastPage()
    self.page = self.page_num
    self:storeActivePage()
    self:updateItems()
    self:refreshDialog()
    self:updateHotkeys()
    self:registerCollectionSubPage("register_collection_subpage")
    return true
end

function Menu:onGotoPage(page)
    self.page = page
    self:storeActivePage()
    self:updateItems()
    self:refreshDialog()
    self:updateHotkeys()
    self:registerCollectionSubPage("register_collection_subpage")
    return true
end

function Menu:onRight()
    return self:sendHoldEventToFocusedWidget()
end

function Menu:onClose()
    local table_length = #self.item_table_stack
    if table_length == 0 then
        self:onCloseAllMenus()
    else
        --* back to parent menu
        local parent_item_table = table.remove(self.item_table_stack, table_length)
        self:switchItemTable(parent_item_table.title, parent_item_table)
    end
    KOR.registry:unset("hotkeys_update_method")
    KOR.screenhelpers:refreshUI()
    return true
end

function Menu:onCloseAllMenus()
    KOR.registry:unset("restore_bookmarks_list")
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function Menu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:onCloseAllMenus()
        self.garbage = arg
        return true
    end
end

function Menu:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
        self.garbage = arg
    elseif KOR.system:isClosingGesture(direction) then
        if not self.no_title then
            --* If there is a close button displayed (so, this Menu can be
            --* closed), allow easier closing with swipe south.
            self:onClose()
        end
        --* If there is no close button, it's a top level Menu and swipe
        --* up/down may hide/show top menu
    elseif direction == "north" then
        --* no use for now
        return --* luacheck: ignore 541
    else --* diagonal swipe
        --* trigger full refresh
        UIManager:setDirty(nil, "full")
    end
end

function Menu:onPan(arg, ges_ev)
    if ges_ev.mousewheel_direction then
        if ges_ev.direction == "north" then
            self:onNextPage()
        elseif ges_ev.direction == "south" then
            self:onPrevPage()
            self.garbage = arg
        end
    end
    return true
end

function Menu:onMultiSwipe()
    --* For consistency with other fullscreen widgets where swipe south can't be
    --* used to close and where we then allow any multiswipe to close, allow any
    --* multiswipe to close this widget too.
    if not self.no_title then
        --* If there is a titlebar with a close button displayed (so, this Menu can be
        --* closed), allow easier closing with swipe south.
        self:onClose()
    end
    return true
end

function Menu:setTitleBarLeftIcon(icon)
    if self.top_buttons_left then
        self.title_bar:setLeftIcon(icon)
    end
end

function Menu:onLeftNavButtonTap() --* to be overriden and implemented by the caller
end

function Menu:getFirstVisibleItemIndex()
    return self.item_group[1].idx
end

--- Adds > to touch menu items with a submenu
local arrow_left  = "◂" --* U+25C2 BLACK LEFT-POINTING SMALL TRIANGLE
local arrow_right = "▸" --* U+25B8 BLACK RIGHT-POINTING SMALL TRIANGLE
local sub_item_format
--* Adjust arrow direction and position for menu with sub items
--* according to possible user choices
if BD.mirroredUILayout() then
    if BD.rtlUIText() then --* normal case with RTL language
        sub_item_format = "%s " .. BD.rtl(arrow_left)
    else --* user reverted text direction, so LTR
        sub_item_format = BD.ltr(arrow_left) .. " %s"
    end
else
    if BD.rtlUIText() then --* user reverted text direction, so RTL
        sub_item_format = BD.rtl(arrow_right) .. " %s"
    else --* normal case with LTR language
        sub_item_format = "%s " .. BD.ltr(arrow_right)
    end
end

function Menu.getItemFontSize(perpage)
    --* Get adjusted font size for the given nb of items per page:
    --* item font size between 14 and 24 for better matching
    return math.floor(24 - ((perpage - 6) * (1/18)) * 10)
end

function Menu.getItemMandatoryFontSize(perpage)
    --* Get adjusted font size for the given nb of items per page:
    --* "mandatory" font size between 12 and 18 for better matching
    return math.floor(18 - (perpage - 6) * (1/3))
end

function Menu.getMenuText(item)
    local text
    if item.text_func then
        text = item.text_func()
    else
        text = item.text
    end
    if item.sub_item_table ~= nil or item.sub_item_table_func then
        text = string.format(sub_item_format, text)
    end
    return text
end

function Menu.itemTableFromTouchMenu(t)
    local item_t = {}
    local item
    for k, v in FFIUtil.orderedPairs(t) do
        item = { text = k }
        if v.callback then
            item.callback = v.callback
        else
            item.sub_item_table = v
        end
        table.insert(item_t, item)
    end
    return item_t
end

--* ==================== SMARTSCRIPTS =====================

--* fix for KOReaders fullscreen Menus not updating when navigating through subpages or closing them:
--* also now used to register subpages of collection dialogs:
function Menu:registerCollectionSubPage(register_collection_subpage)
    -- #((set collection subpage))
    if register_collection_subpage and self.collection then
        local iselect_number = self.perpage * self.page - 1
        KOR.dialogs.collection_dialogs_subpages[self.collection] = iselect_number
    end
end

function Menu:getCurrentPage(select_number)
    return math.floor(select_number / self.perpage) + 1
end

function Menu:gotoCharacter(input)
    local letter = input or self.page_info_text.input_dialog:getInputText():lower()
    if has_text(letter) then
        local text, word_start, page
        count = #self.item_table
        for nr = 1, count do
            text = self.item_table[nr].text
            word_start = text:match("([A-Za-z]+)")
            if word_start and word_start:sub(1, 1):lower() == letter then
                page = math.ceil(nr / self.perpage)
                self:onGotoPage(page)
                self.page_info_text:closeInputDialog()
                return
            end
        end
        KOR.messages:notify("geen items gevonden, beginnend met " .. letter)
    end
end

function Menu:onGotoItemNr(nr)
    local page = math.ceil(nr / self.perpage)
    self:onGotoPage(page)
end

function Menu:getFilterButton(callback, reset_callback, hold_callback)
    local filter_active = self:isFilterActive()

    self:addHotkeyForFilterButton(filter_active, callback, reset_callback)

    local filter_button_config = {
        icon = not filter_active and "filter" or "filter-reset",
        --* to make the icon more easily tappable:
        padding_left = Size.padding.outerfooterbutton,
        show_parent = self.show_parent,
        callback_label = filter_active and "reset" or "filter",
        callback = function()
            self:resetAllBoldItems()
            if filter_active then
                reset_callback()
            else
                callback()
            end
        end,
    }
    if not filter_active then
        filter_button_config.info = "filter-ikoon | Geef een term op waarop deze lijst gefilterd moet worden."
    elseif hold_callback then
        filter_button_config.info = "filter-reset-ikoon | hoofdfunctie arrow reset het filter\nnevenfunctie arrow geef een nieuw filter op"
        filter_button_config.hold_callback_label = "nieuw filter"
        filter_button_config.hold_callback = hold_callback
    end
    return Button:new(KOR.buttoninfopopup:forMenuFilterButton(filter_button_config))
end

--* insert footer buttons; additionally optionally inserts a filter button at the left end and an inverted page keys indicator at the right end:
function Menu:injectFooterButtons(footer_nav_elems)

    local nav_spacer = self.page_info_spacer
    local button, left_padding_arg, right_padding_arg
    if self.footer_buttons_left then
        count = #self.footer_buttons_left
        for i = 1, count do
            left_padding_arg = not self.filter and i == 1 and "is_first_button_left"
            button = self:instantiateButton(self.footer_buttons_left[i], left_padding_arg)
            table.insert(footer_nav_elems, 1, button)
            table.insert(footer_nav_elems, 2, nav_spacer)
        end
    end
    if self.footer_buttons_right then
        count = #self.footer_buttons_right
        for i = 1, count do
            right_padding_arg = i == count and "is_last_button_right"
            table.insert(footer_nav_elems, nav_spacer)
            button = self:instantiateButton(self.footer_buttons_right[i], nil, right_padding_arg)
            table.insert(footer_nav_elems, button)
        end
    end

    if self.filter then
        local f = self.filter
        local filter_button = self:getFilterButton(f.callback, f.reset_callback, f.hold_callback)
        table.insert(footer_nav_elems, 1, nav_spacer)
        table.insert(footer_nav_elems, 1, filter_button)
    end
end

function Menu:calculatePageNum()
    self.page_num = math.ceil(#self.item_table / self.perpage)
    --* fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then
        self.page = self.page_num
    end
    self:storeActivePage()
end

function Menu:isFilterActive()
    if not self.filter then
        return false
    end
    --* self.filter.state can be defined for non text filtering, e.g. in ((XrayController#onShowList)) > ((filter table example)):
    return self.filter.state == "filtered" or has_text(self.filter.filter)
end

function Menu:isBoldItem(i)
    if self:isFilterActive() then
        return false
    end
    if self.item_table[i].bold then
        return true
    end
    return self.item_table.current == i
end

function Menu:resetAllBoldItems()
    count = #self.item_table
    for i = 1, count do
        self.item_table[i].bold = false
    end
end

function Menu:showFilteredItemsCountInTitle(new_title)
    if not new_title then
        return
    end
    if self.show_filtered_count and self:isFilterActive() then
        local filtered_count = 0
        count = #self.item_table
        for i = 1, count do
            if self.item_table[i].bold == true then
                filtered_count = filtered_count + 1
            end
        end

        new_title = new_title .. " (" .. self.filter.filter .. ": " .. filtered_count .. ")"
    end
    return new_title
end

function Menu:refreshTabButtons(tab_buttons_left, tab_buttons_right)
    self.title_bar:refreshTabButtons(tab_buttons_left, tab_buttons_right)
end

--* called via ((Menu#onScreenResize)) > ((Menu#init)):
function Menu:restoreTitleAfterScreenResize()
    local restore_title = KOR.registry:getOnce("restore_title")
    if restore_title and self.title == "Geen titel" then
        self.title = restore_title
    end
end

function Menu:storeActivePage()
    if self.module then
        KOR.registry:setMenuPage(self.module, self.page)
    else
        KOR.registry:set("menu_active_page", self.page)
    end
end

--* under Android, text characters and previous subpage covers were showing through the book covers:
function Menu:refreshDialog()

    if (G_reader_settings:isNilOrFalse("fast_menu_display") and self.covers_fullscreen)
    or
    (not self.old_dimen and not self.dimen) then
        --KOR.screenhelpers:refreshScreen()
        UIManager:setDirty(self.layout, "full")
    else
        UIManager:setDirty(self.show_parent, function()
            local refresh_dimen = self.old_dimen and self.old_dimen:combine(self.dimen)
                    or self.dimen
            return "ui", refresh_dimen
        end)
    end
end

function Menu:detectAndSetFullscreenState()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    if self.width == self.screen_w and self.height == self.screen_h then
        --* to prevent unnecessary showing of overlay in ((Menu#init)) > ((show overlay for non fullscreen menus)):
        self.fullscreen = true
        self.is_borderless = true
        self.is_popout = false
    end
end

function Menu:instantiateButton(button, is_first_button_left, is_last_button_right)
    local is_table = type(button) == "table"
    if not DX.s.is_mobile_device or not is_table then
        self:addPaddingForFirstAndLastFooterButtons(button, is_first_button_left, is_last_button_right)
        return is_table and Button:new(button) or button
    end

    button.icon_size_ratio = button.icon_size_ratio and button.icon_size_ratio or 0.6
    button.icon_size_ratio = math.floor(button.icon_size_ratio)
    self:addPaddingForFirstAndLastFooterButtons(button, is_first_button_left, is_last_button_right)
    return Button:new(button)
end

function Menu:addPaddingForFirstAndLastFooterButtons(button, is_first_button_left, is_last_button_right)
    if is_first_button_left then
        button.padding_left = Size.padding.outerfooterbutton
    elseif is_last_button_right then
        button.padding_right = Size.padding.outerfooterbutton
    end
end

function Menu:onPrevPageWithShiftSpace()
    self:onPrevPage()
end

function Menu:addHotkeyForFilterButton(filter_active, callback, reset_callback)

    --* because in FileManagerHistory "F" hotkey has been used for activation of Fiction tab, only there use Shift+F:
    local hotkey = KOR.registry:get("history_active") and { { "Shift", { "F" } } } or { { "F" } }
    self:registerCustomKeyEvent(hotkey, "FilterMenu", function()
        self:resetAllBoldItems()
        if filter_active then
            reset_callback()
        else
            callback()
        end
        return true
    end)
end

function Menu:onLoadCollectionItem(no)
    local item_no = (self.page - 1) * self.perpage + no

    local full_path = self.item_table[item_no].file
    UIManager:close(self)
    KOR.files:openFile(full_path)
end

function Menu:onShowCollectionItemInfo(no)
    local item_no = (self.page - 1) * self.perpage + no

    local full_path = self.item_table[item_no].file
    KOR.descriptiondialog:show(false, full_path)
end

function Menu:registerHotkeys()
    if Device:hasKeys() then
        --* set up keyboard events
        self.key_events.Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
        self.key_events.PrevPageWithShiftSpace = Input.group.ShiftSpace

        if self.tab_labels and self.activate_tab_callback then
            self:registerTabHotkeys()
        end
    end
end

function Menu:updateHotkeys()
    if self.hotkey_updater then
        self.hotkey_updater()
    end
end

function Menu:registerCustomKeyEvent(hotkey, handler_label, handler_callback)
    self["on" .. handler_label] = handler_callback
    self.key_events[handler_label] = type(hotkey) == "table" and hotkey or { { hotkey } }
end

function Menu:registerTabHotkeys()
    local action, hotkey
    count = #self.tab_labels
    for i = 1, count do
        local current = i
        action = self.tab_labels[current]
        hotkey = action:sub(1, 1):upper()
        self:registerCustomKeyEvent(hotkey, "ActivateTab_" .. action, function()
            return self:activateTab(current)
        end)
    end
end

function Menu:activateTab(tab_no)
    self.activate_tab_callback(tab_no)
end

return Menu
