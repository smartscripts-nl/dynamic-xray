
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local json = require("json")
local T = require("ffi/util").template

local DX = DX
local has_text = has_text
local table = table
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
        --* querying series information, because this query will be used when DX is set in book display mode, but the individual books data can still contain series information:
        get_all_book_items = [[
            SELECT
                x.id,
                x.name,
                b.series,
                x.ebook,
                b.title,
                x.short_names,
                x.description,
                x.xray_type,
                x.aliases,
                x.tags,
                x.linkwords,
                x.book_hits,
                (
                    SELECT SUM(x2.book_hits)
                    FROM xray_items x2
                    JOIN bookinfo b2 ON b2.filename = x2.ebook
                    WHERE b2.series = b.series
                      AND x2.name = x.name
                ) AS series_hits,
                x.chapter_hits,
                x.chapter_hits_data,
                o.chapters,
                GROUP_CONCAT(b.series_index || '. ' || b.title, ', ' ORDER BY b.series_index) AS mentioned_in
            FROM xray_items x
                JOIN bookinfo b ON x.ebook = b.filename
                LEFT OUTER JOIN xray_books o ON x.ebook = o.ebook
            WHERE x.ebook = '%1'
            GROUP BY %2
            ORDER BY (x.xray_type = 2 or x.xray_type = 4) DESC, %3;]],

        --* s.ebook, s.title, s.book_hits and s.chapter_hits will be null when the xray item only is found in one or more OTHER books in the series, but not in the current ebook:
        get_all_series_items = [[
           WITH

           book_xray_data AS (
            SELECT
             x.id,
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
             b.title,
             o.chapters
            FROM xray_items x
            JOIN bookinfo b ON b.filename = x.ebook
            LEFT OUTER JOIN xray_books o ON b.filename = o.ebook
            WHERE x.ebook = 'safe_path'),

            series_data AS (
                SELECT
                x.name,
                b.series,
                SUM(x.book_hits) AS series_hits,
                GROUP_CONCAT(
                    b.series_index || '. ' || b.title || ' (' || COALESCE(x.book_hits, 0) || ')',
                    '|'
                    ORDER BY b.series_index
                ) AS mentioned_in
             FROM xray_items x
               JOIN bookinfo b ON b.filename = x.ebook
             WHERE b.series = '%1'
               AND x.name IS NOT NULL
               AND x.name != ''
             GROUP BY x.name, x.xray_type, b.series)

            SELECT
               x.id,
               x.name,
               x.aliases,
               x.tags,
               x.short_names,
               x.linkwords,
               x.description,
               x.xray_type,

               x.book_hits,
               x.chapters,
               x.chapter_hits,
               x.chapter_hits_data,
               x.ebook,
               x.title,

               s.series,
               s.series_hits,
               s.mentioned_in

            FROM series_data s
            LEFT JOIN book_xray_data x ON x.name = s.name

            ORDER BY (x.xray_type = 2 OR x.xray_type = 4) DESC, %2, x.name;]],

        get_series_name =
            "SELECT series FROM bookinfo WHERE directory || filename = 'safe_path' LIMIT 1;",

        get_items_for_import_from_other_series =
            "SELECT DISTINCT(x.name), x.short_names, x.description, x.xray_type, x.aliases, x.tags, x.linkwords FROM xray_items x LEFT OUTER JOIN bookinfo b ON x.ebook = b.filename WHERE b.series = 'safe_path' ORDER BY x.name;",

        get_series_hits = [[
            SELECT SUM(x.book_hits) AS series_hits
            FROM xray_items x
            JOIN bookinfo b ON b.filename = x.ebook
            WHERE x.name = '%1' AND b.series = '%2';]],
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
    local conn = KOR.databases:getDBconnForBookInfo(context)
    local result = conn:exec(self.queries_external[query_index])
    conn = KOR.databases:closeInfoConnections(conn)
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
    local group_by = parent.sorting_method == "hits" and "x.name, x.xray_type, x.book_hits" or "x.name, x.xray_type"
    sort = parent.sorting_method == "hits" and "x.book_hits DESC" or "x.name"

    return T(self.queries.get_all_book_items, current_ebook_basename, group_by, sort)
