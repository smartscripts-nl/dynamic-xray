
local require = require

local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("extensions/modules/font")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local HistogramWidget = require("extensions/widgets/histogramwidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
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
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_text = has_text
local math = math
local math_floor = math.floor
local pairs = pairs
local table = table
local table_insert = table.insert

-- Inject scroll page method for ScrollHtmlWidget
ScrollHtmlWidget.scrollToPage = function(self, page_num)
    if page_num > self.htmlbox_widget.page_count then
        page_num = self.htmlbox_widget.page_count
    end
    self.htmlbox_widget:setPageNumber(page_num)
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()
    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
end

ScrollHtmlWidget.scrollToPage = function(self, page_num)
    if page_num > self.htmlbox_widget.page_count then
        page_num = self.htmlbox_widget.page_count
    end
    self.htmlbox_widget:setPageNumber(page_num)
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()
    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
end

--- @class NavigatorBox
--- @field page_navigator XrayPageNavigator
local NavigatorBox = InputContainer:extend{
    additional_key_events = nil,
    after_close_callback = nil,
    align = "center",
    chapter_occurrences_histogram = nil,
    chapters_count = nil,
    content_padding = nil,
    --* this is the default, but some widgets can set the content_type to "text" for a specific tab; e.g. see ((XrayButtons#getItemViewerTabs)):
    content_type = "html",
    current_chapter_index = nil,
    frame_content_fullscreen = nil,
    fullscreen = false,
    has_anchor_button = false,
    height = nil,
    histogram_bottom_line_height = 0,
    histogram_height = 0,
    html = nil,
    info_panel_buttons = nil,
    info_panel_text = nil,
    --* set by ((XrayPageNavigator#showNavigator)):
    key_events_module = nil,
    modal = true,
    next_item_callback = nil,
    occurrences_subject = nil,
    occurrences_per_chapter = nil,
    page_navigator = nil,
    prev_item_callback = nil,
    ratio_per_chapter = nil,
    screen_height = nil,
    screen_width = nil,
    side_buttons = nil,
    side_buttons_width = Screen:scaleBySize(135),
    side_panel_tab_activators = nil,
    title = nil,
    title_alignment = "left",
    titlebar = nil,
    titlebar_height = nil,
    top_buttons_left = nil,
    width = nil,
    --* Static class member, holds a ref to the currently opened widgets (in instantiation order).
    window_list = {},
    window_size = "fullscreen",
}

function NavigatorBox:init()
    self:initFrames()
    self:setModuleProps()
    self:initHotkeys()
    self:setWidth()
    --* height will be computed below, after we build top and bottom components, when we know how much height they are taking
    self:generateTitleBar()
    self:setPaddingAndSpacing()
    self:computeLineHeight()
    self:generateSidePanelButtons()
    self:setMargins()
    self:computeAvailableHeight()
    self:setSeparator()
    self:computeHeights()
    self:generateInfoButtons()
    self:generateChapterOccurrencesHistogram()
    self:generateInfoPanel()
    self:generateScrollWidget()
    self:generateSidePanel()
    self:addFrameToContentWidget()
    self:generateWidget()
    self:registerAnchorButtonYPos()
    self:finalizeWidget()
end

--- @private
function NavigatorBox:initFrames()
    self.frame_content_fullscreen = {
        radius = 0,
        bordersize = 0,
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
function NavigatorBox:initHotkeys()
    KOR.keyevents:addHotkeysForNavigatorBox(self, self.key_events_module)

    --! we need this call to restore hotkeys for the dialog every time a new tab gets activated (and therefore the dialog reloaded):
    --* examples of hotkeys configurators: ((KeyEvents#addHotkeysForXrayPageNavigator)) and ((KeyEvents#addHotkeysForXrayItemViewer)):
    if self.hotkeys_configurator then
        self.hotkeys_configurator()
    end
end

--- @private
function NavigatorBox:generateChapterOccurrencesHistogram()
    if not self.ratio_per_chapter or not DX.s.PN_show_chapter_hits_histogram then
        return
    end

    local bottom_line = LineWidget:new{
        background = KOR.colors.histogram_bar_light,
        dimen = Geom:new{
            w = self.info_panel_width,
            h = self.histogram_bottom_line_height,
        }
    }
    --* at about 50 items will give a nice distribution of not too wide histogram bars; if there are significantly less chapters, we reduce the width of the histogram, so the bars will not get too wide:
    local histogram_width = self.info_panel_width
    if self.chapters_count <= 45 then
        histogram_width = math_floor(self.chapters_count / 50 * histogram_width)
    end

    self.chapter_occurrences_histogram = CenterContainer:new{
        dimen = Geom:new{ w = self.info_panel_width, h = self.histogram_height + self.histogram_bottom_line_height },
        VerticalGroup:new{
            HistogramWidget:new{
                current_chapter_index = self.current_chapter_index,
                height = self.histogram_height,
                histogram_type = "chapterpages",
                nb_items = self.chapters_count,
                occurrences_per_chapter = self.occurrences_per_chapter,
                ratios = self.ratio_per_chapter,
                show_parent = self,
                width = histogram_width,
            },
            bottom_line,
        }
    }
end

function NavigatorBox:chapterTapCallback(n)
    return self:showChapterInformation(n)
end

function NavigatorBox:chapterHoldCallback(n)
    return self:showChapterInformation(n)
end

--- @private
function NavigatorBox:showChapterInformation(n)
    --* DX.vd.book_chapters was populated in ((XrayDataLoader#_populateViewsDataBookChapters)):
    local chapter_title = DX.vd.book_chapters[n] or "-"
    local page
    local display_page = ""
    if chapter_title ~= "-" then
        page = KOR.toc:getPageFromItemTitle(chapter_title)
        display_page = ", pagina " .. page
    end

    self.chapter_information = KOR.dialogs:niceAlert(self.occurrences_subject, T(_("Chapter %1/%2%3%4\"%5\"%6Occurrences: %7"), n, self.chapters_count, display_page, "\n", chapter_title, "\n\n", self.occurrences_per_chapter[n]), {
        buttons = {{
            {
                icon = "back",
                callback = function()
                    UIManager:close(self.chapter_information)
                end
            },
            {
                icon_text = {
                    icon = "goto-location",
                    text = " " .. _("navigator"),
                },
                callback = function()
                    if not self:handleBeforeGotoPageRequest(page) then
                        return
                    end
                    DX.sp:resetActiveSideButtons("NavigatorBox:showChapterInformation")
                    DX.pn.navigator_page_no = page
                    DX.pn:restoreNavigator()
                end
            },
            {
                icon_text = {
                    icon = "goto-location",
                    text = " " .. KOR.icons.arrow_bare .. " " .. _("book"),
                },
                callback = function()
                    if not self:handleBeforeGotoPageRequest(page) then
                        return
                    end
                    KOR.ui.link:addCurrentLocationToStack()
                    KOR.ui:handleEvent(Event:new("GotoPage", page))
                end
            },
        }}
    })
    return true
end

--- @private
function NavigatorBox:handleBeforeGotoPageRequest(page)
    UIManager:close(self.chapter_information)
    if not page then
        KOR.messages:notify(_("page number of chapter could not be determined"))
        return false
    end
    DX.pn:closePageNavigator()
    return true
end

--- @private
function NavigatorBox:generateInfoButtons()
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
function NavigatorBox:generateInfoPanel()

    local height = self.content_height
    --* info_text was generated in ((XrayPageNavigator#showNavigator)) > ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markItem)) > ((XrayPageNavigator#getItemInfoText)):
    local info_text = self.info_panel_text or " "
    local info_panel_height = math_floor(self.screen_height * DX.s.PN_info_panel_height)
    self.info_panel = ScrollTextWidget:new{
        text = info_text,
        face = Font:getFace("x_smallinfofont", DX.s.PN_panels_font_size or 14),
        line_height = 0.16,
        alignment = "left",
        justified = false,
        dialog = self,
        --* info_panel_width was computed in ((NavigatorBox#generateInfoButtons)):
        width = self.info_panel_width,
        height = info_panel_height,
    }
    self.info_panel_separator = LineWidget:new{
        background = KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.info_panel_width,
            h = Size.line.thick,
        }
    }
    self.info_panel_height = self.info_panel:getSize().h
    self.info_panel_separator_height = self.info_panel_separator:getSize().h
    height = height - self.info_panel_height - self.info_panel_separator_height - self.info_panel_nav_buttons_height
    --* for consumption in ((NavigatorBox#generateScrollWidget)):
    self.swidth = self.info_panel_width
    self.sheight = height
    if self.ratio_per_chapter then
        self.sheight = self.sheight - self.histogram_height - self.histogram_bottom_line_height
    end
end

--* Used in init & update to instantiate the Scroll*Widget that self.html_widget points to
--- @private
function NavigatorBox:generateScrollWidget()
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
        css = KOR.html:getHtmlBoxCss(self.css),
        default_font_size = Screen:scaleBySize(self.box_font_size),
        width = self.swidth,
        height = self.sheight,
        dialog = self,
    }
end

function NavigatorBox:onCloseWidget()

    if self.after_close_callback then
        self.after_close_callback()
    end
    self.additional_key_events = nil

    --* Drop our ref from the static class member
    for i = #NavigatorBox.window_list, 1, -1 do
        local window = NavigatorBox.window_list[i]
        --* We should only find a single match, but, better safe than sorry...
        if window == self then
            table.remove(NavigatorBox.window_list, i)
        end
    end

    --* NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
end

function NavigatorBox:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self.box_frame.dimen
    end)
    return true
end

function NavigatorBox:onClose()
    for menu in pairs(self.menu_opened) do
        UIManager:close(menu)
    end
    self.menu_opened = {}
    KOR.dialogs:unregisterWidget(self)
    UIManager:close(self)
    KOR.dialogs:closeAllOverlays()

    return true
end

function NavigatorBox:onReadNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    return true
end

function NavigatorBox:onReadPrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    return true
end

function NavigatorBox:onReadPrevItemWithShiftSpace()
    return self:onReadPrevItem()
end

--! this method and the next one are needed to jump to a next or previous page when pressing Space and Shift+Space on a (BT) keyboard:
function NavigatorBox:onForceNextItem()
    if not self.next_item_callback then
        return false
    end
    self:next_item_callback()
    return true
end

function NavigatorBox:onForcePrevItem()
    if not self.prev_item_callback then
        return false
    end
    self:prev_item_callback()
    return true
end

--- @private
function NavigatorBox:computeHeights()
    local buttons_height = self.button_table and self.button_table:getSize().h or 0
    local others_height =
        self.titlebar_height
        + Size.line.thick
        + 2 * self.content_top_margin:getSize().h
        + buttons_height

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

    -- #((set NavigatorBox dialog height))
    --* compare ((set NavigatorBox dialog width))
    self.height = self.avail_height
    self.content_height = self.height - others_height
end

--- @private
function NavigatorBox:computeLineHeight()
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
function NavigatorBox:generateSidePanel()

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

    --* self.avail_height was computed in ((NavigatorBox#computeAvailableHeight)):
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
        --* these buttons (or a spacer in case of no buttons) were generated in ((NavigatorBox#generateSidePanelButtons)):
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
function NavigatorBox:generateSidePanelButtons()
    --* these side panel buttons were generated in ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markedItemRegister)):
    if not self.page_navigator or not self.side_buttons then
        return
    end

    self.side_buttons_table, self.side_buttons_table_separator = DX.sp:generateSidePanelButtons(self.side_buttons_width, self.screen_height)
end

--- @private
function NavigatorBox:finalizeWidget()
    --* self.region was set in ((NavigatorBox#computeAvailableHeight)):
    self[1] = WidgetContainer:new{
        align = "top",
        dimen = self.region,
        self.box_frame,
    }

    --* we're a new window:
    table_insert(NavigatorBox.window_list, self)

    UIManager:setDirty(self, function()
        return "partial", self.box_frame.dimen
    end)

    --* make NavigatorBox widget closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
end

--- @private
function NavigatorBox:addFrameToContentWidget()
    local has_side_buttons = #self.side_buttons > 0
    if has_side_buttons then
        self.spacer_width = self.spacer_width - self.side_buttons_table_separator:getSize().h
    end
    local main_content = VerticalGroup:new{
        align = "left",
        self.html_widget,
        self.info_panel_separator,
        self.info_panel_nav_buttons,
        self.info_panel_separator,
        self.info_panel,
    }
    if DX.s.PN_show_chapter_hits_histogram then
        table_insert(main_content, self.chapter_occurrences_histogram)
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
                main_content,
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
function NavigatorBox:generateWidget()

    local frame = self.frame_content_fullscreen
    local content_height = self.content_widget:getSize().h
    local elements = VerticalGroup:new{
        self.titlebar,
        self.separator,
        self.content_top_margin,
        --* content
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = content_height,
            },
            self.content_widget,
        },
        self.content_bottom_margin,
    }

    --? I don't know why I need this hack on my Bigme phone:
    if self.is_fullscreen and DX.s.is_mobile_device then
        local spacer = VerticalSpan:new{ width = Size.padding.large }
        table.insert(elements, 2, spacer)
    end

    elements.align = "left"
    table.insert(frame, elements)
    self.box_frame = FrameContainer:new(frame)
end

--- @private
function NavigatorBox:registerAnchorButtonYPos()
    --? strange that we don't have to subtract self.info_panel_height here to get the correct result:
    --* but y pos computation is a bit wacky; compare comment in ((MovableContainer#moveToAnchor)):
    local scale_factor = DX.s.PN_popup_menu_y_offset + 8
    local computed_y_pos = self.screen_height - self.content_padding_v - self.info_panel_nav_buttons_height - self.histogram_height - self.histogram_bottom_line_height - Screen:scaleBySize(scale_factor)

    KOR.registry:set("anchor_button_y_pos", computed_y_pos)
end

--- @private
function NavigatorBox:computeAvailableHeight()
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
function NavigatorBox:setMargins()
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
function NavigatorBox:setModuleProps()
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
    self.window_size = "fullscreen"
    if self.tabs_table_buttons then
        self.title_alignment = "center"
    end
    KOR.tabnavigator:broadcastActivatedTab()

    if DX.s.PN_show_chapter_hits_histogram then
        self.histogram_height = Screen:scaleBySize(25)
        self.histogram_bottom_line_height = Size.line.thin
    end

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
    --* We'll also need to close any opened such menu when closing this NavigatorBox
    --* (needed if closing all DictQuickLookups via long-press on Close on the top one)
    self.menu_opened = {}
end

--- @private
function NavigatorBox:setPaddingAndSpacing()
    --* This padding and the resulting width apply to the content
    --* below the title:  lookup word and definition
    self.content_padding_h = self.content_padding or Size.padding.closebuttonpopupdialog
    self.content_padding_v = Size.padding.fullscreen --* added via VerticalSpan
    self.content_width = self.width - 2 * self.content_padding_h

    --* Spans between components
    self.content_top_margin = VerticalSpan:new{ width = self.content_padding_v }
    self.content_bottom_margin = VerticalSpan:new{ width = self.content_padding_v }
end

--- @private
function NavigatorBox:setSeparator()
    self.separator = LineWidget:new{
        background = self.tabs_table and KOR.colors.tabs_table_separators or KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
end

--- @private
function NavigatorBox:generateTitleBar()
    local config = {
        width = self.width,
        title = self.title,
        title_face = Font:getFace("smallinfofontbold"),
        --* NavigatorBox delivers the separator, so we don't want a separator in the titlebar:
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

        less_title_top_padding = false,
    }
    self.titlebar = TitleBar:new(config)
    self.titlebar_height = self.titlebar:getSize().h
end

--- @private
function NavigatorBox:setWidth()
    -- #((set NavigatorBox dialog width))
    --* compare ((set NavigatorBox dialog height))
    self.width = self.screen_width
end

return NavigatorBox
