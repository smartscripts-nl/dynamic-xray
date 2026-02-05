
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
--local logger = require("logger")
local md5 = require("ffi/sha2").md5
local Math = require("optmath")

local DX = DX
local has_content = has_content
local has_items = has_items
local has_text = has_text
local pairs = pairs
local string = string
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

local count

--- @class SeriesManager
local SeriesManager = WidgetContainer:extend{
    name = "series",
    active_item_no = nil,
    all_series_resultset = nil,
    arg = nil,
    boxes = {},
    context_dialog = nil,
    is_non_series_item = false,
    items = {},
    path = nil,
    separator = " • ",
    separator_with_extra_spacing = "  •  ",
    series = {},
    series_context_dialog_index = "series_manager_for_current_book",
    serieslist = nil,
    series_annotations = nil,
    series_descriptions = nil,
    series_stars = nil,
    series_ratings = nil,
    series_table_indexed = {},
    series_resultsets = {},
}

function SeriesManager:searchSerieMembers(full_path)

    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:searchSerieMembers")
    KOR.databases:attachStatisticsDB(conn)
    local sql = [[
    WITH latest_progress AS (
        SELECT
            p.page || '/' || p.total_pages AS progress,
            b.title,
            b.series
        FROM statistics.page_stat_data p
        JOIN (
            SELECT id_book, MAX(start_time) AS max_time
            FROM statistics.page_stat_data
            GROUP BY id_book
        ) lp
          ON lp.id_book = p.id_book
         AND lp.max_time = p.start_time
         JOIN book b ON b.id = p.id_book
        WHERE p.total_pages IS NOT NULL
          AND p.total_pages != 0
    )

    SELECT
        i.directory || i.filename AS path,
        i.authors,
        i.series AS series_name,
        i.rating_goodreads,
        COALESCE(SUM(i.pages), 0) AS series_total_pages,
        GROUP_CONCAT(i.directory || i.filename, '%s') AS series_paths,
        GROUP_CONCAT(COALESCE(i.description, '-'), '%s') AS series_descriptions,
        GROUP_CONCAT(COALESCE(i.annotations, '-'), '%s') AS series_annotations,
        GROUP_CONCAT(COALESCE(i.rating_goodreads, '-'), '%s') AS series_ratings,
        GROUP_CONCAT(COALESCE(i.stars, '-'), '%s') AS series_stars,
        GROUP_CONCAT(COALESCE(i.title, '-'), '%s') AS series_titles,
        GROUP_CONCAT(COALESCE(f.path, '-'), '%s') AS finished_paths,
        GROUP_CONCAT(COALESCE(i.series_index, '-'), '%s') AS series_numbers,
        GROUP_CONCAT(COALESCE(i.pages, '-'), '%s') AS pages,
        GROUP_CONCAT(COALESCE(i.publication_year, '-'), '%s') AS publication_years,
        GROUP_CONCAT(COALESCE(lp.progress, '-'), '%s') AS series_percentages,
        COUNT(i.title) AS series_count
    FROM (%s) i
    LEFT OUTER JOIN finished_books f
        ON i.directory || i.filename = f.path
    LEFT OUTER JOIN latest_progress lp
        ON lp.title = i.title AND lp.series = i.series
    WHERE i.series IS NOT NULL AND i.series != ''
    GROUP BY i.authors, i.series
    ORDER BY i.authors, i.series;
    ]]
    -- AND i.series_index IS NOT NULL AND i.series_index != ''
    --! this subquery needed to order the group_concat items:
    local subquery = "SELECT * FROM bookinfo WHERE series IS NOT NULL AND series != ''"
    if full_path then
        local current_series_limitation = KOR.databases:injectSafePath(" AND series IN (SELECT series FROM bookinfo WHERE directory || filename = 'safe_path' LIMIT 1) ", full_path)
        subquery = subquery .. current_series_limitation
    end
    --* use this cast to sort naturally:
    subquery = subquery .. " ORDER BY CAST(series_index AS DECIMAL)"
    local s = self.separator
    sql = string.format(sql, s, s, s, s, s, s, s, s, s, s, s, subquery)
    --logger.warn("query", sql:gsub("\n", " "))
    local result = conn:exec(sql)
    KOR.databases:detachStatisticsDB(conn)
    conn = KOR.databases:closeInfoConnections(conn)
    if not full_path and not result then
        self:showNoSeriesFoundMessage()
        return
    end
    if full_path then
        KOR.registry:set("series_members", result)
    else
        KOR.registry:set("all_series", result)
    end
    return result
