--[[--
This extension is part of the Dynamic Xray plugin; its task is the management of data required for views in the Dynamic Xray module.

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

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = KOR:initCustomTranslations()

local DX = DX
local has_items = has_items
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local table = table
local tonumber = tonumber
local type = type

local count
--- @type XrayDataLoader data_loader
local data_loader
--- @type XrayModel parent
local parent
--- @type XrayTappedWords tapped_words
local tapped_words

--- @class XrayViewsData
local XrayViewsData = WidgetContainer:new {
    active_list_tab = 1,
    alias_indent = "  ",
    cached_hits = {},
    chapter_page_number_format = "<span style='font-size: 80%; color: #888888;'> [p.%1]</span>",
    chapter_props = {},
    chapters_start_pages_ordered = {},
    current_item = nil,
    current_tab_items = nil,
    filtered_count = 0,
    filter_state = "unfiltered",
    filter_string = "",
    filter_xray_types = nil,
    item_meta_info_template = "<tr><td><ul><li>%1</li></ul></td><td>&nbsp;</td><td>%2</td></tr>",
    item_table = { {}, {}, {} },
    --* items, persons and terms props act as some kind of temporary data store (not influenced by filters etc.) for the current ebook xray items:
    items = {},
    list_display_mode = "series", --* or "book"
    max_line_length = 64,
    new_item_hits = nil,
    persons = {},
    --* this prop can be modified with the checkbox in ((XrayDialogs#showFilterDialog)):
    search_simple = false,
    terms = {},
    type_matched = false,
    xray_type_description = "1 " .. KOR.icons.arrow_bare .. " " .. KOR.icons.xray_person_bare .. "  2 " .. KOR.icons.arrow_bare .. " " .. KOR.icons.xray_person_important_bare .. "  3 " .. KOR.icons.arrow_bare .. " " .. KOR.icons.xray_term_bare .. "  4 " .. KOR.icons.arrow_bare .. " " .. KOR.icons.xray_term_important_bare,
    --* for usage in ((XrayButtons#forItemEditorTypeSwitch)):
    xray_type_choice_labels = {
        T(" 1: %1 ", KOR.icons.xray_person_bare) .. _("person"),
        T(" 2: %1 ", KOR.icons.xray_person_important_bare) .. _("important person"),
        T(" 3: %1 ", KOR.icons.xray_term_bare) .. _("term"),
        T(" 4: %1 ", KOR.icons.xray_term_important_bare) .. _("important term"),
    },
    xray_type_icons = {
        KOR.icons.xray_person_bare .. " ",
        KOR.icons.xray_person_important_bare .. " ",
        KOR.icons.xray_term_bare .. " ",
        KOR.icons.xray_term_important_bare .. " ",
    },
    xray_type_icons_bare = {
        KOR.icons.xray_person_bare,
        KOR.icons.xray_person_important_bare,
        KOR.icons.xray_term_bare,
        KOR.icons.xray_term_important_bare,
    },
    --* toggle xray type to important (dark) or normal (light) icon:
    xray_type_icons_importance_toggle = {
        KOR.icons.xray_person_important_bare,
        KOR.icons.xray_person_bare,
        KOR.icons.xray_term_important_bare,
        KOR.icons.xray_term_bare,
    },
    --* toggle xray type from person to term or vice versa, while keeping the importance (dark or light icon) of the item:
    xray_type_icons_person_or_term_toggle = {
        KOR.icons.xray_term_bare,
        KOR.icons.xray_term_important_bare,
        KOR.icons.xray_person_bare,
        KOR.icons.xray_person_important_bare,
    },
}

--- @param xray_model XrayModel
function XrayViewsData:initDataHandlers(xray_model)
    parent = xray_model
    data_loader = DX.dl
    tapped_words = DX.tw
end

function XrayViewsData:resetData()
    self.chapter_props = {}
    self.chapters_start_pages_ordered = {}
    self.items = {}
    self.persons = {}
    self.terms = {}
    self.filtered_count = 0
    self.item_table_for_filter = {
        {}, --* all
        {}, --* persons
        {}, --* terms
    }
    --! crucial to prevent seemingly duplicated items upon adding new items:
    self.item_table = { {}, {}, {} }
    self.current_tab_items = nil
    self:resetAllFilters()
end

function XrayViewsData:resetAllFilters()
    self.filter_xray_types = nil
    self.filter_string = ""
    self.filter_state = "unfiltered"
end

function XrayViewsData:updateItemsTable(select_number, reset_item_table_for_filter)
    if reset_item_table_for_filter then
        DX.d:setProp("filter_state", "filtered")
        self.item_table_for_filter = {
            {}, --* all
            {}, --* persons
            {}, --* terms
        }
    end

    --! hotfix:
    if not parent.current_title then
        parent.current_title = "???"
    end
    if not parent.current_series then
        self.list_display_mode = "book"
    end
    local icon = self.list_display_mode == "series" and KOR.icons.xray_series_mode_bare or KOR.icons.xray_book_mode_bare
    if parent.use_tapped_word_data then
        --icon = KOR.icons.xray_link_bare
        icon = KOR.icons.xray_tapped_collection_bare
    end
    local source = self.list_display_mode == "series" and icon .. " " .. parent.current_series or icon .. " " .. parent.current_title

    --! don't reapply filters after item_table_for_filters has been populated; otherwise count for self.item would be reduced if we select tab no 2 (persons) or 3 (terms):
    if not parent.use_tapped_word_data and has_no_items(self.item_table_for_filter[1]) then
        self:applyFilters(select_number)
    end

    local title

    if self.filter_xray_types then
        --* when no xray_items found with the current filter:
        if self.filtered_count == 0 then
            self:handleNoItemsFoundWithFilter(_("no items of this type were found..."))
            return false
        else
            title = DX.d.filter_icon .. " " .. source
        end

    elseif self.filtered_count > 0 and self.filter_string and self.filter_string:len() >= 3 then
        --* when no xray_items found with the current filter:
        if #self.item_table == 0 then
            --select_number, title = self:noItemsFoundWithFilterHandler("niets gevonden met \"" .. self.filter_string .. "\"...")
            return nil, false
        else
            title = source .. " - " .. self.filter_string
        end
    else
        title = source
    end
    if #self.item_table == 0 then
        return {}, _("Xray items")
    end

    return self.item_table, title
end

--- @private
function XrayViewsData:handleNoItemsFoundWithFilter(message)
    KOR.messages:notify(message, 4)
    DX.c:resetFilteredItems()
end

function XrayViewsData:getItem(item_no)
    local subject_table = self:getCurrentListTabItems()
    return subject_table[item_no]
end

function XrayViewsData:setItemHits(item, args)
    --* store_book_hits - which triggers saving of book_hits to database - will only be true when current method is called from ((XrayController#saveNewItem)) or ((XrayFormsData#getAndStoreEditedItem)):
    local store_book_hits, for_display_mode
    if args then
        store_book_hits, for_display_mode = args.store_book_hits, args.for_display_mode
        if args.force_update then
            item.book_hits = nil
            item.series_hits = nil
        end
    end

    --* don't repopulate data needlessly:
    if not store_book_hits and (not args or not args.force_update) and item.chapter_query_done then
        return self:_returnCachedHits(item, for_display_mode)
    end

    local book_hits, chapter_hits = self:getAllTextHits(item)
    item.book_hits = book_hits
    item.chapter_hits = chapter_hits
    --* chapter_hits could be zero after query, so here we signal the current method that in that case the query shouldn't be repeated:
    item.chapter_query_done = true

    --* series_hits will dynamically be updated in the database:
    DX.ds.storeItemHits(item)
end

--- @private
function XrayViewsData:_returnCachedHits(item, for_display_mode)
    if not for_display_mode and self.list_display_mode == "series" then
        if not item.series_hits and item.book_hits then
            item.series_hits = item.book_hits
        end
        return item.series_hits
    end
    return item.book_hits, item.chapter_hits, item.series_hits
end

--- @private
function XrayViewsData:addItemToPersonsOrTerms(item)
    local item_copy = KOR.tables:shallowCopy(item)
    if item.xray_type <= 2 then
        table.insert(self.item_table[2], item_copy)
        item_copy.index = #self.persons + 1
        table.insert(self.persons, item_copy)
    else
        table.insert(self.item_table[3], item_copy)
        item_copy.index = #self.terms + 1
        table.insert(self.terms, item_copy)
    end
end

function XrayViewsData:repopulateItemsPersonsTerms(item)
    count = #self.items
    self.persons = {}
    self.terms = {}
    --* luckily we don't have to update TextViewer.paragraph_headings etc. (loaded from XrayUI data) here, because those take their info from XrayModel via ((XrayUI#getXrayItemsFoundInText)) > ((get xray_item for XrayUI))...

    for i = 1, count do
        --! watch out: this table MIGHT be filtered and in that have less items then self.item_table:
        if self.items[i] and self.items[i].id then
            --* item is not given when updating the tables after importing items via ((XrayController#doBatchImport)):
            if item and self.items[i].id == item.id then
                self.items[i] = item
                self.current_item = item
                self.items[i].callback = function()
                    UIManager:close(DX.d.xray_items_chooser_dialog)
                    DX.d:setProp("needle_name_for_list_page", item.name)
                    DX.d:showItemViewer(item, "called_from_list")
                end
            end
            self.items[i].index = i
            self:addItemToPersonsOrTerms(self.items[i])
        end
    end
end

--* only called from ((XrayController#saveUpdatedItem)), but not for newly added items; for those we call ((XrayViewsData#registerNewItem)):
function XrayViewsData:updateAndSortAllItemTables(item)
    self:repopulateItemsPersonsTerms(item)
    --* this call is also needed to add reliability and xray type icons:
    self:applyFilters()

    --* display the new item in its proper place in the list of items (placeImportantItemsAtTop wil also add corresponding "index" prop to each item):
    self.items = parent:placeImportantItemsAtTop(self.items, -1)
    self.item_table[1] = parent:placeImportantItemsAtTop(self.item_table[1], -1)
    if item.xray_type <= 2 then
        self.item_table[2] = parent:placeImportantItemsAtTop(self.item_table[2], -1)
        self.persons = parent:placeImportantItemsAtTop(self.persons, -1)
        return
    end
    self.item_table[3] = parent:placeImportantItemsAtTop(self.item_table[3], -1)
    self.terms = parent:placeImportantItemsAtTop(self.terms, -1)
end

--* compare ((XrayViewsData#registerUpdatedItem)) and ((XrayViewsData#updateAndSortAllItemTables)) for edited items:
function XrayViewsData:registerNewItem(new_item)
    --* by forcing refresh, we reload items from the database:
    self.initData("force_refresh")
    self.prepareData(new_item)
end

--* compare ((XrayTappedWords#getCurrentListTabItems)):
function XrayViewsData:getCurrentListTabItems(needle_item)
    --* this will sometimes be the case when we first call up a definition through ReaderHighlight, before calling the list of Xray items:
    if has_no_items(self.current_tab_items) then
        if has_items(self.item_table[1]) then
            self.items = KOR.tables:shallowCopy(self.item_table[1])
            self.persons = KOR.tables:shallowCopy(self.item_table[2])
            self.terms = KOR.tables:shallowCopy(self.item_table[3])
        else
            self.initData()
        end
    end

    --* this can occur after a filter reset from ((XrayController#resetFilteredItems)):
    if not self.filter_xray_types or parent.items_prepared_for_basename ~= parent.current_ebook_basename then
        --* index items and populate xray type tables self.persons and self.terms:
        self.prepareData()
    end
    local subject_tables = {
        self.items,
        self.persons,
        self.terms,
    }
    local items = subject_tables[parent.active_list_tab]

    --* prop "text" is generated in ((XrayViewsData#generateListItemText)):
    --* make sure items in the list have a sequence number; only done here, after prioritizing and sorting items, and not in ((XrayViewsData#generateListItemText)), because order could be changed by those actions:
    count = #items
    for i = 1, count do
        --* this can be the case when the item was only just added from the ebook text:
        if not items[i].text then
            items[i].text = self:generateListItemText(items[i])
        end
        items[i].text = KOR.strings:formatListItemNumber(i, items[i].text, "use_spacer")
        --* ensure that only the last edited or added item gets shown bold:
        items[i].bold = items[i].id == DX.fd.last_modified_item_id
        if DX.d.filter_state == "unfiltered" then
            items[i].index = i
        end
        if needle_item and needle_item.name == items[i].name then
            self.current_item = items[i]
            DX.fd:setViewerItemId(items[i])
        end
    end
    self.current_tab_items = items
    return items
end

function XrayViewsData:getNextItem(item)
    local next = item.index + 1
    --local subject_table = self:getCurrentListItems()
    local subject_table = self.current_tab_items
    if next > #subject_table then
        next = 1
    end

    self.current_item = subject_table[next]
    --? for some reason this index here was always 1, so now we correct that:
    self.current_item.index = next
    DX.fd:setViewerItemId(self.current_item)
    return self.current_item
end

function XrayViewsData:getPreviousItem(item)
    local previous = item.index - 1
    --local subject_table = self:getCurrentListItems()
    --* self.current_tab_items was populated from ((XrayDialogs#initListDialog))
    local subject_table = self.current_tab_items
    if previous < 1 then
        previous = #subject_table
    end

    self.current_item = subject_table[previous]
    --? for some reason this index here was always 1, so now we correct that:
    self.current_item.index = previous
    DX.fd:setViewerItemId(self.current_item)
    return self.current_item
end

--- @private
function XrayViewsData:setChapterHits(chapter_stats, chapters_ordered, chapter_title)
    local chapter_props = self.chapter_props[chapter_title]

    if not chapter_stats[chapter_title] then
        chapter_stats[chapter_title] = { count = 1, index = chapter_props.index, start_page = chapter_props.start_page }

        --* insert chapter in the right place in chapters_ordered
        local inserted = false
        count = #chapters_ordered
        local existing_chapter
        for i = 1, count do
            existing_chapter = chapters_ordered[i]
            if chapter_stats[existing_chapter].index > chapter_props.index then
                table.insert(chapters_ordered, i, chapter_title)
                table.insert(self.chapters_start_pages_ordered, i, chapter_stats[chapter_title].start_page)
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(chapters_ordered, chapter_title)
            table.insert(self.chapters_start_pages_ordered, chapter_stats[chapter_title].start_page)
        end
    else
        chapter_stats[chapter_title].count = chapter_stats[chapter_title].count + 1
    end
end

function XrayViewsData:getAllTextHits(search_text_or_item)

    local aliases = {}
    local short_names = {}
    local main_name = search_text_or_item

    if type(search_text_or_item) == "table" then
        main_name = search_text_or_item.name
        if has_text(search_text_or_item.aliases) then
            aliases = parent:splitByCommaOrSpace(search_text_or_item.aliases)
        end
        if has_text(search_text_or_item.short_names) then
            short_names = parent:splitByCommaOrSpace(search_text_or_item.short_names)
        end
    end

    --* build unified list of search terms:
    local search_terms = { main_name }
    count = #aliases
    for i = 1, count do
        table.insert(search_terms, aliases[i])
    end
    count = #short_names
    for i = 1, count do
        table.insert(search_terms, short_names[i])
    end

    --* initialize containers
    local chapter_stats = {}
    local chapters_ordered = {}

    --* process all search terms (main + aliases):
    local total_count = 0
    count = #search_terms
    for s = 1, count do
        total_count = self:getChapterHitsPerTerm(search_terms[s], chapter_stats, chapters_ordered, total_count)
    end

    --* chapter_info used in 4 places, to populate the chapter_hits prop of items:
    local chapter_info
    local chapters_found = #chapters_ordered
    if chapters_found > 0 then
        local present_as_table = not DX.s.is_mobile_device
        local chapter_items = {}
        local max_hits = 0
        -- #((generate chapter info))
        for i = 1, chapters_found do
            max_hits = self:addChapterToChapterStats(chapters_ordered, chapter_items, chapter_stats, present_as_table, i, max_hits)
        end
        chapter_info = self:generateChaptersListHtml(chapter_items, present_as_table, max_hits)
    end

    return total_count, chapter_info
end

--- @private
local function getNameVariants(haystack_name)
    local uc = KOR.strings:ucfirst(haystack_name, "force_only_first")
    local is_lower_needle = not haystack_name:match("[A-Z]")

    return uc, is_lower_needle
end

--- @private
function XrayViewsData:_doStrongMatchCheck(needle_item, matcher, args, t, for_relations)
    local tapped_word = args.tapped_word
    local is_exists_check = args.is_exists_check
    local tapped_ok, is_same_item, exists

    local item = self.items[t]
    local needle_name = needle_item.name
    local haystack_name = item.name
    local uc, is_lower_needle = getNameVariants(haystack_name)

    --* for checks whether an item exists we use very strict matching:
    exists = is_exists_check and
        (
        haystack_name == needle_name
        or haystack_name:match("^" .. needle_name .. "[, ]")
        or haystack_name:match(" " .. needle_name .. "[, ]")
        or haystack_name:match(" " .. needle_name .. "$")
        )
    if exists then
        --* needle_item, item_was_upgraded, needle_matches_fullname:
        return item, true, true
    end

    tapped_ok = not tapped_word
        or tapped_word == haystack_name
        or tapped_word == haystack_name
        or (is_lower_needle and tapped_word == uc)

    is_same_item = needle_item.index == item.index
        or needle_item.name == haystack_name
        --* plural:
        or haystack_name:match("^" .. matcher .. "s$")
        or (is_lower_needle and uc:match("^" .. matcher .. "s$"))

    if tapped_ok and is_same_item then
        if for_relations then
            item.reliability_indicator = tapped_words.match_reliability_indicators.full_name
            return { item }, true, true
        end
        return item, true, true
    end
end

--- @private
function XrayViewsData:_doWeakMatchCheck(t, needle, partial_matches, for_relations)
    local item = self.items[t]

    local haystack, uc_haystack, is_lower_haystack, indicator
    for i = 1, 2 do
        haystack = i == 1 and item.name or item.aliases
        uc_haystack, is_lower_haystack = getNameVariants(haystack)
        indicator = self:haystackItemPartlyMatches(needle, haystack, uc_haystack, is_lower_haystack)
        if indicator then
            if for_relations then
                item.reliability_indicator = indicator
            end
            table.insert(partial_matches, item)
            --* item_was_upgraded:
            return true
        end
    end
end

--* upgrade a placeholder needle_item derived from tapped text (needle_item.name) in the ebook to a regular xray item, if the name or aliases of that xray item match the tapped text; but this method also called from xray item forms:
--- @return table, boolean, boolean upgraded_item, item_was_upgraded, needle_matches_fullname
function XrayViewsData:upgradeNeedleItem(needle_item, args)
    if not args.is_exists_check and (not args.include_name_match or has_no_text(needle_item.name)) then
        return needle_item, false, false
    end
    local for_relations = args.for_relations
    local matcher = needle_item.name:gsub("%-", "%%-")
    local partial_matches = {}
    local item_was_upgraded = false
    local needle_matches_fullname, upgraded_needle_item
    count = #self.items

    for t = 1, count do
        upgraded_needle_item, item_was_upgraded, needle_matches_fullname = self:_doStrongMatchCheck(needle_item, matcher, args, t, for_relations)
        if item_was_upgraded then
            return upgraded_needle_item, item_was_upgraded, needle_matches_fullname
        end
    end

    for t = 1, count do
        item_was_upgraded = self:_doWeakMatchCheck(t, needle_item.name, partial_matches, for_relations)
        if item_was_upgraded then
            break
        end
    end

    if #partial_matches > 0 then
        needle_matches_fullname = false
        item_was_upgraded = true
        if for_relations then
            return partial_matches, item_was_upgraded, needle_matches_fullname
        end
        return partial_matches[1], true, needle_matches_fullname
    end

    return needle_item, item_was_upgraded, needle_matches_fullname
end

--- @private
function XrayViewsData:addMenuItemToItemTables(menu_item)
    table.insert(self.item_table_for_filter[1], menu_item)
    if menu_item.xray_type <= 2 then
        table.insert(self.item_table_for_filter[2], menu_item)
    else
        table.insert(self.item_table_for_filter[3], menu_item)
    end
end

--- @private
function XrayViewsData:applyTextFilters(item, linked_item_needles, hits_registry)

    local score, reliability_indicator
    local matched = true
    --* only during first loop we populate linked_item_needles, to search for items LINKED to main item; this search will be executed in ((XrayViewsData#populateItemTableFromLinkWords)):
    local is_first_loop = linked_item_needles
    local is_loop_for_linked_items = not is_first_loop

    if self.type_matched and has_text(self.filter_string) then

        if self.search_simple then
            score, reliability_indicator = tapped_words:doSimpleSearchScoreMatch(item)
        else
            score, reliability_indicator = tapped_words:doScoreMatch(item)
        end
        matched = has_items(score) and (is_first_loop or score > 20)
        if is_loop_for_linked_items and matched and not self.search_simple then
            reliability_indicator = tapped_words.match_reliability_indicators.linked_item
        end

        --* here linked_item_needles is populated, IF not self.search_simple and we are in the first loop:
        hits_registry = self:updateFilteredCountUponTextMatch(item, linked_item_needles, matched, score, is_first_loop, hits_registry)
    end

    return matched, reliability_indicator, hits_registry
end

--* self.filtered_count can also be increased in ((XrayViewsData#updateFilteredCountUponTextMatch)):
--- @private
function XrayViewsData:applyTypeFilters(item)
    if not self.filter_xray_types then
        return true
    end

    local icon_no
    count = #self.filter_xray_types
    for c = 1, count do
        icon_no = self.filter_xray_types[c]
        if icon_no == item.xray_type then
            self.filtered_count = self.filtered_count + 1
            return true
        end
    end
end

--* self.filtered_count can also be increased in ((XrayViewsData#applyTypeFilters)):
--- @private
--- @param item table
function XrayViewsData:updateFilteredCountUponTextMatch(item, linked_item_needles, matched, score, is_first_loop, hits_registry)
    --* add to filtered sets:
    if matched then
        if is_first_loop and score > 20 and item.linkwords then
            table.insert(linked_item_needles, item.linkwords)
        end

        if is_first_loop then
            hits_registry = hits_registry .. " " .. item.name
        end
        self.filtered_count = self.filtered_count + 1
    end
    return hits_registry
end

--- @private
function XrayViewsData:filterAndAddItemToItemTables(items, n, search_needles, linked_item_needles, hits_registry)

    local list_item, matched, reliability_indicator

    local item = items[n]
    self.type_matched = self:applyTypeFilters(item)

    matched, reliability_indicator, hits_registry = self:applyTextFilters(item, linked_item_needles, hits_registry)

    local insert_item = (not search_needles and not self.filter_xray_types) or (search_needles and matched) or (self.filter_xray_types and self.type_matched)

    --* now: build menu row if this subject list is active and (no filter or matched)
    if insert_item then
        list_item = {
            text = self:generateListItemText(item, reliability_indicator),
            id = item.id,
            name = item.name,
            description = item.description,
            xray_type = item.xray_type,
            short_names = item.short_names,
            linkwords = item.linkwords,
            aliases = item.aliases,
            book_hits = item.book_hits,
            series_hits = item.series_hits,
            chapter_hits = item.chapter_hits,
            series = parent.current_series,
            mentioned_in = item.mentioned_in,
            index = #self.item_table_for_filter[1] + 1,
            callback = function()
                UIManager:close(DX.d.xray_items_chooser_dialog)
                DX.d:setProp("needle_name_for_list_page", item.name)
                DX.d:showItemViewer(item, "called_from_list")
            end
        }

        self:addMenuItemToItemTables(list_item)
    end
    return hits_registry
end

--* loop for items which had full or partial matching AND had linkwords; now we search for those linkwords, to get all items linked to these main items:
--- @private
function XrayViewsData:populateItemTableFromLinkWords(linked_item_needles, items, hits_registry)

    if #linked_item_needles == 0 then
        return
    end

    linked_item_needles = table.concat(linked_item_needles, " ")
    local needles = KOR.strings:split(linked_item_needles, " ")
    local purged = {}
    count = #needles
    for i = 1, count do
        if not hits_registry:find(needles[i], 1, true) then
            table.insert(purged, needles[i])
        end
    end
    needles = purged

    count = #items
    for n = 1, count do
        self:filterAndAddItemToItemTables(items, n, needles)
    end
end

--* ((XrayViewsData#upgradeNeedleItem)) has to be called in the caller context, before calling getRelatedItems:
function XrayViewsData:getLinkedItems(needle_item)

    --* don't return here when needle_item has no linkwords, because we also search in the other xray items, to see if THEIR linkwords match to the name of the needle_item...
    local linked_items, linked_names_index = {}, {}
    local linkwords = parent:splitByCommaOrSpace(needle_item.linkwords, "add_singulars") or {}

    local haystack_item
    count = #self.items
    for i = 1, count do
        haystack_item = self.items[i]
        --* add items which are linked by the keywords in needle_item:
        self:addLinkedItem(1, needle_item, haystack_item, linkwords, linked_names_index, linked_items)
        if not linked_names_index[haystack_item.name] and has_text(haystack_item.linkwords) then
            --* add items which link via THEIR linkwords to the needle_item:
            local other_linkwords = parent:splitByCommaOrSpace(haystack_item.linkwords, "add_singulars")
            self:addLinkedItem(2, needle_item, haystack_item, other_linkwords, linked_names_index, linked_items)
        end
    end
    if #linked_items > 1 then
        linked_items = parent:placeImportantItemsAtTop(linked_items, -1)
    end
    return linked_items, linked_names_index
end

--- @private
function XrayViewsData:addLinkedItem(stage, needle_item, compare_item, linkwords, linked_names_index, linked_items)
    if compare_item.name == needle_item.name then
        return
    end
    local linkword, needle, aliases_needle
    count = #linkwords
    for i = 1, count do
        linkword = linkwords[i]
        linkword = linkword:gsub("%-", "%%-")
        needle = stage == 1 and compare_item.name or needle_item.name
        --* we also check for matches with aliases of xray items:
        aliases_needle = stage == 1 and compare_item.aliases or needle_item.aliases
        if (parent:hasExactMatch(needle, linkword) or parent:hasExactMatch(aliases_needle, linkword)) and not linked_names_index[compare_item.name] then
            table.insert(linked_items, compare_item)
            linked_names_index[compare_item.name] = true
            if stage == 2 then
                break
            end
        end
    end
end

function XrayViewsData:getItemIndexById(id)
    local items = self:getCurrentListTabItems()
    count = #items
    for i = 1, count do
        if items[i].id == id then
            return items[i].index
        end
    end
end

--- @private
function XrayViewsData:addAliasesInfo(info, item, has_aliases, has_linkwords)
    if not has_aliases then
        return info
    end

    local suffix = ""
    if has_linkwords then
        suffix = item.aliases:match(" ") and " " or "     "
    end
    if item.linkwords:match(" ") then
        suffix = suffix .. "   "
    end
    local noun = item.aliases:match(" ") and _("aliases: ") or _("alias: ")
    local aliases = noun .. suffix .. item.aliases
    aliases = KOR.strings:splitLinesToMaxLength(aliases, self.max_line_length, self.alias_indent)

    return info .. "\n\n" .. aliases
end

--- @private
function XrayViewsData:addLinkWordsInfo(info, item, has_linkwords, has_aliases)
    if not has_linkwords then
        return info
    end

    local noun = item.linkwords:match(" ") and _("link terms: ") or _("link term: ")
    local linkwords = noun .. item.linkwords
    local info_spacer = has_aliases and "\n" or "\n\n"
    linkwords = KOR.strings:splitLinesToMaxLength(linkwords, self.max_line_length, self.alias_indent)

    return info .. info_spacer .. linkwords
end

--- @private
function XrayViewsData:addMentionedInInfo(info, item, mentioned_in, has_aliases, has_linkwords)
    local mentioned_in_multiple_books = item.book_hits and item.series_hits and item.book_hits ~= item.series_hits
    if not mentioned_in_multiple_books or not mentioned_in then
        return info
    end
    local info_spacer = (has_aliases or has_linkwords) and "\n" or "\n\n"
    --* "|" was used for GROUP_CONCAT in query:
    mentioned_in = KOR.strings:split(mentioned_in, "|")

    return info .. info_spacer .. table.concat(mentioned_in, "\n")
end

function XrayViewsData:getItemInfo(item, ucfirst)
    local info = ucfirst and KOR.strings:ucfirst(item.description) .. "\n" or "\n" .. item.description .. "\n"

    local has_aliases, has_linkwords, mentioned_in = has_text(item.aliases), has_text(item.linkwords), has_text(item.mentioned_in)
    info = self:addAliasesInfo(info, item, has_aliases, has_linkwords)
    info = self:addLinkWordsInfo(info, item, has_linkwords, has_aliases)

    return self:addMentionedInInfo(info, item, mentioned_in, has_aliases, has_linkwords)
end

--- @private
--- @param meta_info_html table
function XrayViewsData:addAliasesHtml(meta_info_html, item)
    if has_no_text(item.aliases) then
        return
    end
    table.insert(meta_info_html, T(self.item_meta_info_template, item.aliases:match(" ") and "Aliassen:" or "Alias:", item.aliases))
end

--- @private
--- @param meta_info_html table
function XrayViewsData:addLinkWordsHtml(meta_info_html, item)
    if has_no_text(item.linkwords) then
        return
    end
    table.insert(meta_info_html, T(self.item_meta_info_template, item.linkwords:match(" ") and "Link-termen:" or "Link-term:", item.linkwords))
end

--- @private
--- @param meta_info_html table
function XrayViewsData:addMentionedInHtml(meta_info_html, item)
    local mentioned_in_multiple_books = item.book_hits and item.series_hits and item.book_hits ~= item.series_hits
    if has_no_text(item.mentioned_in) or not mentioned_in_multiple_books then
        return
    end
    --* "|" was used for GROUP_CONCAT in query:
    local list = KOR.strings:split(item.mentioned_in, "|")
    list = table.concat(list, "<br>")
    table.insert(meta_info_html, T(self.item_meta_info_template, _("Mentioned in") .. ":", list))
end

--- @private
--- @param meta_info_html table
function XrayViewsData:addHitsHtml(meta_info_html, item)
    if parent.current_series and item.series_hits then
        table.insert(meta_info_html, T(self.item_meta_info_template, _("Hits in series") .. ":", tonumber(item.series_hits)))
    end
    if item.book_hits then
        table.insert(meta_info_html, T(self.item_meta_info_template, _("Hits in book") .. ":", tonumber(item.book_hits)))
    end
end

function XrayViewsData:getItemInfoHtml(item, ucfirst)
    local separator = "<br>"
    local info = ucfirst and KOR.strings:ucfirst(item.description) .. separator or separator .. item.description .. separator

    local meta_info_html = { "<table style='margin-top: 2.5em'>" }
    self:addAliasesHtml(meta_info_html, item)
    self:addLinkWordsHtml(meta_info_html, item)
    self:addHitsHtml(meta_info_html, item)
    self:addMentionedInHtml(meta_info_html, item)
    if #meta_info_html > 1 then
        table.insert(meta_info_html, "</table>")
        info = info .. table.concat(meta_info_html, "")
    end

    --* only return general info:
    if not item.chapter_hits then
        return info
    end

    --* if chapter_hits also available, return general info AND chapter_hits:

    --* prop chapter_hits - if determined - will have the chapter info in html format:
    --* since we want to view our info tabbed, we return two values in case of html display and don't concatenate them:
    return info, T(_("<span style='font-size: 90%'>An %1 marks the highest number of hits in the current book...</span>"), KOR.icons.arrow_left_bare) .. item.chapter_hits
end

--* this info will be consumed for the info panel in ((HtmlBox#generateScrollWidget)):
--- @private
function XrayViewsData:getItemInfoText(item)
    --* the reliability_indicators were added in ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)):
    local reliability_indicator = item.reliability_indicator and item.reliability_indicator .. " " or ""
    local sub_info_separator = "\n     "
    local info = "\n" .. reliability_indicator .. item.name .. ": " .. item.description .. "\n"
    if has_text(item.aliases) then
        info = info .. sub_info_separator .. KOR.icons.xray_alias_bare .. " " .. item.aliases
    end
    if has_text(item.linkwords) then
        return info .. sub_info_separator .. KOR.icons.xray_link_bare .. " " .. item.linkwords
    end
    return info
end

function XrayViewsData:generateInfoPanelTextIfMissing(side_buttons, info_panel_text)
    if info_panel_text or not side_buttons or not side_buttons[1] then
        return info_panel_text
    end

    local first_item = side_buttons[1][1]
    --* this prop was set in ((XrayPageNavigator#markItem)):
    info_panel_text = self.first_info_panel_text or self:getItemInfoText(first_item)
    self.first_info_panel_text = info_panel_text
    self.first_info_panel_item_name = first_item.name
    side_buttons[1][1].text = KOR.icons.active_tab_bare .. side_buttons[1][1].text

    return info_panel_text
end

function XrayViewsData:getItemTypeIcon(item, bare)
    item.xray_type = tonumber(item.xray_type)
    if not item.xray_type or item.xray_type < 1 or item.xray_type > 4 then
        item.xray_type = 1
    end
    if bare then
        return self.xray_type_icons_bare[item.xray_type]
    end
    return self.xray_type_icons[item.xray_type]
end

--* generate list item texts for ((XrayDialogs#showList)):
function XrayViewsData:generateListItemText(item, reliability_indicator)

    local icon = self:getItemTypeIcon(item)

    --* in series mode we want the list to show the total count of items for the whole series, instead of only for the current book:
    local hits = self.list_display_mode == "series" and item.series_hits or item.book_hits
    local hits_info = has_items(hits) and " (" .. hits .. ")" or ""

    if not reliability_indicator then
        reliability_indicator = ""
    end

    --* we don't add sequence number here, because that will only be done after prioritizing and sorting items in the list, at end of ((XrayViewsData#getCurrentListTabItems)):
    return reliability_indicator .. icon .. item.name .. hits_info .. ": " .. KOR.strings:lcfirst(item.description)
end

--- @private
function XrayViewsData:isFilterActive()
    return has_text(parent.filter_string) or parent.filter_xray_types
end

--* filter list by text; compare finding matching items for tapped text ((TAPPED_WORD_MATCHES)) & ((XrayTappedWords#getXrayItemAsDictionaryEntry)):
--- @private
function XrayViewsData:filterAndPopulateItemTables(data_items)
    local filter_active = self:isFilterActive()
    self.item_table_for_filter = {
        {}, --* all
        {}, --* persons
        {}, --* terms
    }
    self.filtered_count = 0

    local needles
    if has_text(self.filter_string) then
        needles = KOR.strings:getKeywordsForMatchingFrom(self.filter_string, "no_lower_case")
    end

    local linked_item_needles = {}
    local items = data_items[self.active_list_tab]
    local hits_registry = ""
    count = #items
    for n = 1, count do
        hits_registry = self:filterAndAddItemToItemTables(items, n, needles, linked_item_needles, hits_registry)
    end

    --* loop for items which had full or partial matching AND had linkwords; now we search for those linkwords, to get all items linked to these main items:
    if not self.search_simple then
        self:populateItemTableFromLinkWords(linked_item_needles, items, hits_registry)
    end

    DX.d:notifyFilterResult(filter_active, self.filtered_count)
    if filter_active and self.filtered_count == 0 then
        self.filter_string = ""
    end

    --* prioritizing important items by placing them at the top and sorting the items will be done later via ((XrayViewsData#prepareData)) > ((XrayViewsData#indexItems))..
    if not filter_active or (filter_active and self.filtered_count > 0) then
        --* self.items updated here through this method for debugging purposes:
        self:setItems(self.item_table_for_filter[1])
        self.persons = self.item_table_for_filter[2]
        self.terms = self.item_table_for_filter[3]
    end
end

--- @private
function XrayViewsData:addChapterToChapterStats(chapters_ordered, chapter_items, chapter_stats, present_as_table, i, max_hits)
    local chapter_start_page
    local chapter = chapters_ordered[i]
    --* in the viewer this will be a list under an ul; using ul for this sublist yields ugly big open bullets, so here no list tags used:
    --* chapter_stats[chapter].count was set in ((XrayViewsData#setChapterHits)):
    if present_as_table then
        chapter_start_page = chapter_stats[chapter].start_page
                and T(self.chapter_page_number_format, chapter_stats[chapter].start_page)
                or ""
        table.insert(chapter_items, "<tr><td>" ..
                i .. ". <i>" .. chapter .. "</i>" .. chapter_start_page .. "</td><td>&nbsp;&nbsp;</td><td>" .. chapter_stats[chapter].count .. "</td></tr>")
    else
        table.insert(chapter_items, chapter .. " " .. KOR.icons.arrow_bare .. " " .. chapter_stats[chapter].count .. "<br>")
    end
    if chapter_stats[chapter].count > max_hits then
        max_hits = chapter_stats[chapter].count
    end
    return max_hits
end

--- @private
function XrayViewsData:generateChaptersListHtml(chapter_items, present_as_table, max_hits)
    local chapter_info = table.concat(chapter_items, "")
    local max_hit_indicator = max_hits .. " " .. KOR.icons.arrow_left_bare

    if present_as_table then
        --* wrap table around the info:
        chapter_info = "<table><tr><td><b>chapter</b></td><td>&nbsp;</td><td><b>hits</b></td></tr>" .. chapter_info .. "</table>"
        --* mark the highest hits with a bullet:
        return chapter_info:gsub("<td>" .. max_hits .. "</td>", "<td>" .. max_hit_indicator .. "</td>")
    end

    return chapter_info:gsub(max_hits .. "<br>", max_hit_indicator .. "<br>")
end

--* the chapter data retrieved here are generated for display in ((XrayViewsData#getAllTextHits)) caller of current method > ((generate chapter info)):
--- @private
function XrayViewsData:getChapterHitsPerTerm(term, chapter_stats, chapters_ordered, total_count)
    local document = KOR.ui.document
    local results, needle, case_insensitive, last_chapter_title, last_chapter_index
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(term)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)

    if has_no_items(results) then
        return total_count
    end

    local result_count = #results
    total_count = total_count + result_count
    for i = 1, result_count do
        last_chapter_title = KOR.toc:getTocLastChapterInfo(results[i].start)

        --* the cached chapter_props will only be reset in ((XrayController#resetDynamicXray)), so when opening another ebook:
        if not self.chapter_props[last_chapter_title] then
            last_chapter_index = KOR.toc:getAccurateTocIndexByXPointer(results[i].start)

            self.chapter_props[last_chapter_title] = {
                index = last_chapter_index,
                start_page = KOR.toc:getChapterStartPage(results[i].start),
            }
        end

        if has_text(last_chapter_title) then
            self:setChapterHits(chapter_stats, chapters_ordered, last_chapter_title)
        end
    end

    return total_count
end

function XrayViewsData:resultsPageGreaterThan(results, current_page, next_page)
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

function XrayViewsData:resultsPageSmallerThan(results, current_page, prev_page)
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

function XrayViewsData:getNextPageHitForTerm(item, current_page)
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

function XrayViewsData:getPreviousPageHitForTerm(item, current_page)
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

--* called from ((XrayViewsData#prepareData)):
--- @private
function XrayViewsData:indexItems(new_item)
    --* here we set top items only for self.terms, because later on in ((XrayViewsData#populateTypeTables)) self.persons and self.terms will be populated from self.items:

    local sorting_prop = "name"
    if parent.sorting_method == "hits" and self.list_display_mode == "series" then
        sorting_prop = "series_hits"
    elseif parent.sorting_method == "hits" and self.list_display_mode == "book" then
        sorting_prop = "book_hits"
    end
    self.items = KOR.tables:sortByPropDescendingAndSetTopItems(self.items, sorting_prop, function(xray_item)
        return xray_item.xray_type == 2 or xray_item.xray_type == 4
    end)
    count = #self.items
    for nr = 1, count do
        local current = nr
        self.items[nr].index = nr

        if new_item and new_item.name == self.items[nr].name then
            new_item = self.items[nr]
        end
        --! this statement is crucial to ensure items have a callback always:
        self.items[current].callback = function()
            DX.d:showItemViewer(self.items[current])
        end
    end

    return new_item
end

-- #((XrayViewsData#initData))
--- @private
function XrayViewsData.initData(force_refresh, override_mode, full_path)

    local self = DX.vd
    self:setProp("parent", DX.m)
    if force_refresh then
        parent:resetData(force_refresh)
    end
    parent:setProp("current_ebook_full_path", full_path or KOR.registry.current_ebook)
    parent:setProp("current_ebook_basename", KOR.filedirnames:basename(full_path or KOR.registry.current_ebook))

    --* force book display mode for books which are not part of a series:
    --* DX.m.current_series should have been set, when list_display_mode is "series", from the doc_props in ((XrayController#resetDynamicXray)) > ((XrayModel#setTitleAndSeries)):
    if not parent.current_series then
        override_mode = "book"
    end
    local mode = override_mode or self.list_display_mode
    data_loader:loadAllItems(mode, force_refresh)
end

--- @private
function XrayViewsData:applyFilters()
    --* self.items etc. were populated in (())
    local xray_items, persons, terms = self.items or {}, self.persons or {}, self.terms or {}
    self.filtered_count = 0
    if #xray_items > 0 then
        --* in these calls self.filtered_count must be updated:
        local subjects = {
            xray_items,
            persons,
            terms,
        }
        self:filterAndPopulateItemTables(subjects)
    end
end

function XrayViewsData:findChapterTitleByChapterNo(chapter_html, chapter_no)
    local td = chapter_html:match(T("<td>%1%..-</td>", chapter_no))
    if not td then
        return
    end
    --* extract title, enclosed in i elements:
    local chapter_title = td:match("<i>(.-)</i>")
    if chapter_title then
        return chapter_title
    end
end

-- #((XrayViewsData#prepareData))
function XrayViewsData.prepareData(new_item)
    local self = DX.vd
    new_item = self:indexItems(new_item)
    self:populateTypeTables()
    DX.m:markItemsPreparedForCurrentEbook()
    DX.m:setTabDisplayCounts()

    return new_item
end

--- @private
function XrayViewsData:populateTypeTables()
    self.terms = {}
    self.persons = {}
    local xray_item
    count = #self.items
    for i = 1, count do
        xray_item = self.items[i]
        if xray_item.xray_type <= 2 then
            table.insert(self.persons, xray_item)
        else
            table.insert(self.terms, xray_item)
        end
    end
end

--* compare ((XrayViewsData#registerNewItem)):
function XrayViewsData:registerUpdatedItem(updated_item)
    --* these props nr, icons and text are needed so we get no crash because of one of these props missing when generating list items in ((XrayViewsData#generateListItemText)) and ((Strings#formatListItemNumber)):
    updated_item.nr = updated_item.index
    local old_icons = self.items[updated_item.index].icons
    updated_item.icons = old_icons or ""
    updated_item.text = self:generateListItemText(updated_item)

    --! when saving items from the tapped words popup, the index and nr props have to be retrieved from the non tapped word items, otherwise these props would be wrong and the normal, non tapped word items list would show seemingly duplicated items (overwriting another item with the same index):
    if DX.m.use_tapped_word_data then
        updated_item.index = self:getItemIndexById(updated_item.id)
        updated_item.nr = updated_item.index
    end
    self.current_item = updated_item
    self.items[updated_item.index] = updated_item

    self:updateAndSortAllItemTables(updated_item)
end

function XrayViewsData:setItems(items)
    self.items = items
end

--- @private
function XrayViewsData:isSingularOrPluralMatch(needle, haystack_name)
    return needle == haystack_name or needle == haystack_name .. "s"
end

--- @private
function XrayViewsData:haystackItemPartlyMatches(needle, haystack, uc_haystack, is_lower_haystack)
    local parts = KOR.strings:split(haystack, " +")
    local uc_parts
    if is_lower_haystack then
        uc_parts = KOR.strings:split(uc_haystack, " +")
    end
    count = #parts
    for i = 1, count do
        if self:isSingularOrPluralMatch(needle, parts[i]) or (is_lower_haystack and self:isSingularOrPluralMatch(needle, uc_parts[i])) then
            if i == 1 then
                return tapped_words.match_reliability_indicators.first_name
            elseif i == count then
                return tapped_words.match_reliability_indicators.last_name
            end
            return tapped_words.match_reliability_indicators.partial_match
        end
    end
    return false
end

function XrayViewsData:setFilterTypes(filter_types)
    self.filter_xray_types = filter_types
end

function XrayViewsData:setProp(prop, value)
    self[prop] = value
    if prop == "filter_string" then
        self.filter_state = has_text(value) and "filtered" or "unfiltered"
    end
end

return XrayViewsData