end

--- @private
function XrayDataLoader:_loadAllData(mode)
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataLoader:_loadAllData")
    local sql = self:_getAllDataSql(mode)
    local result = conn:exec(sql, nil, "XrayDataLoader:_loadAllData")
    if not result then
        conn = KOR.databases:closeInfoConnections(conn)
        return
    end

    self:_populateViewsDataBookChapters(result)

    parent.tags_relational = {}
    --* loop over 1 or multiple books (in series mode):
    if mode == "series" then
        self:_loadDataForSeries(result)
    else
        self:_loadDataForBook(result)
    end

    conn = KOR.databases:closeInfoConnections(conn)

    --* was only needed for transfer in DeveloperTools from LuaSettings file:
    --KOR.registry:set("all_xray_items", p.ebooks)

    local items = mode == "series" and parent.series[parent.current_series] or parent.ebooks[parent.current_ebook_basename] or {}
    views_data:setItems(items)
end

--- @private
function XrayDataLoader:_loadDataForBook(result)
    local book_index = result["ebook"][1]
    count = #result["name"]
    for i = 1, count do
        if has_text(result["tags"][i]) then
            parent:addTags(result["tags"][i])
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
            parent:addTags(result["tags"][i])
        end
        self:_addSeriesItem(result, i, series_index)
    end
    parent:sortAndSetTags()
end

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
        aliases = result["aliases"][i] or "",
        tags = result["tags"][i] or "",
        linkwords = result["linkwords"][i] or "",
        mentioned_in = result["ebook"][i],
        book_hits = tonumber(result["book_hits"][i]),
        series_hits = tonumber(result["series_hits"][i]),
        chapter_hits = result["chapter_hits"][i],
        chapter_hits_data = self:convertChapterHitsData(result["chapter_hits_data"][i]),
    }
    table.insert(parent.ebooks[book_index], item)

    parent:updateStaticReferenceCollections(id, item)
end

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
        aliases = result["aliases"][i] or "",
        tags = result["tags"][i] or "",
        linkwords = result["linkwords"][i] or "",
        series_hits = tonumber(result["series_hits"][i]) or 0,
        book_hits = tonumber(result["book_hits"][i]) or 0,
        chapter_hits = result["chapter_hits"][i],
        chapter_hits_data = self:convertChapterHitsData(result["chapter_hits_data"][i]),
        mentioned_in = result["mentioned_in"][i] or "",
    }
    parent:updateStaticReferenceCollections(id, item)

    -- #((set xray item props))
    table.insert(parent.series[series_index], item)
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

function XrayDataLoader:getItemsCountForBook(file_basename)
    --* to get the number of xray items only for the this book:
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataLoader:getItemsCountForBook")
    local sql = KOR.databases:injectSafePath(self.queries.get_book_items_count, file_basename)
    local xray_items_count = conn:rowexec(sql, nil, "XrayDataLoader:getItemsCountForBook")
    conn = KOR.databases:closeInfoConnections(conn)

    return xray_items_count
end

--! file_base_name can be an "external" book, when we call this method for creating an ebook abstract:
function XrayDataLoader:getItemsForEbook(file_basename)
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataLoader:getItemsForEbook")
    file_basename = KOR.databases:escape(file_basename)
    local sql = T(self.queries.get_items_for_ebook_abstract, file_basename)
    local result = conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    return result
end

function XrayDataLoader:getItemsForImportFromOtherSeries(conn, series)
    local sql = KOR.databases:injectSafePath(self.queries.get_items_for_import_from_other_series, series)
    return conn:exec(sql)
end

function XrayDataLoader:getSeriesHits(conn, series, name)
    return conn:rowexec(T(self.queries.get_series_hits, name, series)) or 0
end

function XrayDataLoader:getSeriesName()
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataLoader:getSeriesName")
    local sql = KOR.databases:injectSafePath(self.queries.get_series_name, parent.current_ebook_full_path)
    local series = conn:rowexec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    return series
end

return XrayDataLoader
