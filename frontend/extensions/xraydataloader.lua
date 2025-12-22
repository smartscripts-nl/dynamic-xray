--[[--
This extension is part of the Dynamic Xray plugin; its task is the loading of data for the Dynamic Xray module.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData)), ((XrayTranslations))
V = ((XrayUI)), ((XrayTranslations)), ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
linkwords,
book_hits, -- an integer
chapter_hits, -- a string, containing a html list of all hits in the chapters of an ebook
hits_determined -- an integer

series_hits is NOT a db field, it is computed dynamically by queries XrayDataLoader.queries.get_all_book_items and XrayDataLoader.queries.get_all_series_items
]]

--* compare ((XrayDataSaver)) for saving data:
--- @class XrayDataLoader
local XrayDataLoader = WidgetContainer:new{
    queries = {
        get_all_book_items =
            [[
            SELECT x.id,
                x.name,
                b.series,
                x.ebook,
                b.title,
                x.short_names,
                x.description,
                x.xray_type,
                x.aliases,
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
                x.hits_determined,
                GROUP_CONCAT(b.series_index || '. ' || b.title, ', ' ORDER BY b.series_index) AS mentioned_in
            FROM xray_items x JOIN bookinfo b ON x.ebook = b.filename
            WHERE x.ebook = '%1'
            GROUP BY %2
            ORDER BY (x.xray_type = 2 or x.xray_type = 4) DESC, %3;]],

        --* s.ebook, s.title, s.book_hits and s.chapter_hits will be null when the xray item only is found in one or more OTHER books in the series, but not in the current ebook:
        get_all_series_items = [[
        SELECT x.id,
           x.name,
           b.series,
           s.ebook,
           s.title,
           x.short_names,
           x.description,
           x.xray_type,
           x.aliases,
           x.linkwords,
           s.book_hits,
           s.chapter_hits,
           SUM(x.book_hits) AS series_hits,

           GROUP_CONCAT(b.series_index || '. ' || b.title || ' (' || COALESCE(x.book_hits, 0) || ')', '|' ORDER BY b.series_index) AS mentioned_in,
           x.hits_determined

        FROM bookinfo b
         LEFT JOIN xray_items x ON x.ebook = b.filename
         LEFT JOIN (SELECT x2.name, x2.book_hits, x2.chapter_hits, x2.ebook, b2.title
            FROM xray_items x2
            LEFT JOIN bookinfo b2 ON b2.filename = x2.ebook
            WHERE x2.ebook = 'safe_path'
            GROUP BY x2.name) s ON s.name = x.name

        WHERE b.series = '%1'
          AND x.name IS NOT NULL
          AND x.name != ''

        GROUP BY x.name, x.xray_type
        ORDER BY (x.xray_type = 2 or x.xray_type = 4) DESC, %2, x.ebook;
        ]],

        get_series_name =
            "SELECT series FROM bookinfo WHERE directory || filename = 'safe_path' LIMIT 1;",
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
        sort = parent.sorting_method == "hits" and "series_hits DESC" or "x.name"

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
        self:_addBookItem(result, i, book_index)
    end
end

--- @private
function XrayDataLoader:_loadDataForSeries(result)
    count = #result["name"]
    local series_index = result["series"][1]
    for i = 1, count do
        self:_addSeriesItem(result, i, series_index)
    end
end

--- @private
function XrayDataLoader:_addBookItem(result, i, book_index)

    if not parent.ebooks[book_index] then
        parent.ebooks[book_index] = {}
    end

    -- #((set xray item props))
    table.insert(parent.ebooks[book_index], {
        id = tonumber(result["id"][i]),
        series = result["series"][i],
        name = result["name"][i],
        short_names = result["short_names"][i] or "",
        description = result["description"][i] or "",
        xray_type = tonumber(result["xray_type"][i]) or 1,
        aliases = result["aliases"][i] or "",
        linkwords = result["linkwords"][i] or "",
        mentioned_in = result["ebook"][i],
        book_hits = tonumber(result["book_hits"][i]),
        series_hits = tonumber(result["series_hits"][i]),
        chapter_hits = result["chapter_hits"][i],
    })
end

--- @private
function XrayDataLoader:_addSeriesItem(result, i, series_index)
    local name = result["name"][i]
    --* unique key (i.e. name) per item in the series:
    local item = parent.series[series_index][name]
            or {
        id = tonumber(result["id"][i]),
        series = result["series"][i],
        name = result["name"][i],
        short_names = result["short_names"][i] or "",
        description = result["description"][i] or "",
        xray_type = tonumber(result["xray_type"][i]) or 1,
        aliases = result["aliases"][i] or "",
        linkwords = result["linkwords"][i] or "",
        series_hits = tonumber(result["series_hits"][i]) or 0,
        book_hits = tonumber(result["book_hits"][i]) or 0,
        chapter_hits = result["chapter_hits"][i],
        mentioned_in = result["mentioned_in"][i] or "",
        hits_determined = tonumber(result["hits_determined"][i]),
    }

    -- #((set xray item props))
    table.insert(parent.series[series_index], item)
end

function XrayDataLoader:getSeriesName()
    local conn = KOR.databases:getDBconnForBookInfo("XrayDataLoader:getSeriesName")
    local sql = KOR.databases:injectSafePath(self.queries.get_series_name, parent.current_ebook_full_path)
    local series = conn:rowexec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    return series
end

return XrayDataLoader
