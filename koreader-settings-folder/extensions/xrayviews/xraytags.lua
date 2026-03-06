
--* see ((Dynamic Xray: module info)) for more info

--! info about TextViewer TOC functionality for Xray items: see ((TextViewer toc button))

local require = require

local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local Device = require("device")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen
local T = require("ffi/util").template

local DX = DX
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local math = math
local math_floor = math.floor
local table = table
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort

local count

--- @class XrayTags
local XrayTags = WidgetContainer:new{
    select_for_tags = false,
    select_for_tag_items = {},
    select_for_tags_tag = nil,

    tag_group = nil,
    tag_group2 = nil,
    iconless_tag_group = nil,

    tag_groups = nil,
    tag_groups2 = nil,
    iconless_tag_groups = nil,
    tags = nil,
    tags_concatenated = nil,
}

function XrayTags:showTagSelector(mode)
    local tags = DX.m.tags
    if self:showNoTagsNotification() then
        return
    end
    local buttons_per_row = 4
    local buttons = { {} }
    local row = 1
    local tags_dialog
    local button_width = math_floor(Screen:getWidth() / 6)
    count = #tags
    local dialog_width = count < buttons_per_row and count * button_width or buttons_per_row * button_width
    for i = 1, count do
        table_insert(buttons[row], {
            text = tags[i],
            font_bold = false,
            width = button_width,
            callback = function()
                UIManager:close(tags_dialog)
                if mode == "list" then
                    DX.c:filterItemsByTag(tags[i])

                else
                    DX.pn:betweenTagsNavigationActivate(tags[i])
                    if DX.s.PN_show_tagged_items_navigation_alert then
                        KOR.dialogs:niceAlert(_("Tag group navigation"), T(_("You can now browse:\n\n* with the arrow buttons\n* or with N and P on your keyboard\n\nfrom page with tagged items to next/previous page with tagged items%1\n\nDisable this popup by setting PN_show_tagged_items_navigation_alert to false%2"), KOR.strings.ellipsis, KOR.strings.ellipsis), {
                            delay = 7,
                        })
                    end
                end
            end,
        })
        if i > 1 and i % buttons_per_row == 0 then
            table_insert(buttons, {})
            row = row + 1
        end
    end
    local subtitle = mode == "page_navigator" and _("browse between occurrences of tag group members") or _("filter the List by a tag")
    tags_dialog = ButtonDialogTitle:new{
        title = _("tag groups"),
        subtitle = subtitle .. KOR.strings.ellipsis,
        width = dialog_width,
        buttons = buttons,
    }
    UIManager:show(tags_dialog)
end

function XrayTags:addTagsToItems()
    if KOR.tables:associativeTableLength(self.select_for_tag_items) == 0 then
        KOR.messages:notify(_("you haven't selected any items for tag update yet"), 4)
        self:resetModule()
        DX.d:showListWithRestoredArguments()
        return
    end

    DX.ds.storeItemsTags(self.select_for_tag_items)
    self:resetAllSelectionsForTag()
    self:resetModule()
    DX.c:resetDynamicXray("is_prepared")
    KOR.messages:notify(_("tag assigned to the items"), 4)

    DX.d:showListWithRestoredArguments()
end

--- @private
function XrayTags:resetModule()
    self.select_for_tags = false
    self.select_for_tags_tag = nil
    self.select_for_tag_items = {}
end

function XrayTags:resetTagGroups()
    self.tag_group = nil
    self.tag_group2 = nil
    self.iconless_tag_group = nil

    self.tag_groups = nil
    self.tag_groups2 = nil
    self.iconless_tag_groups = nil
    self.tags_concatenated = nil
end

function XrayTags:getTagsForExporterOverview(info)
    local tags = self.tags_concatenated or table_concat(DX.m.tags, " - ")
    self.tags_concatenated = tags

    info = KOR.strings:split(info, "\n", "capture_empty_entity")
    table_insert(info, 2, _("Tags in this overview") .. ": " .. self.tags_concatenated)

    return table_concat(info, "\n")
end

--- @private
function XrayTags:resetItemForTagsSelection(item, for_one_item)
    item.dim = nil
    item.text = item.text:gsub(" " .. KOR.icons.checkboxes, "", 1)

    --* then all items will be reset in a loop:
    if not for_one_item then
        return
    end

    self.select_for_tag_items[item.id] = nil
    DX.d.xray_items_inner_menu:updateItems()
end

--- @private
function XrayTags:resetAllSelectionsForTag()
    local item_table = DX.d.xray_items_inner_menu.item_table
    for i = 1, #item_table do
        self:resetItemForTagsSelection(item_table[i])
    end
    DX.d.xray_items_inner_menu:updateItems()
end

