--[[--
This is part of the Dynamic Xray plugin; it is the model (databases operations etc.) for XrayController. It has several child data handlers.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! important info
--* onReaderReady hits per item in the book are stored in self.hits_per_series_title. This prop can be updated in memory after updating, deleting or adding items, so we don't have to reload the data from the database.

--! since I ran into some weird "bad self" error messages when trying to store data in the database, I changed the format of methods involved in this from colon methods to dot functions; and in those I set a local self to KOR.xraymodel

local require = require

local Device = require("device")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local G_reader_settings = G_reader_settings
local has_items = has_items
local has_no_text = has_no_text
local has_text = has_text
local math = math
local pairs = pairs
local string = string
local table = table
local tonumber = tonumber
local type = type

local DB_SCHEMA_VERSION = 20251027
local count
--- @type XrayDataLoader data_loader
local data_loader
--- @type XrayTappedWords tapped_words
local tapped_words
--- @type XrayFormsData forms_data
local forms_data
--- @type XrayViewsData views_data
local views_data

--- @class XrayModel
local XrayModel = WidgetContainer:new{
    active_list_tab = 1,
    create_db = true,
    current_ebook_basename = nil,
    current_ebook_full_path = nil,
    current_series = nil,
    current_title = nil,
    debug_methods_trace = {},
    debug_status = false,
    ebooks = {},
    items_prepared_for_basename = nil,
    min_match_word_length = 4,
    previous_series = nil,
    queries = {
        create_db = [[
            CREATE TABLE IF NOT EXISTS "xray_items" (
                "id" INTEGER NOT NULL,
                "ebook",
                "name",
                "short_names",
                "description",
                "xray_type"	INTEGER NOT NULL DEFAULT 1,
                "aliases",
                "linkwords",
                "book_hits" INTEGER,
                "chapter_hits",
                "hits_determined" INTEGER NOT NULL DEFAULT 0,
                CONSTRAINT "ebook_xray_name_unique" UNIQUE("ebook","name"),
                PRIMARY KEY("id" AUTOINCREMENT)
            );]],

        --* no index added because of small table:
        --[[
        CREATE INDEX "xray_ebook_index" ON "xray_items" (
                "ebook"	ASC
            );
        ]]

        delete_item_book =
            "DELETE FROM xray_items WHERE ebook = ? AND name = ?;",

        delete_item_by_id =
            "DELETE FROM xray_items WHERE ebook = '%1' AND id = %2;",

        delete_item_series =
            [[
            DELETE FROM xray_items
            WHERE ebook IN (
              SELECT filename
              FROM bookinfo
              WHERE series = ?
            )
            AND name = ?;
            ]],

        get_book_items_count =
            "SELECT COUNT(*) FROM xray_items WHERE ebook = 'safe_path';",

        --* we need name AND aliases and short_names, to really find all text occurrences of an item:
        get_items_for_hits_update =
            "SELECT name, aliases, short_names, description, id FROM xray_items WHERE ebook = '%1' AND (book_hits IS NULL OR book_hits = 0) ORDER BY name;",

        get_items_for_ebook_abstract =
            "SELECT name, aliases, short_names, description, id FROM xray_items WHERE ebook = '%1' ORDER BY name;",

        get_items_for_import_from_other_series =
            "SELECT DISTINCT(x.name), x.short_names, x.description, x.xray_type, x.aliases, x.linkwords FROM xray_items x LEFT OUTER JOIN bookinfo b ON x.ebook = b.filename WHERE b.series = 'safe_path' ORDER BY x.name;",

        get_series_name =
            "SELECT series FROM bookinfo WHERE directory || filename = 'safe_path' LIMIT 1;",

        import_items_from_other_books_in_series =
            [[
            SELECT DISTINCT(x.name), x.short_names, x.description, x.xray_type, x.aliases, x.linkwords,
            (
                SELECT SUM(x2.book_hits)
                FROM xray_items x2
                JOIN bookinfo b2 ON b2.filename = x2.ebook
                WHERE b2.series = a.series
                  AND x2.name = x.name
            ) AS series_hits
            FROM xray_items x LEFT OUTER JOIN bookinfo b ON x.ebook = b.filename WHERE b.series = '%1' AND name NOT IN (SELECT name FROM xray_items WHERE ebook = '%2') ORDER BY x.name;
            ]],

        insert_imported_items =
            "INSERT OR IGNORE INTO xray_items (ebook, name, short_names, description, xray_type, aliases, linkwords, book_hits, chapter_hits, hits_determined) VALUES ('%1', ?, ?, ?, ?, ?, ?, ?, ?, 1);",

        update_item_hits =
            "UPDATE xray_items SET book_hits = ?, chapter_hits = ?, hits_determined = 1 WHERE ebook = '%1' AND id = ?;",

        set_db_version =
            "PRAGMA user_version=%1;",
    },
    series = {},
    --* by default sort xray items by number of occurrences:
    sorting_method = "hits",
    switch_first_and_sur_name = false,
    tab_display_counts = { 0, 0, 0 },
    use_tapped_word_data = false,
}

--* this method will be called from ((KOR#initExtensions)):
function XrayModel:init()
    --* if we would use this and consequently would reference DX.c.model instead of DX.m in the other DX modules, data would be reloaded from database onReaderReady for each new book:
    self:createDB()
    self:initDataHandlers()
end

--* using di to inject these data handlers resulted sometimes in crashes, so therefor loading them hardcoded in this method:
function XrayModel:initDataHandlers()
    --* XraySettings must always be registered, so it was registered in ((KOR#initExtensions)) > ((KOR#registerXrayModules))...

    data_loader = require("extensions/xraydataloader")
    data_loader:initDataHandlers(self)
    DX.setProp("dl", data_loader)

    views_data = require("extensions/xrayviewsdata")
    views_data:initDataHandlers(self)
    DX.setProp("vd", views_data)

    forms_data = require("extensions/xrayformsdata")
    forms_data:initDataHandlers(self)
    DX.setProp("fd", forms_data)

    tapped_words = require("extensions/xraytappedwords")
    tapped_words:initDataHandlers(self)
    DX.setProp("tw", tapped_words)
end

-- #((XrayModel#storeDeletedItem))
function XrayModel.storeDeletedItem(current_series, name)

    local self = KOR.xraymodel

    local conn = KOR.databases:getDBconnForBookInfo("XrayModel:storeDeletedItem")
    local sql, stmt
    --! this argument CAN be nil!, so don't use self.current_series here:
    if has_text(current_series) then
        sql = self.queries.delete_item_series
        stmt = conn:prepare(sql)
        stmt:reset():bind(current_series, name):step()
    else
        sql = self.queries.delete_book_item
        stmt = conn:prepare(sql)
        stmt:reset():bind(self.current_ebook_basename, name):step()
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--* lower case needles must be at least 4 characters long, but for names with upper case characters in them no such condition is required:
function XrayModel:isValidNeedle(needle)
    return needle:len() >= self.min_match_word_length or needle:match("[A-Z]")
end

function XrayModel:isXrayItem(name)
    return name:gsub(":.+$", ""):match("[A-Z]")
end

function XrayModel.storeImportedItems(series)

    local self = KOR.xraymodel

    local conn = KOR.databases:getDBconnForBookInfo("XrayModel:storeImportedItems")
    KOR.registry:set("db_conn", conn)
    local sql = KOR.databases:injectSafePath(self.queries.get_items_for_import_from_other_series, series)
    local result = conn:exec(sql)
    if not result then
        conn = KOR.databases:closeInfoConnections(conn)
        KOR.messages:notify(T(_("the series %1 was not found..."), series))
        return
    end
    local current_ebook_basename = KOR.databases:escape(self.current_ebook_basename)
    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))

    count = #result["name"]
    for i = 1, count do
        stmt:reset():bind(
            result["name"][i],
            result["short_names"][i],
            result["description"][i],
            tonumber(result["xray_type"][i]),
            result["aliases"][i],
            result["linkwords"][i],
            0, --* book_hits (integer)
            0 --* chapter_hits (html)
        ):step()
    end
    stmt = KOR.databases:closeInfoStmts(stmt)
    --* above statementa were only concerned with metadata; actual hits update wil now be done in the model: ((XrayModel#refreshItemHitsForCurrentEbook)):
    --* we don't close conn here, because it will be used there:
    DX.c:refreshItemHitsForCurrentEbook()
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
                DX.c:resetFilteredItems()
                DX.d:viewItem(citem, nil, tapped_word)
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
            DX.c:resetFilteredItems()
            DX.d:closeViewer()
            DX.d:viewItem(item, nil, tapped_word)
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

-- #((XrayModel#refreshItemHitsForCurrentEbook))
--* compare ((XrayDialogs#showImportFromOtherSeriesDialog)):
function XrayModel.refreshItemHitsForCurrentEbook()
    local self = KOR.xraymodel

    --* recount all occurrences and save to database; if count = 0, then save as 0 for current book.
    --* if book is part of series, then import all items which are not in the current book, search for their occurrences in current book and only if found store that occurrence for the current book

    local conn = KOR.databases:getDBconnForBookInfo("XrayModel:refreshItemHitsForCurrentEbook")
    local current_ebook_basename = KOR.databases:escape(self.current_ebook_basename)

    local updated_count = 0
    --* determine whether there are items in the series which are not in the current ebook:
    if self.current_series then
        self:setSeriesHitsForImportedItems(conn, current_ebook_basename, updated_count)
    else
        self:setBookHitsForImportedItems(conn, current_ebook_basename)
    end
    conn = KOR.databases:closeInfoConnections(conn)
end

--* compare ((XrayModel#setSeriesHitsForImportedItems)):
--- @private
function XrayModel:setBookHitsForImportedItems(conn, current_ebook_basename)
    local sql = T(self.queries.get_items_for_hits_update, current_ebook_basename)
    local result = conn:exec(sql)
    if not result then
        return
    end

    local name, item, id, book_hits, chapter_hits
    count = #result[1]
    local items_per_batch = math.floor(count / DX.s.batch_count_for_import)
    local stmt = conn:prepare(T(self.queries.update_item_hits, current_ebook_basename))
    DX.c:doBatchImport(count, function(start, icount)
        conn:exec("BEGIN IMMEDIATE")
        local loop_end = start + items_per_batch - 1 <= icount and start + items_per_batch - 1 or icount
        for i = start, loop_end do
            id = tonumber(result["id"][i])
            name = result["name"][i]
            item = {
                name = name,
                chapter_query_done = false,
                aliases = result["aliases"][i],
                short_names = result["short_names"][i],
            }
            book_hits, chapter_hits = views_data:getAllTextHits(item)
            if item.book_hits == 0 then
                conn:exec(T(self.queries.delete_item_by_id, current_ebook_basename, id))
            else
                --* here we execute self.queries.update_item_hits:
                stmt:reset():bind(book_hits, chapter_hits, id):step()
            end
        end
        conn:exec("COMMIT")
        local percentage = math.ceil(loop_end / icount * 100) .. "%"
        return start + items_per_batch, loop_end, percentage
    end)
    stmt = KOR.databases:closeInfoStmts(stmt)
end

--* compare ((XrayModel#setBookHitsForImportedItems)):
--- @private
function XrayModel:setSeriesHitsForImportedItems(conn, current_ebook_basename)
    local current_series = KOR.databases:escape(self.current_series)
    local sql = T(self.queries.import_items_from_other_books_in_series, current_series, current_ebook_basename)
    local new_items_result = conn:exec(sql)
    if not new_items_result then
        return
    end

    local xray_items = KOR.databases:resultsetToItemset(new_items_result)
    local item, book_hits, chapter_hits
    count = #xray_items
    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))
    local items_per_batch = math.floor(count / DX.s.batch_count_for_import)
    DX.c:doBatchImport(count, function(start, icount)
        conn:exec("BEGIN IMMEDIATE")
        local loop_end = start + items_per_batch - 1 <= icount and start + items_per_batch - 1 or icount
        local name
        for i = start, loop_end do
            item = {
                name = xray_items[i].name,
                aliases = xray_items[i].aliases,
            }
            book_hits, chapter_hits = views_data:getAllTextHits(item)
            if book_hits > 0 then
                stmt:reset():bind(
                    xray_items[i].name,
                    xray_items[i].short_names,
                    xray_items[i].description,
                    tonumber(xray_items[i].xray_type),
                    xray_items[i].aliases,
                    xray_items[i].linkwords,
                    book_hits,
                    chapter_hits
                ):step()
            else
                name = KOR.databases:escape(xray_items[i].name)
                conn:exec(T(self.queries.delete_book_item, current_ebook_basename, name))
            end
        end
        conn:exec("COMMIT")
        local percentage = math.ceil(loop_end / icount * 100) .. "%"
        return start + items_per_batch, loop_end, percentage
    end)
    stmt = KOR.databases:closeInfoStmts(stmt)
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
    local self = KOR.xraymodel

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
    self.current_ebook_full_path = full_path or KOR.registry.current_ebook
    self.current_ebook_basename = KOR.filedirnames:basename(self.current_ebook_full_path)

    if use_doc_props and KOR.ui and KOR.ui.doc_props then
        current_series = KOR.ui.doc_props.series
        current_title = KOR.ui.doc_props.title
    end

    local is_non_series_book, series_has_changed
    if not current_series then
        current_series = self:getSeriesName()
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

--- @private
function XrayModel:createDB()
    if not self.create_db or G_reader_settings:isTrue("xray_items_db_created") then
        return
    end

    local db_conn = KOR.databases:getDBconnForBookInfo("XrayModel:createDB")
    --* make it WAL, if possible
    local pragma = Device:canUseWAL() and "WAL" or "TRUNCATE"
    db_conn:exec(string.format("PRAGMA journal_mode=%s;", pragma))
    --* create db
    db_conn:exec(self.queries.create_db)
    --* check version; user_version is unique to sqlite and cannot be changed to another name:
    local db_version = tonumber(db_conn:rowexec("PRAGMA user_version;"))
    --* Update version
    if db_version == 0 then
        db_conn:exec(T(self.queries.set_db_version, DB_SCHEMA_VERSION))
    elseif db_version < DB_SCHEMA_VERSION then
        --[[local ok, re
        local log = function(msg)
            logger.warn("[vocab builder db migration]", msg)
        end
        if db_version < 20220608 then
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD prev_context TEXT;")
            if not ok then
                log(re)
            end
        end

        db_conn:exec("CREATE INDEX IF NOT EXISTS title_id_index ON vocabulary(title_id);")]]
        --* update version
        db_conn:exec(T(self.queries.set_db_version, DB_SCHEMA_VERSION))
    end
    db_conn:close()

    G_reader_settings:saveSetting("xray_items_db_created", true)
end

--* This method can be called at the end of methods in XrayDialog, or ((XrayController#onReaderReady)):
function XrayModel:showMethodsTrace(caller)
    if not self.debug_status or not DX.s.is_ubuntu then
        return
    end

    table.insert(self.debug_methods_trace, caller)

    --* reset the trace for new method calls:
    self.debug_methods_trace = {}
end

-- #((XrayModel#deleteItem))
function XrayModel.deleteItem(delete_item, remove_all_instances_in_series)
    local self = KOR.xraymodel
    local xray_items = {}
    local position = 1
    local xray_item
    count = #views_data.items
    for nr = 1, count do
        xray_item = views_data.items[nr]
        if xray_item.id ~= delete_item.id then
            table.insert(xray_items, xray_item)
        else
            position = nr
        end
    end
    local series = remove_all_instances_in_series and self.current_series
    self.storeDeletedItem(series, delete_item.name)

    if position > #xray_items then
        return #xray_items
    end
    if position == 0 then
        return 1
    end
    return position
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

function XrayModel:resetData(force_refresh)
    --! this one is crucial for when we view tab 2 or 3 in the list in one book and then change to another book; without this, the data for tab 1 of that new book would be set to the data of tab 2 or 3 in the previous book!:
    self.active_list_tab = 1

    self.items_prepared_for_basename = nil
    tapped_words:resetData(force_refresh)
    views_data:resetData()
    if force_refresh then
        self.current_ebook_full_path = KOR.registry.current_ebook
    end
    self.current_ebook_basename = KOR.filedirnames:basename(self.current_ebook_full_path)
    self.ebooks[self.current_ebook_basename] = {}
    if self.current_series then
        self.series[self.current_series] = {}
    end
end

function XrayModel:getSeriesName()
    local conn = KOR.databases:getDBconnForBookInfo("XrayModel:getSeriesName")
    local sql = KOR.databases:injectSafePath(self.queries.get_series_name, self.current_ebook_full_path)
    local series = conn:rowexec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    return series
end

function XrayModel:setProp(prop, value)
    self[prop] = value
end

function XrayModel:markItemsPreparedForCurrentEbook()
    self.items_prepared_for_basename = self.current_ebook_basename
end

return XrayModel
