
--* derived from ((DictQuickLookup))

local require = require

local BD = require("ui/bidi")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollHtmlWidget = require("extensions/widgets/scrollhtmlwidget")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextWidget = require("extensions/widgets/textwidget")
local TitleBar = require("extensions/widgets/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
--local logger = require("logger")
local Screen = Device.screen

local DX = DX
local G_reader_settings = G_reader_settings
local has_items = has_items
local has_text = has_text
local math = math
local math_floor = math.floor
local pairs = pairs
local table = table
local table_insert = table.insert
local type = type

-- Inject scroll page method for ScrollHtmlWidget
ScrollHtmlWidget.scrollToPage = function(self, page_num)
    if page_num > self.htmlbox_widget.page_count then
        page_num = self.htmlbox_widget.page_count
    end
    self.htmlbox_widget:setPageNumber(page_num)
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()
    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

ScrollHtmlWidget.scrollToPage = function(self, page_num)
    if page_num > self.htmlbox_widget.page_count then
        page_num = self.htmlbox_widget.page_count
    end
    self.htmlbox_widget:setPageNumber(page_num)
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()
    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

--- @class HtmlBox
--- @field page_navigator XrayPageNavigator
local HtmlBox = InputContainer:extend{
    additional_key_events = nil,
    after_close_callback = nil,
    align = "center",
    buttons_table = nil,
    content_padding = nil,
    --* this is the default, but some widgets can set the content_type to "text" for a specific tab; e.g. see ((XrayButtons#getItemViewerTabs)):
    content_type = "html",
    frame_content_fullscreen = nil,
    frame_content_windowed = nil,
    fullscreen = false,
    has_anchor_button = false,
    height = nil,
    html = nil,
    info_panel_buttons = nil,
    info_panel_text = nil,
    key_events_module = nil,
    modal = true,
    next_item_callback = nil,
    no_buttons_row = false,
    page_navigator = nil,
    --* to inform the parent about a newly activated tab, via ((TabNavigator#broadcastActivatedTab)):
    parent = nil,
    --* optional list of full_paths, to open books retrieved on base of the current html content of the box:
    paths = nil,
    prev_item_callback = nil,
    screen_height = nil,
    screen_width = nil,
    side_buttons = nil,
    side_buttons_width = Screen:scaleBySize(135),
    side_panel_tab_activators = nil,
    --* this table will be populated by ((TabFactory#setTabButtonAndContent)):
    tabs_table_buttons = nil,
    title = nil,
    title_alignment = "left",
    titlebar = nil,
    titlebar_height = nil,
    title_tab_buttons_left = nil,
    title_tab_callbacks = nil,
    top_buttons_left = nil,
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
    self:generateSidePanelButtons()
    self:generateButtonTables()
    self:setMargins()
    self:computeAvailableHeight()
    self:generateTabsTable()
    self:setSeparator()
    self:computeHeights()
    self:generateInfoButtons()
    self:generateInfoPanel()
    self:generateScrollWidget()
    self:generateSidePanel()
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

    if Device:isTouchDevice() then
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
end

--- @private
function HtmlBox:getHtmlBoxCss()
    --* Using Noto Sans because Nimbus doesn't contain the IPA symbols.
    --* 'line-height: 1.3' to have it similar to textboxwidget,
    --* and follow user's choice on justification
    local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
    local css = [[
        @page {
            margin: 0;
            font-family: 'Noto Sans';
        }

        body {
            margin: 0;
            line-height: 1.3;
            ]]..css_justify..[[
        }

        div.redhat, div.redhat * {
            font-family: 'Red Hat Text' !important;
        }

        blockquote, dd {
            margin: 0 1em;
        }

        ol, ul, menu {
            margin: 0; padding: 0 1.7em;
        }

        p {
            margin: 0;
        }

        p + p {
            text-indent: 1.5em;
        }

        p.whitespace + p {
            text-indent: 0;
        }

        div.poezie p {
            text-indent: 0 !important;
        }
    ]]
    --* For reference, MuPDF declarations with absolute units:
    --*  "blockquote{margin:1em 40px}"
    --*  "dd{margin:0 0 0 40px}"
    --*  "ol,ul,menu {margin:1em 0;padding:0 0 0 30pt}"
    --*  "hr{border-width:1px;}"
    --*  "td,th{padding:1px}"
    --*
    --* MuPDF doesn't currently scale CSS pixels, so we have to use a font-size based measurement.
    --* Unfortunately MuPDF doesn't properly support `rem` either, which it bases on a hard-coded
    --* value of `16px`, so we have to go with `em` (or `%`).
    --*
    --* These `em`-based margins can vary slightly, but it's the best available compromise.
    --*
    --* We also keep left and right margin the same so it'll display as expected in RTL.
    --* Because MuPDF doesn't currently support `margin-start`, this results in a slightly
    --* unconventional but hopefully barely noticeable right margin for <dd>.
    --*
    --* For <ul> and <ol>, bullets and numbers are displayed in the margin/padding, so
    --* we need a bit more for them to not get truncated (1.7em allows for 2 digits list
    --* item numbers). Unfortunately, because we want this also for RTL, this space is
    --* wasted on the other side...

    if self.css then
        return css .. self.css
    end
    return css
end

--- @private
function HtmlBox:generateInfoButtons()
    --? for some reason self.side_buttons_table not available when we click on the Item Viewer button; because then self.side_buttons not set at the start of ((XraySidePanels#generateSidePanelButtons)) and the script returns, without generating the side buttons:
    self.info_panel_width = self.side_buttons_table and self.content_width - self.side_buttons_table:getSize().w or self.content_width

    local buttons = ButtonTable:new{
        width = self.info_panel_width,
        --* these buttons were generated in ((XrayButtons#forPageNavigator)):
        buttons = self.info_panel_buttons,
        show_parent = self,
        button_font_weight = "normal",
    }

    if self.has_anchor_button then
        KOR.anchorbutton:setHeight(buttons:getSize().h)
    end

    local buttons_height = buttons:getSize().h
    self.info_panel_nav_buttons = CenterContainer:new{
        dimen = Geom:new{
            w = self.info_panel_width,
            h = buttons_height,
        },
        buttons,
    }
    self.info_panel_nav_buttons_height = self.info_panel_nav_buttons:getSize().h
end

--- @private
function HtmlBox:generateInfoPanel()
    if not self.side_buttons_table then
        --* for consumption in ((HtmlBox#generateScrollWidget)):
        self.swidth = self.content_width
        self.sheight = self.content_height
        return
    end

    local height = self.content_height
    --* info_text was generated in ((XrayPageNavigator#showNavigator)) > ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markItem)) > ((XrayPageNavigator#getItemInfoText)):
    local info_text = self.info_panel_text or " "
    self.info_panel = ScrollTextWidget:new{
        text = info_text,
        face = Font:getFace("x_smallinfofont", DX.s.PN_panels_font_size or 14),
        line_height = 0.16,
        alignment = "left",
        justified = false,
        dialog = self,
        --* info_panel_width was computed in ((HtmlBox#generateInfoButtons)):
        width = self.info_panel_width,
        height = math_floor(self.screen_height * DX.s.PN_info_panel_height),
    }
    self.info_panel_separator = LineWidget:new{
        background = KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.info_panel_width,
            h = Size.line.thick,
        }
    }
    height = height - self.info_panel:getSize().h - 2 * self.info_panel_separator:getSize().h - self.info_panel_nav_buttons_height
    --* for consumption in ((HtmlBox#generateScrollWidget)):
    self.swidth = self.info_panel_width
    self.sheight = height
end

--* Used in init & update to instantiate the Scroll*Widget that self.html_widget points to
--- @private
function HtmlBox:generateScrollWidget()
    --* this is the default, but some widgets can set the content_type to "text" for a specific tab; e.g. see ((XrayButtons#getItemViewerTabs)):
    if self.content_type == "text" then
        self.html_widget = ScrollTextWidget:new{
            text = self.html,
            face = self.content_face,
            line_height = KOR.registry.line_height or 0.95,
            alignment = "left",
            justified = false,
            dialog = self,
            width = self.swidth,
            height = self.sheight,
        }
        return
    end

    self.html_widget = ScrollHtmlWidget:new{
        html_body = self.html,
        css = self:getHtmlBoxCss(),
        default_font_size = Screen:scaleBySize(self.box_font_size),
        width = self.swidth,
        height = self.sheight,
        dialog = self,
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
            table.remove(HtmlBox.window_list, i)
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
    if not self.movable then
        return false
    end
    --* Let our MovableContainer handle swipe outside of definition
    return self.movable:onMovableSwipe(arg, ges)
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
    return self:onReadPrevItem()
end

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

function HtmlBox:onReadPrevItemWithShiftSpace()
    return self:onReadPrevItem()
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
        self.height = math.min(self.avail_height, math_floor(self.window_size.h))
        self.content_height = self.height - others_height
        local nb_lines = math_floor(self.content_height / self.content_line_height)
        self.content_height = nb_lines * self.content_line_height

    elseif self.is_fullscreen or self.window_size == "max" then
        self.height = self.avail_height
        self.content_height = self.height - others_height

    elseif self.window_size == "large" then
        self.content_height = math_floor(self.avail_height * 0.7)
        --* But we want it to fit to the lines that will show, to avoid
        --* any extra padding
        local nb_lines = Math.round(self.content_height / self.content_line_height)
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
        local nb_lines = Math.round(self.content_height / self.content_line_height)
        self.content_height = nb_lines * self.content_line_height
        self.height = self.content_height + others_height
    end
end

--- @private
function HtmlBox:computeLineHeight()
    --* Lookup word
    local word_font_face = "tfont"
    --* Ensure this word doesn't get smaller than its definition
    local word_font_size = math.max(22, self.box_font_size)
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

--- @private
function HtmlBox:generateSidePanel()

    local pn = self.page_navigator
    if not pn then
        return
    end

    --* self.page_navigator.current_item is set from the callback of a side_button in ((XraySidePanels#addSideButton)) and when marking the active button in ((XraySidePanels#markActiveSideButton)):
    --! the linked_items prop for the current_item were set in ((XraySidePanels#computeLinkedItems)):
    local has_linked_items =
        DX.sp.active_side_tab == 1
        and pn.current_item
        and (
            has_text(pn.current_item.linkwords)
            or
            has_items(pn.current_item.linked_items)
        )

    local generate_tab_activators = has_linked_items or DX.sp.active_side_tab == 2
    if generate_tab_activators then
        self.side_panel_tab_activators = DX.sp:generateSidePanelTabActivators(has_linked_items, self.side_buttons_width)
    end

    --* self.avail_height was computed in ((HtmlBox#computeAvailableHeight)):
    self.spacer_width = self.avail_height
        --* for top and bottom margin:
        - 2 * self.content_top_margin:getSize().h
        - self.side_buttons_table:getSize().h
        - (generate_tab_activators and self.side_panel_tab_activators:getSize().h or 0)
        - self.titlebar_height
        - 2 * self.side_buttons_table_separator:getSize().h

    local has_side_buttons = #self.side_buttons > 0
    local bottom_padding = VerticalSpan:new{
        width = self.spacer_width
    }
    self.side_panel = has_side_buttons and VerticalGroup:new{
        align = "left",
        --* these buttons (or a spacer in case of no buttons) were generated in ((HtmlBox#generateSidePanelButtons)):
        self.side_buttons_table,
        self.side_buttons_table_separator,
        bottom_padding,
        self.side_buttons_table_separator,
        self.side_panel_tab_activators,
    }
    or
    VerticalGroup:new{
        align = "left",
        self.side_buttons_table,
        bottom_padding,
        self.side_buttons_table_separator,
        self.side_panel_tab_activators,
    }
end

--- @private
function HtmlBox:generateSidePanelButtons()
    --* these side panel buttons were generated in ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markedItemRegister)):
    if not self.page_navigator or not self.side_buttons then
        return
    end

    self.side_buttons_table, self.side_buttons_table_separator = DX.sp:generateSidePanelButtons(self.side_buttons_width, self.screen_height)
end

--- @private
function HtmlBox:generateButtonTables()

    if self.no_buttons_row then
        return
    end

    --* Different sets of buttons whether fullpage or not
    local buttons = self.buttons_table or {
        {
            {
                text = "⇱",
                id = "top",
                vsync = true,
                callback = function()
                    self.html_widget:scrollToTop()
                end,
            },
            {
                text = "⇲",
                id = "bottom",
                vsync = true,
                callback = function()
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
    --* Bottom buttons get a bit less padding so their line separators
    --* reach out from the content to the borders a bit more
    local buttons_padding = Size.padding.default
    local buttons_width = self.inner_width - 2 * buttons_padding
    self.button_table = ButtonTable:new{
        width = buttons_width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
        button_font_weight = "normal",
    }
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
    if not self.page_navigator then
        self.content_widget = FrameContainer:new{
            padding = 0,
            padding_left = self.content_padding_h,
            padding_right = self.content_padding_h,
            margin = 0,
            bordersize = 0,
            self.html_widget,
        }
        return
    end

    local has_side_buttons = #self.side_buttons > 0
    if has_side_buttons then
        self.spacer_width = self.spacer_width - self.side_buttons_table_separator:getSize().h
    end
    self.content_widget = FrameContainer:new{
        padding = 0,
        padding_left = self.content_padding_h,
        padding_right = 0,
        margin = 0,
        bordersize = 0,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.content_width,
                h = self.content_height,
            },
            HorizontalGroup:new{
                align = "center",
                VerticalGroup:new{
                    align = "left",
                    self.html_widget,
                    self.info_panel_separator,
                    self.info_panel_nav_buttons,
                    self.info_panel_separator,
                    self.info_panel,
                },
                FrameContainer:new{
                    padding = 0,
                    margin = 0,
                    color = KOR.colors.line_separator,
                    bordersize = Size.line.medium,
                    self.side_panel,
                }
            }
        },
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
    if self.has_anchor_button then
        KOR.anchorbutton:increaseParentYposWith(
        self.titlebar_height
        + self.separator:getSize().h
        + self.content_top_margin:getSize().h
            + content_height)
    end

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
        if self.has_anchor_button then
            KOR.anchorbutton:increaseParentYposWith(self.tabs_table:getSize().h)
        end
    end

    --? I don't know why I need this hack on my Bigme phone:
    if self.is_fullscreen and DX.s.is_mobile_device then
        local spacer = VerticalSpan:new{ width = Size.padding.large }
        table.insert(elements, 2, spacer)
        if self.has_anchor_button then
            KOR.anchorbutton:increaseParentYposWith(spacer:getSize().h)
        end
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
    table.insert(frame, elements)
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

    self.box_font_size = DX.s.is_mobile_device and 26 or 18
    self.content_face = Font:getFace("x_smallinfofont", self.box_font_size)
    --self.content_face = Font:getFace("infofont", self.box_font_size)
    local font_size_alt = self.box_font_size - 4
    if font_size_alt < 8 then
        font_size_alt = 8
    end
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
        has_small_close_button_padding = true,
        align = self.title_alignment,
        show_parent = self,
        lang = self.lang_out,
        top_buttons_left = self.top_buttons_left,

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

return HtmlBox
