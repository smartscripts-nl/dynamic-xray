
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_no_items = has_no_items
local math_ceil = math.ceil
local os_date = os.date
local table_concat = table.concat
local table_insert = table.insert

local count

--- @class XrayExporter
local XrayExporter = WidgetContainer:new{
    active_tab = 1,
    items = nil,
    items2 = nil,
    items3 = nil,
    persons = nil,
    persons2 = nil,
    persons3 = nil,
    terms = nil,
    terms2 = nil,
    terms3 = nil,
    iconless_items = nil,
    iconless_persons = nil,
    iconless_terms = nil,

    export_nouns = {
        _("items"),
        _("persons"),
        _("terms"),
        _("tag-groups"),
    },
}

function XrayExporter:resetCache()
    self.items = nil
    self.persons = nil
    self.terms = nil

    self.items2 = nil
    self.persons2 = nil
    self.terms2 = nil

    self.items3 = nil
    self.persons3 = nil
    self.terms3 = nil

    self.iconless_items = nil
    self.iconless_persons = nil
    self.iconless_terms = nil
end

--- @private
function XrayExporter:getTitle(active_tab)
    local title = DX.m.current_series and _("All Xray %1: series mode") or _("All Xray %1: book mode")
    return T(title, self.export_nouns[active_tab])
end

--- @private
function XrayExporter:getExportDialogInfo(active_tab, columns)
    local title = self:getTitle(active_tab)
    local data = self:getInfoText(active_tab, false, columns)
    local spacer = active_tab == 4 and "\n" or "\n\n"
    local export_title = title:gsub(": ([^\n]+)", " in \"" .. DX.m.current_title .. "\" (%1)") .. "\n" .. "Lijst aangemaakt: " .. os_date("%d-%m-%Y") .. spacer

    if not data then
        data = ""
    end
    --? shouldn't there be more columns here (3 and 4 are also sometimes defined: linked item, tag groups):
    if columns then
        return data
    end

    local info = export_title .. data
    return self:addTagsOverview(info, active_tab)
end