function XrayTags:initiateItemTagsSelection()
    if not self.select_for_tags then
        return
    end

    local manager = self
    DX.d.xray_items_inner_menu.onMenuSelect = function(parent, item)
        if item.dim then
            --* argument parent here not used, but added to silence code sniffing:
            manager:resetItemForTagsSelection(item, "for_one_item", parent)
            return
        end

        local matcher = KOR.strings:prepareNeedleForMatching(manager.select_for_tags_tag, "with_word_boundaries")
        if has_text(item.tags) and item.tags:match(matcher) then

            manager.tag_exists_alert = KOR.dialogs:niceAlert(_("Tag already assigned"), T(_("This item already has the tag \"%1\"%2\n\n* choose \"remove\" to remove the tag\n* choose \"forget\" to deselect the item\n\nPreviously defined tag-groups:\n%3"), manager.select_for_tags_tag, KOR.strings.ellipsis, DX.m:getAllAssignedTagsString()), {
                modal = true,
                buttons = {{
                    {
                        text = _("remove"),
                        callback = function()
                            UIManager:close(manager.tag_exists_alert)
                            item.dim = true
                            item.text = item.text:gsub("(%d+%.)", "%1 " .. KOR.icons.checkboxes, 1)
                            manager:prepareUpdatedItemTags(item, "delete")
                            DX.d.xray_items_inner_menu:updateItems()
                        end,
                    },
                    {
                        text = _("forget"),
                        callback = function()
                            UIManager:close(manager.tag_exists_alert)
                            item.dim = nil
                            DX.d.xray_items_inner_menu:updateItems()
                        end
                    }
                }}
            })

        --* item didn't have any tags yet or didn't have the current tag:
        else
            item.dim = true
            item.text = item.text:gsub("(%d+%.)", "%1 " .. KOR.icons.checkboxes, 1)
            manager:prepareUpdatedItemTags(item, "add")
            DX.d.xray_items_inner_menu:updateItems()
        end
    end
end

