--[[--
This extension is part of the Dynamic Xray plugin; it has all dialogs and forms (including their callbacks) which are used in XrayController and its other extensions.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! counts of items per tab (all, persons, terms) determined in ((XrayButtons#getListSubmenuButton)). Reset filter callback for this filter: ((XrayDialogs#getListFilter)) > ((XrayController#resetFilteredItems)) > ((XrayDialogs#showListWithRestoredArguments)).


local require = require

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("extensions/widgets/button")
local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Event = require("ui/event")
local Font = require("extensions/modules/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("extensions/widgets/inputdialog")
local KOR = require("extensions/kor")
local Menu = require("extensions/widgets/menu")
local MultiInputDialog = require("extensions/widgets/multiinputdialog")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local math = math
local select = select
local table = table
local tostring = tostring

--- @type XrayTranslations translations
local translations

local count

--- @class XrayDialogs
local XrayDialogs = WidgetContainer:new{
    action_result_message = nil,
    add_item_input = nil,
    called_from_list = false,
    change_xray_type = nil,
    current_tab_items = nil,
    description_field_face = Font:getFace("x_smallinfofont", 19),
    description_field_height = DX.s.is_ubuntu and 180 or 420,
    edit_item_description_dialog = nil,
    edit_item_input = nil,
    filter_icon = nil,
    filter_xray_items_input = nil,
    form_was_cancelled = false,
    help_texts = {},
    items_per_page = G_reader_settings:readSetting("items_per_page") or 14,
    item_requested = nil,
    item_viewer = nil,
    list_args = nil,
    list_is_opened = false,
    list_title = nil,
    needle_name_for_list_page = "",
    other_fields_face = Font:getFace("x_smallinfofont", 19),
    -- #((Xray-item edit dialog: tab buttons in TitleBar))
    title_tab_buttons_left = { _(" xray-item "), _(" metadata ") },
    xray_item_chooser = nil,
    xray_items_chooser_dialog = nil,
    --! self.xray_type_field_nr has to correspond to the index used to get the xray_type in ((XrayFormsData#convertFieldValuesToItemProps)); see also ((XrayDialogs#switchFocusForXrayType)):
    xray_type_field_nr = 4,
    xray_ui_info_dialog = nil,
}

function XrayDialogs:initViewHelpers()
    translations = require("extensions/xrayviews/xraytranslations")
    DX.setProp("t", translations)
end

--- @return boolean signalling whether the user was redirected to the viewer (true), or not (false)
function XrayDialogs:closeForm(mode)
    KOR.dialogs:closeAllOverlays()
    KOR.registry:unset("xray_item_type_chosen")
    if mode == "add" then
        UIManager:close(self.add_item_input)
        self.add_item_input = nil
        --* this prop can be set in ((XrayButtons#forItemViewer)) > ((cancel item form)), when the user opens an add or edit form:
        --* current_item could not be set when the user selected a word in the ebook and chose to add that to the xray items:
        if
            --* this var, set in ((XrayFormsData#initNewItemFormProps)), can be truthy if editor was activated from a text selection in the ebook:
            not KOR.registry:getOnce("xray_editor_activated_from_text_selection")
            and DX.c.return_to_viewer
            and self.form_was_cancelled
            and DX.vd.current_item
        then
            --* reset values and go to item viewer:
            self.form_was_cancelled = false
            DX.vd:setProp("new_item_hits", nil)
            self:viewItem(DX.vd.current_item, self.called_from_list, nil, "skip_item_search")
            --* signal that we were redirected to the item viewer:
            return true
        end

        self.form_was_cancelled = false
        --* signal that we were NOT redirected to the item viewer:
        return false
    end

    --* edit mode:
    UIManager:close(self.edit_item_input)
    self.edit_item_input = nil
    --* this prop can be set in ((XrayButtons#forItemViewer)) > ((enable return to viewer)), when the user opens an edit form:
    if DX.c.return_to_viewer and DX.vd.current_item then
        self:viewItem(DX.vd.current_item, self.called_from_list, nil, "skip_item_search")
        return true
    end
    return false
end

function XrayDialogs:showRefreshHitsForCurrentEbookConfirmation()
    self.import_items_dialog = KOR.dialogs:confirm(_("Do you want to import Xray items from the other books in the series and compute their occurrence in the current book?\n\nNB: this is a heavy, computation-intensive function; the import therefor will take some time (you will be notified about the progress)..."), function()
        UIManager:close(self.import_items_dialog)
        UIManager:close(self.xray_items_chooser_dialog)
        local import_notification = KOR.messages:notify("import started: 0% imported...")
        UIManager:forceRePaint()
        KOR.registry:set("import_notification", import_notification)
        --* the import will be processed and the user notified about the progress in ((XrayDataSaver#setSeriesHitsForImportedItems)) > ((XrayController#doBatchImport)):
        DX.c:refreshItemHitsForCurrentEbook()
    end)
end

function XrayDialogs:showEditDescriptionDialog(description_field, callback, cancel_callback)
    self.edit_item_description_dialog = InputDialog:new{
        title = _("Edit description"),
        input = description_field:getText() or "",
        input_hint = "",
        input_type = "text",
        scroll = true,
        allow_newline = true,
        cursor_at_end = true,
        fullscreen = true,
        input_face = Font:getFace("smallinfofont", 18),
        width = Screen:getWidth() * 0.9,
        buttons = DX.b:forEditDescription(callback, cancel_callback),
    }
    UIManager:show(self.edit_item_description_dialog)
    self.edit_item_description_dialog:onShowKeyboard()
end

--* compare ((XrayDialogs#showEditItemForm)):
--- @private
function XrayDialogs:getFormFields(item_copy, target_field, name_from_selected_text)
    local aliases = DX.fd:getAliasesText(item_copy)
    local linkwords = DX.fd:getLinkwordsText(item_copy)
    local icon = DX.vd:getItemTypeIcon(item_copy, "bare")
    local aliases_field = {
        text = item_copy.aliases,
        input_type = "text",
        description = "Aliassen:",
        info_popup_title = _("field: Aliases"),
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _([[This field has space or comma separated terms, as aliases (of the main item name in the first tab). Can e.g. be a title or a nickname of a person.

Through aliases:
1) main names will be found in the Xray overview of items in paragraphs on the current page;
2) the main item will be shown if the user longpresses an alias in the ebook text.]]),
        tab = 2,
        cursor_at_end = true,
        input_face = self.other_fields_face,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local linkwords_field = {
        text = item_copy.linkwords,
        input_type = "text",
        description = _("Link terms") .. ":",
        info_popup_title = _("field") .. ": " .. _("Link terms"),
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _([[This field has space or comma separated (partial) names of other Xray items, to link the current item to those other items.

If such an other item is longpressed in the book, the linked items will be shown as extra buttons in the popup dialog.]]),
        tab = 2,
        cursor_at_end = true,
        input_face = self.other_fields_face,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local xray_type_field = {
        text = tostring(item_copy.xray_type) or "1",
        input_type = "number",
        --description = DX.fd:getTypeLabel(item_copy) .. "\n  " .. DX.vd.xray_type_description,
        description = "Xray-type:",
        --* splitting of items done by ((XrayModel#splitByCommaOrSpace)):
        info_popup_text = _("Set Xray type with numbers 1 through 4. If you use the button at the right side of the field for this, you'll see an explanation of these types."),
        tab = 2,
        input_face = self.other_fields_face,
        cursor_at_end = true,
        scroll = false,
        allow_newline = false,
        force_one_line_height = true,
        disable_paste = true,
        custom_edit_button = DX.b:forItemEditorTypeSwitch(item_copy, {
            fgcolor = KOR.colors.button_label,
            radius = Size.radius.button,
            bordersize = Size.border.button,
            padding = Size.padding.buttonvertical,
        }),
        margin = Size.margin.small,
    }
    local short_names_field = {
        text = item_copy.short_names,
        input_type = "text",
        description = _("Short names") .. ":",
        info_popup_title = _("field") .. ": " .. _("Short names"),
        info_popup_text = _([[Comparable with aliases, but in this case comma separated short variants of the main item name in the first tab. Handy when those shorter names are sometimes used in the book instead of the longer main name.

For Xray overviews of (paragraphs in) the current page the scripts initially will firstly search for whole instances of these short names, or otherwise for first and surnames derived from these.]]),
        tab = 2,
        input_face = self.other_fields_face,
        cursor_at_end = true,
        scroll = true,
        allow_newline = false,
        force_one_line_height = true,
        margin = Size.margin.small,
    }
    local fields = {
        {
            text = target_field == "description" and name_from_selected_text or item_copy.description or "",
            input_type = "text",
            description = linkwords and _("Description") .. T(" (%1):", linkwords) or _("Description"),
            info_popup_title = _("field") .. ": " .. _("Description"),
            info_popup_text = T(_([[If it is your intention that a Xray item should be filterable with a term in its description, you should ensure that that term in case of:

NAMES OF PERSONS %1
is mentioned with uppercase characters at start of first and surname in the description;

TERMS %2
only has lower case characters in the description.]]), KOR.icons.xray_person_important_bare .. "/" .. KOR.icons.xray_person_bare, KOR.icons.xray_term_important_bare .. "/" .. KOR.icons.xray_term_bare),
            tab = 1,
            height = "auto",
            input_face = self.description_field_face,
            scroll = true,
            scroll_by_pan = true,
            allow_newline = true,
            cursor_at_end = true,
            is_edit_button_target = true,
            margin = Size.margin.small,
        },
        {
            text = target_field == "name" and name_from_selected_text or item_copy.name or "",
            input_type = "text",
            description = aliases and _("Name") .. " (" .. aliases .. "):  " .. icon or _("Name") .. ": " .. icon,
            info_popup_title = _("field") .. ": " .. _("Name"),
            info_popup_text = _([[PERSONS
Enter person names including uppercase starting characters [A-Za-z]. Because in that case the search for Xray items in the book will be done CASE SENSITIVE. By default when searching for Xray items, Dynamic Xray will search for first names in the text. If you want the plugin to search for occurrences/hits for the surname instead (because these references are more frequent in the text), use this format: "surname, first name".

TERMS
Enter with only lowercase characters [a-z], because then searches for these items will be executed CASE INSENSITIVE. So as to find hits in format "term" as well as "Term".]]),
            tab = 1,
            input_face = self.other_fields_face,
            cursor_at_end = true,
            scroll = true,
            --* force fixed height for this field in ((force one line field height)):
            force_one_line_height = true,
            allow_newline = false,
            margin = Size.margin.small,
        },
    }

    --* on mobile devices we don't want two field rows (not enough space):
    if DX.s.is_mobile_device then
        table.insert(fields, aliases_field)
        table.insert(fields, linkwords_field)
        table.insert(fields, xray_type_field)
        table.insert(fields, short_names_field)
    else
        --* insert 2 two field rows:
        table.insert(fields, {
            aliases_field,
            linkwords_field,
        })
        table.insert(fields, {
            short_names_field,
            xray_type_field,
        })
    end

    return fields
end

--* compare ((XrayController#refreshItemHitsForCurrentEbook)):
function XrayDialogs:showImportFromOtherSeriesDialog()
    local question
    question = KOR.dialogs:prompt({
        title = _("Import from another series"),
        input_hint = _("name series..."),
        callback = function(series)
            UIManager:close(question)
            DX.ds.storeImportedItems(series)
        end
    })
end

--* compare ((XrayDialogs#showEditItemForm)):
function XrayDialogs:showNewItemForm(args)
    local active_form_tab = args.active_form_tab or self.active_form_tab
    local item_copy = args.item_copy

    --* to be able to re-attach the book_hits etc. to the item if the user DOES save it:
    --* consumed in ((XrayController#saveNewItem)):
    DX.vd:setProp("new_item_hits", {
        book_hits = item_copy.book_hits,
        chapter_hits = item_copy.chapter_hits,
        series_hits = item_copy.series_hits,
    })

    self.add_item_input = MultiInputDialog:new{
        title = args.title,
        title_shrink_font_to_fit = true,
        title_tab_buttons_left = self.title_tab_buttons_left,
        active_tab = active_form_tab,
        tab_callback = DX.fd:getFormTabCallback("add", active_form_tab, item_copy),
        has_field_rows = true,
        fields = self:getFormFields(item_copy, args.target_field, args.name_from_selected_text),
        close_callback = function()
            self:closeForm("add")
        end,
        --* to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#registerInputFields)):
        input_registry = "xray_item",
        description_face = self.other_fields_face,
        fullscreen = true,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        input = "",
        buttons = DX.b:forItemEditor("add", self.active_form_tab, item_copy),
    }

    if active_form_tab == 1 then
        self:adaptTextAreaHeight(self.add_item_input)
    end

    UIManager:show(self.add_item_input)
    self.add_item_input:onShowKeyboard()
end

--- @private
function XrayDialogs:adaptTextAreaHeight(dialog)
    --* this var was set in ((MultiInputDialog#init)):
    local keyboard_height = KOR.registry:get("keyboard_height")
    local form_height = dialog:getSize().h
    local screen_height = Screen:getHeight()
    local total_height = form_height + keyboard_height
    if total_height == screen_height then
        return
    end

    --local description_field_height
    if total_height < screen_height then
        self.description_field_height = self.description_field_height + screen_height - total_height
    else
        self.description_field_height = self.description_field_height - total_height + screen_height
    end
end

function XrayDialogs:showDeleteItemConfirmation(delete_item, dialog, remove_all_instances_in_series)
    if not dialog then
        dialog = self.item_viewer
    end

    local target = remove_all_instances_in_series and _("for the entire series?") or _("for the current book?")
    KOR.dialogs:confirm(T(_([[Do you indeed want to delete

%1

 ]]), delete_item.name) .. target, function()
        UIManager:close(dialog)
        DX.ds.deleteItem(delete_item, remove_all_instances_in_series)
        local message = remove_all_instances_in_series and _(" deleted for the entire series...") or _(" deleted for the current book...")
        self:refreshItemsList(delete_item.name .. message)
        self:showListWithRestoredArguments()
    end,
    function()
        if self.list_is_opened then
            UIManager:close(dialog)
            --self:showList(delete_item)
            self:showListWithRestoredArguments()
            return
        end
        self:viewItem(DX.vd.current_item)
    end)
end

--*compare ((XrayDialogs#showNewItemForm)):
function XrayDialogs:showEditItemForm(args)
    local active_form_tab = args.active_form_tab or self.active_form_tab
    local item = args.item
    local item_copy = args.item_copy

    self.edit_item_input = MultiInputDialog:new{
        title = KOR.icons.edit_bare .. " " .. item.name:gsub(" %(.+", ""):gsub(" %-.+", ""),
        title_shrink_font_to_fit = true,
        title_tab_buttons_left = self.title_tab_buttons_left,
        --* always start with first tab in form:
        active_tab = active_form_tab,
        tab_callback = DX.fd:getFormTabCallback("edit", active_form_tab, item_copy),

        tabs_count = 2,
        activate_tab_callback = function(tab_no)
            self:closeForm("edit")
            DX.c:onShowEditItemForm(self.edit_args.xray_item, self.edit_args.reload_manager, tab_no)
        end,
        has_field_rows = true,
        fields = self:getFormFields(item_copy),
        close_callback = function()
            self:closeForm("edit")
        end,
        --* to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#registerInputFields))
        input_registry = "xray_item",
        description_face = self.other_fields_face,
        fullscreen = true,
        titlebar_alignment = "center",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        --* saving edits: ((XrayController#saveUpdatedItem)) > ((XrayFormsData#getAndStoreEditedItem))
        buttons = DX.b:forItemEditor("edit", active_form_tab, args.reload_manager, item_copy),
    }

    if active_form_tab == 1 then
        self:adaptTextAreaHeight(self.edit_item_input)
    end

    UIManager:show(self.edit_item_input)
    self.edit_item_input:onShowKeyboard()
end

function XrayDialogs:showFilterDialog()
    local face = Font:getDefaultDialogFontFace()
    --KOR.dialogs:showOverlayReloaded()
    KOR.dialogs:showOverlay()
    self.filter_xray_items_input = InputDialog:new{
        title = _("Filter xray items"),
        description = _("Text filters are case insensitive (except for items which contain uppercase characters):"),
        top_buttons_left = {
            Button:new({
                icon = "info-slender",
                callback = function()
                    KOR.dialogs:niceAlert(_("Filter dialog"), _([[checkbox checked:
search only for whole word hits in the name, aliases or short names or descriptions of items.

checkbox not checked:
search for hits in the name, aliases or short names and show linked items for those hits.]]))
                end
            })
        },
        input = DX.m.filter_string,
        --* these fonts only set in InputDialog are ignored, so we have to define them here:
        input_face = face,
        description_face = face,
        button_font_weight = "normal",
        input_type = "text",
        allow_newline = false,
        cursor_at_end = true,
        buttons = DX.b:forFilterDialog(),
    }
    self.check_button_descriptions = CheckButton:new{
        text = _("Simple search: name and description"),
        checked = DX.vd.search_simple,
        parent = self.filter_xray_items_input,
        max_width = self.filter_xray_items_input._input_widget.width,
        callback = function()
            DX.vd:setProp("search_simple", self.check_button_descriptions.checked)
        end,
    }
    local checkbox_shift = math.floor((self.filter_xray_items_input.width - self.filter_xray_items_input._input_widget.width) / 2 + 0.5)
    local check_buttons = HorizontalGroup:new{
        HorizontalSpan:new{ width = checkbox_shift },
        VerticalGroup:new{
            align = "left",
            self.check_button_descriptions,
        },
    }

    --* insert check buttons before the regular buttons
    local nb_elements = #self.filter_xray_items_input.dialog_frame[1]
    table.insert(self.filter_xray_items_input.dialog_frame[1], nb_elements - 1, check_buttons)
    UIManager:show(self.filter_xray_items_input)
    self.filter_xray_items_input:onShowKeyboard()
end

function XrayDialogs:notifyFilterResult(filter_active, filtered_count)
    self.filter_state = filtered_count == 0 and "unfiltered" or "filtered"
    if filter_active and filtered_count == 0 then
        local message = has_text(DX.m.filter_string) and T(_("geen items gevonden met filter \"%1\"..."), DX.m.filter_string) or _("no items found with this filter...")
        self:setActionResultMessage(message)
    end
end

--* information for this dialog was generated in ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation))
--* extra buttons (from xray items) were populated in ((XrayUI#ReaderHighlightGenerateXrayInformation))
--* current method called from callback in ((xray paragraph info callback)):
function XrayDialogs:showItemsInfo(hits_info, headings, matches_count, extra_button_rows, haystack_text)
    local debug = false
    local info = hits_info
    if not self.xray_ui_info_dialog and has_text(info) then
        --* paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
        if debug and haystack_text then
            info = haystack_text .. "\n\n" .. info
        end
        local matches_count_info = matches_count == 1 and _("1 Xray item") or matches_count .. " " .. _("Xray items")
        local subject = DX.s.ui_mode == "paragraph" and _(" in this paragraph") or _(" on this page")
        local target = DX.s.ui_mode == "paragraph" and _("the ENTIRE PAGE") or _("PARAGRAPHS")
        local new_trigger = DX.s.ui_mode == "paragraph" and _("the first line marked with a lightning icon") or _("a paragraph marked with a star")
        --* the data below was populated in ((XrayUI#ReaderViewGenerateXrayInformation)):
        self.xray_ui_info_dialog = KOR.dialogs:textBox({
            title = matches_count_info .. subject,
            info = info,
            fullscreen = true,
            covers_fullscreen = true,
            top_buttons_left = DX.b:forUiInfoTopLeft(target, new_trigger, self),
            paragraph_headings = headings,
            fixed_face = Font:getFace("x_smallinfofont", 19),
            close_callback = function()
                self.xray_ui_info_dialog = nil
                KOR.dialogs:closeOverlay()
            end,
            -- #((xray paragraph info: after load callback))
            --- @param textviewer TextViewer
            after_load_callback = function(textviewer)
                DX.u:onInfoPopupLoadShowToc(textviewer, headings)
            end,
            -- #((inject xray list buttons))
            --* for special buttons like index and navigation arrows see ((TextViewer toc button)):
            extra_button_position = 1,
            extra_button = KOR.buttoninfopopup:forXrayList({
                fgcolor = Blitbuffer.COLOR_GRAY_3,
                callback = function()
                    UIManager:close(self.xray_ui_info_dialog)
                    self.xray_ui_info_dialog = nil
                    self:showList()
                end
            }),
            extra_button2_position = 2,
            extra_button2 = KOR.buttoninfopopup:forXrayShowMatchReliabilityExplanation({
                icon_size_ratio = 0.58,
            }),
            extra_button_rows = extra_button_rows,
        })
    end
end

--- @private
function XrayDialogs:getListFilter()
    return {
        state = self.filter_state,
        callback = function()
            self:showFilterDialog()
        end,
        reset_callback = function()
            DX.c:resetFilteredItems()
            self:showListWithRestoredArguments()
        end,
    }
end

--- @private
function XrayDialogs:_prepareItemsForList(current_tab_items)

    --* items already prepared, so don't do it again:
    if current_tab_items and current_tab_items[1] and current_tab_items[1].text then
        return
    end

    count = #current_tab_items
    for i = 1, count do
        local item = current_tab_items[i]
        item.text = DX.vd:generateListItemText(item)
        item.text = KOR.strings:formatListItemNumber(i, item.text)
        item.callback = function()
            UIManager:close(self.xray_items_chooser_dialog)
            self.needle_name_for_list_page = item.name
            self:viewItem(item, "called_from_list")
        end
    end

    DX.vd:setProp("current_tab_items", current_tab_items)
end

--- @private
function XrayDialogs:initListDialog(focus_item, dont_show, current_tab_items)
    local select_number = focus_item and focus_item.index or 1

    --* optionally items are filtered here also:
    local title = select(2, DX.vd:updateItemsTable(select_number))
    self.list_title = title
    if not title then
        return
    end

    --* goto page where recently displayed xray_item can be found in the manager:
    --* this is the case after editing, deleting or adding xray_items:
    --* if the related items popup is active, after tapping on a name in the reader, show that collection of items instead of all items:
    --* here, if necessary, we format the items just like in ((XrayViewsData#filterAndAddItemToItemTables)):
    self:_prepareItemsForList(current_tab_items)

    self.xray_items_chooser_dialog = CenterContainer:new{
        dimen = Screen:getSize(),
    }

    --* icon size for filter button set in ((Menu#getFilterButton)):
    local base_icon_size = 0.6
    local config = {
        show_parent = self.xray_items_chooser_dialog,
        parent = nil,
        fullscreen = true,
        covers_fullscreen = true,
        has_close_button = true,
        is_popout = false,

        -- #((Xray items list tab activation with hotkeys))
        --* for activation of tabs with hotkeys:
        tab_labels = {
            "alles",
            "personen",
            "begrippen",
        },
        activate_tab_callback = DX.m.activateListTabCallback,
        after_close_callback = function()
            self.list_is_opened = false
        end,
        is_borderless = true,
        top_buttons_left = DX.b:forListTopLeft(self),
        -- #((filter table example))
        filter = self:getListFilter(),
        title_submenu_buttontable = DX.b:forListSubmenu(),
        footer_buttons_left = DX.b:forListFooterLeft(focus_item, dont_show, base_icon_size),
        footer_buttons_right = DX.b:forListFooterRight(base_icon_size),
        --! don't use after_close_callback or call ((XrayController#resetFilteredItems)), because then filtering items will not work at all!
        onMenuHold = self.onMenuHold,
        items_per_page = self.items_per_page,
        _manager = self,
    }
    self.xray_items_inner_menu = Menu:new(config)

    table.insert(self.xray_items_chooser_dialog, self.xray_items_inner_menu)
    self.xray_items_inner_menu.close_callback = function()
        UIManager:close(self.xray_items_chooser_dialog)
        KOR.dialogs:unregisterWidget(self.xray_items_chooser_dialog)
        self.xray_items_chooser_dialog = nil
    end

    if has_text(self.needle_name_for_list_page) then
        self.xray_items_inner_menu:switchItemTable(title, current_tab_items, nil, {
            name = self.needle_name_for_list_page
        })
        self.needle_name_for_list_page = ""
    elseif select_number then
        self.xray_items_inner_menu:switchItemTable(title, current_tab_items, select_number)
    end
end

function XrayDialogs:showListWithRestoredArguments()
    self.xray_items_inner_menu.close_callback()
    self:showList(self.list_args.focus_item, self.list_args.dont_show)
end

--- @private
function XrayDialogs:showJumpToChapterDialog()
    KOR.dialogs:prompt({
        title = "Jump to chapter",
        description = _("Enter number as seen at the front of the items in the chapter list in tab 2 (current location will be added to location stack):"),
        input_type = "number",
        width = math.floor(Screen:getWidth() * 2.3 / 5),
        callback = function(chapter_no)
            if not chapter_no then
                KOR.messages:notify(_("please enter a valid page number..."))
                return
            end
            local chapter_html = DX.vd.current_item.chapter_hits
            if has_no_text(chapter_html) then
                KOR.messages:notify(_("this item has no chapter information..."))
                return
            end

            local chapter_title = DX.vd:findChapterTitleByChapterNo(chapter_html, chapter_no)
            if not chapter_title then
                KOR.messages:notify(_("page of chapter could not be determined..."))
                return
            end

            --* this method is defined in 2-xray-patches.lua:
            local page = KOR.toc:getPageFromItemTitle(chapter_title)
            if not page then
                KOR.messages:notify(_("page of chapter could not be determined..."))
                return
            end

            self:closeViewer()
            KOR.ui.link:addCurrentLocationToStack()
            KOR.ui:handleEvent(Event:new("GotoPage", page))
        end,
    })
end

function XrayDialogs:refreshItemsList(action_result_message)
    DX.vd.initData("force_refresh")
    self:setActionResultMessage(action_result_message)
    if self.list_is_opened then
        self:showListWithRestoredArguments()
    elseif action_result_message then
        KOR.messages:notify(action_result_message)
        self:setActionResultMessage(nil)
    end
end

function XrayDialogs:showList(focus_item, dont_show)

    --! important for generating texts of xray items in this list: ((XrayViewsData#generateListItemText))

    DX.fd:resetViewerItemId()

    --* this var will be set in ((XrayController#saveNewItem)) upon adding a new item; when set, we force update of the data and setting of correct new item index, so the list will display the subpage with the new item:
    local new_item = KOR.registry:getOnce("new_item")

    --! this condition is needed to prevent this call from triggering ((XrayViewsData#prepareData)) > ((XrayViewsData#indexItems)), because that last call will be done at the proper time via ((XrayDialogs#showList)) > ((XrayModel#getCurrentItemsForView)) > ((XrayViewsData#getCurrentListTabItems)) > ((XrayViewsData#prepareData)) > ((XrayViewsData#indexItems)):
    local current_tab_items = not new_item and DX.m:getCurrentItemsForView()
    --* this will occur after a filter reset from ((XrayController#resetFilteredItems)) and sometimes when we first call up a definition through ReaderHighlight:
    if new_item or has_no_items(current_tab_items) then
        --* if items were already retrieved from the database, that will not be done again: XrayViewsData.items etc. will be reset from XrayViewsData.item_table, in ((XrayViewsData#getCurrentListTabItems))
        DX.vd.initData("force_refresh")
        current_tab_items = DX.m:getCurrentItemsForView()
    end
    if new_item then
        --* this should enforce that focus_item has the correct index, so the list will initally show to the subpage with this item:
        focus_item = DX.vd.prepareData(new_item)

        self.needle_name_for_list_page = focus_item.name
    end
    self.list_args = {
        focus_item = focus_item,
        dont_show = dont_show,
    }

    self.item_requested = focus_item
    self.called_from_list = false
    if self.xray_items_chooser_dialog then
        UIManager:close(self.xray_items_chooser_dialog)
        self.xray_items_chooser_dialog = nil
    end

    if DX.c:listHasReloadOrDontShowRequest(focus_item, dont_show) then
        return
    end

    self:initListDialog(focus_item, dont_show, current_tab_items)
    self.list_is_opened = true

    self:addHotkeysForList()
    UIManager:show(self.xray_items_chooser_dialog)
    self:showActionResultMessage()

    KOR.dialogs:registerWidget(self.xray_items_chooser_dialog)
end

--* information about available hotkeys in list shown in ((XrayButtons#forListTopLeft)) > ((XrayDialogs#showHelp)):
--- @private
function XrayDialogs:addHotkeysForList()
    local actions = {
        {
            label = "import",
            hotkey = { { "I" } },
            callback = function()
                self:showRefreshHitsForCurrentEbookConfirmation()
                return true
            end,
        },
        {
            label = "show_info",
            hotkey = { { "Shift", { "I" } } },
            callback = function()
                self:showHelp(1)
                return true
            end,
        },
        {
            label = "toggle_book_series",
            hotkey = { { "M" } },
            callback = function()
                self:showToggleBookOrSeriesModeDialog(self.list_args.focus_item, self.list_args.dont_show)
                return true
            end,
        },
        {
            label = "sort",
            hotkey = { { "O" } },
            callback = function()
                DX.c:toggleSortingMode()
                return true
            end,
        },
        {
            label = "add",
            hotkey = { { "V" } },
            callback = function()
                DX.c:onShowNewItemForm()
                return true
            end,
        },
        {
            label = "import_from_other_serie",
            hotkey = { { "X" } },
            callback = function()
                self:showImportFromOtherSeriesDialog()
                return true
            end,
        },
    }
    if DX.m.current_series then
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
                return true
            end,
        })
    end

    --- SET HOTKEYS FOR LIST MENU INSTANCE

    count = #actions
    local hotkey, label
    for i = 1, count do
        hotkey = actions[i].hotkey
        label = actions[i].label
        local callback = actions[i].callback
        self.xray_items_inner_menu:registerCustomKeyEvent(hotkey, "action_" .. label, function()
            return callback()
        end)
    end

    --* for some reason "7" as hotkey doesn't work under Ubuntu, triggers no event:
    local current_page, per_page
    for i = 1, 9 do
        local current = i
        self.xray_items_inner_menu:registerCustomKeyEvent({ { { tostring(i) } } }, "SelectItemNo" .. current, function()
            current_page = self.xray_items_inner_menu.page
            per_page = self.xray_items_inner_menu.perpage
            local item_no = (current_page - 1) * per_page + current
            UIManager:close(self.xray_items_chooser_dialog)
            self:viewItem(DX.vd:getItem(item_no))
            return true
        end)
    end
end

function XrayDialogs:selectListTab(tab_no, counts)
    if DX.m:getActiveListTab() ~= tab_no and counts[tab_no] > 0 then
        DX.m:setActiveListTab(tab_no)
        self:showListWithRestoredArguments()
    end
end

function XrayDialogs:setActionResultMessage(message)
    self.action_result_message = message
end

--- @private
function XrayDialogs:showActionResultMessage()
    if self.action_result_message then
        KOR.registry:set("notify_case_sensitive", true)
        KOR.messages:notify(self.action_result_message, 4)
        self.action_result_message = nil
    end
end

function XrayDialogs:onMenuHold(item)
    --- @type XrayDialogs manager
    local manager = self._manager
    manager.item_context_dialog = ButtonDialogTitle:new{
        title = item.name,
        title_align = "center",
        use_low_title = true,
        buttons = DX.b:forListContext(manager, item)
    }
    UIManager:show(manager.item_context_dialog)
    return true
end

--- @private
function XrayDialogs:_closeListDialog()
    if self.xray_items_chooser_dialog then
        UIManager:close(self.xray_items_chooser_dialog)
        self.xray_items_chooser_dialog = nil
    end
end

function XrayDialogs:closeViewer()
    UIManager:close(self.item_viewer)
end

--- @private
function XrayDialogs:_showNoHitsNotification(name)
    KOR.messages:notify(T("geen hits in het boek voor %1...", name), 5)
end

--- @private
function XrayDialogs:showToggleBookOrSeriesModeDialog()
    local question = DX.vd.list_display_mode == "series" and
    T(_([[
Switch from series mode %1

TO BOOK MODE %2?
]]), KOR.icons.xray_series_mode_bare, KOR.icons.xray_book_mode_bare)
    or
    T(_([[
Switch from book mode %1

TO SERIES MODE %2?
]]), KOR.icons.xray_book_mode_bare, KOR.icons.xray_series_mode_bare)

    KOR.dialogs:confirm(question, function(focus_item, dont_show)
        local mode = DX.vd.list_display_mode == "series" and "book" or "series"
        DX.vd.list_display_mode = mode
        DX.c:toggleBookOrSeriesMode(mode, focus_item, dont_show)
    end)
end

--* information about available hotkeys in list shown in ((XrayDialogs#viewItem)) > ((XrayDialogs#showHelp))
--- @private
function XrayDialogs:addHotkeysForItemViewer()
    local actions = {
        {
            label = "add",
            hotkey = { { "A" } },
            callback = function()
                self:closeViewer()
                DX.c:resetFilteredItems()
                self:initAndShowNewItemForm()
                return true
            end,
        },
        {
            label = "delete_for_book",
            hotkey = { { "D" } },
            callback = function()
                self:showDeleteItemConfirmation(DX.vd.current_item, self.item_viewer)
                return true
            end,
        },
        {
            label = "delete_for_series",
            hotkey = { { "Shift", { "D" } } },
            callback = function()
                self:showDeleteItemConfirmation(DX.vd.current_item, self.item_viewer, "remove_all_instances_in_series")
                return true
            end,
        },
        {
            label = "edit",
            hotkey = { { "E" } },
            callback = function()
                self:closeViewer()
                DX.c:onShowEditItemForm(DX.vd.current_item, false, 1)
                return true
            end,
        },
        {
            label = "hits",
            hotkey = { { "H" } },
            callback = function()
                DX.c:viewItemHits(DX.vd.current_item.name)
                return true
            end,
        },
        {
            label = "show_info",
            hotkey = { { "Shift", { "I" } } },
            callback = function()
                self:showHelp(2)
                return true
            end,
        },
        {
            label = "goto_list",
            hotkey = { { "L" } },
            callback = function()
                self:closeViewer()
                self:showList(DX.vd.current_item)
                return true
            end,
        },
        {
            label = "goto_next",
            hotkey = { { "N" } },
            callback = function()
                -- #((next related item via hotkey))
                if DX.m.use_tapped_word_data then
                    self:viewNextTappedWordItem()
                    return true
                end
                self:viewNextItem(DX.vd.current_item)
                return true
            end,
        },
        {
            label = "open_chapter",
            hotkey = { { "O" } },
            callback = function()
                self:showJumpToChapterDialog()
                return true
            end,
        },
        {
            label = "goto_previous",
            hotkey = { { "P" } },
            callback = function()
                if DX.m.use_tapped_word_data then
                    self:viewPreviousTappedWordItem()
                    return true
                end
                self:viewPreviousItem(DX.vd.current_item)
                return true
            end,
        },
        {
            label = "search_hits",
            hotkey = { { "Shift", { "S" } } },
            callback = function()
                if DX.vd.current_item and has_items(DX.vd.current_item.book_hits) then
                    DX.c:viewItemHits(DX.vd.current_item.name)
                else
                    self:_showNoHitsNotification(DX.vd.current_item.name)
                end
                return true
            end,
        },
    }
    if DX.m.current_series then
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
                return true
            end,
        })
    end

    --- SET HOTKEYS FOR HTMLBOX INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initEventKeys)):
    KOR.registry:set("scrolling_html_eventkeys", actions)

    count = #actions
    local hotkey, label
    local suffix = "XVC"
    for i = 1, count do
        hotkey = actions[i].hotkey
        label = actions[i].label
        local callback = actions[i].callback
        self.item_viewer:registerCustomKeyEvent(hotkey, "action_" .. label .. suffix, function()
            return callback()
        end)
    end
end

--- @private
function XrayDialogs:_prepareViewerData(needle_item)
    DX.vd:getCurrentListTabItems(needle_item)
end

function XrayDialogs:viewItem(needle_item, called_from_list, tapped_word, skip_item_search)

    if tapped_word then
        called_from_list = false
    end
    self.called_from_list = called_from_list
    local book_hits
    --* skip_item_search is truthy when an add or edit for was cancelled and we just want to return to the most recently viewed item (no data were changed in this case):
    if not skip_item_search then
        self:_prepareViewerData(needle_item)
    end
    if not needle_item then
        KOR.messages:notify(_("item could not be loaded..."))
        return
    end
    book_hits = needle_item.book_hits
    local current_items_count = #DX.vd.current_tab_items

    self:_closeListDialog()

    --! if you want to show additional or specific props in the info, those props have to be added in ((XrayDataLoader#_loadAllData)) > ((set xray item props)), AND you have to add them to the menu_item props in ((XrayViewsData#filterAndPopulateItemTables))! Search for "mentioned_in" to see an example of this...
    local main_info, hits_info = DX.vd:getItemInfoHtml(needle_item, "ucfirst")
    if not hits_info then
        hits_info = ""
    end

    local name = needle_item.name
    local icon = DX.vd:getItemTypeIcon(needle_item)

    --* this sometimes happens when we only just added a new item from the ebook text and want to view it immediately:
    if needle_item.index > current_items_count then
        needle_item.index = current_items_count
    end
    local title = icon .. name .. " (" .. needle_item.index .. "/" .. current_items_count .. ")"

    self.needle_name_for_list_page = needle_item.name

    local tabs = DX.b:forItemViewerTabs(main_info, hits_info)
    self.item_viewer = KOR.dialogs:htmlBoxTabbed(1, {
        title = title,
        top_buttons_left = DX.b:forItemViewerTopLeft(self),
        tabs = tabs,
        window_size = "max",
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        modal = false,
        text_padding_top_bottom = Screen:scaleBySize(25),
        next_item_callback = function()
            self:viewNextItem(DX.vd.current_item)
        end,
        prev_item_callback = function()
            self:viewPreviousItem(DX.vd.current_item)
        end,
        after_close_callback = function()
            KOR.registry:unset("scrolling_html_eventkeys")
        end,
        --* key events are set in ((XrayDialogs#addHotkeysForList)), so additional_key_events doesn't have to be set here...
        buttons_table = DX.b:forItemViewer(needle_item, called_from_list, tapped_word, book_hits),
    })
    self:addHotkeysForItemViewer()
    self:showActionResultMessage()
end

function XrayDialogs:closeItemViewer()
    UIManager:close(self.item_viewer)
end

function XrayDialogs:viewTappedWordItem(needle_item, called_from_list, tapped_word)

    self.called_from_list = called_from_list
    local current_tab_items = DX.tw:getCurrentListTabItems()

    --* this will sometimes be the case when we first call up a definition through ReaderHighlight:
    if has_no_items(current_tab_items) then
        DX.vd.initData()
    end
    --* break off if after calling initData we still have no items:
    if has_no_items(current_tab_items) then
        return
    end
    count = #current_tab_items
    local current_items_count = count

    local book_hits = needle_item.book_hits
    DX.fd:setViewerItemId(needle_item)

    --! if you want to show additional or specific props in the info, those props have to be added in ((XrayDataLoader#_loadAllData)) > ((set xray item props)), AND you have to add them to the menu_item props in ((XrayViewsData#filterAndPopulateItemTables))! Search for "mentioned_in" to see an example of this...
    local main_info, hits_info = DX.vd:getItemInfoHtml(needle_item, "ucfirst")
    if not hits_info then
        hits_info = ""
    end

    local name = needle_item.name
    local icon = DX.vd:getItemTypeIcon(needle_item)

    local title = icon .. name .. " (" .. needle_item.tapped_index .. "/" .. current_items_count .. ")"

    self.needle_name_for_list_page = needle_item.name

    local tabs = DX.b:forItemViewerTabs(main_info, hits_info)
    self.item_viewer = KOR.dialogs:htmlBoxTabbed(1, {
        title = title,
        top_buttons_left = DX.b:forItemViewerTopLeft(self),
        tabs = tabs,
        window_size = "max",
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(25),
        next_item_callback = function()
            self:viewNextTappedWordItem()
        end,
        prev_item_callback = function()
            self:viewPreviousTappedWordItem()
        end,
        after_close_callback = function()
            KOR.registry:unset("scrolling_html_eventkeys")
        end,
        --* key events are set in ((XrayDialogs#addHotkeysForList)), so additional_key_events doesn't have to be set here...
        buttons_table = DX.b:forTappedWordItemViewer(needle_item, false, tapped_word, book_hits),
    })
    self:addHotkeysForItemViewer()
    self:showActionResultMessage()
end

function XrayDialogs:viewLinkedItem(item, tapped_word)
    self:closeViewer()
    self:viewItem(item, "called_from_list", tapped_word)
end

function XrayDialogs:viewNextItem(item)
    self:closeViewer()
    local next_item = DX.vd:getNextItem(item)
    self:viewItem(next_item, nil, nil, "skip_item_search")
end

function XrayDialogs:viewPreviousItem(item)
    self:closeViewer()
    self:viewItem(DX.vd:getPreviousItem(item), nil, nil, "skip_item_search")
end

function XrayDialogs:viewNextTappedWordItem()
    self:closeViewer()
    self:viewTappedWordItem(DX.tw:getNextItem())
end

function XrayDialogs:viewPreviousTappedWordItem()
    self:closeViewer()
    self:viewTappedWordItem(DX.tw:getPreviousItem())
end

--* compare ((XrayButtons#handleMoreButtonClick)), for the popup after the user tapped on the "More..." button:
function XrayDialogs:showTappedWordCollectionPopup(buttons, buttons_count, tapped_word)
    -- #((multiple related xray items found))
    self.xray_item_chooser = ButtonDialogTitle:new{
        title = tapped_word .. KOR.icons.arrow .. buttons_count .. _(" xray items found:"),
        title_align = "center",
        use_low_title = true,
        --no_overlay = true,
        after_close_callback = function()
            self.xray_item_chooser = nil
            --* remove the temporary table with related items for viewing:
            DX.tw:itemsUnregister()
        end,
        --* these buttons were generated in ((XrayButtons#forItemsCollectionPopup)):
        buttons = buttons,
        --* so list of related items can be shown on top of this popup:
        modal = false,
    }
    UIManager:show(self.xray_item_chooser)
end

--- @private
function XrayDialogs:modifyXrayTypeFieldValue(new_type)
    --* to be consumed in ((XrayDialogs#switchFocusForXrayType)):
    self.change_xray_type = new_type
    KOR.registry:set("xray_item_type_chosen", self.change_xray_type)
    --* this dialog instance was set in ((XrayButtons#forItemEditorTypeSwitch)):
    UIManager:close(DX.b.xray_type_chooser)
    self:dispatchFocusSwitch()
end

--- @private
function XrayDialogs:dispatchFocusSwitch()
    self:switchFocusForDescriptionField()
    self:switchFocusForXrayType()
end

--- @private
function XrayDialogs:switchFocusForDescriptionField()
    local description_field = KOR.registry:get("edit_button_target")
    if not description_field then
        return
    end

    self:showEditDescriptionDialog(description_field, function(updated_description)
        description_field:setText(updated_description)
        description_field:onFocus()
    end,
    function()
        description_field:onFocus()
    end)
end

--* this method will also be called when the user taps the button for choosing an xray type; see ((XrayButtons#forItemEditorTypeSwitch)):
function XrayDialogs:switchFocusForXrayType(for_button_tap)
    if not for_button_tap and not self.change_xray_type then
        return
    end
    --* this registry var was set in ((MultiInputDialog#registerInputFields)):
    local input_fields = KOR.registry:get("xray_item")
    --* unfocus all fields, except the xray type field:
    self:switchFocusFieldLoop(input_fields, 4, self.xray_type_field_nr)

    --* e.g. when user tapped on the choose xray type button:
    if not self.change_xray_type then
        return
    end

    --! self.xray_type_field_nr has to correspond to the index used to get the xray_type in ((XrayFormsData#convertFieldValuesToItemProps)):
    input_fields[self.xray_type_field_nr]:setText(tostring(self.change_xray_type))
    self.change_xray_type = nil
end

--- @private
function XrayDialogs:switchFocusFieldLoop(input_fields, last_field_no, focus_field_no)
    --* this set of fields values can be set in ((XrayButtons#forItemEditorTypeSwitch)) > ((xray choose type dialog)) > ((XrayDialogs#modifyXrayTypeFieldValue)):
    --* input fields were stored in Registry in ((MultiInputDialog#init)) > ((MultiInputDialog#registerInputFields)):
    if not input_fields then
        input_fields = KOR.registry:get("xray_item")
    end
    if not input_fields then
        return
    end

    --* unfocus all fields, except the focus_field_no field:
    for i = 1, last_field_no do
        if i ~= focus_field_no then
            input_fields[i]:onUnfocus()
        end
    end
    input_fields[focus_field_no]:onFocus()
end

function XrayDialogs:showHelp(initial_tab)
    --* these hotkeys are mostly defined in ((XrayDialogs#addHotkeysForList)):
    local list_info = self.help_texts["list"] or T(_([[Titlebar %1/%2 = items displayed in series/book mode
Titlebar %3 = only linked items, from longpressed word
Browse to next/previous page: Space/Shift+Space
Longpress item: quick access to actions.

A, P, B = activate tab starting with that character
1 through 9 = open corresponding item in list
F = Filter list
I = Import items and update hits
Shift+I = show this Information dialog
M = toggle book or series Mode
O = toggle sOrt by alphabet or hits count
S = show books in Series
V = add item
X = import items from eXternal series
]]), KOR.icons.xray_series_mode_bare, KOR.icons.xray_book_mode_bare, KOR.icons.xray_tapped_collection_bare)
    self.help_texts["list"] = list_info

    --* these hotkeys are mostly defined in ((XrayDialogs#addHotkeysForItemViewer)):
    local viewer_info = self.help_texts["viewer"] or T(_([[

You can also navigate through items by tapping near to the left or right border of the viewer dialog.
Browse to next/previous info screen: Space/Shift+Space

1, 2 = activate first or second tab

A = Add item
D = Delete current item for current book
Shift+D = Delete current item for entire series
E = Edit current item
Shift+I = show this Information dialog
L = go back to List
N = go to Next item (when Right doesn't work)
O = Open chapter no...
P = go to Previous item (when Left doesn't work)
S = show Series manager
Shift+S = Show all hits in book
]]), KOR.icons.series_mode_bare, KOR.icons.book_bare)
    self.help_texts["viewer"] = viewer_info

    KOR.dialogs:textBoxTabbed(initial_tab, {
        title = _("(BT) Hotkeys and more"),
        is_standard_tabbed_dialog = true,
        tabs = {
            {
                tab = _("In list of items"),
                info = list_info,
            },
            {
                tab = _("In item viewer"),
                info = viewer_info,
            },
        }
    })
end

function XrayDialogs:getControllerEntryName(entry)
    return _(entry)
end

function XrayDialogs:setProp(prop, value)
    self[prop] = value
end

return XrayDialogs
