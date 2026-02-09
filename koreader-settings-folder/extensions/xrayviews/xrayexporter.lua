
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local os_date = os.date

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
function XrayExporter:getExportTitle()
    local dtitle = DX.m.current_series and "Alle Xray %1: serie-modus" or "Alle Xray %1: boek-modus"
    return T(dtitle, self.export_nouns[self.active_tab])
end

--- @private
function XrayExporter:getExportDialogInfo(active_tab)
    local info_texts = {
        self.cached_export_info_all,
        self.cached_export_info_persons,
        self.cached_export_info_terms,
    }

    local title = DX.m.current_series and _("All Xray %1: series mode") or _("All Xray %1: book mode")
    title = T(title, self.export_nouns[active_tab])
    local export_title = title:gsub(": ([^\n]+)", " " .. _("in") .. " \"" .. DX.m.current_title .. "\" (%1)") .. "\n" .. _("List generated") .. ": " .. os_date("%d-%m-%Y") .. "\n\n"

    return export_title .. info_texts[active_tab]
end

--- @private
function XrayExporter:exportInfoToFile()
    local title = DX.m.current_series and "Alle Xray %1: serie-modus" or "Alle Xray %1: boek-modus"
    title = T(title, self.export_nouns[self.active_tab])

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

    self.cached_export_info_all, self.cached_export_info_icon_less_all = DX.vd:generateXrayItemsOverview(items)
    self.cached_export_info_persons, self.cached_export_info_icon_less_persons = DX.vd:generateXrayItemsOverview(DX.vd.persons)
    self.cached_export_info_terms, self.cached_export_info_icon_less_terms = DX.vd:generateXrayItemsOverview(DX.vd.terms)

    return true
end

function XrayExporter:showExportXrayItemsDialog()
    if not self:initData() then
        return
    end

    local top_buttons_left = DX.b:forExportItemsTopLeft()
    KOR.dialogs:textBoxTabbed(self.active_tab, {
        title_func = function()
            return self:getExportTitle()
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