--- @private
function XrayTags:prepareUpdatedItemTags(item, mode)
    local tags = item.tags
    local separator = ", "
    if mode == "add" then
        if has_no_text(tags) then
            self.select_for_tag_items[item.id] = self.select_for_tags_tag
            return
        end
        tags = DX.m:splitByCommaOrSpace(tags)
        table_insert(tags, self.select_for_tags_tag)
        table_sort(tags)
        self.select_for_tag_items[item.id] = table_concat(tags, separator)
        return
    end

    --* remove existing tag:
    tags = DX.m:splitByCommaOrSpace(tags)
    local pruned_tags = {}
    count = #tags
    for i = 1, count do
        if tags[i] ~= self.select_for_tags_tag then
            table_insert(pruned_tags, tags[i])
        end
    end
    if has_no_items(pruned_tags) then
        --* this will be converted to a real nil value in ((XrayDataSaver#storeItemsTags)):
        self.select_for_tag_items[item.id] = "nil"
        return
    end
    self.select_for_tag_items[item.id] = table_concat(pruned_tags, separator)
end

function XrayTags:toggleItemsForTagsSelection()
    self.select_for_tags = not self.select_for_tags
    if self.select_for_tags then
        KOR.dialogs:prompt({
            no_overlay = true,
            title = _("Tag to be assigned"),
            callback = function(tags)
                if not has_text(tags) then
                    KOR.messages:notify(_("you haven't entered a tag"))
                    self.select_for_tags = false
                    return
                end
                --* selection of items happens in ((XrayTags#initiateItemTagsSelection)):
                self.select_for_tags_tag = tags
                --* to show the tag to be added in the title of the Items List dialog:
                DX.d:showListWithRestoredArguments()
                KOR.messages:notify(_("now select items"), 4)
            end,
            cancel_callback = function()
                self.select_for_tags = false
            end,
        })
    else
        self:resetAllSelectionsForTag()
        self:resetModule()
        KOR.messages:notify(_("items selection for tag-assigment disabled"))
    end
    DX.d:showListWithRestoredArguments()
end

--- @private
function XrayTags:generateTagGroup(tag)
    local items = DX.vd.items
    local tag_group = {}
    local needle = KOR.strings:prepareNeedleForMatching(tag, "with_word_boundaries")
    local is_first_para = true
    local tagged_items = {}
    count = #items
    for i = 1, count do
        if has_text(items[i].tags) and items[i].tags:match(needle) then
            table_insert(tagged_items, items[i])
        end
    end
    count = #tagged_items
    for i = 1, count do
        self:populateTagGroup(tag_group, tag, tagged_items[i], count, is_first_para)
        is_first_para = false
    end
    count = #tag_group.paras
    local use_two_column_display = KOR.twocolumntext:useTwoColumnDisplay(count)

    --* column2 here will be set to nil if use_two_column_display is false:
    --* return as text: column1, column2, paragraphs_iconless:
    self.tag_group, self.tag_group2, self.iconless_tag_group = KOR.twocolumntext:getColumnTexts(tag_group.paras, nil, use_two_column_display, tag_group.paras_iconless)
end

function XrayTags:generateTagGroupsOverview()
    local items = DX.vd.items
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
    local otable = KOR.tables:getSortedAssociativeTable(tag_groups)
    count = #otable
    for i = 1, count do
        data = otable[i][2]
        KOR.tables:merge(paragraphs, data.paras)
        KOR.tables:merge(paragraphs_iconless, data.paras_iconless)
    end
    count = #paragraphs
    if self:showNoTagsNotification(count, "with_explanation") then
        return
    end

    local use_two_column_display = KOR.twocolumntext:useTwoColumnDisplay(count)

    --* column2 here will be set to nil if use_two_column_display is false:
    --* return as text: column1, column2, paragraphs_iconless:
    self.tag_groups, self.tag_groups2, self.iconless_tag_groups = KOR.twocolumntext:getColumnTexts(paragraphs, nil, use_two_column_display, paragraphs_iconless)
end

--- @private
function XrayTags:populateTagGroup(tag_group, tag, item, tagged_count, is_first_para)
    if is_first_para then
        tag_group.paras = {}
        tag_group.paras_iconless = {
            tag:upper() .. "\n\n"
        }
    end
    local paragraph, paragraph_iconless = DX.vd:generateXrayExportOrLinkedItemInfo(tagged_count, item, nil, is_first_para, "for_all_items_list")
    table_insert(tag_group.paras, paragraph .. "\n")
    table_insert(tag_group.paras_iconless, paragraph_iconless .. "\n")
end

--- @private
function XrayTags:populateTagGroups(tag_groups, item)
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
        table_insert(tag_groups[tag].paras, paragraph .. "\n")
        table_insert(tag_groups[tag].paras_iconless, paragraph_iconless .. "\n")
    end
end

function XrayTags:getNextTagGroup(tag)
    local tags = DX.m.tags
    local next_tag_index
    count = #tags
    for i = 1, count do
        if tags[i] == tag then
            next_tag_index = i + 1
            if next_tag_index > count then
                next_tag_index = 1
            end
            return tags[next_tag_index]
        end
    end
end

function XrayTags:getPreviousTagGroup(tag)
    local tags = DX.m.tags
    local previous_tag_index
    count = #tags
    for i = 1, count do
        if tags[i] == tag then
            previous_tag_index = i - 1
            if previous_tag_index < 1 then
                previous_tag_index = count
            end
            return tags[previous_tag_index]
        end
    end
end

function XrayTags:isSameTagGroup(tag, other_tag)
    if other_tag == tag then
        KOR.messages:notify(_("only one tag-group has been defined"))
        return true
    end
    return false
end

function XrayTags:showTagGroupSelector()
    local tags = DX.m.tags
    if self:showNoTagsNotification(tags) then
        return
    end
    self.tag_group_selector = ButtonDialogTitle:new{
        title = _("Choose a tag-group"),
        use_low_title = true,
        title_align = "center",
        width_factor = 0.95,
        button_width = 0.33,
        buttons = DX.b:forTagGroupsSelector(self, tags),
        --[[after_close_callback = function()
            KOR.dialogs:closeAllOverlays()
        end]]
    }
    UIManager:show(self.tag_group_selector)
end

function XrayTags:showTagGroup(tag)
    self:generateTagGroup(tag)
    self.tag_group_viewer = KOR.dialogs:textBox({
        title = _("Tag-group") .. ": " .. tag,
        fullscreen = true,
        info = self.tag_group,
        info2 = self.tag_group2,
        extra_button = KOR.buttoninfopopup:forXrayTagGroupNext({
            callback = function()
                local next_tag = DX.ta:getNextTagGroup(tag)
                if DX.ta:isSameTagGroup(tag, next_tag) or not next_tag then
                    return
                end
                UIManager:close(self.tag_group_viewer)
                DX.ta:showTagGroup(next_tag)
            end,
        }),
        extra_button_position = 2,
        extra_button2 = KOR.buttoninfopopup:forXrayTagGroupPrevious({
            callback = function()
                local previous_tag = DX.ta:getPreviousTagGroup(tag)
                if DX.ta:isSameTagGroup(tag, previous_tag) or not previous_tag then
                    return
                end
                UIManager:close(self.tag_group_viewer)
                DX.ta:showTagGroup(previous_tag)
            end,
        }),
        extra_button2_position = 2,
        text_for_copy = self.iconless_tag_group,
    })
end

function XrayTags:showNoTagsNotification(tags, with_explanation)
    if has_no_items(tags) then
        local message = _("you haven't assigned any tags to items yet")
        if with_explanation then
            message = message .. "\n\n" .. _("You can create tag-groups by adding tags to Xray items.")
        end
        KOR.messages:notify(message)
        return true
    end
    return false
end

return XrayTags
