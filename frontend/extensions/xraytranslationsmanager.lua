--[[--
This extension is part of the Dynamic Xray plugin; it initializes translations for all view related modules. The translations are stored in the database.

New translations encountered in the code will be automatically/lazily added to the database.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XrayTappedWords)) and ((XrayViewsData)), ((XrayTranslations))
V = ((XrayUI)), ((XrayTranslations)), ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local Button = require("extensions/widgets/button")
local ButtonDialog = require("extensions/widgets/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local InputDialog = require("extensions/widgets/inputdialog")
local KOR = require("extensions/kor")
local Menu = require("extensions/widgets/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local ipairs = ipairs
local table = table

--- @class XrayTranslationsManager
local XrayTranslationsManager = WidgetContainer:new{
    current_translation_nr = 1,
    filtered_translations = {},
    filter_state = "unfiltered",
    filter_string = "",
    translated_indicator = "✓",
    translations = {},
    translations_chooser_dialog = nil,
    translations_menu = nil,
    translations_table = {},
    items_per_page = G_reader_settings:readSetting("items_per_page") or 14,
    previous_filter = "",
}

--* called at end of ((XrayTranslations#loadAllTranslations)):
function XrayTranslationsManager:setTranslations(translations)
    self.translations = translations
end

--* used for backward and forward navigation through ideas:
--- @private
function XrayTranslationsManager:populateForNavigation(translation)
    local translations_source = self.translations
    local use_filter = self.filter_string:len() >= 3
    if not use_filter and #self.translations > 0 then
        return translations_source
    end
    if #self.filtered_translations > 0 then
        translations_source = self.filtered_translations
    elseif use_filter then
        self:populateFilteredTranslations(translation)
        translations_source = self.filtered_translations
    end
    return translations_source
end

--- @private
function XrayTranslationsManager:populateFilteredTranslations(translation)
    self.filtered_translations = {}
    local needle = self.filter_string
    for _, itranslation in ipairs(self.translations) do
        local haystack = itranslation.text:lower()
        if haystack:match(needle) then
            table.insert(self.filtered_translations, itranslation)
        end
    end
    if #self.filtered_translations == 0 then
        KOR.messages:notify(_("no translations found with this filter..."), 2)
        self:resetFilteredTranslations(true)
        self:reset()
        self:updateTranslationsTable(translation)
        self:manageTranslations(translation)
    end
end

function XrayTranslationsManager:reset()
    self:resetFilteredTranslations()
end

--- @private
function XrayTranslationsManager:getNextTranslation(translation)
    local translations_source = self:populateForNavigation(translation)
    local next = self.current_translation_nr + 1
    if next > #translations_source then
        next = 1
    end
    self.current_translation_nr = next
    return translations_source[next]
end

--- @private
function XrayTranslationsManager:getPreviousTranslation(translation)
    local translations_source = self:populateForNavigation(translation)
    local previous = self.current_translation_nr - 1
    if previous < 1 then
        previous = #translations_source
    end
    self.current_translation_nr = previous
    return translations_source[previous]
end

function XrayTranslationsManager:manageTranslations(translation)
    KOR.dialogs:showOverlay()
    if self.translations_chooser_dialog then
        UIManager:close(self.translations_chooser_dialog)
    end

    self.translations_chooser_dialog = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.translations_menu = Menu:new{
        show_parent = self.translations_chooser_dialog,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        no_title = false,
        parent = nil,
        has_close_button = true,
        is_popout = false,
        filter = {
            filter = self.filter_string,
            callback = function()
                self.filter_state = "filtered"
                self:setTextFilter()
            end,
            reset_callback = function()
                self.filter_state = "unfiltered"
                self.filter_string = ""
                self:reset()
                self:manageTranslations()
            end,
            hold_callback = function()
                self.filter_state = "filtered"
                self:setTextFilter("reset")
            end,
        },
        top_buttons_left = {
            KOR.buttoninfopopup:forTranslationsResetAll({
                callback = function()
                    KOR.dialogs:confirm(_("Do you indeed want to reset ALL translations to their untranslated original texts (in English)?\n\nNB: already translated texts will NOT be removed."), function()
                        DX.ds:execExternalQuery("XrayTranslationsManager:manageTranslations remove all translations", "remove_all_translations")
                        UIManager:close(self.translations_chooser_dialog)
                        DX.t:loadAllTranslations()
                        KOR.messages:notify(_("all translations removed..."))
                    end)
                end
            })
        },
        covers_fullscreen = true,
        is_borderless = true,
        onMenuHold = self.onMenuHold,
        perpage = self.items_per_page,
        _manager = self,
    }
    table.insert(self.translations_chooser_dialog, self.translations_menu)
    self.translations_menu.close_callback = function()
        UIManager:close(self.translations_chooser_dialog)
        KOR.dialogs:unregisterWidget(self.translations_chooser_dialog)
        self.translations_chooser_dialog = nil
    end
    local success = self:updateTranslationsTable(translation)
    if success then
        UIManager:show(self.translations_chooser_dialog)
        KOR.dialogs:registerWidget(self.translations_menu)
    end
end

--- @private
function XrayTranslationsManager:updateTranslationsTable(translation)
    local translations = self:populateForNavigation(translation)
    if #translations == 0 then
        return
    end
    local item_table = {}
    local title
    for nr, item in ipairs(translations) do
        local menu_item = DX.t:generateItemForManagerList(item, nr)
        menu_item.callback = function()
            UIManager:close(self.translations_menu)
            self:showTranslation(menu_item)
        end
        table.insert(item_table, menu_item)
    end

    title = _("Manage") .. " "
    if self.filter_string:len() >= 3 then
        --* when no translations found with the current filter:
        if #self.filtered_translations == 0 then
            KOR.messages:notify(T(_("no translations found with \"%1\"..."), self.filter_string), 2)
            self:reset()
            self:manageTranslations()
            return
        end
        title = title .. #self.filtered_translations .. _(" translations") .. " - " .. self.filter_string
    else
        title = title .. #translations .. _(" translations")
    end

    if translation then
        if self.translations_menu then
            --* goto page where recently displayed translation can be found in the manager:
            self.translations_menu:switchItemTable(title, item_table, nil, translation)
        else
            self:manageTranslations()
        end
    else
        if self.translations_menu then
            --* self.current_translation_nr > try to stay on current page:
            self.translations_menu:switchItemTable(title, item_table, self.current_translation_nr)
        else
            self:manageTranslations()
        end
    end
    return true
end

--- @private
function XrayTranslationsManager:resetFilteredTranslations(reset_filters)
    if reset_filters then
        self.filter_string = ""
    end
    self.filtered_translations = {}
end

--- @private
function XrayTranslationsManager:showTranslation(translation)
    self:closeListDialog()
    if self.translation_viewer then
        UIManager:close(self.translation_viewer)
        self.translation_viewer = nil
    end
    local translations = #self.filtered_translations > 0
            and self.filtered_translations
            or self.translations
    if not translation then
        translation = translations[self.current_translation_nr]
    end
    self.current_translation_nr = translation.translation_nr
    local title = _("Translation ") .. self.current_translation_nr .. "/" .. #translations
    if translation.is_translated == 1 then
        title = title .. "  -  " .. self.translated_indicator
    end

    self.translation_viewer = KOR.dialogs:textBox({
        title = title,
        info = KOR.strings:prepareForDisplay(translation.viewer_text),
        narrow_text_window = true,
        use_computed_height = true,
        text_padding_top_bottom = Screen:scaleBySize(25),
        next_item_callback = function()
            self:showNextTranslation()
        end,
        prev_item_callback = function()
            self:showPreviousTranslation()
        end,
        buttons_table = DX.b:forTranslationViewer(self, translation)
    })
end

function XrayTranslationsManager:closeListDialog()
    if self.translations_chooser_dialog then
        UIManager:close(self.translations_chooser_dialog)
        self.translations_chooser_dialog = nil
    end
end

function XrayTranslationsManager:onMenuHold(item)
    self.translations_manipulate_dialog = ButtonDialog:new{
        buttons = DX.b:forTranslationsContextDialog(self, item),
    }
    UIManager:show(self.translations_manipulate_dialog)
end

function XrayTranslationsManager:editNextTranslation(translation)
    UIManager:close(self.translation_viewer)
    self:editTranslation(self:getNextTranslation(translation))
end

function XrayTranslationsManager:editPreviousTranslation(translation)
    UIManager:close(self.translation_viewer)
    self:editTranslation(self:getPreviousTranslation(translation))
end

--- @private
function XrayTranslationsManager:showNextTranslation(translation)
    UIManager:close(self.translation_viewer)
    self:showTranslation(self:getNextTranslation(translation))
end

--- @private
function XrayTranslationsManager:showPreviousTranslation(translation)
    UIManager:close(self.translation_viewer)
    self:showTranslation(self:getPreviousTranslation(translation))
end

function XrayTranslationsManager:editTranslation(item)
    if self.edit_translation_input then
        UIManager:close(self.edit_translation_input)
    end
    self.edit_translation_input = InputDialog:new{
        title = _("Edit translation"),
        input = item.msgstr,
        input_type = "text",
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = true,
        force_no_navbar = true,
        top_buttons_left = {
            Button:new({
                icon = "info",
                icon_size_ratio = 0.5,
                callback = function()
                    KOR.dialogs:htmlBox({
                        title = _("About this editor"),
                        window_size = "medium",
                        no_buttons_row = true,
                        html = _("<ul style='font-size: 80%'><li>Edit the text and save it...</li><li><strong>Make sure you leave special codes like |, %1, %2 etc. and html tags intact: they are important for correct display of translations.</strong></li><li>Edited and saved translations will be immediately used in the interface.</li><li>Translated items will be marked bold and by a checkmark.</li></ul>"),
                    })
                end,
            }),
            Button:new(KOR.buttoninfopopup:forTranslationEditorResetText({
                callback = function()
                    KOR.dialogs:confirm(_("Are you sure you want to reset the translation?"), function()
                        self.edit_translation_input._input_widget:setText(item.msgid)
                    end)
                end,
            }))
        },
        buttons = DX.b:forTranslationsEditor(self, item),
    }
    UIManager:show(self.edit_translation_input)
    self.edit_translation_input:onShowKeyboard()
end

--- @private
function XrayTranslationsManager:setTextFilter(reset)
    KOR.dialogs:showOverlay()
    self.filter_translations_input = InputDialog:new{
        title = _("Filter for translations"),
        input = reset and "" or self.filter_string,
        input_type = "text",
        allow_newline = false,
        cursor_at_end = true,
        buttons = DX.b:forTranslationsFilter(self),
    }
    UIManager:show(self.filter_translations_input)
    self.filter_translations_input:onShowKeyboard()
end

function XrayTranslationsManager:saveUpdatedTranslation(translation)
    self:closeListDialog()
    local updated_translation = self.edit_translation_input:getInputText()
    self:resetFilteredTranslations()
    UIManager:close(self.edit_translation_input)

    local org_item = KOR.tables:shallowCopy(translation)
    local translations
    translation, translations = DX.t:updateTranslation(translation, updated_translation)
    if not translation then
        self:showTranslation(org_item)
        KOR.messages:notify(_("item couldn't be updated..."))
        return
    end

    self.translations = translations
    self:updateTranslationsTable(translation)
    self:showTranslation()
end

return XrayTranslationsManager
