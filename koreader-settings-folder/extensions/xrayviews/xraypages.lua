
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local md5 = require("ffi/sha2").md5
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_no_items = has_no_items
local math_abs = math.abs
local math_ceil = math.ceil
local tonumber = tonumber

local count

--- @class XrayPages
local XrayPages = WidgetContainer:new{
    browsing_page_current = nil,
    browsing_page_new = nil,
    button_labels_injected = {},
    cached_html_by_page_no = {},
    cached_page_texts = {},
    --* whole word name parts which may not be marked bold and trigger an item hit by themselves only; used in ((XrayPages#checkTextMatch)):
    --? but should this not also be used as option to ((Strings#split)), when determining items in ((XrayPages))?:
    forbidden_needle_parts = {
        ["De"] = true,
        ["La"] = true,
        ["Le"] = true,
    },
    is_filter_item = false,
    non_active_layout = nil,
    non_filtered_items_marker_em = "<em>%1</em>",
    non_filtered_items_marker_smallcaps = "<span style='font-variant: small-caps'>%1</span>",
    non_filtered_items_marker_smallcaps_italic = "<i style='font-variant: small-caps'>%1</i>",
    non_filtered_items_marker_strong = "<strong>%1</strong>",
    non_filtered_layouts = nil,
    previous_filter_item = nil,
    previous_filter_name = nil,
    prev_marked_item = nil,
    search_also_in_opposite_direction = false,
}

--- @private
function XrayPages:showNextOrPreviousItemMessage(direction, needle)
    if self.search_also_in_opposite_direction then
        return
    end

    local adjective = direction == 1 and _("next") or _("previous")
    KOR.messages:notify(T(_("go to %1 occurrence of \"%2\""), adjective, needle))
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
                KOR.messages:notify(_("the page number entered was invalid"))
                return
            end
            DX.sp:resetActiveSideButtons("XrayPages:jumpToPage")
            DX.pn.page_no = value
            DX.pn:restoreNavigator()
        end,
    })
end

--- @private
function XrayPages:pageHasItemName(page_no, filter_name, filter_name2)
    local html = self:getPageHtmlForPage(page_no)
    local tagged_items = DX.pn:getTaggedItems()
    local hits = DX.u:getXrayItemsFoundInText(html, tagged_items)
    if not hits then
        return false
    end
    local hcount = #hits
    local found = 0
    for i = 1, hcount do
        if not filter_name2 and hits[i].name == filter_name then
            return true
        elseif filter_name2 and (hits[i].name == filter_name or hits[i].name == filter_name2) then
            found = found + 1
        end
    end
    if filter_name2 and found == 2 then
        return true
    end
    return false
end

--- @private
function XrayPages:getPageHtmlForPage(page_no, skip_cache)
    if skip_cache then
        return KOR.document:getPageHtml(page_no)
    end
    if self.cached_html_by_page_no[page_no] then
        return self.cached_html_by_page_no[page_no]
    end

    self.cached_html_by_page_no[page_no] = KOR.document:getPageHtml(page_no)
    return self.cached_html_by_page_no[page_no]
end

function XrayPages:resetCache()
    self.cached_html_by_page_no = {}
    self.cached_page_texts = {}
end

function XrayPages:toCurrentNavigatorPage()
    DX.sp:resetActiveSideButtons("XrayPages:toCurrentNavigatorPage")
    DX.pn.page_no = DX.pn.initial_browsing_page
    DX.pn:restoreNavigator()
end

function XrayPages:toNextNavigatorPage(goto_next_item)
    DX.sp:resetActiveSideButtons("XrayPages:toNextNavigatorPage")
    local direction = 1
    --* navigation to next tagged item hit:
    if DX.pn.navigation_tag then
        --* via ((XrayPages#getPageHtmlForPage)) and ((XrayPages#getPageHtmlForPage)) PageNavigator.navigator_page_html can be populated with html containing the tagged items:
        self:gotoPageHitForTaggedItem(direction)
        return
    --* navigation to next double filtered items hit:
    elseif DX.pn.filter_item_double then
        self:gotoPageHitForDuoItem(direction)
        return
    --* navigation to next filtered item hit:
    elseif DX.pn.filter_item or goto_next_item then
        self:gotoPageHitForItem(goto_next_item, direction)
        return
    end

    --* regular navigation:
    DX.pn.page_no = DX.pn.page_no + 1
    local epages = KOR.document:getPageCount()
    if DX.pn.page_no >= epages then
        DX.pn:setProp("page_no", epages)
        self:showNoNextPreviousOccurrenceMessage(direction)
        return
    end
    DX.pn:restoreNavigator()
end

function XrayPages:toPrevNavigatorPage(goto_prev_item, stay_at_top_of_page)
    DX.sp:resetActiveSideButtons("XrayPages:toPrevNavigatorPage")
    local direction = -1
    --* navigation to previous tagged item hit:
    if DX.pn.navigation_tag then
        self:gotoPageHitForTaggedItem(direction)
        return
    --* navigation to next double filtered items hit:
    elseif DX.pn.filter_item_double then
        self:gotoPageHitForDuoItem(direction)
        return
    --* navigation to previous filtered item hit:
    elseif DX.pn.filter_item or goto_prev_item then
        self:gotoPageHitForItem(goto_prev_item, direction)
        return
    end

    --* regular navigation:
    DX.pn.page_no = DX.pn.page_no - 1
    if DX.pn.page_no < 1 then
        DX.pn:setProp("page_no", 1)
        self:showNoNextPreviousOccurrenceMessage(direction)
        return
    end
    DX.pn:restoreNavigator()
    --* this is truthy when navigating backwards with left arrow button in Page Navigator:
    if stay_at_top_of_page then
        return
    end
    DX.pn:scrollToBottom()
end

function XrayPages:toPrevOrNextNavigatorPage(goto_item)
    DX.sp:resetActiveSideButtons("XrayPages:toPrevOrNextNavigatorPage")
    local direction = -1
    self.search_also_in_opposite_direction = true
    self:gotoPageHitForItem(goto_item, direction)
end

function XrayPages:resetPageForFilteredBrowsing()
    self.browsing_page_new = nil
end

--- @private
function XrayPages:gotoPageHitForItem(goto_item, direction)
    --* this temporarily sets DX.pn.filter_item:
    if goto_item then
        self:setTemporaryFilterItem(goto_item)
    end
    local item = DX.pn.filter_item
    self:showNextOrPreviousItemMessage(direction, item.name)

    --* self.browsing_page_new will be set to nil upon activating the item filter, via ((XrayPageNavigator#setFilter)) > ((XrayPages#resetPageForFilteredBrowsing)):
    self.browsing_page_current = DX.pn.page_no
    local max_page = KOR.document:getPageCount()
    local other_page = self.browsing_page_new or self.browsing_page_current
    local prev_page = other_page
    other_page = self:modifyCheckPage(direction, other_page, max_page)

    local found, hit
    if other_page then
        found, hit = self:pageHasItem(other_page, item)
        --* pageHasItemName example: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
        if not self:pageHasItemName(other_page, DX.pn.active_filter_name) then
            found = false
        end
    end

    if self:invalidItemPageHitHandled(found, direction, goto_item, other_page) then
        self.browsing_page_new = prev_page
        return false
    end

    while not found and other_page do
        other_page = self:modifyCheckPage(direction, other_page, max_page)
        if other_page then
            found, hit = self:pageHasItem(other_page, item) --, page_text
            if not self:pageHasItemName(other_page, DX.pn.active_filter_name) then
                found = false
            end
        end
    end

    if self:invalidItemPageHitHandled(found, direction, goto_item, other_page) then
        self.browsing_page_new = prev_page
        return false
    end

    --* we don't use second arg html here, because html generated and items marked in (()):
    self:handleItemHitFound(self.browsing_page_new)
    --! this statement MUST be executed AFTER the previous one, because undoTemporaryFilterItem reset DX.pn.active_filter_name:
    self:undoTemporaryFilterItem(goto_item)

    return true
end

--- @private
function XrayPages:gotoPageHitForDuoItem(direction)

    local subjects = T("%1 + %2", DX.pn.filter_item.name, DX.pn.filter_item_double.name)

    local patience = _("searching")
    local message =
        direction == 1 and
        T("%1 %2 %3", subjects, KOR.icons.arrow_bare, patience)
        or
        T("%1 %2: %3", KOR.icons.arrow_left_bare, subjects, patience)
    KOR.messages:notify(message)
    UIManager:forceRePaint()

    --* self.browsing_page_new will be set to nil upon activating the item filter, via ((XrayPageNavigator#setFilterDouble)) > ((XrayPages#resetPageForFilteredBrowsing)):
    self.browsing_page_current = DX.pn.page_no
    local max_page = KOR.document:getPageCount()
    local other_page = self.browsing_page_new or self.browsing_page_current
    local prev_page = other_page
    other_page = self:modifyCheckPage(direction, other_page, max_page)

    local found
    if other_page then
        found = self:pageHasDuoItem(other_page)
        --* pageHasItemName example: if we made "Coram van Texel" the filter item, the script would search for occurrences of "Coram" and - but for this extra condition - yield back a false hit for "Farder Coram":
        if not self:pageHasItemName(other_page, DX.pn.active_filter_name, DX.pn.active_filter_name_double) then
            found = false
        end
    end

    if self:invalidItemPageHitHandled(found, direction, nil, other_page) then
        self.browsing_page_new = prev_page
        return false
    end

    while not found and other_page do
        other_page = self:modifyCheckPage(direction, other_page, max_page)
        if other_page then
            found = self:pageHasDuoItem(other_page)
            if not self:pageHasItemName(other_page, DX.pn.active_filter_name, DX.pn.active_filter_double) then
                found = false
            end
        end
    end

    if self:invalidItemPageHitHandled(found, direction, nil, other_page) then
        self.browsing_page_new = prev_page
        return false
    end

    --* we don't use second arg html here, because html generated and items marked in (()):
    self:handleItemHitFound(self.browsing_page_new)

    return true
end

--- @private
function XrayPages:modifyCheckPage(direction, ref_page, max_page)
    if direction == 1 then
        ref_page = ref_page + 1
        if ref_page > max_page then
            return
            end
        self.browsing_page_new = ref_page
        return ref_page
    end

    ref_page = ref_page - 1
    if ref_page < 1 then
            return
        end
    self.browsing_page_new = ref_page
    return ref_page
end

--- @private
function XrayPages:notifyNoNextOccurrences()
    KOR.messages:notify(_("no later occurrences found"))
end

--- @private
function XrayPages:notifyNoPreviousOccurrences()
    KOR.messages:notify(_("no previous occurrences found"))
end

--- @private
function XrayPages:gotoPageHitForTaggedItem(direction)
    local page_no = DX.pn.page_no
    local page_count = KOR.document:getPageCount()
    if page_no == 1 and direction == -1 then
        self:notifyNoPreviousOccurrences()
        return
    elseif page_no == page_count and direction == 1 then
        self:notifyNoNextOccurrences()
        return
    end
    local html
    while page_no > 0 and page_no <= page_count do
        if direction == 1 then
            page_no = page_no + 1
        else
            page_no = page_no - 1
        end
        html = page_no > 0 and page_no <= page_count and self:markItemsFoundInPageHtml(page_no, "for_tagged_items")

        if html and html:find("<strong", 1, true) then
            self:handleItemHitFound(page_no, html)
            return
        elseif page_no == page_count and direction == 1 then
            self:notifyNoNextOccurrences()
            return
        elseif page_no == 1 and direction == -1 then
            self:notifyNoPreviousOccurrences()
            return
        end
    end
end

--- @private
function XrayPages:invalidItemPageHitHandled(found, direction, goto_item, other_page)
    if found then
        return false
    end
    --* first two props should be set by ((XrayPages#modifyCheckPage)):
    if
        not other_page
        or not self.browsing_page_new
        or self.browsing_page_new == DX.pn.page_no
        or direction == 1 and self.browsing_page_new < DX.pn.page_no
        or direction == -1 and self.browsing_page_new > DX.pn.page_no
    then
        if goto_item then
            self:undoTemporaryFilterItem(goto_item)
        end
        self:showNoNextPreviousOccurrenceMessage(direction)
        return true
    end

    return false
end

--* this method updates the view in Page Navigator, with Xray items marked, via ((XrayPageNavigator#restoreNavigator)); see for further steps ((XRAY_ITEMS_DATA_FLOW)):
--- @private
function XrayPages:handleItemHitFound(page_no, html)
    DX.pn:setProps(
        { "page_no", page_no },
        { "navigator_page_html", html },
        { "navigator_side_buttons", DX.sp.side_buttons }
    )
    if not DX.pn.navigation_tag then
        DX.sp.active_side_button_by_name = DX.pn.active_filter_name
    end
    DX.pn:restoreNavigator()
end

--- @private
function XrayPages:pageHasItem(page_no, item)

    local text = self.cached_page_texts[page_no] or KOR.document:getPageText(page_no, "cleanup", "force_update")
    self.cached_page_texts[page_no] = text

    --* these needles (also containing aliases and short names!) and other filter item props were set in ((XrayPageNavigator#setFilter)):
    local needles = DX.pn.filter_item.needles
    local is_term = DX.pn.filter_item.is_term
    local is_lowercase = DX.pn.filter_item.is_lowercase
    local ncount = DX.pn.filter_item.needles_count
    local needle
    for i = 1, ncount do
        needle = needles[i].needle
        --* ncount is 1 when only matching for full name:
        if ncount == 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            return true, item.name
        elseif ncount > 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            return true, needle
        end
    end

    return false
end

--- @private
function XrayPages:pageHasDuoItem(page_no)

    local text = self.cached_page_texts[page_no] or KOR.document:getPageText(page_no, "cleanup", "force_update")
    self.cached_page_texts[page_no] = text

    --* these needles (also containing aliases and short names!) and other filter item props were set in ((XrayPageNavigator#setFilterDouble)):
    local needles = DX.pn.filter_item.needles
    local is_term = DX.pn.filter_item.is_term
    local is_lowercase = DX.pn.filter_item.is_lowercase
    local ncount = DX.pn.filter_item.needles_count
    local needle, item1_found
    for i = 1, ncount do
        needle = needles[i].needle
        --* ncount is 1 when only matching for full name:
        if ncount == 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            item1_found = true
            break
        elseif ncount > 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            item1_found = true
            break
        end
    end
    if not item1_found then
        return false
    end
    needles = DX.pn.filter_item_double.needles
    is_term = DX.pn.filter_item_double.is_term
    is_lowercase = DX.pn.filter_item_double.is_lowercase
    ncount = DX.pn.filter_item_double.needles_count
    for i = 1, ncount do
        needle = needles[i].needle
        --* ncount is 1 when only matching for full name:
        if ncount == 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            return true
        elseif ncount > 1 and self:checkTextMatch(text, needle, is_term, is_lowercase) then
            return true
        end
    end

    return false
end

--- @private
function XrayPages:checkTextMatch(text, needle, is_term, is_lowercase)

    local match_template = "%f[%a]%1%f[%A]"

    --* len() > 2: for example don't mark "of" in "Consistorial Court of Discipline":
    if not self.forbidden_needle_parts[needle] and needle:len() > 2 and text:match(T(match_template, needle)) then
        return true
    end

    if is_term and is_lowercase then
        needle = KOR.strings:upper(needle)
        if not self.forbidden_needle_parts[needle] and needle:len() > 2 and text:match(T(match_template, needle)) then
            return true
        end
    end
    return false
end

--- @private
function XrayPages:setTemporaryFilterItem(goto_item)
    self.previous_filter_item = KOR.tables:shallowCopy(DX.pn.filter_item)
    self.previous_filter_name = DX.pn.active_filter_name

    DX.pn:setProp("filter_item", KOR.tables:shallowCopy(goto_item))
    DX.pn:setProp("active_filter_name", goto_item.name)
end

--- @private
function XrayPages:undoTemporaryFilterItem(goto_item)
    if not goto_item then
        return
    end
    DX.pn:setProp("filter_item", self.previous_filter_item)
    DX.pn:setProp("active_filter_name", self.previous_filter_name)
end

--- @private
function XrayPages:showNoNextPreviousOccurrenceMessage(direction)
    local adjective = direction == 1 and _("next") or _("previous")

    local is_double_filter = DX.pn.filter_item_double
    local message = is_double_filter and _("no %1 occurrence of these items found; what do you want to do now?") or _("no %1 occurrence of this item found; what do you want to do now?")
    message = T(message, adjective)

    local dialog
    local opposite_direction = direction == 1 and _("previous") or _("next")
    dialog = KOR.dialogs:multiConfirm(message, {
        {
            {
                icon = "back",
                callback = function()
                    UIManager:close(dialog)
                end
            },
            {
                icon_text = {
                    icon = "dustbin",
                    text = " " .. _("filter"),
                    text_font_bold = false,
                },

                callback = function()
                    UIManager:close(dialog)
                    if is_double_filter then
                        DX.pn:resetFilterDouble()
                        return
                    end

                    DX.pn:resetFilter()
                end,
            },
            {
                icon_text = {
                    icon = "appbar.search",
                    text_font_bold = false,
                    text = " " .. opposite_direction,
                },
                callback = function()
                    UIManager:close(dialog)
                    direction = math_abs(direction - 1)
                    if is_double_filter then
                        self:gotoPageHitForDuoItem(direction)
                        return
                    end

                    self:gotoPageHitForItem(self.goto_item, direction)
                end,
            },
            {
                icon_text = {
                    icon = "add",
                    text_font_bold = false,
                    text = " " .. _("new filter"),
                },
                callback = function()
                    UIManager:close(dialog)
                    if is_double_filter then
                        DX.pn:resetFilterDouble()
                        DX.pn:setFilterDouble()
                        return
                    end

                    DX.pn:resetFilter()
                    DX.pn:setFilter()
                end,
            },
        },
    })
end

--- @private
function XrayPages:isPruneSideButton(item)
    local unique_label = md5(item.name)
    if self.button_labels_injected[unique_label] then
        return true
    end
    self.button_labels_injected[unique_label] = true
    return false
end

--* e.g. called for generating page html in Page Navigator:
--* self.cached_html_and_buttons_by_page_no will be updated here:
function XrayPages:markItemsFoundInPageHtml(page_no, for_tagged_items)

    local html = self:getPageHtmlForPage(page_no, for_tagged_items)
    --* side_buttons FOR SIDE PANEL TAB NO.1 de facto populated in ((XrayPages#markedItemRegister)) > ((XraySidePanels#addSideButton)):

    DX.sp:resetSideButtons()
    self.button_labels_injected = {}
    DX.pn:setProp("page_no", page_no)
    DX.ip:setProp("upon_load_panel_text", nil)

    local hits
    local tagged_items = DX.pn:getTaggedItems()
    if DX.pn.navigation_tag and has_items(tagged_items) then
        hits = DX.u:getXrayItemsFoundInText(html, tagged_items)
        if not hits then
            return html
        end
    elseif DX.pn.navigation_tag then
        return html
    else
        hits = DX.u:getXrayItemsFoundInText(html)
    end
    if has_no_items(hits) then
        return html
    end

    count = #hits
    self.prev_marked_item = nil
    if not self.non_active_layout then
        self:activateNonFilteredItemsLayout()
    end
    for i = 1, count do
        self:markedItemRegister(hits[i])
        if not DX.pn.active_filter_name or DX.pn.active_filter_name == hits[i].name or DX.pn.active_filter_name_double == hits[i].name then
            html = DX.vd:markItemInHtml(html, hits[i], "strong")
        else
            --* non_active_layout either "em", "small-caps", "small-caps-italic", "strong" (configured by XraySettings.PN_non_filtered_items_layout):
            html = DX.vd:markItemInHtml(html, hits[i], self.non_active_layout)
        end
    end
    --* don't use cache if a filtered item was set (with its additional html):
    if not DX.pn.active_filter_name and not DX.pn.navigation_tag then
        DX.pn.cached_html_and_buttons_by_page_no[DX.pn.page_no] = {
            html = html,
            side_buttons = DX.sp.side_buttons,
        }
    end
    return html
end

--- @private
function XrayPages:markedItemRegister(item)

    --* skip_item_registration might be set by ((XrayViewsData#markItemInHtml)), upon generating quotes html for an item:
    if self:isPruneSideButton(item) then
        return
    end

    local info_text = DX.ip:getItemInfoText(item)
    if info_text and not DX.ip.upon_load_panel_text then
        DX.ip:setProp("upon_load_panel_text", info_text)
    end

    --* linked item buttons (when DX.sp.active_side_tab == 2) are added in ((XrayPageNavigator#loadDataForPage)) > ((XraySidePanels#computeLinkedItems)):
    if DX.sp.active_side_tab == 1 then
        DX.sp:addSideButton(item, info_text)
    end
    end

function XrayPages:initNonFilteredItemsLayout()
    --* the indices here must correspond to the settings in ((non_filtered_items_layout)):
    self.non_filtered_layouts = {
        ["em"] = self.non_filtered_items_marker_em,
        ["small-caps"] = self.non_filtered_items_marker_smallcaps,
        ["small-caps-italic"] = self.non_filtered_items_marker_smallcaps_italic,
        ["strong"] = self.non_filtered_items_marker_strong,
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
