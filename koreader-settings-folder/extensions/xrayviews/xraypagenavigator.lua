--[[--
This extension is part of the Dynamic Xray plugin; it has all dialogs and forms (including their callbacks) which are used in XrayController and its other extensions.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayPageNavigator))
V = ((XrayUI)), ((XrayPageNavigator)), and ((XrayPageNavigator)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs, XrayPageNavigator and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayPageNavigator will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_items = has_items
local has_text = has_text
local table = table

local count
--- @type XrayModel parent
local parent

--- @class XrayPageNavigator
local XrayPageNavigator = WidgetContainer:new{
    alias_indent = "   ",
    cached_hits = {},
    current_item = nil,
    initial_browsing_page = nil,
    marker = KOR.icons.active_tab_bare,
    max_line_length = 80,
    navigator_page_no = nil,
    no_navigator_page_found = false,
    page_navigator_filter_item = nil,
    prev_marked_item = nil,
    scroll_to_page = nil,
}

--- @param xray_model XrayModel
function XrayPageNavigator:initDataHandlers(xray_model)
    parent = xray_model
end

function XrayPageNavigator:showNavigator(initial_browsing_page, info_panel_text, marker_name)

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
    --* this prop can be set in ((XrayPageNavigator#toNextNavigatorPage)) and ((XrayPageNavigator#toPrevNavigatorPage)):
    if self.no_navigator_page_found then
        self.no_navigator_page_found = false
    else
        self:closePageNavigator()
    end
    local side_buttons
    local html = KOR.document:getPageHtml(self.navigator_page_no)
    html, side_buttons = self:markItemsFoundInPageHtml(html, self.navigator_page_no, marker_name)

    info_panel_text = self:generateInfoPanelTextIfMissing(side_buttons, info_panel_text)

    self.page_navigator = KOR.dialogs:htmlBox({
        title = DX.m.current_title .. " - p." .. self.navigator_page_no,
        html = html,
        info_panel_text = info_panel_text,
        window_size = "fullscreen",
        no_buttons_row = true,
        top_buttons_left = DX.b:forPageNavigatorTopLeft(self),
        --? for some reason sometimes buttons with same labels are duplicated; here we prune the duplications:
        side_buttons = DX.b:pruneDuplicatedNavigatorButtons(side_buttons),
        side_buttons_navigator = DX.b:forXrayPageNavigator(self),
        next_item_callback = function()
            self:toNextNavigatorPage()
        end,
        prev_item_callback = function()
            self:toPrevNavigatorPage()
        end,
    })
end

function XrayPageNavigator:toCurrentNavigatorPage()
    self.navigator_page_no = self.initial_browsing_page
    self.no_navigator_page_found = false
    self:showNavigator()
end

function XrayPageNavigator:toNextNavigatorPage()
    local first_info_panel_text
    --* navigation to next filtered item hit:
    if self.page_navigator_filter_item then
        local next_page = self:getNextPageHitForTerm(self.page_navigator_filter_item, self.navigator_page_no)
        if not next_page or next_page == self.navigator_page_no then
            self.no_navigator_page_found = true
            KOR.messages:notify(_("no next mention of this item found..."))
            return
        end
        self.navigator_page_no = next_page
        first_info_panel_text = self:getItemInfoText(self.page_navigator_filter_item)

    --* regular navigation:
    else
        self.navigator_page_no = self.navigator_page_no + 1
        local epages = KOR.document:getPageCount()
        if self.navigator_page_no >= epages then
            self.navigator_page_no = epages
            self.no_navigator_page_found = true
            return
        end
    end
    self:showNavigator(self.initial_browsing_page, first_info_panel_text)
end

function XrayPageNavigator:toPrevNavigatorPage()
    local first_info_panel_text
    --* navigation to previous filtered item hit:
    if self.page_navigator_filter_item then
        local previous_page = self:getPreviousPageHitForTerm(self.page_navigator_filter_item, self.navigator_page_no)
        if not previous_page or previous_page == self.navigator_page_no then
            self.no_navigator_page_found = true
            KOR.messages:notify(_("no previous mention of this item found..."))
            return
        end
        self.navigator_page_no = previous_page
        first_info_panel_text = self:getItemInfoText(self.page_navigator_filter_item)

    --* regular navigation:
    else
        self.navigator_page_no = self.navigator_page_no - 1
        if self.navigator_page_no < 1 then
            self.navigator_page_no = 1
            self.no_navigator_page_found = true
            return
        end
    end
    self:showNavigator(self.initial_browsing_page, first_info_panel_text)
end

--- @private
function XrayPageNavigator:generateInfoPanelTextIfMissing(side_buttons, info_panel_text)
    if info_panel_text or not side_buttons or not side_buttons[1] then
        return info_panel_text
    end

    local first_item = side_buttons[1][1]
    --* this prop was set in ((XrayPageNavigator#markItem)):
    info_panel_text = self.first_info_panel_text or self:getItemInfoText(first_item)
    self.first_info_panel_text = info_panel_text
    self.first_info_panel_item_name = first_item.name
    side_buttons[1][1].text = self.marker .. side_buttons[1][1].text

    return info_panel_text
end

--- @private
function XrayPageNavigator:markItemsFoundInPageHtml(html, navigator_page_no, marker_name)
    local buttons = {}
    self.navigator_page_no = navigator_page_no
    self.first_info_panel_text = nil
    self.marker_name = marker_name

    local hits = DX.u:getXrayItemsFoundInText(html, "for_navigator")
    if not hits then
        return html, buttons
    end
    count = #hits

    self.prev_marked_item = nil
    for i = 1, count do
        html = self:markItemsInHtml(html, buttons, hits[i])
    end
    return html, buttons
end

--- @private
function XrayPageNavigator:markItemsInHtml(html, buttons, item)
    if item.name == self.prev_marked_item then
        return html
    end
    self.prev_marked_item = item.name

    local subject
    for l = 1, 2 do
        if l == 2 and not has_text(item.aliases) then
            return html
        end
        subject = l == 1 and item.name or item.aliases
        html = self:markItem(item, subject, html, buttons)
    end
    return html
end

--- @private
function XrayPageNavigator:markItem(item, subject, html, buttons)
    local parts, parts_count, uc

    subject = KOR.strings:trim(subject)
    html = self:markFullNameHit(html, item, subject)

    parts = KOR.strings:split(subject, ",? ")
    parts_count = #parts
    for i = 1, parts_count do
        uc = parts[i]
        --* only here side panel buttons are populated:
        self:markPartialHits(html, buttons, item, uc, i)
    end
    return html
end

--- @private
function XrayPageNavigator:markFullNameHit(html, item, subject)
    if item.reliability_indicator ~= DX.tw.match_reliability_indicators.full_name then
        return html
    end

    local matcher_esc = subject:gsub("%-", "%%-")
    html = html:gsub(matcher_esc, "<strong>" .. subject .. "</strong>")
    local xray_name_swapped = KOR.strings:getNameSwapped(matcher_esc)
    if not xray_name_swapped then
        return html
    end

    return html:gsub(xray_name_swapped, "<strong>" .. xray_name_swapped .. "</strong>")
end

--- @private
function XrayPageNavigator:markPartialHits(html, buttons, item, uc, i)
    local is_term, lc, matcher, matcher_esc

    local is_lowercase_person = item.xray_type < 3 and not uc:match("[A-Z]")
        is_term = item.xray_type > 2
    if (is_term or is_lowercase_person) and i == 1 then
    uc = KOR.strings:ucfirst(uc)
    end
    --* e.g. don't mark "of" in "Consistorial Court of Discipline":
    local is_markable_part_of_name = (is_term or is_lowercase_person or uc:match("[A-Z]")) and uc:len() > 2 and true or false

    matcher_esc = uc:gsub("%-", "%%-")
    matcher = "%f[%w_]" .. matcher_esc .. "%f[^%w_]"
    if is_markable_part_of_name and html:match(matcher) then
        --* return html and add item to buttons:
        return self:markedItemRegister(item, html, buttons, matcher_esc)

    --* for terms we also try to find lowercase variants of their names:
    elseif (is_term or is_lowercase_person) and is_markable_part_of_name then
        lc = KOR.strings:lower(uc)
        matcher_esc = lc:gsub("%-", "%%-")
        matcher = "%f[%w_]" .. matcher_esc .. "%f[^%w_]"
        if html:match(matcher) then
            --* return html and add item to buttons:
            return self:markedItemRegister(item, html, buttons, matcher_esc)
        end
    end
end

--* this info will be consumed for the info panel in ((HtmlBox#generateScrollWidget)):
--- @private
function XrayPageNavigator:getItemInfoText(item)
    --* the reliability_indicators were added in ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)):
    local reliability_indicator = item.reliability_indicator and item.reliability_indicator .. " " or ""

    self.alias_indent_corrected = DX.s.is_mobile_device and self.alias_indent .. self.alias_indent .. self.alias_indent .. self.alias_indent or self.alias_indent
    self.max_line_length = DX.s.is_mobile_device and 40 or self.max_line_length

    self.sub_info_separator = ""
    local description = KOR.strings:splitLinesToMaxLength(reliability_indicator .. item.name .. ": " .. item.description, self.max_line_length, self.alias_indent, nil, "dont_indent_first_line")
    local info = "\n" .. description .. "\n"

    self.sub_info_separator = "     "
    info = self:splitLinesToMaxLength(info, item.aliases, KOR.icons.xray_alias_bare .. " " .. item.aliases)
    info = self:splitLinesToMaxLength(info, item.linkwords, KOR.icons.xray_link_bare .. " " .. item.linkwords)
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
function XrayPageNavigator:markedItemRegister(item, html, buttons, matcher_esc)
    local replacer = "%f[%w_](" .. matcher_esc .. ")%f[^%w_]"
    html = html:gsub(replacer, "<strong>%1</strong>")
    local info_text = self:getItemInfoText(item)
    if info_text and not self.first_info_panel_text then
        self.first_info_panel_text = info_text
        self.first_info_panel_item_name = item.name
    end
    table.insert(buttons, {{
        text = (self.page_navigator_filter_item and item.name == self.page_navigator_filter_item.name and KOR.icons.filter .. item.name) or (item.name == self.marker_name and self.marker .. item.name) or item.name,
        align = "left",
        callback = function()
            if self.current_item and item.name == self.current_item.name then
                return true
            end
            self.current_item = item
            self:setActiveScrollPage()
            self:reloadPageNavigator(item, info_text)
        end,
        --* for marking or unmarking an item as filter criterium:
        hold_callback = function()
            if self.page_navigator_filter_item and self.page_navigator_filter_item.name == item.name then
                self:setActiveScrollPage()
                self.page_navigator_filter_item = nil
                self:reloadPageNavigator(item, info_text)
                return
            end
            self:setActiveScrollPage()
            self.page_navigator_filter_item = item
            self:reloadPageNavigator(item, info_text)
        end,
    }})
    return html
end

--- @private
function XrayPageNavigator:reloadPageNavigator(item, info_text)
    self:showNavigator(self.navigator_page_no, info_text, item.name)
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
function XrayPageNavigator:resultsPageGreaterThan(results, current_page, next_page)
    local page_no
    if has_items(results) then
        count = #results
        local last_occurrence = KOR.document:getPageFromXPointer(results[count].start)
        if current_page == last_occurrence then
            return
        end
        for i = 1, count do
            page_no = KOR.document:getPageFromXPointer(results[i].start)
            if page_no > current_page and (not next_page or page_no < next_page) then
                return page_no
            end
        end
    end
end

--- @private
function XrayPageNavigator:resultsPageSmallerThan(results, current_page, prev_page)
    local page_no
    if has_items(results) then
        count = #results
        local first_occurrence = KOR.document:getPageFromXPointer(results[1].start)
        if current_page == first_occurrence then
            return
        end
        for i = count, 1, -1 do
            page_no = KOR.document:getPageFromXPointer(results[i].start)
            if page_no < current_page and (not prev_page or page_no > prev_page) then
                return page_no
            end
        end
    end
end

--- @private
function XrayPageNavigator:getNextPageHitForTerm(item, current_page)
    local document = KOR.ui.document
    local results, needle, case_insensitive
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(item)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = self.cached_hits[needle] or document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
    self.cached_hits[needle] = results
    local next_page = self:resultsPageGreaterThan(results, current_page)

    local search_for_aliases = has_text(item.aliases)
    if search_for_aliases then
        local aliases = parent:splitByCommaOrSpace(item.aliases)
        local aliases_count = #aliases
        for a = 1, aliases_count do
            results = document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
            next_page = self:resultsPageGreaterThan(results, current_page, next_page)
        end
    end

    return next_page
end

--- @private
function XrayPageNavigator:getPreviousPageHitForTerm(item, current_page)
    local document = KOR.ui.document
    local results, needle, case_insensitive
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(item)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = self.cached_hits[needle] or document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)
    self.cached_hits[needle] = results
    local prev_page = self:resultsPageSmallerThan(results, current_page)

    local search_for_aliases = has_text(item.aliases)
    if search_for_aliases then
        local aliases = parent:splitByCommaOrSpace(item.aliases)
        local aliases_count = #aliases
        for a = 1, aliases_count do
            results = document:findAllTextWholeWords(aliases[a], case_insensitive, 0, 3000, false)
            prev_page = self:resultsPageSmallerThan(results, current_page, prev_page)
        end
    end

    return prev_page
end

--- @private
function XrayPageNavigator:closePageNavigator()
    if self.page_navigator then
        UIManager:close(self.page_navigator)
        self.page_navigator = nil
    end
end

return XrayPageNavigator
