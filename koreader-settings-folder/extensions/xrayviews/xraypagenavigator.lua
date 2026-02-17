
--* see ((Dynamic Xray: module info)) for more info

local require = require

local ButtonDialog = require("extensions/widgets/buttondialog")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local Size = require("extensions/modules/size")
local T = require("ffi/util").template

local DX = DX
local has_content = has_content
local has_text = has_text
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber
local unpack = unpack

local count
--- @type XrayModel parent
local parent

--- @class XrayPageNavigator
local XrayPageNavigator = WidgetContainer:new{
    active_filter_name = nil,
    alias_indent = "   ",
    cached_histogram_data = {},
    cached_hits_by_needle = {},
    cached_html_and_buttons_by_page_no = {},
    cached_items_info = {},
    current_item = nil,
    first_info_panel_text = nil,
    --* this prop will be set from ((NavigatorBox#generateInfoButtons)):
    info_panel_width = nil,
    initial_browsing_page = nil,
    key_events = {},
    max_line_length = DX.s.PN_info_panel_max_line_length,
    navigator_page_no = nil,
    movable_popup_menu = nil,
    navigation_tag = nil,
    navigator_page_html = nil,
    navigator_side_buttons = nil,
    page_navigator_filter_item = nil,
    --* we need this item for computing linked item buttons in side panel no 2:
    parent_item = nil,
    popup_buttons = nil,
    popup_menu = nil,
    popup_menu_coords = nil,
    return_to_current_item = nil,
    return_to_item_no = nil,
    return_to_page = nil,
    screen_width = nil,
    scroll_to_page = nil,
}

--- @param xray_model XrayModel
function XrayPageNavigator:initDataHandlers(xray_model)
    parent = xray_model
    self.screen_width = Screen:getWidth()
end

function XrayPageNavigator:restoreNavigator()
    self:showNavigator(self.initial_browsing_page)
end

function XrayPageNavigator:showNavigator(initial_browsing_page)

    if KOR.ui and KOR.ui.paging then
        KOR.messages:notify(_("the page navigator is only available in epubs etc..."))
        return
    end

    self.popup_buttons = self.popup_buttons or DX.b:forPageNavigatorPopupButtons(self)

    --! watch out: this is another var than navigator_page_no on the next line; if you make their names identical, then browsing to next or previous page is not possible anymore:
    --* initial_browsing_page is the page on which you started using the Navigator, while self.navigator_page_no is the actual page you are viewing in the Navigator after browsing to other pages:
    if not self.navigator_page_no or (initial_browsing_page and self.initial_browsing_page ~= initial_browsing_page) then
        self.navigator_page_no = DX.u:getCurrentPage()
        if not self.navigator_page_no then
            KOR.messages:notify("pagina kon niet worden bepaald")
            return
        end
    end
    self.initial_browsing_page = initial_browsing_page or DX.u:getCurrentPage()
    self:closePageNavigator()
    local html = self:loadDataForPage()
    local item = DX.sp:getCurrentTabItem()
    local chapters_count, ratio_per_chapter, occurrences_per_chapter
    --* if there were no Xray items found in the page, item will be nil:
    if item then
        chapters_count, ratio_per_chapter, occurrences_per_chapter = self:computeHistogramData(item)
    end

    local key_events_module = "XrayPageNavigator"
    self.page_navigator = KOR.dialogs:navigatorBox({
        chapters_count = chapters_count,
        current_chapter_index = KOR.toc:getTocIndexByPage(DX.u:getCurrentPage()),
        html = html,
        key_events_module = key_events_module,
        info_panel_buttons = DX.b:forPageNavigator(self),
        info_panel_text = DX.ip:getInfoPanelText(),
        modal = false,
        no_buttons_row = true,
        occurrences_per_chapter = occurrences_per_chapter,
        occurrences_subject = item and item.name,
        page_navigator = self,
        ratio_per_chapter = ratio_per_chapter,
        --* side_buttons were generated via ((XrayPages#markedItemRegister)) > ((XraySidePanels#addSideButton)):
        side_buttons = DX.sp.side_buttons,
        title = DX.m.current_title .. " - p." .. self.navigator_page_no,
        top_buttons_left = DX.b:forPageNavigatorTopLeft(self),
        window_size = "fullscreen",
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayPageNavigator(self, key_events_module)
        end,
        next_item_callback = function()
            DX.p:toNextNavigatorPage()
        end,
        prev_item_callback = function()
            DX.p:toPrevNavigatorPage()
        end,
    })

    --! have the popup menu available immediately, so we can compute its height in this method, for correct positioning above the anchor button:
    self:createPopupMenu()
end

--* calls ((XrayViewsData#generateChapterHitsData)) when no chapter_hits_data found for item:
--- @private
function XrayPageNavigator:computeHistogramData(item)

    local index = KOR.tables:normalizeTableIndex(item.name)
    local data = self.cached_histogram_data[index]
    local chapters_count, ratio_per_chapter, occurrences_per_chapter
    if data then
        chapters_count, ratio_per_chapter, occurrences_per_chapter = unpack(data)
        return chapters_count, ratio_per_chapter, occurrences_per_chapter
    end

    item = item or DX.sp:getCurrentTabItem()

    --* for best speed do this only for current / actual item in the info panel, and not for all items in the side panel:
    if item and not item.chapter_hits_data then
        item.chapter_hits_data = DX.vd:getChapterHitsData(item)
        DX.ds.storeChapterHitsData(item)
    end

    if not item or not item.chapter_hits_data then
        return
    end

    occurrences_per_chapter = item.chapter_hits_data
    chapters_count = #occurrences_per_chapter
    local max_value = KOR.tables:getMaxValue(occurrences_per_chapter)
    ratio_per_chapter = {}
    for i = 1, chapters_count do
        table_insert(ratio_per_chapter, occurrences_per_chapter[i] / max_value)
    end

    self.cached_histogram_data[index] = {
        chapters_count,
        ratio_per_chapter,
        occurrences_per_chapter
    }

    return chapters_count, ratio_per_chapter, occurrences_per_chapter
end

--* this info will be consumed for the info panel in ((NavigatorBox#generateScrollWidget)):
function XrayPageNavigator:getItemInfoText(item, for_info_panel)
    --* the reliability_indicators were added in ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)):
    local reliability_indicator = item.reliability_indicator and item.reliability_indicator .. " " or ""

    if self.cached_items_info[item.name] then
        --* if an item was cached, don't add linebreaks to the linebreak already present in the cached info:
        local prefix = for_info_panel and "" or "\n"
        local info = prefix .. reliability_indicator .. self.cached_items_info[item.name]
        if not info:match("^\n") then
            return "\n" .. info
        end
        return info:gsub("^\n\n", "\n")
    end

    local reliability_indicator_placeholder = item.reliability_indicator and "  " or ""
    self.sub_info_separator = ""

    local icon = DX.vd:getItemTypeIcon(item, "bare")
    --* alias_indent suffixed with 2 spaces, because of icon .. " ":
    local description = item.description
    description = KOR.strings:splitLinesToMaxLength(icon .. " " .. item.name .. ": " .. description, self.max_line_length, self.alias_indent .. "  ", nil, "dont_indent_first_line")
    local info = "\n" .. reliability_indicator_placeholder .. description .. "\n"

    local info_table = {}
    local indent = self:getItemInfoIndentation()

    local hits_info = self:itemInfoAddHits(item, indent)
    if has_text(hits_info) then
        table_insert(info_table, hits_info .. "\n")
    end
    --* for use with ((XrayPageNavigator#splitLinesToMaxLength)):
    self.alias_indent_corrected = DX.s.is_mobile_device and self.alias_indent .. self.alias_indent .. self.alias_indent .. self.alias_indent or self.alias_indent
    self:itemInfoAddPropInfo(item, "aliases", KOR.icons.xray_alias_bare, info_table, indent)
    self:itemInfoAddPropInfo(item, "linkwords", KOR.icons.xray_link_bare, info_table, indent)
    self:itemInfoAddPropInfo(item, "tags", KOR.icons.tag_open_bare, info_table, indent)
    if #info_table > 0 then
        info = info .. " \n" .. table_concat(info_table, "")
    end

    --* remove reliability_indicator_placeholder:
    self.cached_items_info[item.name] = info:gsub("\n  ", "", 1)

    if self.navigation_tag then
        --? for some reason we only need this correction if a navigation tag is active:
        reliability_indicator = reliability_indicator:gsub("^\n+", "")
        return "\n" .. reliability_indicator .. self.cached_items_info[item.name]
    end
    if not reliability_indicator:match("^\n") then
        reliability_indicator = "\n" .. reliability_indicator
    end

    return reliability_indicator .. self.cached_items_info[item.name]
end

--- @private
function XrayPageNavigator:getItemInfoIndentation()
    local indent = " "
    return indent:rep(DX.s.item_info_indent)
end

--- @private
function XrayPageNavigator:itemInfoAddHits(item, indent)
    --* when called from ((XrayViewsData#generateXrayItemInfo)) - so when generating an overview of all Xray items -, add no additional indentation:
    if not indent then
        indent = ""
    end
    local hits = ""
    local series_hits_added = false
    if parent.current_series and has_content(item.series_hits) then
        series_hits_added = true
        hits = KOR.icons.graph_bare .. " " .. _("series") .. " " .. tonumber(item.series_hits)
    end
    if has_content(item.book_hits) then
        local separator = series_hits_added and ", " or KOR.icons.graph_bare .. " "
        hits = hits .. separator .. _("book") .. " " .. tonumber(item.book_hits)
    end
    if has_text(hits) then
        return indent .. hits
    end
    return hits
end

--- @private
function XrayPageNavigator:itemInfoAddPropInfo(item, prop, icon, info_table, indent)
    if not item[prop] then
        return
    end

    local prop_info = self:splitLinesToMaxLength(item[prop], icon .. " " .. item[prop])
    if has_text(prop_info) then
        table_insert(info_table, indent .. prop_info .. "\n")
    end
end

--- @private
function XrayPageNavigator:splitLinesToMaxLength(prop, text)
    if not has_text(prop) then
        return ""
    end
    return KOR.strings:splitLinesToMaxLength(text, self.max_line_length - DX.s.item_info_indent, self.alias_indent_corrected, nil, "dont_indent_first_line")
end

function XrayPageNavigator:resetFilter()
    self:setActiveScrollPage()
    self.page_navigator_filter_item = nil
    self.active_filter_name = nil
    DX.sp:resetActiveSideButtons("XrayPageNavigator:resetFilter")
    self:reloadPageNavigator()
    KOR.messages:notify(_("filter was reset"))
    return true
end

function XrayPageNavigator:setFilter(item)
    --* when called from reset filter button in ((XrayButtons#forPageNavigatorTopLeft)):
    if not item then
        item = self.current_item
    end
    self:setActiveScrollPage()
    self.active_filter_name = item.name
    self.page_navigator_filter_item = item
    DX.sp:resetActiveSideButtons("XrayPageNavigator:setFilter", "dont_reset_active_side_buttons")

    self:reloadPageNavigator()
    KOR.messages:notify(T(_("filter set to %1"), item.name))
    return true
end

--- @private
function XrayPageNavigator:setCurrentItem(item)
    if not item then
        return
    end
    local id = item.id
    --! reference static items collection, to be more flexible after item updates:
    self.current_item = parent.items_by_id[id]
    --* we need this item for computing linked item buttons in side panel no 2:
    self.parent_item = KOR.tables:shallowCopy(item)
end

function XrayPageNavigator:reloadPageNavigator()
    --* this might be the case when current method called after adding/updating an Xray item, from ((XrayController#resetDynamicXray)):
    if not self.page_navigator then
        return
    end
    self:restoreNavigator()
    self:restoreActiveScrollPage()
end

--* this page will be consumed by ((XrayPageNavigator#reloadPageNavigator)) > ((XrayPageNavigator#restoreActiveScrollPage)):
--- @private
function XrayPageNavigator:setActiveScrollPage()
    self.scroll_to_page = self.page_navigator.html_widget.htmlbox_widget.page_number
end

--* the active scroll page was set in ((XrayPageNavigator#setActiveScrollPage)):
--- @private
function XrayPageNavigator:restoreActiveScrollPage()
    if self.scroll_to_page and self.scroll_to_page > 1 then
        for i = 1, self.scroll_to_page - 1 do
            self.page_navigator.html_widget:onScrollDown(i)
        end
    end
end

--* compare ((XrayPageNavigator#restoreActiveScrollPage)), where self.scroll_to_page is used to scroll to a specific scroll subpage; current method is called at the end of ((XrayPages#toPrevNavigatorPage)) when browsing with Shift+Space and then jumping to a previous page:
function XrayPageNavigator:scrollToBottom()
    local scroll_pages_count = self.page_navigator.html_widget.htmlbox_widget.page_count
    if scroll_pages_count then
        for i = 1, scroll_pages_count - 1 do
            self.page_navigator.html_widget:onScrollDown(i)
        end
    end
end

function XrayPageNavigator:getTaggedItems()
    if not self.navigation_tag then
        return nil
    end
    local ids = DX.m.tags_relational[self.navigation_tag]
    local tagged_items = {}
    count = #ids
    for i = 1, count do
        table_insert(tagged_items, DX.m.items_by_id[ids[i]])
    end
    return tagged_items
end

function XrayPageNavigator:betweenTagsNavigationActivate(tag)
    self.navigation_tag = tag
    self.current_item = nil
    --* disable regular filter when we are using tag groups to navigate:
    self.active_filter_name = nil
    self:reloadPageNavigator()
end

function XrayPageNavigator:betweenTagsNavigationDisable()
    self.navigation_tag = nil
    KOR.messages:notify(_("tag group navigation disabled"))
    self:reloadPageNavigator()
end

--- @private
function XrayPageNavigator:setButtonsAndReturnHtmlFromCache()
    --* get html and side_buttons from cache; these were stored in ((XrayPages#markItemsFoundInPageHtml)):
    if
        not self.navigator_page_no
        or not self.cached_html_and_buttons_by_page_no[self.navigator_page_no]
        --* don't use cache if a filtered item was set (with its additional html):
        or self.active_filter_name
        or self.navigation_tag
    then
        return
    end

    if DX.sp.active_side_tab == 1 then
        DX.sp:setSideButtons(self.cached_html_and_buttons_by_page_no[self.navigator_page_no].side_buttons)
        DX.sp:markActiveSideButton()
    end

    return self.cached_html_and_buttons_by_page_no[self.navigator_page_no].html
end

--- @private
function XrayPageNavigator:loadDataForPage()

    DX.sp:resetSideButtons()

    if self.navigation_tag and self.navigator_side_buttons and DX.sp.active_side_tab == 1 then
        DX.sp:setSideButtons(self.navigator_side_buttons)
        self:setCurrentItem(self.navigator_side_buttons[1][1].xray_item)
        self.navigator_side_buttons = nil
    end

    if self.current_item then
        DX.sp:computeLinkedItems()
        if DX.sp.active_side_tab == 2 and not self.active_filter_name then
            DX.sp:populateLinkedItemsPanel()
        end
    end

    local html = self:setButtonsAndReturnHtmlFromCache()
    if html then
        return html
    end

    --* when we initiated browsing between tagged items, via ((XrayPages#getPageHtmlForPage)) and ((XrayPages#getPageHtmlForPage)) PageNavigator.navigator_page_html can be populated with html containing the tagged items:
    html = self.navigation_tag and self.navigator_page_html or DX.p:getPageHtmlAndMarkItems(self.navigator_page_no)
    self.navigator_page_html = nil

    --? eilas, when an item filter or a tag filter has been set, linked items for side panel no 2 have to be recomputed for some reason:
    if DX.sp.active_side_tab == 2 and (self.active_filter_name or self.navigation_tag) then
        DX.sp:computeLinkedItems()
        DX.sp:populateLinkedItemsPanel()
    end

    DX.sp:markActiveSideButton()

    return html
end

function XrayPageNavigator:resetCache()
    self.cached_histogram_data = {}
    self.cached_html_and_buttons_by_page_no = {}
    self.cached_hits_by_needle = {}
    self.popup_menu_coords = nil
    KOR.registry:unset("popup_menu_coords")
end

function XrayPageNavigator:resetCachedInfoFor(item)
    self.cached_items_info[item.name] = nil
end

function XrayPageNavigator:closePageNavigator()
    if self.page_navigator then
        self:closePopupMenu()
        UIManager:close(self.page_navigator)
        self.page_navigator = nil
    end
end

--* the popup menu was opened in ((XrayCallbacks#execShowPopupButtonsCallback)):
function XrayPageNavigator:closePopupMenu()
    UIManager:close(self.movable_popup_menu)
    self.movable_popup_menu = nil
end

function XrayPageNavigator:resetReturnToProps()
    self.return_to_page = nil
    self.return_to_item_no = nil
    self.return_to_current_item = nil
end

function XrayPageNavigator:returnToNavigator()
    --* set by ((XrayCallbacks#execEditCallback)):
    if self.return_to_page then
        --* this is needed so we can return to the page we were looking at:
        self.navigator_page_no = self.return_to_page
        self:restoreNavigator()
        local active_side_button = self.return_to_item_no or 1
        DX.sp:setActiveSideButton("XrayPageNavigator:returnToNavigator", active_side_button)
        --* re-open the last opened item; also set by ((XrayCallbacks#execEditCallback)):
        if self.return_to_item_no then
            self.current_item = self.return_to_current_item
            local side_button = DX.sp:getSideButton(self.return_to_item_no)
            if side_button then
                --* callback defined in ((XrayPages#markedItemRegister)):
                side_button.callback("force_return_to_item")
            end
        end
        self:resetReturnToProps()

        return true
    end

    return false
end

--* this menu is created AFTER ((XrayPageNavigator#showNavigator)) has been called, so info_panel_width is available here:
--* positioning of the menu is done via ((NavigatorBox#init)) > ((NavigatorBox#registerPopupMenuCoords)) and ((XrayPageNavigator#showPopupMenu)):
--- @private
function XrayPageNavigator:createPopupMenu()
    if self.popup_menu then
        return
    end
    self.popup_menu = ButtonDialog:new{
        additional_key_events = KOR.keyevents:addHotkeysForXrayPageNavigatorPopupMenu(self),
        bordercolor = KOR.colors.line_separator,
        borderradius = Size.radius.default,
        --* these buttons were populated in ((XrayButtons#forPageNavigatorPopupButtons)):
        buttons = self.popup_buttons,
        forced_width = self.info_panel_width,
        tap_close_callback = function()
            self:closePopupMenu()
        end,
    }
end

--* called via hotkey "M" in ((KeyEvents#addHotkeysForXrayPageNavigator)) or button in ((XrayButtons#forPageNavigator)) > ((XrayCallbacks#execShowPopupButtonsCallback)):
function XrayPageNavigator:showPopupMenu()
    self.movable_popup_menu = MovableContainer:new{
        self.popup_menu,
        dimen = Screen:getSize(),
    }
    if not self.popup_menu_coords then
        --* these coords were set in ((NavigatorBox#registerPopupMenuCoords)):
        local coords = KOR.registry:get("popup_menu_coords")
        coords.y = coords.y - self.popup_menu.inner_height
        self.popup_menu_coords = coords
    end
    self.movable_popup_menu:movePopupMenuToAboveParent(self.popup_menu_coords)
    UIManager:show(self.movable_popup_menu)
end

function XrayPageNavigator:setProp(prop, value)
    self[prop] = value
end

return XrayPageNavigator
