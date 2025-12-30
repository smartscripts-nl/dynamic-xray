
local require = require

local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local KOR = require("extensions/kor")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen
local T = require("ffi/util").template

local DX = DX
local G_reader_settings = G_reader_settings
local has_text = has_text
local pairs = pairs
local table = table
local tonumber = tonumber
local tostring = tostring
local type = type

local count

--- @class SettingsManager
local SettingsManager = WidgetContainer:new{
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
}

--! don't call this method "init", because then ((KOR#initExtensions)) could call this method prematurely:
function SettingsManager:setUp()
    self.settings_db = LuaSettings:open(DataStorage:getSettingsDir() .. "/settings_manager.lua")
    if self.settings_db then
        self.settings = self.settings_db:readSetting(self.settings_index)
    end

    self:updateSettingsFromTemplate()

    local locked_indicator
    for key, props in pairs(self.settings) do
        self.parent[key] = props.value
        locked_indicator = props.locked == 1 and " " .. KOR.icons.lock_bare or ""
        table.insert(self.settings_for_menu, { key = key, value = props.value, explanation = props.explanation, locked = props.locked, options = props.options, text = key .. ": " .. tostring(props.value) .. locked_indicator })
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
    if
        self:addNewSettingsFromTemplate()
        or
        self:removeSettingsFromTemplate()
    then
        self:saveSettings()
    end
end

--- @private
function SettingsManager:addNewSettingsFromTemplate()
    local settings_were_added = false
    for key, props in pairs(self.parent.settings_template) do
        if not self.settings[key] then
            self.settings[key] = props
            settings_were_added = true
        end
    end
    return settings_were_added
end

--- @private
function SettingsManager:removeSettingsFromTemplate()
    local settings_were_deleted = false
    for key in pairs(self.settings) do
        if not self.parent.settings_template[key] then
            self.settings[key] = nil
            settings_were_deleted = true
        end
    end
    return settings_were_deleted
end

function SettingsManager:show()
    self.settings_dialog = CenterContainer:new{
        dimen = Screen:getSize(),
        modal = true,
    }
    self.settings_menu = Menu:new{
        show_parent = self.ui,
        fullscreen = true,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        perpage = self.items_per_page,
        top_buttons_left = {
            {
                icon = "info-slender",
                callback = function()
                    KOR.dialogs:niceAlert(_("Settings management"), T(_([[Here you can modify settings for %1.

Items with an %2 are computed settings, which you can't modify manually.
If you longpress a setting, you'll see an explanation of that setting.]]), self.list_title, KOR.icons.lock_bare))
                end,
            }
        },
        after_close_callback = function()
            KOR.dialogs:closeOverlay()
        end,
        onMenuHold = self.onMenuHoldSettings,
        _manager = self,
    }
    table.insert(self.settings_dialog, self.settings_menu)
    self.settings_menu.close_callback = function()
        UIManager:close(self.settings_dialog)
    end
    self:updateItemTable()
    self.settings_menu:switchItemTable(self.list_title .. ": " .. _("settings"), self.item_table)
    UIManager:show(self.settings_dialog)
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
    if count > 0 then
        local item
        for nr = 1, count do
            local setting = self.settings_for_menu[nr]
            setting.type = type(setting.value)
            local current_nr = nr
            item = {
                text = KOR.strings:formatListItemNumber(nr, setting.text),
                key = setting.key,
                explanation = _(setting.explanation),
                editable = true,
                deletable = false,
                callback = function()
                    if setting.locked == 1 then
                        self:show()
                        KOR.messages:notify(_("this setting cannot be modified by the user..."))
                        return
                    end
                    self:editSetting(setting, current_nr)
                end
            }
            table.insert(self.item_table, item)
        end
    end
end

--- @private
function SettingsManager:onMenuHoldSettings(item)
    KOR.dialogs:niceAlert(item.key, item.explanation)
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
        table.insert(buttons[1], {
            text = marker .. tostring(options[current]),
            font_bold = false,
            callback = function()
                UIManager:close(self.option_chooser)
                self:saveSetting(key, options[current])
                self:changeMenuSetting(key, options[current], current_nr)
                KOR.messages:notify(_("setting ") .. key .. _(" modified to ") .. tostring(options[current]), 4)
            end
        })
    end
    table.insert(buttons[1], {
        icon = "back",
        callback = function()
            UIManager:close(self.option_chooser)
            self:show()
        end
    })
    self.option_chooser = ButtonDialogTitle:new{
        title = key,
        subtitle = explanation,
        button_font_bold = false,
        buttons = buttons,
    }
    UIManager:show(self.option_chooser)
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

    self:showPromptForNewSetting(key, value, current_nr, itype, explanation)
end

function SettingsManager:showPromptForNewSetting(key, value, current_nr, itype, explanation)
    KOR.dialogs:prompt({
        title = key,
        allow_newline = false,
        input_type = itype == "number" and "number" or "text",
        description = _("Explanation:\n") .. KOR.strings:lowerFirst(explanation):gsub("%.$", ""),
        input = tostring(value),
        callback = function(new_value)
            self:handleNewValue(new_value, key, current_nr, itype)
        end,
        cancel_callback = function()
            self:show()
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
    if not is_valid then
        self:show()
        KOR.messages:notify(_("you entered an invalid value..."), 4)
        return
    end
    self:saveSetting(key, new_value)
    self:changeMenuSetting(key, new_value, current_nr)
    KOR.messages:notify(_("settting ") .. key .. _(" modified to ") .. tostring(new_value), 4)
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
