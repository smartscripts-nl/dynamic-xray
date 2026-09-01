
--* PROCEDURE: generate top_buttons_left, title and top_buttons_right groups;
--* then determine width and height of each of these;
--* inject the top spacer / padding above the highest group
--* treat biggest width of top_buttons groups as margin for title
--* then determine font size and remaining max_width of title group
--* in one left container inject top_buttons_left, title group injected into a center container and top_buttons_right
--* depending on biggest height of the three groups inject top spacers to the other one or two groups
--* inject the bottom spacer / padding below the highest group

----------------------- SPACERS --------------------

------------------------ LEFT ----------------------

--* ((TitleBar#generateTopButtonsGroups)) > ((TitleBar#injectLeftButtonGroupButton)): inject self.top_button_group_spacer as first item and between buttons;

------------------------ RIGHT ---------------------

--* ((TitleBar#generateTopButtonsGroups)) > ((TitleBar#injectRightButtonGroupButton)): inject self.top_button_group_spacer as last item and between buttons; empty spacer only injected when no top_button_right and no close button given in ((TitleBar#injectTabButtonsRight))
--* if tab_buttons_right set, then injectTopButtonsGroups not called, but buttons instead handled in ((TitleBar#injectTabButtonsRight))

local require = require

local Button = require("xrayviews/widgets/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("modules/font")
local FrameContainer = require("xrayviews/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("xrayviews/widgets/iconwidget")
local IconWidgetInverted = require("xrayviews/widgets/iconwidgetinverted")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/rightcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("modules/size")
local TextBoxWidget = require("xrayviews/widgets/textboxwidget")
local TextWidget = require("xrayviews/widgets/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen

local G_reader_settings = G_reader_settings
local has_no_items = has_no_items
local math_ceil = math_ceil
local math_floor = math_floor
local math_max = math_max
local math_min = math_min
local pairs = pairs
local T = T
local table_insert = table_insert
local type = type

local count
local DGENERIC_ICON_SIZE = math_floor(G_defaults:readSetting("DGENERIC_ICON_SIZE") * 0.6)

--- @class TitleBar
local TitleBar = OverlapGroup:extend{

    --* Internal: remember first sizes computed when title_shrink_font_to_fit=true,
    --* and keep using them after :setTitle() in case a smaller font size is needed,
    --* to keep the TitleBar geometry stable.
    _initial_titlebar_height = nil,
    _initial_re_init_needed = false,

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

    with_bottom_line = true,
    bottom_line_h_padding = nil, --* default to 0: full width
    bottom_line_thickness = Size.line.thin,

    --* set any of these _callback to false to not handle the event
    --* and let it propagate; otherwise the event is discarded
    --* If provided, use right_icon="exit" and use this as right_icon_tap_callback
    close_callback = nil,
    close_hold_callback = nil,

    show_parent = nil,

    close_button_inserted = false,
    -- #((define desired height of title bar))
    computed_titlebar_height = 0,
    dialog_queue_id = nil,
    is_popout_dialog = false,
    for_collection = false,

    title_icon = nil,
    title_icon_widget = nil,

    --- for FileChooser, a subclass of Menu, its no_title prop will be set to true, because FileManager already provided a TitleBar:
    for_filemanager = false,
    --* if close button is the only button in both groups:
    has_only_close_button = false,
    --* if there are button at the left side, but only a close button on the right side:
    has_only_close_button_on_right_side = false,
    has_small_close_button_padding = false,
    --! will be set to true when top_buttons_left or top_buttons_right or tab_buttons_left are set:
    has_top_buttons = false,
    has_top_buttons_left = false,
    has_top_buttons_right = false,
    higher_tab_buttons = false,
    higher_tab_buttons_correction = 5,
    inverted_background_color = KOR.colors.background_inverted,
    --* dynamically set in ((TitleBar#setWidgetProps)):
    is_landscape_screen = true,
    no_close_button_padding = false,
    parent_has_tabs = false,
    --* submenu BELOW the title bar:
    submenu_buttontable = nil,
    --* tab buttons IN THE LEFT HALF of the titlebar itself:
    --* either tables of real Buttons, or tables with button configs:
    tab_buttons_left = nil,
    tab_buttons_left_inserted = false,
    tab_buttons_left_top_padding = nil,
    tab_buttons_right = nil,
    tab_buttons_right_inserted = false,
    --* for referencing buttons, to be able to modify them:
    --? used by methods in ((TabFactory#setTabButtonAndContent)) ??:
    tabs = {},
    titlebar_inverted = false,
    title_height = 0,
    title_icon = nil,
    title_icon_widget = nil,
    title_width_was_adapted = false,
    top_button_group_spacer = nil,
    --* icon buttons IN the titlebar itself, at the left and the right (there for now only close button):
    --* if given as table, table items must have these props: icon, icon_size_ratio, rotation_angle, callback, hold_callback, allow_flash:
    top_buttons_left = nil,
    top_buttons_right = nil,
    top_left_buttons_height = 0,
    top_left_buttons_reserved_width = 0,
    top_right_buttons_height = 0,
    top_right_buttons_reserved_width = 0,
    use_minimal_spacers = false,
}

--- @private
function TitleBar:initData()
    self:setWidgetProps()
    --* we either have icon buttons in the left half of the titlebar, or tab buttons; don't allow both, so replace top_buttons_left by tab_buttons_left:
    self:ifTabButtonsLeftThenAddTopButtonsLeft()
    self:addDialogQueueButton()
    self:addCloseButton()
    self:setTopButtonsSizeAndCallbacks()
end

function TitleBar:init(skip_data)

    if not skip_data then
        self:initData()
    end

    self:initContainers()
    self:injectTabButtonsLeft()
    self:injectTabButtonsRight()

    self:generateTopButtonsGroups()
    self:injectSubMenuButtons()

    --! this call MUST come before ((injectSideContainersLeftVerticallyPadded)), to nicely center the title:
    if self.has_only_close_button then
        self:computeCorrectedTitleWidthForOnlyCloseButton()
    else
        self:computeCorrectedTitleWidth()
    end
    self:injectSideContainersLeftVerticallyPadded()
    --- this is de facto the title text:
    self:injectTitleIntoMainContainer()

    if self:wasReInitialized() then
        return
    end

    --! to actually see all items, it is important that the left and right containers are inserted AFTER the center/title container:
    self:injectSideContainersRightVerticallyPadded()

    self:injectMainContainer()
    self:injectFillerAndBottomLine()
    --* ((InputDialog)): description line above a field :
    self:injectSubTitle()
    self:setDims()

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

--- @private
function TitleBar:setWidgetProps()
    self.is_landscape_screen = KOR.screenhelpers:isLandscapeScreen()

    --* for tabbed interfaces initiated and handled after activating new tabs via ((Dialogs#htmlBoxTabbed)) or ((Dialogs#textBoxTabbed)), dialog_queue_id might be set there already, when defined in the caller; see e.g. ((XrayDialogs#viewItem)) and ((XrayDialogs#viewTappedWordItem)):
    if not self.dialog_queue_id then
        self.dialog_queue_id = KOR.dialogsqueue:getLastId()
    end

    if self.submenu_buttontable then
        self.bottom_line_thickness = Size.line.thick
    end

    --! in dialogs with title bars for which no top_buttons_left were defined, define that now, so we can inject the DialogsQueue back-button:
    if not self.top_buttons_left and KOR.dialogsqueue:getQueueCount() > 1 then
        self.top_buttons_left = {}
    end

    self.has_top_buttons_left = self.top_buttons_left or self.tab_buttons_left
    self.has_top_buttons_right = self.top_buttons_right or self.tab_buttons_right

    self.has_top_buttons = self.has_top_buttons_left or self.has_top_buttons_right

    if self.has_top_buttons_left and not self.has_only_close_button then
        self.align = "center"
    end
    if not self.width then
        self.width = Screen:getWidth()
    end
end

--- @private
function TitleBar:initContainers()
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

    self.main_container = HorizontalGroup:new{
        align = "center",
    }
end

--- @private
function TitleBar:wasReInitialized()
    if not self._initial_re_init_needed then
        return false
    end

    --* We have computed all the self._initial_ metrics needed.
    self._initial_re_init_needed = false
    self:clear()
    self:init("skip_data")
    return true
end

--- @private
function TitleBar:injectMainContainer()
    if self.titlebar_inverted then
        self.main_container = FrameContainer:new {
            bordersize = 0,
            background = self.inverted_background_color,
            focus_border_color = KOR.colors.white,
            self.main_container,
            --! this prop is crucial to prevent unwanted shifts in the positions of the title and the top buttons:
            padding = 0,
        }
    end
    table_insert(self, self.main_container)

    if not self.title_bar_height then
        self.title_bar_height = self.main_container:getSize().h
    end
end

--- @private
function TitleBar:setDims()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.titlebar_height, --* buttons can overflow this
    }
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
        self:init("skip_data")
        if no_refresh then
            --* If caller is sure to handle refresh correctly, it can provide this
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

--- @private
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

--- @private
function TitleBar:setButtonIconType(config, button)
    local props = { "icon", "icon_text", "text_icon", "icon_icon" }
    local prop
    count = #props
    for i = 1, count do
        prop = props[i]
        if button[prop] then
            config[prop] = button[prop]
            return
        end
    end
end

--* compare ((TitleBar#setTopButtonsSizeAndCallbacks))
--* compare final injection in ((TitleBar#generateTopButtonsGroups))
--- @private
function TitleBar:getAdaptedTopButton(button)

    local config
    --* paddings for buttons are ignored in OverlapGroups:
    if button.text then
        config = {
            text = button.text,
            bordersize = 0,
            font_bold = button.font_bold,
            text_font_bold = button.text_font_bold,
            callback = button.callback,
            hold_callback = button.hold_callback,
            info_callback = button.info_callback,
            generate_inverted_icon = self.titlebar_inverted,
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
            icon_size_ratio = button.icon_size_ratio,
            icon_size_ratio_forced = button.icon_size_ratio_forced,
            callback = button.callback,
            hold_callback = button.hold_callback,
            info_callback = button.info_callback,
            generate_inverted_icon = self.titlebar_inverted,
            allow_flash = G_reader_settings:isNilOrFalse("night_mode"),
            show_parent = self.show_parent,
            for_titlebar = true,
        }
    end
    self:setButtonIconType(config, button)
    return Button:new(config)
end

--? Is this necessary?
--- @private
function TitleBar:setButtonProps(button)
    local new_button = {}
    for name, prop in pairs(button) do
        new_button[name] = prop
    end
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
--* compare final injection in ((TitleBar#generateTopButtonsGroups))
--- @private
function TitleBar:setTopButtonsSizeAndCallbacks()
    self.has_only_close_button = not self.no_close_button and not self.top_buttons_left and self.top_buttons_right and not self.tab_buttons_right
    local bcount
    if self.top_buttons_left then
        bcount = #self.top_buttons_left
        for b = 1, bcount do
            if self.top_buttons_left[b].callback then
                --* buttons will be instantiated in ((TitleBar#generateTopButtonsGroups))
                self:setButtonProps(self.top_buttons_left[b])
            end
        end
    end
    if not self.top_buttons_right then
        return
    end

    bcount = #self.top_buttons_right
    for b = 1, bcount do
        if self.top_buttons_right[b].callback then
            --* buttons will be instantiated in ((TitleBar#generateTopButtonsGroups))
            self:setButtonProps(self.top_buttons_right[b])
        end
    end
end

--- @private
function TitleBar:injectTitleIntoMainContainer()

    local title_max_width = self.corrected_title_width or self.width - 2 * self.title_h_padding - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width
    self.corrected_title_width = title_max_width

    local subtitle_max_width = self.width - 2 * self.title_h_padding

    local width = self.width

    --* title, subtitle, and their alignment:
    local title_face = self.title_face
    if not title_face then
        title_face = self.fullscreen and self.title_face_fullscreen or self.title_face_not_fullscreen
    end
    --* for align == "left" we need width correction, to make sure the titlebar doesnot overlap the right title bar border:
    local adapted_width = width
    local title_icon_width = 0
    if self.title_icon then
        self.title_icon_widget = self.title_icon:match("inverted") and
        IconWidgetInverted:new{
            icon = self.title_icon,
            icon_rotation_angle = 0,
            icon_height = DGENERIC_ICON_SIZE,
            icon_width = DGENERIC_ICON_SIZE,
        }
        or
        IconWidget:new{
            icon = self.title_icon,
            icon_rotation_angle = 0,
            icon_height = DGENERIC_ICON_SIZE,
            icon_width = DGENERIC_ICON_SIZE,
        }
        title_icon_width = DGENERIC_ICON_SIZE
    end
    if self.title_multilines then
        width = self.corrected_title_width and self.corrected_title_width - title_icon_width or width - title_icon_width
        if self.align == "left" then
            width = width + 2 * Size.padding.large + title_icon_width + 6
        end
        self.title_widget = TextBoxWidget:new{
            text = self.title,
            bgcolor = self.titlebar_inverted and self.inverted_background_color or KOR.colors.white,
            fgcolor = self.titlebar_inverted and KOR.colors.white or KOR.colors.black,
            alignment = self.align,
            width = width,
            face = title_face,
            lang = self.lang,
            bold = true,
            bordersize = 0,
        }
    else
        while true do
            self.title_widget = TextWidget:new{
                text = self.title,
                face = title_face,
                bgcolor = self.titlebar_inverted and self.inverted_background_color or KOR.colors.white,
                fgcolor = self.titlebar_inverted and KOR.colors.white or KOR.colors.black,
                padding = 0,
                alignment = self.align,
                lang = self.lang,
                --* truncate if not self.title_shrink_font_to_fit:
                max_width = not self.title_shrink_font_to_fit and title_max_width - title_icon_width,
            }
            adapted_width = self.title_widget:getWidth()
            if not self.title_shrink_font_to_fit then
                break --* truncation allowed, no loop needed
            end
            if adapted_width - title_icon_width < title_max_width then
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

    if self.title_icon_widget then
        self.title_widget = HorizontalGroup:new {
            self.title_icon_widget,
            self.title_widget,
        }
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

    if self.tab_buttons_left then
        table_insert(self.title_group, self.tab_buttons_left_top_padding)
    end

    if self.align == "left" then
        --* we need to :resetLayout() both VerticalGroup and HorizontalGroup in :setTitle()

        local title_elems = {
            HorizontalSpan:new{ width = self.top_left_buttons_reserved_width + self.title_h_padding },
        }
        table_insert(title_elems, self.title_widget)
        self.inner_title_group = HorizontalGroup:new(title_elems)
        table_insert(self.title_group, self.inner_title_group)
    else
        table_insert(self.title_group, self.title_widget)
    end

    if self.subtitle_widget then
        table_insert(self.subtitle_group, VerticalSpan:new{ width = self.title_subtitle_v_padding })
        if self.align == "left" then
            local span_width = self.title_h_padding
            if not self.subtitle_fullwidth then
                span_width = span_width + self.top_left_buttons_reserved_width
            end
            self.inner_subtitle_group = HorizontalGroup:new{
                HorizontalSpan:new{ width = span_width },
                self.subtitle_widget,
            }
            table_insert(self.subtitle_group, self.inner_subtitle_group)
        else
            table_insert(self.subtitle_group, self.subtitle_widget)
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
    table_insert(self.title_group_vertically_centered, self.title_group)

    self.center_container = VerticalGroup:new{
        align = self.align,
        overlap_align = self.align,
        self.title_group_vertically_centered,
    }
    if self.align == "left" and self.subtitle_widget then
        table_insert(self.center_container, self.subtitle_group)
    end

    if self.align == "center" and self.subtitle_widget then
        table_insert(self.center_container, self.subtitle_widget)
        --- we need this extra CenterContainer as wrapper to make sure that title and subtitle are nicely centered as one module:
        self.center_container = CenterContainer:new{
            dimen = Geom:new{ w = math_max(self.title_width, self.subtitle_width), h = self.title_height },
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

    table_insert(self.main_container, self.center_container)
end

--- @private
function TitleBar:injectTabButtonsLeft()
    --? used by methods in ((TabFactory#setTabButtonAndContent)) > ((tabs in titlebar)) ??:
    --* button props were set in ((Button#addTitleBarTabButtonProps)):
    self.tabs = {}
    if not self.tab_buttons_left then
        return
    end

    self.title_padding_for_computations = self.is_landscape_screen and self.title_h_padding or self.title_h_padding_portrait

    local separator = HorizontalSpan:new{ width = self.title_padding_for_computations }
    --* horizontal padding from the left:
    table_insert(self.left_buttons_container, HorizontalSpan:new{ width = self.title_padding_for_computations })
    local button
    count = #self.tab_buttons_left
    for i = 1, count do
        button = self:instantiateButton(self.tab_buttons_left[i])
        --? used by methods in ((TabFactory#setTabButtonAndContent)) > ((tabs in titlebar)) ??:
        table_insert(self.tabs, button)
        table_insert(self.left_buttons_container, separator)
        table_insert(self.left_buttons_container, button)
    end

    local dims = self.left_buttons_container:getSize()
    self.top_left_buttons_height = dims.h
    self.top_buttons_left_reserved_width = dims.w

    self.tab_buttons_left_inserted = true
end

--- @private
function TitleBar:injectTabButtonsRight()

    --* button props were set in ((Button#addTitleBarTabButtonProps)):
    if self.tab_buttons_right then
        local button
        local separator = HorizontalSpan:new{ width = self.title_padding_for_computations }
        count = #self.tab_buttons_right
        for i = count, 1, -1 do
            button = self:instantiateButton(self.tab_buttons_right[i])
            --? used by methods in ((TabFactory#setTabButtonAndContent)) ??:
            table_insert(self.tabs, button)
            table_insert(self.right_buttons_container, 1, button)
            table_insert(self.right_buttons_container, 2, separator)
        end

        self.tab_buttons_right_inserted = true

    --* add empty spacer:
    elseif not self.top_buttons_right and not self.has_only_close_button_on_right_side then
        table_insert(self.right_buttons_container, HorizontalSpan:new{ width = self.top_right_buttons_reserved_width })

        self.tab_buttons_right_inserted = true
    end

    if self.tab_buttons_right_inserted then
        local dims = self.right_buttons_container:getSize()
        self.top_right_buttons_height = dims.h
        self.top_buttons_right_reserved_width = dims.w
    end
end

--- @private
function TitleBar:addCloseButton()
    if self.no_close_button or not self.close_callback or self.close_button_inserted then
        return
    end

    self.has_top_buttons_right = true
    local add_to_other_buttons = self.top_buttons_right
    --* in this case we need a smaller spacer above the close button in ((TitleBar#addVerticalSpacers)), because for some reason the button would not be vertically centered otherwise:
    self.has_only_close_button_on_right_side = not add_to_other_buttons
    self.has_top_buttons = true

    --* don't insert close button repeatedly:
    if add_to_other_buttons and self.top_buttons_right[#self.top_buttons_right].is_close_button then
        return
    end

    local icon_height = KOR.buttonprops:getFixedIconHeight("for_close_button")

    local close_button = Button:new({
        icon = self.titlebar_inverted and "close-inverted" or "close-kor",
        icon_height = icon_height,
        icon_width = icon_height - 20,
        is_close_button = true,
        background = self.titlebar_inverted and self.inverted_background_color or KOR.colors.white,
        generate_inverted_icon = self.titlebar_inverted,
        callback = function()
            --* only a dialog registered in DialogsQueue may reset the dialogs queue:
            if self.dialog_queue_id then
                KOR.dialogsqueue:reset()
            end
            if self.parent_has_tabs then
                UIManager:close(KOR.dialogs.last_dialog_instance)
            end
            self.close_callback()
        end,
        hold_callback = function()
            if self.close_hold_callback then
                self.close_hold_callback()
            end
        end
    })

    if add_to_other_buttons then
        table_insert(self.top_buttons_right, close_button)
        --? to prevent repeated injection; why needed?:
        self.close_button_inserted = true
        return
    end

    self.top_buttons_right = {
        close_button,
    }
end

function TitleBar:addDialogQueueButton()
    local buttons = self.tab_buttons_left or self.top_buttons_left

    if has_no_items(buttons) or not self.dialog_queue_id or not KOR.dialogsqueue:getParentId() or KOR.dialogsqueue:getQueueCount() < 2 then
        return
    end

    --[[if #buttons > 0 and buttons[#buttons].icon == "back-small" then
        table_remove(buttons)
    end]]

    table_insert(buttons, KOR.buttonchoicepopup:forXrayReturnToCaller({
        info = T(_("back icon | :return to the dialog from which you opened the current item\n\n:close current dialog and return to the first opened dialog - %1 - in the dialog history"), KOR.dialogsqueue:getFirstDialogDescription()),
        callback = function()
            if self.close_callback then
                self.close_callback()
            else
                UIManager:close(self.show_parent)
            end
            KOR.dialogsqueue:restorePrevious(self.dialog_queue_id)
        end,
        hold_callback = function()
            if self.close_callback then
                self.close_callback()
            else
                UIManager:close(self.show_parent)
            end
            KOR.dialogsqueue:returnToFirstDialog()
        end,
    }))
end

--* compare ((TitleBar#setTopButtonsSizeAndCallbacks))
--* compare ((TitleBar#getAdaptedTopButton))
--- the groups generated here are only horizontally oriented
--- @private
function TitleBar:generateTopButtonsGroups()

    --* self.top_buttons_left and self.top_buttons_right will be nil when there were self.tab_buttons_left and self.tab_buttons_right, because of ((TitleBar#ifTabButtonsLeftThenAddTopButtonsLeft)):
    local populate_left_buttons = self.top_buttons_left
    local populate_right_buttons = self.top_buttons_right
    if (not populate_left_buttons and not populate_right_buttons) or self.first_init_done then
        return
    end

    self:initTopButtonGroupsSpacer()
    self:initPopoutDialogButtonPadding()

    local dims
    if populate_left_buttons then
        --* this is de facto a left-side-padding for top_buttons_left:
        table_insert(self.left_buttons_container, self.top_button_group_spacer)
        count = #self.top_buttons_left
        for nr = 1, count do
            self:injectLeftButtonGroupButton(nr)
        end
        dims = self.left_buttons_container:getSize()
        self.top_left_buttons_height = dims.h
        self.top_buttons_left_reserved_width = dims.w
    end
    if not populate_right_buttons then
        return
    end

    count = #self.top_buttons_right
    for nr = 1, count do
        self:injectRightButtonGroupButton(nr)
    end
    if self.popout_dialog_button_spacer then
        --* defined in ((TitleBar#initPopoutDialogButtonPadding)); at start of ((TitleBar#injectLeftButtonGroupButton)) this was also injected in this case:
        table_insert(self.right_buttons_container, self.popout_dialog_button_spacer)
    end
    dims = self.right_buttons_container:getSize()
    self.top_right_buttons_height = dims.h
    self.top_buttons_right_reserved_width = dims.w

    --? strangely enough things go wrong when we wrap self.right_buttons_container in a RightContainer here; it MUST be done only in ((TitleBar#injectSideContainersRightVerticallyPadded))...
end

--* compare ((TitleBar#injectRightButtonGroupButton)):
--- @private
function TitleBar:injectLeftButtonGroupButton(nr)
    local button = self:instantiateButton(self.top_buttons_left[nr])
    if nr == 1 and self.popout_dialog_button_spacer then
            --* defined in ((TitleBar#initPopoutDialogButtonPadding)); will also be injected at end of ((TitleBar#injectRightButtonGroupButton)):
            table_insert(self.left_buttons_container, self.popout_dialog_button_spacer)
        end
    button = self:getAdaptedTopButton(button)
    if nr == 1 then
        self.left_button = button
    end
    table_insert(self.left_buttons_container, button)
    --* count has been set by caller:
    if nr < count then
        table_insert(self.left_buttons_container, self.top_button_group_spacer)
    end
    return button
end

--* compare ((TitleBar#injectLeftButtonGroupButton)):
--- @private
function TitleBar:injectRightButtonGroupButton(nr)
    local button = self:instantiateButton(self.top_buttons_right[nr])
    button = self:getAdaptedTopButton(button)
    if nr == 1 then
        self.right_button = button
    end

    table_insert(self.right_buttons_container, button)

    --* count has been set by caller:
    if (nr < count or not self.no_close_button_padding) and not self.has_only_close_button then
        table_insert(self.right_buttons_container, self.top_button_group_spacer)
    end
end

--- @private
function TitleBar:initTopButtonGroupsSpacer()
    if self.top_button_group_spacer then
        return
    end
    --* under Android we need more horizontal spacing:
    local spacer_width = KOR.screenhelpers:getHorizontalSpacerWidth(nil, nil, self.use_minimal_spacers)

    self.top_button_group_spacer = HorizontalSpan:new{
        width = spacer_width,
    }
end

--- @private
function TitleBar:initPopoutDialogButtonPadding()
    if self.popout_dialog_button_spacer or not self.is_popout_dialog then
        return
    end
    self.popout_dialog_button_spacer = HorizontalSpan:new {
        width = self:getCloseButtonPaddingRight(),
    }
end

--- @private
function TitleBar:injectFillerAndBottomLine()
    if self.with_bottom_line or self.submenu_buttontable or self.tabs_table_buttons then

        local width = self.is_popout_dialog and self.width - 2 * Size.line.thick or self.width

        local background = self.submenu_buttontable and KOR.colors.title_bar_with_submenu_bottom_line or KOR.colors.title_bar_bottom_line
        local line_widget = LineWidget:new{
            dimen = Geom:new{ w = width, h = self.bottom_line_thickness },
            background = background,
        }
        if self.bottom_line_h_padding then
            line_widget.dimen.w = line_widget.dimen.w - 2 * self.bottom_line_h_padding
            line_widget = HorizontalGroup:new{
                HorizontalSpan:new{ width = self.bottom_line_h_padding },
                line_widget,
            }
        end

        local filler_and_bottom_line = VerticalGroup:new{
            VerticalSpan:new{ width = self.computed_titlebar_height },
            self.submenu_buttontable_container,
            line_widget,
        }
        table_insert(self, filler_and_bottom_line)
        self.titlebar_height = filler_and_bottom_line:getSize().h
    end
end

--* defacto used for showing description line above a field for ((InputDialog)):
--- @private
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
        table_insert(self, filler_and_info_text)
        if not self.bottom_v_padding then
            self.bottom_v_padding = 0
        end
        self.titlebar_height = filler_and_info_text:getSize().h
    end
end

--- @private
function TitleBar:injectSideContainersLeftVerticallyPadded()
    if not self.has_top_buttons then
        return
    end

    --- inject left container, either with icon buttons or tab buttons:

    local container
    if self.has_top_buttons_left then
        --* the height used for computation was computed in ((TitleBar#generateTopButtonsGroups)) or ((TitleBar#injectTabButtonsLeft)):
        container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            self.left_buttons_container,
        }
        if self.tab_buttons_left then
            self.tab_buttons_left_top_padding = VerticalSpan:new{ width = Screen:scaleBySize(2) }
            table_insert(container, 1, self.tab_buttons_left_top_padding)
        end
        container = LeftContainer:new{
            dimen = container:getSize(),
            container,
        }
        table_insert(self.main_container, container)
        return
    end

    --* in case of top_buttons_right but no top_buttons_left and centered title, add empty filler for left buttons group:
    if self.has_top_buttons_right and self.align == "center" then
        container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            HorizontalSpan:new{ width = self.top_right_buttons_reserved_width },
        }
        container = LeftContainer:new{
            dimen = container:getSize(),
            container,
        }
        table_insert(self.main_container, container)
    end
end

--- @private
function TitleBar:injectSideContainersRightVerticallyPadded()
    if not self.has_top_buttons then
        return
    end

    if self.has_top_buttons_right then
        --* the height used for computation was computed in ((TitleBar#generateTopButtonsGroups)):
        local dims = self.right_buttons_container:getSize()
        table_insert(self.main_container, RightContainer:new{
            dimen = Geom:new{ w = self.top_right_buttons_reserved_width, h = dims.h },
            align = "left",
            overlap_align = "left",
            self.right_buttons_container,
        })
        return
    end

    --* in case of top_buttons_left but no top_buttons_right and centered title, add empty filler for right buttons group:
    if self.has_top_buttons_left and self.align == "center" then
        table_insert(self.main_container, VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            HorizontalSpan:new{ width = self.top_left_buttons_reserved_width },
        })
    end
end

--- @private
function TitleBar:injectSubMenuButtons()
    if self.submenu_buttontable then
        table_insert(self.submenu_buttontable_container, self.submenu_buttontable)
    end
end

--- @private
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

--- @private
function TitleBar:ifTabButtonsLeftThenAddTopButtonsLeft()
    if not self.tab_buttons_left or not self.top_buttons_left then
        return
    end

    local button
    count = #self.top_buttons_left
    for i = 1, count do
        button = self.top_buttons_left[i]
        button.bordersize = 0
        table_insert(self.tab_buttons_left, 1, button)
    end
    self.top_buttons_left = nil
end

--- @private
function TitleBar:addVerticalSpacers()

    local title_height = self.center_container:getSize().h
    local max_height = title_height

    if self.has_top_buttons_left then
        --* this height was set in ((TitleBar#injectTabButtonsLeft)):
        if self.top_left_buttons_height > max_height then
            max_height = self.top_left_buttons_height
        end
    end
    if self.has_top_buttons_right then
        --* this height was set in ((TitleBar#injectTabButtonsRight)):
        if self.top_right_buttons_height > max_height then
            max_height = self.top_right_buttons_height
        end
    end

    local padding = Screen:scaleBySize(1)
    max_height = max_height + 2 * padding
    self.computed_titlebar_height = max_height

    padding = math_ceil((max_height - title_height) / 2)
    self.center_container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
        VerticalSpan:new{ width = padding },
            CenterContainer:new{
                dimen = Geom:new{ w = self.width - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width, h = title_height },
                self.center_container,
            },
        VerticalSpan:new{ width = padding },
        }

    --* top_buttons_left:
    local padding_top
    if self.has_top_buttons_left then
        padding = math_ceil((max_height - self.top_left_buttons_height) / 2)
        padding_top = padding
        self.left_buttons_container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            VerticalSpan:new{ width = padding_top },
            self.left_buttons_container,
            VerticalSpan:new{ width = padding },
        }
    end

    --* top_buttons_right:
    if self.has_top_buttons_right and not KOR.registry:get("history_active") then
        padding = math_ceil((max_height - self.top_right_buttons_height) / 2)
        padding_top = padding
        self.right_buttons_container = VerticalGroup:new{
            align = "left",
            overlap_align = "left",
            VerticalSpan:new{ width = padding_top },
            self.right_buttons_container,
            VerticalSpan:new{ width = padding },
        }
    end
end

--* compare ((TitleBar#computeCorrectedTitleWidthForOnlyCloseButton)):
--- @private
function TitleBar:computeCorrectedTitleWidth()
    self.top_left_buttons_reserved_width = 0
    self.top_right_buttons_reserved_width = 0
    if self.has_top_buttons_left then
        self.top_left_buttons_reserved_width = self.left_buttons_container:getSize().w
    end
    if self.has_top_buttons_right then
        self.top_right_buttons_reserved_width = self.right_buttons_container:getSize().w
    end

    -- #((corrected title width for Xray edit dialog))
    self.corrected_title_width = self.width - self.top_left_buttons_reserved_width - self.top_right_buttons_reserved_width
end

--? for some reason for popout dialogs with only a close button the computations in ((TitleBar#computeCorrectedTitleWidth)) don't work - close button then outside dialog -, so in that case we need these computations:
--- @private
function TitleBar:computeCorrectedTitleWidthForOnlyCloseButton()
    self.top_left_buttons_reserved_width = 0
    self.top_right_buttons_reserved_width = self.right_buttons_container:getSize().w
    local screen_width = Screen:getWidth()
    if self.align == "center" then
        --* Keep title and subtitle text centered even if single button
        self.top_left_buttons_reserved_width = math_max(self.top_left_buttons_reserved_width, self.top_right_buttons_reserved_width)
        self.top_right_buttons_reserved_width = self.top_left_buttons_reserved_width

        self.corrected_title_width = self.has_only_close_button and math_min(self.width, screen_width - self.top_left_buttons_reserved_width) or math_min(self.width, screen_width - 2 * self.top_left_buttons_reserved_width)
    end
end

--- @private
function TitleBar:getCloseButtonPaddingRight()
    local padding
    if self.fullscreen then
        padding = Size.padding.fullscreen
        return padding
    end

    --* to make sure e.g. the close button doesn't overlap the radius of the dialog border:
    return Size.padding.closebuttonpopupdialog
end

return TitleBar
