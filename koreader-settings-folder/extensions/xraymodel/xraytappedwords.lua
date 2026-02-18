
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_no_text = has_no_text
local has_text = has_text
local pairs = pairs
local table = table
local table_insert = table.insert

local count
--- @type XrayModel parent
local parent
--- @type XrayViewsData views_data
local views_data

--- @class XrayTappedWords
local XrayTappedWords = WidgetContainer:new{
    _item_index = nil,
    active_tapped_word_tab = 1,
    at_top1_name_matches = nil,
    at_top2_name_matches = nil,
    bottom_linked_items = nil,
    --* set via ((XrayDialogs#viewTappedWordItem)) > ((XrayTappedWords#registerCurrentItem))
    current_tapped_word_item = nil,
    items_collection = {},
    popup_items = nil,
    popup_persons = nil,
    popup_terms = nil,
    relation_primary_prop = nil,
    relation_secondary_prop = nil,
    tapped_word = nil,
    --* set via ((XrayButtons#forItemsCollectionPopup)) > ((XrayTappedWords#itemsRegister)):
    tapped_word_items = {},
    tapped_word_persons = {},
    tapped_word_status_indicators = {},
    tapped_word_terms = {},
}

--- @param xray_model XrayModel
function XrayTappedWords:initDataHandlers(xray_model)
    parent = xray_model
    views_data = DX.vd
end

function XrayTappedWords:resetData(force_refresh)
    self.current_tapped_word_item = nil
    self.tapped_word = nil
    self.tapped_word_status_indicators = {}
    self.items_collection = {}
    self.tapped_word_items = {}
    self.tapped_word_persons = {}
    self.tapped_word_terms = {}
    if force_refresh then
        self._item_index = nil
    end
end

function XrayTappedWords:getXrayItemAsDictionaryEntry(tapped_word)

    self.tapped_word = tapped_word

    --* First try to treat the word as the name of an XrayItem:
    local spaces_count = KOR.strings:substrCount(tapped_word, " ")
    --* don't allow larger strings which contain a saved name to trigger matches:
    if spaces_count <= 2 then
        --* match by name only is falsy in this case:
        --* this call also sets XrayTappedWords.tapped_word, for use in ((XrayTappedWords#getTypeAndReliabilityIcons)):
        local items_found = self:itemExists(tapped_word, tapped_word)
        if items_found then

            -- #((xray_item as dictionary plugin pre dialog))
            --* we only want to show the popup if there are more than one item found, because in case of only one item we can immediately show that in the Item Viewer:
            if #items_found > 1 then
                --* items will already be sorted by name or hits...
                local buttons, buttons_count = DX.b:forItemsCollectionPopup(items_found, tapped_word)
                DX.d:showTappedWordCollectionPopup(buttons, buttons_count, tapped_word)
                return true

            --* when only a single item found, show it immediately:
            elseif #items_found > 0 then
                --* false for called_from_list:
                DX.d:showItemViewer(items_found[1], false, tapped_word)
                return true
            end
        end
    end
    return false
end

function XrayTappedWords:getNextItem()
    local next = self.current_tapped_word_item.tapped_index + 1
    if next > #self.tapped_word_items then
        next = 1
    end
    self.current_tapped_word_item = self.tapped_word_items[next]
    return self.current_tapped_word_item
end

function XrayTappedWords:getPreviousItem()
    local previous = self.current_tapped_word_item.tapped_index - 1
    if previous < 1 then
        previous = #self.tapped_word_items
    end
    self.current_tapped_word_item = self.tapped_word_items[previous]
    return self.current_tapped_word_item
end

--* see for registering of these item ((XrayTappedWords#itemsRegister)):
function XrayTappedWords:itemsUnregister()
    --* this occurs when we close the related items popup and explicitly want to reset the associated items; see after_close_callback in ((XrayDialogs#showTappedWordCollectionPopup)):
    self:resetData()
    self.active_tapped_word_tab = 1
    parent:setProp("use_tapped_word_data", false)
    KOR.registry:unset("dont_bolden_active_menu_items")
end

function XrayTappedWords:rememberTappedWord(tapped_word)
    self.tapped_word = tapped_word
end

--* see for unregistering ((XrayTappedWords#itemsUnregister)):
function XrayTappedWords:itemsRegister(tapped_word_items)
    local items = KOR.tables:shallowCopy(tapped_word_items)
    count = #items
    --* these indices are needed for navigating back and forth through the related items:
    for i = 1, count do
        items[i].tapped_index = i
    end
    self.tapped_word_items = items
    parent:setProp("use_tapped_word_data", true)
end

function XrayTappedWords:registerCurrentItem(item)
    self.current_tapped_word_item = item
end

--- @private
function XrayTappedWords:buildItemIndex()
    if self._item_index then
        return self._item_index
    end
    local index = {}
    local name, item
    count = #views_data.items
    for i = 1, count do
        item = views_data.items[i]
        name = KOR.tables:normalizeTableIndex(item.name)
        if name then
            index[name] = index[name] or {}
            table_insert(index[name], item)
        end
        self:addToItemIndexFromAlias(item, index)
    end
    self._item_index = index

    return index
end

--- @private
function XrayTappedWords:addToItemIndexFromAlias(item, index)
    if has_no_text(item.aliases) then
        return
    end
    local alias_norm
    for alias in item.aliases:gmatch("[^,]+") do
        if has_text(alias) then
            alias_norm = KOR.tables:normalizeTableIndex(alias)
            index[alias_norm] = index[alias_norm] or {}
            table_insert(index[alias_norm], item)
        end
    end
end

--* store the metadata of related items (derived from buttons metadata in ), for use when generating the text prop for those items in the list, in ((XrayTappedWords#getCurrentListTabItems)):
--- @private
function XrayTappedWords:storeCollectionMetadata(status_indicators)
    table_insert(self.tapped_word_status_indicators, status_indicators)
end

--* compare ((XrayViewsData#getCurrentListTabItems)):
function XrayTappedWords:getCurrentListTabItems()
    --* when viewing related items in a list, we don't want to see items marked with bold (too much emphasis in a short list):
    KOR.registry:set("dont_bolden_active_menu_items", true)

    --self:prepareItemsData()
    parent:setTabDisplayCounts()
    --* this items were populated in ((XrayButtons#forItemsCollectionPopup)) > ((store tapped word popup collection info)):
    local subject_tables = {
        self.popup_items,
        self.popup_persons,
        self.popup_terms,
    }
    local items = subject_tables[self.active_tapped_word_tab]

    count = #items
    for i = 1, count do
        --* use a custom list item generator, not that of XrayModel:
        items[i].text = views_data:generateListItemText(items[i])
        items[i].text = KOR.strings:formatListItemNumber(i, items[i].text, "use_spacer")

        --! give the item a callback to execute when the item is tapped:
        items[i].callback = function()
            self.current_tapped_word_item = items[i]
            --* reset bold attributes which were set in the regular list of all Xray items:
            items[i].bold = false
            DX.d:viewTappedWordItem(items[i], nil, self.tapped_word)
        end
    end
    return items
end

--* Search for xray_item to be saved in all stored xray_items. match_by_name_only: falsy in case of tapped words in ebook. Let the xray_items manager know whether a match has been found:
function XrayTappedWords:itemExists(needle_name, tapped_word, is_exists_check)

    self.tapped_word = tapped_word

    local item_was_upgraded, needle_matches_fullname
    local include_name_match = true
    local needle_item = {
        description = "",
        name = needle_name,
        short_names = "",
        aliases = "",
        tags = "",
        linkwords = "",
        xray_type = 1,
    }

    needle_item, item_was_upgraded, needle_matches_fullname = views_data:upgradeNeedleItem(needle_item, {
        for_relations = not is_exists_check and true,
        include_name_match = include_name_match,
        is_exists_check = is_exists_check,
        tapped_word = tapped_word,
    })
    if not item_was_upgraded then
        return
    end
    if is_exists_check and item_was_upgraded then
        return needle_item
    end
    return self:getCollection(needle_item, "compare_multiple_items", include_name_match, needle_matches_fullname, tapped_word)
end

--- @private
function XrayTappedWords:itemsPrioritize(subject, relation_primary_prop, relation_secundary_prop)
    self.at_top1_name_matches = {}
    self.at_top2_alias_matches = {}
    self.bottom_linked_items = {}
    self.relation_primary_prop = relation_primary_prop
    self.relation_secundary_prop = relation_secundary_prop
    count = #subject
    for nr = 1, count do
        self:relatedItemAdd({
            subject = subject,
            nr = nr,
        })
    end

    return #self.at_top1_name_matches,
    #self.at_top2_alias_matches,
    #self.bottom_linked_items
end

--- @private
function XrayTappedWords:relatedItemAdd(args)
    local item = args.subject[args.nr]

    if item[self.relation_primary_prop] == true then
        table_insert(self.at_top1_name_matches, item)
        return
    elseif item[self.relation_secundary_prop] == true then
        table_insert(self.at_top2_alias_matches, item)
        return
    end
    table_insert(self.bottom_linked_items, item)
end

function XrayTappedWords:collectionPopulateAndSort(items, tapped_word)
    local copies = {}
    local xray_item, copy

    count = #items
    for nr = 1, count do
        xray_item = items[nr]
        copy = KOR.tables:shallowCopy(xray_item)
        copy.is_bold1 = xray_item.name:find(tapped_word, 1, true) and true or false
        copy.is_bold2 = has_text(xray_item.aliases) and xray_item.aliases:find(tapped_word, 1, true) and true or false


        --* is_bold prop MUST be set to either false or true, to be used in ((ButtonTable#init)):
        copy.is_bold = copy.is_bold1 or copy.is_bold2
        table_insert(copies, copy)
    end

    --* make sure that items with hits are shown first always, and then show items without hits (but linked) according to XrayViewsData.list_display_mode:
    local top1_count, top2_count, bottom_count = self:itemsPrioritize(copies, "is_bold1", "is_bold2")

    --! watch out: sorting_method, not sorting_mode:
    --* now sort top items and regular items each according to XrayModel.sorting_method:
    --if parent.sorting_method == "hits" then
    --* sort tables at_top1, at_top2 and regular_items each by either item.book_hits, when self.list_display_mode == "book", or by item.series_hits, when views_data.list_display_mode == "series"
    --else
    --* sort tables at_top1, at_top2 and regular_items each by their name prop
    --end

    copies = self:itemsSort(top1_count, top2_count, bottom_count)
    self:itemsRegister(copies)

    return copies
end

--- @private
function XrayTappedWords:collectionSortAndPurge(needle_items, needle_matches_fullname)
    local items_collection = self.items_collection
    count = #items_collection
    if count < 1 then
        return items_collection
    end
    items_collection = parent:placeImportantItemsAtTop(items_collection, 1)
    local sorted_and_purged = {}
    local is_full_match, needle, is_unique_item

    local already_injected = " "
    local needle_count = #needle_items
    for i = 1, count do
        local item = items_collection[i]
        is_full_match = false
        if needle_matches_fullname then
            for n = 1, needle_count do
                needle = needle_items[n]
                if item.name == needle.name or item.name:match("^" .. needle.name .. "s$") then
                    is_full_match = true
                    break
                end
            end
        end

        --* already_injected: sometimes for some reason a main item (found via name) was shown twice, but this fixes that:

        is_unique_item = not already_injected:find(" " .. item.name .. " ", 1, true)
        if is_full_match and is_unique_item then
            table_insert(sorted_and_purged, 1, item)
            already_injected = already_injected .. item.name .. " "
        elseif is_unique_item then
            table_insert(sorted_and_purged, item)
            already_injected = already_injected .. item.name .. " "
        end
    end
    self.items_collection = sorted_and_purged

    return sorted_and_purged
end

--* include_name_match is only truthy when we pressed a word in the ebook text:
--* ((XrayViewsData#upgradeNeedleItem)) has to be called before calling getRelatedItems:
--- @private
function XrayTappedWords:getCollection(needle_items, compare_multiple_items, include_name_match, needle_matches_fullname, tapped_word)

    if not compare_multiple_items then
        needle_items = { needle_items }
    end
    self.items_collection = needle_items
    local index = self:buildItemIndex() --* precomputed name/alias index
    local seen = {} --* dedup by item.tapped_index or name

    local candidates, aliases, needle_item, alias_count, alias
    count = #needle_items
    for i = 1, count do
        needle_item = needle_items[i]
        aliases = has_text(needle_item.aliases)
            and parent:splitByCommaOrSpace(needle_item.aliases, "add_singulars")
            or {}

        --* build candidate set from index:
        candidates = {}

        --* add main name and aliases as index keys
        self:addLinkedItemCandidatesFor(candidates, needle_item.name, index)
        alias_count = #aliases
        for a = 1, alias_count do
            alias = aliases[a]
            self:addLinkedItemCandidatesFor(candidates, alias, index)
        end

        --* also add tapped_word if present (to catch dynamic word hits):
        if tapped_word then
            self:addLinkedItemCandidatesFor(candidates, tapped_word, index)
        end
        self:addCollectionItem(candidates, seen, needle_item, include_name_match, aliases, tapped_word)
    end

    return self:collectionSortAndPurge(needle_items, needle_matches_fullname)
end

--- @private
function XrayTappedWords:addCollectionItem(candidates, seen, needle_item, include_name_match, aliases, tapped_word)
    local items_collection = {} --* temp buffer for hits
    --* now iterate only over the small candidate set:
    local related_items_count, eitem, key
    for item in pairs(candidates) do
        --* items_collection is populated in this call, if applicable:
        self:matchItemToTappedWord(items_collection, item, needle_item, include_name_match, aliases, tapped_word)
        related_items_count = #items_collection
        for e = 1, related_items_count do
            eitem = items_collection[e]
            key = eitem.tapped_index or eitem.name
            if not seen[key] then
                seen[key] = true
                table_insert(self.items_collection, eitem)
            end
        end
        items_collection = {}
    end
end

--- @private
function XrayTappedWords:matchItemToTappedWord(tapped_word_collection, item, needle_item, include_name_match, aliases, tapped_word)
    local tapped_word_matcher = tapped_word
    if tapped_word then
        tapped_word_matcher = tapped_word:gsub("%-", "%%-")
    end

    local linked_items, linked_names_index = views_data:getLinkedItems(needle_item)
    count = #linked_items
    for i = 1, count do
        table_insert(tapped_word_collection, linked_items[i])
    end
    if linked_names_index[item.name] then
        return
    end

    --* include extact fullname match, if allowed:
    if include_name_match and (not tapped_word or tapped_word == item.name) and (item.tapped_index == needle_item.tapped_index or item.name == needle_item.name or item.name:match("^" .. needle_item.name .. "s$")) then
        item.reliability_indicator = DX.i:getMatchReliabilityIndicator("full_name")
        table_insert(tapped_word_collection, item)
        return

    elseif include_name_match and tapped_word and item.name:match("^" .. tapped_word_matcher) then
        item.reliability_indicator = DX.i:getMatchReliabilityIndicator("first_name")
        table_insert(tapped_word_collection, item)
        return

    elseif include_name_match and tapped_word and item.name:match(tapped_word_matcher .. "$") then
        item.reliability_indicator = DX.i:getMatchReliabilityIndicator("last_name")
        table_insert(tapped_word_collection, item)
        return

    elseif include_name_match and tapped_word and item.name:match(tapped_word_matcher) then
        item.reliability_indicator = DX.i:getMatchReliabilityIndicator("partial_match")
        table_insert(tapped_word_collection, item)
        return
    end

    --* include items which in their aliases match to the aliases of the needle item:
    local alias
    count = #aliases
    for i = 1, count do
        alias = aliases[i]:gsub("%-", "%%-")
        if parent:hasExactMatch(item.aliases, alias) then
            item.reliability_indicator = DX.i:getMatchReliabilityIndicator("alias")
            table_insert(tapped_word_collection, item)
            return
        end
    end
end

--* this method is only used for tapped word collections, put together based upon a word the user tapped in the reader text; called via ((XrayButtons#addTappedWordCollectionButton)):
function XrayTappedWords:getTypeAndReliabilityIcons(item)
    --* regular button insert:
    local icon = views_data:getItemTypeIcon(item)
    local status_indicators = icon

    --* to prevent that partial or whole matches are attributed to items which only have been added to the collection because they are a linked item:
    --* self.tapped_word was set in ((XrayTappedWords#itemExists)), the method which is also used to determine which items have to be added to the tapped word collection:
    local matches_with_tapped_word = self.tapped_word and item.name:find(self.tapped_word, 1, true)
    local alias_matches_with_tapped_word = self.tapped_word and (item.aliases:find(self.tapped_word, 1, true) or item.short_names:find(self.tapped_word, 1, true))

    local text = KOR.strings:lower(item.name)
    local ri = DX.i.match_reliability_indicators

    --* reliability_icons were added using ((xray match reliability indicators)):
    local status_indicator_color
    if matches_with_tapped_word and not alias_matches_with_tapped_word and item.reliability_indicator then
        status_indicators = item.reliability_indicator .. status_indicators
    elseif alias_matches_with_tapped_word then
        status_indicators = ri.alias .. status_indicators
    else
        status_indicators = DX.i:getMatchReliabilityIndicator("linked_item") .. status_indicators
        --* show linked items with lighter status indicator icons:
        status_indicator_color = KOR.colors.xray_item_status_indicators_color
    end

    --* store metadata for display later on the list of related items:
    self:storeCollectionMetadata(status_indicators)

    return icon, text, status_indicators, status_indicator_color
end

local function sort_by_name(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
end

--* note: this one *returns* a sorter function so it does not capture stale state:
local function make_sort_by_hits(hit_field)
    return function(a, b)
        return (a[hit_field] or 0) > (b[hit_field] or 0)
    end
end

--- @private
function XrayTappedWords:itemsSort(top1_count, top2_count, bottom_count)
    --* choose which hit field to sort by:
    local hit_field = (views_data.list_display_mode == "book") and "book_hits" or "series_hits"

    --* table sorter dispatcher:
    local sorter
    if parent.sorting_method == "hits" then
        sorter = make_sort_by_hits(hit_field)
    else
        sorter = sort_by_name
    end
    if top1_count > 1 then
        table.sort(self.at_top1_name_matches, sorter)
    end

    local related_items_sorted = self.at_top1_name_matches

    if top2_count > 1 then
        table.sort(self.at_top2_alias_matches, sorter)
    end
    local item
    for i = 1, top2_count do
        item = self.at_top2_alias_matches[i]
        table_insert(related_items_sorted, item)
    end
    if bottom_count > 1 then
        table.sort(self.bottom_linked_items, sorter)
    end
    for i = 1, bottom_count do
        item = self.bottom_linked_items[i]
        table_insert(related_items_sorted, item)
    end

    return related_items_sorted
end

function XrayTappedWords:doSimpleSearchScoreMatch(item)
    local name_lower = item.name:lower()
    local aliases_lower = item.aliases:lower()
    local short_names_lower = item.short_names:lower()
    local description = item.description:lower()
    local needle_lower = "%f[%w]" .. DX.vd.filter_string:lower() .. "%f[%W]"
    return (name_lower:match(needle_lower) or description:match(needle_lower) or aliases_lower:match(needle_lower) or short_names_lower:match(needle_lower)) and 100, DX.i:getMatchReliabilityIndicator("full_name") or 0, nil
end

--- @private
function XrayTappedWords:getMatchingRulesFromFilterString()
    local needle = DX.vd.filter_string
    local nlen = #needle
    return {
        { score = 100, key = "name", does_match = function(v)
            return v == needle or v == needle .. "s"
        end, indicator = "full_name" },
        { score = 100, key = "aliases", does_match = function(v)
            return v == needle
        end, indicator = "alias" },
        { score = 100, key = "short_names", does_match = function(v)
            return v == needle
        end, indicator = "alias" },

        { score = 70, key = "name", does_match = function(v)
            return v:sub(1, nlen) == needle
        end, indicator = "first_name" },
        { score = 70, key = "uc_name", does_match = function(v)
            return v:sub(1, nlen) == needle
        end, indicator = "first_name" },

        { score = 60, key = "name", does_match = function(v)
            return v:sub(-nlen) == needle
        end, indicator = "last_name" },
        { score = 60, key = "uc_name", does_match = function(v)
            return v:sub(-nlen) == needle
        end, indicator = "last_name" },

        { score = 50, key = "short_names", does_match = function(v)
            return v:find(needle, 1, true)
        end, indicator = "alias" },

        { score = 40, key = "name", does_match = function(v)
            return v:find(needle, 1, true)
        end, indicator = "partial_match" },
        { score = 40, key = "uc_name", does_match = function(v)
            return v:find(needle, 1, true)
        end, indicator = "partial_match" },
        { score = 30, key = "aliases", does_match = function(v)
            return v:find(needle, 1, true)
        end, indicator = "alias" },
        { score = 20, key = "linkwords", does_match = function(v)
            return v:find(needle, 1, true)
        end, indicator = "linked_item" },
    }
end

--- @private
function XrayTappedWords:getMatchingFields(item)
    local name = item.name
    local uc_name
    if not name:match("[A-Z]") then
        uc_name = KOR.strings:ucfirst(name, "force_only_first")
    end
    return {
        name = name,
        uc_name = uc_name,
        short_names = item.short_names,
        aliases = item.aliases,
        linkwords = item.linkwords,
    }
end

function XrayTappedWords:doScoreMatch(item)
    local fields = self:getMatchingFields(item)
    local rules = self:getMatchingRulesFromFilterString()
    local val, rule
    count = #rules
    for i = 1, count do
        rule = rules[i]
        val = fields[rule.key]
        if val and rule.does_match(val) then
            return rule.score, DX.i:getMatchReliabilityIndicator(rule.indicator)
        end
    end
    return 0, nil
end

--- @private
function XrayTappedWords:addLinkedItemCandidatesFor(candidates, term, index)
    local key = KOR.tables:normalizeTableIndex(term)
    if key and index[key] then
        local item
        count = #index[key]
        for i = 1, count do
            item = index[key][i]
            candidates[item] = true
        end
    end
end

--* this table was populated with icons in ((XrayButtons#forItemsCollectionPopup)) > ((store tapped word popup collection info)), and optionally will be used to generate a list of these items in ((XrayTappedWords#getCurrentListTabItems))
function XrayTappedWords:setPopupResult(sorted_items, popup_icons)
    self.popup_items = sorted_items
    count = #sorted_items
    self.popup_persons = {}
    self.popup_terms = {}
    local item
    for i = 1, count do
        item = self.popup_items[i]
        item.icons = popup_icons[i]
        if DX.m:isPerson(item) then
            table_insert(self.popup_persons, item)
        else
            table_insert(self.popup_terms, item)
        end
    end
end

function XrayTappedWords:setProp(name, value)
    self[name] = value
end

return XrayTappedWords
