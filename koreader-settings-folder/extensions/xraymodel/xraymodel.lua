--[[--
This is part of the Dynamic Xray plugin; it is the model (databases operations etc.) for XrayController. It has several child data handlers.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayPageNavigator)), ((XrayTranslations)) and ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! important info

--! since I ran into some weird "bad self" error messages when trying to store data in the database, I changed the format of methods involved in this from colon methods to dot functions; and in those I set a local self to DX.m

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_items = has_items
local has_no_text = has_no_text
local has_text = has_text
local pairs = pairs
local table = table
local type = type

local count
--- @type XrayDataLoader data_loader
local data_loader
--- @type XrayDataSaver data_saver
local data_saver
--- @type XrayPageNavigator page_navigator
local page_navigator
--- @type XrayTappedWords tapped_words
local tapped_words
--- @type XrayFormsData forms_data
local forms_data
--- @type XrayViewsData views_data
local views_data

--- @class XrayModel
local XrayModel = WidgetContainer:new{
    active_list_tab = 1,
    current_ebook_basename = nil,
    current_ebook_full_path = nil,
    current_series = nil,
    current_title = nil,
    ebooks = {},
    items_prepared_for_basename = nil,
    min_match_word_length = 4,
    previous_series = nil,
    series = {},
    --* by default sort xray items by number of occurrences:
    sorting_method = "hits",
    switch_first_and_sur_name = false,
    tab_display_counts = { 0, 0, 0 },
    use_tapped_word_data = false,
}

function XrayModel:setDatabaseFile()
    if DX.m:isPrivateDXversion("silent") then
        return
    end
    if has_text(DX.s.database_filename) and DX.s.database_filename ~= "bookinfo_cache.sqlite3" then
        KOR.databases:setDatabaseFileName(DX.s.database_filename ~= "bookinfo_cache.sqlite3")
    end
end

