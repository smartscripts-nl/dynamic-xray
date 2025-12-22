--[[--
This is part of the Dynamic Xray plugin; it is the model (databases operations etc.) for XrayController. It has several child data handlers.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayDataSaver)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData)), ((XrayTranslations))
V = ((XrayUI)), ((XrayTranslations)), ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! important info

--! since I ran into some weird "bad self" error messages when trying to store data in the database, I changed the format of methods involved in this from colon methods to dot functions; and in those I set a local self to DX.ds

local require = require

local Device = require("device")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_text = has_text
local math = math
local string = string
local table = table
local type = type
local unpack = unpack

local count
--- @type XrayModel parent
local parent
--- @type XrayViewsData views_data
local views_data

--[[
fields in the xray_items table:
id,
ebook, -- this is the file basename
name, -- the name of the xray item
short_names,
description,
xray_type, -- value here determines whether an item is important (xray_type 2 or 4) or not (xray_type 1 or 3), and whether it is a person (1-2) or a term (3-4)
aliases,
linkwords,
book_hits, -- an integer
chapter_hits, -- a string, containing a html list of all hits in the chapters of an ebook
hits_determined -- an integer

series_hits is NOT a db field, it is computed dynamically by queries XrayDataLoader.queries.get_all_book_items and XrayDataLoader.queries.get_all_series_items
]]

