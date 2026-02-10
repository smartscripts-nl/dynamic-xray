
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_text = has_text
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
    cached_export_info_iconless_all = nil,
    cached_export_info_iconless_persons = nil,
    cached_export_info_iconless_terms = nil,

    cached_export_info_tag_groups = nil,
    cached_export_info_iconless_tag_groups = nil,
    export_nouns = {
        _("items"),
        _("persons"),
        _("terms"),
        _("tag-groups"),
    },
}

function XrayExporter:resetCache()
    self.cached_export_info_all = nil
    self.cached_export_info_persons = nil
    self.cached_export_info_terms = nil
    self.cached_export_info_iconless_all = nil
    self.cached_export_info_iconless_persons = nil
    self.cached_export_info_iconless_terms = nil
    self.cached_export_info_tag_groups = nil
    self.cached_export_info_iconless_tag_groups = nil
end

--- @private
function XrayExporter:getTitle(active_tab)
    local title = DX.m.current_series and _("All Xray %1: series mode") or _("All Xray %1: book mode")
    return T(title, self.export_nouns[active_tab])
end

--- @private
function XrayExporter:getExportDialogInfo(active_tab)
    local title = self:getTitle(active_tab)
    local data = self:getInfoText(active_tab)
    local export_title = title:gsub(": ([^\n]+)", " " .. _("in") .. " \"" .. DX.m.current_title .. "\" (%1)") .. "\n" .. _("List generated") .. ": " .. os_date("%Y-%m-%d") .. "\n\n"

    return export_title .. data
end

--- @private
function XrayExporter:getInfoText(active_tab, iconless)
    --* these collections were generated in ((XrayExporter#initData)):
    local info_texts = iconless and
        {
            self.cached_export_info_iconless_all,
            self.cached_export_info_iconless_persons,
            self.cached_export_info_iconless_terms,
            self.cached_export_info_iconless_tag_groups,
        }
    or
        {
        self.cached_export_info_all,
        self.cached_export_info_persons,
        self.cached_export_info_terms,
        self.cached_export_info_tag_groups,
    }
    return info_texts[active_tab]
end

--- @private
function XrayExporter:exportInfoToFile()
    local info =
        self:getTitle(self.active_tab)
        .. "\n" .. _("List generated") .. ": " ..
        os_date("%Y-%m-%d") .. "\n\n" ..
        self:getInfoText(self.active_tab, "iconless")

    KOR.files:filePutcontents(DataStorage:getDataDir() .. "/xray-items.txt", info)

    KOR.messages:notify(_("list exported to xray-items.txt..."))
end

--- @private
function XrayExporter:initData()
    if self.cached_export_info_all then
        return true
    end
    if not DX.vd.items then
        return false
    end

    self.cached_export_info_all, self.cached_export_info_iconless_all = self:generateXrayItemsOverview(DX.vd.items)
    self.cached_export_info_persons, self.cached_export_info_iconless_persons = self:generateXrayItemsOverview(DX.vd.persons)
    self.cached_export_info_terms, self.cached_export_info_iconless_terms = self:generateXrayItemsOverview(DX.vd.terms)
    self.cached_export_info_tag_groups, self.cached_export_info_iconless_tag_groups = self:generateTagGroupsOverview(DX.vd.items)

    return true
end

function XrayExporter:generateXrayItemsOverview(items)
    local paragraphs = {}
    local paragraphs_iconless = {}
    local paragraph, paragraph_iconless
    count = #items
    for i = 1, count do
        paragraph, paragraph_iconless = DX.vd:generateXrayItemInfo(items[i], nil, i, "for_all_items_list")
        if i == 1 then
            paragraph = paragraph:gsub(DX.vd.info_indent, "", 1)
            paragraph_iconless = paragraph_iconless:gsub(DX.vd.info_indent, "", 1)
        end
        table_insert(paragraphs, paragraph)
        table_insert(paragraphs_iconless, paragraph_iconless)
    end
    local info = table_concat(paragraphs, "")
    local info_iconless = table_concat(paragraphs_iconless, "")

    return info, info_iconless
end

--- @private
function XrayExporter:generateTagGroupsOverview(items)
    local paragraphs = {}
    local paragraphs_iconless = {}
    local tag_groups = {}
    count = #items
    for i = 1, count do
        if has_text(items[i].tags) then
            self:populateTagGroups(tag_groups, items[i])
        end
    end
    local data
    local otable = KOR.tables:getSortedRelationalTable(tag_groups)
    count = #otable
    for i = 1, count do
        data = otable[i][2]
        KOR.tables:merge(paragraphs, data.paras)
        KOR.tables:merge(paragraphs_iconless, data.paras_iconless)
    end
    if #paragraphs == 0 then
        return "you haven't defined any tag-groups as yet" .. "...\n\n" .. _("You can create tag-groups by adding tags to Xray items.")
    end
    local info = table_concat(paragraphs, "")
    local info_iconless = table_concat(paragraphs_iconless, "")

    return info, info_iconless
end

--- @private
function XrayExporter:populateTagGroups(tag_groups, item)
    local tags = DX.m:splitByCommaOrSpace(item.tags)
    local tag, heading_tag
    local add_spacer = true
    count = #tags
    for i = 1, count do
        tag = tags[i]
        heading_tag = tag:upper()
        if not tag_groups[tag] then
            add_spacer = false
            tag_groups[tag] = {
                paras = {
                    KOR.icons.tag_open_bare .. " " .. heading_tag .. "\n\n",
                },
                paras_iconless = {
                    heading_tag .. "\n\n",
                },
            }
        end
        local paragraph, paragraph_iconless = DX.vd:generateXrayItemInfo(item, nil, i, "for_all_items_list")
        if i == 1 then
            paragraph = paragraph:gsub(DX.vd.info_indent, "", 1)
            paragraph_iconless = paragraph_iconless:gsub(DX.vd.info_indent, "", 1)
        end
        if add_spacer then
            table_insert(tag_groups[tag].paras, "\n")
            table_insert(tag_groups[tag].paras_iconless, "\n")
        end
        table_insert(tag_groups[tag].paras, paragraph)
        table_insert(tag_groups[tag].paras_iconless, paragraph_iconless)
    end
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
            {
                tab = self.export_nouns[4],
                info = function()
                    return self:getExportDialogInfo(4)
                end,
            },
        },
        parent = self,
        fullscreen = true,
        text_for_copy = function()
            return self:getInfoText(self.active_tab, "iconless")
        end,
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