end

--- @private
function SeriesManager:getNonSeriesData(full_path)

    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:getNonSeriesData")
    local sql = [[
        SELECT
        i.authors,
        i.description,
        i.annotations,
        i.stars,
        i.rating_goodreads,
        i.title,
        i.publication_year,
        COALESCE(f.path, '-') AS finished_path
        FROM bookinfo i
        LEFT OUTER JOIN finished_books f
            ON i.directory || i.filename = f.path

        WHERE i.directory || i.filename = 'safe_path';
    ]]
    sql = KOR.databases:injectSafePath(sql, full_path)
    local result = conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    if not result then
        KOR.messages:notify(_("no data found for this ebook"))
        return
    end
    return result
end

--- @private
function SeriesManager:showNoSeriesFoundMessage()
    KOR.messages:notify(_("no series found on this e-reader"), 5)
end

--- @private
function SeriesManager:populateSeries(result)
    --* query to get resultset in ((SeriesManager#searchSerieMembers))
    local series_table = {}
    local series_name, show_title, series_count
    count = #result[1]
    for i = 1, count do
        series_name = result["series_name"][i]
        --* only add unique books:
        if not series_table[series_name] then
            series_count = tonumber(result["series_count"][i])
            show_title = result["authors"][i] .. ", " .. result["series_name"][i] .. " (" .. series_count .. ")"
            show_title = show_title .. "  –  " .. result["series_titles"][i]
            series_table[series_name] = {
                text = show_title,
                series_name = series_name,
                series_count = series_count,
                path = result["path"][i],
                index = i,
                authors = result["authors"][i],
                sort_index = result["authors"][i] .. " " .. show_title,
                series_paths = result["series_paths"][i],
                series_descriptions = result["series_descriptions"][i],
                series_annotations = result["series_annotations"][i],
                series_stars = result["series_stars"][i],
                series_ratings = result["series_ratings"][i],
                series_titles = result["series_titles"][i],
                finished_paths = result["finished_paths"][i],
                series_percentages = result["series_percentages"][i],
                series_numbers = result["series_numbers"][i],
                publication_years = result["publication_years"][i],
                pages = result["pages"][i],
                series_total_pages = result["series_total_pages"][i],
            }
        end
    end
    self.series = {}
    self.series_table_indexed = series_table
    for _, item in pairs(series_table) do
        table_insert(self.series, item)
    end
end

--- @private
function SeriesManager:closeDialog()
    UIManager:close(self.series_dialog)
end

function SeriesManager:getCacheIndex(full_path)
    return md5(full_path)
end

function SeriesManager:onShowSeriesList(full_path)

    local result = self:getCachedResultset(full_path)

    if full_path and not result then
        self:showNoSeriesFoundMessage()
        return true
    end

    if full_path and self:showContextDialogForCurrentEbook(result, full_path) then
        return true
    end

    self:populateSeries(result)
    count = #self.series
    if count == 0 then
        self:showNoSeriesFoundMessage()
        return
    end

    self.series_dialog = KOR.list:create({
        list_title = _("All series"),
        item_table = self:generateListMenuItems(),
        parent = self,
        menu_name = "all_series_menu",
        menu_manager = self,
    })
    UIManager:show(self.series_dialog)

    return true
end

--- @private
function SeriesManager:getCachedResultset(full_path)
    --* this var will be set in ((SeriesManager#searchSerieMembers)):
    local cached_result = full_path and KOR.registry:getOnce("series_members") or KOR.registry:get("all_series")

    local cache_index
    if full_path then
        cache_index = self:getCacheIndex(full_path)
    end
    local result
    if cached_result then
        result = cached_result

    elseif not cached_result and cache_index and not self.series_resultsets[cache_index] then
        result = self:searchSerieMembers(full_path)

    elseif cache_index and self.series_resultsets[cache_index] then
        return self.series_resultsets[cache_index]

    elseif self.all_series_resultset then
        return self.all_series_resultset

    --* for "normal", show all series case (no path and cache_index given):
    else
        result = self:searchSerieMembers()
    end

    self:_cache_resultset(cache_index, result)

    return result
end

--- @private
function SeriesManager:generateListMenuItems()
    local item_table = {}
    for nr = 1, count do
        local item = KOR.tables:shallowCopy(self.series[nr])
        item.text = KOR.strings:formatListItemNumber(nr, item.text)
        item.editable = true
        item.deletable = false
        item.callback = function()
            UIManager:close(self.series_dialog)
            self:showContextDialog(item, item.path)
        end
        table_insert(item_table, item)
    end
    return item_table
end

function SeriesManager:reloadContextDialog()
    if KOR.registry:get(self.series_context_dialog_index) then
        UIManager:close(self.context_dialog)
        self:showContextDialog(self.item, self.full_path)
    end
end

function SeriesManager:resetData()
    local cache_index = self:getCacheIndex(DX.m.current_ebook_full_path)
    self.all_series_resultset = nil
    self.items = {}
    self.series = {}
    self.serieslist = nil
    self.series_annotations = nil
    self.series_descriptions = nil
    self.series_stars = nil
    self.series_ratings = nil
    self.series_table_indexed = {}
    self.series_resultsets[cache_index] = nil
    KOR.registry:unset("series_members", "all_series")
end

function SeriesManager:showContextDialogForNonSeriesBook(full_path)
    local result = self:getNonSeriesData(full_path)
    if not result then
        return false
    end
    local percentage = "-"
    local current_page = KOR.ui:getCurrentPage()
    local pages = KOR.document:getPageCount()
    if current_page and pages and pages > 0 then
        --* this is the format expected by ((SeriesManager#getMetaInformation)):
        percentage = current_page .. "/" .. pages
    end
    local item = {
        authors = result["authors"][1],
        description = result["description"][1],
        finished_path = result["finished_path"][1],
        publication_year = result["publication_year"][1],
        pages = pages,
        percentage = percentage,
        annotations = result["annotations"][1],
        rating_goodreads = result["rating_goodreads"][1],
        path = full_path,
        title = result["title"][1],
    }
    self:showContextDialog(item, full_path, "is_non_series_item")
    return true
end

--* data for item were retrieved in ((SeriesManager#populateSeries)):
--- @private
function SeriesManager:showContextDialog(item, full_path, is_non_series_item)

    if not full_path and item.path then
        full_path = item.path
    end

    self.is_non_series_item = is_non_series_item
    self.item = item
    self.full_path = full_path

    KOR.registry:set(self.series_context_dialog_index, true)

    if self.is_non_series_item then
        self.items = {}
        local is_current_ebook = full_path == DX.m.current_ebook_full_path
        item.text = item.authors .. ": " .. item.title
        local bitem = self:generateSingleBoxItem(is_current_ebook, item)
        table_insert(self.items, bitem)
    else
        self:generateBoxItems(item)
    end
    local title = self:formatDialogTitle(item)
    self.context_dialog = KOR.dialogs:filesBox({
        title = title,
        key_events_module = self.series_context_dialog_index,
        items = self.items,
        non_series_box = self.is_non_series_item and self.items[1],
        top_buttons_left = {
            KOR.buttoninfopopup:forAllSeries({
                callback = function()
                    UIManager:close(self.context_dialog)
                    DX.c:onShowSeriesManager()
                end
            }),
            KOR.buttoninfopopup:forXraySettings({
                callback = function()
                    DX.s.showSettingsManager()
                end
            }),
        },
        after_close_callback = function()
            KOR.registry:unset(self.series_context_dialog_index)
        end,
    })
end

---  @private
function SeriesManager:generateBoxItems(item)
    local pages = KOR.strings:split(item.pages, self.separator)
    local publication_years = KOR.strings:split(item.publication_years, self.separator)
    local finished_paths = KOR.strings:split(item.finished_paths, self.separator)
    local series_paths = KOR.strings:split(item.series_paths, self.separator)
    local series_descriptions = KOR.strings:split(item.series_descriptions, self.separator)
    self.series_annotations = item.series_annotations and KOR.strings:split(item.series_annotations, self.separator)
    self.series_stars = item.series_stars and KOR.strings:split(item.series_stars, self.separator)
    self.series_ratings = item.series_ratings and KOR.strings:split(item.series_ratings, self.separator)
    local series_percentages = item.series_percentages and KOR.strings:split(item.series_percentages, self.separator)
    local series_numbers = item.series_numbers and KOR.strings:split(item.series_numbers, self.separator)
    local series_titles = KOR.strings:split(item.series_titles, self.separator)

    local total_buttons = #series_paths
    local is_current_ebook, data, title
    self.active_item_no = 0
    self.items = {}
    for i = 1, total_buttons do
        is_current_ebook = series_paths[i] == DX.s.current_ebook_full_path
        title = series_titles[i]
        if self:isValidEntry(publication_years[i]) then
            title = title .. " - " .. publication_years[i]
        end
        if self:isValidEntry(finished_paths[i]) then
            title = title .. " " .. KOR.icons.finished_bare
        end
        data = {
            finished_path = finished_paths[i],
            description = series_descriptions[i],
            pages = pages[i],
            annotations = self.series_annotations and self.series_annotations[i],
            stars = self.series_stars and self.series_stars[i],
            rating_goodreads = self.series_ratings and self.series_ratings[i],
            percentage = series_percentages and series_percentages[i],
            series_number = series_numbers and series_numbers[i] or i,
            path = series_paths[i],
            title = title,
        }
        self:generateBoxItem(i, is_current_ebook, data)
        if is_current_ebook then
            self.active_item_no = i
        end
    end
end

--- @private
function SeriesManager:formatDialogTitle(item)
    local series_total_pages = tonumber(item.series_total_pages) or 0
    local dialog_title = item.text:gsub("  –  .+$", "")
    if not self.is_non_series_item and self.active_item_no > 0 then
        dialog_title = dialog_title:gsub("%(", "(" .. self.active_item_no .. "/")
    end
    if self.series_ratings then
        dialog_title = dialog_title:gsub(KOR.icons.rating_bare .. "%d+,%d+", "")
    end
    if has_items(series_total_pages) then
        return KOR.strings:trim(dialog_title) .. " - " .. series_total_pages .. _("pp")
    end
    return dialog_title
end

--- @private
function SeriesManager:generateBoxItem(i, is_current_ebook, data)
    local series_number = self:getSeriesNumber(data, i)
    local meta_info, percentage_read = self:getMetaInformation(data)
    local generated_data = {
        path = data.path,
        title_info = self:formatEbookTitle(data.title, series_number),
        meta_info = meta_info,
        percentage_read = percentage_read,
        description = data.description,
        is_current_ebook = is_current_ebook,
    }
    table_insert(self.items, generated_data)
end

--* compare ((FilesBox#generateBoxes)) for regular series boxes:
--- @private
function SeriesManager:generateSingleBoxItem(is_current_ebook, item)
    local meta_info, percentage_read = self:getMetaInformation(item)
    local box_item = {
        title_info = self:formatEbookTitle(item.title),
        meta_info = meta_info,
        percentage_read = percentage_read,
        is_current_ebook = is_current_ebook,
        path = item.path,
    }
    return box_item
end

--- @private
function SeriesManager:getMetaInformation(data)
    local meta_items = {}

    local percentage
    local has_valid_percentage = self:isValidEntry(data.percentage)
    if not has_valid_percentage then
        if self:isValidEntry(data.pages) then
            table_insert(meta_items, data.pages .. "pp")
        else
            table_insert(meta_items, "?pp")
        end
    else
        local page, total_pages = data.percentage:match("^(%d+)/(%d+)")
        page = tonumber(page)
        total_pages = tonumber(total_pages)
        percentage = page / total_pages
        local display_percentage = Math.round(percentage * 100)
        table_insert(meta_items, KOR.icons.page_bare .. " " .. data.percentage .. " " .. display_percentage .. "%")
    end
    if self:isValidEntry(data.annotations) and tonumber(data.annotations) > 0 then
        table_insert(meta_items, KOR.icons.bookmark_bare .. data.annotations)
    end
    if self:isValidEntry(data.rating_goodreads) then
        table_insert(meta_items, KOR.icons.rating_bare .. data.rating_goodreads)
    end
    if self:isValidEntry(data.stars) and tonumber(data.stars) > 0 then
        table_insert(meta_items, KOR.icons.star_bare .. data.stars)
    end
    if has_items(meta_items) then
        return table_concat(meta_items, self.separator), percentage
    end

    return "", nil
end

--- @private
function SeriesManager:formatEbookTitle(title, series_number)
    --* reduce a title like "Destroyermen 05 - Storm Surge" to "Storm Surge":
    title = title:gsub("^.+%d %- ", "")
    --* reduce a title like "[Lux 03] Opal" to "Opal":
    title = title:gsub("^.+%d%] ", "")
    --* reduce a title like "Seventh Carier.title" to "title":
    title = title:gsub("^.+%. ?", "")
    --* series_number is not available for a non-series book:
    if series_number then
        title = series_number .. " " .. title
    end
    if title and title:len() > DX.s.SeriesManager_max_title_length then
        return title:sub(1, DX.s.SeriesManager_max_title_length - 3) .. "…"
    end
    return title
end

--- @private
function SeriesManager:getSeriesNumber(data, i)
    local series_number = data.series_number
    if data.series_number == "-" then
        return i .. "."
        --* don't add point to serie numbers like 4.5:
    elseif not data.series_number:match("%.") then
        return data.series_number .. "."
    end
    return series_number
end

--- @private
function SeriesManager:showContextDialogForCurrentEbook(result, full_path)
    if not full_path then
        full_path = DX.m.current_ebook_full_path
    end
    if not DX.m.current_series then
        return self:showContextDialogForNonSeriesBook(full_path)
    end
    if not result then
        result = self:searchSerieMembers(full_path)
    end
    if result and full_path then -- and #result[1] == 1
        self:populateSeries(result)
        local series_name = result["series_name"][1]
        if self.series_table_indexed[series_name] then
            self:showContextDialog(self.series_table_indexed[series_name], full_path)
            return true
        end
    end

    return false
end

--- @private
function SeriesManager:_cache_resultset(cache_index, resultset)
    --* query to get resultset in ((SeriesManager#searchSerieMembers))
    --* cache for individual file:
    if cache_index then
        self.series_resultsets[cache_index] = resultset
        --* cache for all files which are part of a series:
    else
        self.all_series_resultset = resultset
    end
end

function SeriesManager:getSeriesName(full_path)
    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:getSeriesName")
    local sql = KOR.databases:injectSafePath("SELECT series, series_index FROM bookinfo WHERE path = 'safe_path' LIMIT 1", full_path)
    local series, series_index = conn:rowexec(sql)
    conn = KOR.databases:closeInfoConnections(conn)

    return has_text(series), series_index
end

--- @private
function SeriesManager:isValidEntry(entry)
    return has_content(entry) and entry ~= "-"
end

function SeriesManager:showSeriesForEbookPath(full_path)
    if not full_path then
        full_path = DX.m.current_ebook_full_path
    end
    if not DX.m.current_series then
        KOR.seriesmanager:showContextDialogForNonSeriesBook(full_path)
        return
    end

    local series_members = self:searchSerieMembers(full_path)
    if series_members and full_path then
        self:closeDialog()
    end

    --* by adding param full_path, we make the manager display the series dialog for that particular file only:
    self:onShowSeriesList(full_path)
end

function SeriesManager:setBookFinishedStatus(full_path)
    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:setBookFinishedStatus")
    local sql = "INSERT OR IGNORE INTO finished_books (path) VALUES ('safe_path');"
    sql = KOR.databases:injectSafePath(sql, full_path)
    conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    self:resetData()
end

function SeriesManager:setAnnotationsCount(full_path, acount)
    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:setBookmarksCount")
    local sql = "UPDATE bookinfo SET annotations = ? WHERE directory || filename = 'safe_path';"
    sql = KOR.databases:injectSafePath(sql, full_path)
    local stmt = conn:prepare(sql)
    stmt:reset():bind(acount):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
    self:resetData()
end

function SeriesManager:setStars(full_path, num)
    if num == 0 then
        num = nil
    end
    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:setBookmarksCount")
    local sql = "UPDATE bookinfo SET stars = ? WHERE directory || filename = 'safe_path';"
    sql = KOR.databases:injectSafePath(sql, full_path)
    local stmt = conn:prepare(sql)
    stmt:reset():bind(num):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
    self:resetData()
end

return SeriesManager
