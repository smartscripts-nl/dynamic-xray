
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
local XrayPages = WidgetContainer:new {
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

function XrayPages:resultsPageGreaterThan(results, current_page, next_page)
    if not has_items(results) then
        return
    end
    count = #results
    local last_occurrence = KOR.document:getPageFromXPointer(results[count].start)
    if current_page == last_occurrence then
        return
    end
    local page_no, valid_next_page
    local start = 1
    local l_end = count
    start, l_end = self:getLoopStartEnd(results, start, l_end, current_page, next_page)
    for i = start, l_end do
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        valid_next_page = self:verifyPageHit(page_no > current_page and (not next_page or page_no < next_page), page_no)
        if valid_next_page then
            return valid_next_page
        end
    end
end

function XrayPages:resultsPageSmallerThan(results, current_page, prev_page)
    if not has_items(results) then
        return
    end
    count = #results
    local first_occurrence = KOR.document:getPageFromXPointer(results[1].start)
    if current_page == first_occurrence then
        return
    end
    local page_no, valid_prev_page
    local start = count
    local l_end = 1
    start, l_end = self:getLoopStartEnd(results, start, l_end, current_page, prev_page)
    for i = start, l_end, -1 do
        page_no = KOR.document:getPageFromXPointer(results[i].start)
        valid_prev_page = self:verifyPageHit(page_no < current_page and (not prev_page or page_no > prev_page), page_no)
        if valid_prev_page then
            return valid_prev_page
        end
    end
end

--- @private
function XrayPages:getLoopStartEnd(results, start, l_end, current_page, check_page)
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
    local needle, page_no, valid_page, diff
    local direction = start == 1 and 1 or -1
    for i = 1, test_loops do
        diff = l_end - start
        if diff < 4 then
            return start, l_end
        end
        needle = start + math_ceil(diff / 2)
        page_no = KOR.document:getPageFromXPointer(results[needle].start)
        if direction == 1 then
            valid_page = self:verifyPageHit(page_no > current_page and (not check_page or page_no < check_page), page_no)
        else
            valid_page = self:verifyPageHit(page_no < current_page and (not check_page or page_no > check_page), page_no)
        end
        if not valid_page then
            start = needle
        else
            l_end = needle
            self.garbage = i
        end
    end
    return start, l_end
end

--- @private
function XrayPages:verifyPageHit(condition, page_no)
    if
        condition
        and
        --! verify that the filter item is present in this page; if not, then it must be another item of which the name partly(!) matches with the name of the filter item:
        --* e.g.: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
        self:pageHasItemName(page_no)
    then
        return page_no
    end
end

function XrayPages:jumpToPage()
    local max_page = KOR.document:getPageCount()
    local dialog
    dialog = KOR.dialogs:prompt({
        title = _("Jump to page"),
        input = "",
        input_type = "number",
        description = T(_("Last page: %1"), KOR.document:getPageCount()),
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
            DX.pn:showNavigator()
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
    DX.pn:showNavigator()
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
        local current_page = DX.pn.navigator_page_no
        local results, needle, case_insensitive
        --* if applicable, we only search for first names (then probably more accurate hits count):
        needle = DX.m:getRealFirstOrSurName(item)
        local adjective = direction == 1 and _("next") or _("previous")
        KOR.messages:notify(T(_("to %1 occurrence of \"%2\""), adjective, needle))
        --* for lowercase needles (terms instead of persons), we search case insensitive:
        case_insensitive = not needle:match("[A-Z]")

        --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
        results = DX.pn.cached_hits_by_needle[needle] or KOR.document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
        DX.pn.cached_hits_by_needle[needle] = results
        local next_page = direction == 1 and self:resultsPageGreaterThan(results, current_page) or self:resultsPageSmallerThan(results, current_page)

        local no_page_found = not next_page or next_page == DX.pn.navigator_page_no
        if self.search_also_in_opposite_direction and no_page_found then
            next_page = self:resultsPageGreaterThan(results, current_page)
            no_page_found = not next_page or next_page == DX.pn.navigator_page_no
        end

        if has_no_text(item.aliases) then
            if no_page_found then
                self:showNoNextPreviousOccurrenceMessage(direction)
                return
            end
            self:handleItemHitFound(next_page, goto_item)
            return
        end

        local aliases = DX.m:splitByCommaOrSpace(item.aliases)
        local aliases_count = #aliases
        for a = 1, aliases_count do
            results = DX.pn.cached_hits_by_needle[needle] or KOR.document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
            DX.pn.cached_hits_by_needle[needle] = results
            next_page = self:resultsPageGreaterThan(results, current_page, next_page)
        end

        no_page_found = not next_page or next_page == DX.pn.navigator_page_no

        if self.search_also_in_opposite_direction and no_page_found then
            next_page = self:resultsPageGreaterThan(results, current_page)
            no_page_found = not next_page or next_page == DX.pn.navigator_page_no
        end

        if no_page_found then
            self:showNoNextPreviousOccurrenceMessage(direction)
            return
        end
        self:handleItemHitFound(next_page, goto_item)
    end)
end

--- @private
function XrayPages:handleItemHitFound(page, called_upon_hold_button)
    DX.pn:setProp("navigator_page_no", page)
    DX.sp.active_side_button_by_name = DX.pn.active_filter_name
    if called_upon_hold_button then
        self:undoTemporaryFilterItem()
    end
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
function XrayPages:undoTemporaryFilterItem()
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
    if item.reliability_indicator ~= KOR.informationdialog:getMatchReliabilityIndicator("full_name") then
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
