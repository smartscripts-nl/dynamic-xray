--[[--
This extension is part of the Dynamic Xray plugin; it has all dialogs and forms (including their callbacks) which are used in XrayController and its other extensions.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayPageNavigator))
V = ((XrayUI)), ((XrayPageNavigator)), ((XrayTranslations)) and ((XrayTranslationsManager)), and ((XrayPageNavigator)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs, XrayPageNavigator and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayPageNavigator will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local DataStorage = require("datastorage")
local Event = require("ui/event")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local T = require("ffi/util").template

local DX = DX
local has_content = has_content
local has_items = has_items
local has_no_text = has_no_text
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
    active_item_marker = KOR.icons.active_tab_bare,
    active_side_buttons = { 1, 1 },
    active_side_tab = 1,
    alias_indent = "   ",
    button_labels_injected = "",
    cached_export_info = nil,
    cached_hits_by_needle = {},
    cached_html_and_buttons_by_page_no = {},
    cached_html_by_page_no = {},
    cached_items = {},
    current_item = nil,
    filtered_item_marker = KOR.icons.filter,
    --* whole word name parts which may not be marked bold and trigger an item hit by themselves only; used in ((XrayPageNavigator#markItem)):
    forbidden_needle_parts = {
        ["De"] = true,
        ["La"] = true,
        ["Le"] = true,
    },
    --* two sets, one for each side_panel:
    info_panel_texts = { {}, {} },
    initial_browsing_page = nil,
    key_events = {},
    max_line_length = 80,
    navigator_page_no = nil,
    non_active_layout = nil,
    non_filtered_items_marker_bold = "<strong>%1</strong>",
    non_filtered_items_marker_smallcaps = "<span style='font-variant: small-caps'>%1</span>",
    non_filtered_items_marker_smallcaps_italic = "<i style='font-variant: small-caps'>%1</i>",
    non_filtered_layouts = nil,
    page_navigator_filter_item = nil,
    prev_marked_item = nil,
    return_to_current_item = nil,
    return_to_item_no = nil,
    return_to_page = nil,
    scroll_to_page = nil,
    side_buttons = {},
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
end

function XrayPageNavigator:showNavigator(initial_browsing_page, info_panel_text)

    if KOR.ui and KOR.ui.paging then
        KOR.messages:notify(_("the page navigator is only available in epubs etc..."))
        return
    end

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

    local has_side_buttons = #self.side_buttons > 0
    if has_side_buttons then
        local active_side_button = self.active_side_buttons[self.active_side_tab]
        info_panel_text = self.info_panel_texts[self.active_side_tab][active_side_button]
    end
    if not info_panel_text and self.first_info_panel_text then
        --* this text was generated for the first item via ((XrayPageNavigator#markActiveSideButton)) > ((XrayPageNavigator#generateInfoTextForFirstSideButton))
        info_panel_text = self.first_info_panel_text
    elseif not info_panel_text then
        info_panel_text = " "
    end

    local key_events_module = "XrayPageNavigator"
    self.page_navigator = KOR.dialogs:htmlBox({
        title = DX.m.current_title .. " - p." .. self.navigator_page_no,
        page_navigator = self,
        html = html,
        modal = false,
        info_panel_text = self:getInfoPanelText(info_panel_text),
        window_size = "fullscreen",
        key_events_module = key_events_module,
        no_buttons_row = true,
        top_buttons_left = DX.b:forPageNavigatorTopLeft(self),
        --* side_buttons were generated via ((XrayPageNavigator#markedItemRegister)) > ((XrayPageNavigator#addSideButton)):
        side_buttons = self.side_buttons,
        info_panel_buttons = DX.b:forPageNavigator(self),
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayPageNavigator(self, key_events_module)
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        next_item_callback = function()
            self:toNextNavigatorPage()
        end,
        prev_item_callback = function()
            self:toPrevNavigatorPage()
        end,
    })
end

function XrayPageNavigator:toCurrentNavigatorPage()
    self:setActiveSideButton("XrayPageNavigator:toCurrentNavigatorPage", 1)
    self.navigator_page_no = self.initial_browsing_page
    self:showNavigator()
end

function XrayPageNavigator:toNextNavigatorPage()
    self:resetActiveSideButtons("XrayPageNavigator:toNextNavigatorPage")
    local first_info_panel_text
    --* navigation to next filtered item hit:
    if self.page_navigator_filter_item then
        local next_page = self:getNextPageHitForTerm()
        if not next_page or next_page == self.navigator_page_no then
            self:showNoNextPreviousOccurrenceMessage(1)
            return
        end
        self.navigator_page_no = next_page
        first_info_panel_text = self:getItemInfoText(self.page_navigator_filter_item)
        self:showNavigator(self.initial_browsing_page, first_info_panel_text)
        return
    end

    --* regular navigation:
    self.navigator_page_no = self.navigator_page_no + 1
    local epages = KOR.document:getPageCount()
    if self.navigator_page_no >= epages then
        self.navigator_page_no = epages
    self:showNoNextPreviousOccurrenceMessage(1)
        return
    end
    self:showNavigator(self.initial_browsing_page, first_info_panel_text)
end

function XrayPageNavigator:toPrevNavigatorPage()
    self:resetActiveSideButtons("XrayPageNavigator:toPrevNavigatorPage")
    local first_info_panel_text
    --* navigation to previous filtered item hit:
    if self.page_navigator_filter_item then
        local previous_page = self:getPreviousPageHitForTerm()
        if not previous_page or previous_page == self.navigator_page_no then
            self:showNoNextPreviousOccurrenceMessage(-1)
            return
        end
        self.navigator_page_no = previous_page
        first_info_panel_text = self:getItemInfoText(self.page_navigator_filter_item)
        self:showNavigator(self.initial_browsing_page, first_info_panel_text)
        return
    end

    --* regular navigation:
    self.navigator_page_no = self.navigator_page_no - 1
    if self.navigator_page_no < 1 then
        self.navigator_page_no = 1
    self:showNoNextPreviousOccurrenceMessage(-1)
        return
    end
    self:showNavigator(self.initial_browsing_page, first_info_panel_text)
end

--- @private
function XrayPageNavigator:showNoNextPreviousOccurrenceMessage(direction)
    local adjective = direction == 1 and "volgende" or "vorige"
    KOR.messages:notify(T("geen %1 vermelding van dit item meer gevonden..."), adjective)
end

--- @private
function XrayPageNavigator:getPageHtmlForPage(page_no)
    if self.cached_html_by_page_no[page_no] then
        return self.cached_html_by_page_no[page_no]
    end

    --- @type CreDocument document
    local document = KOR.document
    self.cached_html_by_page_no[page_no] = document:getPageHtml(page_no)
    return self.cached_html_by_page_no[page_no]
end

--- @private
function XrayPageNavigator:pageHasItemName(page_no)
    local html = self:getPageHtmlForPage(page_no)
    local hits = DX.u:getXrayItemsFoundInText(html, "for_navigator")
    if not hits then
        return false
    end
    local hcount = #hits
    for i = 1, hcount do
        if hits[i].name == self.active_filter_name then
            return true
        end
    end
    return false
end

--- @private
function XrayPageNavigator:markItemsFoundInPageHtml(html, navigator_page_no)
    self.side_buttons = {}
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
            side_buttons = self.side_buttons,
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
            --* only here side panel buttons are populated:
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

    self.alias_indent_corrected = DX.s.is_mobile_device and self.alias_indent .. self.alias_indent .. self.alias_indent .. self.alias_indent or self.alias_indent
    self.max_line_length = DX.s.is_mobile_device and 40 or self.max_line_length

    local reliability_indicator_placeholder = item.reliability_indicator and "  " or ""
    self.sub_info_separator = ""

    local description = item.description
    description = KOR.strings:splitLinesToMaxLength(item.name .. ": " .. description, self.max_line_length, self.alias_indent, nil, "dont_indent_first_line")
    local info = "\n" .. reliability_indicator_placeholder .. description .. "\n"

    info = self:itemInfoAddHits(info, item)

    self.sub_info_separator = "     "
    if item.aliases then
        info = self:splitLinesToMaxLength(info, item.aliases, KOR.icons.xray_alias_bare .. " " .. item.aliases)
    end
    if item.linkwords then
        info = self:splitLinesToMaxLength(info, item.linkwords, KOR.icons.xray_link_bare .. " " .. item.linkwords)
    end

    --* remove reliability_indicator_placeholder:
    self.cached_items[item.name] = info:gsub("\n  ", "", 1)

    return "\n" .. reliability_indicator .. self.cached_items[item.name]
end

--- @private
function XrayPageNavigator:itemInfoAddHits(info, item)
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
    --* when called from list of all items in TextViewer > ((XrayViewsData#generateXrayItemInfo)):
    if info == "" then
        return hits
    end
    if has_text(hits) then
        return info .. "\n" .. DX.vd.info_indent .. hits
    end

    return info
end

--- @private
function XrayPageNavigator:splitLinesToMaxLength(info, prop, text)
    if not has_text(prop) then
        return info
    end
    local separator = self.sub_info_separator ~= "" and self.sub_info_separator or ""
    text = KOR.strings:splitLinesToMaxLength(separator .. text, self.max_line_length, self.alias_indent_corrected, nil, "dont_indent_first_line")
    if separator ~= "" then
        separator = "\n"
    end
    return info .. separator .. text
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

    --* linked item buttons (when self.active_side_tab == 2) are added in ((XrayPageNavigator#loadDataForPage)) > ((XrayPageNavigator#populateLinkedItemButtons)):
    if self.active_side_tab == 1 then
        self:addSideButton(item, info_text)
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

function XrayPageNavigator:resetFilter(item, info_text)
    --* when called from filter button in ((XrayButtons#forPageNavigatorTopLeft)):
    if not item then
        item = self.current_item
        info_text = self.info_panel_text
    end
    self:setActiveScrollPage()
    self.page_navigator_filter_item = nil
    self.active_filter_name = nil
    self:resetActiveSideButtons("XrayPageNavigator:resetFilter")
    self:reloadPageNavigator(info_text)
    KOR.messages:notify(_("filter was reset") .. "...")
    return true
end

function XrayPageNavigator:setFilter(item, info_text)
    --* when called from reset filter button in ((XrayButtons#forPageNavigatorTopLeft)):
    if not item then
        item = self.current_item
        info_text = self.info_panel_text
    end
    self:setActiveScrollPage()
    self.active_filter_name = item.name
    self.page_navigator_filter_item = item
    self:resetActiveSideButtons("XrayPageNavigator:setFilter")
    self:reloadPageNavigator(info_text)
    KOR.messages:notify(T(_("filter set to %1") .. "...", item.name))
    return true
end

--- @private
function XrayPageNavigator:setCurrentItem(item)
    self.current_item = item
end

--- @private
function XrayPageNavigator:reloadPageNavigator(info_text)
    --* this might be the case when current method called after adding/updating an Xray item, from ((XrayController#resetDynamicXray)):
    if not self.page_navigator then
        return
    end
    self:showNavigator(self.initial_browsing_page, info_text)
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
function XrayPageNavigator:verifyPageHit(condition, page_no)
    if
        condition
        and
        --! verify that the filter item is present in this page; if not, then it must be another item of which the name partly(!) matches with the name of the filter item:
        --* e.g.: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
        self:pageHasItemName(page_no, self.active_filter_name)
    then
        return page_no
    end
end

--- @private
function XrayPageNavigator:resultsPageGreaterThan(results, current_page, next_page)
    if not has_items(results) then
        return
    end
    count = #results
    local last_occurrence = KOR.document:getPageFromXPointer(results[count].start)
    if current_page == last_occurrence then
        return
    end
    local page_no, valid_next_page
    for i = 1, count do
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        valid_next_page = self:verifyPageHit(page_no > current_page and (not next_page or page_no < next_page), page_no)
        if valid_next_page then
            return valid_next_page
        end
    end
end

--- @private
function XrayPageNavigator:resultsPageSmallerThan(results, current_page, prev_page)
    if not has_items(results) then
        return
    end
    count = #results
    local first_occurrence = KOR.document:getPageFromXPointer(results[1].start)
    if current_page == first_occurrence then
        return
    end
    local page_no, valid_prev_page
    for i = count, 1, -1 do
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        valid_prev_page = self:verifyPageHit(page_no < current_page and (not prev_page or page_no > prev_page), page_no)
        if valid_prev_page then
            return valid_prev_page
        end
    end
end

--- @private
function XrayPageNavigator:getNextPageHitForTerm()
    local item = self.page_navigator_filter_item
    local current_page = self.navigator_page_no
    --- @type CreDocument document
    local document = KOR.document
    local results, needle, case_insensitive
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(item)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = self.cached_hits_by_needle[needle] or document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
    self.cached_hits_by_needle[needle] = results
    local next_page = self:resultsPageGreaterThan(results, current_page)

    if has_no_text(item.aliases) then
        return next_page
    end

    local aliases = parent:splitByCommaOrSpace(item.aliases)
    local aliases_count = #aliases
    for a = 1, aliases_count do
        results = document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
        next_page = self:resultsPageGreaterThan(results, current_page, next_page)
    end
    return next_page
end

--- @private
function XrayPageNavigator:getPreviousPageHitForTerm()
    local item = self.page_navigator_filter_item
    local current_page = self.navigator_page_no
    --- @type CreDocument document
    local document = KOR.document
    local results, needle, case_insensitive
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(item)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = self.cached_hits_by_needle[needle] or document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
    self.cached_hits_by_needle[needle] = results
    local prev_page = self:resultsPageSmallerThan(results, current_page)

    if has_no_text(item.aliases) then
        return prev_page
    end

    local aliases = parent:splitByCommaOrSpace(item.aliases)
    local aliases_count = #aliases
    for a = 1, aliases_count do
        results = document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
        prev_page = self:resultsPageSmallerThan(results, current_page, prev_page)
    end
    return prev_page
end

--- @private
function XrayPageNavigator:loadDataForPage()

    self.side_buttons = {}
    --! first condition is essential to prevent getting wrong info panel texts assigned to the buttons in the main side tab:
    if self.active_side_tab == 2 and self.current_item then
        self:populateLinkedItemButtons()
    end

    --* get html and side_buttons from cache; these were stored in ((XrayPageNavigator#markItemsFoundInPageHtml)):
    if self.navigator_page_no and self.cached_html_and_buttons_by_page_no[self.navigator_page_no]

        --* don't use cache if a filtered item was set (with its additional html):
        and not self.active_filter_name
    then

        if self.active_side_tab == 1 then
            self.side_buttons = self.cached_html_and_buttons_by_page_no[self.navigator_page_no].side_buttons
            self:markActiveSideButton()
        end

        return self.cached_html_and_buttons_by_page_no[self.navigator_page_no].html
    end

    local html = self:getPageHtmlForPage(self.navigator_page_no)
    --* self.cached_html_and_buttons_by_page_no will be updated here:
    --* side_buttons de facto populated in ((XrayPageNavigator#markedItemRegister)) > ((XrayPageNavigator#addSideButton)):
    html = self:markItemsFoundInPageHtml(html, self.navigator_page_no)
    self:markActiveSideButton()

    return html
end

--* regular main item buttons (self.active_side_tab == 1) were added in ((XrayPageNavigator#markedItemRegister)):
--- @private
function XrayPageNavigator:populateLinkedItemButtons()
    local linked_items_were_determined = self.current_item.linked_items

    --* the linked_items prop of self.current_item will be used in ((HtmlBox#generateSidePanel)) to determine whether the side panel tab activator buttons should be shown...
    --! shallowCopy used twice in this method, to ensure that table_insert(linked_items... farther below doesn't modify this prop (and so would make it contain ever more duplicated items)!
    local linked_items = linked_items_were_determined and KOR.tables:shallowCopy(self.current_item.linked_items) or DX.vd:getLinkedItems(self.current_item)
    if not linked_items_were_determined then
        self.current_item.linked_items = KOR.tables:shallowCopy(linked_items)
    end

    table_insert(linked_items, 1, self.current_item)
    count = #linked_items
    local info_panel_text
    for i = 1, count do
        info_panel_text = DX.vd:generateXrayItemInfo(linked_items, nil, i, linked_items[i].name, 2, "for_all_items_list")
        if i == 1 then
            self.first_info_panel_text = info_panel_text
        end
        --* apply some hacks to get a correct, uniform lay-out for the info in the bottom panel (apparently we need this for side panel no 2, but not for side panel 1):
        info_panel_text = self:formatInfoPanelText(info_panel_text)
        self:addSideButton(linked_items[i], info_panel_text)
    end
end

--* called from ((XrayPageNavigator#populateLinkedItemButtons)):
--- @private
function XrayPageNavigator:formatInfoPanelText(info_panel_text)
    return info_panel_text
        --* apply some hacks to get a correct, uniform lay-out for the info of linked items in the bottom panel:
        :gsub(DX.vd.info_indent, DX.vd.alias_indent)
        :gsub(DX.vd.alias_indent, "", 1)
        :gsub("\n" .. DX.vd.alias_indent, ": ", 1)
        :gsub(DX.vd.alias_indent .. KOR.icons.graph_bare, "\n" .. DX.vd.alias_indent .. DX.vd.alias_indent .. KOR.icons.graph_bare, 1)
end

--- @private
function XrayPageNavigator:addSideButton(item, info_text)
    --* active marking of buttons will be done in ((XrayPageNavigator#markActiveSideButton))
    local label = item.name
    local button_index = #self.side_buttons + 1
    if button_index < 10 then
        label = button_index .. ". " .. label
    end
    local index = #self.side_buttons + 1
    if self.active_side_buttons[self.active_side_tab] == index then
        label = self.active_item_marker .. label
    end
    table_insert(self.info_panel_texts[self.active_side_tab], info_text)
    table_insert(self.side_buttons, {{
      text = label,
      xray_item = item,
      index = index,
      align = "left",
      --* force_item will be set when we return to the Page Navigator from ((XrayPageNavigator#returnToNavigator)):
      callback = function(force_return_to_item)
          self:setActiveSideButton("XrayPageNavigator:addSideButton button callback", index)
          --* in side tab no 2 taps on the current item must display info:
          if self.active_side_tab ~= 2 and not force_return_to_item and self.current_item and item.name == self.current_item.name then
              return true
          end
          --! only items in side panel no 1 (main items) may modify self.current_item:
          if self.active_side_tab == 1 then
                self:setCurrentItem(item)
          end
          self:setActiveScrollPage()
          self:reloadPageNavigator(info_text)
          return true
      end,

      --* for marking or unmarking an item as filter criterium:
      hold_callback = function()
          if self.active_filter_name == item.name then
              return self:resetFilter(item, info_text)
          end
          return self:setFilter(item, info_text)
      end,
  }})
end

--* these side panel buttons were generated in ((XrayPageNavigator#markItemsFoundInPageHtml)) > ((XrayPageNavigator#markedItemRegister)):
function XrayPageNavigator:markActiveSideButton()
    count = #self.side_buttons
    local button
    self.current_item = nil

    --* these are rows with one button each:
    for r = 1, count do
        button = self:getSideButton(r)
        button.text = button.text
            :gsub(self.active_item_marker, "")
            :gsub(self.filtered_item_marker, "")
        if button.xray_item.name == self.active_filter_name then
            button.text = self.filtered_item_marker .. button.text
        end
        if r == self.active_side_buttons[self.active_side_tab] then
            button.text = self.active_item_marker .. button.text
            --! only items in side panel no 1 (main items) may modify self.current_item:
            if self.active_side_tab == 1 then
                self:setCurrentItem(button.xray_item)
            end
        end
        if r == 1 then
            self:generateInfoTextForFirstSideButton(button)
        end
    end
end

function XrayPageNavigator:getSideButton(i)
    return self.side_buttons[i] and self.side_buttons[i][1]
end

--- @private
function XrayPageNavigator:getSideButtonIndexByItem(item)
    local bcount = #self.side_buttons
    for i = 1, bcount do
        if item.name == self.side_buttons[i][1].xray_item.name then
            return self.side_buttons[i][1].index
        end
    end
end

--- @private
function XrayPageNavigator:generateInfoTextForFirstSideButton(button)
    --* the xray_item prop of these buttons was set in ((XrayPageNavigator#markedItemRegister)):
    local info_text = self:getItemInfoText(button.xray_item)
    button.xray_item.info_text = info_text
    self.first_info_panel_text = info_text
    self.first_info_panel_item_name = button.xray_item.name
end

function XrayPageNavigator:getCurrentTabItem()
    if self.active_side_tab == 1 then
        return self.current_item
    end

    local button_index = self.active_side_buttons[2]
    return self.side_buttons[button_index][1].xray_item
end

--- @private
function XrayPageNavigator:getInfoPanelText(info_panel_text)
    if info_panel_text then
        return info_panel_text
    end

    local side_button = self:getSideButton(1)
    --* xray_item.info_text for first button was generated in ((XrayPageNavigator#markActiveSideButton)) > ((XrayPageNavigator#generateInfoTextForFirstSideButton)):
    --* info_text for each button generated via ((XrayPageNavigator#markedItemRegister)) > ((XrayPageNavigator#getItemInfoText)) > ((XrayPageNavigator#addSideButton)):
    return side_button and side_button.info_text or ""
end

function XrayPageNavigator:resetCache()
    self.cached_export_info = nil
    self.cached_html_and_buttons_by_page_no = {}
    self.cached_hits_by_needle = {}
    self.cached_html_by_page_no = {}
    self.cached_items = {}
    self.current_item = nil
end

function XrayPageNavigator:closePageNavigator()
    if self.page_navigator then
        UIManager:close(self.page_navigator)
        self.page_navigator = nil
    end
end

function XrayPageNavigator:resetReturnToProps()
    self.return_to_page = nil
    self.return_to_item_no = nil
    self.return_to_current_item = nil
end

function XrayPageNavigator:returnToNavigator()
    --* set by ((XrayPageNavigator#execEditCallback)):
    if self.return_to_page then
        --* this is needed so we can return to the page we were looking at:
        self.initial_browsing_page = self.return_to_page
        self:showNavigator(self.return_to_page);
        self.return_to_page = nil
        local active_side_button = self.return_to_item_no or 1
        self:setActiveSideButton("XrayPageNavigator:returnToNavigator", active_side_button)
        --* re-open the last opened item; also set by ((XrayPageNavigator#execEditCallback)):
        if self.return_to_item_no then
            self.current_item = self.return_to_current_item
            local side_button = self:getSideButton(self.return_to_item_no)
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

--* compare ((XrayPageNavigator#setActiveSideButton)):
--- @private
function XrayPageNavigator:resetActiveSideButtons(context)

    self.active_side_tab = 1
    self.active_side_buttons = { 1, 1 }
    self.info_panel_texts = { {}, {} }

    --* context was given here only for debugging:
    self.garbage = context
end

--* compare ((XrayPageNavigator#resetActiveSideButtons)):
--- @private
function XrayPageNavigator:setActiveSideButton(context, active_side_button)
    if active_side_button and self.active_side_tab == 1 then
        self.active_side_buttons = { active_side_button, 1 }
        self.info_panel_texts[2] = {}
    elseif active_side_button then
        self.active_side_buttons = { self.active_side_buttons[1], active_side_button }
    end

    --* context was given here only for debugging:
    self.garbage = context
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


--- =========== (KEYBOARD) EVENT HANDLERS ============
--* for calling through hotkeys - ((KeyEvents#addHotkeysForXrayPageNavigator)) - and as callbacks for usage in Xray buttons


--- @param iparent XrayPageNavigator
function XrayPageNavigator:execEditCallback(iparent)
    local current_tab_item = iparent:getCurrentTabItem()
    if not current_tab_item then
        KOR.messages:notify(_("there was no item to be edited..."))
        return true
    end
    DX.fd:setFormItemId(current_tab_item.id)
    iparent:closePageNavigator()
    DX.c:setProp("return_to_viewer", false)
    --* to to be consumed in ((XrayButtons#forItemEditor)) > ((XrayPageNavigator#returnToNavigator)):
    iparent:setProp("return_to_page", iparent.navigator_page_no)
    if #iparent.side_buttons > 0 then
        iparent:setProp("return_to_item_no", iparent.active_side_button)
        iparent:setProp("return_to_current_item", iparent.current_item)
    end
    DX.c:onShowEditItemForm(current_tab_item, false, 1)
    return true
end

--* compare ((XrayDialogs#showUiPageInfo))
function XrayPageNavigator:execExportXrayItemsCallback()

    if self.cached_export_info then
        self:showExportXrayItemsDialog()
        return true
    end

    local items = DX.vd.items
    if not items then
        return true
    end
    local paragraphs = {}
    local paragraphs_icon_less = {}
    local paragraph, paragraph_icon_less
    count = #items
    for i = 1, count do
        paragraph, paragraph_icon_less = DX.vd:generateXrayItemInfo(items, nil, i, items[i].name, i, "for_all_items_list")
        if i == 1 then
            paragraph = paragraph:gsub(DX.vd.info_indent, "", 1)
            paragraph_icon_less = paragraph_icon_less:gsub(DX.vd.info_indent, "", 1)
        end
        table_insert(paragraphs, paragraph)
        table_insert(paragraphs_icon_less, paragraph_icon_less)
    end
    self.cached_export_info = table_concat(paragraphs, "")
    self.cached_export_info_icon_less = table_concat(paragraphs_icon_less, "")

    self:showExportXrayItemsDialog()
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execGotoNextPageCallback(iparent)
    iparent:toNextNavigatorPage()
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execGotoPrevPageCallback(iparent)
    iparent:toPrevNavigatorPage()
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execJumpToCurrentPageInNavigatorCallback(iparent)
    KOR.messages:notify(_("jumped back to start page..."))
    iparent:toCurrentNavigatorPage()
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execJumpToCurrentPageInEbookCallback(iparent)
    iparent:closePageNavigator()
    KOR.ui.link:addCurrentLocationToStack()
    KOR.ui:handleEvent(Event:new("GotoPage", iparent.navigator_page_no))
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execSettingsCallback(iparent)
    iparent:closePageNavigator()
    DX.s.showSettingsManager()
    return true
end

function XrayPageNavigator:execShowHelpInfoCallback()
    self:showHelpInformation()
    return true
end

function XrayPageNavigator:execShowListCallback()
    DX.c:onShowList()
    return true
end

function XrayPageNavigator:execShowItemOccurrencesCallback()
    local current_tab_item = self:getCurrentTabItem()
    if not current_tab_item then
        return true
    end

    if not current_tab_item then
        KOR.messages:notify(_("no item to display found on this page..."))
        return true
    end
    DX.c:viewItemHits(current_tab_item.name)
    return true
end

--! needed for ((XrayPageNavigator#execShowPageBrowserCallback)) > show PageBrowserWidget > tap on a page > ((PageBrowserWidget#onClose)) > call laucher:onClose():
function XrayPageNavigator:onClose()
    self:closePageNavigator()
    local initial_page = self.initial_browsing_page

    --* use PageBrowserWidget taps to navigate in Page Navigator, but reset location in reader to previous page:
    UIManager:nextTick(function()
        self.navigator_page_no = DX.u:getCurrentPage()
        --* undo page jump in the e-reader:
        KOR.link:onGoBackLink()
        self:showNavigator(initial_page)
    end)
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execShowPageBrowserCallback(iparent)
    if not iparent.navigator_page_no then
        return true
    end
    local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    self.page_browser = PageBrowserWidget:new{
        --* via this prop PageBrowserWidget can call ((XrayPageNavigator#onClose)):
        launcher = self,
        ui = KOR.ui,
        focus_page = iparent.navigator_page_no,
        cur_page = iparent.navigator_page_no,
    }
    UIManager:show(self.page_browser)
    self.page_browser:update()
    return true
end

--- @param iparent XrayPageNavigator
function XrayPageNavigator:execViewItemCallback(iparent)
    local current_tab_item = iparent:getCurrentTabItem()
    if not current_tab_item then
        return true
    end
    DX.d:showItemViewer(current_tab_item)
    return true
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
