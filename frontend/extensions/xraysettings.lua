--[[--
This extension is part of the Dynamic Xray plugin; it has buttons which are generated for dialogs and forms in XrayController and its other extensions.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

--local locked_xray_setting_message = _("This setting will be automatically computed by Dynamic Xray and therefor the user cannot modify it.")

--- @class XraySettings
--- @field settings_manager SettingsManager
local XraySettings = WidgetContainer:new{
    settings_manager = nil,
    --* the settings in this template will be dynamically read from settings/settings_manager.lua and then stored as props of the current class:
    --! these settings MUST have a locked prop, which is either 0 or 1; if 1, then user cannot modify that setting, because it is a computed property:
    settings_template = {
        batch_count_for_import = {
            value = 5,
            explanation = "This number determines in how many batches Xray items from other books will be imported. In case of very many items, a higher number here is probably prudent.",
            locked = 0,
        },
        database_filename = {
            value = "bookinfo_cache.sqlite3",
            explanation = _("Only change this setting if your database file in the KOReader settings folder has a language code at the start. E.g. like \"PT_bookinfo_cache.sqlite3\"."),
            locked = 0,
        },
        editor_vertical_align_buttontable = {
            value = false,
            explanation = "If set to true, DX tries to vertically align the buttontable in the Xray item editor, so that it is shown just above the keyboard. On some e-readers this can lead to the problem that the buttons aren't visible anymore! In that case set this setting to false.",
            locked = 0,
        },
        is_android = {
            value = false,
            explanation = "This variabele triggers a number of default settings for Android devices.",
            locked = 0,
        },
        is_mobile_device = {
            value = false,
            explanation = "This variabele triggers a number of default settings for mobile devices (narrow screens).",
            locked = 0,
        },
        is_tablet_device = {
            value = false,
            explanation = "This variabele enables a number of default settings for (horizontally) wide devices, e.g. the Boox Go 10.3.",
            locked = 0,
        },
        is_ubuntu = {
            value = false,
            explanation = "This variables enables a number of default settings for KOReader onder Ubuntu, e.g. that the user can close some dialogs with ESC.",
            locked = 0,
        },
        ui_mode = {
            value = "page",
            options = { "page", "paragraph" },
            explanation = "This setting determines whether Xray items in a page are shown with one lightning marker for the entire page or star markers for each of the paragraphs with items.",
            locked = 0,
        },
    },
}

--! don't call this method "init", because then ((KOR#initExtensions)) could call this method prematurely; we want ((KOR#registerXrayModules)) to call this method:
function XraySettings:setUp()
    self.settings_manager = KOR.settingsmanager:new({
        list_title = _("Dynamic Xray"),
        parent = self,
        settings_index = "xray_settings",
    })
    self.settings_manager:setUp()
end

function XraySettings:showSettingsManager()
    self.settings_manager:show()
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

return XraySettings