--* using di to inject these data handlers resulted sometimes in crashes, so therefor loading them hardcoded in this method:
function XrayModel:initDataHandlers()
    --* XraySettings must always be registered, so it was registered in ((KOR#initExtensions)) > ((KOR#initDX))...

    views_data = require("extensions/xraymodel/xrayviewsdata")
    page_navigator = require("extensions/xrayviews/xraypagenavigator")
    data_loader = require("extensions/xraymodel/xraydataloader")
    data_saver = require("extensions/xraymodel/xraydatasaver")
    forms_data = require("extensions/xraymodel/xrayformsdata")
    tapped_words = require("extensions/xraymodel/xraytappedwords")
    DX.setProp("vd", views_data)
    DX.setProp("dl", data_loader)
    DX.setProp("ds", data_saver)
    DX.setProp("fd", forms_data)
    DX.setProp("pn", page_navigator)
    DX.setProp("tw", tapped_words)

    views_data:initDataHandlers(self)
    data_loader:initDataHandlers(self)
    data_saver:initDataHandlers(self)

    if self:isPublicDXversion("silent") then
        --* since XrayTranslations needs table xrays_translations to be created, we run this here:
        data_saver.createAndModifyTables()
    end

    forms_data:initDataHandlers(self)
    page_navigator:initDataHandlers(self)
    tapped_words:initDataHandlers(self)
end

function XrayModel:isPrivateDXversion(silent)
    if IS_AUTHORS_DX_INSTALLATION then
        if not silent then
            KOR.messages:notify("functionality not available in authors' version of dx...")
        end
        return true
    end
    return false
end

function XrayModel:isPublicDXversion()
    if IS_AUTHORS_DX_INSTALLATION then
        return false
    end
    return true
end

--* lower case needles must be at least 4 characters long, but for names with upper case characters in them no such condition is required:
function XrayModel:isValidNeedle(needle)
    return needle:len() >= self.min_match_word_length or needle:match("[A-Z]")
end

function XrayModel:isXrayItem(name)
    return name:gsub(":.+$", ""):match("[A-Z]")
end

function XrayModel:getSortingProp()
    if self.sorting_method == "hits" and views_data.list_display_mode == "series" then
        return "series_hits"

    elseif self.sorting_method == "hits" and views_data.list_display_mode == "book" then
        return "book_hits"
    end

    return "name"
end

function XrayModel:placeImportantItemsAtTop(items, sorting_direction)

    local sorting_prop = self:getSortingProp()
    if sorting_direction == 1 then
        return KOR.tables:sortByPropAscendingAndSetTopItems(items, sorting_prop, function(item)
            return item.xray_type == 2 or item.xray_type == 4
        end)
    end
    return KOR.tables:sortByPropDescendingAndSetTopItems(items, sorting_prop, function(item)
        return item.xray_type == 2 or item.xray_type == 4
    end)
end

function XrayModel:addLinkedItemsAsContextButtonsForViewer(buttons, needle_item, max_per_row, context_buttons_max_buttons, tapped_word)

    local sorted_items = views_data:getLinkedItems(needle_item)
    count = #sorted_items
    --* nothing to do if no linked items were found:
    if count == 0 then
        return
    end

    local remainder = count % max_per_row
    if remainder == 0 then
        remainder = max_per_row
    end
    local add_more_button = count > context_buttons_max_buttons

    --* first (top) row: fewer buttons (1–3) or full if divisible:
    local first_row = {}
    for i = 1, remainder do
        self:insertViewerContextButton(first_row, sorted_items[i], tapped_word)
    end
    local row_count = 1

    --* remaining rows: always max_per_row items:
    local index = remainder + 1
    while index <= count and index < context_buttons_max_buttons do
        local row = {}
        row_count = row_count + 1
        for j = 1, max_per_row do
            if sorted_items[index] then
                self:insertViewerContextButton(row, sorted_items[index], tapped_word)
            else
                self.garbage = j
            end
            index = index + 1
        end

        --* insert each new row at position 1 ABOVE previous rows:
        table.insert(buttons, 1, row)
    end
    table.insert(buttons, 1, first_row)
    if add_more_button then
        DX.b:addMoreButton(buttons, nil, {
            --* popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons - this prop to be consumed in ((XrayButtons#handleMoreButtonClick)):
            max_total_buttons_after_first_popup = context_buttons_max_buttons + 16,
            max_total_buttons = context_buttons_max_buttons,
            current_row = row_count,
            popup_buttons_per_row = max_per_row,
            source_items = sorted_items,
            title = " extra xray-items:",
            parent_dialog = KOR.ui,
            item_callback = function(citem)
                DX.d:viewLinkedItem(citem, tapped_word)
            end,
            item_hold_callback = function(citem, iicon)
                KOR.dialogs:textBox({
                    title = iicon .. citem.name,
                    info = self:getItemInfo(citem),
                    use_computed_height = true,
                })
            end,
        })
    end
end

--- @private
function XrayModel:insertViewerContextButton(row, item, tapped_word)
    local icon = DX.vd:getItemTypeIcon(item)
    local linked_item_hits
    if DX.m.current_series then
        linked_item_hits = has_items(item.series_hits) and " (" .. item.series_hits .. ")" or ""
    else
        linked_item_hits = has_items(item.book_hits) and " (" .. item.book_hits .. ")" or ""
    end
    table.insert(row, {
        text = item.name:lower() .. linked_item_hits .. KOR.icons.xray_link_bare .. icon,
        font_bold = item.is_bold,
        text_font_face = "x_smallinfofont",
        font_size = self.related_item_text_font_size,
        callback = function()
            DX.d:viewLinkedItem(item, tapped_word)
        end,
        hold_callback = function()
            KOR.dialogs:textBox({
                title = icon .. " " .. item.name,
                title_shrink_font_to_fit = true,
                info = self:getItemInfo(item),
                use_computed_height = true,
            })
        end,
    })
end

function XrayModel:toggleSortingMode()
    self.sorting_method = self.sorting_method == "name" and "hits" or "name"
    return self.sorting_method
end

--* change a suggested name like Joe Glass to Glass, Joe. If self.switch_first_and_sur_name is set to true:
--- @private
function XrayModel:switchFirstAndSurName(name)
    if not self.switch_first_and_sur_name or not name:match(" ") then
        return name
    end

    local name_parts = KOR.strings:split(name, " ", false)
    local parts = {}
    table.insert(parts, name_parts[2] .. ",")
    count = #name_parts
    for nr = 1, count do
        if nr ~= 2 then
            table.insert(parts, name_parts[nr])
        end
    end
    return table.concat(parts, " ")
end

function XrayModel:getCurrentItemsForView()
    return self.use_tapped_word_data and
        tapped_words:getCurrentListTabItems()
        or
        views_data:getCurrentListTabItems()
end

function XrayModel:getRealFirstOrSurName(item_or_item_name)
    if type(item_or_item_name) == "table" then
        item_or_item_name = item_or_item_name.name
    end
    if not item_or_item_name:match("[A-Z]") then
        return item_or_item_name
    end
    --* for names in format "[surname], [given name]", first remove comma:
    item_or_item_name = item_or_item_name:gsub(",", "")
    local parts = KOR.strings:split(item_or_item_name, " ")
    count = #parts
    for i = 1, count do
        if parts[i]:match("[A-Z]") then
            return parts[i]
        end
    end
end

-- #((XrayModel#activateListTabCallback))
function XrayModel.activateListTabCallback(tab_no)
    local self = DX.m

    if self:getActiveListTab() == tab_no then
        return false
    end
    if self.tab_display_counts[tab_no] == 0 then
        return false
    end

    self:setActiveListTab(tab_no)
    DX.d:showListWithRestoredArguments()

    return true
end

--* first try to read current series from the doc_props, then from EbookProps, or otherwise try to get if using the full_path of the current ebook:
--- @private
function XrayModel:setTitleAndSeries(full_path)
    local use_doc_props = true
    local current_series
    local current_title

    --! this reset is crucial to reset the data upon opening another ebook, when the previous ebook was part of a series:
    self.current_series = nil

    self.current_ebook_full_path = full_path or KOR.registry.current_ebook
    KOR.registry.current_ebook = self.current_ebook_full_path
    self.current_ebook_basename = KOR.filedirnames:basename(self.current_ebook_full_path)

    if use_doc_props and KOR.ui and KOR.ui.doc_props then
        current_series = KOR.ui.doc_props.series
        current_title = KOR.ui.doc_props.title
    end

    local is_non_series_book, series_has_changed
    if not current_series then
        current_series = DX.dl:getSeriesName()
        local doc_props = KOR.ui.doc_settings:readSetting("doc_props")
        current_title = doc_props.title or "???"
        if has_text(current_series) then
            self.current_series = current_series:gsub(" #%d+", "")
            self.current_title = current_title
            is_non_series_book = false
            series_has_changed = self.current_series ~= self.previous_series
            self.previous_series = self.current_series
            return series_has_changed, is_non_series_book
        end
    end
    if has_no_text(current_series) then
        series_has_changed = true
        is_non_series_book = true
        self.current_title = current_title
        self.previous_series = self.current_series
        return series_has_changed, is_non_series_book
    end

    is_non_series_book = false
    self.current_series = current_series:gsub(" #%d+", "")
    self.current_title = current_title
    series_has_changed = self.current_series ~= self.previous_series

    self.previous_series = self.current_series

    return series_has_changed, is_non_series_book
end

function XrayModel:getActiveListTab()
    return self.use_tapped_word_data and tapped_words.active_tapped_word_tab or self.active_list_tab
end

--! this method can also be called via ((XrayButtons#getListSubmenuButton)) > ((XrayDialogs#selectListTab))
function XrayModel:setActiveListTab(tab_no)
    if self.use_tapped_word_data then
        tapped_words:setProp("active_tapped_word_tab", tab_no)
        return
    end
    self.active_list_tab = tab_no
end

--* these counts will be used in ((XrayButtons#forListSubmenu)) > ((XrayButtons#getListSubmenuButton)):
function XrayModel:setTabDisplayCounts()
    if self.use_tapped_word_data then
        self.tab_display_counts = {
            #tapped_words.popup_items,
            #tapped_words.popup_persons,
            #tapped_words.popup_terms,
        }
    else
        self.tab_display_counts = {
            #views_data.items,
            #views_data.persons,
            #views_data.terms,
        }
    end

    return self.tab_display_counts
end

--* called from ((TextViewer#findCallback)):
function XrayModel:removeMatchReliabilityIndicators(subject)
    for _i, indicator in pairs(tapped_words.match_reliability_indicators) do
        subject = subject:gsub(indicator .. " ", "")
        self.garbage = _i
    end
    return subject:gsub(" " .. KOR.icons.arrow_bare .. ".+$", "")
end

--* compare usage of ((Strings#sortKeywords)) in ((XrayFormsData#convertFieldValuesToItemProps)):
function XrayModel:splitByCommaOrSpace(subject, add_singulars)
    local separated_by_commas = subject:match(",")
    local keywords
    local plural_keywords = {}
    --* in case of comma separated linkwords we want exact, non partly hits of these linkwords:
    keywords = separated_by_commas and KOR.strings:split(subject, ", *") or KOR.strings:split(subject, " +")
    local keyword
    count = #keywords
    for nr = 1, count do
        keyword = keywords[nr]
        keywords[nr] = keyword:gsub("%-", "%%-")
        if add_singulars and keyword:match("s$") then
            local plural = keyword:gsub("s$", "")
            table.insert(plural_keywords, plural)
        end
    end
    if #plural_keywords > 0 then
        return KOR.tables:merge(keywords, plural_keywords)
    end
    return keywords
end

--- @private
function XrayModel:hasExactMatch(haystack, needle)
    if haystack == needle then
        return true
    end
    --* lower case needles must be at least 4 characters long, but for names with upper case characters in them no such condition is required:
    local found = self:isValidNeedle(needle)
        and (haystack:match(needle) and not haystack:match(needle .. "%l+"))
    if found then
        return true
    end

    needle = KOR.strings:singular(needle, 1)
    return self:isValidNeedle(needle)
        and (haystack:match(needle)
        and not haystack:match(needle .. "%l+"))
end

function XrayModel:resetData(force_refresh, full_path)
    --! this one is crucial for when we view tab 2 or 3 in the list in one book and then change to another book; without this, the data for tab 1 of that new book would be set to the data of tab 2 or 3 in the previous book!:
    self.active_list_tab = 1

    self.items_prepared_for_basename = nil
    tapped_words:resetData(force_refresh)
    views_data:resetData()
    if force_refresh then
        self.current_ebook_full_path = full_path or KOR.registry.current_ebook
    end
    self.current_ebook_basename = KOR.filedirnames:basename(self.current_ebook_full_path)
    self.ebooks[self.current_ebook_basename] = {}
    if self.current_series then
        self.series[self.current_series] = {}
    end
end

function XrayModel:setProp(prop, value)
    self[prop] = value
end

function XrayModel:markItemsPreparedForCurrentEbook()
    self.items_prepared_for_basename = self.current_ebook_basename
end

return XrayModel
