
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = KOR:initCustomTranslations()

local DX = DX
local has_content = has_content
local has_items = has_items
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local table = table
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber
local type = type

local count, count2
--- @type XrayDataLoader data_loader
local data_loader
--- @type XrayModel parent
local parent
--- @type XrayTappedWords tapped_words
local tapped_words

--- @class XrayViewsData
local XrayViewsData = WidgetContainer:new{
    active_list_tab = 1,
    alias_indent = "  ",
    chapter_page_number_format = "<span style='font-size: 80%; color: #888888;'> [p.%1]</span>",
    chapter_props = {},
    chapters_start_pages_ordered = {},
    current_item = nil,
    current_tab_items = nil,
    filtered_count = 0,
    filter_string = "",
    filter_tag = nil,
    filter_xray_types = nil,
    item_meta_info_template = "<tr><td><ul><li>%1</li></ul></td><td>&nbsp;</td><td>%2</td></tr>",
    item_table = { {}, {}, {} },
    item_table_for_filter = { {}, {}, {} },
    --* items, persons and terms props act as some kind of temporary data store (not influenced by filters etc.) for the current ebook xray items:
    items = {},
    list_display_mode = "series", --* or "book"
    new_item_hits = nil,
    persons = {},
    --* this prop can be modified with the checkbox in ((XrayDialogs#showFilterDialog)):
    search_simple = false,
    separator = " " .. KOR.icons.arrow_bare .. " ",
    terms = {},
    type_matched = false,
    word_end = "%f[%A]",
    word_start = "%f[%a]",
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
    --! crucial to prevent seemingly duplicated items upon adding new items:
    self.item_table = { {}, {}, {} }
    self.item_table_for_filter = {
        {}, --* all
        {}, --* persons
        {}, --* terms
    }
    self.current_tab_items = nil
    self:resetAllFilters()
end

function XrayViewsData:resetAllFilters()
    self.filter_xray_types = nil
    self.filter_string = ""
    self.filter_tag = nil
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
        --* when no xray_items found with the current xray_type filter:
        if self.filtered_count == 0 then
            self:handleNoXrayTypeItemsFoundWithFilter(_("no items of this type were found..."))
            return false
        else
            title = DX.d.filter_icon .. " " .. source
        end

    elseif self.filtered_count > 0 and self.filter_string and self.filter_string:len() >= 3 then
        --* when no xray_items found with the current filter:
        if #self.items == 0 then
            --select_number, title = self:noItemsFoundWithFilterHandler("niets gevonden met \"" .. self.filter_string .. "\"...")
            return nil, false
        else
            title = source .. " - " .. self.filter_string
        end

    elseif self.filtered_count > 0 and self.filter_tag then
        --* when no xray_items found with the current filter:
        if #self.items == 0 then
            return nil, false
        else
            title = source .. " - " .. self.filter_tag
        end
    else
        title = source
    end
    if #self.items == 0 then
        return {}, _("Xray items")
    end

    return title
end

--- @private
function XrayViewsData:handleNoXrayTypeItemsFoundWithFilter(message)
    KOR.messages:notify(message, 4)
    DX.c:resetFilteredItems()
end

function XrayViewsData:getItem(item_no)
    local subject_table = self:getCurrentListTabItems()
    return subject_table[item_no]
end

function XrayViewsData:setItemHits(item, args)
    --* store_book_hits - which triggers saving of book_hits to database - will only be true when current method is called from ((XrayController#saveNewItem)) or ((XrayFormsData#saveUpdatedItem)):
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

    local book_hits, chapter_hits, chapter_hits_data = self:getAllTextHits(item)
    item.book_hits = book_hits
    item.chapter_hits = chapter_hits
    item.chapter_hits_data = chapter_hits_data
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
    --* item_table tables and self.items, self.persons and self.terms will be sorted later on in ((XrayViewsData#updateAndSortAllItemTables)):
    if DX.m:isPerson(item) then
        table_insert(self.item_table[2], item_copy)
        item_copy.index = #self.persons + 1
        table_insert(self.persons, item_copy)
    else
        table_insert(self.item_table[3], item_copy)
        item_copy.index = #self.terms + 1
        table_insert(self.terms, item_copy)
    end
end

--- @private
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
            table_insert(self.item_table[1], self.items[i])
            self:addItemToPersonsOrTerms(self.items[i])
        end
    end
end

--* only called from ((XrayController#saveUpdatedItem)), but not for newly added items; for those we call ((XrayViewsData#registerNewItem)):
function XrayViewsData:updateAndSortAllItemTables(item)

    --* here we also populate self.item_table[1] etc.:
    self:repopulateItemsPersonsTerms(item)
    --* this call is also needed to add reliability and xray type icons:
    self:applyFilters()

    --* display the new item in its proper place in the Items List (placeImportantItemsAtTop wil also add corresponding "index" prop to each item):
    self.items = parent:placeImportantItemsAtTop(self.items, -1)
    self.item_table[1] = parent:placeImportantItemsAtTop(self.item_table[1], -1)
    if DX.m:isPerson(item) then
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
    --* this will sometimes be the case when we first call up a definition through ReaderHighlight, before calling the Items List:
    if has_no_items(self.current_tab_items) then
        if has_items(self.item_table[1]) then
            self.items = KOR.tables:shallowCopy(self.item_table[1])
            self.persons = KOR.tables:shallowCopy(self.item_table[2])
            self.terms = KOR.tables:shallowCopy(self.item_table[3])
        else
            self.initData("force_refresh")
            self.prepareData()
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
            DX.fd:setFormItemId(items[i].id)
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
    DX.fd:setFormItemId(self.current_item.id)
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
    DX.fd:setFormItemId(self.current_item.id)
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
                table_insert(chapters_ordered, i, chapter_title)
                table_insert(self.chapters_start_pages_ordered, i, chapter_stats[chapter_title].start_page)
                inserted = true
                break
            end
        end
        if not inserted then
            table_insert(chapters_ordered, chapter_title)
            table_insert(self.chapters_start_pages_ordered, chapter_stats[chapter_title].start_page)
        end
    else
        chapter_stats[chapter_title].count = chapter_stats[chapter_title].count + 1
    end
end

--! this method will only be called upon creating a new or updating an existing item:
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
        table_insert(search_terms, aliases[i])
    end
    count = #short_names
    for i = 1, count do
        table_insert(search_terms, short_names[i])
    end

    --* initialize containers
    local chapter_stats = {}
    local chapter_titles_ordered = {}

    --* process all search terms (main + aliases):
    local total_count = 0
    count = #search_terms
    for s = 1, count do
        total_count = self:getChapterHitsPerTerm(search_terms[s], chapter_stats, chapter_titles_ordered, total_count)
    end

    --* chapter_info used in 4 places, to populate the chapter_hits html prop of items:
    local chapter_info
    local chapters_found = #chapter_titles_ordered
    if chapters_found > 0 then
        local present_as_table = not DX.s.is_mobile_device
        local chapter_items = {}
        local current_chapter_title, current_chapter_stats
        local max_hits = 0
        -- #((generate chapter info))
        for i = 1, chapters_found do
            current_chapter_title = chapter_titles_ordered[i]
            current_chapter_stats = chapter_stats[current_chapter_title]
            max_hits = self:addChapterToChapterStats(current_chapter_title, chapter_items, current_chapter_stats, present_as_table, i, max_hits)
        end
        chapter_info = self:generateChaptersListHtml(chapter_items, present_as_table, max_hits)
    end

    local chapter_hits_data = self:generateChapterHitsData(chapter_titles_ordered, chapter_stats)

    return total_count, chapter_info, chapter_hits_data
end

--* these data will be used for generating a chapter-occurrences-histogram in the PN info panel; current method called from ((XrayPageNavigator#setCurrentItem)):
function XrayViewsData:getChapterHitsData(item)

    local aliases = {}
    local short_names = {}
    local main_name = item

    if type(item) == "table" then
        main_name = item.name
        if has_text(item.aliases) then
            aliases = parent:splitByCommaOrSpace(item.aliases)
        end
        if has_text(item.short_names) then
            short_names = parent:splitByCommaOrSpace(item.short_names)
        end
    end

    --* build unified list of search terms:
    local search_terms = { main_name }
    count = #aliases
    for i = 1, count do
        table_insert(search_terms, aliases[i])
    end
    count = #short_names
    for i = 1, count do
        table_insert(search_terms, short_names[i])
    end

    --* initialize containers:
    local chapter_stats = {}
    local chapter_titles_ordered = {}

    --* process all search terms (main + aliases):
    local total_count = 0
    count = #search_terms
    for s = 1, count do
        total_count = self:getChapterHitsPerTerm(search_terms[s], chapter_stats, chapter_titles_ordered, total_count)
    end

    return self:generateChapterHitsData(chapter_titles_ordered, chapter_stats)
end

--- @private
function XrayViewsData:generateChapterHitsData(chapter_titles_ordered, chapter_stats)
    local toc = KOR.toc.toc
    if has_no_items(toc) then
        return {}
    end

    local chapters_count = #toc
    local hits_per_chapter = KOR.tables:populateWithPlaceholders(chapters_count, 0)

    count = #chapter_titles_ordered
    local title
    for i = 1, count do
        title = chapter_titles_ordered[i]
        hits_per_chapter[chapter_stats[title].index] = chapter_stats[title].count
    end

    return hits_per_chapter
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
            item.reliability_indicator = DX.i:getMatchReliabilityIndicator("full_name")
            return { item }, true, true
        end
        return item, true, true
    end
end

--- @private
function XrayViewsData:_doWeakMatchCheck(t, needle, partial_matches, for_relations)
    local item = self.items[t]

    local needles = {
        item.name,
    }
    local loops_count = 1
    if has_text(item.aliases) then
        table_insert(needles, item.aliases)
        loops_count = 2
    end
    local haystack, uc_haystack, is_lower_haystack, indicator
    for i = 1, loops_count do
        haystack = needles[i]
        uc_haystack, is_lower_haystack = getNameVariants(haystack)
        indicator = self:haystackItemPartlyMatches(needle, haystack, uc_haystack, is_lower_haystack)
        if indicator then
            if for_relations then
                item.reliability_indicator = indicator
            end
            table_insert(partial_matches, item)
            --* item_was_upgraded:
            return true
        end
    end
    return false
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
    table_insert(self.item_table_for_filter[1], menu_item)
    if DX.m:isPerson(menu_item) then
        table_insert(self.item_table_for_filter[2], menu_item)
    else
        table_insert(self.item_table_for_filter[3], menu_item)
    end
end

--- @private
function XrayViewsData:applyTagFilter(item, hits_registry)
    if has_no_text(item.tags) or not item.tags:find(self.filter_tag) then
        return false, false, nil, hits_registry
    end

    self.filtered_count = self.filtered_count + 1
    return false, true, DX.i:getMatchReliabilityIndicator("tag"), hits_registry .. item.name .. " "
end

--- @private
function XrayViewsData:applyTextFilters(item, linked_item_needles, hits_registry)

    local score, reliability_indicator
    local matched = true
    --* only during first loop we populate linked_item_needles, to search for items LINKED to main item; this search will be executed in ((XrayViewsData#populateItemTableFromLinkWords)):
    local is_first_loop = linked_item_needles
    local is_loop_for_linked_items = not is_first_loop

    --* when a linked item was already found as main item, don't add it a second time as linked item:
    if is_loop_for_linked_items and hits_registry:find(item.name, 1, true) then
        return false, nil, hits_registry
    end

    if self.type_matched and has_text(self.filter_string) then
        if self.search_simple then
            score, reliability_indicator = tapped_words:doSimpleSearchScoreMatch(item)
        else
            score, reliability_indicator = tapped_words:doScoreMatch(item)
        end
        matched = has_items(score) and (is_first_loop or score > 20)
        if is_loop_for_linked_items and matched and not self.search_simple then
            reliability_indicator = DX.i:getMatchReliabilityIndicator("linked_item")
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
            table_insert(linked_item_needles, item.linkwords)
        end

        if is_first_loop then
            hits_registry = hits_registry .. " " .. item.name
        end
        self.filtered_count = self.filtered_count + 1
    end
    return hits_registry
end

--* returns matched, tag_matched, reliability_indicator, hits_registry (in that exact sequence):
--- @private
function XrayViewsData:evaluateFilters(item, linked_item_needles, hits_registry)
    local matched, reliability_indicator
    local tag_matched = false
    if self.filter_tag then
        matched, tag_matched, reliability_indicator, hits_registry = self:applyTagFilter(item, hits_registry)
        return matched, tag_matched, reliability_indicator, hits_registry
    end

    self.type_matched = self:applyTypeFilters(item)

    --* in first loop linked_items_needles are only populated, but in the second loop they themselves become the needles and arg linked_item_needles is nil:
    matched, reliability_indicator, hits_registry = self:applyTextFilters(item, linked_item_needles, hits_registry)

    return matched, tag_matched, reliability_indicator, hits_registry
end

--- @private
function XrayViewsData:filterAndAddItemToItemTables(items, n, search_needles, linked_item_needles, hits_registry)

    local list_item, matched, tag_matched, reliability_indicator
    local no_filters_active = not search_needles and not self.filter_tag and not self.filter_xray_types
    if self.filter_tag then
        self.filter_string = nil
    end
    local item = items[n]

    if not no_filters_active then
        matched, tag_matched, reliability_indicator, hits_registry = self:evaluateFilters(item, linked_item_needles, hits_registry)
    end

    local insert_item =
        no_filters_active
        or matched
        or tag_matched
        or (self.filter_xray_types and self.type_matched)

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
            tags = item.tags,
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
        return hits_registry
    end

    linked_item_needles = table_concat(linked_item_needles, " ")
    local needles = KOR.strings:split(linked_item_needles, " ")
    local purged = {}
    count = #needles
    for i = 1, count do
        if not hits_registry:find(needles[i], 1, true) then
            table_insert(purged, needles[i])
        end
    end
    needles = purged

    count = #items
    for n = 1, count do
        hits_registry = self:filterAndAddItemToItemTables(items, n, needles, nil, hits_registry)
    end

    return hits_registry
end

--* ((XrayViewsData#upgradeNeedleItem)) has to be called in the caller context, before calling getRelatedItems:
function XrayViewsData:getLinkedItems(needle_item)

    --* don't return here when needle_item has no linkwords, because we also search in the other xray items, to see if THEIR linkwords match to the name of the needle_item...
    local linked_items, linked_names_index = {}, {}
    local needle_item_has_linkwords = has_text(needle_item.linkwords)

    local haystack_item
    count = #self.items
    for i = 1, count do
        haystack_item = self.items[i]
        --* add items which are linked by the keywords in needle_item:
        if needle_item_has_linkwords then
            self:addLinkedItem(needle_item, haystack_item, linked_names_index, linked_items)
        end
        --* add items which link to the parent item:
        if not linked_names_index[haystack_item.name] and has_text(haystack_item.linkwords) then
            self:addItemsWhichPointToParent(needle_item, haystack_item, linked_names_index, linked_items)
        end
    end
    if #linked_items > 1 then
        --* for consumption in ((Tables#merge)); we shift the starting index to 2, because the parent item with index 1 will be injected at the start of this collection of items, in ((XraySidePanels#populateLinkedItemsPanel)):
        KOR.registry:set("starting_sorting_index", 2)
        linked_items = parent:placeImportantItemsAtTop(linked_items, -1)
    end
    return linked_items, linked_names_index
end

--- @private
function XrayViewsData:addLinkedItem(needle_item, haystack_item, linked_names_index, linked_items)
    if haystack_item.name == needle_item.name then
        return
    end
    local linkword, needle, aliases_needle
    local linkwords = parent:splitByCommaOrSpace(needle_item.linkwords, "add_singulars")
    count2 = #linkwords
    for i = 1, count2 do
        linkword = linkwords[i]
        linkword = linkword:gsub("%-", "%%-")
        needle = haystack_item.name
        --* we also check for matches with aliases of xray items:
        aliases_needle = haystack_item.aliases
        if
            (
                parent:hasExactMatch(needle, linkword)
                or
                (aliases_needle and parent:hasExactMatch(aliases_needle, linkword))
            )
            and not linked_names_index[haystack_item.name]
        then
            --! don't inadvertently change the parent item in self.items:
            haystack_item = KOR.tables:shallowCopy(haystack_item)
            table_insert(linked_items, haystack_item)
            linked_names_index[haystack_item.name] = true
        end
    end
end

--- @private
function XrayViewsData:addItemsWhichPointToParent(needle_item, haystack_item, linked_names_index, linked_items)
    if haystack_item.name == needle_item.name then
        return
    end
    --* add items which link via THEIR linkwords to the needle_item:
    local haystack_linkwords = parent:splitByCommaOrSpace(haystack_item.linkwords, "add_singulars")
    local linkword, needle, aliases_needle
    count2 = #haystack_linkwords
    for i = 1, count2 do
        linkword = haystack_linkwords[i]
        linkword = linkword:gsub("%-", "%%-")
        needle = needle_item.name
        --* we also check for matches with aliases of xray items:
        aliases_needle = needle_item.aliases
        if
            (
                parent:hasExactMatch(needle, linkword)
                or
                (aliases_needle and parent:hasExactMatch(aliases_needle, linkword))
            )
            and not linked_names_index[haystack_item.name]
        then
            --! don't inadvertently change the parent item in self.items:
            haystack_item = KOR.tables:shallowCopy(haystack_item)
            table_insert(linked_items, haystack_item)
            linked_names_index[haystack_item.name] = true
            break
        end
    end
end

--- @private
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
    local noun = item.aliases:match(" ") and _("aliases") or _("alias")
    noun = noun .. ": "
    local aliases = noun .. suffix .. item.aliases
    aliases = KOR.strings:splitLinesToMaxLength(aliases, DX.s.PN_info_panel_max_line_length, DX.ip.alias_indent)

    return info .. "\n\n" .. aliases
end

--- @private
function XrayViewsData:addTagsInfo(info, item, has_tags, has_linkwords)
    if not has_tags then
        return info
    end

    local suffix = ""
    if has_linkwords then
        suffix = item.tags:match(" ") and " " or "     "
    end
    if item.linkwords:match(" ") then
        suffix = suffix .. "   "
    end
    local noun = item.aliases:match(" ") and _("tags") or _("tag")
    noun = noun .. ": "
    local tags = noun .. suffix .. item.tags
    tags = KOR.strings:splitLinesToMaxLength(tags, DX.s.PN_info_panel_max_line_length, DX.ip.alias_indent)

    return info .. "\n\n" .. tags
end

--- @private
function XrayViewsData:addLinkWordsInfo(info, item, has_linkwords, has_aliases)
    if not has_linkwords then
        return info
    end

    local noun = item.linkwords:match(" ") and _("link-terms") or _("link-term")
    noun = noun .. ": "
    local linkwords = noun .. item.linkwords
    local info_spacer = has_aliases and "\n" or "\n\n"
    linkwords = KOR.strings:splitLinesToMaxLength(linkwords, DX.s.PN_info_panel_max_line_length, DX.ip.alias_indent)

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

    return info .. info_spacer .. table_concat(mentioned_in, "\n")
end

function XrayViewsData:getItemInfo(item, ucfirst)
    local info = ucfirst and KOR.strings:ucfirst(item.description) .. "\n" or "\n" .. item.description .. "\n"

    local has_aliases, has_tags, has_linkwords, mentioned_in = has_text(item.aliases), has_text(item.tags), has_text(item.linkwords), has_text(item.mentioned_in)
    info = self:addAliasesInfo(info, item, has_aliases, has_linkwords)
    info = self:addTagsInfo(info, item, has_tags, has_linkwords)
    info = self:addLinkWordsInfo(info, item, has_linkwords, has_aliases)

    return self:addMentionedInInfo(info, item, mentioned_in, has_aliases, has_linkwords)
end

--- @private
--- @param meta_info table
function XrayViewsData:addAliasesHtml(meta_info, item)
    if has_no_text(item.aliases) then
        return
    end
    table_insert(meta_info, T(self.item_meta_info_template, item.aliases:match(" ") and _("Aliases") .. ": " or _("Alias") .. ": ", item.aliases))
end

--- @private
--- @param meta_info table
function XrayViewsData:addLinkWordsHtml(meta_info, item)
    if has_no_text(item.linkwords) then
        return
    end
    table_insert(meta_info, T(self.item_meta_info_template, item.linkwords:match(" ") and _("Link-terms") .. ": " or _("Link-term") .. ": ", item.linkwords))
end

--- @private
--- @param meta_info table
function XrayViewsData:addMentionedInHtml(meta_info, item)
    local mentioned_in_multiple_books = item.book_hits and item.series_hits and item.book_hits ~= item.series_hits
    if has_no_text(item.mentioned_in) or not mentioned_in_multiple_books then
        return
    end
    --* "|" was used for GROUP_CONCAT in query:
    local list = KOR.strings:split(item.mentioned_in, "|")
    list = table_concat(list, "<br>")
    table_insert(meta_info, T(self.item_meta_info_template, _("Mentioned in") .. ":", list))
end

--- @private
--- @param meta_info table
function XrayViewsData:addTagsHtml(meta_info, item)
    if has_no_text(item.tags) then
        return
    end
    table_insert(meta_info, T(self.item_meta_info_template, item.tags:match(" ") and _("Tags") .. ": " or _("Tag") .. ": ", item.tags))
end

--! hits html has only been generated and stored in database upon creating a new or updating an existing item:
--- @private
--- @param meta_info table
function XrayViewsData:addHitsHtml(meta_info, item)
    if parent.current_series and item.series_hits then
        table_insert(meta_info, T(self.item_meta_info_template, _("Hits in series") .. ":", tonumber(item.series_hits)))
    end
    if item.book_hits then
        table_insert(meta_info, T(self.item_meta_info_template, _("Hits in book") .. ":", tonumber(item.book_hits)))
    end
end

function XrayViewsData:getItemInfoHtml(item, ucfirst)
    local separator = "<br>"
    local info = ucfirst and KOR.strings:ucfirst(item.description) .. separator or separator .. item.description .. separator

    local meta_info = { "<table style='margin-top: 2.5em'>" }
    self:addAliasesHtml(meta_info, item)
    self:addLinkWordsHtml(meta_info, item)
    self:addTagsHtml(meta_info, item)
    self:addHitsHtml(meta_info, item)
    self:addMentionedInHtml(meta_info, item)
    if #meta_info > 1 then
        table_insert(meta_info, "</table>")
        info = info .. table_concat(meta_info, "")
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

--* only used for linked items and for XrayExporter:
--* compare for generation of info_text for found-in-page side panel items: ((XrayInfoPanel#getItemInfoText)):
function XrayViewsData:generateXrayExportOrLinkedItemItemInfo(item, ui_explanation, information_level, for_all_items_list)

    local iindent = for_all_items_list and DX.ip.info_indent or DX.ip.alias_indent .. "  "
    local aindent = DX.ip.alias_indent

    local linebreak = information_level == 1 and "" or "\n"
    local first_line = {
        linebreak
    }
    local first_line_fc = {
        linebreak
    }
    local description_indent, meta_indent
    local description = item.description
    if for_all_items_list then
        meta_indent = aindent
    else
        description_indent, meta_indent = DX.ip:getConfiguredInfoPanelIndentation()
        iindent = meta_indent
    end
    description = KOR.strings:splitLinesToMaxLength(description, DX.s.PN_info_panel_max_line_length, description_indent)
    --* suffix "fc" stands for "for copy":
    local aliases, aliases_fc = self:generateAliasesInfo(item, iindent, for_all_items_list)
    local linkwords, linkwords_fc = self:generateLinkwordsInfo(item, iindent, for_all_items_list)
    local tags, tags_fc = self:generateTagsInfo(item, iindent, for_all_items_list)
    local hits, hits_fc = self:generateHitsInfo(item, iindent, for_all_items_list)

    -- #((use xray match reliability indicators))
    local xray_match_reliability_icon = DX.i:getMatchReliabilityIndicator("full_name")

    --! don't use has_text here, because for full name hits we don't add a text (i.e. the full name) after the reliability weight icon)! Under Ubuntu this is not a problem, but using has_text under Android causes explanation not to be shown:
    if has_content(ui_explanation) then
        xray_match_reliability_icon = ui_explanation:match(self.separator .. "([^ ]+)")

    --* when we want to populated the linked items side panel:
    elseif not for_all_items_list then
        --* this indicator for the parent item in the first side panel tab was set via ((XraySidePanels#activatePageNavigatorPanelTab)) > ((XrayInfoPanel#setParentReliabilityIndicator)):
        local parent_item_indicator = KOR.registry:getOnce("parent_reliability_indicator")
        if parent_item_indicator then
            table_insert(first_line, parent_item_indicator .. " ")
        else
            table_insert(first_line, DX.i:getMatchReliabilityIndicator("linked_item") .. " ")
        end
    end
    local xray_type_icon = DX.vd:getItemTypeIcon(item)
    first_line, first_line_fc = self:generateFirstLines(first_line, first_line_fc, item, xray_type_icon, ui_explanation, meta_indent, for_all_items_list)

    local info = table_concat({
        first_line,
        description,
        "\n",
        hits,
        "\n",
        aliases,
        linkwords,
        tags,
    })
    local info_fc
    if for_all_items_list then
        info_fc = table_concat({
            first_line_fc,
            description,
            "\n",
            meta_indent,
            _("mentions"),
            ": ",
            hits_fc,
            "\n",
            aliases_fc,
            linkwords_fc,
            tags_fc,
        })
        --* for copyable list (without icons) of all items:
        return info, info_fc
    end

    --* for Xray Page Information popup:
    return info, xray_type_icon, xray_match_reliability_icon
end

--- @private
function XrayViewsData:generateAliasesInfo(item, iindent, for_all_items_list)
    if not has_text(item.aliases) then
        return "", ""
    end
    local aliases, aliases_fc = "", ""

    local icon = KOR.icons.xray_alias_bare .. " "
    aliases = KOR.strings:splitLinesToMaxLength(item.aliases, DX.s.PN_info_panel_max_line_length, iindent, icon) .. "\n"
    if for_all_items_list then
        local noun = self:getKeywordsCount(item.aliases) == 1 and _("alias") .. ": " or _("aliases") .. ": "
        aliases_fc = KOR.strings:splitLinesToMaxLength(item.aliases, DX.s.PN_info_panel_max_line_length, iindent, noun) .. "\n"
    end
    return aliases, aliases_fc
end

--- @private
function XrayViewsData:generateHitsInfo(item, iindent, for_all_items_list)
    local hits, hits_fc = "", ""

    local series_hits_added = false
    if DX.m.current_series and has_content(item.series_hits) then
        series_hits_added = true
        hits = KOR.icons.graph_bare .. " serie " .. tonumber(item.series_hits)
    end
    if has_content(item.book_hits) then
        local separator = series_hits_added and ", " or KOR.icons.graph_bare .. " "
        hits = iindent .. hits .. separator .. "boek " .. tonumber(item.book_hits)
    end

    if for_all_items_list then
        local noun = "vermeldingen: "
        hits_fc = iindent .. noun .. hits
    end

    return hits, hits_fc
end

--- @private
function XrayViewsData:generateTagsInfo(item, iindent, for_all_items_list)
    if not has_text(item.tags) then
        return "", ""
    end
    local tags, tags_fc = "", ""

    local icon = KOR.icons.tag_open_bare .. " "
    tags = KOR.strings:splitLinesToMaxLength(item.tags, DX.s.PN_info_panel_max_line_length, iindent, icon) .. "\n"
    if for_all_items_list then
        local noun = self:getKeywordsCount(item.tags) == 1 and _("tag") .. ": " or _("tags") .. ": "
        tags_fc = KOR.strings:splitLinesToMaxLength(item.tags, DX.s.PN_info_panel_max_line_length, iindent, noun) .. "\n"
    end

    return tags, tags_fc
end

--- @private
function XrayViewsData:generateLinkwordsInfo(item, iindent, for_all_items_list)
    if not has_text(item.linkwords) then
        return "", ""
    end
    local linkwords, linkwords_fc = "", ""
    local icon = KOR.icons.xray_link_bare .. " "
    linkwords = KOR.strings:splitLinesToMaxLength(item.linkwords, DX.s.PN_info_panel_max_line_length, iindent, icon) .. "\n"
    if for_all_items_list then
        local noun = self:getKeywordsCount(item.linkwords) == 1 and _("link-term") .. ": " or _("link-terms") .. ": "
        linkwords_fc = KOR.strings:splitLinesToMaxLength(item.linkwords, DX.s.PN_info_panel_max_line_length, iindent, noun) .. "\n"
    end

    return linkwords, linkwords_fc
end

--- @private
function XrayViewsData:generateFirstLines(first_line, first_line_fc, item, xray_type_icon, ui_explanation, meta_indent, for_all_items_list)
    local name = item.name

    --* here the info gets combined:
    -- #((xray items dialog add match reliability explanations))
    table_insert(first_line, xray_type_icon)
    table_insert(first_line, name)
    if ui_explanation then
        table_insert(first_line, ui_explanation)
    end
    first_line = table_concat(first_line)
    first_line = KOR.strings:splitLinesToMaxLength(first_line, DX.s.PN_info_panel_max_line_length, meta_indent) .. "\n"
    if for_all_items_list then
        local important_marker = (item.xray_type == 2 or item.xray_type == 4) and "!" or ""
        table_insert(first_line_fc, important_marker)
        table_insert(first_line_fc, name)
        table_insert(first_line_fc, ui_explanation)
        first_line_fc = table_concat(first_line_fc)
        first_line_fc = KOR.strings:splitLinesToMaxLength(first_line_fc, DX.s.PN_info_panel_max_line_length, meta_indent) .. "\n"
    end

    return first_line, first_line_fc
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
    return has_text(self.filter_string) or has_text(self.filter_tag) or self.filter_xray_types
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
    if not self.search_simple and not self.filter_tag then
        hits_registry = self:populateItemTableFromLinkWords(linked_item_needles, items, hits_registry)
    end

    DX.d:notifyFilterResult(filter_active, self.filtered_count)
    if filter_active and self.filtered_count == 0 then
        self.filter_string = ""
        self.filter_tag = nil
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
function XrayViewsData:addChapterToChapterStats(current_chapter_title, chapter_items, current_chapter_stats, present_as_table, i, max_hits)
    local chapter_start_page
    --* in the viewer this will be a list under an ul; using ul for this sublist yields ugly big open bullets, so here no list tags used:
    --* chapter_stats[chapter].count was set in ((XrayViewsData#setChapterHits)):
    if present_as_table then
        chapter_start_page = current_chapter_stats.start_page
                and T(self.chapter_page_number_format, current_chapter_stats.start_page)
                or ""
        table_insert(chapter_items, "<tr><td>" ..
                i .. ". <i>" .. current_chapter_title .. "</i>" .. chapter_start_page .. "</td><td>&nbsp;&nbsp;</td><td>" .. current_chapter_stats.count .. "</td></tr>")
    else
        table_insert(chapter_items, current_chapter_title .. " " .. KOR.icons.arrow_bare .. " " .. current_chapter_stats.count .. "<br>")
    end
    if current_chapter_stats.count > max_hits then
        max_hits = current_chapter_stats.count
    end
    return max_hits
end

--- @private
function XrayViewsData:generateChaptersListHtml(chapter_items, present_as_table, max_hits)
    local chapter_info = table_concat(chapter_items, "")
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
    local results, needle, case_insensitive, last_chapter_title, last_chapter_index
    --* if applicable, we only search for first names (then probably more accurate hits count):
    needle = parent:getRealFirstOrSurName(term)
    --* for lowercase needles (terms instead of persons), we search case insensitive:
    case_insensitive = not needle:match("[A-Z]")

    --! using document:findAllTextWholeWords instead of document:findAllText here crucial to get exact hits count:
    results = KOR.document:findAllTextWholeWords(needle, case_insensitive, 0, 3000, false)

    if has_no_items(results) then
        return total_count
    end

    local result_count = #results
    total_count = total_count + result_count
    for i = 1, result_count do
        last_chapter_title = KOR.toc:getTocLastChapterInfo(results[i].start)

        --* the cached chapter_props will only be reset in ((XrayController#onReaderReady)) > ((XrayController#resetDynamicXray)), so when opening another ebook:
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
    --* DX.m.current_series should have been set, when list_display_mode is "series", from the doc_props in ((XrayController#onReaderReady)) > ((XrayController#resetDynamicXray)) > ((XrayModel#setTitleAndSeries)):
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
        if DX.m:isPerson(xray_item) then
            table_insert(self.persons, xray_item)
        else
            table_insert(self.terms, xray_item)
        end
    end
end

--* compare ((XrayViewsData#registerNewItem)):
function XrayViewsData:registerUpdatedItem(updated_item)

    --* the props icons and text are needed so we get no crash because of one of these props missing when generating list items in ((XrayViewsData#generateListItemText)) and ((Strings#formatListItemNumber)):
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
    DX.m:updateStaticReferenceCollections(updated_item.id, updated_item)

    self:updateAndSortAllItemTables(updated_item)
end

--- @private
function XrayViewsData:setItems(items)
    self.items = items
end

--* compare getting keywords via ((XrayModel#splitByCommaOrSpace)):
--- @private
function XrayViewsData:getKeywordsCount(text)
    if not text:match(",") then
        return KOR.strings:substrCount(text, " ") + 1
    end
    return KOR.strings:substrCount(text, ",") + 1
end

function XrayViewsData:getNeedleString(word, for_substitution)
    local matcher_esc = word:gsub("%-", "%%-")
    if for_substitution then
        return self.word_start .. "(" .. matcher_esc .. self.word_end .. ")"
    end
    return self.word_start .. matcher_esc .. self.word_end
end

function XrayViewsData:getNeedleStringPlural(word, for_substitution)
    local matcher_esc = word:gsub("%-", "%%-")
    local plural_matcher
    if not matcher_esc:match("s$") then
        plural_matcher = matcher_esc .. "s"
        word = word .. "s"

        --* if a word already seems to be in plural form, deduce its possible singular form:
    else
        plural_matcher = matcher_esc:gsub("s$", "")
        word = word:gsub("s$", "")
    end
    if for_substitution then
        return self.word_start .. "(" .. plural_matcher .. self.word_end .. ")", word
    end
    return self.word_start .. plural_matcher .. self.word_end
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
                return DX.i:getMatchReliabilityIndicator("first_name")
            elseif i == count then
                return DX.i:getMatchReliabilityIndicator("last_name")
            end
            return DX.i:getMatchReliabilityIndicator("partial_match")
        end
    end
    return false
end

function XrayViewsData:setFilterTypes(filter_types)
    self.filter_xray_types = filter_types
end

function XrayViewsData:setProp(prop, value)
    self[prop] = value
end

return XrayViewsData
