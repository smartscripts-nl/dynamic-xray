
local require = require

local Device = require("device")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MultiInputDialog = require("extensions/widgets/multiinputdialog")
local Size = require("extensions/modules/size")
local UIManager = require("ui/uimanager")
local _ = KOR:initCustomTranslations()
--local logger = require("logger")
local Screen = Device.screen
local T = require("ffi/util").template

local has_content = has_content
local tonumber = tonumber
local type = type

--- @class EbookMetadata
--- @field metadata_dialog MultiInputDialog
local EbookMetadata = InputContainer:extend{
    metadata_dialog = nil,
}

--- @private
function EbookMetadata:getMetadata(full_path, data, conn)

    local is_local_conn = not conn
    if is_local_conn then
        conn = KOR.databases:getDBconn("EbookMetadata#getMetadata")
    end

    local sql = KOR.databases:injectSafePath("SELECT authors, title, publication_year, series, series_index, rating_goodreads, pages, description FROM bookinfo WHERE directory || filename = 'safe_path'", full_path)
    local authors, title, publication_year, series, series_index, rating_goodreads, pages, description = conn:rowexec(sql)
    if is_local_conn then
        conn = KOR.databases:closeConnections(conn)
    end

    if data then
        pages = tonumber(data.pages) or ""
        rating_goodreads = tonumber(data.rating_goodreads) or ""
        publication_year = tonumber(data.publication_year) or ""
        series_index = tonumber(data.series_index) or ""
    else
        pages = tonumber(pages) or ""
        publication_year = tonumber(publication_year)
        series_index = tonumber(series_index)
        rating_goodreads = tonumber(rating_goodreads)
    end

    if not authors then
        authors = ""
    end

    return authors, title, publication_year, series, series_index, rating_goodreads, pages, description
end

function EbookMetadata:editEbookMetadata(full_path, data, active_tab)
    if not active_tab then
        active_tab = 1
    end
    local conn = KOR.databases:getDBconn("Ebooks:updateEbookMetadata")
    local authors, title, publication_year, series, series_index, rating_goodreads, pages, description = self:getMetadata(full_path, data, conn)
    local fields_description = "\n" .. T(_("fields from left %1 right:\n1. year, 2. authors, 3. title, 4. series,\n5. series-index, 6. pages, 7. GoodReads-rating"), KOR.icons.arrow_bare)
    fields_description = fields_description:gsub("(%d%.) ", "%1 ")
    self.metadata_dialog = MultiInputDialog:new{
        modal = true,
        tabs_count = 2,
        has_field_rows = true,
        active_tab = active_tab,
        tab_callback = function(new_tab)
            if new_tab == active_tab then
                return
            end
            data = self:saveDataForTabChange(data)
            self:closeDialog()
            self:editEbookMetadata(full_path, data, new_tab)
            return true
        end,
        title_tab_buttons_left = { " " .. _("metadata") .. " ", " " .. _("description") .. " " },
        top_paddings_tabs = "1",
        input_registry = "ebook_metadata",
        title_shrink_font_to_fit = true,
        titlebar_alignment = "center",
        --* long ebook file names yield a title bar that is too high:
        --title = "Metadata: " .. path:gsub("^.+/", ""),
        title = authors .. ": " .. title,
        close_callback = function()
            self:closeDialog()
        end,
        footer_description = active_tab == 1 and "  " .. fields_description,
        focus_field = 3,
        fullscreen = true,
        is_popout = false,
        is_borderless = true,
        fullscreen = true, --* if true, a close button is not available
        covers_fullscreen = true,
        allow_newline = false,
        fields = self:getFields({
            authors = authors,
            description = description,
            pages = pages,
            publication_year = publication_year,
            rating_goodreads = rating_goodreads,
            series = series,
            series_index = series_index,
            title = title,
        }),
        width = Screen:getWidth(),
        buttons = self:getButtons(full_path, conn),
    }
    UIManager:show(self.metadata_dialog)
    self.metadata_dialog:onShowKeyboard()

    return true
end

--* save the data entered in fields before we change to another tab, so data modifications will be persisted:
--- @private
function EbookMetadata:saveDataForTabChange(data)
    local fields = self.metadata_dialog:getAllTabsFieldsValues()
    if not data then
        data = {}
    end
    data.publication_year = fields[1]
    data.authors = fields[2]
    data.title = fields[3]
    data.series = fields[4]
    data.series_index = fields[5]
    data.pages = fields[6]
    data.rating_goodreads = fields[7]
    data.description = fields[8]

    return data
end

