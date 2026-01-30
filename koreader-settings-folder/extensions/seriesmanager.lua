
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
local last_file = last_file
local pairs = pairs
local string = string
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

local count

--- @class SeriesManager
local SeriesManager = WidgetContainer:extend{
    name = "series",
    all_series_resultset = nil,
    arg = nil,
    context_dialog = nil,
    path = nil,
    separator = " • ",
    separator_with_extra_spacing = "  •  ",
    series = {},
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
        GROUP_CONCAT(i.title, '%s') AS series_titles,
        GROUP_CONCAT(COALESCE(f.path, '-'), '%s')  AS finished_paths,
        GROUP_CONCAT(COALESCE(i.series_index, '?'), '%s') AS series_numbers,
        GROUP_CONCAT(COALESCE(i.pages, '?'), '%s') AS pages,
        GROUP_CONCAT(COALESCE(i.description, '?'), '%s') AS descriptions,
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
    sql = string.format(sql, self.separator, self.separator, self.separator, self.separator, self.separator, self.separator, subquery)
    local result = conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)
    if not full_path and not result then
        self:showNoSeriesFoundMessage()
        return
    end
    KOR.registry:set("series_members", result)
    return result
end

function SeriesManager:showNoSeriesFoundMessage()
    KOR.messages:notify(_("no series found on this e-reader"), 5)
end

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
                series_titles = result["series_titles"][i],
                finished_paths = result["finished_paths"][i],
                series_numbers = result["series_numbers"][i],
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

function SeriesManager:closeDialog()
    UIManager:close(self.series_dialog)
end

--* arg path will more often than not be nil here:
function SeriesManager:onShowSeriesDialog(full_path, arg)
    self.path = full_path
    --* this var will be set in ((SeriesManager#searchSerieMembers)):
    local cached_result = KOR.registry:getOnce("series_members")
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
    if not result then
        self:showNoSeriesFoundMessage()
        return
    end

    if self:showContextDialogForCurrentEbook(result, full_path) then
        return
    end

    self.arg = arg
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
            finished_paths = self.series[nr].finished_paths,
        }
        item.callback = function()
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

--* data for item were retrieved in ((SeriesManager#populateSeries)):
function SeriesManager:showContextDialog(item, return_to_series_list, full_path)
    if not full_path then
        full_path = last_file()
    end
    KOR.dialogs:showOverlay()

    local descriptions = KOR.strings:split(item.descriptions, self.separator)
    local pages = KOR.strings:split(item.pages, self.separator)
    local series_total_pages = tonumber(item.series_total_pages)
    local finished_paths = KOR.strings:split(item.finished_paths, self.separator)
    local series_paths = KOR.strings:split(item.series_paths, self.separator)
    local series_numbers = item.series_numbers and KOR.strings:split(item.series_numbers, self.separator)
    local series_titles = KOR.strings:split(item.series_titles, self.separator)

    local total_buttons = #series_paths
    local read_marker = " " .. KOR.icons.finished_bare
    local is_current_ebook, meta, series_number, title, description, meta_items
    local active_item_no = 0
    local boxes = {}
    for i = 1, total_buttons do
        meta_items = {}
        is_current_ebook = full_path == series_paths[i]

        if is_current_ebook then
            active_item_no = i
        end
        if has_content(finished_paths[i]) and finished_paths[i] ~= "-" then
            table_insert(meta_items, read_marker)
        end
        if has_content(pages[i]) then
            table_insert(meta_items, pages[i] .. "pp")
        end
        meta = ""
        if has_items(meta_items) then
            meta = table_concat(meta_items, self.separator)
        end
        series_number = series_numbers and series_numbers[i] or i
        description = descriptions[i]
        --* don't add point to serie numbers like 4.5:
        if series_number == "?" then
            series_number = i .. "."
        elseif not series_number:match("%.") then
            series_number = series_number .. "."
        end
        --* reduce a title like "Destroyermen 05 - Storm Surge" to "Storm Surge":
        series_titles[i] = series_titles[i]:gsub("^.+ %- ", "")
        --* reduce a title like "[Lux 03] Opal" to "Opal":
        series_titles[i] = series_titles[i]:gsub("^.+%] ", "")
        --* reduce a title like "Seventh Carier.title" to "title":
        series_titles[i] = series_titles[i]:gsub("^.+%. ?", "")
        --table_insert(buttons[#buttons], {
        table_insert(boxes, {
            path = series_paths[i],
            info = series_number .. " " .. series_titles[i],
            description = description,
            meta_info = meta,
            font_bold = is_current_ebook,
            is_current_ebook = is_current_ebook,
        })
    end
    title = item.text:gsub("  –  .+$", "")
    if active_item_no > 0 then
        title = title:gsub("%(", "(" .. active_item_no .. "/")
    end
    if has_items(series_total_pages) then
        title = KOR.strings:trim(title) .. " - " .. series_total_pages .. _("pp")
    else
        title = KOR.strings:trim(title) .. " - " .. "?" .. _("pp")
    end
    self.context_dialog = KOR.dialogs:filesBox({
        title = title,
        items = boxes,
        after_close_callback = return_to_series_list and
        function()
            KOR.dialogs:closeOverlay()
            self:onShowSeriesDialog(self.path, self.parent_event, self.arg)
        end,
    })
end

function SeriesManager:showContextDialogForCurrentEbook(result, full_path)
    if result and full_path and #result[1] == 1 then
        self:populateSeries(result)
        local series_name = result["series_name"][1]
        if self.series_table_indexed[series_name] then
            self:showContextDialog(self.series_table_indexed[series_name], false, full_path)
            return true
        end
    end

    return false
end

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

function SeriesManager:showSeriesForEbookPath(full_path)
    if not DX.m.current_series then
        KOR.messages:notify(_("current book does not seem to be part of a series"))
        return
    end

    if not full_path then
        full_path = DX.m.current_ebook_full_path
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
