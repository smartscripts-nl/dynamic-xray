
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local os_date = os.date
local table_concat = table.concat
local table_insert = table.insert

local count

--- @class XrayExporter
local XrayExporter = WidgetContainer:new{
    active_tab = 1,
    cached_export_info_all = nil,
    cached_export_info_persons = nil,
    cached_export_info_terms = nil,
    export_nouns = {
        _("items"),
        _("persons"),
        _("terms"),
    },
}

function XrayExporter:resetCache()
    self.cached_export_info_all = nil
    self.cached_export_info_persons = nil
    self.cached_export_info_terms = nil
    self.cached_export_info_icon_less_all = nil
    self.cached_export_info_icon_less_persons = nil
    self.cached_export_info_icon_less_terms = nil
end

--- @private
function XrayExporter:getTitle(active_tab)
    local title = DX.m.current_series and _("All Xray %1: series mode") or _("All Xray %1: book mode")
    return T(title, self.export_nouns[active_tab])
end

--- @private
function XrayExporter:getExportDialogInfo(active_tab)
    local info_texts = {
        self.cached_export_info_all,
        self.cached_export_info_persons,
        self.cached_export_info_terms,
    }

    local title = self:getTitle(active_tab)
    local export_title = title:gsub(": ([^\n]+)", " " .. _("in") .. " \"" .. DX.m.current_title .. "\" (%1)") .. "\n" .. _("List generated") .. ": " .. os_date("%d-%m-%Y") .. "\n\n"

    return export_title .. info_texts[active_tab]
end

--- @private
function XrayExporter:exportInfoToFile()
    local title = self:getTitle(self.active_tab)

    local info_texts = {
        self.cached_export_info_all,
        self.cached_export_info_persons,
        self.cached_export_info_terms,
    }
    local data = info_texts[self.active_tab]

    local info = title .. "\n" .. _("List generated") .. ": " .. os_date("%d-%m-%Y") .. "\n\n" .. data
    KOR.files:filePutcontents(DataStorage:getDataDir() .. "/xray-items.txt", info)

    KOR.messages:notify(_("list exported to xray-items.txt..."))
end

--- @private
function XrayExporter:initData()
    if self.cached_export_info_all then
        return true
    end
    local items = DX.vd.items
    if not items then
        return false
    end

    self.cached_export_info_all, self.cached_export_info_icon_less_all = self:generateXrayItemsOverview(items)
    self.cached_export_info_persons, self.cached_export_info_icon_less_persons = self:generateXrayItemsOverview(DX.vd.persons)
    self.cached_export_info_terms, self.cached_export_info_icon_less_terms = self:generateXrayItemsOverview(DX.vd.terms)

    return true
end

function XrayExporter:generateXrayItemsOverview(items)
    local paragraphs = {}
    local paragraphs_icon_less = {}
    local paragraph, paragraph_icon_less
    count = #items
    for i = 1, count do
        paragraph, paragraph_icon_less = DX.vd:generateXrayItemInfo(items, nil, i, items[i].name, i, "for_all_items_list")
        if i == 1 then
            paragraph = paragraph:gsub(DX.vd.info_indent, "", 1)
            paragraph_icon_less = paragraph_icon_less:gsub(DX.vd.info_indent, "", 1)
        end
        table_insert(paragraphs, paragraph)
        table_insert(paragraphs_icon_less, paragraph_icon_less)
    end
    local info = table_concat(paragraphs, "")
    local info_icon_less = table_concat(paragraphs_icon_less, "")

    return info, info_icon_less
end

function XrayExporter:showExportXrayItemsDialog()
    if not self:initData() then
        return
    end

    local top_buttons_left = DX.b:forExportItemsTopLeft()
    KOR.dialogs:textBoxTabbed(self.active_tab, {
        title_func = function()
            return self:getTitle(self.active_tab)
        end,
        tabs = {
            {
                tab = _("all"),
                info = function()
                    return self:getExportDialogInfo(1)
                end,
            },
            {
                tab = self.export_nouns[2],
                info = function()
                    return self:getExportDialogInfo(2)
                end,
            },
            {
                tab = self.export_nouns[3],
                info = function()
                    return self:getExportDialogInfo(3)
                end,
            },
        },
        parent = self,
        fullscreen = true,
        copy_icon_less_text = true,
        extra_button = KOR.buttoninfopopup:forXrayItemsExportToFile({
            callback = function()
                self:exportInfoToFile()
            end,
        }),
        extra_button_position = 3,
        top_buttons_left = top_buttons_left,
    })
    KOR.screenhelpers:refreshScreen()
end

return XrayExporter
