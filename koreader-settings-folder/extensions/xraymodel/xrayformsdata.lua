
--* see ((Dynamic Xray: module info)) for more info

local require = require

local Font = require("extensions/modules/font")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Size = require("extensions/modules/size")
local T = require("ffi/util").template

local DX = DX
local has_no_text = has_no_text
local has_text = has_text
local table_insert = table.insert
local tonumber = tonumber
local tostring = tostring
local type = type

local count
--- @type XrayModel parent
local parent
--- @type XrayTappedWords tapped_words
local tapped_words
--- @type XrayViewsData views_data
local views_data

--- @class XrayFormsData
local XrayFormsData = WidgetContainer:new{
    active_form_mode = nil,
    description_field_face = Font:getFace("x_smallinfofont", 19),
    edit_item_index = nil,
    form_item_id = nil,
    item_before_edit = nil,
    --* used to determine whether an item should be displayed bold in the list or not; and also used in ((XrayViewsData#storeItemHits)) to store the (updated) book_hits for an item in the database:
    last_modified_item_id = nil,
    other_fields_face = Font:getFace("x_smallinfofont", 19),
}

--- @param xray_model XrayModel
function XrayFormsData:initDataHandlers(xray_model)
    parent = xray_model
    tapped_words = DX.tw
    views_data = DX.vd
end

function XrayFormsData:initNewItemFormProps(name_from_selected_text, active_form_tab, item)
    local prefilled_field = "name"
    self.active_form_mode = "add"
    local is_text_from_selection = has_text(name_from_selected_text)
    --* for consumption in ((XrayDialogs#closeForm)) and to force return to ebook text there, if truthy:
    KOR.registry:set("xray_editor_activated_from_text_selection", is_text_from_selection)
    if is_text_from_selection and KOR.strings:substrCount(name_from_selected_text, " ") > 3 then
        prefilled_field = "description"
    end
    --* active_form_tab can be higher than 1 when the tab callback has been called and set this argument to a higher number:
    if not active_form_tab then
        active_form_tab = 1
    end
    DX.d:setProp("active_form_tab", active_form_tab)
    local xray_type = item and item.xray_type
    if has_text(name_from_selected_text) and not name_from_selected_text:match("[A-Z]") then
        xray_type = 3
        if item then
            item.xray_type = 3
        end
    end
    local xray_type_stored = false
    --* this concerns the active tab of the Xray items list:
    if parent.active_list_tab == 3 or tapped_words.active_tapped_word_tab == 3 then
        xray_type = 3
        if item then
            item.xray_type = 3
        end
    --* item will only be set after we navigated from tab 1 to tab 2:
    elseif not item and has_text(name_from_selected_text) then
        --* if onAddItem invoked with text selection and that selection doesn't contain uppercase characters, assume it's an entity, not a person:
        xray_type = is_text_from_selection and not name_from_selected_text:match("[A-Z]") and 3 or 1
        --* for consumption in the next code block:
        KOR.registry:set("xray_type", xray_type)
        xray_type_stored = true
    end

    --* when we navigate to the second tab, after xray_type has been set in the first tab, based on the text selection the user made:
    if item and not xray_type_stored then
        local xray_type_from_previous_tab = KOR.registry:getOnce("xray_type")
        if xray_type_from_previous_tab then
            item.xray_type = xray_type_from_previous_tab
        end
    end
    local item_copy = self:getItemCopy(item, xray_type)

    --* show how many times the selected text occurs in the book:
    local search_text = name_from_selected_text or item_copy.name
    local no_hits_title = _("Add xray item")
    local use_search_text = has_text(search_text)
    local title = use_search_text and KOR.icons.xray_add_item_bare or no_hits_title
    if use_search_text then
        --! this statement is crucial to get an indicatior of the numerical presence of this item in de current book:
        item_copy.name = prefilled_field == "name" and search_text or ""
        --* book_hits only retrieved here to give the user an indication how important this item is in the text of the book:
        if prefilled_field ~= "description" then
            views_data:setItemHits(item_copy, { for_display_mode = "book", force_update = true })
        end
        self:resetFormItemId()
        if item_copy.book_hits == 0 then
            title = no_hits_title
        else
            title = KOR.icons.xray_add_item_bare .. " " .. item_copy.book_hits .. _(" hits in book")
        end
    end

    return title, item_copy, prefilled_field
end

--- @private
function XrayFormsData:getItemCopy(item, xray_type)
    return item and KOR.tables:shallowCopy(item) or {
        description = "",
        name = "",
        short_names = "",
        linkwords = "",
        aliases = "",
        tags = "",
        xray_type = xray_type or 1,
        mentioned_in = nil,
        book_hits = 0,
        chapter_hits = '',
        series_hits = 0,
        series = parent.current_series,
    }
end

--* called from ((XrayDialogs#showNewItemForm)):
function XrayFormsData:resetItemProps(item_copy)
    --* for a new item reset everything but hits data, xray_type, series, name and description (which might be computed based on the text selection the user made):
    local reset_props = { "short_names", "linkwords", "aliases", "tags", "mentioned_in" }
    count = #reset_props
    for i = 1, count do
        item_copy[reset_props[i]] = nil
    end
end

function XrayFormsData:initEditFormProps(item, reload_manager, active_form_tab)
    self.active_form_mode = "edit"

    DX.d:setProp("edit_args", {
        reload_manager = reload_manager,
    })

    --* this can be the case on longpressing an toc-item in TextViewer; see ((TextViewer toc button)):
    if not item.index or (not item.xray_type and not item.aliases and not item.tags) then
        item = views_data:upgradeNeedleItem(item, {
            include_name_matches = true,
            is_exists_check = true,
        })
        DX.d:setProp("edit_item", KOR.tables:shallowCopy(item))
    end

    --! because of tabs in edit form, we need to re-attach the "hidden" item id after switching between tabs:
    if self.form_item_id then
        item.id = self.form_item_id
    end

    --* active_form_tab can be higher than 1 when the tab callback has been called and set the argument to a higher number:
    if not active_form_tab then
        active_form_tab = 1
    end
    DX.d:setProp("active_form_tab", active_form_tab)
    if not item.index then
        views_data.prepareData()
        item = views_data:upgradeNeedleItem(item, {
            include_name_matches = true,
        })
    end
    local item_copy = KOR.tables:shallowCopy(item)
    self.edit_item_index = item.index

    self.item_before_edit = item

    return item, item_copy
end

--* compare ((XrayFormsData#saveNewItem)):
function XrayFormsData:saveUpdatedItem(field_values)
    if not self.edit_item_index then
        KOR.messages:notify(_("edit_item_index has not been set for this item..."))
        return
    end
    --* current method is called from ((XrayController#saveUpdatedItem)); book_hits count was added to the edited item there:
    local edited_props = self:
    convertFieldValuesToItemProps(field_values)

    --! re-attach the item id!:
    self:reAttachViewerItemId(edited_props)

    --! name field MUST be present:
    if has_no_text(edited_props.name) then
        KOR.messages:notify(_("xray item to be edited wasn't found..."), 4)
        return
    end

    DX.d:setProp("needle_name_for_list_page", "")
    local edited_item = {
        --! this prop is mandatory for saving updated item:
        id = edited_props.id,
        name = edited_props.name,
        description = edited_props.description,
        short_names = edited_props.short_names,
        linkwords = edited_props.linkwords,
        aliases = edited_props.aliases,
        tags = edited_props.tags,
        index = self.edit_item_index,
        xray_type = tonumber(edited_props.xray_type),
        mentioned_in = views_data.items[self.edit_item_index].mentioned_in,
        series = parent.current_series,
    }
    --* so as to force call to ((XrayViewsData#generateListItemText)) below to show the possible changed number of book_hits:
    --* this call adds props "book_hits" and "chapter_hits" to the item:
    views_data:setItemHits(edited_item, { store_book_hits = true, mode = "edit" })
    local hits_in_book = edited_item.book_hits
    local hits_in_book_for_store = hits_in_book
    if hits_in_book == 0 then
        hits_in_book_for_store = nil
    end
    edited_item.book_hits = hits_in_book_for_store
    self:storeItemUpdates("edit", edited_item)
    parent:updateTags(edited_item)

    --* no filter was set, so return simply edited_item:
    if views_data.filter_state == "unfiltered" then
        return edited_item
    end

    --* if a filter was set, return an updated filtered item:
    return self:getFilteredItem(edited_props, edited_item.series_hits, hits_in_book, edited_item.chapter_hits)
        or
        edited_item
end

function XrayFormsData:convertFieldValuesToItemProps(values)
    --! xray_type field is last field and has therefore index 6 (2 fields in tab one + 4 fields in tab two):
    --* see also ((XrayDialogs#switchFocusForXrayType)):
    local xray_type = tonumber(values[DX.d.xray_type_field_nr + 2])
    if not xray_type or xray_type == 0 then
        xray_type = 1
    elseif xray_type > 4 then
        xray_type = 4
    end
    return {
        description = has_text(values[1]) or "",
        name = values[2],
        --* compare usage of sortKeywords here to ((XrayModel#splitByCommaOrSpace)) for getting needles for searching linked items:
        aliases = has_text(values[3]) and KOR.strings:sortKeywords(values[3]) or "",
        linkwords = has_text(values[4]) and KOR.strings:sortKeywords(values[4]) or "",
        short_names = has_text(values[5]) and KOR.strings:sortKeywords(values[5]) or "",
        --* this is field no 6:
        xray_type = xray_type,
        tags = has_text(values[7]) and KOR.strings:sortKeywords(values[7]) or "",
    }
end

--* this id was "remembered" in ((XrayFormsData#setFormItemId)):
function XrayFormsData:reAttachViewerItemId(item)
    if self.form_item_id then
        --! never let the id of an item get set to nil, because we need it when switching between form tabs in the edit form:
        item.id = self.form_item_id
        self:resetFormItemId()
        return
    end

    --* fallback; this prop was set in ((XrayFormsData#initEditFormProps)):
    local edit_item = KOR.registry:get("edit_item")
    if edit_item then
        item.id = edit_item.id

    --? for some reason we need the second fallback in case of editing items from List context menu, because otherwise id would not be remembered:
    --* this prop was set in ((XrayButtons#forListContext)):
    else
        item.id = KOR.registry:getOnce("edit_item_id")
    end
end

--* this id is set upon viewing an item from the list or after tapping an Xray item button in ((XrayDialogs#showItemViewer)), or upon viewing an item found upon tapping a word in the reader in ((XrayDialogs#viewTappedWordItem)):
function XrayFormsData:setFormItemId(item_id)
    --* "hidden" id, to be re-attached to the updated item in ((XrayFormsData#reAttachViewerItemId)):
    self.form_item_id = item_id
end

function XrayFormsData:resetFormItemId()
    self.form_item_id = nil
end

--- @private
function XrayFormsData:getFilteredItem(new_props, entire_series_hits, hits_in_book, hits_in_chapter)
    count = #views_data.item_table[1]
    local item
    for nr = 1, count do
        item = views_data.item_table[1][nr]
        if item.index == self.edit_item_index then
            return {
                id = new_props.id,
                --! crucial to be able to edit the item once again in filtered mode:
                index = item.index,
                name = new_props.name,
                --* entire_series_hits here: so as to force ((XrayViewsData#generateListItemText)) to show the possible changed number of book_hits:
                text = views_data:generateListItemText(new_props),
                description = new_props.description,
                short_names = new_props.short_names,
                aliases = new_props.aliases,
                tags = new_props.tags,
                linkwords = new_props.linkwords,
                xray_type = new_props.xray_type,
                book_hits = hits_in_book,
                chapter_hits = hits_in_chapter,
                series_hits = entire_series_hits,
                mentioned_in = item.mentioned_in,
                series = parent.current_series,
            }
        end
    end
end

function XrayFormsData:getTypeLabel(item)
    return has_text(item.name) and KOR.strings:limitLength(item.name, DX.s.PN_info_panel_max_line_length) .. ": " or ""
end

function XrayFormsData:getAliasesText(item)
    if has_no_text(item.aliases) then
        return
    end
    local noun = item.aliases:match(" ") and _("aliases") or _("alias")
    noun = noun .. KOR.icons.arrow_bare .. " "
    return KOR.strings:limitLength(noun .. " " .. item.aliases, DX.s.PN_info_panel_max_line_length)
end

function XrayFormsData:getLinkwordsText(item)
    if has_no_text(item.linkwords) then
        return
    end
    local noun = item.linkwords:match(" ") and _("link-terms") or _("link-term")
    noun = noun .. KOR.icons.arrow_bare .. " "
    return KOR.strings:limitLength(noun .. " " .. item.linkwords, DX.s.PN_info_panel_max_line_length)
end

function XrayFormsData:getFormTabCallback(mode, active_form_tab, item_copy)
    return function(form_tab)
        if form_tab == active_form_tab then
            return
        end
        --- @type MultiInputDialog source
        local source = mode == "add" and DX.d.add_item_input or DX.d.edit_item_input
        item_copy = self:convertFieldValuesToItemProps(source:getAllTabsFieldsValues())
        DX.d:closeForm(mode)
        if mode == "edit" then
            DX.d.edit_item_input = nil
            --! this one is crucial to switch between tabs and preserve changed values!:
            item_copy.index = self.edit_item_index
            DX.c:onShowEditItemForm(item_copy, false, form_tab)
        else
            DX.d.add_item_input = nil
            DX.c:onShowNewItemForm(nil, form_tab, item_copy)
        end
    end
end

--- @private
function XrayFormsData:getNeedleName(item)
    --* when using plus icon in top left of ReaderSearch results dialog:
    local needle_name = type(item) == "string" and item or item.name

    --* if we tapped the plus button and want to add a new item from scratch:
    if not needle_name then
        return ""
    end

    --* optionally change a suggested name like Joe Glass to Glass, Joe:
    return parent:switchFirstAndSurName(needle_name)
end

--* called from add dialog and ReaderDictionary and other plugins:
--* compare ((XrayFormsData#saveUpdatedItem)):
-- #((XrayFormsData#saveNewItem))
function XrayFormsData.saveNewItem(new_item)

    local self = DX.fd

    local needle_name = self:getNeedleName(new_item)

    --* might be set to a value by ((XrayTappedWords#itemExists)), so here we reset it:
    --* method in current extension, but called like this, to silence luacheck:
    self.filter_string = ""

    if DX.c:guardIsExistingItem(needle_name) then
        return
    end
    if type(new_item) == "string" or new_item.text then
        --* name_from_selected_text can be nil when we want to type and add a completely new item:
        DX.c:onShowNewItemForm(needle_name)
        return
    end

    new_item.name = needle_name

    --* this call also adds an id prop to item, needed for ((XrayViewsData#updateAndSortAllItemTables)):
    --* always reset filters when adding a new item, to prevent problems; disabled, because already run upon showing add new item form; see e.g. ((XrayButtons#forItemViewer)) or ((XrayCallbacks#execAddCallback)):
    --DX.c:resetFilteredItems()
    DX.ds.storeNewItem(new_item)

    --* set and store props book_hits etc. for this new item:
    views_data:setItemHits(new_item, { store_book_hits = true, mode = "add" })

    --! don't call views_data:updateAndSortAllItemTables(item, "add") here, because then all previous items in list gone from view...
    --* we force refresh of data here, because it could be that Items List hasn't been shown yet:
    views_data:registerNewItem(new_item)
    parent:updateTags(new_item, "is_new_item")
end

--- @private
function XrayFormsData:toggleIsImportantItem(toggle_item)
    local xray_items = {}
    local position = 1
    local item
    count = #views_data.items
    for nr = 1, count do
        item = views_data.items[nr]
        if item.id == toggle_item.id then
            if toggle_item.xray_type == 2 or toggle_item.xray_type == 4 then
                item.xray_type = item.xray_type - 1
            else
                item.xray_type = item.xray_type + 1
            end
            toggle_item.xray_type = item.xray_type
            position = nr
        end
        table_insert(xray_items, item)
    end
    self:storeItemUpdates("toggle_type", toggle_item)

    return position, toggle_item
end

--- @private
function XrayFormsData:toggleIsPersonOrTerm(toggle_item)
    local xray_items = {}
    local position = 1
    local item
    count = #views_data.items
    for nr = 1, count do
        item = views_data.items[nr]
        if item.id == toggle_item.id then
            if DX.m:isPerson(toggle_item) then
                item.xray_type = item.xray_type + 2
            else
                item.xray_type = item.xray_type - 2
            end
            toggle_item.xray_type = item.xray_type
            position = nr
        end
        table_insert(xray_items, item)
    end
    self:storeItemUpdates("toggle_type", toggle_item)

    return position, toggle_item
end

--- @private
function XrayFormsData:isNotSameFieldValue(a, b)
    return a ~= b and not (has_no_text(a) and has_no_text(b))
end

function XrayFormsData:needsFullUpdate(item)
    --* item_before_edit was set in ((XrayFormsData#initEditFormProps)):

    item = KOR.tables:shallowCopy(item)
    return
        self:isNotSameFieldValue(item.name, self.item_before_edit.name)
        or self:isNotSameFieldValue(item.linkwords, self.item_before_edit.linkwords)
        or self:isNotSameFieldValue(item.aliases, self.item_before_edit.aliases)
        or self:isNotSameFieldValue(item.short_names, self.item_before_edit.short_names)
        or self:isNotSameFieldValue(item.xray_type, self.item_before_edit.xray_type)
end

--* this method called upon rename/edit, toggle importance, toggle person/term of Xray item:
--* for storing new items see ((XrayDataSaver#storeNewItem))
function XrayFormsData:storeItemUpdates(mode, item)
    if not item then
        KOR.messages:notify(_("item could not be updated..."))
        return

    elseif not item.id then
        return
    end
    self.last_modified_item_id = item.id

    --* optionally set to a value by ((XrayTappedWords#itemExists)), so here we reset it:
    --! disabled, we want to retain a filter that has been set:
    --self.filter_string = ""

    --* mode has this value when called from ((XrayFormsData#toggleIsPersonOrTerm)) or ((XrayFormsData#toggleIsImportantItem)):
    if mode == "toggle_type" then
        DX.ds.storeUpdatedItemType(item)

    elseif mode == "edit" then
        --* updated_value in this case is a xray item:
        DX.ds.storeUpdatedItem(item)
    end

    views_data:registerUpdatedItem(item)
end

--* compare ((XrayDialogs#showEditItemForm)):
--- @private
function XrayFormsData:getFormFields(item_copy, prefilled_field, name_from_selected_text)
    local aliases = self:getAliasesText(item_copy)
    local linkwords = self:getLinkwordsText(item_copy)
    local icon = DX.vd:getItemTypeIcon(item_copy, "bare")

    local aliases_field = {
        text = item_copy.aliases,
        input_type = "text",
        description = "Aliassen:",
        info_popup_title = _("field: Aliases"),
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _([[This field has space or comma separated terms, as aliases (of the main item name in the first tab). Can e.g. be a title or a nickname of a person.

Through aliases:
1) main names will be found in the Xray overview of items in paragraphs on the current page;
2) the main item will be shown if the user longpresses an alias in the ebook text.]]),
        tab = 2,
        cursor_at_end = true,
        input_face = self.other_fields_face,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local tags_field = {
        text = item_copy.tags,
        input_type = "text",
        description = "Tags:",
        info_popup_title = "veld: Tags",
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _("This field has space or comma separated terms. Tags will be used: 1) (coming soon) in Page Navigator, to only accentuate items which have a certain tag and to quickly jump between their occurrences; 2) in XrayExporter, to export a list of groups of items which share a tag."),
        tab = 2,
        cursor_at_end = true,
        input_face = self.other_fields_face,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local linkwords_field = {
        text = item_copy.linkwords,
        input_type = "text",
        description = _("Link-terms") .. ":",
        info_popup_title = _("field") .. ": " .. _("Link-terms"),
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _([[This field has space or comma separated (partial) names of other Xray items, to link the current item to those other items.

If such an other item is longpressed in the book, the linked items will be shown as extra buttons in the popup dialog.]]),
        tab = 2,
        cursor_at_end = true,
        input_face = self.other_fields_face,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local xray_type_field = {
        text = tostring(item_copy.xray_type) or "1",
        input_type = "number",
        --description = DX.fd:getTypeLabel(item_copy) .. "\n  " .. DX.vd.xray_type_description,
        description = "Xray-type:",
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _("Set Xray type with numbers 1 through 4. If you use the button at the right side of the field for this, you'll see an explanation of these types."),
        tab = 2,
        input_face = self.other_fields_face,
        cursor_at_end = true,
        scroll = false,
        allow_newline = false,
        force_one_line_height = true,
        disable_paste = true,
        custom_edit_button = DX.b:forItemEditorTypeSwitch(item_copy, {
            fgcolor = KOR.colors.button_light,
            bordercolor = KOR.colors.button_light,
            radius = Size.radius.button,
            bordersize = Size.border.button,
            padding = Size.padding.buttonvertical,
        }),
        margin = Size.margin.small,
    }
    local short_names_field = {
        text = item_copy.short_names,
        input_type = "text",
        description = _("Short names") .. ":",
        info_popup_title = _("field") .. ": " .. _("Short names"),
        info_popup_text = _([[Comparable with aliases, but in this case comma separated short variants of the main item name in the first tab. Handy when those shorter names are sometimes used in the book instead of the longer main name.

For Xray overviews of (paragraphs in) the current page the scripts initially will firstly search for whole instances of these short names, or otherwise for first and surnames derived from these.]]),
        tab = 2,
        input_face = self.other_fields_face,
        cursor_at_end = true,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local fields = {
        {
            text = prefilled_field == "description" and name_from_selected_text or item_copy.description or "",
            input_type = "text",
            description = linkwords and _("Description") .. T(" (%1):", linkwords) or _("Description"),
            info_popup_title = _("field") .. ": " .. _("Description"),
            info_popup_text = T(_([[If it is your intention that a Xray item should be filterable with a term in its description, you should ensure that that term in case of:

NAMES OF PERSONS %1
is mentioned with uppercase characters at start of first and surname in the description;

TERMS %2
only has lower case characters in the description.]]), KOR.icons.xray_person_important_bare .. "/" .. KOR.icons.xray_person_bare, KOR.icons.xray_term_important_bare .. "/" .. KOR.icons.xray_term_bare),
            tab = 1,
            height = "auto",
            input_face = self.description_field_face,
            scroll = true,
            scroll_by_pan = true,
            allow_newline = true,
            cursor_at_end = true,
            is_edit_button_target = true,
            margin = Size.margin.small,
        },
        {
            text = prefilled_field == "name" and name_from_selected_text or item_copy.name or "",
            input_type = "text",
            description = aliases and _("Name") .. " (" .. aliases .. "):  " .. icon or _("Name") .. ": " .. icon,
            info_popup_title = _("field") .. ": " .. _("Name"),
            info_popup_text = _([[PERSONS
Enter person names including uppercase starting characters [A-Za-z]. Because in that case the search for Xray items in the book will be done CASE SENSITIVE. By default when searching for Xray items, Dynamic Xray will search for first names in the text. If you want the plugin to search for occurrences/hits for the surname instead (because these references are more frequent in the text), use this format: "surname, first name".

TERMS
Enter with only lowercase characters [a-z], because then searches for these items will be executed CASE INSENSITIVE. So as to find hits in format "term" as well as "Term".]]),
            tab = 1,
            input_face = self.other_fields_face,
            cursor_at_end = true,
            scroll = true,
            --* force fixed height for this field in ((force one line field height)):
            force_one_line_height = true,
            allow_newline = false,
            margin = Size.margin.small,
        },
    }

    --* on Bigme we don't want two field rows (not enough space):
    if DX.s.is_mobile_device then
        table_insert(fields, aliases_field)
        table_insert(fields, linkwords_field)
        table_insert(fields, short_names_field)
        table_insert(fields, xray_type_field)
    else
        --* insert 2 two field rows:
        table_insert(fields, {
            aliases_field,
            linkwords_field,
        })
        table_insert(fields, {
            short_names_field,
            xray_type_field,
        })
    end
    table_insert(fields, tags_field)

    return fields
end

function XrayFormsData:setProp(prop, value)
    self[prop] = value
    if prop == "filter_string" then
        self.filter_state = has_text(value) and "filtered" or "unfiltered"
    end
end

return XrayFormsData
