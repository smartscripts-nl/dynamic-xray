
local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local KOR = require("extensions/kor")
local Menu = require("xrayviews/widgets/menu")
local MultiInputDialog = require("xrayviews/widgets/multiinputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen

local has_no_items = has_no_items
local has_no_text = has_no_text
local T = T
local table_insert = table_insert
local utf8lower = utf8lower

local count

--- @class InformationManager
local InformationManager = WidgetContainer:extend{
    name = "informationmanager",
    current_menu_page = 1,
    --* can be overridden:
    --! tables used here must have fields id, item, information:
    db_table = nil,
    dialog_title = nil,
    information_hint = nil,
    information_items = {},
    item_hint = nil,
    item_name = nil,
    items_per_page = G_reader_settings:readSetting("items_per_page"),
    key_events = {},
    manager_instance = nil,
    manager_instance_inner_menu = nil,
    module_options = nil,
    view_nr = 1,
}

--- @private
function InformationManager:loadInformation()
    local conn = self:getDBconn("InformationManager:loadInformation")
    local sql = [[
        SELECT id, item, information
        FROM ]] .. self.db_table .. [[
        ORDER BY item
    ]]
    local result = conn:exec(sql)
    conn = self:closeDBconn(conn)
    return result
end

--- @private
function InformationManager:guardBlockNonUniqueItem(name)
    name = utf8lower(name)
    count = #self.information_items
    for i = 1, count do
        if utf8lower(self.information_items[i].name) == name then
            KOR.messages:notify(_(T("an entry with the name %1 already exists", name)))
            return true
        end
    end
    return false
end

--- @private
function InformationManager:populateInformationItems(result)
    self.information_items = {}
    local id, name, information
    count = #result[1]
    for i = 1, count do
        local current_nr = i
        id = result["id"][i]
        name = result["item"][i]
        information = result["information"][i]
        table_insert(self.information_items, {
            table_id = id,
            nr = current_nr,
            name = name,
            text = name .. " " .. KOR.icons.arrow_bare .. " " .. information,
            information = information,
            callback = function()
                self.view_nr = current_nr
                self:showViewDialog()
            end,
        })
    end
end

function InformationManager:getGroupedItems(list, entry_name)

    if has_no_items(list) then
        return {}, 1
    end
    list = KOR.tables:getSortedAssociativeTable(list)
    --* return grouped_list and select_number:
    return self:populateList(nil, list, entry_name)
end

function InformationManager:getGroupedItemsFromDb(db_table)
    self.db_table = db_table
    local result = self:loadInformation()
    if not result then
        return {}
    end
    --* return grouped list and select_number 1:
    return self:populateList(result)
end

--- @private
function InformationManager:populateList(result, list, entry_name)
    local key, value, first_char, first_char_upper
    local select_number = 1
    local grouped = {}
    count = result and #result[1] or #list
    for i = 1, count do
        key = result and result["item"][i] or list[i][1]
        value = result and result["information"][i] or list[i][2]
        if entry_name and key == entry_name then
            select_number = i
        end
        first_char = key:lower():sub(1, 1)
        if not grouped[first_char] then
            grouped[first_char] = {}
        end
        grouped[first_char][key] = value

        --* also replace snippets in the dialog text which start with an uppercase character:
        first_char_upper = first_char:upper()
        if not grouped[first_char_upper] then
            grouped[first_char_upper] = {}
        end
        grouped[first_char_upper][key] = value
    end
    return grouped, select_number
end

function InformationManager:onShowInformationManager(module_options)
    --[[
    Call example:

    KOR.informationmanager:onShowInformationManager({
        db_table = self.substitutions_table,
        dialog_title = "Snippets",
        item_hint = "snippet-naam",
        item_name = "snippet",
        value_hint = "snippet-tekst",
        after_save_callback = function(modified_list)
            self.substitutions = modified_list
        end
    })
    ]]

    KOR.dialogsqueue:register({
        id = "information_manager",
        restore = function()
            self:onShowInformationManager(module_options)
        end,
    })

    if module_options.select_number then
        KOR.registry:set("force_select_number", module_options.select_number)
    end

    self:initModuleProps(module_options)

    local result = self:loadInformation()
    if self.manager_instance then
        UIManager:close(self.manager_instance)
        self.manager_instance = nil
    end
    if not result then
        self:showAddDialog()
        return
    end

    self:populateInformationItems(result)
    if #self.information_items == 0 then
        return
    end

    self.manager_instance = CenterContainer:new{
        dimen = Screen:getSize(),
        modal = true,
    }

    local config = {
        title = module_options.dialog_title,
        show_parent = self.manager_instance,
        parent = self,
        fullscreen = true,
        covers_fullscreen = true,
        has_close_button = true,
        is_popout = false,
        is_borderless = true,
        -- #((set menu page which was active before add/edit))
        menu_page = self.current_menu_page,
        onMenuHold = self.onMenuHold,
        item_table = self.information_items,
        top_buttons_left = module_options.top_buttons_left,
        footer_buttons_right = {
            KOR.buttoninfopopup:forSnippetsAdd({
                callback = function()
                    self:showAddDialog()
                end,
            }),
        },
        items_per_page = self.items_per_page,
        _manager = self,
    }
    self.manager_instance_inner_menu = Menu:new(config)
    table_insert(self.manager_instance, self.manager_instance_inner_menu)
    self.manager_instance_inner_menu.close_callback = function()
        UIManager:close(self.manager_instance)
        KOR.dialogs:unregisterWidget(self.manager_instance)
        self.manager_instance = nil
    end
    UIManager:show(self.manager_instance)
end

function InformationManager:onMenuHold(item)
    self._manager:showEditDialog(item)
end

--- @private
function InformationManager:initModuleProps(module_options)

    self.module_options = module_options

    local props = {
        "after_save_callback",
        "db_table",
        "dialog_title",
        "item_hint",
        "item_name",
        "value_hint",
    }
    count = #props
    local prop
    for i = 1, count do
        prop = props[i]
        self[prop] = module_options[prop]
    end
end

--- @private
function InformationManager:storeCurrentMenuPage()
    self.current_menu_page = KOR.registry:get("menu_active_page")
end

--- @private
function InformationManager:showAddDialog()
    KOR.dialogsqueue:register({
        id = "information_manager_add",
        restore = function()
            self:showAddDialog()
        end,
    })
    self:storeCurrentMenuPage()
    UIManager:close(self.manager_instance)
    local dialog
    local item_name = self.item_name
    dialog = MultiInputDialog:new{
        title = _(T("Add %1", item_name)),
        --* to prevent replacement of snippets in the snippet editor fields:
        is_snippet_dialog = self.item_name == "snippet",
        fullscreen = true,
        fields = {
            {
                text = "",
                hint = self.item_hint,
                focused = true,
                allow_newline = false,
                scroll = false,
            },
            {
                text = "",
                hint = self.value_hint,
                height = "auto",
                allow_newline = true,
                scroll = true,
            },
        },
        buttons = {{
            {
                icon = "back",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                icon = "save",
                callback = function()
                    self:saveNewItem(dialog)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- @private
function InformationManager:showEditDialog(item)

    KOR.dialogsqueue:register({
        id = "information_manager_edit",
        restore = function()
            self:showEditDialog(item)
        end,
    })
    self:storeCurrentMenuPage()

    KOR.system:inhibitInputOnGesture()

    local table_id = item.table_id
    local nr = item.nr
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Edit") .. " " .. self.item_name,
        --* to prevent replacement of snippets for the snippet editor field:
        is_snippet_dialog = self.item_name == "snippet",
        fullscreen = true,
        --* because list with items is also modal:
        modal = true,
        fields = {
            {
                text = item.name,
                hint = self.item_hint,
                focused = true,
                allow_newline = false,
                cursor_at_end = true,
                scroll = false,
            },
            {
                text = item.information,
                hint = self.value_hint,
                height = "auto",
                allow_newline = true,
                cursor_at_end = true,
                scroll = true,
            },
        },
        buttons = {{
            {
                icon = "back",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                icon = "dustbin",
                callback = function()
                    UIManager:close(dialog)
                    self:deleteItem(nr, table_id)
                end,
            },
            {
                icon = "save",
                callback = function()
                    self:updateItem(dialog, nr, table_id)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- @private
function InformationManager:saveNewItem(dialog)

    local fields = dialog:getFields()
    if self:hasInvalidInput(fields) then
        UIManager:close(dialog)
        return
    end

    local entry_name = fields[1]
    local information = fields[2]
    if self:guardBlockNonUniqueItem(entry_name) then
        return
    end

    UIManager:close(dialog)
    local conn = self:getDBconn("InformationManager:saveNewItem")
    local sql = "INSERT INTO " .. self.db_table .. " (item, information) VALUES (?, ?)"
    local stmt = conn:prepare(sql)
    stmt:reset():bind(entry_name, information):step()
    stmt = self:closeDBstmts(stmt)
    local table_id = KOR.databases:getNewItemId(conn)
    conn = self:closeDBconn(conn)

    local nr = #self.information_items + 1
    self.information_items[nr] = {
        nr = nr,
        mandatory = nr,
        table_id = table_id,
        name = entry_name,
        text = entry_name .. " " .. KOR.icons.arrow_bare .. " " .. information,
        information = information,
        callback = function()
            self.view_nr = nr
            self:showViewDialog()
        end,
    }

    UIManager:close(self.manager_instance)
    self.module_options.select_number = self:updateCaller(entry_name)
    self:onShowInformationManager(self.module_options)
end

--- @private
function InformationManager:deleteItem(nr, table_id)
    local purged_table = {}
    count = #self.information_items
    for i = 1, count do
        if i ~= nr then
            table_insert(purged_table, self.information_items[i])
        end
    end
    self.information_items = purged_table

    local conn = self:getDBconn("InformationManager:deleteItem")
    local sql = "DELETE FROM " .. self.db_table .. " WHERE id = ?"
    local stmt = conn:prepare(sql)
    stmt:reset():bind(table_id):step()
    stmt = self:closeDBstmts(stmt)
    conn = self:closeDBconn(conn)

    UIManager:close(self.manager_instance)
    self.module_options.select_number = self:updateCaller()
    self:onShowInformationManager(self.module_options)
end

--- @private
function InformationManager:hasInvalidInput(fields)
    local delay = 4
    if has_no_text(fields[1]) then
        KOR.messages:notify("geen geldige naam opgegeven", delay)
        return true
    elseif has_no_text(fields[2]) then
        KOR.messages:notify("geen geldige waarde opgegeven", delay)
        return true
    end

    return false
end

--- @private
function InformationManager:updateItem(dialog, nr, table_id)
    local fields = dialog:getFields()
    if self:hasInvalidInput(fields) then
        UIManager:close(dialog)
        return
    end

    local updated_entry_name = fields[1]
    local entry_name = self.information_items[nr].name
    if updated_entry_name ~= entry_name and self:guardBlockNonUniqueItem(updated_entry_name) then
        return
    end

    UIManager:close(dialog)
    local information = fields[2]
    self.information_items[nr].name = updated_entry_name
    --! prop text required here, for correct working of Menu:
    self.information_items[nr].text = updated_entry_name .. " " .. KOR.icons.arrow_bare .. " " .. information

    self.information_items[nr].information = information

    local conn = self:getDBconn("InformationManager:saveItem")
    local sql = "UPDATE " .. self.db_table .. " SET item = ?, information = ? WHERE id = ?"
    local stmt = conn:prepare(sql)
    stmt:reset():bind(updated_entry_name, information, table_id):step()
    stmt = self:closeDBstmts(stmt)
    conn = self:closeDBconn(conn)

    UIManager:close(self.manager_instance)

    self.module_options.select_number = self:updateCaller(updated_entry_name)
    self:onShowInformationManager(self.module_options)
end

--- @private
function InformationManager:updateCaller(entry_name)
    if not self.after_save_callback then
        return
    end

    count = #self.information_items
    local list = {}
    for i = 1, count do
        list[self.information_items[i].name] = self.information_items[i].information
    end
    --* return Menu select_number:
    return self.after_save_callback(list, entry_name)
end

--- @private
function InformationManager:showViewDialog()

    self:storeCurrentMenuPage()

    local item = self.information_items[self.view_nr]
    local table_id = item.table_id
    self.view_dialog = KOR.dialogs:textBox({
        title = item.name,
        info = item.information,
        modal = true,
        next_item_callback = function()
            return self:onReadNextItem()
        end,
        prev_item_callback = function()
            return self:onReadPrevItem()
        end,
        buttons_table = {{
            {
                icon = "dustbin",
                callback = function()
                    UIManager:close(self.view_dialog)
                    self:deleteItem(item.table_id, table_id)
                end,
            },
            {
                icon = "edit",
                callback = function()
                    UIManager:close(self.view_dialog)
                    self:showEditDialog(item)
                end,
            },
            {
                icon = "previous",
                callback = function()
                    self:onViewPrevious()
                end,
            },
            {
                icon = "next",
                callback = function()
                    self:onViewNext()
                end,
            },
            {
                icon = "back",
                callback = function()
                    UIManager:close(self.view_dialog)
                end,
            },
        }},
    })
end

function InformationManager:onReadNextItem()
    return self:onViewNext()
end

function InformationManager:onReadNextItemWithAlphaKey()
    return self:onViewNext()
end

function InformationManager:onReadPrevItem()
    return self:onViewPrevious()
end

function InformationManager:onReadPrevItemWithAlphaKey()
    return self:onViewPrevious()
end

function InformationManager:onReadPrevItemWithShiftSpace()
    return self:onViewPrevious()
end

--- @private
function InformationManager:onViewNext()
    UIManager:close(self.view_dialog)
    self.view_nr = self.view_nr + 1 <= #self.information_items and self.view_nr + 1 or 1
    self:showViewDialog()
    return true
end

--- @private
function InformationManager:onViewPrevious()
    UIManager:close(self.view_dialog)
    self.view_nr = self.view_nr - 1 > 0 and self.view_nr - 1 or #self.information_items
    self:showViewDialog()
    return true
end

--- @private
function InformationManager:onViewPreviousWithShiftSpace()
    return self:onViewPrevious()
end

--- @private
function InformationManager:onCloseInformationManager()
    UIManager:close(self.view_dialog)
    UIManager:close(self.manager_instance)
end

--- @private
function InformationManager:closeDBconn(conn)
    if self.db_table == "snippets" then
        return KOR.databases:closeSnippetsConnections(conn)
    end
    return KOR.databases:closeConnections(conn)
end

--- @private
function InformationManager:closeDBstmts(stmt)
    if self.db_table == "snippets" then
        return KOR.databases:closeSnippetsStmts(stmt)
    end
    return KOR.databases:closeStmts(stmt)
end

--- @private
function InformationManager:getDBconn()
    if self.db_table == "snippets" then
        return KOR.databases:getDBconnForSnippets()
    end
    return KOR.databases:getDBconn()
end

return InformationManager
