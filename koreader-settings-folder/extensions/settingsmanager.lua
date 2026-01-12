
local require = require

local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local KOR = require("extensions/kor")
local LuaSettings = require("luasettings")
local Menu = require("extensions/widgets/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen
local T = require("ffi/util").template

local DX = DX
local G_reader_settings = G_reader_settings
local has_text = has_text
local math_floor = math.floor
local pairs = pairs
local table = table
local table_insert = table.insert
local tonumber = tonumber
local tostring = tostring
local type = type

local count

--- @class SettingsManager
--- @field parent XraySettings
local SettingsManager = WidgetContainer:new{
    active_tab = nil,
    filtered_settings = {},
    items_per_page = G_reader_settings:readSetting("items_per_page") or 14,
    item_table = nil,
    list_title = nil,
    parent = nil,
    --* this prop will be populated from an item with name specified in settings_index below in settings/settings_manager.lua:
    settings = {},
    settings_db = nil,
    settings_index = nil,
    settings_for_menu = {},
    --! parent must have a prop settings_template, in this format:
    --[[
    settings_template = {
        is_mobile_device = {
            value = false,
            explanation = "Deze variabele regelt een aantal standaard instellingen voor smalle schermen",
            locked = 0, --* or 1, for computed props
            options = { 0, 1 } --* optional, for fixed options
        },
    }
    ]]
    --* set by caller:
    tab_labels = nil,
}

--! don't call this method "init", because then ((KOR#initExtensions)) could call this method prematurely:
function SettingsManager:setUp(tab_labels)
    if not self.tab_labels then
        self.tab_labels = tab_labels
        self.settings_db = LuaSettings:open(DataStorage:getSettingsDir() .. "/settings_manager.lua")
        if self.settings_db then
            if not KOR.tables then
                KOR.tables = require("extensions/tables")
            end
            self.settings = self.settings_db:readSetting(self.settings_index)
        end
        self:updateSettingsFromTemplate()
    end

    local locked_indicator
    for key, props in pairs(self.settings) do
        self.parent[key] = props.value
        locked_indicator = props.locked == 1 and " " .. KOR.icons.lock_bare or ""
        table_insert(self.settings_for_menu, {
            key = key,
            value = props.value,
            explanation = props.explanation,
            locked = props.locked,
            options = props.options,
            text = key .. ": " .. tostring(props.value) .. locked_indicator }
        )
    end
end

--- @private
function SettingsManager:updateSettingsFromTemplate()
    --* if var set for overruling or settings don't exist yet, generate them (anew):
    if self.settings_db:isTrue(self.settings_index .. "_overrule") or not self.settings then
        if not KOR.tables then
            KOR.tables = require("extensions/tables")
        end
        self.settings = KOR.tables:shallowCopy(self.parent.settings_template)
        self.settings_db:makeFalse(self.settings_index .. "_overrule")
        self:saveSettings()

        return
    end

    --* following the parent's settings template, add settings that were added there, or remove settings that were deleted there:
    local settings_were_added = self:addNewSettingsOrHelpTextsFromTemplate()
    local settings_were_deleted = self:removeSettingsFromTemplate()
    if settings_were_added or settings_were_deleted then
        self:saveSettings()
    end
end

--- @private
function SettingsManager:addNewSettingsOrHelpTextsFromTemplate()
    local settings_were_updated = false
    for key, props in pairs(self.parent.settings_template) do
        --* add missing settings from template:
        if not self.settings[key] then
            self.settings[key] = props
            settings_were_updated = true

            --* add updated explanations from template:
        elseif self.settings[key].explanation ~= props.explanation then
            self.settings[key].explanation = props.explanation
            settings_were_updated = true
        end
    end
    return settings_were_updated
end

--- @private
function SettingsManager:removeSettingsFromTemplate()
    local settings_were_deleted = false
    for key in pairs(self.settings) do
        if not self.parent.settings_template[key] and key ~= "database_filename" then
            self.settings[key] = nil
            settings_were_deleted = true
        end
    end
    return settings_were_deleted
end

function SettingsManager:showParentDialog()
    self.parent.showSettingsManager(self.active_tab, self.tab_labels)
end

function SettingsManager:getTabContent(caller_method, active_tab)
    self.active_tab = active_tab

    local dimen = Screen:getSize()
    self.settings_dialog = CenterContainer:new{
        dimen = dimen,
        modal = true,
    }
    self.width = math_floor(dimen.w * 0.8)
    local tab_label_fontsize = 16
    self.settings_menu = Menu:new{
        title_submenu_buttontable = KOR.tabfactory:generateTabButtons(caller_method, self.active_tab, self.tab_labels, self.width, tab_label_fontsize),
        show_parent = self.ui,
        height = math_floor(dimen.h * 0.8),
        width = self.width,
        is_borderless = false,
        is_popout = true,
        fullscreen = false,
        with_bottom_line = true,
        perpage = self.items_per_page,
        top_buttons_left = {
            {
                icon = "info-slender",
                callback = function()
                    KOR.dialogs:niceAlert(_("Settings management"), T(_([[Here you can modify settings for %1.

Items with an %2 are computed settings, which you can't modify manually.
If you longpress a setting, you'll see an explanation of that setting.]]), self.list_title, KOR.icons.lock_bare))
                end,
            },
        },
        after_close_callback = function()
            KOR.dialogs:closeOverlay()
        end,
        onMenuHold = self.onMenuHoldSettings,
        _manager = self,
    }
    table_insert(self.settings_dialog, self.settings_menu)
    self.settings_menu.close_callback = function()
        UIManager:close(self.settings_dialog)
        KOR.dialogs:closeOverlay()
    end
    self:updateItemTable()
    self.settings_menu:switchItemTable(self.list_title .. ": instellingen", self.item_table)

    return self.settings_dialog
end

--- @private
function SettingsManager:sortMenuItems()
    table.sort(self.settings_for_menu, function(v1, v2)
        local locked1 = v1.locked or 0
        local locked2 = v2.locked or 0
        if locked1 ~= locked2 then
            return locked1 < locked2
        end

        local key1 = v1.key or ""
        local key2 = v2.key or ""
        return key1 < key2
    end)
end

--- @private
function SettingsManager:updateItemTable()
    self:sortMenuItems()
    self.item_table = {}
    count = #self.settings_for_menu
    local item, is_hotkey
    local list_no = 0
    local not_editable_message = _("this setting cannot be modified by the user...")
    for nr = 1, count do
        local setting = self.settings_for_menu[nr]
        is_hotkey = setting.text:match("^hk_")
        if
        (self.active_tab == 1 and setting.locked == 0 and not is_hotkey)
                or (self.active_tab == 2 and is_hotkey)
                or (self.active_tab == 3 and setting.locked == 1)
        then
            setting.type = type(setting.value)
            local current_nr = nr
            list_no = list_no + 1
            item = {
                text = KOR.strings:formatListItemNumber(list_no, self:removeHotkeyPrefix(setting.text)),
                key = setting.key,
                explanation = setting.explanation,
                editable = true,
                deletable = false,
                callback = function()
                    if setting.locked == 1 then
                        self:showParentDialog()
                        KOR.messages:notify(not_editable_message)
                        return
                    end
                    self:editSetting(setting, current_nr)
                end
            }
            table_insert(self.item_table, item)
        end
    end
end

--- @private
function SettingsManager:onMenuHoldSettings(item)
    --- @type SettingsManager manager
    local manager = self._manager
    KOR.dialogs:niceAlert(manager:removeHotkeyPrefix(item.key), item.explanation)
    return true
end

--- @private
function SettingsManager:chooseSetting(key, current_nr, current_value, options, explanation)
    local has_boolean_options = type(current_value) == "boolean" and not options
    if has_boolean_options then
        options = { true, false }
    end
    count = #options
    local buttons = { {} }
    local marker
    for i = 1, count do
        marker = options[i] == current_value and KOR.icons.active_tab_bare or ""
        local current = i
        table_insert(buttons[1], {
            text = marker .. tostring(options[current]),
            font_bold = false,
            callback = function()
                UIManager:close(self.option_chooser)
                self:saveSetting(key, options[current])
                self:changeMenuSetting(key, options[current], current_nr)
                KOR.messages:notify(_("setting ") .. key .. _(" modified to ") .. tostring(options[current]), 4)
                self:showParentDialog()
            end
        })
    end
    table_insert(buttons[1], {
        icon = "back",
        callback = function()
            UIManager:close(self.option_chooser)
            self:showParentDialog()
        end
    })
    self.option_chooser = ButtonDialogTitle:new{
        title = key,
        subtitle = explanation,
        button_font_bold = false,
        buttons = buttons,
    }
    KOR.dialogs:showDialogOnTopOfOverlay(function()
        UIManager:show(self.option_chooser)
    end)
end

--- @private
function SettingsManager:editSetting(settings, current_nr)
    local key = settings.key
    local value = settings.value
    local itype = settings.type
    local options = settings.options
    local explanation = settings.explanation
    KOR.dialogs:showOverlay()
    if options or itype == "boolean" then
        self:chooseSetting(key, current_nr, value, options, explanation)
        return
    end

    self:showPromptForNewSettingsValue(key, value, current_nr, itype, explanation)
end

--- @private
function SettingsManager:showPromptForNewSettingsValue(key, value, current_nr, itype, explanation)
    KOR.dialogs:prompt({
        title = self:removeHotkeyPrefix(key),
        allow_newline = false,
        input_type = itype == "number" and "number" or "text",
        description = explanation:gsub("%.$", ""),
        input = tostring(value),
        callback = function(new_value)
            self:handleNewValue(new_value, key, current_nr, itype)
        end,
        cancel_callback = function()
            self:showParentDialog()
        end,
    })
end

--- @private
function SettingsManager:handleNewValue(new_value, key, current_nr, itype)
    local is_valid = false
    if itype == "boolean" and new_value == "true" or new_value == "1" then
        new_value = true
        is_valid = true
    elseif itype == "boolean" and new_value == "false" or new_value == "0" or new_value == "" then
        new_value = false
        is_valid = true
    elseif itype == "number" then
        new_value = tonumber(new_value)
        if new_value then
            is_valid = true
        end
    elseif itype == "string" and has_text(new_value) then
        is_valid = true
    end
    --* ensure hotkeys only have one uppercase character:
    if is_valid and key:match("^hk_") then
        new_value = KOR.strings:upper(new_value):sub(1, 1)
    end
    if not is_valid then
        self:showParentDialog()
        KOR.messages:notify(_("you entered an invalid value..."), 4)
        return
    end
    self:saveSetting(key, new_value)
    self:changeMenuSetting(key, new_value, current_nr)
    KOR.messages:notify(_("settting ") .. key .. _(" modified to ") .. tostring(new_value), 4)
    self:showParentDialog()
end

--- @private
function SettingsManager:changeMenuSetting(key, value, current_nr)
    if not current_nr or not self.settings_for_menu[current_nr] or self.settings_for_menu[current_nr].key ~= key then
        return
    end
    self.settings_for_menu[current_nr].value = value
    self.settings_for_menu[current_nr].text = key .. ": " .. tostring(value)
    self:updateItemTable()
end

---@private
function SettingsManager:removeHotkeyPrefix(text)
    return text:gsub("^hk_", "", 1)
end

--- @private
function SettingsManager:saveSetting(key, value)
    self.parent[key] = value
    self.settings[key].value = value
    self:saveSettings()

    if key == "database_filename" then
        local index = DX.ds.version_index_name
        self.parent[index] = 0
        self.settings[index].value = 0
        self:saveSettings()
        KOR.messages:notify(_("KOReader will be reloaded now..."))
        UIManager:scheduleIn(2, function()
            if KOR.ui.document then
                KOR.ui:reloadDocument()
            end
        end)
        return
    end

    --* this method can be called externally, so we need to re-setup:
    self.settings_for_menu = {}
    self:setUp()
end

--- @private
function SettingsManager:saveSettings()
    self.settings_db:saveSetting(self.settings_index, self.settings)
    self.settings_db:flush()
end

return SettingsManager
