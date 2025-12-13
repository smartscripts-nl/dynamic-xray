--[[--
This extension is part of the Dynamic Xray plugin; it handles the data required for the forms to manage the Xray items.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_no_text = has_no_text
local has_text = has_text
local table = table
local tonumber = tonumber
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
    edit_item_index = nil,
    form_item_id = nil,
    --* used to determine whether an item should be displayed bold in the list or not; and also used in ((XrayViewsData#storeItemHits)) to store the (updated) book_hits for an item in the database:
    last_modified_item_id = nil,
    queries = {
        insert_item =
            "INSERT INTO xray_items (ebook, name, short_names, description, xray_type, aliases, linkwords) VALUES (?, ?, ?, ?, ?, ?, ?);",

        update_item =
            "UPDATE xray_items SET name = ?, short_names = ?, description = ?, xray_type = ?, aliases = ?, linkwords = ?, book_hits = ?, chapter_hits = ? WHERE ebook = ? AND id = ?;",

        update_item_type =
            "UPDATE xray_items SET xray_type = ? WHERE ebook = ? AND id = ?;",

        update_item_for_entire_series =
            [[
            UPDATE xray_items
            SET
            name = ?,
            short_names = ?,
            description = ?,
            xray_type = ?,
            aliases = ?,
            linkwords = ?
            WHERE name = (SELECT xi.name
              FROM xray_items xi
              WHERE xi.id = ?)
            AND ebook IN (
              SELECT ab.filename
              FROM bookinfo ab
              WHERE ab.series = (
                  SELECT ab2.series
                  FROM bookinfo ab2
                  JOIN xray_items xi2 ON xi2.ebook = ab2.filename
                  WHERE xi2.id = ?
              )
          );]],
    },
}

--- @param xray_model XrayModel
function XrayFormsData:initDataHandlers(xray_model)
    parent = xray_model
    tapped_words = DX.tw
    views_data = DX.vd
end

function XrayFormsData:initNewItemFormProps(name_from_selected_text, active_form_tab, item)
    local target_field = "name"
    self.active_form_mode = "add"
    local is_text_from_selection = has_text(name_from_selected_text)
    if is_text_from_selection and KOR.strings:substrCount(name_from_selected_text, " ") > 3 then
        target_field = "description"
    end
    --* active_form_tab can be higher than 1 when the tab callback has been called and set this argument to a higher number:
    if not active_form_tab then
        active_form_tab = 1
    end
    DX.d:setProp("active_form_tab", active_form_tab)
    local xray_type = item and item.xray_type
    --* this concerns the active tab of the Xray items list:
    if parent.active_list_tab == 3 or tapped_words.active_tapped_word_tab == 3 then
        xray_type = 3
    elseif not xray_type then
        --* if onAddItem invoked with text selection and that selection doesn't contain uppercase characters, assume it's an entity, not a person:
        xray_type = is_text_from_selection and not name_from_selected_text:match("[A-Z]") and 3 or 1
    end
    local item_copy = item and KOR.tables:shallowCopy(item) or {
        description = "",
        name = "",
        short_names = "",
        linkwords = "",
        aliases = "",
        xray_type = xray_type,
        mentioned_in = nil,
        book_hits = 0,
        chapter_hits = '',
        series_hits = 0,
        series = parent.current_series,
    }

    --* show how many times the selected text occurs in the book:
    local search_text = name_from_selected_text or item_copy.name
    local no_hits_title = _("Add xray item")
    local use_search_text = has_text(search_text)
    local title = use_search_text and KOR.icons.xray_add_item_bare or no_hits_title
    if use_search_text then
        --! this statement is crucial to get an indicatior of the numerical presence of this item in de current book:
        item_copy.name = search_text
        --* book_hits only retrieved here to give the user an indication how important this item is in the text of the book:
        views_data:setItemHits(item_copy, { for_display_mode = "book", force_update = true })
        self:resetViewerItemId()
        if item_copy.book_hits == 0 then
            title = no_hits_title
        else
            title = KOR.icons.xray_add_item_bare .. " " .. item_copy.book_hits .. _(" hits in book")
        end
    end

    return title, item_copy, target_field
end

function XrayFormsData:initEditFormProps(item, reload_manager, active_form_tab)
    self.active_form_mode = "edit"

    DX.d:setProp("edit_args", {
        xray_item = item,
        reload_manager = reload_manager,
    })

    --* this can be the case on longpressing an toc-item in TextViewer; see ((TextViewer toc button)):
    if not item.index or (not item.xray_type and not item.aliases) then
        item = views_data:upgradeNeedleItem(item, {
            include_name_matches = true,
            is_exists_check = true,
        })
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

    return item, item_copy
end

function XrayFormsData:getAndStoreEditedItem(item_copy, field_values)
    if not self.edit_item_index then
        KOR.dialogs:alertError(_("XrayDialogs.edit_item_index has not been set for this item."))
        return
    end
    --* current method is called from ((XrayController#saveUpdatedItem)); book_hits count was added to the edited item there:
    local edited_props = self:
    convertFieldValuesToItemProps(field_values)
    self:reAttachViewerItemId(edited_props)

    --! name field MUST be present:
    if has_no_text(edited_props.name) then
        KOR.messages:notify(_("xray item to be edited wasn't found..."), 4)
        return
    end

    DX.d:setProp("needle_name_for_list_page", "")
    local edited_item = {
        --! this prop is mandatory for saving updated item:
        id = item_copy.id,
        name = edited_props.name,
        description = edited_props.description,
        short_names = edited_props.short_names,
        linkwords = edited_props.linkwords,
        aliases = edited_props.aliases,
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
    self.storeItemUpdates("edit", edited_item.id, edited_item)

    --views_data:initData()

    --* no filter was set, so return simply edited_item:
    if views_data.filter_state == "unfiltered" then
        return edited_item
    end

    --* if a filter was set, return an updated filtered item:
    return self:getFilteredItem(edited_props, edited_item.series_hits, hits_in_book, edited_item.chapter_hits)
        or
        edited_item
end

function XrayFormsData:convertFieldValuesToItemProps(field_values)
    local xray_type = tonumber(field_values[5])
    if not xray_type or xray_type == 0 then
        xray_type = 1
    elseif xray_type > 4 then
        xray_type = 4
    end
    return {
        description = has_text(field_values[1]) or "",
        name = field_values[2],
        --* compare usage of sortKeywords here to ((XrayModel#splitByCommaOrSpace)) for getting needles for searching linked items:
        aliases = has_text(field_values[3]) and KOR.strings:sortKeywords(field_values[3]) or "",
        linkwords = has_text(field_values[4]) and KOR.strings:sortKeywords(field_values[4]) or "",
        xray_type = xray_type,
        short_names = has_text(field_values[6]) and KOR.strings:sortKeywords(field_values[6]) or "",
    }
end

--* this id is set upon viewing an item from the list or after tapping an Xray item button in ((XrayDialogs#viewItem)), or upon viewing an item found upon tapping a word in the reader in ((XrayDialogs#viewTappedWordItem)):
function XrayFormsData:setViewerItemId(item)
    --* "hidden" id, to be re-attached to the updated item in ((XrayFormsData#reAttachViewerItemId)):
    self.form_item_id = item.id
end

--* this id was "remembered" in ((XrayFormsData#setViewerItemId)):
function XrayFormsData:reAttachViewerItemId(item)
    if self.form_item_id then
        --! never set this value to nil, because we need it when switching between form tabs in the edit form:
        item.id = self.form_item_id
    end
    self:resetViewerItemId()
end

function XrayFormsData:resetViewerItemId()
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
    return has_text(item.name) and KOR.strings:limitLength(item.name, views_data.max_line_length) .. ": " or ""
end

function XrayFormsData:getAliasesText(item)
    if has_no_text(item.aliases) then
        return
    end
    local noun = item.aliases:match(" ") and _("aliases") or _("alias")
    noun = noun .. KOR.icons.arrow_bare .. " "
    return KOR.strings:limitLength(noun .. " " .. item.aliases, views_data.max_line_length)
end

function XrayFormsData:getLinkwordsText(item)
    if has_no_text(item.linkwords) then
        return
    end
    local noun = item.linkwords:match(" ") and _("link terms") or _("link term")
    noun = noun .. KOR.icons.arrow_bare .. " "
    return KOR.strings:limitLength(noun .. " " .. item.linkwords, views_data.max_line_length)
end

function XrayFormsData:getFormTabCallback(mode, active_form_tab, item_copy)
    return function(form_tab)
        if form_tab == active_form_tab then
            return
        end
        --- @type MultiInputDialog source
        local source = mode == "add" and DX.d.add_item_input or DX.d.edit_item_input
        item_copy = self:convertFieldValuesToItemProps(source:getValues())
        DX.d:closeForm(mode)
        if mode == "edit" then
            DX.d.edit_item_input = nil
            --! this one is crucial to switch between tabs and preserve changed values!:
            item_copy.index = self.edit_item_index
            DX.c:initAndShowEditItemForm(item_copy, false, form_tab)
        else
            DX.d.add_item_input = nil
            DX.c:initAndShowNewItemForm(nil, form_tab, item_copy)
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
-- #((XrayModel#saveNewItem))
function XrayFormsData.saveNewItem(new_item)

    local self = DX.fd
    local needle_name = self:getNeedleName(new_item)

    --* might be set to a value by ((XrayTappedWords#itemExists)), so here we reset it:
    --* method in current extension, but called like this, to silence luacheck:
    DX.fd:setProp("filter_string", "")

    if DX.c:guardIsExistingItem(needle_name) then
        return
    end
    if type(new_item) == "string" or new_item.text then
        --* name_from_selected_text can be nil when we want to type and add a completely new item:
        DX.c:initAndShowNewItemForm(needle_name)
        return
    end

    new_item.name = needle_name

    --* this call also adds an id prop to item, needed for ((XrayViewsData#updateAndSortAllItemTables)):
    self.storeNewItem(new_item)

    --* set and store props book_hits etc. for this new item:
    views_data:setItemHits(new_item, { store_book_hits = true, mode = "add" })

    --! don't call views_data:updateAndSortAllItemTables(item, "add") here, because then all previous items in list gone from view...
    --* we force refresh of data here, because it could be that list of items hasn't been shown yet:
    views_data:addNewItemToItemTables(new_item)
end

--* compare for edited items: ((XrayFormsData#storeItemUpdates)) > ((XrayModel#storeUpdatedItem))
-- #((XrayModel#storeNewItem))
function XrayFormsData.storeNewItem(new_item)

    local self = DX.fd

    --* always reset filters when adding a new item, to prevent problems:
    DX.c:resetFilteredItems()

    local conn = KOR.databases:getDBconnForBookInfo("XrayModel#storeNewItem")
    local stmt = conn:prepare(self.queries.insert_item)
    local x = new_item
    stmt:reset():bind(parent.current_ebook_basename, x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords):step()

    --* retrieve the id of the newly added item, needed for ((XrayViewsData#updateAndSortAllItemTables)):
    new_item.id = KOR.databases:getNewItemId(conn)
    --* to ensure only this item will be shown bold in the items list:
    self:setProp("last_modified_item_id", new_item.id)
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
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
        table.insert(xray_items, item)
    end
    self.storeItemUpdates("toggle_type", toggle_item.id, toggle_item.xray_type)
    views_data.initData("force_refresh")

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
            if toggle_item.xray_type <= 2 then
                item.xray_type = item.xray_type + 2
            else
                item.xray_type = item.xray_type - 2
            end
            toggle_item.xray_type = item.xray_type
            position = nr
        end
        table.insert(xray_items, item)
    end
    self.storeItemUpdates("toggle_type", toggle_item.id, toggle_item.xray_type)
    views_data.initData("force_refresh")

    return position, toggle_item
end

--* this method called upon rename/edit, toggle importance, toggle person/term of Xray item:
--* for storing new items see ((XrayModel#storeNewItem))
-- #((XrayFormsData#storeItemUpdates))
function XrayFormsData.storeItemUpdates(mode, item_id, updated_item)
    local self = DX.fd
    --* optionally set to a value by ((XrayTappedWords#itemExists)), so here we reset it:
    --! disabled, we want to retain a filter that has been set:
    --self.filter_string = ""

    --* mode has this value when called from ((XrayFormsData#toggleIsPersonOrTerm)) or ((XrayFormsData#toggleIsImportantItem)):
    if mode == "toggle_type" and item_id and updated_item then
        self.storeUpdatedItemType(item_id, updated_item)

    elseif mode == "edit" and item_id and updated_item then
        --* updated_value in this case is a xray item:
        self.storeUpdatedItem(item_id, updated_item)

        --* these props nr, icons and text are needed so we get no crash because of one of these props missing when generating list items in ((XrayViewsData#generateListItemText)) and ((Strings#formatListItemNumber)):
        updated_item.nr = updated_item.index
        local old_icons = views_data.items[updated_item.index].icons
        updated_item.icons = old_icons or ""
        updated_item.text = views_data:generateListItemText(updated_item)

        --! when saving items from the tapped words popup, the index and nr props have to be retrieved from the non tapped word items, otherwise these props would be wrong and the normal, non tapped word items list would show seemingly duplicated items (overwriting another item with the same index):
        if DX.m.use_tapped_word_data then
            updated_item.index = views_data:getItemIndexById(updated_item.id)
            updated_item.nr = updated_item.index
        end
        self:setProp("last_modified_item_id", updated_item.id)
        views_data.current_item = updated_item
        views_data.items[updated_item.index] = updated_item
    end
end

--- @private
function XrayFormsData.storeUpdatedItemType(id, xray_type)
    local self = DX.fd
    local conn = KOR.databases:getDBconnForBookInfo("XrayModel#storeUpdatedItemType")
    local sql = self.queries.update_item_type
    local stmt = conn:prepare(sql)
    stmt:reset():bind(xray_type, self.current_ebook_basename, id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayModel#storeUpdatedItem))
--- @private
function XrayFormsData.storeUpdatedItem(id, updated_item)

    local self = DX.fd

    if not updated_item.name then
        KOR.messages:notify(_("name of item was not determined..."), 4)
        return
    end

    --* in series mode we want to display the total count of all occurences of an item in the entire series:
    local conn = KOR.databases:getDBconnForBookInfo("XrayModel#storeUpdatedItem")
    local sql = parent.current_series and self.queries.update_item_for_entire_series or self.queries.update_item
    local stmt = conn:prepare(sql)
    local x = updated_item
    --! when a xray item is defined for a series of books, all instances per book of that same item will ALL be updated!:
    --* this query will be used in both the series AND in current book display mode of the list of items, BUT ONLY IF a series for the current ebook is defined (so parent.current_series set):
    if parent.current_series then
        --! don't store hits here, because otherwise this count will be saved for all same items in ebooks in the series, but they should normally differ!:
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, id, id):step()
    else
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, x.book_hits, x.chapter_hits, self.current_ebook_basename, id):step()
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayFormsData:setProp(prop, value)
    self[prop] = value
    if prop == "filter_string" then
        self.filter_state = has_text(value) and "filtered" or "unfiltered"
    end
end

return XrayFormsData
