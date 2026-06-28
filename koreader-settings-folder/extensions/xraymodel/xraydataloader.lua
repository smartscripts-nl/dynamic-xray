
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local json = require("json")
local T = require("ffi/util").template

local DX = DX
local has_text = has_text
local table_insert = table.insert
local tonumber = tonumber

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

series_hits is NOT a db field, it is computed dynamically by queries XrayDataLoader.queries.get_all_book_items and XrayDataLoader.queries.get_all_series_items
]]

--* compare ((XrayDataSaver)) for saving data:
--- @class XrayDataLoader
local XrayDataLoader = WidgetContainer:new{
    queries = {
        --* querying series information (b.series and b.series_index), because this query will be used when DX is set in book display mode, but the individual books data can still contain series information:
        get_all_book_items = [[
           SELECT DISTINCT x.id,
           x.name,
           b.series,
           b.series_index,
           x.ebook,
           b.title,
           x.short_names,
           x.description,
           x.xray_type,
           x.aliases,
           x.tags,
           x.linkwords,
           x.book_hits,
           -- since no series:
           x.book_hits AS series_hits,
           x.chapter_hits,
           x.chapter_hits_data,
           o.chapters,
           b.title AS mentioned_in,
           x.name AS item_name,
           x.non_breakable,
           q.pos_chapter_quotes

        FROM bookinfo b
        JOIN xray_items x
          ON x.ebook = b.filename

        LEFT JOIN (
            SELECT q.ebook,
                   q.item_name,
                   GROUP_CONCAT(
                       q.ebook || '||' ||
                       COALESCE(q.series_index, '???') || '||' ||
                       COALESCE(q.ebook_title, '???') || '||' ||
                       q.pos0 || '||' ||
                       COALESCE(q.chapter, '???') || '||' ||
                       q.quote,
                       '@@'
                       ORDER BY q.id
                   ) AS pos_chapter_quotes
            FROM xray_quotes q
            GROUP BY q.ebook, q.item_name
        ) q
          ON q.ebook = x.ebook
         AND q.item_name = x.name

        LEFT JOIN xray_books o
          ON x.ebook = o.ebook

        WHERE b.filename = '%1'
        ORDER BY %2;]],

        --* s.ebook, s.title, s.book_hits and s.chapter_hits will be null when the xray item only is found in one or more OTHER books in the series, but not in the current ebook:
        --* for prop pos_chapter_quotes compare ((XrayQuotes#generateQuotesList)):
        get_all_series_items = [[
        WITH book_xray_data AS (
        SELECT x.id,
           x.name,
           x.xray_type,
           x.aliases,
           x.tags,
           x.short_names,
           x.linkwords,
           x.description,
           x.ebook,
           x.book_hits,
           x.chapter_hits,
           x.chapter_hits_data,
           x.non_breakable,
           b.title,
           o.chapters
        FROM xray_items x
                 JOIN bookinfo b
                      ON b.filename = x.ebook
                 LEFT OUTER JOIN xray_books o
                      ON b.filename = o.ebook
        WHERE x.ebook = 'safe_path'
        ),

        series_data AS (
            SELECT x.name,
                   x.xray_type,
                   b.series,
                   SUM(x.book_hits) AS series_hits,

                   GROUP_CONCAT(
                           b.series_index || '. ' || b.title || ' (' || COALESCE(x.book_hits, 0) || ')',
                           '|'
                           ORDER BY b.series_index
                   ) AS mentioned_in

            FROM xray_items x
                     JOIN bookinfo b
                          ON b.filename = x.ebook

            WHERE b.series = '%1'
              AND x.name IS NOT NULL
              AND x.name != ''

            GROUP BY x.name,
                     x.xray_type,
                     b.series
        ),

        quote_data AS (
            SELECT q.series,
                   q.item_name,

                   GROUP_CONCAT(
                           q.ebook || '||' ||
                           COALESCE(q.series_index, '???') || '||' ||
                           COALESCE(q.ebook_title, '???') || '||' ||
                           q.pos0 || '||' ||
                           COALESCE(q.chapter, '???') || '||' ||
                           q.quote,
                           '@@'
                           ORDER BY q.id
                   ) AS pos_chapter_quotes

            FROM xray_quotes q

            GROUP BY q.series,
                     q.item_name
        )

        SELECT DISTINCT x.id,
           x.name,
           x.aliases,
           x.tags,
           x.short_names,
           x.linkwords,
           x.description,
           x.xray_type,
           x.non_breakable,

           x.book_hits,
           x.chapters,
           x.chapter_hits,
           x.chapter_hits_data,
           x.ebook,
           x.title,

           s.series,
           s.series_hits,
           s.mentioned_in,

           q.pos_chapter_quotes

            FROM book_xray_data x

             LEFT JOIN series_data s
                       ON s.name = x.name
                           AND s.xray_type = x.xray_type

             LEFT JOIN quote_data q
                       ON q.series = s.series
                           AND q.item_name = x.name

            ORDER BY (x.xray_type = 2 OR x.xray_type = 4) DESC,
             %2,
             x.name;]],
        --* %2 above = parent.sorting_method == "hits" and "s.series_hits DESC" or "s.name"

        get_book_glossary =
            "SELECT glossary FROM bookinfo WHERE directory || filename = 'safe_path';",

        --* this query is used via ((XrayDialogs#showMultipleBookSeriesActionResult)) > ((XrayDataLoader#getCurrentBookItemsOnly)):
        get_current_book_only_items = [[
            WITH unique_series_names AS (SELECT b.series, x.name
                 FROM xray_items x
                      JOIN bookinfo b
                           ON b.filename = x.ebook
                 WHERE x.name IS NOT NULL
                 GROUP BY b.series, x.name
                 HAVING COUNT(DISTINCT x.ebook) = 1)

            SELECT DISTINCT i.id,
                   i.name,
                   i.book_hits,
                   i.description,
                   i.xray_type,
                   b.series

            FROM xray_items i
                 JOIN bookinfo b
                      ON b.filename = i.ebook

                 JOIN unique_series_names u
                      ON u.series = b.series
                          AND u.name = i.name

            WHERE i.ebook = '%1'
            ORDER BY i.book_hits DESC;]],

        --* this query is used via ((XrayDialogs#showMultipleBookSeriesActionResult)) > ((XrayDataLoader#getInAllSeriesBooksItems)):
        get_in_all_series_books_items = [[
            WITH series_books AS (
                SELECT COUNT(DISTINCT filename) AS total_books
                FROM bookinfo
                WHERE series = '%1'
            ),

            series_item_counts AS (
                SELECT x.name,
                       COUNT(DISTINCT x.ebook) AS item_book_count
                FROM xray_items x
                         JOIN bookinfo b
                              ON b.filename = x.ebook
                WHERE b.series = '%2'
                  AND x.name IS NOT NULL
                  AND x.name != ''
                GROUP BY x.name
            )

            SELECT DISTINCT i.id,
                   i.name,
                   i.book_hits,
                   i.description,
                   i.xray_type,
                   b.series

            FROM xray_items i
                 JOIN bookinfo b
                      ON b.filename = i.ebook

                 JOIN series_item_counts sic
                      ON sic.name = i.name

                 CROSS JOIN series_books sb

            WHERE i.ebook = '%3' AND i.book_hits > 0
              AND b.series = '%4'
              AND sic.item_book_count = sb.total_books

            ORDER BY i.book_hits DESC;]],

        get_item_id =
            "SELECT rowid FROM xray_items WHERE name = 'safe_path';",

        get_items_for_import_from_series = [[
            WITH series_books AS (
              SELECT filename
              FROM bookinfo
              WHERE series = 'current_series'
            )

            SELECT DISTINCT x.name,
                x.short_names,
                x.description,
                x.xray_type,
                x.aliases,
                x.tags,
                x.linkwords,
                x.non_breakable
            FROM xray_items x
            JOIN series_books s ON s.filename = x.ebook
            WHERE x.ebook != 'safe_path'
            ORDER BY x.name;]],

        --* this query is used via ((XrayDialogs#showMultipleBookSeriesActionResult)) > ((XrayDataLoader#getNonCurrentBookItemsOnly)):
        --* item props will be populated in ((XrayDataLoader#addExternalBooksItem)):
        get_non_current_book_only_items = [[
            SELECT i.name,
                i.id,
                i.short_names,
                b.series,
                b.series_index,
                b.title AS book_title,
                b.directory || b.filename AS path,
                i.book_hits,
                SUM(i.book_hits) AS series_hits,
                i.description,
                i.xray_type,
                i.non_breakable,
                i.aliases,
                i.tags,
                i.linkwords,
               GROUP_CONCAT(
                       b.series_index || '. ' || b.title || ' (' || COALESCE(i.book_hits, 0) || ')',
                       '|'
                       ORDER BY b.series_index
               ) AS mentioned_in

            FROM xray_items i
                 JOIN bookinfo b
                      ON b.filename = i.ebook

            WHERE b.series = '%1'
              AND i.ebook != '%2'
              AND NOT EXISTS (SELECT 1
                  FROM xray_items r
                  WHERE r.ebook = '%3'
                    AND r.name = i.name)
            GROUP BY i.name
            ORDER BY a.series_index, series_hits DESC]],

        qet_quotes_for_item_book = [[
            SELECT id, quote FROM xray_quotes
            WHERE item_name = '%1' AND ebook = '%2' ORDER BY id;]],

        --* compare ((XrayQuotes#generateQuotesList))
        qet_quotes_for_item_series = [[
            SELECT x.id, x.quote FROM xray_quotes x
            LEFT OUTER JOIN bookinfo b ON b.filename = x.ebook
            WHERE x.item_name = '%1' AND b.series = '%2' ORDER BY x.id;]],

        get_series_name =
            "SELECT series FROM bookinfo WHERE directory || filename = 'safe_path' LIMIT 1;",

        get_series_hits = [[
            SELECT SUM(x.book_hits) AS series_hits
            FROM xray_items x
            JOIN bookinfo b ON b.filename = x.ebook
            WHERE x.name = '%1' AND b.series = '%2';]],

        --* this query is used via ((XrayDialogs#showMultipleBookSeriesActionResult)) > ((XrayDataLoader#getTopBookItems)):
        get_top_book_items = [[
            SELECT id, name, book_hits, description, xray_type
            FROM xray_items
            WHERE ebook = '%1'
            ORDER BY book_hits DESC LIMIT %2;]],

        --* this query is used via ((XrayDialogs#showMultipleBookSeriesActionResult)) > ((XrayDataLoader#getUniqueItemsPerSeriesBook)):
        get_unique_items_per_series_book = [[
            WITH item_books AS (SELECT i.name,
                 COUNT(DISTINCT b.filename) AS book_count
            FROM xray_items i
                 JOIN bookinfo b ON b.filename = i.ebook
                    WHERE b.series = '%1'
            GROUP BY i.name)
            SELECT b.series,
                b.series_index,
                b.title AS book_title,
                b.directory || b.filename AS path,
                i.name,
                i.id,
                i.short_names,
                i.book_hits,
                i.book_hits AS series_hits,
                i.description,
                i.xray_type,
                i.non_breakable,
                i.aliases,
                i.tags,
                i.linkwords,
                b.series_index || '. ' || b.title || ' (' || COALESCE(i.book_hits, 0) || ')' AS mentioned_in
            FROM xray_items i
                 JOIN bookinfo b
                      ON b.filename = i.ebook
                 JOIN item_books ib
                      ON ib.name = i.name
            WHERE b.series = '%2' and ib.book_count = 1
            ORDER BY b.series_index, i.book_hits DESC, i.name;]],
    },
    queries_external = {
        --* used in ((XrayTranslations#loadAllTranslations)):
        get_all_translations =
            "SELECT CASE WHEN msgid != msgstr THEN 1 ELSE 0 END AS is_translated, msgid, msgstr, md5 FROM xray_translations ORDER BY msgid;",
    },
}

--- @param xray_model XrayModel
function XrayDataLoader:initDataHandlers(xray_model)
    parent = xray_model
    views_data = DX.vd
end

function XrayDataLoader:execExternalQuery(context, query_index)
    local conn = KOR.databases:getDBconn(context)
    local result = conn:exec(self.queries_external[query_index])
    conn = KOR.databases:closeConnections(conn)
    return result
end

--* current_ebook_basename always given, but current_series only set when book is part of a series; this series name will be stored in table field xray_items.ebook:
--- @param mode string "series" or "book"
function XrayDataLoader:loadAllItems(mode, force_refresh)
    --! don't reset p.ebooks and p.series, so we can remember and use previously retrieved data:
    --* p.series and p.ebooks contain only the items, which are not sub didided for tabs:
    if not force_refresh then
        if mode == "book" and parent.current_ebook_basename and parent.ebooks[parent.current_ebook_basename] then
            views_data.items = parent.ebooks[parent.current_ebook_basename]
            --* we don't want to call _loadAllData in this case:
            return
        end

        if has_text(parent.current_series) and parent.series[parent.current_series] then
            views_data.items = parent.series[parent.current_series]
            --* we don't want to call _loadAllData in this case:
            return
        end
    end

    self:_loadAllData(mode)
    local items = mode == "series" and parent.series[parent.current_series] or parent.ebooks[parent.current_ebook_basename] or {}
    parent:updateLastNameCounts(items)

    views_data:setItems(items, "from_resultset", "XrayDataLoader:_loadAllData")
end

function XrayDataLoader:loadGlossary(full_path)
    local sql = KOR.databases:injectSafePath(self.queries.get_book_glossary, full_path)
    local conn = KOR.databases:getDBconn("XrayDataLoader:loadGlossary")
    local glossary = conn:rowexec(sql)
    conn = KOR.databases:closeConnections(conn)
    return glossary
end

--- @private
function XrayDataLoader:_getAllDataSql(mode)
    local sort
    if mode == "series" then
        local current_series = KOR.databases:escape(parent.current_series)
        sort = parent.sorting_method == "hits" and "s.series_hits DESC" or "s.name"

        return T(KOR.databases:injectSafePath(self.queries.get_all_series_items, parent.current_ebook_basename), current_series, sort)
    end

    --* for book mode:

    local current_ebook_basename = KOR.databases:escape(parent.current_ebook_basename)
    sort = parent.sorting_method == "hits" and "(x.xray_type = 2 OR x.xray_type = 4) DESC, x.book_hits DESC, x.name" or "(x.xray_type = 2 OR x.xray_type = 4) DESC, x.name"

    return T(self.queries.get_all_book_items, current_ebook_basename, sort)
end

--- @private
function XrayDataLoader:_loadAllData(mode)
    local conn = KOR.databases:getDBconn("XrayDataLoader:_loadAllData")
    local sql = self:_getAllDataSql(mode)
    local result = conn:exec(sql, nil, "XrayDataLoader:_loadAllData")
    conn = KOR.databases:closeConnections(conn)
    if not result then
        return
    end
    --* might be set to true in ((XrayDataLoader#_loadDataForSeries)):
    parent.has_multiple_series_items = false

    self:_populateViewsDataBookChapters(result)

    parent.tags_associative = {}
    --* loop over 1 or multiple books (in series mode):
    if mode == "series" then
        self:_loadDataForSeries(result)
    else
        self:_loadDataForBook(result)
    end

    --* was only needed for transfer in DeveloperTools from LuaSettings file:
    --KOR.registry:set("all_xray_items", p.ebooks)

    local items = mode == "series" and parent.series[parent.current_series] or parent.ebooks[parent.current_ebook_basename] or {}
    views_data:setItems(items, "from_resultset", "XrayDataLoader:_loadAllData")
end

--- @private
function XrayDataLoader:_loadDataForBook(result)
    local book_index = result["ebook"][1]
    count = #result["name"]
    for i = 1, count do
        if has_text(result["tags"][i]) then
            parent:addTags(result["tags"][i], tonumber(result["id"][i]))
        end
        self:_addBookItem(result, i, book_index)
    end
    parent:sortAndSetTags()
end

--- @private
function XrayDataLoader:_populateViewsDataBookChapters(result)
    local chapters
    if not result["chapters"][1] then
        chapters = KOR.toc:getTocTitles(parent.current_ebook_full_path)
        DX.ds.storeChapters(chapters)
    else
        chapters = json.decode(result["chapters"][1])
    end
    views_data:setProp("book_chapters", chapters)
end

--- @private
function XrayDataLoader:_loadDataForSeries(result)
    count = #result["name"]
    local series_index = result["series"][1]
    for i = 1, count do
        if has_text(result["tags"][i]) then
            parent:addTags(result["tags"][i], tonumber(result["id"][i]))
            if not parent.has_multiple_series_items then
                parent.has_multiple_series_items = KOR.strings:substrCount(result["mentioned_in"][i], "|") > 1
            end
        end
        self:_addSeriesItem(result, i, series_index)
    end
    parent:sortAndSetTags()
end

--* populate item props; compare ((XrayDataLoader#_addSeriesItem)):
--- @private
function XrayDataLoader:_addBookItem(result, i, book_index)

    if not parent.ebooks[book_index] then
        parent.ebooks[book_index] = {}
    end

    -- #((set xray item props))
    local id = tonumber(result["id"][i])
    local item = {
        id = id,
        series = result["series"][i],
        name = result["name"][i],
        short_names = result["short_names"][i] or "",
        description = result["description"][i] or "",
        xray_type = tonumber(result["xray_type"][i]) or 1,
        non_breakable = tonumber(result["non_breakable"][i]) or 0,
        aliases = result["aliases"][i] or "",
        tags = result["tags"][i] or "",
        linkwords = result["linkwords"][i] or "",
        mentioned_in = result["ebook"][i],
        book_hits = tonumber(result["book_hits"][i]),
        series_hits = tonumber(result["series_hits"][i]),
        chapter_hits = result["chapter_hits"][i],
        chapter_hits_data = self:convertChapterHitsData(result["chapter_hits_data"][i]),
        pos_chapter_quotes = result["pos_chapter_quotes"][i],
    }
    self:addMatchingProps(item)
    table_insert(parent.ebooks[book_index], item)

    parent:updateStaticReferenceCollections(id, item)
end

--* populate item props; compare ((XrayDataLoader#_addBookItem)):
--- @private
function XrayDataLoader:_addSeriesItem(result, i, series_index)
    local id = tonumber(result["id"][i])
    local item = {
        id = id,
        series = result["series"][i],
        name = result["name"][i],
        short_names = result["short_names"][i] or "",
        description = result["description"][i] or "",
        xray_type = tonumber(result["xray_type"][i]) or 1,
        non_breakable = tonumber(result["non_breakable"][i]) or 0,
        aliases = result["aliases"][i] or "",
        tags = result["tags"][i] or "",
        linkwords = result["linkwords"][i] or "",
        mentioned_in = result["mentioned_in"][i] or "",
        series_hits = tonumber(result["series_hits"][i]) or 0,
        book_hits = tonumber(result["book_hits"][i]) or 0,
        chapter_hits = result["chapter_hits"][i],
        chapter_hits_data = self:convertChapterHitsData(result["chapter_hits_data"][i]),
        pos_chapter_quotes = result["pos_chapter_quotes"][i],
    }
    self:addMatchingProps(item)
    --logger.warn(item)
    parent:updateStaticReferenceCollections(id, item)

    -- #((set xray item props))
    table_insert(parent.series[series_index], item)
end

--* called from ((XrayDataLoader#_addBookItem)) and ((XrayDataLoader#_addSeriesItem)) upon plugin initialisation; called from ((XrayFormsData#saveNewItem)) and ((XrayFormsData#saveUpdatedItem)) upon adding/updating items:
--- @private
function XrayDataLoader:addMatchingProps(item)
    item.is_person = parent:isPerson(item)
    local full_name = KOR.strings:getNameSwapped(item.name)
    if item.is_person and item.non_breakable ~= 1 then
        item.family_name = full_name:match(" ([^ ]+)$")
    end
    item.is_term = not item.is_person
    item.is_lowercase = not item.name:match("[A-Z]")
    self:addMatchingPropsForName(item, full_name)
    self:addMatchingPropsForAliasesAndShortNames(item)
    item.needles_count = #item.needles
end

--- @private
function XrayDataLoader:addMatchingPropsForName(item, full_name)
    item.needles = parent:getNameParts(item)
    item.needles_for_ui = parent:getNamePartsUI(item)
    if item.is_term and item.is_lowercase then

        table_insert(item.needles, 3, views_data:getNeedleString(KOR.strings:ucfirst(full_name)))

        table_insert(item.needles_for_ui, 3, {
            needle = views_data:getNeedleString(KOR.strings:ucfirst(full_name)),
            reliability_indicator = DX.i.match_reliability_indicators.full_name,
            explanation = KOR.icons.arrow .. DX.i.match_reliability_indicators.full_name
        })
    end
end

--- @private
function XrayDataLoader:addMatchingPropsForAliasesAndShortNames(item)
    local props = { "aliases", "short_names" }
    local parts, parts_count, needle
    for i = 1, 2 do
        if item[props[i]] then
            parts = item[props[i]]:match(",") and KOR.strings:split(item[props[i]], ", *") or KOR.strings:split(item[props[i]], " +")
            parts_count = #parts
            for p = 1, parts_count do
                needle = DX.vd:getNeedleString(parts[p])
                table_insert(item.needles, needle)
                table_insert(item.needles_for_ui, {
                    needle = needle,
                    reliability_indicator = DX.i.match_reliability_indicators.alias,
                    explanation = KOR.icons.arrow .. DX.i.match_reliability_indicators.alias
                })
            end
        end
    end
end

function XrayDataLoader:addExternalBooksItem(result, i)

    local id = result["id"][i]
    return {
        id = id,
        series = result["series"][i],
        name = result["name"][i],
        short_names = result["short_names"][i] or "",
        description = result["description"][i] or "",
        xray_type = result["xray_type"][i] or 1,
        non_breakable = result["non_breakable"][i] or 0,
        aliases = result["aliases"][i] or "",
        tags = result["tags"][i] or "",
        linkwords = result["linkwords"][i] or "",
        mentioned_in = result["mentioned_in"][i],
        book_hits = 0,
        series_hits = result["series_hits"][i] or 1,
        --* we don't use chapter_hits, chapter_hits_data and post_chapter_quotes here, because when there are multiple external books, we can't determine which dataset to use for that...
        pos_chapter_quotes = "",
    }
end

--* compare ((XrayDataSaver#getChapterHitsDataForStorage)), where these data are prepared for storage:
--- @private
function XrayDataLoader:convertChapterHitsData(chapter_hits)
    if not chapter_hits then
        --* don't return an empty table here, because of check for empty chapter_hits_data at start of ((XrayPageNavigator#computeHistogramData)):
        return
    end
    local hits = KOR.strings:split(chapter_hits, ",")
    return KOR.tables:makeItemsNumerical(hits)
end

--* this method is called via ((XrayDialogs#showMultipleBookSeriesActionsOverview)) > ((XrayDialogs#showMultipleBookSeriesActionResult)):
function XrayDataLoader:getCurrentBookItemsOnly()
    local conn = KOR.databases:getDBconn("XrayDataLoader:getCurrentBookItemsOnly")
    local file_basename = KOR.databases:escape(parent.current_ebook_basename)
    local sql = T(self.queries.get_current_book_only_items, file_basename)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

--* this method is called via ((XrayDialogs#showMultipleBookSeriesActionsOverview)) > ((XrayDialogs#showMultipleBookSeriesActionResult)):
function XrayDataLoader:getInAllSeriesBooksItems()
    local conn = KOR.databases:getDBconn("XrayDataLoader:getInAllSeriesBooksItems")
    local file_basename = KOR.databases:escape(parent.current_ebook_basename)
    local series_name = KOR.databases:escape(parent.current_series)
    local sql = T(self.queries.get_in_all_series_books_items, series_name, series_name, file_basename, series_name)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

function XrayDataLoader.getItemId(conn, name)
    local self = DX.dl
    local sql = KOR.databases:injectSafePath(self.queries.get_item_id, name)
    return conn:rowexec(sql)
end

function XrayDataLoader:getItemsCountForBook(file_basename)
    --* to get the number of xray items only for the this book:
    local conn = KOR.databases:getDBconn("XrayDataLoader:getItemsCountForBook")
    local sql = KOR.databases:injectSafePath(self.queries.get_book_items_count, file_basename)
    local xray_items_count = conn:rowexec(sql, nil, "XrayDataLoader:getItemsCountForBook")
    conn = KOR.databases:closeConnections(conn)

    return xray_items_count
end

--! file_base_name can be an "external" book, when we call this method for creating an ebook abstract:
function XrayDataLoader:getItemsForEbook(file_basename)
    local conn = KOR.databases:getDBconn("XrayDataLoader:getItemsForEbook")
    file_basename = KOR.databases:escape(file_basename)
    local sql = T(self.queries.get_items_for_ebook_abstract, file_basename)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

function XrayDataLoader:getItemsForImportFromSeries(conn, series)

    local sql = self.queries.get_items_for_import_from_series

    series = KOR.databases:escape(series)
    sql = sql:gsub("current_series", series)

    sql = KOR.databases:injectSafePath(sql, parent.current_ebook_basename)

    return conn:exec(sql)
end

--* this method is called via ((XrayDialogs#showMultipleBookSeriesActionsOverview)) > ((XrayDialogs#showMultipleBookSeriesActionResult)):
function XrayDataLoader:getNonCurrentBookItemsOnly()
    local conn = KOR.databases:getDBconn("XrayDataLoader:getNonCurrentBookItemsOnly")
    local file_basename = KOR.databases:escape(parent.current_ebook_basename)
    local series_name = KOR.databases:escape(parent.current_series)
    local sql = T(self.queries.get_non_current_book_only_items, series_name, file_basename, file_basename)
    --KOR.registry:set("latest-stmt", sql)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

--* this method is called via ((XrayDialogs#showMultipleBookSeriesActionsOverview)) > ((XrayDialogs#showMultipleBookSeriesActionResult)):
function XrayDataLoader:getTopBookItems(limit)
    local conn = KOR.databases:getDBconn("XrayDataLoader:getTopBookItems")
    local file_basename = KOR.databases:escape(parent.current_ebook_basename)
    local sql = limit == 0 and T(self.queries.get_top_book_items, file_basename) or T(self.queries.get_top_book_items, file_basename, limit)
    sql = sql:gsub(" LIMIT %%2", "", 1)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

--* this method is called via ((XrayDialogs#showMultipleBookSeriesActionsOverview)) > ((XrayDialogs#showMultipleBookSeriesActionResult)):
function XrayDataLoader:getUniqueItemsPerSeriesBook()
    local conn = KOR.databases:getDBconn("XrayDataLoader:getUniqueItemsPerSeriesBook")
    local series_name = KOR.databases:escape(parent.current_series)
    local sql = T(self.queries.get_unique_items_per_series_book, series_name, series_name)
    --KOR.registry:set("latest-stmt", sql)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    return result
end

function XrayDataLoader.getQuotesForItemByName(name)
    local self = DX.dl
    local conn = KOR.databases:getDBconn("XrayDataLoader:getQuotesForItemById")
    local sql = parent.list_display_mode == "series" and self.queries.qet_quotes_for_item_series or self.queries.qet_quotes_for_item_book
    name = KOR.databases:escape(name)
    local second_arg = parent.list_display_mode == "series" and parent.current_series or parent.current_ebook_basename
    second_arg = KOR.databases:escape(second_arg)
    sql = T(sql, name, second_arg)
    local result = conn:exec(sql)
    conn = KOR.databases:closeConnections(conn)
    if not result then
        return
    end
    count = #result["quote"]
    local quotes = {}
    for i = 1, count do
        table_insert(quotes, {
            item_no = i,
            id = result["id"][i],
            value = result["quote"][i],
        })
    end
    return quotes
end

function XrayDataLoader:getSeriesHits(conn, series, name)
    return conn:rowexec(T(self.queries.get_series_hits, name, series)) or 0
end

return XrayDataLoader
