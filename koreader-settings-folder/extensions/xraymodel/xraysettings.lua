
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local pairs = pairs
local type = type

--* DX.m and therefore DX.m:isPrivateDXversion not yet available here:
local locked_xray_setting_message = IS_AUTHORS_DX_INSTALLATION and "Deze instelling door Dynamic Xray automatisch berekend en kan daarom niet worden aangepast door de gebruiker." or _("This setting will be automatically computed by Dynamic Xray and therefor the user cannot modify it.")

local hotkeys_warning = "\n\n" .. _("NB: updated hotkeys are effective immediately - except possibly when they conflict with other hotkeys in KOReader.")

--- @class XraySettings
--- @field settings_manager SettingsManager
local XraySettings = WidgetContainer:new{
    active_tab = nil,
    key_events = {},
    list_title = _("Dynamic Xray: settings"),
    settings_manager = nil,
    --* the settings in this template will be dynamically read from settings/settings_manager.lua and then stored as props of the current class:
    --! these settings MUST have a locked prop, which is either 0 or 1; if 1, then user cannot modify that setting, because it is a computed property:
    settings_template = {
        batch_count_for_import = {
            value = 5,
            explanation = _("This number determines in how many batches Xray items from other books will be imported. In case of very many items, a higher number here is probably prudent."),
            locked = 0,
            type = "number",
        },
        hk_add_item = {
            value = "A",
            explanation = _("To add a new Xray item, in the Item Viewer, the Items List or the Page Navigator.") .. hotkeys_warning,
            locked = 0,
        },
        hk_edit_item = {
            value = "E",
            explanation = _("To edit the current Xray item in the Item Viewer or the Page Navigator.") .. hotkeys_warning,
            locked = 0,
        },
        hk_show_list = {
            value = "L",
            explanation = _("To open the Items List. Available in the Item Viewer, the Page Navigator and the Page Information Popup.") .. hotkeys_warning,
            locked = 0,
        },
        hk_goto_next_item = {
            value = "N",
            explanation = _("To go to the next item in a DX dialog where the triangle pointing to the right is visible.") .. hotkeys_warning,
            locked = 0,
        },
        hk_open_chapter_from_viewer = {
            value = "O",
            explanation = _("To open a specific chapter in the ebook from the Item Viewer.") .. hotkeys_warning,
            locked = 0,
        },
        hk_open_page_navigator_from_list = {
            value = "N",
            explanation = _("To open the Page Navigator from the Items List. The List will be closed.") .. hotkeys_warning,
            locked = 0,
        },
        hk_open_export_list = {
            value = "X",
            explanation = "Opens a popup with all Xray items as sorted in the Items List and with info per item as shown in Page Information Popup. For copying and then printing, if you like." .. hotkeys_warning,
            locked = 0,
        },
        hk_open_xray_settings_from_page_navigator = {
            value = "S",
            explanation = _("To open the XraySettings from Page Navigator.") .. hotkeys_warning,
            locked = 0,
        },
        hk_page_navigator_jump_to_page_no = {
            value = "U",
            explanation = "Open the dialog for jUmping to a specific page nUmber." .. hotkeys_warning,
            locked = 0,
        },
        hk_page_navigator_popup_menu = {
            value = "M",
            explanation = "Toggle the Page Navigator popup menu with additional actions." .. hotkeys_warning,
            locked = 0,
        },
        hk_show_pagebrowser_from_page_navigator = {
            value = "B",
            explanation = _("To open the pagebrowser popup in the Page Navigator.") .. hotkeys_warning,
            locked = 0,
        },
        hk_goto_previous_item = {
            value = "P",
            explanation = _("To go to the previous item in a DX dialog where the triangle pointing to the left is visible.") .. hotkeys_warning,
            locked = 0,
        },
        hk_show_information = {
            value = "I",
            explanation = _("To show a popup dialog with information about the current DX dialog. Available in dialogs where you see an information icon.") .. hotkeys_warning,
            locked = 0,
        },
        hk_show_item_occurrences = {
            value = "S",
            explanation = _("To show the occurrences in the ebook of the current item in the Item Viewer, of in the Tapped Word Popup.") .. hotkeys_warning,
            locked = 0,
        },
        hk_show_list_filter_dialog = {
            value = "F",
            explanation = _("If a filter icon is shown in te left side of a list footer, you can use this hotkey to call up a dialog for filtering that list.") .. hotkeys_warning,
            locked = 0,
        },
        hk_view_item_from_list_or_navigator = {
            value = "V",
            explanation = _("To view the details of the current item in the Items List or in the Page Navigator.") .. hotkeys_warning,
            locked = 0,
        },
        is_android = {
            value = false,
            explanation = _("This variabele triggers a number of default settings for Android devices."),
            locked = 0,
        },
        is_mobile_device = {
            value = false,
            explanation = _("This variabele triggers a number of default settings for mobile devices (narrow screens)."),
            locked = 0,
        },
        is_tablet_device = {
            value = false,
            explanation = _("This variabele enables a number of default settings for (horizontally) wide devices, e.g. the Boox Go 10.3."),
            locked = 0,
        },
        is_ubuntu = {
            value = false,
            explanation = _("This variables enables a number of default settings for KOReader onder Ubuntu, e.g. that the user can close some dialogs with ESC."),
            locked = 0,
        },
        PN_infopanel_description_indent = {
            value = 10,
            explanation = _("This variables enables the numbers of spaces used to indent the item description in the PN item info panel at the bottom."),
            locked = 0,
            validator = {
                name = "infopanel_description_indent",
                min_value = 1,
                max_value = 20,
                default_value = 10,
                value_step = 1,
            },
            type = "number",
            after_change_callback = "reset_page_navigator_cache",
        },
        PN_infopanel_meta_indent = {
            value = 10,
            explanation = _("This variables enables the numbers of spaces used to indent the item meta information (hits, aliases etc.) in the PN item info panel at the bottom."),
            locked = 0,
            validator = {
                name = "infopanel_meta_indent",
                min_value = 1,
                max_value = 20,
                default_value = 12,
                value_step = 1,
            },
            type = "number",
            after_change_callback = "reset_page_navigator_cache",
        },
        PN_info_panel_height = {
            --* this value is used in ((XrayInfoPanel#generateInfoPanel)):
            value = 0.22,
            --* this validator references a function included in self.validators:
            validator = {
                name = "info_panel_height",
                min_value = 0.1,
                max_value = 0.5,
                default_value = 0.22,
                value_step = 0.01,
            },
            explanation = _("Page Navigator: this setting, a fraction between 0.1 and 0.8, determines the height of the bottom info panel relative to the screen height."),
            locked = 0,
            type = "number",
            after_change_callback = "reload_page_navigator",
        },
        PN_info_panel_max_line_length = {
            value = 70,
            explanation = "Page Navigator: this setting determines the max line length for information in the bottom info panel. You can use this to prevent ugly soft line wraps.",
            locked = 0,
            type = "number",
            after_change_callback = "reset_page_navigator_cache",
        },
        -- #((non_filtered_items_layout))
        --* consumed in ((XrayPages#activateNonFilteredItemsLayout)):
        PN_non_filtered_items_layout = {
            value = "small-caps-italic",
            options = { "small-caps", "small-caps-italic", "bold", },
            explanation = _("Page Navigator: when an item filter is set, the non-matching Xray items in the page will be marked with this lay-out."),
            locked = 0,
        },
        PN_panels_font_size = {
            value = 14,
            explanation = _("Page Navigator: with this setting you can determine the font size of the side and bottom panels."),
            locked = 0,
            type = "number",
        },
        PN_show_chapter_hits_histogram = {
            value = true,
            explanation = _("Page Navigator: if set to true, at the bottom of the info panel a histogram will be added to show the hits per chapter for the Xray item currently shown in the info panel."),
            locked = 0,
        },
        PN_show_tagged_items_navigation_alert = {
            value = true,
            explanation = _("Page Navigator: if this setting is false, no popup will be shown when you activate tagged items navigation in Page Navigator."),
            locked = 0,
        },
        SeriesManager_all_data_imported = {
            value = false,
            explanation = _("Series Manager: this value will be set to true after you imported all ebooks data into the Series Manager (via the import icon in the top left of Series Manager dialogs). You can reset this to false if you wish to re-import the data."),
            locked = 0,
            after_change_callback = "series_manager_reload",
        },
        SeriesManager_columns_count = {
            value = 2,
            options = { 2, 3 },
            explanation = "Series Manager: determines in how many columns the items will be shown. The larger value can result in some lay-out issues",
            locked = 0,
            type = "number",
            after_change_callback = "series_manager_reload",
        },
        SeriesManager_mark_active_title_with_border = {
            value = true,
            explanation = _("Series Manager: if set to true, the current book will be highlighted with a border around it."),
            locked = 0,
            after_change_callback = "series_manager_reload",
        },
        SeriesManager_max_title_length = {
            value = 40,
            explanation = _("Series Manager: if a title is longer than this value, it will be truncated with an ellipsis to this max length."),
            locked = 0,
            type = "number",
            after_change_callback = "series_manager_reload",
        },
        UI_mode = {
            value = "page",
            options = { "page", "paragraph" },
            explanation = _("This setting determines whether Xray items in a page are shown with one lightning marker for the entire page or star markers for each of the paragraphs with items."),
            locked = 0,
        },
    },
    settings_template_for_public_DX = {
        database_filename = {
            value = "bookinfo_cache.sqlite3",
            explanation = _("Only change this setting if your database file not is called \"bookinfo_cache.sqlite3\". E.g. because it has a language code at the front, like \"PT_bookinfo_cache.sqlite3\"."),
            locked = 0,
        },
        --* this setting controls database scheme modifications via ((XrayDataSaver#createAndModifyTables)) > ((XrayDataSaver#modifyTables)) > XrayDataSaver.scheme_alter_queries:
        database_scheme_version = {
            value = 0,
            explanation = _("This setting detemines which tasks to update the database scheme should be executed. Most times it is best to leave this value untouched. But suppose for some reason you deleted a table, you can then set this to a lower value, to let XrayDataSaver re-create the table. USE WITH EXTREME CAUTION!"),
            locked = 0,
        },
        prune_orphan_translations_version = {
            value = 1,
            explanation = locked_xray_setting_message,
            locked = 1,
        },
        tables_created = {
            value = false,
            explanation = _("This settings should be set to true by DX after its tables have been created.\n\nYou can set it to false to try to recreate the DX tables (after you manually deleted them from the database), in case of problems."),
            locked = 0,
        },
    },
    tabbed_interface = nil,
    tab_labels = {
        "1. " .. _("general"),
        "2. " .. _("hotkeys"),
        "3. " .. _("system"),
    },
    after_change_callbacks = {
        reload_page_navigator = function()
            DX.pn:reloadPageNavigator()
        end,
        reset_page_navigator_cache = function()
            DX.c:resetDynamicXray()
            DX.pn:closePageNavigator()
            KOR.dialogs:closeAllOverlays()
        end,
        series_manager_reload = function()
            KOR.seriesmanager:reloadContextDialog()
        end,
    },
    validators = {
        info_panel_height = function(value)
            return type(value) == "number" and value >= 0.1 and value <= 0.5 or _("a valid value should lie between 0.1 and 0.5...")
        end,
        item_info_indent = function(value)
            --* so we immediately will see the new indentation:
            DX.pn:resetCache("do_limited_refresh")
            return type(value) == "number" and value >= 4 and value <= 14 or _("a valid value should lie between 4 and 14...")
        end,
    },
}

function XraySettings:setUp()

    --* DX.m and therefore DX.m:isPrivateDXversion not yet available here:
    if not IS_AUTHORS_DX_INSTALLATION then
        for key, props in pairs(self.settings_template_for_public_DX) do
            self.settings_template[key] = props
        end
    end

    self.settings_manager = KOR.settingsmanager:new({
        list_title = _("Dynamic Xray"),
        parent = self,
        settings_index = "xray_settings",
    })
    self.settings_manager:setUp(self.tab_labels)
end

-- #((XraySettings#showSettingsManager))
function XraySettings.showSettingsManager(active_tab)

    local self = DX.s
    if self.tabbed_interface then
        UIManager:close(self.tabbed_interface)
        self.tabbed_interface = nil
    end
    if not active_tab then
        active_tab = 1
    end
    self.active_tab = active_tab

    self.settings_manager:setProp("active_tab", active_tab)
    self.tabbed_interface = KOR.tabbedlist:create({
        caller = self,
        caller_method = self.showSettingsManager,
        menu_manager = self.settings_manager,
        top_buttons_left = {
            {
                icon = "info-slender",
                callback = function()
                    return self.settings_manager:showSettingsManagerInfo()
                end,
            },
        },
        populate_tab_items_callback = function()
            self.settings_manager:updateItemTableForTab()
        end,
    })
    UIManager:show(self.tabbed_interface)
end

function XraySettings:toggleSetting(key, alternatives)
    local new_index
    for i = 1, 2 do
        if self[key] == alternatives[i] then
            new_index = i == 1 and 2 or 1
            self[key] = alternatives[new_index]
            self.settings_manager:saveSettings()
            break
        end
    end
end

function XraySettings:saveSetting(key, value)
    if KOR.dialogs then
        KOR.dialogs:closeAllOverlays()
    end
    local self = DX.s
    self.settings_manager:saveSetting(key, value)
end

return XraySettings
