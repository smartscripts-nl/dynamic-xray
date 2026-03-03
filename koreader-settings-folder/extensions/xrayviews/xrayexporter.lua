
--* see ((Dynamic Xray: module info)) for more info

local require = require

local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_no_items = has_no_items
local has_text = has_text
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
    persons = nil,
    persons2 = nil,
    terms = nil,
    terms2 = nil,
    iconless_items = nil,
    iconless_persons = nil,
    iconless_terms = nil,

    tag_groups = nil,
    tag_groups2 = nil,
    iconless_tag_groups = nil,

    tags = nil,
    tags_concatenated = nil,

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
    self.iconless_items = nil
    self.iconless_persons = nil
    self.iconless_terms = nil

    self.tag_groups = nil
    self.tag_groups2 = nil
    self.iconless_tag_groups = nil

    self.tags_concatenated = nil
end

--- @private
function XrayExporter:getTitle(active_tab)
    local title = DX.m.current_series and _("All Xray %1: series mode") or _("All Xray %1: book mode")
    return T(title, self.export_nouns[active_tab])
end

--- @private
function XrayExporter:getExportDialogInfo(active_tab, column_2)
    local title = self:getTitle(active_tab)
    local data = self:getInfoText(active_tab, false, column_2)
    local spacer = active_tab == 4 and "\n" or "\n\n"
    local export_title = title:gsub(": ([^\n]+)", " " .. _("in") .. " \"" .. DX.m.current_title .. "\" (%1)") .. "\n" .. _("List generated") .. ": " .. os_date("%Y-%m-%d") .. spacer

    if column_2 then
        return data
    end

    local info = export_title .. data
    return self:addTagsOverview(info, active_tab)
end

--- @private
function XrayExporter:getInfoText(active_tab, iconless, column_2)
    local info_texts
    if column_2 then
        info_texts = {
            self.items2,
            self.persons2,
            self.terms2,
            self.tag_groups2,
        }
        --* choose one of the above items:
        return info_texts[active_tab]
    end

    --* these collections were generated in ((XrayExporter#initData)):
    info_texts = iconless and
        {
            self.iconless_items,
            self.iconless_persons,
            self.iconless_terms,
            self.iconless_tag_groups,
        }
    or
        {
            self.items,
            self.persons,
            self.terms,
            self.tag_groups,
    }

    --* choose one of the above items:
    return info_texts[active_tab]
end

--- @private
function XrayExporter:addTagsOverview(info, active_tab)
    if active_tab < 4 or has_no_items(DX.m.tags) then
        return info
    end

    local tags = self.tags_concatenated or table_concat(DX.m.tags, " - ")
    self.tags_concatenated = tags

    info = KOR.strings:split(info, "\n", "capture_empty_entity")
    table_insert(info, 2, _("Tags in this overview") .. ": " .. self.tags_concatenated)

    return table_concat(info, "\n")
end

--- @private
function XrayExporter:exportInfoToFile()
    local info =
        self:getTitle(self.active_tab)
        .. "\n" .. _("List generated") .. ": " ..
        os_date("%Y-%m-%d") .. "\n\n" ..
        self:getInfoText(self.active_tab, "iconless")

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

    local use_two_column_display = KOR.twocolumntext:useTwoColumnDisplay(#DX.vd.items)
    self.items, self.items2, self.iconless_items = self:generateXrayItemsOverview(DX.vd.items, "for_all_items_list", use_two_column_display)

    use_two_column_display = KOR.twocolumntext:useTwoColumnDisplay(#DX.vd.persons)
    self.persons, self.persons2, self.iconless_persons = self:generateXrayItemsOverview(DX.vd.persons, "for_all_items_list", use_two_column_display)

    KOR.twocolumntext:useTwoColumnDisplay(#DX.vd.terms)
    self.terms, self.terms2, self.iconless_terms = self:generateXrayItemsOverview(DX.vd.terms, "for_all_items_list", use_two_column_display)

    self.tag_groups, self.tag_groups2, self.iconless_tag_groups = self:generateTagGroupsOverview(DX.vd.items)

    return true
end

--- @param mode string Either "for_all_items_list" or "for_linked_items_tab"
function XrayExporter:generateXrayItemsOverview(items, mode, use_two_column_display)
    local paragraphs_iconless = {}
    local paragraph, paragraph_iconless
    local column1, column2 = {}, {}
    count = #items

    local half_way = math_ceil(count / 2)
    local is_top_column_item
    for i = 1, count do
        --* at the top of the second column we don't want to start with a line ending, so set is_top_column_item to true for that case:
        is_top_column_item = use_two_column_display and i == half_way + 1
        paragraph, paragraph_iconless = DX.vd:generateXrayExportOrLinkedItemInfo(count, items[i], nil, is_top_column_item, mode)
        table_insert(column1, paragraph)
        table_insert(paragraphs_iconless, paragraph_iconless)
    end

    --* returned here: column1, column2, info_iconless; column2 will be set to nil when usage of text columns wasn't active:
    return KOR.twocolumntext:getColumnTexts(column1, column2, use_two_column_display, paragraphs_iconless)
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
    count = #paragraphs
    if count == 0 then
        return "you haven't defined any tag-groups as yet" .. "...\n\n" .. _("You can create tag-groups by adding tags to Xray items.")
    end

    local use_two_column_display = KOR.twocolumntext:useTwoColumnDisplay(count)

    --* column2 here will be set to nil if use_two_column_display is false:
    --* return as text: column1, column2, paragraphs_iconless:
    return KOR.twocolumntext:getColumnTexts(paragraphs, nil, use_two_column_display, paragraphs_iconless)
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
                    "\n" .. KOR.icons.tag_open_bare .. " " .. heading_tag .. "\n\n",
                },
                paras_iconless = {
                    "\n" .. heading_tag .. "\n\n",
                },
            }
        end
        local paragraph, paragraph_iconless = DX.vd:generateXrayExportOrLinkedItemInfo(count, item, nil, i, "for_all_items_list")
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
                tab = self.export_nouns[1],
                info = function()
                    return self:getExportDialogInfo(1)
                end,
                info2 = function()
                    return self:getExportDialogInfo(1, "column_2")
                end,
            },
            {
                tab = self.export_nouns[2],
                info = function()
                    return self:getExportDialogInfo(2)
                end,
                info2 = function()
                    return self:getExportDialogInfo(2, "column_2")
                end,
            },
            {
                tab = self.export_nouns[3],
                info = function()
                    return self:getExportDialogInfo(3)
                end,
                info2 = function()
                    return self:getExportDialogInfo(3, "column_2")
                end,
            },
            {
                tab = self.export_nouns[4],
                info = function()
                    return self:getExportDialogInfo(4)
                end,
                info2 = function()
                    return self:getExportDialogInfo(4, "column_2")
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
