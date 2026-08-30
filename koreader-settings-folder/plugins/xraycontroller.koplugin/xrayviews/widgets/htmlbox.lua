
local require = require

local BD = require("ui/bidi")
local Button = require("xrayviews/widgets/button")
local ButtonTable = require("xrayviews/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("xrayviews/widgets/checkbutton")
local Device = require("device")
local Font = require("modules/font")
local FrameContainer = require("xrayviews/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("xrayviews/widgets/inputdialog")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("xrayviews/widgets/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollHtmlWidget = require("xrayviews/widgets/scrollhtmlwidget")
local ScrollTextWidget = require("xrayviews/widgets/scrolltextwidget")
local Size = require("modules/size")
local TextWidget = require("xrayviews/widgets/textwidget")
local TitleBar = require("xrayviews/widgets/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
--local logger = require("logger")
local Screen = Device.screen
local _ = KOR:initCustomTranslations()

local DX = DX
local has_items = has_items
local math_floor = math_floor
local math_max = math_max
local math_min = math_min
local math_round = math_round
local pairs = pairs
local table_insert = table_insert
local table_remove = table_remove
local type = type
local utf8lower = utf8lower

local count

--- @class HtmlBox
--- @field box_widget HtmlBoxWidget
local HtmlBox = InputContainer:extend{
    _find_next = false,
    active_tab = nil,
    additional_key_events = nil,
    after_close_callback = nil,
    align = "center",
    auto_height = false,
    bottom_widget = nil,
    --! we use text_viewer_font_size instead of html_box_font_size here, because the latter is a value in percentages:
    box_font_size = DX.s.textviewer_font_size,
    box_widget = nil,
    buttons_table = nil,
    case_sensitive = true,
    check_button_case = nil,
    content_padding = nil,
    --* this is the default, but some widgets can set the content_type to "text" for a specific tab; e.g. see ((XrayButtons#getItemViewerTabs)):
    content_type = "html",
    css = nil,
    dialog_queue_id = nil,
    extract_texts = false,
    frame_content_fullscreen = nil,
    frame_content_windowed = nil,
    fullscreen = false,
    has_items_editor = false,
    has_tabs = false,
    headings = nil,
    height = nil,
    html = nil,
    --* for two column display of linked items in landscape display:
    html2 = nil,
    --* for three column display of linked items in landscape display:
    html3 = nil,
    html_widget = nil,
    html_widget1 = nil,
    html_widget2 = nil,
    html_widget3 = nil,
    is_duo_scroll_widget = false,
    is_reference_information_or_glossary = false,
    is_single_scroll_widget = true,
    is_three_scroll_widget = false,
    key_events_module = nil,
    left_side_buttons = nil,
    modal = true,
    next_item_callback = nil,
    no_buttons_row = false,
    --* to inform the parent about a newly activated tab, via ((TabNavigator#broadcastActivatedTab)):
    parent = nil,
    --* optional list of full_paths, to open books retrieved on base of the current html content of the box:
    paths = nil,
    prev_item_callback = nil,
    ratio_per_chapter = nil,
    search_for_headings = false,
    search_value = "",
    screen_height = nil,
    screen_width = nil,
    separator = nil,
    --* this table will be populated by ((TabFactory#setTabButtonAndContent)):
    tabs_table_buttons = nil,
    title = nil,
    title_alignment = "left",
    titlebar = nil,
    titlebar_height = nil,
    title_tab_buttons_left = nil,
    title_tab_callbacks = nil,
    top_buttons_left = nil,
    top_buttons_right = nil,
    width = nil,
    --* Static class member, holds a ref to the currently opened widgets (in instantiation order).
    window_list = {},
    window_size = "medium", --* or fullscreen, max, large, small, or table with props h and w, or highcenter
}

function HtmlBox:init()
    self:initFrames()
    self:setModuleProps()
    self:initHotkeys()
    self:initTouch()
    self:setWidth()
    --* height will be computed below, after we build top and bottom components, when we know how much height they are taking
    self:generateTitleBar()
    self:setPaddingAndSpacing()
    self:computeLineHeight()
    self:generateButtons()
    self:setMargins()
    self:computeAvailableHeight()
    self:generateTabsTable()
    self:setSeparator()
    self:computeHeights()
    self:generateScrollWidget()
    self:addFrameToContentWidget()
    self:generateWidget()
    if not self.is_fullscreen then
        self:generateMovableContainer()
    end
    self:finalizeWidget()
end

--- @private
function HtmlBox:initFrames()
    self.frame_bordersize = not self.is_fullscreen and Size.border.window or 0
    self.frame_content_windowed = {
        radius = Size.radius.window,
        bordersize = self.frame_bordersize,
        padding = 0,
        margin = 0,
        background = KOR.colors.background,
    }
    self.frame_content_fullscreen = {
        radius = 0,
        bordersize = self.frame_bordersize,
        fullscreen = true,
        covers_fullscreen = true,
        padding = 0,
        margin = 0,
        background = KOR.colors.background,
        --* make the borders white to hide them completely:
        color = KOR.colors.background,
    }
end

--- @private
function HtmlBox:initHotkeys()
    KOR.keyevents:addHotkeysForHtmlBox(self, self.key_events_module)

    --! we need this call to restore hotkeys for the dialog every time a new tab gets activated (and therefore the dialog reloaded):
    --* examples of hotkeys configurators: ((KeyEvents#addHotkeysForXrayPageNavigator)) and ((KeyEvents#addHotkeysForXrayItemViewer)):
    if self.hotkeys_configurator then
        self.hotkeys_configurator()
    end
end

--- @private
function HtmlBox:initTouch()
    if not Device:isTouchDevice() then
        return
    end

    local range = Geom:new{
        x = 0, y = 0,
        w = self.screen_width,
        h = self.screen_height,
    }
    self.ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
                range = range,
            },
        },
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = range,
            },
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = range,
            },
        },
        --* This was for selection of a single word with simple hold
        -- HoldWord = {
        --     GestureRange:new{
        --         ges = "hold",
        --         range = function()
        --             return self.region
        --         end,
        --     },
        --     -- callback function when HoldWord is handled as args
        --     args = function(word)
        --         KOR.ui:handleEvent(
        --             -- don't pass self.highlight to subsequent lookup, we want
        --             -- the first to be the only one to unhighlight selection
        --             -- when closed
        --             KOR.dictionary:onLookupWord(word, true, {self.word_box})
        --     end
        -- },
        --* Allow selection of one or more words (see textboxwidget.lua):
        HoldStartText = {
            GestureRange:new{
                ges = "hold",
                range = range,
            },
        },
        HoldPanText = {
            GestureRange:new{
                ges = "hold",
                range = range,
            },
        },
        --* These will be forwarded to MovableContainer after some checks
        ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
        ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
        ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
    }
end

--* Used in init & update to instantiate the Scroll*Widget that self.html_widget points to ((ScrollHtmlWidget)):
--- @private
function HtmlBox:generateScrollWidget()

    self.swidth = self.content_width
    self.sheight = self.content_height

    --* this is the default, but some widgets can set the content_type to "text" for a specific tab; e.g. see ((XrayButtons#getItemViewerTabs)):
    if self.content_type == "text" then
        self:generateTextScrollWidget()
        return
    end

    self:generateHtmlScrollWidget()
end

--- @private
function HtmlBox:generateHtmlScrollWidget()

    local edit_button
    if self.has_items_editor then
        edit_button = Button:new(KOR.buttoninfopopup:forXrayQuotesManager({
            callback = function()
                DX.c:showQuotesManager()
            end,
        }))
        local dims = edit_button:getSize()
        edit_button = RightContainer:new{
            dimen = Geom:new{
                w = self.swidth + dims.w,
                h = dims.h,
            },
            edit_button,
        }
    end

    self.html_widget = ScrollHtmlWidget:new{
        html_body = self.html,
        extract_texts = self.extract_texts,
        --* self.css here might have been set from the book css via ((ReferenceInformation#prepareHtmlAndCssForSaving)):
        css = KOR.html:getHtmlWidgetCss(self.is_reference_information_or_glossary, self.css),
        default_font_size = Screen:scaleBySize(self.box_font_size),
        width = self.swidth,
        height = self.sheight,
        dialog = self,
    }
    if not self.bottom_widget and self.has_items_editor then
        self.html_widget = OverlapGroup:new{
            dimen = Geom:new{
                w =  self.swidth,
                h = self.sheight,
            },
            edit_button,
            self.html_widget,
        }
        return
    elseif not self.bottom_widget then
        return
    end

    self.html_widget = VerticalGroup:new{
        align = "left",
        self.html_widget,
        self.bottom_widget,
    }
    if not self.has_items_editor then
        return
    end

    local height = self.sheight + self.bottom_widget:getSize().h
    self.html_widget = OverlapGroup:new{
        dimen = Geom:new{
            w = self.swidth,
            h = height,
        },
        edit_button,
        self.html_widget,
    }
end

--- @private
function HtmlBox:generateTextScrollWidget()
    self.is_duo_scroll_widget = false
    self.is_three_scroll_widget = false
    --* three column display:
    if self.html3 then
        self.is_three_scroll_widget = true
        self.is_single_scroll_widget = false
        self.html_widget, self.html_widget1, self.html_widget2, self.html_widget3 = KOR.columntexts:getThreeWidget({
            parent = self,
            column1_text = self.html,
            column2_text = self.html2,
            column3_text = self.html3,
            face = self.content_face,
            width = self.swidth,
            container_width = self.screen_width,
            height = self.sheight,
        })

    --* two column display:
    elseif self.html2 then
        self.is_duo_scroll_widget = true
        self.is_single_scroll_widget = false
        self.html_widget, self.html_widget1, self.html_widget2 = KOR.columntexts:getDuoWidget({
            parent = self,
            column1_text = self.html,
            column2_text = self.html2,
            face = self.content_face,
            width = self.swidth,
            container_width = self.screen_width,
            height = self.sheight,
        })

        --* single column display:
    else
        self.html_widget = CenterContainer:new{
            dimen = Geom:new{
                w = self.screen_width,
                h = self.sheight,
            },
            ScrollTextWidget:new{
                text = self.html,
                face = self.content_face,
                line_height = KOR.registry.line_height or 0.95,
                alignment = "left",
                justified = false,
                dialog = self,
                width = self.swidth,
                height = self.sheight,
            }
        }
    end
    if not self.bottom_widget then
        return
    end

    self.html_widget = VerticalGroup:new{
        align = "left",
        self.html_widget,
        --* to display the occurrences histogram centered under a box with content_type "text":
        CenterContainer:new{
            dimen = Geom:new{
                w = self.screen_width,
                h = self.bottom_widget:getSize().h,
            },
            self.bottom_widget,
        }
    }
end

function HtmlBox:onCloseWidget()

    if self.after_close_callback then
        self.after_close_callback()
    end
    self.additional_key_events = nil

    --* Drop our ref from the static class member
    for i = #HtmlBox.window_list, 1, -1 do
        local window = HtmlBox.window_list[i]
        --* We should only find a single match, but, better safe than sorry...
        if window == self then
            table_remove(HtmlBox.window_list, i)
        end
    end

    --* NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
end

function HtmlBox:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self.box_frame.dimen
    end)
    return true
end

-- #((HtmlBox#onTap))
function HtmlBox:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.box_frame.dimen) then
        self.garbage = arg
        KOR.dialogs:closeOverlay()
        self:onClose()
        return true
    end
    --* Allow for changing item with tap (tap event will be first
    --* processed for scrolling definition by ScrollTextWidget, which
    --* will pop it up for us here when it can't scroll anymore).
    --* This allow for continuous reading of results' definitions with tap.
    if BD.flipIfMirroredUILayout(ges_ev.pos.x < self.screen_width / 2) then
        self:onReadPrevItem()
    else
        self:onReadNextItem()
    end
    return true
end

function HtmlBox:onTap(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.box_frame.dimen) then
        self:onClose()
        KOR.registry:unset("dictionary_context")
        self.garbage = arg
        return true
    end

    return true
end

function HtmlBox:onClose()
    for menu in pairs(self.menu_opened) do
        UIManager:close(menu)
    end
    self.menu_opened = {}
    KOR.dialogs:unregisterWidget(self)
    UIManager:close(self)
    KOR.dialogs:closeAllOverlays()

    return true
end

function HtmlBox:onHoldClose()
    --* Pop the windows FILO
    for i = #HtmlBox.window_list, 1, -1 do
        local window = HtmlBox.window_list[i]
        window:onClose()
    end
    return true
end

function HtmlBox:onSwipe(arg, ges)
    return KOR.closingswipes:handle(self, arg, ges)
end

function HtmlBox:onHoldStartText(_, ges)
    if not self.movable then
        return false
    end
    --* Forward Hold events not processed by TextBoxWidget event handler
    --* to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function HtmlBox:onHoldPanText(arg, ges)
    if not self.movable then
        return false
    end
    --* Forward Hold events not processed by TextBoxWidget event handler
    --* to our MovableContainer
    --* We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function HtmlBox:onHoldReleaseText(_, ges)
    if not self.movable then
        return false
    end
    --* Forward Hold events not processed by TextBoxWidget event handler
    --* to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

--* These 3 event processors are just used to forward these events
--* to our MovableContainer, under certain conditions, to avoid
--* unwanted moves of the window while we are selecting text in
--* the definition widget.
function HtmlBox:onForwardingTouch(arg, ges)
    if not self.movable then
        return false
    end
    --* This Touch may be used as the Hold we don't get (for example,
    --* when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.content_widget.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        --* Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function HtmlBox:onForwardingPan(arg, ges)
    if not self.movable then
        return false
    end
    --* We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function HtmlBox:onForwardingPanRelease(arg, ges)
    if not self.movable then
        return false
    end
    --* We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end

function HtmlBox:onReadNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    KOR.tabnavigator:broadcastActivatedTab()
    return true
end

function HtmlBox:onReadPrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    KOR.tabnavigator:broadcastActivatedTab()
    return true
end

function HtmlBox:onReadPrevItemWithShiftSpace()
    self:onReadPrevItem()
    return true
end

--! this method and the next one are needed to jump to a next or previous page when pressing Space and Shift+Space on a physical (BT) keyboard:
function HtmlBox:onForceNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    return true
end

function HtmlBox:onForcePrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    return true
end

--* compare ((TextViewer#generateTabsTable)):
--- @private
function HtmlBox:generateTabsTable()
    if not self.tabs_table_buttons then
        return
    end
    self.tabs_table = KOR.buttontablefactory:getTabsTable(self)
    KOR.tabnavigator:broadcastActivatedTab()
end

--* add support for navigating to previous tab with hardware keys:
function HtmlBox:onToNextTab()
    return KOR.tabnavigator:onToNextTab()
end

function HtmlBox:onToPreviousTab()
    return KOR.tabnavigator:onToPreviousTab()
end

function HtmlBox:onForcePreviousTab()
    return KOR.tabnavigator:onForcePreviousTab()
end

--* add support for navigating to previous tab with hardware keys:
function HtmlBox:onForceNextTab()
    return KOR.tabnavigator:onForceNextTab()
end

--- @private
function HtmlBox:computeHeights()
    local tabs_table_height = self.tabs_table_buttons and self.tabs_table:getSize().h or 0
    local buttons_height = self.button_table and self.button_table:getSize().h or 0
    local others_height =
        self.frame_bordersize * 2
        + self.titlebar_height
        + Size.line.thick
        + 2 * self.content_top_margin:getSize().h
        + buttons_height
        + tabs_table_height

    --* To properly adjust the definition to the height of text, we need
    --* the line height a ScrollTextWidget will use for the current font
    --* size (we'll then use this perfect height for ScrollTextWidget,
    --* but also for ScrollHtmlWidget, where it doesn't matter).
    if not self.content_line_height then
        local test_widget = ScrollTextWidget:new{
            text = "z",
            face = self.content_face,
            width = self.content_width,
            height = self.content_height,
            for_measurement_only = true, --* flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        self.content_line_height = test_widget:getLineHeight()
        test_widget:free(true)
    end

    -- #((set HtmlBox dialog height))
    --* compare ((set HtmlBox dialog width))
    if type(self.window_size) == "table" then
        self.height = math_min(self.avail_height, math_floor(self.window_size.h))
        self.content_height = self.height - others_height
        local nb_lines = math_floor(self.content_height / self.content_line_height)
        self.content_height = nb_lines * self.content_line_height

    elseif self.is_fullscreen or self.window_size == "max"
            --* with prop auto_height we can maximize the height of the HtmlBox:
            or self.auto_height then
        self.height = self.avail_height
        self.content_height = self.height - others_height

    elseif self.window_size == "large" then
        self.content_height = math_floor(self.avail_height * 0.7)
        --* But we want it to fit to the lines that will show, to avoid
        --* any extra padding
        local nb_lines = math_round(self.content_height / self.content_line_height)
        self.content_height = nb_lines * self.content_line_height
        self.height = self.content_height + others_height

    elseif self.window_size == "highcenter" then
        self.height = self.avail_height
        self.content_height = self.height - others_height
        local nb_lines = math_floor(self.content_height / self.content_line_height)
        self.content_height = math_floor(nb_lines * self.content_line_height * 0.95)

    elseif self.window_size == "medium" then
        --* Available height for definition + components
        self.height = self.avail_height
        self.content_height = self.height - others_height
        local nb_lines = math_floor(self.content_height / self.content_line_height)
        self.content_height = math_floor(nb_lines * self.content_line_height * 0.35)

    else
        --* Main content height was previously computed as 0.5*0.7*screen_height, so keep
        --* it that way. Components will add themselves to that.
        self.content_height = math_floor(self.avail_height * 0.5 * 0.7)
        --* But we want it to fit to the lines that will show, to avoid
        --* any extra padding
        local nb_lines = math_round(self.content_height / self.content_line_height)
        self.content_height = nb_lines * self.content_line_height
        self.height = self.content_height + others_height
    end

    if self.bottom_widget then
        local bottom_widget_height = self.bottom_widget:getSize().h
        self.content_height = self.content_height - bottom_widget_height
    end
end

--- @private
function HtmlBox:computeLineHeight()
    --* Lookup word
    local word_font_face = "tfont"
    --* Ensure this word doesn't get smaller than its definition
    local word_font_size = math_max(22, self.box_font_size)
    --* Get the line height of the normal font size, as a base for sizing this component
    if not self.word_line_height then
        local test_widget = TextWidget:new{
            text = "z",
            face = Font:getFace(word_font_face, word_font_size),
        }
        self.word_line_height = test_widget:getSize().h
        test_widget:free()
    end
end

--* compare ((TextViewer#getDefaultButtons)):
--- @private
function HtmlBox:generateButtons()

    if self.no_buttons_row then
        return
    end

    --* self.headings might have been stored in ((ReferenceInformation#prepareHtmlAndCssForSaving)) or ((ReferenceInformation#addWikiHeadings)), and loaded in ((ReferenceInformation#load)):
    self.search_for_headings = self.is_single_scroll_widget and has_items(self.headings)

    --* Different sets of buttons whether fullpage or not
    local buttons = {
        {
            {
                text = "⇱",
                id = "top",
                vsync = true,
                callback = function()
                    if self.is_three_scroll_widget then
                        self.html_widget1:scrollToTop()
                        self.html_widget2:scrollToTop()
                        self.html_widget3:scrollToTop()
                        return
                    elseif self.is_duo_scroll_widget then
                        self.html_widget1:scrollToTop()
                        self.html_widget2:scrollToTop()
                        return
                    end
                    self.html_widget:scrollToTop()
                end,
            },
            {
                text = "⇲",
                id = "bottom",
                vsync = true,
                callback = function()
                    if self.is_three_scroll_widget then
                        self.html_widget1:scrollToBottom()
                        self.html_widget2:scrollToBottom()
                        self.html_widget3:scrollToBottom()
                        return
                    elseif self.is_duo_scroll_widget then
                        self.html_widget1:scrollToBottom()
                        self.html_widget2:scrollToBottom()
                        return
                    end
                    self.html_widget:scrollToBottom()
                end,
            },
            {
                id = "close",
                icon = "back",
                icon_size_ratio = 0.8,
                callback = function()
                    self:onClose()
                end,
                hold_callback = function()
                    self:onHoldClose()
                end,
            },
        },
    }
    if self.tweak_buttons_func then
        self:tweak_buttons_func(buttons)
    end
    if self.left_side_buttons then
        count = #self.left_side_buttons[1]
        for i = count, 1, -1 do
            table_insert(buttons[1], 1, self.left_side_buttons[1][i])
        end
        table_remove(buttons[1])
    end

    if self.extract_texts then
        -- #((HtmlBox search button))
        --* compare ((TextViewer search button)):
        table_insert(buttons[1], 1, KOR.buttoninfopopup:forHtmlBoxSearch({
            callback = function()
                self:findDialog()
            end,
        }))
        table_insert(buttons[1], 2, KOR.buttoninfopopup:forHtmlBoxSearchNext({
            enabled_func = function()
                return self._find_next
            end,
            callback = function()
                if self._find_next then
                    self:findCallback()
                else
                    self:findDialog()
                end
            end,
        }))
    end

    if self.search_for_headings then
        table_insert(buttons[1], 3, KOR.buttoninfopopup:forTextViewerWikiHeadingsIndex({
            enabled_func = function()
                --* this prop is set in ((Dialogs#registerActiveTab)):
                return not self.tabs or KOR.dialogs.active_tab_index_enabled
            end,
            callback = function()
                KOR.referenceinformation:generateButtonsIndex(self, function(heading)
                    self.search_value = heading
                    self._find_next = false
                    self.case_sensitive = true
                    self:findCallback(nil, "search_from_start", _("heading"))
                end)
            end,
        }))
    end

    --* Bottom buttons get a bit less padding so their line separators
    --* reach out from the content to the borders a bit more
    local buttons_padding = Size.padding.default
    local buttons_width = self.inner_width - 2 * buttons_padding
    local config = {
        width = buttons_width,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    for key, value in pairs(DX.b.default_tabs_button_table_props) do
        config[key] = value
    end
    self.button_table = ButtonTable:new(config)
end

--- @private
function HtmlBox:findDialog()
    local input_dialog
    input_dialog = InputDialog:new{
        title = "Vul een zoekterm in",
        input = self.search_value,
        buttons = {
            {
                {
                    icon = "back",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                KOR.buttoninfopopup:forFindFromStart({
                    callback = function()
                        self._find_next = true
                        self:findCallback(input_dialog, "search_from_start")
                    end
                }),
                KOR.buttoninfopopup:forFindNext({
                    callback = function()
                        self._find_next = true
                        self:findCallback(input_dialog)
                    end
                }),
            },
        },
    }
    self.check_button_case = CheckButton:new{
        text = _("case-sensitive"),
        checked = self.case_sensitive,
        parent = input_dialog,
        callback = function()
            self.case_sensitive = self.check_button_case.checked
        end,
    }
    input_dialog:addWidget(self.check_button_case)

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard(true)
end

--- @private
function HtmlBox:findCallback(input_dialog, search_from_start, target)
    if input_dialog then
        self.search_value = input_dialog:getInputText()
        if self.search_value == "" then
            return
        end
        UIManager:close(input_dialog)
    end
    target = target or _("search term")

    --* this html_box_widget has props page_count, page_number (i.e. current "page"/screen):
    self.box_widget = self.html_widget.htmlbox_widget
    local start_page = self.box_widget.page_number
    local current_page = start_page
    local page_count = self.box_widget.page_count

    local msg
    self:prepareNeedleForMatching()
    local text = self:getPageTextForMatching(start_page)
    if page_count == 1 then
        msg = text:match(self.search_value) and target .. " " .. _("found in this screen") or target .. " " .. _("not found in this screen")
        KOR.messages:notify(msg)
        return
    end

    current_page = search_from_start and 1 or self:getNextPage(current_page, page_count)
    local search_on_start_page = false
    if search_from_start then
        start_page = 1
        search_on_start_page = true
    end
    local found = false
    while not found and (search_on_start_page or current_page ~= start_page) do
        text = self:getPageTextForMatching(current_page)
        found = text:match(self.search_value)
        search_on_start_page = false
        if not found then
            current_page = self:getNextPage(current_page, page_count)
        end
    end
    self._find_next = found
    if found then
        self.html_widget:scrollToPage(current_page)
        KOR.messages:notify(target .. " " .. _("found in this screen"))
        return
    end

    KOR.messages:notify(target .. " " .. _("not found (anymore)"))
    self._find_next = false
    self:findDialog()
end

--- @private
function HtmlBox:finalizeWidget()
    --* self.region was set in ((HtmlBox#computeAvailableHeight)):
    self[1] = self.is_fullscreen and
        WidgetContainer:new{
            align = "top",
            dimen = self.region,
            self.box_frame,
        }
        or
        WidgetContainer:new{
            align = self.align,
            dimen = self.region,
            self.movable,
        }

    --* we're a new window:
    table_insert(HtmlBox.window_list, self)

    UIManager:setDirty(self, function()
        return "partial", self.box_frame.dimen
    end)

    --* make HtmlBox widget closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
end

--- @private
function HtmlBox:addFrameToContentWidget()
    self.content_widget = FrameContainer:new{
        padding = 0,
        padding_left = self.content_padding_h,
        padding_right = self.content_padding_h,
        margin = 0,
        bordersize = 0,
        self.html_widget,
    }
end

--- @private
function HtmlBox:generateMovableContainer()
    self.movable = MovableContainer:new{
        --* We'll handle these events ourselves, and call appropriate
        --* MovableContainer's methods when we didn't process the event
        ignore_events = {
            --* These have effects over the definition widget, and may
            --* or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            --* These do not have direct effect over the definition widget,
            --* but may happen while selecting text: we need to check
            --* a few things before forwarding them
            "touch", "pan", "pan_release",
            },
        self.box_frame,
    }
end

--- @private
function HtmlBox:generateWidget()

    local frame = self.is_fullscreen and self.frame_content_fullscreen or self.frame_content_windowed

    local content_height = self.content_widget:getSize().h

    local elements = VerticalGroup:new{
        self.titlebar,
        self.separator,
        self.content_top_margin,
        --* content
        CenterContainer:new{
            dimen = Geom:new{
                w = self.inner_width,
                h = content_height,
            },
            self.content_widget,
        },
        self.content_bottom_margin,
    }

    if self.tabs_table then
        table_insert(elements, 2, self.tabs_table)
    end

    --? I don't know why I need this hack on my Bigme phone:
    if self.is_fullscreen and DX.s.is_mobile_device then
        local spacer = VerticalSpan:new{ width = Size.padding.large }
        table_insert(elements, 2, spacer)
    end

    if not self.no_buttons_row then
        table_insert(elements, CenterContainer:new{
            dimen = Geom:new{
                w = self.inner_width,
                h = self.button_table:getSize().h,
            },
            self.button_table,
        })
    end

    elements.align = "left"
    table_insert(frame, elements)
    self.box_frame = FrameContainer:new(frame)
end

--- @private
function HtmlBox:computeAvailableHeight()
    self.avail_height = self.screen_height - self.margin_top - self.margin_bottom

    --* Region in which the window will be aligned center/top/bottom:
    self.region = Geom:new{
        x = 0,
        y = self.is_fullscreen and 0 or self.margin_top,
        w = self.screen_width,
        h = self.avail_height,
    }
end

--- @private
function HtmlBox:setMargins()
    --* Margin from screen edges
    self.margin_top = not self.is_fullscreen and Size.margin.default or 0
    self.margin_bottom = not self.is_fullscreen and Size.margin.default or 0
    if KOR.ui and KOR.ui.view and KOR.ui.view.footer_visible then
        --* We want to let the footer visible (as it can show time, battery level
        --* and wifi state, which might be useful when spending time reading
        --* definitions or wikipedia articles)
        if not self.is_fullscreen then
            self.margin_bottom = self.margin_bottom + KOR.ui.view.footer:getHeight()
        end
    end
end

--- @private
function HtmlBox:setModuleProps()
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
    if self.fullscreen then
        self.window_size = "fullscreen"
    elseif self.window_size == "middlebox" then
        self.window_size = {
            w = self.screen_width / 2,
            h = self.screen_height / 2 + Screen:scaleBySize(20),
        }
    end
    if self.tabs_table_buttons then
        self.title_alignment = "center"
    end
    KOR.tabnavigator:broadcastActivatedTab()

    if self.hml1 then
        self.extract_texts = false
    end

    if DX.s.PN_show_chapter_hits_histogram then
        self.histogram_height = Screen:scaleBySize(25)
        self.histogram_bottom_line_height = Size.line.thin
    end

    if DX.s.is_mobile_device then
        self.box_font_size = 26
    end
    self.content_face = Font:getFace("x_smallinfofont", self.box_font_size)
    --self.content_face = Font:getFace("infofont", self.box_font_size)
    self.is_fullscreen = self.window_size == "fullscreen"

    --* Scrollable offsets of the various showResults* menus and submenus,
    --* so we can reopen them in the same state they were when closed.
    self.menu_scrolled_offsets = {}
    --* We'll also need to close any opened such menu when closing this HtmlBox
    --* (needed if closing all DictQuickLookups via long-press on Close on the top one)
    self.menu_opened = {}
end

--- @private
function HtmlBox:setPaddingAndSpacing()
    --* This padding and the resulting width apply to the content
    --* below the title:  lookup word and definition
    self.content_padding_h = self.content_padding or (self.window_size == "fullscreen" or self.window_size == "max" or type(self.window_size) == "table") and Size.padding.closebuttonpopupdialog or Size.padding.large
    local content_padding_v = Size.padding.fullscreen --* added via VerticalSpan
    self.content_width = self.inner_width - 2 * self.content_padding_h
    --* in two column display of linked items, make more room available:
    if self.html2 then
        self.content_width = self.inner_width
    end

    self.content_padding_v =  content_padding_v

    --* Spans between components
    self.content_top_margin = VerticalSpan:new{ width = content_padding_v }
    self.content_bottom_margin = VerticalSpan:new{ width = content_padding_v }
end

--- @private
function HtmlBox:setSeparator()
    self.separator = LineWidget:new{
        background = self.tabs_table and KOR.colors.tabs_table_separators or KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
end

--* compare ((TitleBar for TextViewer)):
--- @private
function HtmlBox:generateTitleBar()
    local config = {
        width = self.inner_width,
        title = self.title,
        title_face = Font:getFace("smallinfofontbold"),
        --* HtmlBox delivers the separator, so we don't want a separator in the titlebar:
        with_bottom_line = false,
        close_callback = function()
            self:onClose()
        end,
        close_hold_callback = function()
            self:onHoldClose()
        end,
        dialog_queue_id = self.dialog_queue_id,
        has_small_close_button_padding = true,
        align = self.title_alignment,
        parent_has_tabs = self.has_tabs,
        show_parent = self,
        lang = self.lang_out,
        top_buttons_left = self.top_buttons_left,
        top_buttons_right = self.top_buttons_right,

        less_title_top_padding = DX.s.is_tablet_device and self.tabs_table_buttons and true or false,
    }
    if self.tabs_table_buttons then
        config.with_bottom_line = true
    end
    self.titlebar = TitleBar:new(config)
    self.titlebar_height = self.titlebar:getSize().h
end

--- @private
function HtmlBox:setWidth()
    -- #((set HtmlBox dialog width))
    --* compare ((set HtmlBox dialog height))
    if not self.width then
        if type(self.window_size) == "table" then
            self.width = math_floor(self.window_size.w)
        --* always use max available width on Bigme:
        elseif self.is_fullscreen then
            self.width = self.screen_width
        elseif self.window_size == "max" or DX.s.is_mobile_device then
            self.width = self.screen_width - 2 * Size.margin.default
        elseif self.window_size == "large" then
            self.width = self.screen_width - 2 * Size.margin.extreme
        elseif self.window_size == "highcenter" then
            self.width = math_floor(self.screen_width * 0.6)
        elseif self.window_size == "medium" then
            self.width = self.screen_width - Screen:scaleBySize(300)
        else
            self.width = self.screen_width - Screen:scaleBySize(80)
        end
    end
    self.inner_width = self.width - 2 * self.frame_bordersize
end

function HtmlBox:onToPreviousTabWithShiftSpace()
    return self:onToPreviousTab()
end

--- @private
function HtmlBox:getPageTextForMatching(current_page)
    local text = self.box_widget:getPageText(current_page)
    if not self.case_sensitive then
        return utf8lower(text)
    end
    return text
end

--- @private
function HtmlBox:prepareNeedleForMatching()
    if not self.case_sensitive then
        self.search_value = utf8lower(self.search_value)
    end
    self.search_value = KOR.strings:prepareNeedleForMatching(self.search_value)
end

--- @private
function HtmlBox:getNextPage(current_page, page_count)
    current_page = current_page + 1
    if current_page > page_count then
        return 1
    end
    return current_page
end

return HtmlBox
