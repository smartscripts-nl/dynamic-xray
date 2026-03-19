
--* this is a generic items manager; callers have to provide save and delete callbacks
--* see ((Dynamic Xray: module info)) for more info

local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local InputDialog = require("extensions/widgets/inputdialog")
local KOR = require("extensions/kor")
local Menu = require("extensions/widgets/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local table_insert = table.insert

local count

--- @class ItemsManager
local ItemsManager = WidgetContainer:new{
    add_callback = nil,
    add_item_dialog = nil,
    add_title = nil,
    delete_callback = nil,
    edit_item_dialog = nil,
    edit_title = nil,
    --* each item should have this props: id (in the database), item_no (sequential), value:
    items = nil,
    list_footer_buttons_left = nil,
    list_title = nil,
    manager_dialog = nil,
    manager_dialog_inner_menu = nil,
    viewer_dialog = nil,
    view_title = nil,
    save_callback = nil,
}

function ItemsManager:showList(args)
    if args then
        self.items = args.items
        self.add_title = args.add_title
        self.edit_title = args.edit_title
        self.list_title = args.list_title
        self.view_title = args.view_title
        self.add_callback = args.add_callback
        self.delete_callback = args.delete_callback
        self.save_callback = args.save_callback
        self.list_footer_buttons_left = args.list_footer_buttons_left
        self.items = args.items
    end
    local item_table = self:generateItemTable(self.items)

    self.manager_dialog = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    local config = {
        show_parent = self.manager_dialog,
        parent = nil,
        fullscreen = true,
        covers_fullscreen = true,
        has_close_button = true,
        footer_buttons_left = self.list_footer_buttons_left,
        is_popout = false,
        is_borderless = true,
        --! don't use after_close_callback or call ((XrayController#resetFilteredItems)), because then filtering items will not work at all!
        onMenuHold = self.onMenuHold,
        items_per_page = self.items_per_page,
        _manager = self,
    }
    self.manager_dialog_inner_menu = Menu:new(config)
    table_insert(self.manager_dialog, self.manager_dialog_inner_menu)
    self.manager_dialog_inner_menu.close_callback = function()
        UIManager:close(self.manager_dialog)
        KOR.dialogs:unregisterWidget(self.manager_dialog)
        self.manager_dialog = nil
    end

    self.manager_dialog_inner_menu:switchItemTable(self.list_title, item_table)
    UIManager:show(self.manager_dialog)
    KOR.dialogs:registerWidget(self.manager_dialog)
end

--- @private
function ItemsManager:viewItem(item)
    if self.viewer_dialog then
        UIManager:close(self.viewer_dialog)
    end
    self.viewer_dialog = KOR.dialogs:textBox({
        title = self.view_title .. " " .. item.item_no .. "/" .. #self.items,
        info = item.value,
        fullscreen = true,
        no_back_button = true,
        buttons_table = self:buttonsForViewer(item)
    })
end

--- @private
function ItemsManager:buttonsForViewer(item)
    local buttons = {{
         {
             icon = "back",
             callback = function()
                 UIManager:close(self.viewer_dialog)
                 self:showList()
             end
         },
         {
             icon = "dustbin",
             callback = function()
                 KOR.dialogs:confirm("Wil je dit item inderdaad verwijderen?", function()
                     UIManager:close(self.viewer_dialog)
                     self.delete_callback(item.item_no, item.id)
                     local items = {}
                     count = #self.items
                     for i = 1, count do
                         if self.items[i].id ~= item.id then
                             table_insert(items, self.items[i])
                         end
                     end
                     self.items = items
                     self:showList()
                 end)
             end
         },
         {
             icon = "edit-light",
             callback = function()
                 UIManager:close(self.viewer_dialog)
                 self:editItem(item)
             end
         },
         {
             icon = "previous",
             callback = function()
                 self:showPrevItem(item)
             end
         },
         {
             icon = "next",
             callback = function()
                 self:showNextItem(item)
             end
         },
     }}
    if self.add_callback then
        table_insert(buttons[1], 3, {
            icon = "add",
            callback = function()
                self:addItem(item)
            end,
        })
    end
    if self.list_footer_buttons_left then
        table_insert(buttons[1], 2, self.list_footer_buttons_left[1])
    end
    return buttons
end

--- @private
function ItemsManager:showNextItem(item)
    local item_no = item.item_no + 1
    if item_no > #self.items then
        item_no = 1
    end
    self:viewItem(self.items[item_no])
end

--- @private
function ItemsManager:showPrevItem(item)
    local item_no = item.item_no - 1
    if item_no < 1 then
        item_no = #self.items
    end
    self:viewItem(self.items[item_no])
end

--- @private
--- @param item table This is not the new item, but only the currently viewed item to return to upon cancelation of the add-item dialog
function ItemsManager:addItem(item)
    local buttons = {
        {
            icon = "back",
            callback = function()
                UIManager:close(self.add_item_dialog)
                self:viewItem(item)
            end,
        },
        {
            icon = "save",
            is_enter_default = false,
            callback = function()
                local new_text = self.add_item_dialog:getInputText()
                UIManager:close(self.add_item_dialog)
                --! the add_callback defined by the caller should return the id in the database of the new item:
                local id = self.add_callback(new_text)
                table_insert(self.items, {
                    item_no = #self.items + 1,
                    id = id,
                    value = new_text
                })
                self:showList()
            end,
        },
    }
    self.add_item_dialog = InputDialog:new{
        title = self.add_title,
        input = "",
        input_type = "text",
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = true,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = {
            buttons
        },
    }
    UIManager:show(self.add_item_dialog)
    self.add_item_dialog:onShowKeyboard()
end

--- @private
--- @private
function ItemsManager:editItem(item)
    local buttons = {
        {
            icon = "back",
            callback = function()
                UIManager:close(self.edit_item_dialog)
                self:viewItem(item)
            end,
        },
        {
            icon = "save",
            is_enter_default = false,
            callback = function()
                local new_text = self.edit_item_dialog:getInputText()
                UIManager:close(self.edit_item_dialog)
                self.save_callback(item.item_no, item.id, new_text)
                count = #self.items
                for i = 1, count do
                    if self.items[i].id == item.id then
                        self.items[i].value = new_text
                        break
                    end
                end
                self:showList()
            end,
        },
    }
    self.edit_item_dialog = InputDialog:new{
        title = self.edit_title,
        input = item.value,
        input_type = "text",
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = true,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = {
            buttons
        },
    }
    UIManager:show(self.edit_item_dialog)
    self.edit_item_dialog:onShowKeyboard()
end

--- @private
function ItemsManager:generateItemTable(items)
    local item_table = {}
    count = #items
    for i = 1, count do
        local item = KOR.tables:shallowCopy(items[i])
        item.id = item.id
        item.text = item.value
        item.text = KOR.strings:formatListItemNumber(i, item.text)
        item.callback = function()
            UIManager:close(self.manager_dialog)
            self:viewItem(item)
        end
        table_insert(item_table, item)
    end
    return item_table
end

function ItemsManager:closeDialogs()
    UIManager:close(self.manager_dialog)
    UIManager:close(self.viewer_dialog)
end

return ItemsManager
