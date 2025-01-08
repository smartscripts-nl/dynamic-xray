local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Registry = require("extensions/registry")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

--- @class TitleBar
local TitleBar = OverlapGroup:extend {

    -- Internal: remember first sizes computed when title_shrink_font_to_fit=true,
    -- and keep using them after :setTitle() in case a smaller font size is needed,
    -- to keep the TitleBar geometry stable.
    _initial_title_top_padding = nil,
    _initial_title_text_baseline = nil,
    _initial_titlebar_height = nil,
    _initial_filler_height = nil,
    _initial_re_init_needed = nil,

    width = nil, -- default to screen width
    fullscreen = false, -- larger font and small adjustments if fullscreen
    align = "center", -- or "left": title & subtitle alignment inside TitleBar ("right" nor supported)

    title = "",
    title_face = nil, -- if not provided, one of these will be used:
    title_face_fullscreen = Font:getFace("smalltfont"),
    title_face_not_fullscreen = Font:getFace("x_smalltfont"),
    -- by default: single line, truncated if overflow -- the default could be made dependant on self.fullscreen
    title_multilines = false, -- multilines if overflow
    title_shrink_font_to_fit = false, -- reduce font size so that single line text fits

    subtitle = nil,
    subtitle_face = Font:getFace("xx_smallinfofont"),
    subtitle_truncate_left = false, -- default with single line is to truncate right (set to true for a filepath)
    subtitle_fullwidth = false, -- true to allow subtitle to extend below the buttons
    subtitle_multilines = false, -- multilines if overflow

    info_text = nil, -- additional text displayed below bottom line
    info_text_face = Font:getFace("x_smallinfofont"),
    info_text_h_padding = nil, -- default to title_h_padding

    lang = nil, -- use this language (string) instead of the UI language

    title_top_padding = 0, -- computed if none provided
    title_h_padding = Size.padding.large, -- horizontal padding (this replaces button_padding on the inner/title side)
    title_subtitle_v_padding = Screen:scaleBySize(3),
    bottom_v_padding = nil, -- hardcoded default values, different whether with_bottom_line true or false

    button_padding = Screen:scaleBySize(11), -- fine to keep exit/cross icon diagonally aligned with screen corners

    with_bottom_line = false,
    bottom_line_color = nil, -- default to black
    bottom_line_h_padding = nil, -- default to 0: full width
    bottom_line_thickness = Size.line.thick,

    -- set any of these _callback to false to not handle the event
    -- and let it propagate; otherwise the event is discarded
    -- If provided, use right_icon="exit" and use this as right_icon_tap_callback
    close_callback = nil,
    close_hold_callback = nil,

    show_parent = nil,

    --- PROPS BY SMARTSCRIPTS ---

    desired_height = nil,
    desired_heights = {
        android = 80,
        ubuntu = 46,
    },
    left_buttons_height = 0,
    title_height = 0,
    right_buttons_height = 0,
    has_small_close_button_padding = false,

    has_only_close_button = false,
    for_collection = false,
    less_icon_top_padding = nil,
    no_close_button_padding = false,
    menu_instance = self,

    -- TitleBar for FileManager initialized in ((FileManager#setupLayout)) and ((FileManager#showFiles)) > ((set FileManager subtitle)) or ((set FileManager title and subtitle on path change)) > ((FileManager#setTitleAndSubTitle)) > ((FileChooser#getFilesCount)):
    --- for FileChooser, a subclass of Menu, its no_title prop will be set to true, because FileManager already provided a TitleBar:
    for_filemanager = false,

    -- info: tab buttons IN THE LEFT HALF of the titlebar itself:
    -- must be a table with real Buttons:
    tab_buttons = nil,

    -- info: icon buttons IN the titlebar itself, at the left and the right (there for now only close button):
    -- if given as table, table items must have these props: icon, icon_size_ratio, rotation_angle, callback, hold_callback, allow_flash:
    top_buttons_left = nil,
    top_buttons_right = nil,

    -- info: submenu BELOW the title bar:
    submenu_buttontable = nil,

    -- ! will be set to true when top_buttons_left or top_buttons_right or tab_buttons are set:
    has_top_buttons = false,
}

function TitleBar:init()

    --local has_left_buttons = self.top_buttons_left or self.tab_buttons
    -- for forms with tab buttons, always center the title:
    if self.tab_buttons then
        self.align = "center"
    end
    --- we don't want an in-your-face bottom line in case of fullscreen dialogs:
    if self.fullscreen and self.with_bottom_line then
        self.bottom_line_color = Blitbuffer.COLOR_GRAY
        self.bottom_line_thickness = Size.line.small
    end

    self.has_top_buttons = self.top_buttons_left or self.top_buttons_right or self.tab_buttons

    self.left_buttons_container = HorizontalGroup:new {
        -- ! "left" and "right" not allowed for HorizontalGroups !
        align = "center",
    }
    self.right_buttons_container = HorizontalGroup:new {
        align = "center",
    }
    self.submenu_buttontable_container = HorizontalGroup:new {
        align = "center",
    }

    self:addCloseButton()

    if not self.width then
        self.width = Screen:getWidth()
    end
    self:setDesiredHeight()

    self:setTopButtonsSizeAndCallbacks()
    self:populateTopButtonsGroups()
    -- we either have icon button in the left half of the titlebar, or tab buttons:
    if not self.top_buttons_left then
        self:populateTabButtonsGroup()
    end
    self:populateSubMenuButtons()

    --- this is de facto the title text:
    self:injectCenterContainerForTitle()

    -- ! to actually see all items, it is important that the left and right containers are inserted AFTER the center/title container:
    if self.has_top_buttons then
        self:injectSideContainers()
    end

    self:injectBottomLine()

    if self._initial_re_init_needed then
        -- We have computed all the self._initial_ metrics needed.
        self._initial_re_init_needed = nil
        self:clear()
        self:init()
        return
    end

    self:injectSubTitle()

    self.dimen = Geom:new {
        x = 0,
        y = 0,
        w = self.width,
        h = self.titlebar_height, -- buttons can overflow this
    }

    -- Call our base class's init (especially since OverlapGroup has very peculiar self.dimen semantics...)
    OverlapGroup.init(self)
end

function TitleBar:paintTo(bb, x, y)
    -- We need to update self.dimen's x and y for any ges.pos:intersectWith(title_bar)
    -- to work. (This is done by FrameContainer, but not by most other widgets... It
    -- should probably be done in all of them, but not sure of side effects...)
    self.dimen.x = x
    self.dimen.y = y
    OverlapGroup.paintTo(self, bb, x, y)
end

function TitleBar:getHeight()
    return self.titlebar_height
end

function TitleBar:setTitle(title, no_refresh)
    if self.title_multilines or self.title_shrink_font_to_fit then
        -- We need to re-init the whole widget as its height or
        -- padding may change.
        local previous_height = self.titlebar_height
        -- Call WidgetContainer:clear() that will call :free() and
        -- will remove subwidgets from the OverlapGroup we are.
        self:clear()
        self.title = title
        self:init()
        if no_refresh then
            -- If caller is sure to handle refresh correctly, it can provides this
            return
        end
        if self.title_multilines and self.titlebar_height ~= previous_height then
            -- Title height have changed, and the upper widget may not have
            -- hooks to refresh a combination of its previous size and new
            -- size: be sure everything is repainted
            UIManager:setDirty("all", "ui")
        else
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
    else
        -- TextWidget with max-width: we can just update its text
        self.title_widget:setText(title)
        if self.inner_title_group then
            self.inner_title_group:resetLayout()
        end
        self.title_group:resetLayout()
        if no_refresh then
            return
        end
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setSubTitle(subtitle)
    if self.subtitle_widget and not self.subtitle_multilines then
        -- no TextBoxWidget:setText() available
        self.subtitle_widget:setText(subtitle)
        if self.inner_subtitle_group then
            self.inner_subtitle_group:resetLayout()
        end
        self.title_group:resetLayout()
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setLeftIcon(icon)
    if self.top_buttons_left then
        self.left_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setRightIcon(icon)
    if self.top_buttons_right then
        self.right_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

-- ======================== ADDED =======================

-- compare ((TitleBar#setTopButtonsSizeAndCallbacks))
-- compare final injection in ((TitleBar#populateTopButtonsGroups))
function TitleBar:getAdaptedTopButton(button)

    -- paddings for buttons are ignored in OverlapGroups:
    return Button:new{
        icon = button.icon,
        icon_rotation_angle = button.rotation_angle or 0,
        icon_width = button.icon_size,
        icon_height = button.icon_size,
        icon_size_ratio = button.icon_size_ratio or 0.6,
        bordersize = 0,
        callback = button.callback,
        hold_callback = button.hold_callback,
        decrease_top_padding = button.decrease_top_padding,
        increase_top_padding = button.increase_top_padding,
        allow_flash = G_reader_settings:isNilOrFalse("night_mode"),
        show_parent = self.show_parent,
    }
end

function TitleBar:setButtonProps(button)
    local new_button = {}
    local icon_size_ratio = button.icon_size_ratio or 0.6
    for name, prop in pairs(button) do
        new_button[name] = prop
    end
    if not new_button.icon_size_ratio then
        new_button.icon_size_ratio = icon_size_ratio
        new_button.icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * icon_size_ratio)
    end
    new_button.callback = function()
        button.callback(self.menu_instance)
    end

    if button.hold_callback then
        new_button.hold_callback = function()
            button.hold_callback(self.menu_instance)
        end
    end
end

-- compare ((TitleBar#getAdaptedTopButton))
-- compare final injection in ((TitleBar#populateTopButtonsGroups))
function TitleBar:setTopButtonsSizeAndCallbacks()
    self.has_only_close_button = not self.top_buttons_left and self.top_buttons_right and true or false
    for i = 1, 2 do
        local source = i == 1 and self.top_buttons_left or self.top_buttons_right
        if source then
            for _, button in ipairs(source) do
                button = self:setButtonProps(button)
            end
        end
    end
end

function TitleBar:injectCenterContainerForTitle()

    local top_left_buttons_reserved_width = 0
    local top_right_buttons_reserved_width = 0
    if self.top_buttons_left then
        top_left_buttons_reserved_width = self.left_buttons_container:getSize().w
    end
    if self.top_buttons_right then
        top_right_buttons_reserved_width = self.right_buttons_container:getSize().w
    end
    if self.align == "center" and (self.top_buttons_left or self.top_buttons_right) then
        -- Keep title and subtitle text centered even if single button
        top_left_buttons_reserved_width = math.max(top_left_buttons_reserved_width, top_right_buttons_reserved_width)
        top_right_buttons_reserved_width = top_left_buttons_reserved_width
    end

    local title_max_width = self.width - 2 * self.title_h_padding - top_left_buttons_reserved_width - top_right_buttons_reserved_width
    local subtitle_max_width = self.width - 2 * self.title_h_padding
    local width = self.width

    -- Title, subtitle, and their alignment
    local title_face = self.title_face
    if not title_face then
        title_face = self.fullscreen and self.title_face_fullscreen or self.title_face_not_fullscreen
    end
    -- for align == "left" we need width correction, to make sure the titlebar doesnot overlap the right title bar border:
    if self.title_multilines and self.align ~= "left" then
        self.title_widget = TextBoxWidget:new {
            text = self.title,
            alignment = self.align,
            width = width,
            face = title_face,
            lang = self.lang,
        }
    else
        while true do
            self.title_widget = TextWidget:new {
                text = self.title,
                face = title_face,
                padding = 0,
                lang = self.lang,
                max_width = not self.title_shrink_font_to_fit and title_max_width,
                -- truncate if not self.title_shrink_font_to_fit
            }
            if not self.title_shrink_font_to_fit then
                break -- truncation allowed, no loop needed
            end
            if self.title_widget:getWidth() <= title_max_width then
                break -- text with normal font fits, no loop needed
            end
            -- Text doesn't fit
            if not self._initial_titlebar_height then
                -- We're with title_shrink_font_to_fit and in the first :init():
                -- we don't want to go on measuring with this too long text.
                -- We want metrics proper for when text fits, so if later :setTitle()
                -- is called with a text that fits, this text will look allright.
                -- Longer title with a smaller font size should be laid out on the
                -- baseline of a fitted text.
                -- So, go on computing sizes with an empty title. When all is
                -- gathered, we'll re :init() ourselves with the original title,
                -- using the metrics we're computing now (self._initial*).
                self._initial_re_init_needed = true
                self.title_widget:free(true)
                self.title_widget = TextWidget:new {
                    text = "",
                    face = title_face,
                    padding = 0,
                }
                break
            end
            -- otherwise, loop and do the same with a smaller font size
            self.title_widget:free(true)
            title_face = Font:getFace(title_face.orig_font, title_face.orig_size - 1)
        end
    end

    self.subtitle_widget = nil
    if self.subtitle then
        if self.subtitle_multilines then
            self.subtitle_widget = TextBoxWidget:new {
                text = self.subtitle,
                alignment = self.align,
                width = subtitle_max_width,
                face = self.subtitle_face,
                lang = self.lang,
            }
        else
            self.subtitle_widget = TextWidget:new {
                text = self.subtitle,
                face = self.subtitle_face,
                max_width = subtitle_max_width,
                truncate_left = self.subtitle_truncate_left,
                padding = 0,
                lang = self.lang,
            }
        end
    end

    self.title_group = VerticalGroup:new {
        align = self.align,
    }
    self.title_group_vertically_centered = VerticalGroup:new {
        align = self.align,
    }
    self.subtitle_group = VerticalGroup:new {
        align = self.align,
    }

    if self.align == "left" then
        -- we need to :resetLayout() both VerticalGroup and HorizontalGroup in :setTitle()

        local title_elems = {
            HorizontalSpan:new { width = top_left_buttons_reserved_width + self.title_h_padding },
        }
        table.insert(title_elems, self.title_widget)
        self.inner_title_group = HorizontalGroup:new(title_elems)
        table.insert(self.title_group, self.inner_title_group)
    else
        table.insert(self.title_group, self.title_widget)
    end
    if self.subtitle_widget then
        table.insert(self.subtitle_group, VerticalSpan:new { width = self.title_subtitle_v_padding })
        if self.align == "left" then
            local span_width = self.title_h_padding
            if not self.subtitle_fullwidth then
                span_width = span_width + top_left_buttons_reserved_width
            end
            self.inner_subtitle_group = HorizontalGroup:new {
                HorizontalSpan:new { width = span_width },
                self.subtitle_widget,
            }
            table.insert(self.subtitle_group, self.inner_subtitle_group)
        else
            table.insert(self.subtitle_group, self.subtitle_widget)
        end
    end

    local title_dims = self.title_widget:getSize()
    self.title_height = title_dims.h
    self.title_width = title_dims.w
    self.subtitle_width = 0
    if self.subtitle_widget then
        local subtitle_dims = self.subtitle_widget:getSize()
        self.title_height = self.title_height + subtitle_dims.h
        self.subtitle_width = subtitle_dims.w
    end
    local padding_for_vertical_centering = self:computeVerticalPadding(self.title_height)
    if self.align == "left" then
        padding_for_vertical_centering = padding_for_vertical_centering + 1
    end

    if self.submenu_buttontable then
        table.insert(self.title_group, self.submenu_buttontable_container)
        local line_widget = LineWidget:new {
            dimen = Geom:new { w = self.width, h = self.bottom_line_thickness },
            background = Blitbuffer.COLOR_GRAY_9
        }
        table.insert(self.title_group, line_widget)
    end

    -- info: for titlebars without top buttons we need some bottom padding (but less then with top buttons):
    local no_top_buttons_correction = 4
    if not self.has_top_buttons then
        padding_for_vertical_centering = padding_for_vertical_centering - no_top_buttons_correction
    end
    table.insert(self.title_group_vertically_centered, VerticalSpan:new { width = padding_for_vertical_centering })
    table.insert(self.title_group_vertically_centered, self.title_group)
    -- info: for titlebars without top buttons we need some extra bottom padding (but less then with top buttons):
    if not self.has_top_buttons then
        padding_for_vertical_centering = padding_for_vertical_centering + no_top_buttons_correction + 1
        table.insert(self.title_group_vertically_centered, VerticalSpan:new { width = padding_for_vertical_centering })
    end

    self.center_container = VerticalGroup:new {
        align = self.align,
        overlap_align = self.align,
        self.title_group_vertically_centered,
    }
    if self.align == "left" and self.subtitle_widget then
        table.insert(self.center_container, self.subtitle_group)
    end

    -- This TitleBar widget is an OverlapGroup: all sub elements overlap,
    -- and can overflow or underflow. Its height for its containers is
    -- the one we set as self.dimen.h.

    if self.title_shrink_font_to_fit then
        -- Use, or store, the first title_group height we have computed,
        -- so the TitleBar geometry and the bottom line position stay stable
        -- (face height may have changed, even after we kept the baseline
        -- stable, as we did above).
        if self._initial_titlebar_height then
            self.titlebar_height = self._initial_titlebar_height
        else
            self._initial_titlebar_height = self.titlebar_height
        end
    end

    if self.align == "center" and self.subtitle_widget then
        table.insert(self.center_container, self.subtitle_widget)
        --- we need this extra CenterContainer as wrapper to make sure that title and subtitle are nicely centered as one module:
        self.center_container = CenterContainer:new {
            dimen = Geom:new { w = math.max(self.title_width, self.subtitle_width), h = self.title_height },
            align = self.align,
            overlap_align = self.align,
            self.center_container,
        }
    end

    if self.has_top_buttons then
        local titlebar_bottom_spacer = VerticalSpan:new { width = Size.padding.button }
        table.insert(self.center_container, titlebar_bottom_spacer)
    end

    self.titlebar_height = self.center_container:getSize().h

    table.insert(self, self.center_container)
end

function TitleBar:addCloseButton()
    if self.close_callback then
        self.top_buttons_right = {
            {
                icon = "close",
                icon_size_ratio = 0.4,
                callback = function()
                    self.close_callback()
                end,
            }
        }
        if self.close_hold_callback then
            self.top_buttons_right[1].hold_callback = function()
                self.close_hold_callback()
            end
        end
    end
end

-- compare ((TitleBar#setTopButtonsSizeAndCallbacks))
-- compare ((TitleBar#getAdaptedTopButton))
--- the groups generated here are only horizontally qua orientation
function TitleBar:populateTopButtonsGroups()
    local spacer_width = Size.padding.titlebarbutton
    if self.top_buttons_left then
        if Registry.is_android_device then
            spacer_width = Size.padding.fullscreen
        end
        local horizontal_spacer = HorizontalSpan:new { width = spacer_width }
        for nr, button in ipairs(self.top_buttons_left) do
            if nr == 1 then
                table.insert(self.left_buttons_container, horizontal_spacer)
            end
            button = self:getAdaptedTopButton(button)
            -- to e.g. give ((bm_menu#toggleSelectMode)) > ((Menu#setTitleBarLeftIcon)) > ((TitleBar#setLeftIcon)) a button for which to modify the icon:
            if nr == 1 then
                self.left_button = button
            end
            table.insert(self.left_buttons_container, button)
            if nr < #self.top_buttons_left then
                table.insert(self.left_buttons_container, horizontal_spacer)
            end
        end
        self.left_buttons_height = self.left_buttons_container:getSize().h
    end
    if self.top_buttons_right then
        local horizontal_spacer = HorizontalSpan:new { width = spacer_width }
        for nr, button in ipairs(self.top_buttons_right) do
            if nr < #self.top_buttons_right then
                table.insert(self.right_buttons_container, horizontal_spacer)
            end
            button = self:getAdaptedTopButton(button)
            -- to e.g. give ((FileManager#onToggleSelectMode)) > ((TitleBar#setRightIcon)) a button for which to modify the icon:
            if nr == 1 then
                self.right_button = button
            end

            table.insert(self.right_buttons_container, button)
        end
        self:addCloseButtonRightSpacer()
        self.right_buttons_height = self.right_buttons_container:getSize().h
    end
end

function TitleBar:addCloseButtonRightSpacer()
    if self.for_filemanager or self.has_small_close_button_padding then
        table.insert(self.right_buttons_container, HorizontalSpan:new { width = Size.padding.titlebar })
    elseif not self.fullscreen then
        -- to simulate right margin for close button:
        local right_border_spacer = HorizontalSpan:new { width = Size.padding.closebuttonpopupdialog }
        -- to make sure e.g. the close button doesn't overlap the radius of the dialog border:
        table.insert(self.right_buttons_container, right_border_spacer)
    else
        table.insert(self.right_buttons_container, HorizontalSpan:new { width = Size.padding.large })
    end
end

function TitleBar:populateTabButtonsGroup()
    if self.tab_buttons then
        -- horizontal padding from the left:
        table.insert(self.left_buttons_container, HorizontalSpan:new { width = self.title_h_padding })
        for i = 1, #self.tab_buttons do
            table.insert(self.left_buttons_container, self.tab_buttons[i])
            table.insert(self.left_buttons_container, HorizontalSpan:new { width = self.title_h_padding })
        end

        self.left_buttons_height = self.left_buttons_container:getSize().h
    end
end

function TitleBar:injectBottomLine()
    if self.with_bottom_line then
        local line_widget = LineWidget:new {
            dimen = Geom:new { w = self.width, h = self.bottom_line_thickness },
            background = self.bottom_line_color
        }
        if self.bottom_line_h_padding then
            line_widget.dimen.w = line_widget.dimen.w - 2 * self.bottom_line_h_padding
            line_widget = HorizontalGroup:new {
                HorizontalSpan:new { width = self.bottom_line_h_padding },
                line_widget,
            }
        end

        local filler_and_bottom_line = VerticalGroup:new {
            VerticalSpan:new { width = self.desired_height },
            line_widget,
        }
        table.insert(self, filler_and_bottom_line)
        self.titlebar_height = filler_and_bottom_line:getSize().h
    end
end

function TitleBar:injectSubTitle()
    if self.info_text then
        local h_padding = self.info_text_h_padding or self.title_h_padding
        local v_padding = self.with_bottom_line and Size.padding.default or 0
        local filler_and_info_text = VerticalGroup:new {
            VerticalSpan:new { width = self.titlebar_height + v_padding },
            HorizontalGroup:new {
                HorizontalSpan:new { width = h_padding },
                TextBoxWidget:new {
                    text = self.info_text,
                    face = self.info_text_face,
                    width = self.width - 2 * h_padding,
                    lang = self.lang,
                }
            }
        }
        table.insert(self, filler_and_info_text)
        self.titlebar_height = filler_and_info_text:getSize().h + self.bottom_v_padding
    end
end

function TitleBar:injectSideContainers()

    --- inject left container, either with icon buttons or tab buttons:
    if self.top_buttons_left or self.tab_buttons then

        -- the height used for computation was computed in ((TitleBar#populateTopButtonsGroups)) or ((TitleBar#populateTabButtonsGroup)):
        local padding_for_vertical_centering = self:computeVerticalPadding(self.left_buttons_height, "apply_side_group_correction")
        table.insert(self, VerticalGroup:new {
            align = "left",
            overlap_align = "left",
            VerticalSpan:new { width = padding_for_vertical_centering },
            self.left_buttons_container,
        })
    end

    --- inject right container:
    if self.top_buttons_right then

        -- the height used for computation was computed in ((TitleBar#populateTopButtonsGroups)):
        local padding_for_vertical_centering = self:computeVerticalPadding(self.right_buttons_height, "apply_side_group_correction")
        table.insert(self, VerticalGroup:new {
            align = "right",
            overlap_align = "right",
            VerticalSpan:new { width = padding_for_vertical_centering },
            self.right_buttons_container,
        })
    end
end

function TitleBar:setDesiredHeight()
    self.desired_height = Registry.is_android_device and self.desired_heights.android or self.desired_heights.ubuntu
end

function TitleBar:computeVerticalPadding(height, apply_side_group_correction)
    if apply_side_group_correction or not self.has_top_buttons then
        return math.floor((self.desired_height - height) / 2) - 1
    end
    return math.floor((self.desired_height - height) / 2) / 2
end

function TitleBar:populateSubMenuButtons()
    if self.submenu_buttontable then
        table.insert(self.submenu_buttontable_container, self.submenu_buttontable)
    end
end

return TitleBar
