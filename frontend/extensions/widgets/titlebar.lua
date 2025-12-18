
--* PROCEDURE: generate top_buttons_left, title and top_buttons_right groups;
--* then determine width and height of each of these;
--* inject the top spacer / padding (depending on desired height) above the highest group
--* treat biggest width of top_buttons groups as margin for title
--* then determine font size and remaining max_width of title group
--* in one left container inject top_buttons_left, title group injected into a center container and top_buttons_right
--* depending on biggest height of the three groups inject top spacers to the other one or two groups
--* inject the bottom spacer / padding (depending on desired height) below the highest group

local require = require

local Button = require("extensions/widgets/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TextWidget = require("extensions/widgets/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DX = DX
local G_reader_settings = G_reader_settings
local math = math
local pairs = pairs
local table = table
local type = type

--- @class TitleBar
local TitleBar = OverlapGroup:extend{

    --* Internal: remember first sizes computed when title_shrink_font_to_fit=true,
    --* and keep using them after :setTitle() in case a smaller font size is needed,
    --* to keep the TitleBar geometry stable.
    _initial_titlebar_height = nil,
    _initial_re_init_needed = nil,

    width = nil, --* default to screen width
    fullscreen = false, --* larger font and small adjustments if fullscreen
    align = "center", --* or "left": title & subtitle alignment inside TitleBar ("right" nor supported)

    title = "",
    title_face = nil, --* if not provided, one of these will be used:
    title_face_fullscreen = Font:getFace("smalltfont"),
    title_face_not_fullscreen = Font:getFace("x_smalltfont"),
    --* by default: single line, truncated if overflow
    --* the default could be made dependant on self.fullscreen
    title_multilines = false, --* multilines if overflow
    title_shrink_font_to_fit = true, --* reduce font size so that single line text fits

    subtitle = nil,
    subtitle_face = Font:getFace("xx_smallinfofont"),
    subtitle_truncate_left = false, --* default with single line is to truncate right (set to true for a filepath)
    subtitle_fullwidth = false, --* true to allow subtitle to extend below the buttons
    subtitle_multilines = false, --* multilines if overflow

    info_text = nil, --* additional text displayed below bottom line
    info_text_face = Font:getFace("x_smallinfofont"),
    info_text_h_padding = nil, --* default to title_h_padding

    lang = nil, --* use this language (string) instead of the UI language

    title_h_padding = Size.padding.titlebarbutton, --* horizontal padding (this replaces button_padding on the inner/title side)
    title_h_padding_portrait = Size.padding.buttontable,
    title_subtitle_v_padding = Screen:scaleBySize(3),
    bottom_v_padding = nil, --* hardcoded default values, different whether with_bottom_line true or false

    button_padding = Screen:scaleBySize(11), --* fine to keep exit/cross icon diagonally aligned with screen corners

    with_bottom_line = false,
    bottom_line_h_padding = nil, --* default to 0: full width
    bottom_line_thickness = Size.line.thick,

    --* set any of these _callback to false to not handle the event
    --* and let it propagate; otherwise the event is discarded
    --* If provided, use right_icon="exit" and use this as right_icon_tap_callback
    close_callback = nil,
    close_hold_callback = nil,

    show_parent = nil,

    -- #((define desired height of title bar))
    desired_height = nil,
    desired_heights = {
        android = 70,
        bigme = 100,
        boox_go_10 = 90,
        --* this value will be used for FileManagerHistory under Android:
        android_higher_tabs = 100,
        ubuntu = 26,
    },
    is_popout_dialog = false,
    left_buttons_height = 0,
    title_height = 0,
    right_buttons_height = 0,
    has_small_close_button_padding = false,

    has_only_close_button = false,
    for_collection = false,

    --- for FileChooser, a subclass of Menu, its no_title prop will be set to true, because FileManager already provided a TitleBar:
    for_filemanager = false,

    --* tab buttons IN THE LEFT HALF of the titlebar itself:
    --* either tables of real Buttons, or tables with button configs:
    tab_buttons_left = nil,
    tab_buttons_right = nil,
    higher_tab_buttons = false,
    higher_tab_buttons_correction = 5,
    --* for referencing buttons, to be able to modify them:
    --? used by methods in ((TabFactory#setTabButtonAndContent)) ??:
    tabs = {},

    --* icon buttons IN the titlebar itself, at the left and the right (there for now only close button):
    --* if given as table, table items must have these props: icon, icon_size_ratio, rotation_angle, callback, hold_callback, allow_flash:
    top_buttons_left = nil,
    top_buttons_right = nil,
    title_width_was_adapted = false,

    --* submenu BELOW the title bar:
    submenu_buttontable = nil,

    --! will be set to true when top_buttons_left or top_buttons_right or tab_buttons_left are set:
    has_top_buttons = false,
    has_top_buttons_left = false,
    has_top_buttons_right = false,
    has_only_close_button_on_right_side = false,

    --* dynamically set in ((TitleBar#init)):
    is_landscape_screen = true,
}

function TitleBar:init()

    self.is_landscape_screen = KOR.screenhelpers:isLandscapeScreen()

    --- we don't want an in-your-face bottom line in case of fullscreen dialogs:
    if self.fullscreen and self.with_bottom_line then
        self.bottom_line_thickness = Size.line.small
    end

    self.has_top_buttons_left = self.top_buttons_left or self.tab_buttons_left
    self.has_top_buttons_right = self.top_buttons_right or self.tab_buttons_right
    self.has_top_buttons = self.has_top_buttons_left or self.has_top_buttons_right

    if self.has_top_buttons_left then
        self.align = "center"
    end

    self.left_buttons_container = HorizontalGroup:new{
        --! "left" and "right" not allowed for HorizontalGroups !
        align = "center",
    }
    self.right_buttons_container = HorizontalGroup:new{
        align = "center",
    }
    self.submenu_buttontable_container = HorizontalGroup:new{
        align = "center",
    }

    --* we either have icon buttons in the left half of the titlebar, or tab buttons; don't allow both, so replace top_buttons_left by tab_buttons_left:
    self:replaceTopButtonsLeftByTabButtonsLeft()
    self:injectTabButtonsLeft()

    --! this call must come before injectTabButtonsRight(), so self.has_top_buttons_right will be set to true if a close button has been added:
    if not self.tab_buttons_right then
        self:addCloseButton()
    end
    self:injectTabButtonsRight()

    if not self.width then
        self.width = Screen:getWidth()
    end
    self:setDesiredHeight()
    --* here also ((addCloseButtonRightSpacer)) is called:
    self:injectTopButtonsGroups()
    self:setTopButtonsSizeAndCallbacks()
    self:injectSubMenuButtons()

    self.main_container = HorizontalGroup:new{
        align = "center",
    }

    --! this call MUST come before injectSideContainers(), to nicely center the title:
    self:computeCorrectedTitleWidth()

    if self.has_top_buttons then
        self:injectSideContainers("left")
    end

    --- this is de facto the title text:
    self:injectTitle()

    --! to actually see all items, it is important that the left and right containers are inserted AFTER the center/title container:
    if self.has_top_buttons then
        self:injectSideContainers("right")
    end

    --[[if not self.has_top_buttons_left and self.has_top_buttons_right then
        local filler_width = self.right_buttons_container:getSize().w
        table.insert(self.left_buttons_container, HorizontalGroup:new{HorizontalSpan:new{ width = filler_width }})
    end]]

    if self._initial_re_init_needed then
        --* We have computed all the self._initial_ metrics needed.
        self._initial_re_init_needed = nil
        self:clear()
        self:init()
        return
    end

    table.insert(self, self.main_container)

    if not self.title_bar_height then
        self.title_bar_height = self.main_container:getSize().h
    end

    self:injectBottomLineAndOrSubmenuButtonTable()

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.titlebar_height, --* buttons can overflow this
    }

    --* Call our base class's init (especially since OverlapGroup has very peculiar self.dimen semantics...)
    OverlapGroup.init(self)
end

function TitleBar:paintTo(bb, x, y)
    --* We need to update self.dimen's x and y for any ges.pos:intersectWith(title_bar)
    --* to work. (This is done by FrameContainer, but not by most other widgets... It
    --* should probably be done in all of them, but not sure of side effects...)
    self.dimen.x = x
    self.dimen.y = y
    OverlapGroup.paintTo(self, bb, x, y)
end

function TitleBar:getHeight()
    return self.titlebar_height
end

function TitleBar:setTitle(title, no_refresh)
    if self.title_multilines or self.title_shrink_font_to_fit then
        --* We need to re-init the whole widget as its height or
        --* padding may change.
        local previous_height = self.titlebar_height
        --* Call WidgetContainer:clear() that will call :free() and
        --* will remove subwidgets from the OverlapGroup we are.
        self:clear()
        self.title = title
        self:init()
        if no_refresh then
            --* If caller is sure to handle refresh correctly, it can provides this
            return
        end
        if self.title_multilines and self.titlebar_height ~= previous_height then
            --* Title height have changed, and the upper widget may not have
            --* hooks to refresh a combination of its previous size and new
            --* size: be sure everything is repainted
            UIManager:setDirty("all", "ui")
        else
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
    else
        --* TextWidget with max-width: we can just update its text
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
    if self.subtitle_widget and not self.subtitle_multilines then --* no TextBoxWidget:setText() available
        self.subtitle_widget:setText(subtitle)
        if self.inner_subtitle_group then
            self.inner_subtitle_group:resetLayout()
        end
        self.title_group:resetLayout()
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setLeftIcon(icon)
    if self.top_buttons_left and self.left_icon then
        self.left_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setRightIcon(icon)
    if self.top_buttons_right and self.right_icon then
        self.right_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

--* ==================== SMARTSCRIPTS =====================

function TitleBar:setButtonIconType(config, button)
    local props = { "icon", "icon_text", "text_icon", "icon_icon" }
    local prop
    local count = #props
    for i = 1, count do
        prop = props[i]
        if button[prop] then
            config[prop] = button[prop]
            return
        end
    end
end

--* compare ((TitleBar#setTopButtonsSizeAndCallbacks))
--* compare final injection in ((TitleBar#injectTopButtonsGroups))
function TitleBar:getAdaptedTopButton(button)

    local config
    --* paddings for buttons are ignored in OverlapGroups:
    if button.text then
        config = {
            text = button.text,
            bordersize = 0,
            callback = button.callback,
            hold_callback = button.hold_callback,
            info_callback = button.info_callback,
            allow_flash = G_reader_settings:isNilOrFalse("night_mode"),
            show_parent = self.show_parent,
            for_titlebar = true,
        }
    else
        config = {
            icon_rotation_angle = button.rotation_angle or 0,
            icon_width = button.icon_size,
            icon_height = button.icon_size,
            --icon_size_ratio = button.icon_size_ratio or 0.6,
            bordersize = 0,
            callback = button.callback,
            hold_callback = button.hold_callback,
            info_callback = button.info_callback,
            allow_flash = not G_reader_settings:isTrue("night_mode"),
            show_parent = self.show_parent,
            for_titlebar = true,
        }
    end
    self:setButtonIconType(config, button)
    return Button:new(config)
end

--? Is this necessary?
function TitleBar:setButtonProps(button)
    local new_button = {}
    for name, prop in pairs(button) do
        new_button[name] = prop
    end
    --local icon_size_ratio = button.icon_size_ratio or 0.6
    --[[if not new_button.icon_size_ratio then
        new_button.icon_size_ratio = icon_size_ratio
        new_button.icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * icon_size_ratio)
    end]]
    new_button.callback = function()
        button.callback(self)
    end

    if button.hold_callback then
        new_button.hold_callback = function()
            button.hold_callback(self)
        end
    end
    if button.info_callback then
        new_button.info_callback = function()
            button.info_callback(self)
        end
    end

    button = new_button
end

--* compare ((TitleBar#getAdaptedTopButton))
--* compare final injection in ((TitleBar#injectTopButtonsGroups))
function TitleBar:setTopButtonsSizeAndCallbacks()
    self.has_only_close_button = not self.no_close_button and not self.top_buttons_left and self.top_buttons_right and not self.tab_buttons_right and true or false
    local bcount
    if self.top_buttons_left then
        bcount = #self.top_buttons_left
        for b = 1, bcount do
            if self.top_buttons_left[b].callback then

                --* buttons will be instantiated in ((TitleBar#injectTopButtonsGroups))

                self:setButtonProps(self.top_buttons_left[b])
            end
        end
    end
    if self.top_buttons_right then
        bcount = #self.top_buttons_right
        for b = 1, bcount do
            if self.top_buttons_right[b].callback then

                --* buttons will be instantiated in ((TitleBar#injectTopButtonsGroups))

                self:setButtonProps(self.top_buttons_right[b])
            end
        end
    end
end

function TitleBar:injectTitle()

    local title_max_width = self.corrected_title_width or self.width - 2 * self.title_h_padding - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width

    local subtitle_max_width = self.width - 2 * self.title_h_padding

    local width = self.width

    --* title, subtitle, and their alignment:
    local title_face = self.title_face
    if not title_face then
        title_face = self.fullscreen and self.title_face_fullscreen or self.title_face_not_fullscreen
    end
    --* for align == "left" we need width correction, to make sure the titlebar doesnot overlap the right title bar border:
    local adapted_width = width
    if self.title_multilines and self.align ~= "left" then
        self.title_widget = TextBoxWidget:new{
            text = self.title,
            alignment = self.align,
            --* for Xray edit dialog we need self.corrected_title_width to get title centered; see ((TitleBar#computeCorrectedTitleWidth)) > ((corrected title width for Xray edit dialog)):
            width = self.corrected_title_width or width,
            face = title_face,
            lang = self.lang,
            bordersize = 0,
        }
    else
        while true do
            self.title_widget = TextWidget:new{
                text = self.title,
                face = title_face,
                padding = 0,
                lang = self.lang,
                --* truncate if not self.title_shrink_font_to_fit:
                max_width = not self.title_shrink_font_to_fit and title_max_width,
            }
            adapted_width = self.title_widget:getWidth()
            if not self.title_shrink_font_to_fit then
                break --* truncation allowed, no loop needed
            end
            if adapted_width < title_max_width then
                break --* text with normal font fits, no loop needed
            end
            --* Text doesn't fit
            if not self._initial_titlebar_height then

                self.title_width_was_adapted = true

                --* We're with title_shrink_font_to_fit and in the first :init():
                --* we don't want to go on measuring with this too long text.
                --* We want metrics proper for when text fits, so if later :setTitle()
                --* is called with a text that fits, this text will look allright.
                --* Longer title with a smaller font size should be laid out on the
                --* baseline of a fitted text.
                --* So, go on computing sizes with an empty title. When all is
                --* gathered, we'll re :init() ourselves with the original title,
                --* using the metrics we're computing now (self._initial*).
                self._initial_re_init_needed = true
                self.title_widget:free(true)
                self.title_widget = TextWidget:new{
                    text = "",
                    face = title_face,
                    padding = 0,
                }
                break
            end
            --* otherwise, loop and do the same with a smaller font size
            self.title_widget:free(true)
            title_face = Font:getFace(title_face.orig_font, title_face.orig_size - 1)
        end --* end of loop
    end

    self.subtitle_widget = nil
    if self.subtitle then
        if self.subtitle_multilines then
            self.subtitle_widget = TextBoxWidget:new{
                text = self.subtitle,
                alignment = self.align,
                width = subtitle_max_width,
                face = self.subtitle_face,
                lang = self.lang,
            }
        else
            self.subtitle_widget = TextWidget:new{
                text = self.subtitle,
                face = self.subtitle_face,
                max_width = subtitle_max_width,
                truncate_left = self.subtitle_truncate_left,
                padding = 0,
                lang = self.lang,
            }
        end
    end

    --* self.title_group can optionally be expanded vertically with self.subtitle_widget or self.submenu_buttontable:
    self.title_group = VerticalGroup:new{
        align = self.align,
        bordersize = 0,
    }
    --* this group will receive self.title_group:
    self.title_group_vertically_centered = VerticalGroup:new{
        align = self.align,
        bordersize = 0,
    }
    self.subtitle_group = VerticalGroup:new{
        align = self.align,
        bordersize = 0,
    }

    if self.align == "left" then
        --* we need to :resetLayout() both VerticalGroup and HorizontalGroup in :setTitle()

        local title_elems = {
            HorizontalSpan:new{ width = self.top_left_buttons_reserved_width + self.title_h_padding },
        }
        table.insert(title_elems, self.title_widget)
        self.inner_title_group = HorizontalGroup:new(title_elems)
        table.insert(self.title_group, self.inner_title_group)
    else
        table.insert(self.title_group, self.title_widget)
    end
    if self.subtitle_widget then
        table.insert(self.subtitle_group, VerticalSpan:new{ width = self.title_subtitle_v_padding })
        if self.align == "left" then
            local span_width = self.title_h_padding
            if not self.subtitle_fullwidth then
                span_width = span_width + self.top_left_buttons_reserved_width
            end
            self.inner_subtitle_group = HorizontalGroup:new{
                HorizontalSpan:new{ width = span_width },
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

    --- title:
    table.insert(self.title_group_vertically_centered, self.title_group)

    self.center_container = VerticalGroup:new{
        align = self.align,
        overlap_align = self.align,
        self.title_group_vertically_centered,
    }
    if self.align == "left" and self.subtitle_widget then
        table.insert(self.center_container, self.subtitle_group)
    end

    if self.align == "center" and self.subtitle_widget then
        table.insert(self.center_container, self.subtitle_widget)
        --- we need this extra CenterContainer as wrapper to make sure that title and subtitle are nicely centered as one module:
        self.center_container = CenterContainer:new{
            dimen = Geom:new{ w = math.max(self.title_width, self.subtitle_width), h = self.title_height },
            align = self.align,
            overlap_align = self.align,
            self.center_container,
        }
    end

    --* all elements are injected in groups, now compute their heights and widths and inject spacers into
    self:addVerticalSpacers()

    --* This TitleBar widget is an OverlapGroup: all sub elements overlap,
    --* and can overflow or underflow. Its height for its containers is
    --* the one we set as self.dimen.h.

    if self.title_shrink_font_to_fit then
        --* Use, or store, the first title_group height we have computed,
        --* so the TitleBar geometry and the bottom line position stay stable
        --* (face height may have changed, even after we kept the baseline
        --* stable, as we did above).
        if self._initial_titlebar_height then
            self.titlebar_height = self._initial_titlebar_height
        else
            self._initial_titlebar_height = self.titlebar_height
        end
    end

    --! at least needed for Leeslijsten!:
    self.titlebar_height = self.center_container:getSize().h

    table.insert(self.main_container, self.center_container)
end

function TitleBar:injectTabButtonsLeft()
    --? used by methods in ((TabFactory#setTabButtonAndContent)) > ((tabs in titlebar)) ??:
    --* button props were set in ((Button#addTitleBarTabButtonProps)):
    self.tabs = {}
    if self.tab_buttons_left then
        local separator = self.is_landscape_screen and HorizontalSpan:new{ width = self.title_h_padding } or HorizontalSpan:new{ width = self.title_h_padding_portrait }
        --* horizontal padding from the left:
        table.insert(self.left_buttons_container, HorizontalSpan:new{ width = self.title_h_padding })
        local button
        local count = #self.tab_buttons_left
        for i = 1, count do
            button = self:instantiateButton(self.tab_buttons_left[i])
            --? used by methods in ((TabFactory#setTabButtonAndContent)) > ((tabs in titlebar)) ??:
            table.insert(self.tabs, button)
            table.insert(self.left_buttons_container, separator)
            table.insert(self.left_buttons_container, button)
        end

        self.left_buttons_height = self.left_buttons_container:getSize().h

        self.left_buttons_container_populated = true
    end
end

function TitleBar:injectTabButtonsRight()

    --* button props were set in ((Button#addTitleBarTabButtonProps)):
    if self.tab_buttons_right then
        local button
        local separator = self.is_landscape_screen and HorizontalSpan:new{ width = self.title_h_padding } or HorizontalSpan:new{ width = self.title_h_padding_portrait }
        local count = #self.tab_buttons_right
        for i = count, 1, -1 do
            button = self:instantiateButton(self.tab_buttons_right[i])
            --? used by methods in ((TabFactory#setTabButtonAndContent)) ??:
            table.insert(self.tabs, button)
            table.insert(self.right_buttons_container, 1, button)
            table.insert(self.right_buttons_container, 2, separator)
        end

        self.right_buttons_container_populated = true

    --* add empty spacer:
    elseif not self.top_buttons_right then
        table.insert(self.right_buttons_container, HorizontalSpan:new{ width = self.top_right_buttons_reserved_width })

        self.right_buttons_container_populated = true
    end
end

--* see also ((addCloseButtonRightSpacer)):
function TitleBar:addCloseButton()
    if not self.no_close_button and self.close_callback and not self.tab_buttons_right then
        self.has_top_buttons_right = true

        local icon_height = KOR.buttonprops:getFixedIconHeight("for_close_button")

        --* in this case we need a smaller spaer above the close button in ((TitleBar#addVerticalSpacers)) > ((lower spacer above close button)), because for some reason the button would not be vertically centered otherwise:
        self.has_only_close_button_on_right_side = true
        self.has_top_buttons = true

        self.top_buttons_right = {
            Button:new({
                icon = "close",
                icon_height = icon_height,
                icon_width = icon_height,
                --[[text = "x",
                text_font_size = 14,
                text_font_bold = false,]]
                callback = function()
                    self.close_callback()
                end,
                hold_callback = function()
                    if self.close_hold_callback then
                        self.close_hold_callback()
                    end
                end
            }),
        }
    end
end

--* compare ((TitleBar#setTopButtonsSizeAndCallbacks))
--* compare ((TitleBar#getAdaptedTopButton))
--- the groups generated here are only horizontally oriented
function TitleBar:injectTopButtonsGroups()
    --* under Android we need more horizontal spacing:
    local spacer_width = self:getHorizontalSpacerWidth()
    local count, button
    local horizontal_spacer = HorizontalSpan:new{ width = spacer_width }
    if self.top_buttons_left and not self.left_buttons_container_populated then
        count = #self.top_buttons_left
        for nr = 1, count do
            button = self:instantiateButton(self.top_buttons_left[nr])
            if nr == 1 then
                table.insert(self.left_buttons_container, horizontal_spacer)
            end
            button = self:getAdaptedTopButton(button)
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
    if self.top_buttons_right and not self.right_buttons_container_populated then
        count = #self.top_buttons_right
        for nr = 1, count do
            button = self:instantiateButton(self.top_buttons_right[nr])
            if nr < #self.top_buttons_right and not self.has_only_close_button then
                table.insert(self.right_buttons_container, horizontal_spacer)
            end
            button = self:getAdaptedTopButton(button)
            if nr == 1 then
                self.right_button = button
            end

            table.insert(self.right_buttons_container, button)
        end
        self:addCloseButtonRightSpacer()
        self.right_buttons_height = self.right_buttons_container:getSize().h
    end
end

--* see ((addCloseButton)):
--* to add right margin for close button:
function TitleBar:addCloseButtonRightSpacer()
    local right_border_spacer
    if self.for_filemanager or self.has_small_close_button_padding then
        right_border_spacer = HorizontalSpan:new{ width = Size.padding.titlebar }

    elseif not self.fullscreen and self.is_popout_dialog then
        --* to make sure e.g. the close button doesn't overlap the radius of the dialog border:
        right_border_spacer = HorizontalSpan:new{ width = Size.padding.closebuttonpopupdialog }

    elseif not self.fullscreen then
        right_border_spacer = HorizontalSpan:new{ width = Size.padding.buttontable }

    else
        right_border_spacer = HorizontalSpan:new{ width = self:getHorizontalSpacerWidth("for_close_button") }
    end

    table.insert(self.right_buttons_container, right_border_spacer)
end

function TitleBar:injectBottomLineAndOrSubmenuButtonTable()
    if self.with_bottom_line or self.submenu_buttontable then
        local line_widget = LineWidget:new{
            dimen = Geom:new{ w = self.width, h = self.bottom_line_thickness },
            background = self.submenu_buttontable and KOR.colors.title_bar_with_submenu_bottom_line or KOR.colors.title_bar_bottom_line
        }
        if self.bottom_line_h_padding then
            line_widget.dimen.w = line_widget.dimen.w - 2 * self.bottom_line_h_padding
            line_widget = HorizontalGroup:new{
                HorizontalSpan:new{ width = self.bottom_line_h_padding },
                line_widget,
            }
        end

        local filler_and_bottom_line = VerticalGroup:new{
            VerticalSpan:new{ width = self.desired_height },
            self.submenu_buttontable_container,
            line_widget,
        }
        table.insert(self, filler_and_bottom_line)
        self.titlebar_height = filler_and_bottom_line:getSize().h
    end

    --* ((InputDialog)): description line above a field :
    self:injectSubTitle()
end

--* defacto used for showing description line above a field for ((InputDialog)):
function TitleBar:injectSubTitle()
    if self.info_text then
        local h_padding = self.info_text_h_padding or self.title_h_padding
        local v_padding = self.with_bottom_line and Size.padding.default or 0
        local filler_and_info_text = VerticalGroup:new{
            VerticalSpan:new{ width = self.titlebar_height + v_padding },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = h_padding },
                TextBoxWidget:new{
                    text = self.info_text,
                    face = self.info_text_face,
                    width = self.width - 2 * h_padding,
                    lang = self.lang,
                }
            }
        }
        table.insert(self, filler_and_info_text)
        if not self.bottom_v_padding then
            self.bottom_v_padding = 0
        end
        self.titlebar_height = filler_and_info_text:getSize().h
    end
end

function TitleBar:injectSideContainers(side)

    --- inject left container, either with icon buttons or tab buttons:
    if side == "left" then

        if self.has_top_buttons_left then
            --* the height used for computation was computed in ((TitleBar#injectTopButtonsGroups)) or ((TitleBar#injectTabButtonsLeft)):
            table.insert(self.main_container, VerticalGroup:new{
                align = "left",
                overlap_align = "left",
                self.left_buttons_container,
            })
            return
        end
        --* in case of top_buttons_right but no top_buttons_left and centered title, add empty filler for left buttons group:
        if self.has_top_buttons_right and self.align == "center" then
            table.insert(self.main_container, VerticalGroup:new{
                align = "left",
                overlap_align = "left",
                HorizontalSpan:new{ width = self.top_right_buttons_reserved_width },
            })
        end
        return
    end

    --- inject right container:
    if side == "right" then
        if self.has_top_buttons_right then
            --* the height used for computation was computed in ((TitleBar#injectTopButtonsGroups)):
            local dims = self.right_buttons_container:getSize()
            table.insert(self.main_container, RightContainer:new{
                dimen = Geom:new{ w = self.top_right_buttons_reserved_width, h = dims.h },
                self.right_buttons_container,
            })
            return
        end
        --* in case of top_buttons_left but no top_buttons_right and centered title, add empty filler for right buttons group:
        if self.has_top_buttons_left and self.align == "center" then
            table.insert(self.main_container, VerticalGroup:new{
                align = "left",
                overlap_align = "left",
                HorizontalSpan:new{ width = self.top_left_buttons_reserved_width },
            })
        end
    end
end

function TitleBar:setDesiredHeight()

    if DX.s.is_tablet_device then
        self.desired_height = self.desired_heights.boox_go_10
    elseif DX.s.is_mobile_device then
        self.desired_height = self.desired_heights.bigme
    else
        self.desired_height = DX.s.is_android and self.desired_heights.android or self.desired_heights.ubuntu
    end

    if DX.s.is_android and self.higher_tab_buttons then
        self.desired_height = self.desired_heights.android_higher_tabs
    end

    if self.for_filemanager then
        self.desired_height = self.desired_height + Screen:scaleBySize(27)
    end
end

function TitleBar:getHorizontalSpacerWidth(for_close_button)
    if DX.s.is_mobile_device then
        return Size.padding.fullscreen
    end
    if for_close_button and self.fullscreen then
        return Size.padding.buttonvertical
    end

    return DX.s.is_android and Size.padding.fullscreen or Size.padding.large --* or Size.padding.titlebarbutton instead of large
end

function TitleBar:injectSubMenuButtons()
    if self.submenu_buttontable then
        table.insert(self.submenu_buttontable_container, self.submenu_buttontable)
    end
end

function TitleBar:instantiateButton(button)
    return type(button) == "table" and Button:new(button) or button
end

function TitleBar:refreshTabButtons(tab_buttons_left, tab_buttons_right)
    self.tab_buttons_left = tab_buttons_left
    self.tab_buttons_right = tab_buttons_right

    --* call WidgetContainer:clear() that will call :free() and
    --* will remove subwidgets from the OverlapGroup we are.
    self:clear()
    self:init()
end

function TitleBar:replaceTopButtonsLeftByTabButtonsLeft()
    if self.tab_buttons_left and self.top_buttons_left then
        local button
        local count = #self.top_buttons_left
        for i = 1, count do
            button = self.top_buttons_left[i]
            button.bordersize = 0
            table.insert(self.tab_buttons_left, 1, button)
        end
        self.top_buttons_left = nil
    end
end

function TitleBar:addVerticalSpacers()
    local title_dims = self.center_container:getSize()
    local title_height = title_dims.h
    --* only highest_elem will get a bottom spacer:
    local highest_elem = "title"
    local max_height = title_height

    local top_left_buttons_height = 0
    if self.has_top_buttons_left then
        top_left_buttons_height = self.left_buttons_container:getSize().h
        if top_left_buttons_height > max_height then
            max_height = top_left_buttons_height
            highest_elem = "left_buttons"
        end
    end
    local top_right_buttons_height = 0
    if self.has_top_buttons_right then
        top_right_buttons_height = self.right_buttons_container:getSize().h
        if top_right_buttons_height > max_height then
            max_height = top_right_buttons_height
            highest_elem = "right_buttons"
        end
    end

    if max_height >= self.desired_height then
        self.desired_height = max_height + Screen:scaleBySize(10)
    end

    local difference = self.desired_height - title_height
    local spacer_height = math.floor(difference / 2)
    local config
    if highest_elem == "title" then
        config = {
            align = "left",
            overlap_align = "left",
            --* by minus correction make the title make *visually* give a more centered impression:
            VerticalSpan:new{ width = spacer_height - Screen:scaleBySize(1) },
            CenterContainer:new{
                --* if not topbuttons defined, then self.top_left/right_buttons_reserved_width will be zero:
                dimen = Geom:new{ w = self.width - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width, h = title_height },
                self.center_container,
            },
        }
        if not self.title_width_was_adapted then
            table.insert(config, VerticalSpan:new{ width = spacer_height })
        end
        self.center_container = VerticalGroup:new(config)

    --* title not highest elem:
    else
        --* if title was shrunk, add no spacer above the title container:
        config = self.title_width_was_adapted and {
            align = "left",
            overlap_align = "left",
            CenterContainer:new{
                --* if not topbuttons defined, then self.top_left/right_buttons_reserved_width will be zero:
                dimen = Geom:new{ w = self.width - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width, h = title_height },
                self.center_container,
            },
        }
        or
        {
            align = "left",
            overlap_align = "left",
            VerticalSpan:new{ width = spacer_height },
            CenterContainer:new{
                dimen = Geom:new{ w = self.width - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width, h = title_height },
                self.center_container,
            },
        }
        self.center_container = VerticalGroup:new(config)
    end

    if self.has_top_buttons_left then
        difference = self.desired_height - top_left_buttons_height
        spacer_height = math.floor(difference / 2)
        self.left_buttons_container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            VerticalSpan:new{ width = spacer_height },
            self.left_buttons_container,
        }
        if highest_elem == "left_buttons" and not self.title_width_was_adapted then
            table.insert(self.left_buttons_container, VerticalSpan:new{ width = spacer_height })
        end
    end

    if KOR.registry:get("history_active") then
        return
    end

    if self.has_top_buttons_right then
        difference = self.desired_height - top_right_buttons_height
        spacer_height = math.floor(difference / 2)

        -- #((lower spacer above close button))
        --* in this case we need a smaller spacer above the close button, because for some reason the button would not be vertically centered otherwise:
        if self.has_only_close_button_on_right_side then
            local correction
            if DX.s.is_ubuntu or DX.s.is_tablet_device then
                correction = 5
                spacer_height = spacer_height - Screen:scaleBySize(correction)
            elseif DX.s.is_mobile_device then
                correction = 24
                spacer_height = spacer_height - Screen:scaleBySize(correction)
            end
        end
        self.right_buttons_container = highest_elem == "right_buttons" and not self.title_width_was_adapted and VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            VerticalSpan:new{ width = spacer_height },
            self.right_buttons_container,
            VerticalSpan:new{ width = spacer_height }
        }
        or
        VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            self.right_buttons_container,
        }
        end

    --* when the title was shrunk, make the title filler less high in ((TitleBar#injectBottomLineAndOrSubmenuButtonTable)):
    if self.title_width_was_adapted then
        self.desired_height = math.max(self.center_container:getSize().h, self.left_buttons_container:getSize().h, self.right_buttons_container:getSize().h) - 20
    end
end

function TitleBar:computeCorrectedTitleWidth()
    self.top_left_buttons_reserved_width = 0
    self.top_right_buttons_reserved_width = 0
    if self.has_top_buttons_left then
        self.top_left_buttons_reserved_width = self.left_buttons_container:getSize().w
    end
    if self.has_top_buttons_right then
        self.top_right_buttons_reserved_width = self.right_buttons_container:getSize().w
    end
    local screen_width = Screen:getWidth()
    if self.align == "center" and (self.has_top_buttons_left or self.has_top_buttons_right) then
        --* Keep title and subtitle text centered even if single button
        self.top_left_buttons_reserved_width = math.max(self.top_left_buttons_reserved_width, self.top_right_buttons_reserved_width)
        self.top_right_buttons_reserved_width = self.top_left_buttons_reserved_width

        -- #((corrected title width for Xray edit dialog))
        self.corrected_title_width = math.min(self.width, screen_width - 2 * self.top_left_buttons_reserved_width)
    end
end

return TitleBar