--* compare ((XrayDataLoader)) for loading data:
--- @class XrayDataSaver
local XrayDataSaver = WidgetContainer:new{
    --* these table modifications are run and depending on the setting "database_scheme_version" in ((XraySettings)):
    table_modifications = {},
    queries = {
        create_items_table = [[
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

        create_translations_table = [[
            CREATE TABLE IF NOT EXISTS xray_translations
            (
                msgid  TEXT not null
                    constraint xray_translations_unique_key
                    unique,
                msgstr TEXT not null,
                md5    TEXT not null
            );]],

        delete_item_book =
            "DELETE FROM xray_items WHERE id = ?;",

        delete_item_series =
            [[DELETE FROM xray_items
            WHERE ebook IN (
              SELECT filename
              FROM bookinfo
              WHERE series = ?
            )
            AND name = ?;]],

        --* we need name AND aliases and short_names, to really find all text occurrences of an item:
        get_items_for_hits_update =
            "SELECT name, aliases, short_names, description, id FROM xray_items WHERE ebook = '%1' AND (book_hits IS NULL OR book_hits = 0) ORDER BY name;",

        get_items_for_import_from_other_series =
            "SELECT DISTINCT(x.name), x.short_names, x.description, x.xray_type, x.aliases, x.linkwords FROM xray_items x LEFT OUTER JOIN bookinfo b ON x.ebook = b.filename WHERE b.series = 'safe_path' ORDER BY x.name;",

        get_series_hits =
            [[
            SELECT SUM(x.book_hits) AS series_hits
            FROM xray_items x
            JOIN bookinfo b ON b.filename = x.ebook
            WHERE x.name = '%1' AND b.series = '%2';]],

        import_items_from_other_books_in_series =
            [[SELECT DISTINCT(x.name), x.short_names, x.description, x.xray_type, x.aliases, x.linkwords,
            (
                SELECT SUM(x2.book_hits)
                FROM xray_items x2
                JOIN bookinfo b2 ON b2.filename = x2.ebook
                WHERE b2.series = a.series
                  AND x2.name = x.name
            ) AS series_hits
            FROM xray_items x LEFT OUTER JOIN bookinfo b ON x.ebook = b.filename WHERE b.series = '%1' AND name NOT IN (SELECT name FROM xray_items WHERE ebook = '%2') ORDER BY x.name;]],

        insert_imported_items =
            "INSERT OR IGNORE INTO xray_items (ebook, name, short_names, description, xray_type, aliases, linkwords, book_hits, chapter_hits, hits_determined) VALUES ('%1', ?, ?, ?, ?, ?, ?, ?, ?, 1);",

        insert_item =
            "INSERT INTO xray_items (ebook, name, short_names, description, xray_type, aliases, linkwords) VALUES (?, ?, ?, ?, ?, ?, ?);",

        update_hits =
            [[UPDATE xray_items
            SET
            book_hits = ?,
            chapter_hits = ?,
            hits_determined = 1
            WHERE id = ?;]],

        update_item =
            "UPDATE xray_items SET name = ?, short_names = ?, description = ?, xray_type = ?, aliases = ?, linkwords = ?, book_hits = ?, chapter_hits = ? WHERE id = ?;",

        update_item_for_entire_series =
            [[UPDATE xray_items
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
              SELECT bi.filename
              FROM bookinfo bi
              WHERE bi.series = (
                  SELECT bi2.series
                  FROM bookinfo bi2
                  JOIN xray_items xi2 ON xi2.ebook = bi2.filename
                  WHERE xi2.id = ?
              )
          );]],

        update_item_hits =
            "UPDATE xray_items SET book_hits = ?, chapter_hits = ?, hits_determined = 1 WHERE id = ?;",

        update_item_type =
            "UPDATE xray_items SET xray_type = ? WHERE id = ?;",
    },
    queries_external = {
        --* called from ((XrayTranslations#get)):
        add_translation_item =
            "INSERT OR IGNORE INTO xray_translations(msgid, msgstr, md5) VALUES(?, ?, ?);",

        --* called from ((XrayTranslations#get)):
        prune_orphan_translations =
            "DELETE FROM xray_translations WHERE WHERE_CONDITIONS;",

        --* called from ((XrayTranslationsManager#manageTranslations)):
        remove_all_translations =
            "DELETE FROM xray_translations WHERE msgid = msgstr;",

        --* called from ((XrayTranslations#updateTranslation)):
        update_translation =
            "UPDATE xray_translations SET msgstr = ? WHERE md5 = ?;",
    },
    version_index_name = "database_scheme_version",
}

--- @param xray_model XrayModel
function XrayDataSaver:initDataHandlers(xray_model)
    parent = xray_model
    views_data = DX.vd
end

function XrayDataSaver:execExternalQuery(context, query_index)
    local conn = KOR.databases:getDBconnForBookInfo(context)
    local result = conn:exec(self.queries_external[query_index])
    conn = KOR.databases:closeInfoConnections(conn)
    return result
end

function XrayDataSaver:runExternalStmt(context, stmt_index, params)
    local conn
    local sql = self.queries_external[stmt_index]

    if sql:match("WHERE_CONDITIONS") and type(params) == "string" then

        --* run removals only once:
        local previous_version = DX.s.prune_orphan_translations_version
        if previous_version == DX.t.prune_orphan_translations_version then
            conn = KOR.databases:closeInfoConnections(conn)
            return
        end

        conn = KOR.databases:getDBconnForBookInfo(context)
        sql = sql:gsub("WHERE_CONDITIONS", params)
        conn:exec(sql)
        conn = KOR.databases:closeInfoConnections(conn)
        --* mark the translations table as pruned:
        DX.s:saveSetting("prune_orphan_translations_version", DX.t.prune_orphan_translations_version)
        return
    end

    conn = KOR.databases:getDBconnForBookInfo(context)
    local stmt = conn:prepare(sql)
    count = #params
    for i = 1, count do
        if type(params[i]) == "string" then
            params[i] = KOR.databases:escape(params[i])
        end
    end
    stmt:reset():bind(unpack(params)):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayDataSaver#storeDeletedItem))
function XrayDataSaver.storeDeletedItem(current_series, delete_item)

    local self = DX.ds

    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver:storeDeletedItem")
    local sql, stmt
    --! this argument CAN be nil!, so don't use parent.current_series here:
    if has_text(current_series) then
        sql = self.queries.delete_item_series
        stmt = conn:prepare(sql)
        stmt:reset():bind(current_series, delete_item.name):step()
    else
        sql = self.queries.delete_item_book
        stmt = conn:prepare(sql)
        stmt:reset():bind(delete_item.id):step()
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver.storeImportedItems(series)

    local self = DX.ds

    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver:storeImportedItems")
    KOR.registry:set("db_conn", conn)
    local sql = KOR.databases:injectSafePath(self.queries.get_items_for_import_from_other_series, series)
    local result = conn:exec(sql)
    if not result then
        conn = KOR.databases:closeInfoConnections(conn)
        KOR.messages:notify(T(_("the series %1 was not found..."), series))
        return
    end
    local current_ebook_basename = KOR.databases:escape(parent.current_ebook_basename)
    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))

    count = #result["name"]
    for i = 1, count do
        stmt:reset():bind(
            result["name"][i],
            result["short_names"][i],
            result["description"][i],
            result["xray_type"][i],
            result["aliases"][i],
            result["linkwords"][i],
            0, --* book_hits (integer)
            0 --* chapter_hits (html)
        ):step()
    end
    stmt = KOR.databases:closeStmts(stmt)
    --* above statementa were only concerned with metadata; actual hits update wil now be done in the model: ((XrayDataSaver#refreshItemHitsForCurrentEbook)):
    --* we don't close conn here, because it will be used there:
    DX.c:refreshItemHitsForCurrentEbook()
end

-- #((XrayViewsData#storeItemHits))
function XrayDataSaver.storeItemHits(item)

    local self = DX.ds

    local id = item.id
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver:updateBookHits")
    local stmt = conn:prepare(self.queries.update_hits)
    stmt:reset():bind(item.book_hits, item.chapter_hits, id):step()
    --! hotfix, should not be necessary:
    if not parent then
        parent = DX.m
    end
    --* for items in books which are part of a series update the prop series_hits:
    if has_text(parent.current_series) then
        local name = KOR.databases:escape(item.name)
        local series = KOR.databases:escape(parent.current_series)
        item.series_hits = conn:rowexec(T(self.queries.get_series_hits, name, series)) or 0
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--* compare for edited items: ((XrayFormsData#storeItemUpdates)) > ((XrayDataSaver#storeUpdatedItem))
-- #((XrayDataSaver#storeNewItem))
function XrayDataSaver.storeNewItem(new_item)

    local self = DX.ds

    --* always reset filters when adding a new item, to prevent problems:
    DX.c:resetFilteredItems()

    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver#storeNewItem")
    local stmt = conn:prepare(self.queries.insert_item)
    local x = new_item
    stmt:reset():bind(parent.current_ebook_basename, x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords):step()

    --* retrieve the id of the newly added item, needed for ((XrayViewsData#updateAndSortAllItemTables)):
    new_item.id = KOR.databases:getNewItemId(conn)
    --* to ensure only this item will be shown bold in the items list:
    DX.fd:setProp("last_modified_item_id", new_item.id)
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayDataSaver#storeUpdatedItem))
--- @private
function XrayDataSaver.storeUpdatedItem(updated_item)

    local self = DX.ds
    if self:itemPropWasMissing(updated_item, { "id", "name" }) then
        return
    end

    --* in series mode we want to display the total count of all occurences of an item in the entire series:
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver#storeUpdatedItem")
    local sql = parent.current_series and self.queries.update_item_for_entire_series or self.queries.update_item
    local stmt = conn:prepare(sql)
    local x = updated_item
    --! when a xray item is defined for a series of books, all instances per book of that same item will ALL be updated!:
    --* this query will be used in both the series AND in current book display mode of the list of items, BUT ONLY IF a series for the current ebook is defined (so parent.current_series set):
    if parent.current_series then
        --! don't store hits here, because otherwise this count will be saved for all same items in ebooks in the series, but they should normally differ!:
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, x.id, x.id):step()
    else
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.aliases, x.linkwords, x.book_hits, x.chapter_hits, x.id):step()
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver.storeUpdatedItemType(updated_item)
    local self = DX.ds
    if self:itemPropWasMissing(updated_item, { "id", "xray_type" }) then
        return
    end
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver#updateXrayItemType")
    local sql = self.queries.update_item_type
    local stmt = conn:prepare(sql)
    stmt:reset():bind(updated_item.xray_type, updated_item.id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver:itemPropWasMissing(updated_item, check_props)
    count = #check_props
    for i = 1, count do
        if not updated_item[check_props[i]] then
            KOR.messages:notify(check_props[i] .. _(" of item could not be determined..."), 4)
            return true
        end
    end
    return false
end

-- #((XrayDataSaver#refreshItemHitsForCurrentEbook))
--* compare ((XrayDialogs#showImportFromOtherSeriesDialog)):
function XrayDataSaver.refreshItemHitsForCurrentEbook()
    local self = DX.ds

    --* recount all occurrences and save to database; if count = 0, then save as 0 for current book.
    --* if book is part of series, then import all items which are not in the current book, search for their occurrences in current book and only if found store that occurrence for the current book

    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver:refreshItemHitsForCurrentEbook")
    local current_ebook_basename = KOR.databases:escape(parent.current_ebook_basename)

    --* determine whether there are items in the series which are not in the current ebook:
    if parent.current_series then
        self:setSeriesHitsForImportedItems(conn, current_ebook_basename)
    else
        self:setBookHitsForImportedItems(conn, current_ebook_basename)
    end
    conn = KOR.databases:closeInfoConnections(conn)
end

--- @private
function XrayDataSaver:processItemsInBatches(conn, item_ids, batch_count, process_item)
    count = #item_ids
    if count == 0 then
        return
    end

    local items_per_batch = math.max(1, math.floor(count / batch_count))

    DX.c:doBatchImport(count, function(start, icount)
        conn:exec("BEGIN IMMEDIATE")

        local loop_end = math.min(start + items_per_batch - 1, icount)
        for i = start, loop_end do
            process_item(i, item_ids[i])
        end

        conn:exec("COMMIT")
        local percentage = math.ceil(loop_end / icount * 100) .. "%"
        return start + items_per_batch, loop_end, percentage
    end)
end

--* compare ((XrayDataSaver#setSeriesHitsForImportedItems)):
--- @private
function XrayDataSaver:setBookHitsForImportedItems(conn, current_ebook_basename)
    local sql = T(self.queries.get_items_for_hits_update, current_ebook_basename)
    local result = conn:exec(sql)
    if not result then
        return
    end

    local stmt = conn:prepare(self.queries.update_item_hits)
    local ids = result.id --* this is a table of ids
    self:processItemsInBatches(conn, ids, DX.s.batch_count_for_import, function(i)
        local item = {
            name = result.name[i],
            aliases = result.aliases[i],
            short_names = result.short_names[i],
            chapter_query_done = false,
        }

        local book_hits, chapter_hits = views_data:getAllTextHits(item)
        if book_hits == 0 then
            conn:exec(T(self.queries.delete_item_book, ids[i]))
        else
            stmt:reset():bind(book_hits, chapter_hits, ids[i]):step()
        end
    end)

    KOR.databases:closeStmts(stmt)
end

--* compare ((XrayDataSaver#setBookHitsForImportedItems)):
--- @private
function XrayDataSaver:setSeriesHitsForImportedItems(conn, current_ebook_basename)
    local series = KOR.databases:escape(parent.current_series)
    local sql = T(self.queries.import_items_from_other_books_in_series, series, current_ebook_basename)
    local result = conn:exec(sql)
    if not result then
        return
    end

    local items = KOR.databases:resultsetToItemset(result)
    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))

    self:processItemsInBatches(conn, items, DX.s.batch_count_for_import, function(_, src)
        local item = {
            name = src.name,
            aliases = src.aliases,
        }

        local book_hits, chapter_hits = views_data:getAllTextHits(item)
        if book_hits > 0 then
            stmt:reset():bind(
                src.name,
                src.short_names,
                src.description,
                src.xray_type,
                src.aliases,
                src.linkwords,
                book_hits,
                chapter_hits
            ):step()
        else
            conn:exec(T(self.queries.delete_item_book, src.id))
        end
    end)

    KOR.databases:closeStmts(stmt)
end

-- #((XrayDataSaver#createAndModifyTables))
--- @private
function XrayDataSaver.createAndModifyTables()

    local self = DX.ds

    local version_index = has_items(DX.s[self.version_index_name]) and DX.s[self.version_index_name]
    local updates_count = #self.table_modifications
    if version_index == updates_count then
        return
    end

    local conn = KOR.databases:getDBconnForBookInfo("XrayDataSaver:createDB")
    if version_index == 0 then
        --* make it WAL, if possible
        local pragma = Device:canUseWAL() and "WAL" or "TRUNCATE"
        conn:exec(string.format("PRAGMA journal_mode=%s;", pragma))
        --* create tables:
        conn:exec(self.queries.create_items_table)
        conn:exec(self.queries.create_translations_table)
    end

    --* Update version
    if updates_count > 0 then
        self.modifyTables(conn, updates_count, version_index)
        DX.s:saveSetting(self.version_index_name, updates_count)
    end
    conn = KOR.databases:closeInfoConnections(conn)
end

-- #((XrayDataSaver#deleteItem))
function XrayDataSaver.deleteItem(delete_item, remove_all_instances_in_series)
    local self = DX.ds
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
    local series = remove_all_instances_in_series and parent.current_series
    self.storeDeletedItem(series, delete_item)

    if position > #xray_items then
        return #xray_items
    end
    if position == 0 then
        return 1
    end
    return position
end

-- #((XrayDataSaver#modifyTables))
function XrayDataSaver.modifyTables(conn, updates_count, version_index)
    local self = DX.ds
    if version_index and updates_count > 0 and version_index < updates_count then
        local sql
        for i = version_index + 1, updates_count do
            sql = self.table_modifications[i]
            conn:exec(sql)
        end
    end
end

return XrayDataSaver
