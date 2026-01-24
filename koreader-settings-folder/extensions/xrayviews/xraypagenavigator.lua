
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local T = require("ffi/util").template

local DX = DX
local has_content = has_content
local has_text = has_text
local os_date = os.date
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

local count
--- @type XrayModel parent
local parent

--- @class XrayPageNavigator
local XrayPageNavigator = WidgetContainer:new{
    active_filter_name = nil,
    alias_indent = "   ",
    button_labels_injected = "",
    cached_export_info = nil,
    cached_hits_by_needle = {},
    cached_html_and_buttons_by_page_no = {},
    cached_items = {},
    current_item = nil,
    --* whole word name parts which may not be marked bold and trigger an item hit by themselves only; used in ((XrayPageNavigator#markItem)):
    forbidden_needle_parts = {
        ["De"] = true,
        ["La"] = true,
        ["Le"] = true,
    },
    initial_browsing_page = nil,
    key_events = {},
    max_line_length = 80,
    navigator_page_no = nil,
    movable_popup_menu = nil,
    non_active_layout = nil,
    non_filtered_items_marker_bold = "<strong>%1</strong>",
    non_filtered_items_marker_smallcaps = "<span style='font-variant: small-caps'>%1</span>",
    non_filtered_items_marker_smallcaps_italic = "<i style='font-variant: small-caps'>%1</i>",
    non_filtered_layouts = nil,
    page_navigator_filter_item = nil,
    popup_buttons = nil,
    popup_menu = nil,
    previous_filter_item = nil,
    previous_filter_name = nil,
    prev_marked_item = nil,
    return_to_current_item = nil,
    return_to_item_no = nil,
    return_to_page = nil,
    screen_width = nil,
    scroll_to_page = nil,
}

--- @param xray_model XrayModel
function XrayPageNavigator:initDataHandlers(xray_model)
    parent = xray_model
    --* the indices here must correspond to the settings in ((non_filtered_items_layout)):
    self.non_filtered_layouts = {
        ["small-caps"] = self.non_filtered_items_marker_smallcaps,
        ["small-caps-italic"] = self.non_filtered_items_marker_smallcaps_italic,
        ["bold"] = self.non_filtered_items_marker_bold,
    }
    self.screen_width = Screen:getWidth()
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
    self.initial_browsing_page = initial_browsing_page
    self:closePageNavigator()
    local html = self:loadDataForPage()

    local key_events_module = "XrayPageNavigator"
    self.page_navigator = KOR.dialogs:htmlBox({
        title = DX.m.current_title .. " - p." .. self.navigator_page_no,
        page_navigator = self,
        html = html,
        modal = false,
        info_panel_text = self:getInfoPanelText(),
        window_size = "fullscreen",
        has_anchor_button = true,
        key_events_module = key_events_module,
        no_buttons_row = true,
        top_buttons_left = DX.b:forPageNavigatorTopLeft(self),
        --* side_buttons were generated via ((XrayPageNavigator#markedItemRegister)) > ((XraySidePanels#addSideButton)):
        side_buttons = DX.sp.side_buttons,
        info_panel_buttons = DX.b:forPageNavigator(self),
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayPageNavigator(self, key_events_module)
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        next_item_callback = function()
            DX.p:toNextNavigatorPage()
        end,
        prev_item_callback = function()
            DX.p:toPrevNavigatorPage()
        end,
    })
end

--- @private
function XrayPageNavigator:markItemsFoundInPageHtml(html, navigator_page_no)
    DX.sp:resetSideButtons()
    self.button_labels_injected = ""
    self.navigator_page_no = navigator_page_no
    self.first_info_panel_text = nil

    local hits = DX.u:getXrayItemsFoundInText(html, "for_navigator")
    if not hits then
        return html
    end

    count = #hits
    self.prev_marked_item = nil
    self:setNonFilteredItemsLayout()
    for i = 1, count do
        html = self:markItemsInHtml(html, hits[i])
    end
    --* don't use cache if a filtered item was set (with its additional html):
    if not self.active_filter_name then
        self.cached_html_and_buttons_by_page_no[self.navigator_page_no] = {
            html = html,
            side_buttons = DX.sp.side_buttons,
        }
    end
    return html
end

--- @private
function XrayPageNavigator:markItemsInHtml(html, item)
    if item.name == self.prev_marked_item then
        return html
    end
    self.prev_marked_item = item.name
    self.is_filter_item = self.active_filter_name == item.name

    local subjects = {
        "name",
        "aliases",
        "short_names",
    }
    for l = 1, 3 do
        if has_text(item[subjects[l]]) then
            html = self:markItem(item, item[subjects[l]], html, l)
        end
    end
    return html
end

--- @private
function XrayPageNavigator:markItem(item, subject, html, loop_no)
    local parts, parts_count, uc, was_marked_for_full

    --* subject can be the name or the alias of an Xray item:
    subject = KOR.strings:trim(subject)
    html, was_marked_for_full = self:markFullNameHit(html, item, subject, loop_no)
    html = self:markAliasHit(html, item, subject)

    parts = KOR.strings:split(subject, ",? ")
    parts_count = #parts
    for i = 1, parts_count do
        uc = parts[i]
        --* len() > 2: for example don't mark "of" in "Consistorial Court of Discipline":
        if not self.forbidden_needle_parts[uc] and (uc:match("[A-Z]") or uc:len() > 2) then
            --* only from here to ((XrayPageNavigator#markedItemRegister)) side panel buttons are populated:
            html = self:markPartialHits(html, item, uc, i, was_marked_for_full)
        end
    end
    return html
end

--- @private
function XrayPageNavigator:markAliasHit(html, item)

    local alias_matchers = KOR.strings:getKeywordsForMatchingFrom(item.aliases)
    local needle
    count = #alias_matchers
    for i = 1, count do
        needle = DX.vd:getNeedleString(alias_matchers[i], "for_substitution")
        html = self:markNeedleInHtml(html, needle, item.aliases)
    end

    return html
end

--- @private
function XrayPageNavigator:markFullNameHit(html, item, subject, loop_no)
    if item.reliability_indicator ~= DX.tw.match_reliability_indicators.full_name then
        return html, false
    end

    local org_html = html
    local needle = DX.vd:getNeedleString(subject, "for_substitution")
    html = self:markNeedleInHtml(html, needle)
    if not needle:match("s$") then
        local subject_plural
        needle, subject_plural = DX.vd:getNeedleStringPlural(subject, "for_substitution")
        html = self:markNeedleInHtml(html, needle, subject_plural)
    end

    --* only replace swapped name for loop_no 1, because that's the full name:
    if loop_no > 1 then
        return html, org_html ~= html
    end

    local xray_name_swapped = KOR.strings:getNameSwapped(subject)
    if not xray_name_swapped then
        return html, org_html ~= html
    end
    needle = DX.vd:getNeedleString(xray_name_swapped)

    return self:markNeedleInHtml(html, needle, xray_name_swapped), org_html ~= html
end

--- @private
function XrayPageNavigator:markPartialHits(html, item, uc, i, was_marked_for_full)
    local is_term, lc, needle

    local is_lowercase_person = item.xray_type < 3 and not uc:match("[A-Z]")
    is_term = item.xray_type > 2
    if (is_term or is_lowercase_person) and i == 1 then
        uc = KOR.strings:ucfirst(uc)
    end

    needle = DX.vd:getNeedleString(uc)
    local uc_needle_plural = DX.vd:getNeedleStringPlural(uc)
    if was_marked_for_full or (html:match(needle) or html:match(uc_needle_plural)) then
        --* return html and add item to buttons:
        return self:markedItemRegister(item, html, uc)

    --* for terms we also try to find lowercase variants of their names:
    elseif is_term or is_lowercase_person then
        lc = KOR.strings:lower(uc)
        needle = DX.vd:getNeedleString(lc)
        if html:match(needle) then
            --* return html and add item to buttons:
            return self:markedItemRegister(item, html, lc)
        end
    end

    return html
end

--- @private
function XrayPageNavigator:setNonFilteredItemsLayout()
    self.non_active_layout =
        DX.s.PN_non_filtered_items_layout
        and
        self.non_filtered_layouts[DX.s.PN_non_filtered_items_layout]
        or
        self.non_filtered_items_marker_smallcaps_italic
end

--* this info will be consumed for the info panel in ((HtmlBox#generateScrollWidget)):
--- @private
function XrayPageNavigator:getItemInfoText(item)
    --* the reliability_indicators were added in ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)):
    local reliability_indicator = item.reliability_indicator and item.reliability_indicator .. " " or ""

    if self.cached_items[item.name] then
        return "\n" .. reliability_indicator .. self.cached_items[item.name]
    end

    self.max_line_length = DX.s.is_mobile_device and 40 or self.max_line_length

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
    if #info_table > 0 then
        info = info .. " \n" .. table_concat(info_table, "")
    end

    --* remove reliability_indicator_placeholder:
    self.cached_items[item.name] = info:gsub("\n  ", "", 1)

    return "\n" .. reliability_indicator .. self.cached_items[item.name]
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

--- @private
function XrayPageNavigator:markedItemRegister(item, html, word)
    local needle = DX.vd:getNeedleString(word, "for_substitution")
    html = self:markNeedleInHtml(html, needle)
    local info_text = self:getItemInfoText(item)
    if info_text and not self.first_info_panel_text then
        self.first_info_panel_text = info_text
        self.first_info_panel_item_name = item.name
    end
    if self.button_labels_injected:match(item.name) then
        return html
    end
    self.button_labels_injected = self.button_labels_injected .. " " .. item.name

    --* linked item buttons (when DX.sp.active_side_tab == 2) are added in ((XrayPageNavigator#loadDataForPage)) > ((XraySidePanels#computeLinkedItems)):
    if DX.sp.active_side_tab == 1 then
        DX.sp:addSideButton(item, info_text)
    end

    return html
end

--- @private
function XrayPageNavigator:markNeedleInHtml(html, needle, derived_name)
    if not self.active_filter_name and not derived_name then
        return html:gsub(needle, "<strong>%1</strong>")
    elseif not self.active_filter_name then
        return html:gsub(needle, "<strong>" .. derived_name .. "</strong>")
    end

    if derived_name then
        local non_active_layout = T(self.non_active_layout, derived_name)

        return self.is_filter_item and html:gsub(needle, "<strong>" .. derived_name .. "</strong>") or html:gsub(needle, non_active_layout)
    end

    return self.is_filter_item and html:gsub(needle, "<strong>%1</strong>") or html:gsub(needle, self.non_active_layout)
end

function XrayPageNavigator:resetFilter()
    self:setActiveScrollPage()
    self.page_navigator_filter_item = nil
    self.active_filter_name = nil
    DX.sp:resetActiveSideButtons("XrayPageNavigator:resetFilter")
    self:reloadPageNavigator()
    KOR.messages:notify(_("filter was reset") .. "...")
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
    --! needed for correct showing of linked items in side panel no 2 at end of ((XrayPageNavigator#loadDataForPage)):
    self:setCurrentItem(item)
    DX.sp:resetActiveSideButtons("XrayPageNavigator:setFilter", "dont_reset_active_side_buttons")

    self:reloadPageNavigator()
    KOR.messages:notify(T(_("filter set to %1") .. "...", item.name))
    return true
end

--- @private
function XrayPageNavigator:setCurrentItem(item)
    self.current_item = item
end

--- @private
function XrayPageNavigator:reloadPageNavigator()
    --* this might be the case when current method called after adding/updating an Xray item, from ((XrayController#resetDynamicXray)):
    if not self.page_navigator then
        return
    end
    self:showNavigator()
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

--- @private
function XrayPageNavigator:loadDataForPage()

    DX.sp:resetSideButtons()
    if self.current_item then
        DX.sp:computeLinkedItems()
        if DX.sp.active_side_tab == 2 and not self.active_filter_name then
            DX.sp:populateLinkedItemsPanel(self.current_item)
        end
    end

    --* get html and side_buttons from cache; these were stored in ((XrayPageNavigator#markItemsFoundInPageHtml)):
    if self.navigator_page_no and self.cached_html_and_buttons_by_page_no[self.navigator_page_no]

        --* don't use cache if a filtered item was set (with its additional html):
        and not self.active_filter_name
    then

        if DX.sp.active_side_tab == 1 then
            DX.sp:setSideButtons(self.cached_html_and_buttons_by_page_no[self.navigator_page_no].side_buttons)
            DX.sp:markActiveSideButton()
        end

        return self.cached_html_and_buttons_by_page_no[self.navigator_page_no].html
    end

    local html = DX.p:getPageHtmlForPage(self.navigator_page_no)
    --* self.cached_html_and_buttons_by_page_no will be updated here:
    --* side_buttons FOR SIDE PANEL TAB NO.1 de facto populated in ((XrayPageNavigator#markedItemRegister)) > ((XraySidePanels#addSideButton)):
    html = self:markItemsFoundInPageHtml(html, self.navigator_page_no)

    --? eilas, when a filter has been set, linked items for side panel no 2 have to be recomputed for some reason:
    if self.current_item and DX.sp.active_side_tab == 2 and self.active_filter_name then
        DX.sp:computeLinkedItems()
        DX.sp:populateLinkedItemsPanel(self.current_item)
    end

    DX.sp:markActiveSideButton()

    return html
end

--* called from ((XraySidePanels#populateLinkedItemsPanel)):
function XrayPageNavigator:formatInfoPanelText(info_panel_text)
    return info_panel_text
        --* apply some hacks to get a correct, uniform lay-out for the info of linked items in the bottom panel:
        :gsub(DX.vd.info_indent, DX.vd.alias_indent)
        :gsub(DX.vd.alias_indent, "", 1)
        :gsub("\n" .. DX.vd.alias_indent, ": ", 1)
        :gsub(DX.vd.alias_indent .. KOR.icons.graph_bare, "\n" .. DX.vd.alias_indent .. DX.vd.alias_indent .. KOR.icons.graph_bare, 1)
end

--- @private
function XrayPageNavigator:getInfoPanelText()
    if #DX.sp.side_buttons == 0 then
        return " "
    end

    local active_side_button = DX.sp.active_side_buttons[DX.sp.active_side_tab]

    --* the info panel texts per button were computed in ((XraySidePanels#addSideButton)):
    if has_text(DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]) then
        return DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]
    end

    if has_text(self.first_info_panel_text) and active_side_button == 1 then
        --* this text was generated for the first item via ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton))
        return self.first_info_panel_text
    end

    local side_button = DX.sp:getSideButton(active_side_button)

    --* xray_item.info_text for first button was generated in ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton)):
    --* info_text for each button generated via ((XrayPageNavigator#markedItemRegister)) > ((XrayPageNavigator#getItemInfoText)) > ((XraySidePanels#addSideButton)):
    return side_button and (side_button.info_text or self:getItemInfoText(side_button.xray_item)) or " "
end

function XrayPageNavigator:resetCache()
    self.cached_export_info = nil
    self.cached_html_and_buttons_by_page_no = {}
    self.cached_hits_by_needle = {}
    self.cached_items = {}
    DX.sp:resetActiveSideButtons("XrayPageNavigator:resetCache")
    self.current_item = nil
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
        self:showNavigator()
        self.return_to_page = nil
        local active_side_button = self.return_to_item_no or 1
        DX.sp:setActiveSideButton("XrayPageNavigator:returnToNavigator", active_side_button)
        --* re-open the last opened item; also set by ((XrayCallbacks#execEditCallback)):
        if self.return_to_item_no then
            self.current_item = self.return_to_current_item
            local side_button = DX.sp:getSideButton(self.return_to_item_no)
            if side_button then
                --* callback defined in ((XrayPageNavigator#markedItemRegister)):
                side_button.callback("force_return_to_item")
            end
            self.return_to_current_item = nil
            self.return_to_item_no = nil
        end

        return true
    end

    return false
end

--- @private
function XrayPageNavigator:showExportXrayItemsDialog()
    local top_buttons_left = DX.b:forExportItemsTopLeft()
    local title = parent.current_series and _("All Xray items: series mode") or _("All Xray items: book mode")

    KOR.dialogs:textBox({
        title = title,
        info = self.cached_export_info,
        info_icon_less = self.cached_export_info_icon_less,
        fullscreen = true,
        copy_icon_less_text = true,
        extra_button = KOR.buttoninfopopup:forXrayItemsExportToFile({
            callback = function()
                title = title:gsub(": ([^\n]+)", " in \"" .. parent.current_title .. "\" (%1)")
                local info = title .. "\n" .. _("List generated") .. ": " .. os_date("%Y-%m-%d") .. "\n\n" .. self.cached_export_info_icon_less
                KOR.files:filePutcontents(DataStorage:getDataDir() .. "/xray-items.txt", info)
                KOR.messages:notify(_("list exported to xray-items.txt..."))
            end,
        }),
        extra_button_position = 3,
        top_buttons_left = top_buttons_left,
    })
    KOR.screenhelpers:refreshScreen()
end

function XrayPageNavigator:setProp(prop, value)
    self[prop] = value
end


--- =============== HELP INFORMATION ================

function XrayPageNavigator:showHelpInformation()
    local screen_dims = Screen:getSize()

    KOR.dialogs:htmlBoxTabbed(1, {
        parent = parent,
        title = _("Page Navigator help information"),
        modal = true,
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(10),
        window_size = {
            h = screen_dims.h * 0.8,
            w = screen_dims.w * 0.7,
        },
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
        end,
        no_buttons_row = true,
        tabs = {
            {
                tab = _("Browsing"),
                html = _([[With the arrows in the right bottom corner you can browse through pages.<br>
    If you longpress the arrow buttons, PN will jump to the previous/next occurrence of the item shown in the bottom information panel.<br>
<br>
If you have a (BT) keyboard, you can also browse with Space and Shift+Space. If you reach the end of a page, the viewer will jump to the next page if you press Space. If you reach the top of a page, then Shift+Space will take you to the previous page.<br>
<br>
With the target icon you can jump back to the page on which you started navigating through the pages.<br>
<br>
With the XraySetting "PN_panels_font_size" (see cog icon in top left corner) you can change the font size of the side and bottom panels.]])
            },
            {
                tab = _("Filtering"),
                html = _([[Tap on items in the side panel to see explantions of those items.<br>
<br>
<strong>Filtered browsing</strong><br>
<br>
If you longpress on an item in the side panel, that will be used as a filter criterium (a filter icon appears on the right side of it). After this the Navigator will only jump to the next or previous page where the filtered item is mentioned.<br>
<br>
<strong>Resetting the filter</strong><br>
<br>
Longpress on the filtered item in the side panel.]])
            },
            {
                tab = _("Hotkeys"),
                html = self:getHotkeysInformation(),
            },
        },
    })
end


--- ============= HOTKEYS HELP INFORMATION ==============

--- @private
function XrayPageNavigator:getHotkeysInformation()
    if self.hotkeys_information then
        return self.hotkeys_information
    end
    self.hotkeys_information = _("For usage with (BT) keyboards:") .. [[<br>
                <br>
<strong>In Page Navigator</strong><br>
<br>
<table style='border-collapse: collapse'>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>E</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Edit Xray item shown in bottom info panel")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>I</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("show this Information dialog")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>J</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Page Navigator: Jump to page currently displayed in e-book")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+J</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("e-book: Jump to page currently displayed in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>L</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("show List of Items")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>N</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("jump to Next page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>P</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("jump to Previous page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>S</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("open Dynamic Xray Settings")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>V</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("View details of item currently displayed in bottom info panel")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>]] .. _("1 - 9") .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Show information of corresponding Xray item in side panel in bottom information panel")
            .. [[</td></tr>
    <tr><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]] .. _("space") .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("browse to next page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='white-space: pre; text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Shift+space")
            .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("browse to previous page in Page Navigator")
            .. [[</td></tr>
</table>
<br>
<strong>In this help dialog</strong><br>
<br>
<table>
    <tr><td style='white-space: pre; padding: 8px 22px; border: 1px solid #444444'>1, 2, 3</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Jump to the corresponding tab in the dialog")
            .. [[</td></tr>
</table>]]

    return self.hotkeys_information
end

return XrayPageNavigator
