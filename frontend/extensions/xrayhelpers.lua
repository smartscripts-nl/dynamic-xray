
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Colors = require("extensions/colors")
local Databases = require("extensions/databases")
local Device = require("device")
local Dialogs = require("extensions/dialogs")
local Event = require("ui/event")
local Font = require("ui/font")
local Icons = require("extensions/icons")
local KOR = require("extensions/kor")
local Registry = require("extensions/registry")
local Screen = Device.screen
local Strings = require("extensions/strings")
local Tables = require("extensions/tables")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
                and box.x + box.w >= x
                and box.y + box.h >= y then
            return true
        end
    end
end

-- used as registry for global vars:
--- @class XrayHelpers
local XrayHelpers = WidgetContainer:new{
    button_info = {
        add_item = "Add xray item.",
        edit_item = "Edit this xray-item.",
        lookup_in_dictionary = "Search for this word in the Dictionary.",
        show_item = "View this xray item.",
        show_context = "Show all locations for this xray-item.",
        toggle_main_xray_item = "Toggle importance (black or white icon) of this xray item.",
    },
    current_ebook_or_series = nil,
    ebooks = {},
    families_matched_by_multiple_parts = {},
    forbidden_words = {
        Look = 1,
        This = 1,
        Thou = 1,
    },
    hits_buttons_max = 30,
    -- partially disable clicks on xray lines (for region closest to left side of ereader):
    inert_left_region_width = 25,
    info_mode = G_reader_settings:readSetting("xray_info_mode") or "paragraph",
    max_buttons_per_row = 4,
    max_line_length = 72,
    min_match_word_length = 4,
    paragraph_texts = nil,
    queries = {
        create = "INSERT INTO xray_items (ebook, name, short_names, description, xray_type, aliases, linkwords, hits) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",

        update = "UPDATE xray_items SET name = ?, short_names = ?, description = ?, xray_type = ?, aliases = ?, linkwords = ?, hits = ? WHERE ebook = ? AND id = ?",
    },
    separator = " " .. Icons.arrow_bare .. " ",
    -- will be set at run time in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)):
    show_xray_explanations = true,
    xray_icons = {
        Icons.user_bare .. " ",
        Icons.user_dark_bare .. " ",
        Icons.introduction_bare .. " ",
        Icons.introduction_done_bare .. " ",
    },
    xray_icons_bare = {
        Icons.user_bare,
        Icons.user_dark_bare,
        Icons.introduction_bare,
        Icons.introduction_done_bare,
    },
    xray_info_extra_button_rows = {},
    xray_info_max_total_buttons = 16,
    xray_info_use_upper_case_names = false,
    xray_info_extra_indent = "    ",
    xray_info_indent = "     ",
    xray_items = {},
    xray_items_terms = {},
    xray_items_persons = {},
    xray_matches = nil,
    xray_page = nil,
}

