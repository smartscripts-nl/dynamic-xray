
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local md5 = require("ffi/sha2").md5

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
    path = nil,
    separator = " • ",
    separator_with_extra_spacing = "  •  ",
    series = {},
    series_context_dialog_index = "series_manager_for_current_book",
    series_ratings = nil,
    series_table_indexed = {},
    series_resultsets = {},
}

function SeriesManager:searchSerieMembers(full_path)

    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:searchSerieMembers")
    local sql = [[
        SELECT i.directory || i.filename AS path,
        i.authors,
        i.series AS series_name,
        COALESCE(SUM(i.pages), 0) AS series_total_pages,
        GROUP_CONCAT(i.directory || i.filename, '%s') AS series_paths,
        GROUP_CONCAT(COALESCE(i.rating_goodreads, '-'), '%s') AS series_ratings,
        GROUP_CONCAT(COALESCE(i.title, '-'), '%s') AS series_titles,
        GROUP_CONCAT(COALESCE(f.path, '-'), '%s')  AS finished_paths,
        GROUP_CONCAT(COALESCE(i.series_index, '-'), '%s') AS series_numbers,
        GROUP_CONCAT(COALESCE(i.pages, '-'), '%s') AS pages,
        GROUP_CONCAT(COALESCE(i.description, '-'), '%s') AS descriptions,
        GROUP_CONCAT(COALESCE(i.publication_year, '-'), '%s') AS publication_years,
        COUNT(i.title) AS series_count
        FROM (%s) i LEFT OUTER JOIN finished_books f ON i.directory || i.filename = f.path
        WHERE i.series IS NOT NULL AND i.series != ''
        GROUP BY i.authors, i.series
        ORDER BY i.authors, i.series
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
    sql = string.format(sql, s, s, s, s, s, s, s, s, subquery)
    local result = conn:exec(sql)
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
        SELECT authors,
        rating_goodreads,
        title,
        pages,
        publication_year
        FROM bookinfo
        WHERE directory || filename = 'safe_path';
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
                descriptions = result["descriptions"][i],
                series_paths = result["series_paths"][i],
                series_ratings = result["series_ratings"][i],
                series_titles = result["series_titles"][i],
                finished_paths = result["finished_paths"][i],
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

function SeriesManager:onShowSeriesDialog(full_path)
    self.path = full_path
    --* this var will be set in ((SeriesManager#searchSerieMembers)):
    local cached_result = full_path and KOR.registry:getOnce("series_members") or KOR.registry:get("all_series")
    KOR.dialogs:closeOverlay()

    local cache_index
    if full_path then
        cache_index = md5(full_path)
    end
    local result
    if cached_result then
        result = cached_result
        self:_cache_resultset(cache_index, result)

    elseif not cached_result and cache_index and not self.series_resultsets[cache_index] then
        result = self:searchSerieMembers(full_path)
        self:_cache_resultset(cache_index, result)

    elseif cache_index and self.series_resultsets[cache_index] then
        result = self.series_resultsets[cache_index]

    elseif self.all_series_resultset then
        result = self.all_series_resultset

    --* for "normal", show all series case (no path and cache_index given):
    else
        result = self:searchSerieMembers()
        self:_cache_resultset(cache_index, result)
    end

    KOR.dialogs:closeOverlay()
    if full_path and not result then
        self:showNoSeriesFoundMessage()
        return
    end

    if full_path and self:showContextDialogForCurrentEbook(result, full_path) then
        return
    end

    self:populateSeries(result)
    count = #self.series
    if count == 0 then
        self:showNoSeriesFoundMessage()
        return
    end
    self.item_table = {}
    for nr = 1, count do
        local current_nr = nr
        local item = {
            text = KOR.strings:formatListItemNumber(current_nr, self.series[nr].text),
            path = self.series[nr].path,
            editable = true,
            deletable = false,
            series_count = self.series[nr].series_count,
            series_name = self.series[nr].series_name,
            descriptions = self.series[nr].descriptions,
            pages = self.series[nr].pages,
            series_total_pages = self.series[nr].series_total_pages,
            series_paths = self.series[nr].series_paths,
            series_numbers = self.series[nr].series_numbers,
            series_titles = self.series[nr].series_titles,
            publication_years = self.series[nr].publication_years,
            finished_paths = self.series[nr].finished_paths,
        }
        item.callback = function()
            UIManager:close(self.series_dialog)
            KOR.dialogs:closeOverlay()
            self:showContextDialog(item, "return_to_series_list", self.series[nr].path)
        end
        table_insert(self.item_table, item)
    end
    self.series_dialog = KOR.list:create({
        list_title = _("All series"),
        parent = self,
        menu_name = "all_series_menu",
        menu_manager = self,
    })
    UIManager:show(self.series_dialog)
end

function SeriesManager:reloadContextDialog()
    if KOR.registry:get(self.series_context_dialog_index) then
        UIManager:close(self.context_dialog)
        self:showContextDialog(self.item, self.return_to_series_list, self.full_path)
    end
end

function SeriesManager:showContextDialogForNonSeriesBook(full_path)
    local result = self:getNonSeriesData(full_path)
    if not result then
        return
    end
    local item = {
        authors = result["authors"][1],
        publication_year = result["publication_year"][1],
        pages = result["pages"][1],
        rating_goodreads = result["rating_goodreads"][1],
        path = full_path,
        title = result["title"][1],
    }
    self:showContextDialog(item, false, full_path, "is_non_series_item")
end

--* data for item were retrieved in ((SeriesManager#populateSeries)):
--- @private
function SeriesManager:showContextDialog(item, return_to_series_list, full_path, is_non_series_item)

    if not full_path then
        full_path = DX.m.current_ebook_full_path
    end

    self.is_non_series_item = is_non_series_item
    self.item = item
    self.return_to_series_list = return_to_series_list
    self.full_path = full_path

    KOR.registry:set(self.series_context_dialog_index, true)
    KOR.dialogs:showOverlay()

    if self.is_non_series_item then
        self.boxes = {}
        local is_current_ebook = full_path == DX.m.current_ebook_full_path
        item.text = item.authors .. ": " .. item.title
        local box_item = self:generateSingleBoxItem(is_current_ebook, item)
        table_insert(self.boxes, box_item)
    else
        self:generateBoxItems(item, full_path)
    end
    local title = self:formatDialogTitle(item)
    self.context_dialog = KOR.dialogs:filesBox({
        title = title,
        key_events_module = self.series_context_dialog_index,
        items = self.boxes,
        non_series_box = self.is_non_series_item and self.boxes[1],
        top_buttons_left = {
            KOR.buttoninfopopup:forXraySettings({
                callback = function()
                    DX.s.showSettingsManager()
                end
            }),
            KOR.buttoninfopopup:forAllSeries({
                callback = function()
                    UIManager:close(self.context_dialog)
                    DX.c:onShowSeriesManager()
                end
            }),
        },
        after_close_callback = return_to_series_list and
        function()
            KOR.registry:unset(self.series_context_dialog_index)
            KOR.dialogs:closeOverlay()
            self:onShowSeriesDialog(self.path)
        end,
    })
end

---  @private
function SeriesManager:generateBoxItems(item, full_path)
    local descriptions = KOR.strings:split(item.descriptions, self.separator)
    local pages = KOR.strings:split(item.pages, self.separator)
    local publication_years = KOR.strings:split(item.publication_years, self.separator)
    local finished_paths = KOR.strings:split(item.finished_paths, self.separator)
    local series_paths = KOR.strings:split(item.series_paths, self.separator)
    self.series_ratings = item.series_ratings and KOR.strings:split(item.series_ratings, self.separator)
    local series_numbers = item.series_numbers and KOR.strings:split(item.series_numbers, self.separator)
    local series_titles = KOR.strings:split(item.series_titles, self.separator)

    local total_buttons = #series_paths
    local is_current_ebook
    self.active_item_no = 0
    self.boxes = {}
    for i = 1, total_buttons do
        is_current_ebook = full_path == series_paths[i]
        self:generateBoxItem(i, is_current_ebook, {
            description = descriptions[i],
            finished_path = finished_paths[i],
            pages = pages[i],
            publication_year = publication_years[i],
            rating_goodreads = self.series_ratings and self.series_ratings[i],
            series_number = series_numbers[i],
            path = series_paths[i],
            title = series_titles[i],
        })
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
function SeriesManager:generateBoxItem(i, is_current_ebook, d)
    local series_number = self:getSeriesNumber(d, i)
    table_insert(self.boxes, {
        path = d.path,
        title_info = self:formatEbookTitle(d.title, series_number),
        meta_info = self:getMetaInformation(d),
        description = d.description,
        is_current_ebook = is_current_ebook,
    })
end

--* compare ((FilesBox#generateBoxes)) for regular series boxes:
--- @private
function SeriesManager:generateSingleBoxItem(is_current_ebook, item)
    local box_item = {
        title_info = self:formatEbookTitle(item.title),
        meta_info = self:getMetaInformation(item),
        is_current_ebook = is_current_ebook,
        path = item.path,
    }
    return box_item
end

--- @private
function SeriesManager:getMetaInformation(d)
    local read_marker = " " .. KOR.icons.finished_bare
    local meta_items = {}

    if self:isValidEntry(d.publication_year) then
        table_insert(meta_items, d.publication_year)
    end
    if self:isValidEntry(d.finished_path) then
        table_insert(meta_items, read_marker)
    end
    if self:isValidEntry(d.pages) then
        table_insert(meta_items, d.pages .. "pp")
    else
        table_insert(meta_items, "?pp")
    end
    if self:isValidEntry(d.rating_goodreads) then
        table_insert(meta_items, KOR.icons.rating_bare .. d.rating_goodreads)
    end
    if has_items(meta_items) then
        return table_concat(meta_items, self.separator)
    end

    return ""
end

--- @private
function SeriesManager:formatEbookTitle(title, series_number)
    --* reduce a title like "Destroyermen 05 - Storm Surge" to "Storm Surge":
    title = title:gsub("^.+ %- ", "")
    --* reduce a title like "[Lux 03] Opal" to "Opal":
    title = title:gsub("^.+%] ", "")
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
function SeriesManager:getSeriesNumber(d, i)
    local series_number = d.series_number
    if d.series_number == "-" then
        return i .. "."
        --* don't add point to serie numbers like 4.5:
    elseif not d.series_number:match("%.") then
        return d.series_number .. "."
    end
    return series_number
end

--- @private
function SeriesManager:showContextDialogForCurrentEbook(result, full_path)
    if not full_path then
        full_path = DX.m.current_ebook_full_path
    end
    if not result then
        result = self:searchSerieMembers(full_path)
    end
    if result and full_path then -- and #result[1] == 1
        self:populateSeries(result)
        local series_name = result["series_name"][1]
        if self.series_table_indexed[series_name] then
            self:showContextDialog(self.series_table_indexed[series_name], false, full_path)
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
        KOR.dialogs:closeOverlay()
        self:closeDialog()
    end

    --* by adding param full_path, we make the manager display the series dialog for that particular file only:
    self:onShowSeriesDialog(full_path)
end

function SeriesManager:setBookFinishedStatus(full_path)
    local conn = KOR.databases:getDBconnForBookInfo("SeriesManager:setBookFinishedStatus")
    local sql = "INSERT OR IGNORE INTO finished_books (path) VALUES ('safe_path');"
    sql = KOR.databases:injectSafePath(sql, full_path)
    conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
end

return SeriesManager