--- @private
function EbookMetadata:getFields(d)
    local aut_desc = _("authors")
    local tit_desc = _("title")
    local rel_desc = _("year (yyyy)")
    local rat_desc = _("GR-rating")
    local ser_desc = _("series")
    local serno_desc = _("series-index")
    local pag_desc = _("pages")
    local desc_desc = _("description")
    return {
        --* row with 2 fields:
        {
            {
                text = d.publication_year,
                tab = 1,
                allow_newline = false,
                input_type = "number",
                hint = rel_desc,
                cursor_at_end = true,
            },
            {
                text = d.authors,
                tab = 1,
                allow_newline = false,
                hint = aut_desc,
                cursor_at_end = true,
            },
        },
        {
            text = d.title,
            tab = 1,
            allow_newline = false,
            hint = tit_desc,
            cursor_at_end = true,
        },
        --* row with 2 fields:
        {
            {
                text = d.series,
                tab = 1,
                allow_newline = false,
                hint = ser_desc,
                cursor_at_end = true,
            },
            {
                text = d.series_index,
                tab = 1,
                allow_newline = false,
                hint = serno_desc,
                cursor_at_end = true,
            },
        },
        --* row with 2 fields:
        {
            {
                text = d.pages,
                tab = 1,
                allow_newline = false,
                input_type = "number",
                hint = pag_desc,
                cursor_at_end = true,
            },
            {
                text = d.rating_goodreads,
                tab = 1,
                allow_newline = false,
                input_type = "number",
                hint = rat_desc,
                cursor_at_end = true,
            },
        },
        {
            height = "auto",
            text = d.description,
            hint = desc_desc,
            tab = 2,
            scroll = true,
            scroll_by_pan = true,
            allow_newline = true,
            cursor_at_end = false,
            margin = Size.margin.small,
        }
    }
end

--- @private
function EbookMetadata:getButtons(full_path, conn)
    return {
        {
            {
                icon = "back",
                icon_size_ratio = 0.7,
                enabled = true,
                callback = function()
                    self:closeDialog()
                end,
            },
            {
                icon = "save",
                enabled = true,
                is_enter_default = true,
                callback = function()
                    local fields = self.metadata_dialog:getAllTabsFieldsValues()
                    self:closeDialog()

                    local authors, title, publication_year, series, series_index, rating_goodreads, pages, description

                    publication_year = fields[1]
                    authors = fields[2]
                    title = fields[3]
                    series = fields[4]
                    series_index = fields[5]
                    pages = fields[6]
                    rating_goodreads = fields[7]
                    description = fields[8]

                    self:saveMetadata({
                        conn = conn,
                        path = full_path,
                    },
                    {
                        authors = authors,
                        title = title,
                        publication_year = publication_year,
                        series = series,
                        series_index = series_index,
                        rating_goodreads = rating_goodreads,
                        pages = pages,
                        description = description,
                    })
                end,
            },
        },
    }
end

function EbookMetadata:saveMetadata(context, data)

    local authors = data.authors
    local title = data.title
    local publication_year = data.publication_year
    local series = data.series
    local series_index = tonumber(data.series_index)
    local rating_goodreads = data.rating_goodreads
    if has_content(rating_goodreads) and type(rating_goodreads) == "string" then
        rating_goodreads = rating_goodreads:gsub(",", ".")
        rating_goodreads = tonumber(rating_goodreads)
    end
    local pages = tonumber(data.pages)
    local description = data.description

    local conn = context.conn
    local full_path = context.path
    local filemanager_instance = context.filemanager_instance

    if has_content(authors) and has_content(title) then

        if not has_content(publication_year) or not publication_year:match("^%d%d%d%d$") then
            publication_year = nil
        else
            publication_year = tonumber(publication_year)
        end
        local sql = KOR.databases:injectSafePath("UPDATE bookinfo SET authors = ?, title = ?, publication_year = ?, series = ?, series_index = ?, rating_goodreads = ?, pages = ?, description = ? WHERE directory || filename = 'safe_path'", full_path)
        local stmt = conn:prepare(sql)
        stmt:reset():bind(authors, title, publication_year, series, series_index, rating_goodreads, pages, description):step()
        stmt = KOR.databases:closeStmts(stmt)

        sql = KOR.databases:injectSafePath("UPDATE bookinfo SET authors = ?, title = ? WHERE directory || filename = 'safe_path'", full_path)
        stmt = conn:prepare(sql)
        stmt:reset():bind(authors, title):step()
        stmt = KOR.databases:closeStmts(stmt)
        KOR.databases:closeConnections(conn)

        self:closeDialog()
        --* when called from filemanager:
        if filemanager_instance then
            filemanager_instance:updateItems()
        else
            KOR.messages:notify("Metadata opgeslagen")
        end
    end
end

--- @private
function EbookMetadata:closeDialog()
    UIManager:close(self.metadata_dialog)
    self.metadata_dialog = nil
end

return EbookMetadata