--[[
Props needed when you want to add a more button:

nr add_more_button max_total_buttons source_items callback extra_item_callback is_bold (optionally, for when you want to indicate a string has been found in text selection e.g.)

When a more button has been added, this method returns true, so the caller knows it has to break its loop through the source items.
]]
function XrayHelpers:addButton(button_table, xray_item, data)
    local callback = data.callback
    local extra_item_callback = data.extra_item_callback
    local nr = data.nr
    local max_buttons_per_row = data.max_buttons_per_row or self.max_buttons_per_row
    local max_total_buttons = data.max_total_buttons

    if nr == 1 or (nr - 1) % max_buttons_per_row == 0 then
        table.insert(button_table, {})
    end
    local current_row = #button_table
    local add_more_button = nr == max_total_buttons and #data.source_items > max_total_buttons

    if add_more_button and max_total_buttons and nr and nr == max_total_buttons then
        ButtonDialogTitle:addMoreButton(button_table, {
            -- popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons - this prop to be consumed in ((ButtonDialogTitle#handleMoreButtonClick)):
            max_total_buttons_after_first_popup = max_total_buttons + 16,
            max_total_buttons = max_total_buttons,
            current_row = current_row,
            popup_buttons_per_row = max_buttons_per_row,
            source_items = data.source_items,
            title = " extra xray-items:",
            icon_generator = self,
            item_callback = function(citem)
                extra_item_callback(citem)
            end,
            -- this is needed to support multiple more... popups in ((ButtonDialogTitle#handleMoreButtonClick)):
            extra_item_callback = function(citem)
                extra_item_callback(citem)
            end,
            item_hold_callback = function(citem, icon)
                Dialogs:textBox({
                    title = icon .. citem.name,
                    info = self:getInfo(citem),
                    use_computed_height = true,
                })
            end,
        })
        -- signal that more button has been added:
        return true
    end

    -- regular button insert:
    local icon = self:getIcon(xray_item)
    local text = icon .. " " .. Strings:lower(xray_item.name)
    -- hit_reliability_cions were added in ((XrayHelpers#getReliabilityIcon)):
    if xray_item.hit_reliability_cion then
        text = xray_item.hit_reliability_cion .. text
    else
        text = Icons.xray_link_bare .. text
    end
    table.insert(button_table[current_row], {
        text = text,
        -- is_bold prop was set in ((XrayHelpers#sortByBoldProp)):
        font_bold = xray_item.is_bold,
        text_font_face = Font:getFace("x_smallinfofont"),
        font_size = 18,
        callback = function()
            callback()
        end,
        hold_callback = function()
            Dialogs:textBox({
                title = icon .. " " .. xray_item.name,
                title_shrink_font_to_fit = true,
                info = self:getInfo(xray_item),
                use_computed_height = true,
            })
        end,
    })
end

-- current method called from 2 locations in ReaderHighlight: ((ReaderHighlight#onShowHighlightMenu)) and ((ReaderHighlight#lookup))
function XrayHelpers:getXrayItemAsDictionaryEntry(tapped_word, ui)

    KOR.xrayitems:initDataJIT()

    -- First try to treat the word as the name of an XrayItem:
    local spaces_count = Strings:substrCount(tapped_word, " ")
    -- don't allow larger strings which contain a saved name to trigger hits:
    if spaces_count <= 1 then
        -- match by name only is falsy in this case:
        local items_found = self:itemExists(tapped_word, tapped_word)
        if items_found then

            -- #((xray_item as dictionary plugin pre dialog))
            -- compare the buttondialog upon adding a xray_item in ((add xray_item pre dialog)):

            if not ui then
                ui = Registry:getUI()
            end
            if #items_found > 1 then

                -- is_bold prop will here be added to items:
                local copies = self:sortByBoldProp(items_found, tapped_word)

                local buttons = {}
                local buttons_count = 0
                local add_more_button = #copies > self.hits_buttons_max
                local item_with_alias_found = false
                for nr, item in ipairs(copies) do

                    local is_alias = item.hit_reliability_cion and item.hit_reliability_cion == Icons.xray_alias_bare
                    local is_non_bold_alias = is_alias and not item.is_bold
                    if is_non_bold_alias then
                        item_with_alias_found = true
                    end
                    if not is_alias or not item_with_alias_found then
                        buttons_count = buttons_count + 1
                        local more_button_added = self:addButton(buttons, item, {
                            add_more_button = add_more_button,
                            max_total_buttons = self.hits_buttons_max,
                            max_buttons_per_row = self.max_buttons_per_row,
                            nr = nr,
                            source_items = copies,
                            is_bold = item.is_bold,
                            callback = function()
                                --UIManager:close(self.xray_item_chooser)
                                KOR.xrayitems:onShowXrayItem(copies[nr])
                            end,
                            extra_item_callback = function(citem)
                                KOR.xrayitems:onShowXrayItem(citem)
                            end,
                        })
                        if more_button_added then
                            break
                        end
                    end
                end
                table.insert(buttons, {
                    {
                        text = Icons.list_bare,
                        callback = function()
                            KOR.xrayitems:onShowXrayList()
                        end,
                        hold_callback = function()
                            Dialogs:alertInfo("Show list of xray items.")
                        end,
                    },
                    {
                        text = Icons.filter_bare,
                        callback = function()
                            UIManager:close(self.xray_item_chooser)
                            KOR.xrayitems:onShowXrayList(nil, false, "filter_immediately")
                        end,
                        hold_callback = function()
                            Dialogs:alertInfo("Show list of xray items and filter that immediately.")
                        end,
                    },
                    {
                        icon = "info",
                        icon_size_ratio = 0.53,
                        callback = function()
                            Dialogs:textBoxTabbed(1, {
                                title = "Explanation of Xray buttons",
                                modal = true,
                                tabs = {
                                    {
        tab = "bold items",
        info = "BOLD ITEMS\n\nItems in bold lay-out contain the selected text in their main name or their aliases. Bold items will always be shown at the start of the group of buttons.\n\nNon-bold items were linked from a bold item or share a link-term with a bold item.",
                                    },
                                    {
                                        tab = "hit reliability icons",
                                        info = self:getXrayHitsReliabilityExplanation(),
                                    },
                                },
                            })
                        end
                    },
                    {
                        icon = "appbar.search",
                        icon_size_ratio = 0.6,
                        callback = function()
                            UIManager:close(self.xray_item_chooser)
                            KOR.xrayitems:onShowXrayItemLocations(tapped_word)
                        end,
                        hold_callback = function()
                            Dialogs:alertInfo("Show all text locations where the name of this xray item is being mentioned in the current book.")
                        end,
                    },
                    {
                        text = Icons.book_bare,
                        fgcolor = Colors.lighter_text,
                        enabled = has_text(tapped_word),
                        callback = function()
                            ui:handleEvent(Event:new("LookupWord", tapped_word))
                        end,
                        hold_callback = function()
                            Dialogs:alertInfo("Search for this word in the dictionaries.")
                        end,
                    },
                    {
                        text = "+",
                        fgcolor = Colors.lighter_text,
                        callback = function()
                            UIManager:close(self.xray_item_chooser)
                            KOR.xrayitems:onAddXrayItemShowForm(tapped_word)
                        end,
                        hold_callback = function()
                            Dialogs:alertInfo("Add xray item.")
                        end,
                    },
                })
                -- #((multiple related xray items found))
                self.xray_item_chooser = ButtonDialogTitle:new{
                    title = tapped_word .. Icons.arrow .. buttons_count .. " xray-items found:",
                    title_align = "center",
                    use_low_title = true,
                    after_close_callback = function()
                        self.xray_item_chooser = nil
                    end,
                    buttons = buttons,
                }
                UIManager:show(self.xray_item_chooser)
                return true

                -- when only a single item found, show it immediately:
            elseif #items_found > 0 then
                -- false for called_from_list:
                KOR.xrayitems:onShowXrayItem(items_found[1], false, tapped_word)
                return true
            end
        end
    end
    return false
end

-- these matches are to be consumed in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) > ((XrayHelpers#showXrayItemsInfo))
function XrayHelpers:getXrayInfoMatches(paragraph)

    local part_hits, hits, explanations = {}, {}, {}
    local multiple_parts_count = 0
    local a_hit_was_found, an_alias_hit_was_found = false, false
    self.families_matched_by_multiple_parts = {}

    for _, xray_item in ipairs(self.xray_items) do
        local hit_found, alias_hit_found = false, false
        local short_names = has_text(xray_item.short_names)
        local xray_name = xray_item.name
        local names = short_names and Strings:split(short_names, ", *") or { xray_name }
        for nr, xname in ipairs(names) do
            hit_found, multiple_parts_count = self:matchNameToParagraph(paragraph, xname, hits, part_hits, explanations, xray_item, nr)
            if hit_found then
                a_hit_was_found = true
                break
            end
            if has_text(xray_item.aliases) then
                alias_hit_found = self:matchAliasesToParagraph(paragraph, hits, explanations, xray_item)
                if alias_hit_found then
                    an_alias_hit_was_found = true
                    break
                end
            end
        end
    end

    local skip_items = {}
    if (a_hit_was_found or an_alias_hit_was_found) then

        hits, explanations = self:reduceParagraphMatches(hits, part_hits, explanations)

        hits, explanations, skip_items = self:removePartialHitsIfFullHitFound(hits, explanations, part_hits)
    end

    if #hits == 0 then
        return
    end
    return hits, explanations, skip_items
end

-- remove duplicated hits and hits by incorrect names matching another item's surname
function XrayHelpers:reduceParagraphMatches(hits, part_hits, explanations)
    -- when hits found for families with name and surname, remove all items which only match on surname:
    local reduced = {}
    local reduced_explanations = {}
    local processed_names = {}
    for nr, xray_item in ipairs(hits) do

        local xray_name = xray_item.name

        local first_name_matches_a_surname = false
        local has_family_name = xray_name:match(" ") and xray_name:match("[A-Z]")
        local family_name = xray_name:gsub("^.+ ", "")
        local partial_hits = part_hits[xray_name]
        local multiple_hits = self.families_matched_by_multiple_parts[family_name]
        local skip_partial_hit = multiple_hits == 0 and partial_hits and partial_hits > 0
        if not processed_names[xray_name] then
            -- whole name matches must always be kept:
            if multiple_hits == 0 and partial_hits == 0 then
                table.insert(reduced, xray_item)
                table.insert(reduced_explanations, explanations[nr])
                processed_names[xray_name] = 1

                -- when full name and surname found in a paragraph, e.g. Thomas Carlyle), but also found the single name Carlyle, prevent Carlyle Foster to be counted as a hit:
            elseif not skip_partial_hit and partial_hits == 1 and has_family_name then
                local first_name = xray_name:gsub(" .+$", "")
                if self.families_matched_by_multiple_parts[first_name] then
                    first_name_matches_a_surname = true
                end
            end
            if not first_name_matches_a_surname and (not multiple_hits or partial_hits) then
                table.insert(reduced, xray_item)
                table.insert(reduced_explanations, explanations[nr])
                processed_names[xray_name] = 1
            end
        end
    end
    return reduced, reduced_explanations
end

function XrayHelpers:sortByBoldProp(items, needle)
    local copies = {}
    for nr, xray_item in ipairs(items) do
        local copy = Tables:shallowCopy(xray_item)
        needle = needle:gsub("%-", "%%-")
        copy.is_bold1 = xray_item.name:match(needle) and true or false
        copy.is_bold2 = has_text(xray_item.aliases) and xray_item.aliases:match(needle) and true or false

        -- is_bold prop MUST be set to either false or true, to be used in ((ButtonTable#init)):
        copy.is_bold = copy.is_bold1 or copy.is_bold2

        table.insert(copies, copy)
        self.garbage = nr
    end
    return Tables:sortByPrimaryOrSecondaryPropIsTrue(copies, "is_bold1", "is_bold2")
end

-- upgrade a placeholder needle_item derived from tapped text (needle_item.name) in the ebook to a regular xray item, if the name or aliases of that xray item match the tapped text:
function XrayHelpers:upgradeNeedleItem(needle_item, args, for_relations)
    local upgraded = false
    local tapped_word = args.tapped_word
    if args.include_name_match and has_text(needle_item.name) then
        local matcher = needle_item.name:gsub("%-", "%%-")
        local partial_matches = {}
        for i = 1, 2 do
            for __, item in ipairs(self.xray_items) do

                -- info: for lowercase Xray items also compare for ucfirst (start of sentence) items; compare ((xray items list matches for text variant)):
                -- #((tapped word matches for text variant))
                local do_match_for_lowercase_variant = not item.name:match("[A-Z]")
                local uc_first_name = Strings:ucfirst(item.name, "force_only_first")

                if i == 1
                    and (not tapped_word or tapped_word == item.name or (do_match_for_lowercase_variant and tapped_word == uc_first_name))
                    and (needle_item.index == item.index or needle_item.name == item.name or item.name:match("^" .. matcher .. "s$")) or (do_match_for_lowercase_variant and uc_first_name:match("^" .. matcher .. "s$"))
                then
                    if for_relations then
                        item.hit_reliability_cion = self:getReliabilityIcon("full name")
                        item = { item }
                    end
                    -- second returned value is for item was upgraded status and third for upgraded by exact match:
                    return item, true, true

                elseif i == 2
                    and (item.name:match("^" .. matcher)
                    or (do_match_for_lowercase_variant and uc_first_name:match("^" .. matcher)
                ))
                then
                    if for_relations then
                        item.hit_reliability_cion = self:getReliabilityIcon("first name")
                    end
                    table.insert(partial_matches, item)
                    upgraded = true

                elseif i == 2
                    and (item.name:match(matcher .. "s?$") or (do_match_for_lowercase_variant and uc_first_name:match(matcher .. "s?$")))
                then
                    if for_relations then
                        item.hit_reliability_cion = self:getReliabilityIcon("last name")
                    end
                    table.insert(partial_matches, item)
                    upgraded = true

                elseif i == 2
                    and item.name:match(matcher)
                    or (do_match_for_lowercase_variant and uc_first_name:match(matcher))
                then
                    if for_relations then
                        item.hit_reliability_cion = self:getReliabilityIcon("part/parts")
                    end
                    table.insert(partial_matches, item)
                    upgraded = true

                elseif i == 2 and item.aliases:match(matcher) then
                    if for_relations then
                        item.hit_reliability_cion = self:getReliabilityIcon("alias found")
                    end
                    table.insert(partial_matches, item)
                    upgraded = __
                end
            end
        end
        if #partial_matches > 0 then
            if for_relations then
                return partial_matches, true, false
            end
            return partial_matches[1], true, false
        end
    end
    return needle_item, false, false
end

function XrayHelpers:setParagraphsFromDocument()
    -- before drawing sideline icons, first expand them with clickable xray item marks (stars)....
    -- populated in ((CreDocument#storeCurrentPageParagraphs)):
    local paragraphs = KOR.document.paragraphs
    -- hotfix: ui_page not updated anymore after visiting a page two or more times:
    local ui_page = KOR.document.start_page_no
    local check_page = KOR.document.info.has_pages and self.ui.paging.current_page or self.ui:getCurrentPage()
    if ui_page ~= check_page then
        ui_page = check_page
        local xp = KOR.document:getPageXPointer(ui_page)
        KOR.document:storeCurrentPageParagraphs(xp, ui_page)
        paragraphs = KOR.document.paragraphs
    end
    self.paragraphs = paragraphs

    return ui_page
end

function XrayHelpers:addLinkedItem(stage, needle_item, compare_item, linkwords, linked_names_index, linked_items)
    if compare_item.name ~= needle_item.name then
        for _, linkword in ipairs(linkwords) do
            linkword = linkword:gsub("%-", "%%-")
			local needle = stage == 1 and compare_item.name or needle_item.name
            if self:hasExactMatch(needle, linkword) and not linked_names_index[compare_item.name] then
                table.insert(linked_items, compare_item)
                linked_names_index[compare_item.name] = true
				if stage == 2 then
					break
				end
            end
        end
    end
end

-- ((XrayHelpers#upgradeNeedleItem)) has to be called in the caller context, before calling getRelatedItems:
function XrayHelpers:getLinkedItems(needle_item)

    -- info: don't return here when needle_item has no linkwords, because we also search in the other xray items, to see if THEIR linkwords match to the name of the needle_item...
    local linked_items, linked_names_index = {}, {}
    local linkwords = self:splitByCommaOrSpace(needle_item.linkwords, "add_singulars") or {}

    for _, compare_item in ipairs(self.xray_items) do
        -- add items which are linked by the keywords in needle_item:
        self:addLinkedItem(1, needle_item, compare_item, linkwords, linked_names_index, linked_items)
        if not linked_names_index[compare_item.name] and has_text(compare_item.linkwords) then
            -- add items which link via THEIR linkwords to the needle_item:
            local other_linkwords = self:splitByCommaOrSpace(compare_item.linkwords, "add_singulars")
            self:addLinkedItem(2, needle_item, compare_item, other_linkwords, linked_names_index, linked_items)
        end
    end
    if #linked_items > 1 then
        linked_items = Tables:sortByPropAscendingAndSetTopItems(linked_items, "name", function(xray_item)
            return xray_item.xray_type == 2 or xray_item.xray_type == 4
        end)
    end
    return linked_items, linked_names_index
end

-- include_name_match is only truthy when we pressed a word in the ebook text:
-- ((XrayHelpers#upgradeNeedleItem)) has to be called in the caller context, before calling getRelatedItems:
function XrayHelpers:getRelatedItems(needle_items, compare_multiple_items, include_name_match, needle_matches_fullname, tapped_word)

    local extra_items = {}
    -- compare_multiple_items is truthy when tapping a word in the ebook:
    if not compare_multiple_items then
        needle_items = { needle_items }
    end

    -- get keywords derived from name AND linkwords of needle_item:
    for _, needle_item in ipairs(needle_items) do

        local aliases = has_text(needle_item.aliases) and self:splitByCommaOrSpace(needle_item.aliases, "add_singulars") or {}

        for __, item in ipairs(self.xray_items) do
            __ = self:matchItemToNeedleItem(extra_items, item, needle_item, include_name_match, aliases, tapped_word)
        end
        if #extra_items > 1 then
            extra_items = Tables:sortByPropAscendingAndSetTopItems(extra_items, "name", function(xray_item)
                return xray_item.xray_type == 2 or xray_item.xray_type == 4
            end)
            local exact_match_at_start = {}
            local previous_name
            for _, item in ipairs(extra_items) do

                -- place fullname match at start of the buttons:
                if needle_matches_fullname and (item.name == needle_item.name or item.name:match("^" .. needle_item.name .. "s$")) then
                    table.insert(exact_match_at_start, 1, item)
                    previous_name = item.name

                    -- filter away duplicated items:
                elseif item.name ~= previous_name then
                    table.insert(exact_match_at_start, item)
                    previous_name = item.name
                end
            end
            extra_items = exact_match_at_start
        end
    end
    return extra_items
end

function XrayHelpers:getXrayItemsCount(file_basename)
    if not file_basename then
        return
    end
    local xray_items = XrayHelpers.ebooks[file_basename] or {}
    return #xray_items
end

-- Search for xray_item to be saved in all stored xray_items. match_by_name_only: falsy in case of tapped words in ebook. Let the xray_items manager know whether a hit has been found:
function XrayHelpers:itemExists(string_or_object, tapped_word, match_by_name_only)
    local needle_item, item_upgraded, needle_matches_fullname
    local include_name_match = true
    if type(string_or_object) == "string" or string_or_object.text then
        needle_item = {
            description = "",
            name = type(string_or_object) == "string" and string_or_object or string_or_object.text,
            short_names = "",
            aliases = "",
            linkwords = "",
            xray_type = 1,
        }
        -- for regular xray items with a name field:
    else
        needle_item = string_or_object
    end
    needle_item, item_upgraded, needle_matches_fullname = self:upgradeNeedleItem(needle_item, {
        include_name_match = include_name_match,
        match_by_name_only = match_by_name_only,
        tapped_word = tapped_word,
    }, "for_relations")
    if not item_upgraded then
        return
    end
    return self:getRelatedItems(needle_item, "compare_multiple_items", include_name_match, needle_matches_fullname, tapped_word)
end

-- called from ReaderView:
function XrayHelpers:ReaderViewGenerateXrayInformation(ui, bb, x, y)

    self.ui = ui
    self.xray_page = self:setParagraphsFromDocument()
    self.xray_matches = {}
    local marker, marker_width = self:getXrayMarker(bb)
    self.xray_page_info_rects = nil
    self:ReaderViewSetXrayContextProps(marker, marker_width, bb, x, y)
    -- #((set xray info for paragraphs))
    if self:ReaderViewInitParaOrPageData() then
        self:ReaderViewPopulateInfoRects()
    end
end

function XrayHelpers:ReaderViewInitParaOrPageData()

    -- text of paragraphs, for debugging:
    self.paragraphs_with_hits = {}
    self.paragraph_hits = {}
    self.paragraph_explanations = {}
    self.rects_with_hits = {}
    self.xray_info_found = false
    -- register partial hits to be skipped per paragraph. This filter will be executed upon clicking on the first line of the concerned paragraph. See ((skip partial name matches if familiy member with full name also found)):
    self.skip_xray_items = {}
    local screen_width = Screen:getWidth()
    if self.paragraphs and #self.xray_items > 0 then
        local page_text = self:getFullPageText()
        for i = 1, #self.paragraphs do
            local marker_line_found = self:ReaderViewLoopThroughParagraphOrPage(page_text, i, screen_width)
            if self.info_mode == "page" and marker_line_found then
                break
            end
        end
    end
    return self.xray_info_found
end

function XrayHelpers:ReaderViewSetXrayContextProps(marker, marker_width, bb, x, y)
    self.xray_context_props = {
        marker = marker,
        marker_width = marker_width,
        bb = bb,
        x = x,
        y = y,
    }
end

-- see ((DYNAMIC XRAY PLUGIN)) for more info:
function XrayHelpers:ReaderViewLoopThroughParagraphOrPage(page_text, p, screen_width)
    local haystack = self.info_mode == "paragraph" and self.paragraphs[p].text or page_text
    local hits, explanations, skip_items = self:getXrayInfoMatches(haystack)
    if hits then
        -- for debugging only:
        table.insert(self.paragraphs_with_hits, self.paragraphs[p].text)
        -- to be consumed in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)):
        table.insert(self.paragraph_hits, hits)
        table.insert(self.paragraph_explanations, explanations)
        table.insert(self.skip_xray_items, skip_items)
        for xi = 1, #hits do
            local name = hits[xi].name
            if not self.xray_matches[name] then
                self.xray_matches[name] = 1
                self.xray_info_found = true
            end
        end
        -- this context table with props was set in ((set xray info for paragraphs)):
        local c = self.xray_context_props
        if c.bb then
            local lines = KOR.document:getScreenBoxesFromPositions(self.paragraphs[p].pos0, self.paragraphs[p].pos1, true)
            local lines_count = #lines
            if self.info_mode == "page" and p == 1 and lines_count == 1 then
                return false
            end
            local rect
            -- make top line available for menu presses, by moving the xray line marker to line no 2 or farther down the page:
            local start = p == 1 and 2 or 1
            for l = start, lines_count do
                -- lines only have position and dimensions data, no text...
                local compare = lines[l]
                if compare.w > screen_width / 3 then
                    rect = compare
                    break
                end
            end

            if rect then
                -- hotfix: on Boox Page rect and xray marker were sometimes incorrectly drawn on the right half of the screen:
                -- #((set half screen width))
                if not Registry.half_screen_width then
                    -- this Registry var can be updated upon rotation in ((ReaderView#onRotationUpdate)):
                    Registry.half_screen_width = Screen:getWidth() / 2
                end

                if rect.w > self.inert_left_region_width + 20 then
                    rect.x = rect.x + self.inert_left_region_width
                    rect.w = rect.w - self.inert_left_region_width
                end
                self:drawMarker(self.ui, c.bb, c.x, c.y, rect, c.marker, c.marker_width)
                table.insert(self.rects_with_hits, rect)

                return true
            end
        end
    end
    return false
end

function XrayHelpers:ReaderViewPopulateInfoRects()
    -- #((set xray page info rects))
    -- to be consumed in ((ReaderHighlight#onTapXPointerSavedHighlight)):
    self.xray_page_info_rects = {
        paragraph_texts = self.paragraphs_with_hits,
        hits = self.paragraph_hits,
        skip_xray_items = self.skip_xray_items,
        explanations = self.paragraph_explanations,
        rects = self.rects_with_hits,
        callback = function(paragraph_hits_info, extra_button_rows, paragraph_text)
            -- paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
            self:showXrayItemsInfo(paragraph_hits_info, extra_button_rows, paragraph_text)
        end
    }
end

function XrayHelpers:ReaderHighlightGenerateXrayInformation(pos)
    self.show_xray_explanations = G_reader_settings:isTrue("xray_show_explanations")

    -- this var, containing texts and hits info, was defined above in ((XrayHelpers#ReaderViewGenerateXrayInformation)) > ((XrayHelpers#getXrayInfoMatches)) > ((set xray info for paragraphs)):
    local xray_rects = self.xray_page_info_rects
    if xray_rects then
        self.paragraph_texts = xray_rects.paragraph_texts
        local rects = xray_rects.rects
        self.xray_info_extra_button_rows = {}
        for nr, rect in ipairs(rects) do
            if inside_box(pos, rect) then
                self:generateParagraphInformation(xray_rects, nr)
                return true
            end
        end
    end
end

-- called from ((TextViewer#findCallback)):
function XrayHelpers:removeHitReliabilityIcons(subject)
    return subject
        :gsub(Icons.xray_full_bare, "")
        :gsub(Icons.xray_alias_bare, "")
        :gsub(Icons.xray_partial_bare, "")
        :gsub(Icons.xray_half_left_bare, "")
        :gsub(Icons.xray_half_right_bare, "")
        :gsub(Icons.xray_link_bare, "")
end

-- information for this dialog was generated in ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation))
-- extra buttons (from xray items) were populated in ((XrayHelpers#ReaderHighlightGenerateXrayInformation))
-- current method called from callback in ((xray paragraph info callback)):
function XrayHelpers:showXrayItemsInfo(hits_info, headings, hits_count, extra_button_rows, haystack_text)
    local debug = false
    local info = hits_info
    if not self.xray_info_dialog and has_text(info) then
        -- paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
        if debug and haystack_text then
            info = haystack_text .. "\n\n" .. info
        end
        local hits_count_info = hits_count == 1 and "1 item" or hits_count .. " items"
        local subject = self.info_mode == "paragraph" and "paragraph" or "page"
        local target = self.info_mode == "paragraph" and "in the WHOLE PAGE" or "PARAGRAPHS"
        local new_trigger = self.info_mode == "paragraph" and "a sentence marked with a lightning-icon" or "a paragraph marked with a star"
        -- the data below was populated in ((XrayHelpers#ReaderViewGenerateXrayInformation)):
        self.xray_info_dialog = Dialogs:textBox({
            title = "Xray information for this " .. subject .. " - " .. hits_count_info,
            info = info,
            fullscreen = true,
            covers_fullscreen = true,
            top_buttons_left = {
                {
                    text = self.info_mode == "paragraph" and Icons.paragraph_bare or Icons.page_bare,
                    fgcolor = Colors.lighter_text,
                    font_bold = false,
                    icon = self.info_mode == "paragraph" and "paragraph" or "pages",
                    callback = function()
                        local question = "\nDo you indeed want to toggle the display of xray items to %s mode?\n\nAfter applying this toggle long press %s in the side line, to access items in this new mode...\n"
                        question = question:format(target, new_trigger)
                        Dialogs:confirm(question, function()
                            self.info_mode = self.info_mode == "paragraph" and "page" or "paragraph"
                            G_reader_settings:saveSetting("xray_info_mode", self.info_mode)
                            UIManager:close(self.xray_info_dialog)
                            self.xray_info_dialog = nil
                            UIManager:setDirty(nil, "full")
                        end)
                    end,
                    hold_callback = function()
                        Dialogs:alertInfo("Toggle between xray item markers for current page or for current paragraphs.")
                    end,
                },
            },
            paragraph_headings = headings,
            fixed_face = Font:getFace("x_smallinfofont"),
            close_callback = function()
                self.xray_info_dialog = nil
                Dialogs:closeOverlay()
            end,
            -- #((xray paragraph info: after load callback))
            --- @param target_class TextViewer
            after_load_callback = function(target_class)
                if #headings > 2 then
                    -- #((call TextViewer TOC))
                    -- call ((TextViewer#init)) > ((TextViewer execute after load callback)) > ((TextViewer#showToc)) after a short delay:
                    target_class:showToc()
                end
            end,
            -- #((inject xray list buttons))
            -- info: for special buttons like index and navigation arrows see ((TextViewer toc button)):
            extra_button_position = 1,
            extra_button = {
                text = Icons.list_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    KOR.xrayitems:onShowXrayList()
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Show list of xray items.")
                end,
            },
            extra_button2_position = 2,
            extra_button2 = {
                text = Icons.filter_bare,
                callback = function()
                    UIManager:close(self.xray_item_chooser)
                    KOR.xrayitems:onShowXrayList(nil, false, "filter_immediately")
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Show list of xray items and filter that immediately.")
                end,
            },
            extra_button3_position = 3,
            extra_button3 = {
                icon = "info",
                icon_size_ratio = 0.53,
                callback = function()
                    Dialogs:confirm("\nDo you indeed want to toggle the display of \"Explanation:\"-lines? If you disable these lines, some information will be lost.\n", function()
                        local display_explanations = G_reader_settings:isTrue("xray_show_explanations")
                        display_explanations = not display_explanations
                        -- this setting will be read in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)):
                        G_reader_settings:toggle("xray_show_explanations")
                        UIManager:close(self.xray_info_dialog)
                        local message = display_explanations and "\nExplanation of hits ENABLED..." or "\nExplanation of hits DISABLED..."
                        message = message .. "\n\nChange will be visible upon next tap on the sentence with an xray marker (for page or paragraph).\n"
                        Dialogs:alertInfo(message, 5)
                    end)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Hide or display explanation lines. Warning: when hiding these lines, some information will be lost!")
                end,
            },
            extra_button_rows = extra_button_rows,
        })
    end
end

-- called from ((TextViewer#showToc)) or ((XrayHelpers#getXrayItemAsDictionaryEntry)), for info icon:
function XrayHelpers:getXrayHitsReliabilityExplanation()
    local explanations = {
        Icons.xray_full_bare .. " full name",
        Icons.xray_alias_bare .. " alias",
        Icons.xray_half_left_bare .. " first name",
        Icons.xray_half_right_bare .. " last name",
        Icons.xray_partial_bare .. " partial hit",
        Icons.xray_link_bare .. " linked item",
    }
    local message = "XRAY RELIABILITY ICONS\n\nThe type of the hit determines the associated icon. Full names, aliases and linked items yield the most reliable hits:\n\n"
    for _, lemma in ipairs(explanations) do
        message = message .. lemma .. "\n"
    end
    return message
end

function XrayHelpers:drawRect(bb, _x, _y, rect)
    -- hotfix for portrait files?
    if not rect then
        return
    end
    -- garbage collection:
    _x = _y

    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    bb:paintRect(x, y + h, w, 1, Blitbuffer.COLOR_GRAY)
end

function XrayHelpers:drawMarker(ui, bb, _x, _y, rect, marker, marker_width)
    -- hotfix for portrait files?
    if not rect then
        return
    end
    -- garbage collection:
    _x = _y

    local x, y = rect.x, rect.y
    if marker then
        local note_mark_pos_x

        local screen_width = Screen:getWidth()
        local half_screen_width = math.floor(screen_width / 2)
        --the bigger the correction, the more to the left the marker:
        local middle_correction = marker_width - 9
        local right_correction = marker_width
        if Registry.is_ubuntu_device then
            right_correction = right_correction - 3
        end
        local is_xray_page_mode = self.info_mode == "page"
        if ui.document:getVisiblePageCount() == 1 then
            -- page 1 in one-page mode
            note_mark_pos_x = screen_width - right_correction

        elseif is_xray_page_mode and x < half_screen_width then
            -- page 1 in two-page mode in xray page mode:
            note_mark_pos_x = rect.x + rect.w

        elseif x < half_screen_width then
            -- #((set xray marker position))
            -- compare ((set xray marker size))
            local shift_amount = Registry.is_android_device and 22 or 10
            local shift = is_xray_page_mode and shift_amount or 0
            -- page 1 in two-page mode in paragraph mode:
            note_mark_pos_x = half_screen_width - middle_correction + shift
        else
            --note_mark_pos_x = self.tags_mark_pos_x2
            note_mark_pos_x = screen_width - right_correction
        end

        -- when we underline bookmarks to indicate notes, we also want to draw the custom marker icon:
        -- note_mark_pos_x will only be not null for bookmarks with tags:
        if note_mark_pos_x then
            --[[local face = Font:getFace(font_name, font_size)
			local face_height = face.ftsize:getHeightAndAscender()]]
            local y_pos_shift = Registry.is_ubuntu_device and 6 or 12
            local y_pos = y + y_pos_shift
            if self.info_mode == "page" then
                y_pos = y_pos - 7
            end
            marker:paintTo(bb, note_mark_pos_x, y_pos)
        end

    end
end

function XrayHelpers:getXrayItemsForEbook(file_basename, series)
    if has_text(series) and self.ebooks[series] then
        return self.ebooks[series]
    end
    return self.ebooks[file_basename]
end

function XrayHelpers:getXrayMarker(bb)
    local marker, marker_width
    if bb then
        -- #((set xray marker size))
        -- compare ((set xray marker position))
        local size = self.info_mode == "paragraph" and 10 or 18
        marker = TextWidget:new{
            text = self.info_mode == "paragraph" and Icons.xray_item or Icons.lightning_bare,
            face = Font:getFace("smallinfofont", size),
            fgcolor = Colors.xray_page_or_paragraph_hit_marker,
            padding = 0,
        }
        marker_width = marker:getSize().h
    end
    return marker, marker_width
end

-- current_ebook always given, but current_series only set when book is part of a series; this series name will be stored in table field xray_items.ebook:
function XrayHelpers:loadAllXrayItems(current_ebook, current_series, force_refresh)
    local has_series_index = false

    -- disable caching while we are still updating hits in database:
    local conn = Databases:getDBconnForStatistics("XrayHelpers#loadAllXrayItems")
    local sql_stmt = "SELECT id FROM xray_items WHERE ebook = ? AND ebook_hits_retrieved = 1 LIMIT 1"
    local result = conn:rowexec(sql_stmt)
    if not result then
        force_refresh = true
    end

    if not force_refresh then
        if current_ebook and self.ebooks[current_ebook] then
            self.current_ebook_or_series = current_ebook
            self.xray_items = self.ebooks[current_ebook]
            return has_series_index
        end
        if has_text(current_series) and self.ebooks[current_series] then
            self.current_ebook_or_series = current_series
            self.xray_items = self.ebooks[current_series]
            has_series_index = true
            return has_series_index
        end
    end

    sql_stmt = "SELECT id, ebook, name, short_names, description, xray_type, aliases, linkwords, hits, ebook_hits_retrieved FROM xray_items ORDER BY ebook, name"
    result = conn:exec(sql_stmt)
    XrayHelpers.ebooks = {}
    local update_hits_for_current_ebook = false
    for i = 1, #result["ebook"] do
        local ebook_or_series = result["ebook"][i]
        if not self.ebooks[ebook_or_series] then
            self.ebooks[ebook_or_series] = {}
        end

        local id = tonumber(result["id"][i])
        local name = result["name"][i]
        local aliases = result["aliases"][i] or ""
        local hits = tonumber(result["hits"][i])
        local hits_retrieved_for_ebook = tonumber(result["ebook_hits_retrieved"][i])

        if not update_hits_for_current_ebook and ebook_or_series == current_ebook and hits_retrieved_for_ebook == 0 then
            update_hits_for_current_ebook = current_ebook

        elseif not update_hits_for_current_ebook and ebook_or_series == current_series and hits_retrieved_for_ebook == 0 then
            update_hits_for_current_ebook = current_series
        end

        if update_hits_for_current_ebook and name then
            hits = self:updateHitsCount({
                id = id,
                name = name,
                aliases = aliases,
            }, conn)
        end

        table.insert(self.ebooks[ebook_or_series], {
            id = id,
            name = name,
            short_names = result["short_names"][i] or "",
            description = result["description"][i] or "",
            xray_type = tonumber(result["xray_type"][i]) or 1,
            aliases = aliases,
            linkwords = result["linkwords"][i] or "",
            hits = hits,
        })
    end
    if update_hits_for_current_ebook then
        self:markCurrentEbookOrSeriesHitsUpdated(update_hits_for_current_ebook, conn)
    end
    conn = Databases:closeConnections(conn)

    has_series_index = self.ebooks[current_series]
    self.xray_items = has_series_index and self.ebooks[current_series] or self.ebooks[current_ebook] or {}
    self:prepareData()
    return has_series_index
end

function XrayHelpers:removePartialHitsIfFullHitFound(hits, explanations, part_hits)
    local pruned_collection = {}
    local pruned_explanations = {}
    local is_pruned = false
    local skip_items = {}
    for full_hit_fam_name, hit_count in pairs(self.families_matched_by_multiple_parts) do
        -- loop through full name and surname matches:
        if hit_count == 0 then
            for nr, xray_item in ipairs(hits) do
                local skip_item = false
                local xray_name = xray_item.name
                if part_hits[xray_name] and part_hits[xray_name] > 0 then
                    local item_fam_name = xray_name:gsub("^.+ ", "")
                    skip_item = item_fam_name == full_hit_fam_name
                    if skip_item then
                        skip_items[xray_name] = 1
                        is_pruned = true
                    end
                end
                if not skip_item then
                    table.insert(pruned_collection, xray_item)
                    table.insert(pruned_explanations, explanations[nr])
                end
            end
        end
    end
    if is_pruned then
        return pruned_collection, pruned_explanations, skip_items
    end

    return hits, explanations, {}
end

function XrayHelpers:storeAddedXrayItem(current_ebook_or_series, new_xray_item)
    local conn = Databases:getDBconnForStatistics("XrayHelpers#addXrayItem")
    local stmt = conn:prepare(self.queries.create)
    local x = new_xray_item
    stmt:reset():bind(current_ebook_or_series, x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, x.hits):step()
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)
end

function XrayHelpers:storeDeletedXrayItem(current_ebook_or_series, id)
    local conn = Databases:getDBconnForStatistics("XrayHelpers#deleteXrayItem")
    local sql_stmt = "DELETE FROM xray_items WHERE ebook = ? AND id = ?"
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(current_ebook_or_series, id):step()
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)
end

function XrayHelpers:storeImportedXrayItems(current_ebook_or_series)

    self:prepareData()
    local conn = Databases:getDBconnForStatistics("XrayHelpers#saveXrayItems")
    local sql_stmt = "DELETE FROM xray_items WHERE ebook = ?"
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(current_ebook_or_series):step()
    stmt = conn:prepare(self.queries.create)
    local unduplicated = {}
    local previous_item_name
    local initial_items_count = #self.xray_items
    for _, item in ipairs(self.xray_items) do
        if item.name ~= previous_item_name then
            stmt:reset():bind(current_ebook_or_series, item.name, item.short_names, item.description, item.xray_type, item.aliases, item.linkwords, item.hits):step()
            table.insert(unduplicated, item)
            previous_item_name = item.name
        end
    end
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)
    if #unduplicated ~= initial_items_count then
        self.xray_items = unduplicated
        self:prepareData()
        self.ebooks[current_ebook_or_series] = self.xray_items
    end
end

function XrayHelpers:storeUpdatedXrayItemType(current_ebook_or_series, id, xray_type)
    local conn = Databases:getDBconnForStatistics("XrayHelpers#updateXrayItemType")
    local sql_stmt = "UPDATE xray_items SET xray_type = ? WHERE ebook = ? AND id = ?"
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(xray_type, current_ebook_or_series, id):step()
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)
end

function XrayHelpers:storeUpdatedXrayItem(current_ebook_or_series, id, updated_xray_item)
    local conn = Databases:getDBconnForStatistics("XrayHelpers#updateXrayItem")
    local stmt = conn:prepare(self.queries.update)
    local x = updated_xray_item
    stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, x.hits, current_ebook_or_series, id):step()
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)
end

function XrayHelpers:generateParagraphInformation(xray_rects, nr)
    local paragraph_text = self.paragraph_texts[nr]
    local paragraph_hits_info = ""
    local paragraph_headings = {}
    local xray_items = xray_rects.hits[nr]
    local paragraph_hits_count
    local xray_explanations = xray_rects.explanations[nr]
    -- #((skip partial name matches if familiy member with full name also found))
    -- xray items with partial family name matches that must be removed, because a family member with full name has been found:
    local skip_xray_items = xray_rects.skip_xray_items[nr]
    local indent = self.xray_info_indent
    local extra_indent = self.xray_info_extra_indent

    -- hotfix for doubled names, as retrieved by ((XrayHelpers#getXrayInfoMatches)):
    local injected_names = {}
    local injected_nr = 0
    for i = 1, #xray_items do
        local name = xray_items[i].name
        if not injected_names[name] and (not skip_xray_items or not skip_xray_items[name]) then
            injected_names[name] = name
            injected_nr = injected_nr + 1
            local prefix = injected_nr == 1 and "" or "\n"
            if self.xray_info_use_upper_case_names then
                name = Strings:upper(name)
            end
            local description = Strings:splitLinesToMaxLength(xray_items[i].description, self.max_line_length, indent)
            local aliases, linkwords, explanation = "", "", ""
            if has_text(xray_items[i].aliases) then
                local noun = xray_items[i].aliases:match(" ") and "Aliassen: " or "Alias: "
                aliases = Strings:splitLinesToMaxLength(xray_items[i].aliases, self.max_line_length, self.xray_info_indent .. extra_indent, noun) .. "\n"
            end
            if has_text(xray_items[i].linkwords) then
                local noun = xray_items[i].linkwords:match(" ") and "Link-termen: " or "Link-term: "
                linkwords = Strings:splitLinesToMaxLength(xray_items[i].linkwords, self.max_line_length, indent .. extra_indent, noun) .. "\n"
            end
            if self.show_xray_explanations and has_text(xray_explanations[i]) then
                explanation = Strings:splitLinesToMaxLength(xray_explanations[i], self.max_line_length, indent, "Explanation: ") .. "\n"
            end

            local icon = self:getIcon(xray_items[i])
            local xray_hit_reliability_icon = self:getReliabilityIcon(explanation)

            -- here the info gets combined:
            -- #((xray items dialog add hit reliability icons))
            local hit_block = prefix .. icon .. name .. " " .. xray_hit_reliability_icon .. " " .. "\n" .. explanation .. description .. "\n" .. aliases .. linkwords
            paragraph_hits_info = paragraph_hits_info .. hit_block

            -- #((headings for use in TextViewer))
            -- needles will be used in ((TextViewer#blockDown)) and  ((TextViewer#blockUp)):
            table.insert(paragraph_headings, {
                name = name,
                needle = xray_hit_reliability_icon .. icon .. name,
                length = hit_block:len(),
                xray_item = xray_items[i],
            })

            local more_button_added = self:addButton(self.xray_info_extra_button_rows, xray_items[i], {
                nr = injected_nr,
                max_total_buttons = self.xray_info_max_total_buttons,
                max_buttons_per_row = self.max_buttons_per_row,
                source_items = xray_items,
                callback = function()
                    KOR.xrayitems:onEditXrayItem(xray_items[i])
                end,
                extra_item_callback = function(citem)
                    KOR.xrayitems:onEditXrayItem(citem)
                end,
            })
            if more_button_added then
                break
            end
        end
    end -- end for xray_items
    paragraph_hits_count = injected_nr

    -- #((xray paragraph info callback))
    -- callback defined in ((set xray info for paragraphs)) and calls ((XrayHelpers#showXrayItemsInfo)):
    xray_rects.callback(paragraph_hits_info, paragraph_headings, paragraph_hits_count, self.xray_info_extra_button_rows, paragraph_text)
end

function XrayHelpers:getInfo(item, ucfirst)
    local info = ucfirst and Strings:ucfirst(item.description) .. "\n" or "\n" .. item.description .. "\n"
    local has_aliases, has_linkwords = has_text(item.aliases), has_text(item.linkwords)
    if has_aliases then
        local indent = "  "
        local suffix = ""
        if has_linkwords then
            suffix = item.aliases:match(" ") and " " or "     "
        end
        if item.linkwords:match(" ") then
            suffix = suffix .. "   "
        end
        local noun = item.aliases:match(" ") and "aliases: " or "alias: "
        local aliases = noun .. suffix .. item.aliases
        aliases = Strings:splitLinesToMaxLength(aliases, self.max_line_length, indent)
        info = info .. "\n\n" .. aliases
    end
    if has_linkwords then
        local separator = has_aliases and "\n" or "\n\n"
        local indent = "  "
        local noun = item.linkwords:match(" ") and "link-terms: " or "link-term: "
        local linkwords = noun .. item.linkwords
        linkwords = Strings:splitLinesToMaxLength(linkwords, self.max_line_length, indent)
        info = info .. separator .. linkwords
    end
    return info
end

function XrayHelpers:getIcon(item, bare)
    item.xray_type = tonumber(item.xray_type)
    if not item.xray_type or item.xray_type < 1 or item.xray_type > 4 then
        item.xray_type = 1
    end
    if bare then
        return self.xray_icons_bare[item.xray_type]
    end
    return self.xray_icons[item.xray_type]
end

function XrayHelpers:hasTextFilterMatch(item, keywords, uc_first_name)
    if #keywords == 0 then
        return true
    end
    -- uc_first_name will be set when matching for ucfirst variants of lowercase Xray items; ((XrayItems#filterByText)) > ((xray items list matches for text variant)) > current method:
    local name = uc_first_name or item.name
    local haystack = name .. " " .. item.description
    if has_text(item.aliases) then
        haystack = haystack .. " " .. item.aliases
    end
    if has_text(item.linkwords) then
        haystack = haystack .. " " .. item.linkwords
    end
    return Strings:hasUnmodifiedMatch(keywords, haystack, false)
end

function XrayHelpers:hasExactMatch(haystack, needle)
    if haystack == needle then
        return true
    end
    local found = needle:len() >= self.min_match_word_length
            and (haystack:match(needle) and not haystack:match(needle .. "%l+"))
    if found then
        return true
    end

    needle = Strings:singular(needle, 1)
    return needle:len() >= self.min_match_word_length
            and (haystack:match(needle) and not haystack:match(needle .. "%l+"))
end

function XrayHelpers:matchAliasesToParagraph(paragraph, hits, explanations, xray_item)
    local aliases = xray_item.aliases
    local xray_name = xray_item.name
    local alias_table = self:splitByCommaOrSpace(aliases)
    for _, alias in ipairs(alias_table) do
        if paragraph:match(alias) then
            self:registerParagraphHit(hits, explanations, xray_item, "alias found for \"" .. xray_name .. "\"" .. self.separator .. alias)
            return true
        end
    end
    return false
end

function XrayHelpers:splitByCommaOrSpace(subject, add_singulars)
    local separated_by_commas = subject:match(",")
    local keywords
    local plural_keywords = {}
    -- in case of comma separated linkwords we want exact, non partly matches of these linkwords:
    keywords = separated_by_commas and Strings:split(subject, ", *") or Strings:split(subject, "  *")
    for nr, keyword in ipairs(keywords) do
        keywords[nr] = keyword:gsub("%-", "%%-")
        if add_singulars and keyword:match("s$") then
            local plural = keyword:gsub("s$", "")
            table.insert(plural_keywords, plural)
        end
    end
    if #plural_keywords > 0 then
        return Tables:merge(keywords, plural_keywords)
    end
    return keywords
end

function XrayHelpers:matchNameToParagraph(paragraph, xray_needle, hits, part_hits, explanations, xray_item)
    local xray_name = xray_item.name
    local has_family_name = xray_needle:match(" ")
    local is_single_word = not has_family_name
    local is_lower_case = not xray_name:match("[A-Z]")
    local name_parts = Strings:split(xray_needle, " ")
    local family_name
    local multiple_parts_count = 0
    if has_family_name and not is_lower_case then
        family_name = name_parts[#name_parts]
    end
    local matcher = xray_needle:gsub("%-", "%%-")
    if self:isFullWordMatch(paragraph, matcher)
    then
        self:registerParagraphHit(hits, explanations, xray_item, "full name found" .. self.separator .. xray_needle)
        -- #((log family name))
        if has_family_name and not is_lower_case then
            self.families_matched_by_multiple_parts[family_name] = 0
            part_hits[xray_name] = 0
            return true, 2
        end
        return true, 1
    end

    -- for lowercase words and words without spaces we don't match by word parts:
    if is_lower_case or is_single_word then
        return false, 0
    end

    local mparts = matcher and Strings:split(matcher, " ") or Strings:split(xray_needle, " ")
    local hit_found = false
    local left_hit_found = false
    local right_hit_found = false
    local matching_parts = ""
    for nr, part in ipairs(name_parts) do
        if part:len() >= self.min_match_word_length and self:isFullWordMatch(paragraph, mparts[nr]) then
            hit_found = true
            if nr == 1 then
                left_hit_found = true
            elseif nr == #name_parts then
                right_hit_found = true
            end
            multiple_parts_count = multiple_parts_count + 1
            matching_parts = matching_parts .. part .. ", "
        end
    end
    if multiple_parts_count > 0 then
        part_hits[xray_name] = multiple_parts_count
    end

    -- when a full name for a specific family already has been found above, we don't want hits for only their surname; see ((log family name)):
    if self.families_matched_by_multiple_parts[family_name] and multiple_parts_count == 1 then
        return false, 0
    end

    if has_family_name and multiple_parts_count > 1 then
        self.families_matched_by_multiple_parts[family_name] = multiple_parts_count
    end

    if hit_found then
        local hit_type_message = "part/parts of name"
        matching_parts = matching_parts:gsub(", $", "")
        if left_hit_found then
            hit_type_message = "first name"
        elseif right_hit_found then
            hit_type_message = "last name"
        end
        self:registerParagraphHit(hits, explanations, xray_item, hit_type_message .. " found" .. self.separator .. matching_parts)
    end
    return hit_found, multiple_parts_count
end

function XrayHelpers:getFullPageText()
    local page_text = ""
    if self.info_mode == "page" then
        for i = 1, #self.paragraphs do
            page_text = page_text .. self.paragraphs[i].text .. "\n"
        end
        page_text = page_text:gsub("\n$", "", 1)
    end
    return page_text
end

-- these reliability icons will be injected in the dialog with page or paragraphs information in ((XrayHelpers#generateParagraphInformation)) > ((xray items dialog add hit reliability icons)):
function XrayHelpers:getReliabilityIcon(explanation)
    if explanation:match("full name") then
        return Icons.xray_full_bare
    elseif explanation:match("part/parts") then
        return Icons.xray_partial_bare
    elseif explanation:match("alias found") then
        return Icons.xray_alias_bare
    elseif explanation:match("last name") then
        return Icons.xray_half_right_bare
    end
    -- explanation matches "first name":
    return Icons.xray_half_left_bare
end

function XrayHelpers:isFullWordMatch(paragraph, needle)
    local plural_noun
    if not needle:match("s$") then
        plural_noun = needle .. "s"
    end
    return
    Strings:wholeWordMatch(paragraph, needle)
    or
    (plural_noun and Strings:wholeWordMatch(paragraph, plural_noun))
end

function XrayHelpers:matchItemToNeedleItem(extra_items, item, needle_item, include_name_match, aliases, tapped_word)
    local tapped_word_matcher = tapped_word
    if tapped_word then
        tapped_word_matcher = tapped_word:gsub("%-", "%%-")
    end

    local linked_items, linked_names_index = self:getLinkedItems(needle_item)
    if #linked_items > 0 then
        for _, litem in ipairs(linked_items) do
            table.insert(extra_items, litem)
        end
    end
    if linked_names_index[item.name] then
        return
    end

    -- include extact fullname match, if allowed:
    if include_name_match and (not tapped_word or tapped_word == item.name) and (item.index == needle_item.index or item.name == needle_item.name or item.name:match("^" .. needle_item.name .. "s$")) then
        item.hit_reliability_cion = Icons.xray_full_bare
        table.insert(extra_items, item)

    elseif include_name_match and tapped_word and item.name:match("^" .. tapped_word_matcher) then
        item.hit_reliability_cion = Icons.xray_half_left_bare
        table.insert(extra_items, item)

    elseif include_name_match and tapped_word and item.name:match(tapped_word_matcher .. "$") then
        item.hit_reliability_cion = Icons.xray_half_right_bare
        table.insert(extra_items, item)

    elseif include_name_match and tapped_word and item.name:match(tapped_word_matcher) then
        item.hit_reliability_cion = Icons.xray_partial_bare
        table.insert(extra_items, item)

        -- include items which in their aliases match to the aliases of the needle item:
    elseif #aliases > 0 then
        for _, alias in ipairs(aliases) do
            alias = alias:gsub("%-", "%%-")
            if self:hasExactMatch(item.aliases, alias) then
                item.hit_reliability_cion = Icons.xray_alias_bare
                table.insert(extra_items, item)
                break
            end
        end
    end
end

function XrayHelpers:registerParagraphHit(hits, explanations, xray_item, message)
    table.insert(hits, xray_item)
    table.insert(explanations, message)
end

function XrayHelpers:setEbookOrSeriesIndex(current_source, new_source)
    local conn = Databases:getDBconnForStatistics("XrayHelpers#setEbookOrSeriesIndex")
    local sql_stmt = "UPDATE xray_items SET ebook = ? WHERE ebook = ?"
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(new_source, current_source):step()
    stmt = Databases:closeStmts(stmt)
    conn = Databases:closeConnections(conn)

    self.ebooks[new_source] = Tables:shallowCopy(self.ebooks[current_source])
    self.ebooks[current_source] = nil
end

-- called from ((XrayHelpers#prepareData)):
function XrayHelpers:sortAndIndexItems()
    self.xray_items = Tables:sortByPropAscendingAndSetTopItems(self.xray_items, "name", function(xray_item)
        return xray_item.xray_type == 2 or xray_item.xray_type == 4
    end)
    for nr in ipairs(self.xray_items) do
        self.xray_items[nr].index = nr
    end
end

function XrayHelpers:populateTypeTables()
    self.xray_items_terms = {}
    self.xray_items_persons = {}
    for _, xray_item in ipairs(self.xray_items) do
        if xray_item.xray_type == 1 or xray_item.xray_type == 2 then
            table.insert(self.xray_items_persons, xray_item)
        else
            table.insert(self.xray_items_terms, xray_item)
        end
    end
end

function XrayHelpers:prepareData()
    self:sortAndIndexItems()
    self:populateTypeTables()
end

--- @param xray_item_needle table Also has a aliases prop, for matching in KOR.xrayitems:getAllTextCount
function XrayHelpers:updateHitsCount(xray_item_needle, conn)
    local xray_item_id = xray_item_needle.id

    local hits = KOR.xrayitems:getAllTextCount(xray_item_needle)
    local sql_stmt = "UPDATE xray_items SET hits = ? WHERE id = ?"
    local stmt
    if hits > 0 then
        stmt = conn:prepare(sql_stmt)
        stmt:reset():bind(hits, xray_item_id):step()
        stmt = Databases:closeStmts(stmt)
    end
    return hits
end

function XrayHelpers:markCurrentEbookOrSeriesHitsUpdated(ebook_or_series, conn)
    if ebook_or_series then
        local sql_stmt = "UPDATE xray_items SET ebook_hits_retrieved = 1 WHERE ebook = ?"
        local stmt = conn:prepare(sql_stmt)
        ebook_or_series = Databases:escape(ebook_or_series)
        stmt:reset():bind(ebook_or_series):step()
        stmt = Databases:closeStmts(stmt)
    end
end

return XrayHelpers
