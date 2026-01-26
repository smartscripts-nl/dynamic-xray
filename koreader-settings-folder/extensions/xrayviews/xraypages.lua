
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_no_text = has_no_text
local has_text = has_text
local math_ceil = math.ceil
local tonumber = tonumber

local count

--- @class XrayPages
local XrayPages = WidgetContainer:new{
    browsing_page_current = nil,
    browsing_page_new = nil,
    button_labels_injected = "",
    cached_html_by_page_no = {},
    --* whole word name parts which may not be marked bold and trigger an item hit by themselves only; used in ((XrayPages#markItem)):
    forbidden_needle_parts = {
        ["De"] = true,
        ["La"] = true,
        ["Le"] = true,
    },
    is_filter_item = false,
    non_active_layout = nil,
    non_filtered_items_marker_bold = "<strong>%1</strong>",
    non_filtered_items_marker_smallcaps = "<span style='font-variant: small-caps'>%1</span>",
    non_filtered_items_marker_smallcaps_italic = "<i style='font-variant: small-caps'>%1</i>",
    non_filtered_layouts = nil,
    previous_filter_item = nil,
    previous_filter_name = nil,
    prev_marked_item = nil,
    search_also_in_opposite_direction = false,
}

function XrayPages:getNextPageFrom(results)
    if not has_items(results) then
        return
    end
    count = #results
    local last_occurrence = KOR.document:getPageFromXPointer(results[count].start)
    if self.browsing_page_current >= last_occurrence then
        return
    end
    local page_no
    local start = 1
    local l_end = count
    start, l_end = self:getNextLoopStartEnd(results, start, l_end, last_occurrence)
    for i = start, l_end do
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        if self:isValidNextFilteredItemPage(page_no, last_occurrence) then
            return page_no
        end
    end
end

function XrayPages:getPreviousPageFrom(results)
    count = #results
    local first_occurrence = KOR.document:getPageFromXPointer(results[1].start)
    if self.browsing_page_current <= first_occurrence then
        return
    end
    local page_no
    local start = count
    local l_end = 1
    start, l_end = self:getPreviousLoopStartEnd(results, start, l_end)
    for i = start, l_end, -1 do
        --* pageHasItemName example: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        if self:isValidPreviousFilteredItemPage(page_no, first_occurrence) then
            return page_no
        end
    end
end

--- @private
function XrayPages:showNextOrPreviousItemMessage(direction, needle)
    if self.search_also_in_opposite_direction then
        return
    end

    local adjective = direction == 1 and _("next") or _("previous")
    KOR.messages:notify(T(_("go to %1 occurrence of \"%2\""), adjective, needle))
        end

--- @private
function XrayPages:setValidNextBrowsingPage(page_no, direction)
    if not page_no then
        return
    end
    if not self.browsing_page_new then
        self.browsing_page_new = page_no
        return
    end

    if direction == 1 and page_no > self.browsing_page_current and page_no < self.browsing_page_new then
        self.browsing_page_new = page_no

    elseif direction == -1 and page_no < self.browsing_page_current and page_no > self.browsing_page_new then
        self.browsing_page_new = page_no
    end
    end

--- @private
function XrayPages:isValidNextFilteredItemPage(page_no, last_occurrence)
    --* pageHasItemName example: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
    return page_no > self.browsing_page_current and page_no <= last_occurrence and self:pageHasItemName(page_no)
end

--- @private
function XrayPages:isValidPreviousFilteredItemPage(page_no, first_occurrence)
    --* pageHasItemName example: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
    return page_no < self.browsing_page_current and page_no >= first_occurrence and self:pageHasItemName(page_no)
end

--- @private
function XrayPages:getNextLoopStartEnd(results, start, l_end, last_occurrence)
    local test_loops = 4
    if count > 600 then
        test_loops = 12
    elseif count > 500 then
        test_loops = 10
    elseif count > 400 then
        test_loops = 8
    elseif count > 300 then
        test_loops = 6
    elseif count > 200 then
        test_loops = 5
    end
    local needle_no, page_no, diff
    for i = 1, test_loops do
        diff = l_end - start
        if diff < 4 then
            return start, l_end
        end
        needle_no = start + math_ceil(diff / 2)
        page_no = KOR.document:getPageFromXPointer(results[needle_no].start)
        --* if the page is valid, we can subtract from l_end:
        if self:isValidNextFilteredItemPage(page_no, last_occurrence) then
            l_end = needle_no

        --* if the page is not valid, we can use it as start marker:
        else
            start = needle_no
            self.garbage = i
        end
    end
    return start, l_end
end

--- @private
function XrayPages:getPreviousLoopStartEnd(results, start, l_end, first_occurrence)
    local test_loops = 4
    if count > 600 then
        test_loops = 12
    elseif count > 500 then
        test_loops = 10
    elseif count > 400 then
        test_loops = 8
    elseif count > 300 then
        test_loops = 6
    elseif count > 200 then
        test_loops = 5
    end
    local needle_no, page_no, diff
    --! initially start = count and l_end is 1, because we loop back from count to 1; so start is greater than l_end!
    for i = 1, test_loops do
        diff = l_end - start
        if diff < 4 then
            return start, l_end
        end
        needle_no = start + math_ceil(diff / 2)
        page_no = KOR.document:getPageFromXPointer(results[needle_no].start)
        --* if the page is valid, we can subtract from start:
        if self:isValidPreviousFilteredItemPage(page_no, first_occurrence) then
            start = needle_no

        --* if the page is not valid, we can use it as end marker:
        else
            l_end = needle_no
            self.garbage = i
        end
    end
    return start, l_end
end

function XrayPages:jumpToPage()
    local max_page = KOR.document:getPageCount()
    local dialog
    dialog = KOR.dialogs:prompt({
        title = _("Jump to page"),
        input = "",
        input_type = "number",
        description = T(_("Last page: %1"), max_page),
        allow_newline = false,
        cursor_at_end = true,
        width = math_ceil(DX.pn.screen_width / 2.5),
        no_overlay = true,
        callback = function(value)
            UIManager:close(dialog)
            value = tonumber(value)
            if value == 0 or value > max_page then
                KOR.messages:notify(_("the page number entered was invalid") .. "...")
                return
            end
            DX.sp:resetActiveSideButtons("XrayPages:jumpToPage")
            DX.pn.navigator_page_no = value
            DX.pn:showNavigator(DX.pn.initial_browsing_page)
        end,
    })
end

--- @private
function XrayPages:pageHasItemName(page_no)
    local html = self:getPageHtmlForPage(page_no)
    local hits = DX.u:getXrayItemsFoundInText(html, "for_navigator")
    if not hits then
        return false
    end
    local hcount = #hits
    for i = 1, hcount do
        if hits[i].name == DX.pn.active_filter_name then
            return true
        end
    end
    return false
end

--- @private
function XrayPages:getPageHtmlForPage(page_no)
    if self.cached_html_by_page_no[page_no] then
        return self.cached_html_by_page_no[page_no]
    end

    self.cached_html_by_page_no[page_no] = KOR.document:getPageHtml(page_no)
    return self.cached_html_by_page_no[page_no]
end

function XrayPages:resetCache()
    self.cached_html_by_page_no = {}
end

function XrayPages:toCurrentNavigatorPage()
    DX.sp:resetActiveSideButtons("XrayPages:toCurrentNavigatorPage")
    DX.pn.navigator_page_no = DX.pn.initial_browsing_page
    DX.pn:showNavigator(DX.pn.initial_browsing_page)
end

function XrayPages:toNextNavigatorPage(goto_next_item)
    DX.sp:resetActiveSideButtons("XrayPages:toNextNavigatorPage")
    local direction = 1
    --* navigation to next filtered item hit:
    if DX.pn.page_navigator_filter_item or goto_next_item then
        self:gotoPageHitForItem(goto_next_item, direction)
        return
    end

    --* regular navigation:
    DX.pn.navigator_page_no = DX.pn.navigator_page_no + 1
    local epages = KOR.document:getPageCount()
    if DX.pn.navigator_page_no >= epages then
        DX.pn:setProp("navigator_page_no", epages)
        self:showNoNextPreviousOccurrenceMessage(direction)
        return
    end
    DX.pn:showNavigator(DX.pn.initial_browsing_page)
end

function XrayPages:toPrevNavigatorPage(goto_prev_item)
    DX.sp:resetActiveSideButtons("XrayPages:toPrevNavigatorPage")
    local direction = -1
    --* navigation to previous filtered item hit:
    if DX.pn.page_navigator_filter_item or goto_prev_item then
        self:gotoPageHitForItem(goto_prev_item, direction)
        return
    end

    --* regular navigation:
    DX.pn.navigator_page_no = DX.pn.navigator_page_no - 1
    if DX.pn.navigator_page_no < 1 then
        DX.pn:setProp("navigator_page_no", 1)
        self:showNoNextPreviousOccurrenceMessage(direction)
        return
    end
    DX.pn:showNavigator(DX.pn.initial_browsing_page)
end

function XrayPages:toPrevOrNextNavigatorPage(goto_item)
    DX.sp:resetActiveSideButtons("XrayPages:toPrevOrNextNavigatorPage")
    local direction = -1
    self.search_also_in_opposite_direction = true
    self:gotoPageHitForItem(goto_item, direction)
end

--- @private
function XrayPages:gotoPageHitForItem(goto_item, direction)
    Trapper:wrap(function()
        if goto_item then
            self:setTemporaryFilterItem(goto_item)
        end
        local item = DX.pn.page_navigator_filter_item
        local results, needle, case_insensitive
        --* if applicable, we only search for first names (then probably more accurate hits count):
        needle = DX.m:getRealFirstOrSurName(item)
        --* for lowercase needles (terms instead of persons), we search case insensitive:
        case_insensitive = not needle:match("[A-Z]")

        self:showNextOrPreviousItemMessage(direction, needle)

        --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
        results = DX.pn.cached_hits_by_needle[needle] or KOR.document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
        DX.pn.cached_hits_by_needle[needle] = results

        self.browsing_page_new = nil
        self.browsing_page_current = DX.pn.navigator_page_no

        local next_page = direction == 1
            and self:getNextPageFrom(results)
            or self:getPreviousPageFrom(results)
        self:setValidNextBrowsingPage(next_page, direction)

        local no_page_found = not next_page
        if self.search_also_in_opposite_direction and no_page_found then
            --* search_also_in_opposite_direction is true when the search was initiated from ((XrayCallbacks#execPageNavigatorSearchItemCallback)) > ((XrayPages#toPrevOrNextNavigatorPage)); in that case we started searching backwards, but if that yielded no result, we'll now search in forward direction:
            next_page = self:getNextPageFrom(results)
            no_page_found = not next_page
            self:setValidNextBrowsingPage(next_page, direction)
        end

        if has_no_text(item.aliases) then
            self.search_also_in_opposite_direction = false
            if no_page_found then
                self:undoTemporaryFilterItem(goto_item)
                self:showNoNextPreviousOccurrenceMessage(direction)
                return
            end
            self:handleItemHitFound(next_page)
            --! this statement MUST be executed AFTER the previous one, because undoTemporaryFilterItem reset DX.pn.active_filter_name:
            self:undoTemporaryFilterItem(goto_item)
            return
            end

        self:searchNextOrPreviousAliasHit(item, needle, results, case_insensitive, direction)

        if self:invalidItemPageHitHandled(direction, goto_item) then
            return
        end

        self:handleItemHitFound(self.browsing_page_new)
        --! this statement MUST be executed AFTER the previous one, because undoTemporaryFilterItem reset DX.pn.active_filter_name:
        self:undoTemporaryFilterItem(goto_item)
    end)
end

--- @private
function XrayPages:invalidItemPageHitHandled(direction, goto_item)
    --* this prop should be set by ((XrayPages#setValidNextBrowsingPage)):
    if
        not self.browsing_page_new
        or self.browsing_page_new == DX.pn.navigator_page_no
        or direction == 1 and self.browsing_page_new < DX.pn.navigator_page_no
        or direction == -1 and self.browsing_page_new > DX.pn.navigator_page_no
    then
        self:undoTemporaryFilterItem(goto_item)
        self:showNoNextPreviousOccurrenceMessage(direction)
        return true
    end

    return false
end

--- @private
function XrayPages:searchNextOrPreviousAliasHit(item, needle, results, case_insensitive, direction)
        local aliases = DX.m:splitByCommaOrSpace(item.aliases)
        local aliases_count = #aliases
    local next_page
        for a = 1, aliases_count do
            results = DX.pn.cached_hits_by_needle[needle] or KOR.document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
            DX.pn.cached_hits_by_needle[needle] = results
            next_page = direction == 1 and self:getNextPageFrom(results) or self:getPreviousPageFrom(results)
            if not next_page and self.search_also_in_opposite_direction then
                next_page = self:getNextPageFrom(results)
        end
            self:setValidNextBrowsingPage(next_page, direction)
        end
end

--- @private
function XrayPages:handleItemHitFound(page)
    DX.pn:setProp("navigator_page_no", page)
    DX.sp.active_side_button_by_name = DX.pn.active_filter_name
    DX.pn:showNavigator(DX.pn.initial_browsing_page)
end

--- @private
function XrayPages:setTemporaryFilterItem(goto_item)
    self.previous_filter_item = KOR.tables:shallowCopy(DX.pn.page_navigator_filter_item)
    self.previous_filter_name = DX.pn.active_filter_name

    DX.pn:setProp("page_navigator_filter_item", KOR.tables:shallowCopy(goto_item))
    DX.pn:setProp("active_filter_name", goto_item.name)
end

--- @private
function XrayPages:undoTemporaryFilterItem(goto_item)
    if not goto_item then
        return
    end
    DX.pn:setProp("page_navigator_filter_item", self.previous_filter_item)
    DX.pn:setProp("active_filter_name", self.previous_filter_name)
end

--- @private
function XrayPages:showNoNextPreviousOccurrenceMessage(direction)
    local adjective = direction == 1 and _("next") or _("previous")
    KOR.messages:notify(T(_("no %1 occurrence of this item found..."), adjective))
end

function XrayPages:markItemsFoundInPageHtml(html, navigator_page_no)
    DX.sp:resetSideButtons()
    self.button_labels_injected = ""
    DX.pn:setProp("navigator_page_no", navigator_page_no)
    DX.pn:setProp("first_info_panel_text", nil)

    if not self.non_active_layout then
        self:activateNonFilteredItemsLayout()
    end

    local hits = DX.u:getXrayItemsFoundInText(html, "for_navigator")
    if not hits then
        return html
    end

    count = #hits
    self.prev_marked_item = nil
    self:initNonFilteredItemsLayout()
    for i = 1, count do
        html = self:markItemsInHtml(html, hits[i])
    end
    --* don't use cache if a filtered item was set (with its additional html):
    if not DX.pn.active_filter_name then
        DX.pn.cached_html_and_buttons_by_page_no[DX.pn.navigator_page_no] = {
            html = html,
            side_buttons = DX.sp.side_buttons,
        }
    end
    return html
end

--- @private
function XrayPages:markedItemRegister(item, html, word)
    local needle = DX.vd:getNeedleString(word, "for_substitution")
    html = self:markNeedleInHtml(html, needle)
    local info_text = DX.pn:getItemInfoText(item)
    if info_text and not DX.pn.first_info_panel_text then
        DX.pn:setProp("first_info_panel_text", info_text)
        DX.pn:setProp("first_info_panel_item_name", item.name)

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
function XrayPages:markNeedleInHtml(html, needle, derived_name)
    if not DX.pn.active_filter_name and not derived_name then
        return html:gsub(needle, "<strong>%1</strong>")
    elseif not DX.pn.active_filter_name then
        return html:gsub(needle, "<strong>" .. derived_name .. "</strong>")
    end

    if derived_name then
        local non_active_layout = T(self.non_active_layout, derived_name)

        return self.is_filter_item and html:gsub(needle, "<strong>" .. derived_name .. "</strong>") or html:gsub(needle, non_active_layout)
    end

    return self.is_filter_item and html:gsub(needle, "<strong>%1</strong>") or html:gsub(needle, self.non_active_layout)
end

--- @private
function XrayPages:markItemsInHtml(html, item)
    if item.name == self.prev_marked_item then
        return html
    end
    self.prev_marked_item = item.name
    self.is_filter_item = DX.pn.active_filter_name == item.name

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
function XrayPages:markItem(item, subject, html, loop_no)
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
            --* only from here to ((XrayPages#markedItemRegister)) side panel buttons are populated:
            html = self:markPartialHits(html, item, uc, i, was_marked_for_full)
        end
    end
    return html
end

--- @private
function XrayPages:markAliasHit(html, item)

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
function XrayPages:markFullNameHit(html, item, subject, loop_no)
    if item.reliability_indicator ~= DX.i:getMatchReliabilityIndicator("full_name") then
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
function XrayPages:markPartialHits(html, item, uc, i, was_marked_for_full)
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

function XrayPages:initNonFilteredItemsLayout()
    --* the indices here must correspond to the settings in ((non_filtered_items_layout)):
    self.non_filtered_layouts = {
        ["small-caps"] = self.non_filtered_items_marker_smallcaps,
        ["small-caps-italic"] = self.non_filtered_items_marker_smallcaps_italic,
        ["bold"] = self.non_filtered_items_marker_bold,
    }
end

--- @private
function XrayPages:activateNonFilteredItemsLayout()
    if not self.non_filtered_layouts then
        self:initNonFilteredItemsLayout()
    end
    self.non_active_layout = DX.s.PN_non_filtered_items_layout
        and
        self.non_filtered_layouts[DX.s.PN_non_filtered_items_layout]
        or
        self.non_filtered_items_marker_smallcaps_italic
end

return XrayPages