--- @private
function XrayExporter:getInfoText(active_tab, iconless, columns)
    local texts_for_copy = {
        self.iconless_items,
        self.iconless_persons,
        self.iconless_terms,
        DX.ta.iconless_tag_groups,
    }

    local info_texts
    if columns == 3 then
        info_texts = {
            self.items3,
            self.persons3,
            self.terms3,
            DX.ta.tag_groups3,
        }
        --* choose one of the above items:
        return info_texts[active_tab]
    elseif columns == 2 then
        info_texts = {
            self.items2,
            self.persons2,
            self.terms2,
            DX.ta.tag_groups2,
        }
        --* choose one of the above items:
        return info_texts[active_tab]
    end

    --* these collections were generated in ((XrayExporter#initData)):
    info_texts = iconless and
        texts_for_copy
        or
        {
            self.items,
            self.persons,
            self.terms,
            DX.ta.tag_groups,
        }

    --* choose one of the above items:
    return info_texts[active_tab]
end

--- @private
function XrayExporter:addTagsOverview(info, active_tab)
    if active_tab < 4 or has_no_items(DX.m.taggroups) then
        return info
    end
    return DX.ta:getTagsForExporterOverview(info)
end

--- @private
function XrayExporter:exportInfoToFile()
    local info =
        self:getTitle(self.active_tab)
        .. "\n" .. _("List generated") .. ": " ..
        os_date("%Y-%m-%d") .. "\n\n" ..
        self:getInfoText(self.active_tab, "iconless", 1)

    self:addTagsOverview(info, self.active_tab)
    info = info:gsub("\n\n\n+", "\n\n")

    KOR.files:filePutcontents(DataStorage:getDataDir() .. "/xray-items.txt", info)

    KOR.messages:notify(_("list exported to xray-items.txt..."))
end

--- @private
function XrayExporter:initData()
    if self.items then
        return true
    end
    if not DX.vd.items then
        return false
    end

    KOR.columntexts:initDisplayColumnsCount(#DX.vd.items)
    self.items, self.items2, self.items3 = self:generateXrayItemsOverview(DX.vd.items, "for_all_items_list", 1)

    KOR.columntexts:initDisplayColumnsCount(#DX.vd.persons)
    self.persons, self.persons2, self.persons3 = self:generateXrayItemsOverview(DX.vd.persons, "for_all_items_list", 2)

    KOR.columntexts:initDisplayColumnsCount(#DX.vd.terms)
    self.terms, self.terms2, self.terms3 = self:generateXrayItemsOverview(DX.vd.terms, "for_all_items_list", 3)

    DX.ta:generateTagGroupsOverview(4)

    return true
end

--- @param mode string Either "for_all_items_list" or "for_linked_items_tab"
function XrayExporter:generateXrayItemsOverview(items, mode, clipboard_tab_no)
    local paragraphs_iconless = {}
    local paragraph, paragraph_iconless
    local column1, column2, column3 = {}, {}, {}
    count = #items

    local use_two_column_display = DX.s.overview_tabs_columns_count == 2 and count >= 2
    local use_three_column_display = DX.s.overview_tabs_columns_count == 3 and count >= 3

    local half_way = math_ceil(count / 2)
    local third_way = math_ceil(count / 3)
    local is_top_column_item
    for i = 1, count do
        --* at the top of the second column we don't want to start with a line ending, so set is_top_column_item to true for that case:
        is_top_column_item = (not use_two_column_display and not use_three_column_display and i == 1)
                or
                (use_two_column_display and (i == 1 or i == half_way + 1))
                or
                (use_three_column_display and (i == 1 or i == third_way + 1 or i == 2 * third_way + 1))
        paragraph, paragraph_iconless = DX.vd:generateXrayExportOrLinkedItemInfo(count, items[i], nil, is_top_column_item, mode)
        table_insert(column1, paragraph)
        table_insert(paragraphs_iconless, paragraph_iconless)
    end

    KOR.registry:setClipboardTabText(clipboard_tab_no, table_concat(paragraphs_iconless, "\n\n"))

    --* returned here: column1, column2, info_iconless; column2 will be set to nil when usage of text columns wasn't active:
    if use_two_column_display then
        return KOR.columntexts:getTwoColumnTexts(column1, column2)
    elseif use_three_column_display then
        return KOR.columntexts:getThreeColumnTexts(column1, column2, column3)
    end

    return KOR.columntexts:getOneColumnText(column1)
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
                tab = self.export_nouns[1],
                info = function()
                    return self:getExportDialogInfo(1, 1)
                end,
                info2 = function()
                    if DX.s.overview_tabs_columns_count < 2 then
                        return nil
                    end
                    return self:getExportDialogInfo(1, 2)
                end,
                info3 = function()
                    if DX.s.overview_tabs_columns_count < 3 then
                        return nil
                    end
                    return self:getExportDialogInfo(1, 3)
                end,
            },
            {
                tab = self.export_nouns[2],
                info = function()
                    return self:getExportDialogInfo(2, 1)
                end,
                info2 = function()
                    if DX.s.overview_tabs_columns_count < 2 then
                        return nil
                    end
                    return self:getExportDialogInfo(2, 2)
                end,
                info3 = function()
                    if DX.s.overview_tabs_columns_count < 3 then
                        return nil
                    end
                    return self:getExportDialogInfo(2, 3)
                end,
            },
            {
                tab = self.export_nouns[3],
                info = function()
                    return self:getExportDialogInfo(3, 1)
                end,
                info2 = function()
                    if DX.s.overview_tabs_columns_count < 2 then
                        return nil
                    end
                    return self:getExportDialogInfo(3, 2)
                end,
                info3 = function()
                    if DX.s.overview_tabs_columns_count < 3 then
                        return nil
                    end
                    return self:getExportDialogInfo(3, 3)
                end,
            },
            {
                tab = self.export_nouns[4],
                info = function()
                    return self:getExportDialogInfo(4, 1)
                end,
                info2 = function()
                    if DX.s.overview_tabs_columns_count < 2 then
                        return nil
                    end
                    return self:getExportDialogInfo(4, 2)
                end,
                info3 = function()
                    if DX.s.overview_tabs_columns_count < 3 then
                        return nil
                    end
                    return self:getExportDialogInfo(4, 3)
                end,
            },
        },
        parent = self,
        fullscreen = true,
        text_for_copy = function()
            return self:getInfoText(self.active_tab, "iconless")
        end,
        extra_buttons_startpos = 3,
        extra_buttons = {
            KOR.buttoninfopopup:forXrayItemsExportToFile({
                callback = function()
                    self:exportInfoToFile()
                end,
            })
        },
        has_copy_button = true,
        top_buttons_left = top_buttons_left,
    })
    KOR.screenhelpers:refreshScreen()
end

return XrayExporter
