
--* see ((Dynamic Xray: module info)) for more info

--! important info

--! since I ran into some weird "bad self" error messages when trying to store data in the database, I changed the format of methods involved in this from colon methods to dot functions; and in those I set a local self to DX.ds

local require = require

local Device = require("device")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local logger = require("logger")
local json = require("json")

local DX = DX
local G_reader_settings = G_reader_settings
local has_no_items = has_no_items
local has_text = has_text
local logger_info = logger.info
local logger_warn = logger.warn
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local pcall = pcall
local string_format = string.format
local T = T
local table_concat = table.concat
local table_insert = table.insert
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
tags,
linkwords,
book_hits, -- an integer
chapter_hits, -- a string, containing a html list of all hits in the chapters of an ebook
chapter_hits_data -- a comma delimited string of number, indicating item hits per chapter
]]
--! series_hits is NOT a db field, it is computed dynamically by queries XrayDataLoader.queries.get_all_book_items and XrayDataLoader.queries.get_all_series_items

--* compare ((XrayDataLoader)) for loading data:
--- @class XrayDataSaver
local XrayDataSaver = WidgetContainer:new{
    queries = {
        add_quote = [[
            INSERT INTO xray_quotes (item_name, ebook, ebook_title, series, series_index, quote, pos0, chapter) VALUES(?, ?, ?, ?, ?, ?, ?, ?);]],

        -- #((create main DX table))
        create_items_table = [[
            CREATE TABLE IF NOT EXISTS "xray_items" (
                "id" INTEGER NOT NULL,
                "ebook",
                "name",
                "short_names",
                "description",
                "xray_type"	INTEGER NOT NULL DEFAULT 1,
                "aliases",
                "tags",
                "linkwords",
                "book_hits" INTEGER,
                "chapter_hits",
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

        delete_item_series = [[
            DELETE FROM xray_items
            WHERE ebook IN (
              SELECT filename
              FROM bookinfo
              WHERE series = ?
            )
            AND name = ?;]],

        insert_imported_items =
            "INSERT OR IGNORE INTO xray_items (ebook, name, short_names, description, xray_type, non_breakable, aliases, tags, linkwords, book_hits, chapter_hits, chapter_hits_data) VALUES ('%1', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",

        insert_item =
            "INSERT OR IGNORE INTO xray_items (ebook, name, short_names, description, xray_type, non_breakable, aliases, tags, linkwords) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",

        quote_delete =
            "DELETE FROM xray_quotes WHERE id = ?;",

        quote_update =
            "UPDATE xray_quotes SET quote = ? WHERE id = ?;",

        store_book_chapters =
            "INSERT OR IGNORE INTO xray_books (ebook, chapters) VALUES (?, ?);",

        update_chapter_hits_data = [[
            UPDATE xray_items
            SET
            chapter_hits_data = ?
            WHERE id = ?;]],

        update_hits = [[
            UPDATE xray_items
            SET
            book_hits = ?,
            chapter_hits = ?,
            chapter_hits_data = ?
            WHERE id = ?;]],

        update_item =
            "UPDATE OR IGNORE xray_items SET name = ?, short_names = ?, description = ?, xray_type = ?, non_breakable = ?, aliases = ?, tags = ?, linkwords = ?, book_hits = ?, chapter_hits = ? WHERE id = ?;",

        --* this will similtanuously update the item in all ebooks of the series:
        update_item_for_entire_series = [[
            UPDATE OR IGNORE xray_items
            SET
            name = ?,
            short_names = ?,
            description = ?,
            xray_type = ?,
            non_breakable = ?,
            aliases = ?,
            tags = ?,
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
            "UPDATE xray_items SET book_hits = ?, chapter_hits = ?, chapter_hits_data = ? WHERE id = ?;",

        update_items_tags =
            "UPDATE xray_items SET tags = ? WHERE id = ?;",

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
    --* these table modifications for table bookinfo are run and depending on the setting "database_scheme_version" in G_reader_settings or ((XraySettings)), for the public version of DX:
    --* for creation of main DX table, see ((XrayDataSaver#createAndModifyTables)) > ((create main DX table)):
    scheme_alter_queries = {
        --* update 1:
        [[
            CREATE TABLE IF NOT EXISTS finished_books
            (
                path  TEXT not null
                    constraint finished_book_unique
                    unique
            );]],

        --* update 2:
        [[
            ALTER TABLE bookinfo ADD COLUMN rating_goodreads REAL;]],

        --* update 3:
        [[
            ALTER TABLE bookinfo ADD COLUMN publication_year INTEGER;]],

        --* update 4:
        [[
            ALTER TABLE bookinfo ADD COLUMN bookmarks INTEGER;]],

        --* update 5:
        [[
            ALTER TABLE bookinfo RENAME COLUMN bookmarks TO annotations;]],

        --* update 6:
        [[
            ALTER TABLE bookinfo ADD COLUMN stars INTEGER;]],

        --* update 7:
        [[
            ALTER TABLE xray_items ADD COLUMN chapter_hits_data;]],

        --* update 8:
        [[
            CREATE TABLE IF NOT EXISTS xray_books
            (
                ebook TEXT not null,
                chapters TEXT
                    constraint xray_books_unique_book
                    unique
            );]],

        --* update 9:
        [[
            CREATE TABLE IF NOT EXISTS xray_quotes
            (
                id INTEGER NOT NULL
                    CONSTRAINT xray_quotes_pk
                        PRIMARY KEY AUTOINCREMENT,
                item_name NOT NULL,
                series,
                series_index,
                ebook NOT NULL,
                ebook_title,
                chapter,
                pos0,
                quote NOT NULL
            );]],

        --* update 10:
        [[
            ALTER TABLE bookinfo ADD COLUMN glossary;]],

        --* update 11:
        [[
            UPDATE xray_items SET chapter_hits = NULL, chapter_hits_data = NULL WHERE 1;]],

        --* update 12:
        --* a second reset was needed after some updates to the hits counting system:
        [[
            UPDATE xray_items SET chapter_hits = NULL, chapter_hits_data = NULL WHERE 1;]],

        --* update 13:
        [[
            ALTER TABLE xray_items ADD COLUMN non_breakable INTEGER NOT NULL DEFAULT 0;]],

        --* update 14:
        --* a third reset was needed after some updates to the hits counting system:
        [[
            UPDATE xray_items SET chapter_hits_data = NULL, chapter_hits = NULL WHERE 1;]],

        --* update 15:
        [[
            ALTER TABLE bookinfo RENAME COLUMN glossary TO xray_reference_info;]],

        --* update 16:
        [[
            ALTER TABLE bookinfo RENAME COLUMN xray_reference_info TO reference_information;]],

        --* update 17:
        [[
            ALTER TABLE bookinfo ADD COLUMN reference_information_css;]],

        --* update 18:
        [[
            ALTER TABLE bookinfo ADD COLUMN reference_information_headings;]],

        --! when adding scheme modifations above, also add a scheme_verification_query below with the correct index!!
    },
    scheme_verification_queries = {
        --* check update 1:
        { "PRAGMA table_info('finished_books');", 1 },

        --* check update 2:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'rating_goodreads';", 2 },

        --* check update 3:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'publication_year';", 3 },

        --* check update 4:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'bookmarks';", 4 },

        --* check update 5:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'annotations';", 5 },

        --* check update 6:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'stars';", 6 },

        --* check update 7:
        { "SELECT 1 FROM pragma_table_info('xray_items') WHERE name = 'chapter_hits_data';", 7 },

        --* check update 8:
        { "PRAGMA table_info('xray_books');", 8 },

        --* check update 9:
        { "PRAGMA table_info('xray_quotes');", 9 },

        --* check update 10:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'glossary';", 10 },

        --* check update 13:
        { "SELECT 1 FROM pragma_table_info('xray_items') WHERE name = 'non_breakable';", 13 },

        --* check update 15:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'xray_reference_info';", 15 },

        --* check update 16:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'reference_information';", 16 },

        --* check update 17:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'reference_information_css';", 17 },

        --* check update 18:
        { "SELECT 1 FROM pragma_table_info('bookinfo') WHERE name = 'reference_information_headings';", 18 },
    },
    scheme_version_name = "DX_database_scheme_version",
    tables_created_index = "DX_tables_created",
}

--- @param xray_model XrayModel
function XrayDataSaver:initDataHandlers(xray_model)
    parent = xray_model
    views_data = DX.vd
end

function XrayDataSaver:execExternalQuery(context, query_index)
    local conn = KOR.databases:getDBconn(context)
    local result = conn:exec(self.queries_external[query_index])
    conn = KOR.databases:closeConnections(conn)
    return result
end

function XrayDataSaver:runExternalStmt(context, stmt_index, params)
    local conn
    local sql = self.queries_external[stmt_index]

    if sql:match("WHERE_CONDITIONS") and type(params) == "string" then

        --* run removals only once:
        local previous_version = DX.s.prune_orphan_translations_version
        if previous_version == DX.t.prune_orphan_translations_version then
            conn = KOR.databases:closeConnections(conn)
            return
        end

        conn = KOR.databases:getDBconn(context)
        sql = sql:gsub("WHERE_CONDITIONS", params)
        conn:exec(sql)
        conn = KOR.databases:closeConnections(conn)
        --* mark the translations table as pruned:
        DX.s:saveSetting("prune_orphan_translations_version", DX.t.prune_orphan_translations_version)
        return
    end

    conn = KOR.databases:getDBconn(context)
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

    local conn = KOR.databases:getDBconn("XrayDataSaver:storeDeletedItem")
    local sql, stmt
    local id = delete_item.id
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

    parent:updateStaticReferenceCollections(id, nil)
end

function XrayDataSaver.storeChapters(chapters)
    local self = DX.ds

    chapters = json.encode(chapters)
    local conn = KOR.databases:getDBconn("XrayDataSaver.storeChapters")
    local stmt = conn:prepare(self.queries.store_book_chapters)
    stmt:reset():bind(parent.current_ebook_basename, chapters):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver.storeChapterHitsData(item)
    local self = DX.ds

    local chapter_hits_data = self:getChapterHitsDataForStorage(item.chapter_hits_data)
    local conn = KOR.databases:getDBconn("XrayDataSaver.storeChapterHitsData")
    local stmt = conn:prepare(self.queries.update_chapter_hits_data)
    stmt:reset():bind(chapter_hits_data, item.id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayDataSaver.storeMissingChapterHitsData))
function XrayDataSaver.storeMissingChapterHitsData(item, book_hits)
    local self = DX.ds

    local chapter_hits_data = table_concat(item.chapter_hits_data, ",")
    local conn = KOR.databases:getDBconn("XrayDataSaver.storeChapterHitsList")
    local stmt = conn:prepare(self.queries.update_hits)
    stmt:reset():bind(book_hits, item.chapter_hits, chapter_hits_data, item.id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver.storeQuote(item, quote, pos0, chapter)
    local self = DX.ds

    local conn = KOR.databases:getDBconn("XrayDataSaver.storeQuote")
    local stmt = conn:prepare(self.queries.add_quote)
    stmt:reset():bind(item.name, parent.current_ebook_basename, parent.current_title, parent.current_series, parent.current_series_index, quote, pos0, chapter):step()

    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--* compare ((XrayDataLoader#convertChapterHitsData)), where the data are retrieved from the database:
function XrayDataSaver:getChapterHitsDataForStorage(chapter_hits_data)
    if has_no_items(chapter_hits_data) then
        return nil
    end
    return table_concat(chapter_hits_data, ",")
end

function XrayDataSaver.storeImportedItemsFromSeries(series, is_other_series)

    local self = DX.ds

    local conn = KOR.databases:getDBconn("XrayDataSaver:storeImportedItems", nil, "is_initial_connection")
    local result = DX.dl:getItemsForImportFromSeries(conn, series, is_other_series)
    count = result and #result["name"] or 0
    if count == 0 then
        conn = KOR.databases:closeConnections(conn)
        local initial_notification = KOR.registry:getOnce("import_notification")
        UIManager:close(initial_notification)
        UIManager:forceRePaint()
        KOR.messages:notify(_("there were no new items to be imported"))
        return
    end

    local current_ebook_basename = KOR.databases:escape(parent.current_ebook_basename)
    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))
    local item, id
    local imported_items = {}
    for i = 1, count do
        item = {
            name = result["name"][i],
            short_names = result["short_names"][i],
            description = result["description"][i],
            xray_type = result["xray_type"][i],
            non_breakable = tonumber(result["non_breakable"][i]) or 0,
            aliases = result["aliases"][i],
            tags = result["tags"][i],
            linkwords = result["linkwords"][i],
            book_hits = 0,
            chapter_hits = nil,
        }
        stmt:reset():bind(
            result["name"][i],
            result["short_names"][i],
            result["description"][i],
            result["xray_type"][i],
            tonumber(result["non_breakable"][i]) or 0,
            result["aliases"][i],
            result["tags"][i],
            result["linkwords"][i],
            0, --* book_hits (integer)
            nil --* chapter_hits (html)
        ):step()
        id = KOR.databases:getNewItemId(conn)
        item.id = id
        table_insert(imported_items, item)
    end
    stmt = KOR.databases:closeStmts(stmt)
    --* above stmt was only concerned with metadata; actual hits update wil now be done in this method:
    self.setItemHitsForImportedItems(imported_items, conn)
end

-- #((XrayViewsData#storeItemHits))
function XrayDataSaver.storeItemHits(item)

    local self = DX.ds

    local id = item.id
    local conn = KOR.databases:getDBconn("XrayDataSaver:updateBookHits")
    local chapter_hits_data = self:getChapterHitsDataForStorage(item.chapter_hits_data)
    local stmt = conn:prepare(self.queries.update_hits)
    stmt:reset():bind(item.book_hits, item.chapter_hits, chapter_hits_data, id):step()
    --! hotfix, should not be necessary:
    if not parent then
        parent = DX.m
    end
    --* for items in books which are part of a series update the prop series_hits:
    if has_text(parent.current_series) then
        local name = KOR.databases:escape(item.name)
        local series = KOR.databases:escape(parent.current_series)
        item.series_hits = DX.dl:getSeriesHits(conn, series, name)
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayDataSaver#storeItemsTags))
--* item_ids_and_tags is a associative table, with item ids as indices for the updated tags:
function XrayDataSaver.storeItemsTags(item_ids_and_tags)
    local self = DX.ds
    local conn = KOR.databases:getDBconn("XrayDataSaver:storeItemsTags")
    local stmt = conn:prepare(self.queries.update_items_tags)
    local item
    for id, tags in pairs(item_ids_and_tags) do
        --* this might be set in ((XrayTags#prepareUpdatedItemTags)), when after deletion of a tag there were no remaining tags:
        if tags == "nil" then
            tags = nil
        end
        stmt:reset():bind(tags, id):step()
        item = views_data:getItemById(id)
        item.tags = tags
        parent:updateStaticReferenceCollections(id, item)
        views_data:registerUpdatedItem(item)
    end
    --* do this to make sure we remove possibly now empty tag-groups after tag deletions:
    parent:updateAllTags()
    --* to determine unique last names:
    parent:updateLastNameCounts()

    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end


--* compare for edited items: ((XrayFormsData#storeItemUpdates)) > ((XrayDataSaver#storeUpdatedItem))
-- #((XrayDataSaver#storeNewItem))
function XrayDataSaver.storeNewItem(new_item)

    local self = DX.ds

    local conn = KOR.databases:getDBconn("XrayDataSaver#storeNewItem")
    local stmt = conn:prepare(self.queries.insert_item)
    local x = new_item
    --* set empty texts to nil; these might have been generated in ((MultiInputDialog#registerFieldValues)), when the user never opened a particular form tab for left the fields empty:
    self:setEmptyPropsToNil(x)
    stmt:reset():bind(parent.current_ebook_basename, x.name, x.short_names, x.description, x.xray_type, x.non_breakable, x.aliases, x.tags, x.linkwords):step()

    --* retrieve the id of the newly added item, needed for ((XrayViewsData#updateAndSortAllItemTables)):
    --* this is better than using KOR.databases:getNewItemId(), to prevent errors after trying to add an already existing item once again:
    new_item.id = DX.dl.getItemId(conn, x.name)
    --* to ensure only this item will be shown bold in the items list:
    DX.fd:setProp("last_modified_item_id", new_item.id)
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

-- #((XrayDataSaver#storeUpdatedItem))
--- @private
function XrayDataSaver.storeUpdatedItem(item)

    local self = DX.ds
    if self:itemPropWasMissing(item, { "id", "name" }) then
        return
    end

    --* in series mode we want to display the total count of all occurences of an item in the entire series:
    local conn = KOR.databases:getDBconn("XrayDataSaver#storeUpdatedItem")
    local sql = parent.current_series and self.queries.update_item_for_entire_series or self.queries.update_item
    local stmt = conn:prepare(sql)
    local x = item
    local id = item.id
    --* set empty texts to nil; these might have been generated in ((MultiInputDialog#registerFieldValues)), when the user never opened a particular form tab for left the fields empty:
    self:setEmptyPropsToNil(x)
    --! when a xray item is defined for a series of books, all instances per book of that same item will ALL be updated!:
    --* this query will be used in both the series AND in current book display mode of the Items List, BUT ONLY IF a series for the current ebook is defined (so parent.current_series set):
    if parent.current_series then
        --! don't store hits here, because otherwise this count will be saved for all same items in ebooks in the series, but they should normally differ!:
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.non_breakable, x.aliases, x.tags, x.linkwords, id, id):step()
    else
        stmt:reset():bind(x.name, x.short_names, x.description, x.xray_type, x.non_breakable, x.aliases, x.tags, x.linkwords, x.book_hits, x.chapter_hits, id):step()
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)

    parent:updateStaticReferenceCollections(id, item)
end

function XrayDataSaver.storeUpdatedItemType(item)
    local self = DX.ds
    if self:itemPropWasMissing(item, { "id", "xray_type" }) then
        return
    end
    local id = item.id
    local conn = KOR.databases:getDBconn("XrayDataSaver#updateXrayItemType")
    local sql = self.queries.update_item_type
    local stmt = conn:prepare(sql)
    stmt:reset():bind(item.xray_type, id):step()
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

-- #((XrayDataSaver#setItemHitsForImportedItems))
--* compare ((XrayDialogs#showImportFromOtherSeriesDialog)):
function XrayDataSaver.setItemHitsForImportedItems(imported_items, conn)
    local self = DX.ds

    --* recount all occurrences and save to database; if count = 0, then save as 0 for current book.
    --* if book is part of series, then import all items which are not in the current book, search for their occurrences in current book and only if found store that occurrence for the current book

    local current_ebook_basename = KOR.databases:escape(parent.current_ebook_basename)

    --* determine whether there are items in the series which are not in the current ebook:
    if parent.current_series then
        self:setSeriesHitsForImportedItems(conn, current_ebook_basename, imported_items)
    else
        self:setBookHitsForImportedItems(conn, imported_items)
    end
end

--- @private
function XrayDataSaver:processItemsInBatches(conn, stmt, items, batch_count, process_item)
    count = #items
    if count == 0 then
        return
    end

    local items_per_batch = math_max(1, math_floor(count / batch_count))

    conn = DX.c:doBatchImport(conn, stmt, count, function(start, icount)
        conn:exec("BEGIN IMMEDIATE")

        local loop_end = math_min(start + items_per_batch - 1, icount)
        for i = start, loop_end do
            --* process_items callback e.g. defined in ((XrayDataSaver#setSeriesHitsForImportedItems)):
            process_item(items[i])
        end

        conn:exec("COMMIT")
        local percentage = math_ceil(loop_end / icount * 100) .. "%"
        return start + items_per_batch, loop_end, percentage
    end)
end

--* compare ((XrayDataSaver#setSeriesHitsForImportedItems)):
--- @private
function XrayDataSaver:setBookHitsForImportedItems(conn, imported_items)

    local stmt = conn:prepare(self.queries.update_item_hits)
    conn, stmt = self:processItemsInBatches(conn, stmt, imported_items, DX.s.batch_count_for_import, function(item)
        if not item then
            return
        end

        local book_hits, chapter_hits, chapter_hits_data = views_data:getAllTextHits(item)
        if book_hits == 0 then
            conn:exec(T(self.queries.delete_item_book, item.id))
            parent:updateStaticReferenceCollections(item.id, nil)
        else
            chapter_hits_data = self:getChapterHitsDataForStorage(chapter_hits_data)
            stmt:reset():bind(book_hits, chapter_hits, chapter_hits_data, item.id):step()
            item.book_hits = book_hits
            item.chapter_hits = chapter_hits
            item.chapter_hits_data = chapter_hits_data
            item.chapter_query_done = true
            parent:updateStaticReferenceCollections(item.id, item)
        end
    end)
end

--* compare ((XrayDataSaver#setBookHitsForImportedItems)):
--- @private
function XrayDataSaver:setSeriesHitsForImportedItems(conn, current_ebook_basename, imported_items)
    count = #imported_items

    local stmt = conn:prepare(T(self.queries.insert_imported_items, current_ebook_basename))
    conn, stmt = self:processItemsInBatches(conn, stmt, imported_items, DX.s.batch_count_for_import, function(item)
        local id = item.id

        local book_hits, chapter_hits, chapter_hits_data = views_data:getAllTextHits(item)
        if book_hits > 0 then
            chapter_hits_data = self:getChapterHitsDataForStorage(chapter_hits_data)
            stmt:reset():bind(
                item.name,
                item.short_names,
                item.description,
                item.xray_type,
                item.aliases,
                item.tags,
                item.linkwords,
                book_hits,
                chapter_hits,
                chapter_hits_data
            ):step()
            parent:updateStaticReferenceCollections(id, item)
        else
            conn:exec(T(self.queries.delete_item_book, item.id))
            parent:updateStaticReferenceCollections(id, nil)
        end
    end)
end

--- @private
function XrayDataSaver:logSchemeModification(heading, message, message_type)
    if not DX.s.log_database_scheme_modifications then
        return
    end

    if message_type == "warn" then
        logger_warn(heading, message)
        return
    end

    logger_info(heading, message)
end

-- #((XrayDataSaver#createAndModifyTables))
--- @private
function XrayDataSaver.createAndModifyTables()

    --! for manual override and recreation of db tables and fields, see ((XrayCodeProcedures#DATABASE)) in ((xray-info.lua))...

    local self = DX.ds
    local tables_were_created = G_reader_settings:readSetting(self.tables_created_index)

    --* set this to true only for debugging purposes:
    local overrule_tables_creation = false
    if overrule_tables_creation then
        tables_were_created = false
    end
    local conn

    local do_flush_settings = false
    local nothing_modified = true
    if not tables_were_created then

        self:logSchemeModification("creating DX tables", "start", "info")

        conn = KOR.databases:getDBconn("XrayDataSaver:createAndModifyTables 1")
        --* make it WAL, if possible
        local pragma = Device:canUseWAL() and "WAL" or "TRUNCATE"
        conn:exec(string_format("PRAGMA journal_mode=%s;", pragma))
        --* create tables:
        pcall(function()
            conn:exec(self.queries.create_items_table)
            conn:exec(self.queries.create_translations_table)
        end)

        G_reader_settings:saveSetting(self.tables_created_index, true)
        do_flush_settings = true
        nothing_modified = false

        self:logSchemeModification("creating DX tables", "tables created", "info")
    end

    local update_tasks_count = #self.scheme_alter_queries
    local version_index = overrule_tables_creation and 0 or G_reader_settings:readSetting(self.scheme_version_name)

    local do_debug = false
    if do_debug then
        logger_info("db_update version_index > update_tasks_count", version_index .. " > " .. update_tasks_count)
    end

    local version_index_was_saved = true
    if not version_index or version_index == 0 then
        version_index_was_saved = false
        version_index = 0
        if do_debug then
            logger_info("db_update", "version_index reset to 0")
        end

    --* if we removed a modification query, users could have a higher stored version_index, so it must be reset to the lower value
    elseif version_index > update_tasks_count then
        version_index_was_saved = false
        version_index = update_tasks_count
        if do_debug then
            logger_info("db_update", "version_index corrected to lower value")
        end

    elseif version_index ~= update_tasks_count then
        if not conn then
            conn = KOR.databases:getDBconn("XrayDataSaver:createAndModifyTables 2")
        end
        version_index = self.updateVersionIndex(conn, version_index, do_debug)
        version_index_was_saved = false
        if do_debug then
            logger_info("db_update", "update done; new value: " .. version_index)
        end
    end
    if not version_index_was_saved then
        G_reader_settings:saveSetting(self.scheme_version_name, version_index)
        do_flush_settings = true
    end
    if do_flush_settings then
        G_reader_settings:flush()
    end

    --* return if nothing has to be modified:
    if
        update_tasks_count == 0
        or version_index == update_tasks_count
    then
        self:logSchemeModification("NO DX DATABASE-SCHEME MODIFICATION NECESSARY", T("update_tasks_count %1, version_index %2", update_tasks_count, version_index), "info")
        if conn then
            conn = KOR.databases:closeConnections(conn)
        end
        return
    end

    if not conn then
        conn = KOR.databases:getDBconn("XrayDataSaver:createAndModifyTables 3")
    end

    self:logSchemeModification("modifying DX tables", T("start queries %1 to %2", version_index, update_tasks_count), "info")
    self.modifyTables(conn, update_tasks_count, version_index)
    self:logSchemeModification("modifying DX tables", "ready", "info")
    --* update database_scheme_version in XraySettings:
    G_reader_settings:saveSetting(self.scheme_version_name, update_tasks_count)
    G_reader_settings:flush()

    conn = KOR.databases:closeConnections(conn)
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
            table_insert(xray_items, xray_item)
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
function XrayDataSaver.modifyTables(conn, update_tasks_count, version_index)
    if parent:isPrivateDXversion("silent") then
        return
    end
    local self = DX.ds
    local sql, ok, err
    local heading_pre = "\n\n_____________________\n\n"
    local heading_end = ":\n_____________________\n\n"
    local error_heading = "\n\nERROR AND TRACE\n\n"
    for i = version_index + 1, update_tasks_count do
        if self.scheme_alter_queries[i] then
            sql = self.scheme_alter_queries[i]
            ok, err = pcall(function()
                conn:exec(sql)
            end)
            if DX.s.log_database_scheme_modifications and not ok then
                self:logSchemeModification(heading_pre .. "FAILED QUERY " .. i .. "\n(but will be ignored and disappear upon restart)" .. heading_end, sql .. error_heading .. err, "warn")
            elseif DX.s.log_database_scheme_modifications then
                self:logSchemeModification(heading_pre .. "QUERY OK " .. i .. heading_end, sql, "info")
            end
        end
    end
end

function XrayDataSaver.quoteDelete(id)
    local self = DX.ds
    local conn = KOR.databases:getDBconn("XrayDataSaver.quoteDelete")
    local stmt = conn:prepare(self.queries.quote_delete)
    stmt:reset():bind(id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

function XrayDataSaver.quoteUpdate(id, value)
    local self = DX.ds
    local conn = KOR.databases:getDBconn("XrayDataSaver.quoteUpdate")
    local stmt = conn:prepare(self.queries.quote_update)
    stmt:reset():bind(value, id):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--* check whether previous DX installations already created some tables or fields and update version_index accordingly:
function XrayDataSaver.updateVersionIndex(conn, version_index, do_debug)

    local self = DX.ds
    count = #self.scheme_verification_queries

    local last_update_query = self.scheme_verification_queries[count][1]
    if conn:exec(last_update_query) then
        if do_debug then
            logger_warn("XrayDataSaver.updateVersionIndex", "no update necessary")
        end
        --* this returns de facto last_update_index:
        return self.scheme_verification_queries[count][2]
    end

    local update_query, update_index, result
    for i = 1, count do
        update_query = self.scheme_verification_queries[i][1]
        update_index = self.scheme_verification_queries[i][2]
        result = conn:exec(update_query)
        if not result and i == 1 then
            logger_warn("XrayDataSaver.updateVersionIndex", "all queries need to be done")
            return 0
        elseif not result then
            logger_info("XrayDataSaver.updateVersionIndex", "queries need to be run from index " .. update_index - 1)
            return update_index - 1
        end
    end

    if do_debug then
        logger_info("VERSIE OK", version_index)
    end

    return version_index
end

function XrayDataSaver:setEmptyPropsToNil(values)
    for key, value in pairs(values) do
        if value == "" then
            values[key] = nil
        end
    end
end

return XrayDataSaver
