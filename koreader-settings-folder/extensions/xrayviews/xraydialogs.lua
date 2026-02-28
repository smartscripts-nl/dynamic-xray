
--* see ((Dynamic Xray: module info)) for more info

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
local _ = KOR:initCustomTranslations()
local Size = require("ui/size")
local T = require("ffi/util").template

local DX = DX
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local math_floor = math.floor
local table = table
local table_insert = table.insert
local tostring = tostring

local count
--- @type XrayTranslations translations
local translations

--- @class XrayDialogs
local XrayDialogs = WidgetContainer:new{
    action_result_message = nil,
    add_item_input = nil,
    called_from_list = false,
    change_xray_type = nil,
    current_tab_items = nil,
    description_field_height = DX.s.is_ubuntu and 180 or 420,
    edit_item_description_dialog = nil,
    edit_item_input = nil,
    filter_icon = nil,
    filter_xray_items_input = nil,
    form_was_cancelled = false,
    help_texts = {},
    key_events = {},
    items_per_page = G_reader_settings:readSetting("items_per_page") or 14,
    item_requested = nil,
    item_viewer = nil,
    list_args = nil,
    list_is_opened = false,
    needle_name_for_list_page = "",
    select_mode = false,
    -- #((Xray-item edit dialog: tab buttons in TitleBar))
    title_tab_buttons_left = { _(" xray-item "), _(" metadata ") },
    xray_item_chooser = nil,
    xray_items_chooser_dialog = nil,
    --! self.xray_type_field_nr has to correspond to the index used to get the xray_type in ((XrayFormsData#convertFieldValuesToItemProps)); see also ((XrayDialogs#switchFocusForXrayType)):
    xray_type_field_nr = 4,
    xray_ui_info_dialog = nil,
}

function XrayDialogs:initViewHelpers()
    if DX.m:isPrivateDXversion("silent") then
        return
    end
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

        if DX.pn.return_to_page and self.form_was_cancelled then
            DX.pn:resetReturnToProps()
            return true
        end

        --* this prop can be set in ((XrayButtons#forItemViewer)) > ((cancel item form)), when the user opens an add or edit form:
        --* current_item could not be set when the user selected a word in the ebook and chose to add that to the xray items:
        if
            --* this var, set in ((XrayFormsData#initNewItemFormProps)), can be truthy if editor was activated from a text selection in the ebook:
            not KOR.registry:getOnce("xray_editor_activated_from_text_selection")
            and DX.c.return_to_viewer
            and self.form_was_cancelled
            and DX.vd.current_item
        then
            --* reset values and go to Item Viewer:
            self.form_was_cancelled = false
            DX.vd:setProp("new_item_hits", nil)
            self:showItemViewer(DX.vd.current_item, self.called_from_list, nil, "skip_item_search")
            --* signal that we were redirected to the Item Viewer:
            return true
        end

        self.form_was_cancelled = false
        --* signal that we were NOT redirected to the Item Viewer:
        return false
    end

    --* edit mode:
    UIManager:close(self.edit_item_input)
    self.edit_item_input = nil
    KOR.screenhelpers:refreshScreen()

    --* this prop can be set in ((XrayButtons#forItemViewer)) > ((enable return to viewer)), when the user opens an edit form:
    if DX.c.return_to_viewer and DX.vd.current_item then
        self:showItemViewer(DX.vd.current_item, self.called_from_list, nil, "skip_item_search")
        return true
    end
    return false
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

function XrayDialogs:showImportFromCurrentSeriesConfirmation(dialog_close_callback, upon_ready_callback)
    self.import_items_dialog = KOR.dialogs:confirm(_("Do you want to import Xray items from the other books in the current series?\n\nNB: this is a computation-intensive function; the import therefor will take some time (you will be notified about the progress)"), function()
        UIManager:close(self.import_items_dialog)
        dialog_close_callback()
        local import_notification = KOR.messages:notify("import gestart: 0% geïmporteerd…")
        UIManager:forceRePaint()
        KOR.registry:set("import_notification", import_notification)
        --* the import will be processed and the user notified about the progress in ((XrayDataSaver#setSeriesHitsForImportedItems)) > ((XrayController#doBatchImport)):
        DX.ds.storeImportedItemsFromSeries(DX.m.current_series)
        upon_ready_callback()
    end)
end

function XrayDialogs:showImportFromOtherSeriesDialog(dialog_close_callback, upon_ready_callback)
    local question
    question = KOR.dialogs:prompt({
        title = _("Import from another series"),
        input_hint = _("name series..."),
        callback = function(series)
            UIManager:close(question)
            dialog_close_callback()
            DX.ds.storeImportedItemsFromSeries(series, "is_other_series")
            upon_ready_callback()
        end
    })
end

--* compare ((XrayDialogs#showEditItemForm)):
--* props for current form were initialised in ((XrayFormsData#initNewItemFormProps)) > ((XrayController#onShowNewItemForm)):
function XrayDialogs:showNewItemForm(args)
    --! args will be nil when new item form called with a hotkey:
    local active_form_tab = args and args.active_form_tab or self.active_form_tab or 1
    local title, item_copy = DX.fd:initNewItemFormProps()
    if args and args.title then
        title = args.title
    end
    if args and args.item_copy then
        item_copy = args.item_copy
    end

    --* to be able to re-attach the book_hits etc. to the item if the user DOES save it:
    --* consumed in ((XrayController#saveNewItem)):
    DX.vd:setProp("new_item_hits", {
        book_hits = item_copy.book_hits,
        chapter_hits = item_copy.chapter_hits,
        series_hits = item_copy.series_hits,
    })

    --! make sure we don't retain field values from previous form sessions; see also the crucial call to ((MultiInputDialog#resetRegistryValues)) on every init and tab-change of MultiInputDialog:
    DX.fd:resetItemProps(item_copy)
    self.add_item_input = MultiInputDialog:new{
        title = title,
        title_shrink_font_to_fit = true,
        title_tab_buttons_left = self.title_tab_buttons_left,
        active_tab = active_form_tab,
        --* tab_callback can be called from ((InputDialog#init)); activate_tab_callback as used in several KeyEvents definitions not needed here:
        tab_callback = DX.fd:getFormTabCallback("add", active_form_tab, item_copy),
        has_field_rows = true,
        fields = DX.fd:getFormFields(item_copy, args and args.prefilled_field, args and args.name_from_selected_text),
        focus_field = args and args.focus_field or 1,
        close_callback = function()
            self:closeForm("add")
        end,
        --* to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#registerInputFields)):
        input_registry = "xray_item",
        description_face = DX.fd.other_fields_face,
        fullscreen = true,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        input = "",
        buttons = DX.b:forItemEditor("add", self.active_form_tab),
    }

    UIManager:show(self.add_item_input)
    self.add_item_input:onShowKeyboard()
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
        DX.m:updateTags(delete_item, "is_deleted_item")
        self:showListWithRestoredArguments()
    end,
    function()
        if self.list_is_opened then
            UIManager:close(dialog)
            --self:showList(delete_item)
            self:showListWithRestoredArguments()
            return
        end
        self:showItemViewer(DX.vd.current_item)
    end)
end

--*compare ((XrayDialogs#showNewItemForm)):
function XrayDialogs:showEditItemForm(args)
    local active_form_tab = args.active_form_tab or self.active_form_tab
    local item = args.item
    local item_copy = args.item_copy

    --! making sure we don't retain field values from previous form sessions: crucial call to ((MultiInputDialog#resetRegistryValues)) on every init and tab-change of MultiInputDialog:
    self.edit_item_input = MultiInputDialog:new{
        title = KOR.icons.edit_bare .. " " .. item.name:gsub(" %(.+", ""):gsub(" %-.+", ""),
        title_shrink_font_to_fit = true,
        title_tab_buttons_left = self.title_tab_buttons_left,
        tabs_count = 2,
        --* always start with first tab in form:
        active_tab = active_form_tab,
        --* tab_callback can be called from ((InputDialog#init)); activate_tab_callback as used in several KeyEvents definitions not needed here:
        tab_callback = DX.fd:getFormTabCallback("edit", active_form_tab, item_copy),
        has_field_rows = true,
        fields = DX.fd:getFormFields(item_copy),
        close_callback = function()
            self:closeForm("edit")
        end,
        --* to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#registerInputFields))
        input_registry = "xray_item",
        description_face = DX.fd.other_fields_face,
        fullscreen = true,
        titlebar_alignment = "center",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        --* saving edits: ((XrayController#saveUpdatedItem)) > ((XrayFormsData#saveUpdatedItem))
        buttons = DX.b:forItemEditor("edit", active_form_tab, args.reload_manager),
    }

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
    local checkbox_shift = math_floor((self.filter_xray_items_input.width - self.filter_xray_items_input._input_widget.width) / 2 + 0.5)
    local check_buttons = HorizontalGroup:new{
        HorizontalSpan:new{ width = checkbox_shift },
        VerticalGroup:new{
            align = "left",
            self.check_button_descriptions,
        },
    }

    --* insert check buttons before the regular buttons
    local nb_elements = #self.filter_xray_items_input.dialog_frame[1]
    table_insert(self.filter_xray_items_input.dialog_frame[1], nb_elements - 1, check_buttons)
    UIManager:show(self.filter_xray_items_input)
    self.filter_xray_items_input:onShowKeyboard()
end

function XrayDialogs:notifyFilterResult(filter_active, filtered_count)
    self.filter_state = filtered_count == 0 and "unfiltered" or "filtered"
    if filter_active and filtered_count == 0 then
        local message
        if DX.vd.filter_tag then
            message = T(_("no items found with tag \"%1\"..."), DX.vd.filter_tag)
            self:setActionResultMessage(message)
            return
        end
        message = has_text(DX.vd.filter_string) and T(_("no items found with filter \"%1\""), DX.vd.filter_string) .. KOR.strings.ellipsis or _("no items found with this filter") .. KOR.strings.ellipsis
        self:setActionResultMessage(message)
    end
end

--* information for this dialog was generated in ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation))
--* extra buttons (from xray items) were populated in ((XrayUI#ReaderHighlightGenerateXrayInformation))
--* current method called from callback in ((xray paragraph info callback)):
function XrayDialogs:showUiPageInfo(hits_info, headings, matches_count, extra_button_rows, haystack_text)
    local debug = false
    local info = hits_info
    if not self.xray_ui_info_dialog and has_text(info) then
        --* paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
        if debug and haystack_text then
            info = haystack_text .. "\n\n" .. info
        end
        local matches_count_info = matches_count == 1 and _("1 Xray item") or matches_count .. " " .. _("Xray items")
        local subject = DX.s.UI_mode == "paragraph" and _(" in this paragraph") or _(" on this page")
        local target = DX.s.UI_mode == "paragraph" and _("the ENTIRE PAGE") or _("PARAGRAPHS")
        local new_trigger = DX.s.UI_mode == "paragraph" and _("the first line marked with a lightning icon") or _("a paragraph marked with a star")
        --* the data below was populated in ((XrayUI#ReaderViewGenerateXrayInformation)):
        local key_events_module = "XrayUIpageInfoViewer"
        self.xray_ui_info_dialog = KOR.dialogs:textBox({
            title = matches_count_info .. subject,
            info = info,
            fullscreen = true,
            covers_fullscreen = true,
            modal = false,
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
            hotkeys_configurator = function()
                KOR.keyevents.addHotkeysForXrayUIpageInfoViewer(self, key_events_module)
            end,
            after_close_callback = function()
                KOR.registry:unset("add_parent_hotkeys")
                KOR.keyevents:unregisterSharedHotkeys(key_events_module)
            end,
            -- #((inject xray list buttons))
            --* for special buttons like index and navigation arrows see ((TextViewer toc button)):
            extra_button_position = 2,
            extra_button = KOR.buttoninfopopup:forXrayList({
                fgcolor = Blitbuffer.COLOR_GRAY_3,
                callback = function()
                    UIManager:close(self.xray_ui_info_dialog)
                    self.xray_ui_info_dialog = nil
                    self:showList()
                end
            }),
            extra_button2_position = 1,
            extra_button2 = KOR.buttoninfopopup:forXrayShowMatchReliabilityExplanation({
                icon_size_ratio = 0.58,
            }),
            extra_button3_position = 3,
            extra_button3 = KOR.buttoninfopopup:forXrayExport({
                callback = function()
                    UIManager:close(self.xray_ui_info_dialog)
                    return DX.cb:execExportXrayItemsCallback()
                end
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
            --* force_data_update doesn't involve reloading of data from database:
            DX.c:resetFilteredItems("force_data_update")
            self:showListWithRestoredArguments()
        end,
    }
end

--- @private
function XrayDialogs:_prepareItemsForList(current_tab_items, items_for_select)

    --* items already prepared, so don't do it again:
    if not self.select_mode and current_tab_items and current_tab_items[1] and current_tab_items[1].text then
        return
    end

    local select_mode_message
    if self.select_mode == "next_or_previous_message" then
        select_mode_message = ("Select an item to search:")
    elseif self.select_mode == "save_quote" then
        select_mode_message = ("Select an item to attach the quote to:")
    end
    count = #current_tab_items
    for i = 1, count do
        local item = current_tab_items[i]
        item.text = DX.vd:generateListItemText(item)
        item.text = KOR.strings:formatListItemNumber(i, item.text)
        item.callback = (self.select_mode == "next_or_previous_item" and
        function()
            DX.p:toPrevOrNextNavigatorPage(item)
            self.select_mode = false
        end)
        or (self.select_mode == "save_quote" and
        function()
            DX.q:saveQuote(item)
            self.select_mode = false
        end)
        or
        function()
            UIManager:close(self.xray_items_chooser_dialog)
            self.needle_name_for_list_page = item.name
            self:showItemViewer(item, "called_from_list")
        end
        if self.select_mode and item.text:match("%(%d") then
            table_insert(items_for_select, item)
        end
    end

    if not self.select_mode then
        DX.vd:setProp("current_tab_items", current_tab_items)
    end

    return select_mode_message
end

--- @private
function XrayDialogs:initListDialog(focus_item, dont_show, current_tab_items, items_for_select, key_events_module)

    local select_number = focus_item and focus_item.index or 1

    --* optionally items are filtered here also:
    local title = DX.vd:updateItemsTable(select_number)
    if not title then
        return
    end

    --* goto page where recently displayed xray_item can be found in the manager:
    --* this is the case after editing, deleting or adding xray_items:
    --* if the related items popup is active, after tapping on a name in the reader, show that collection of items instead of all items:
    --* here, if necessary, we format the items just like in ((XrayViewsData#filterAndAddItemToItemTables)):
    local select_mode_message = self:_prepareItemsForList(current_tab_items, items_for_select)
    if select_mode_message then
        title = select_mode_message
    end

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
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        is_borderless = true,
        top_buttons_left = not self.select_mode and DX.b:forListTopLeft(self),
        -- #((filter table example))
        filter = self:getListFilter(),
        title_submenu_buttontable = DX.b:forListSubmenu(),
        titlebar_inverted = self.select_mode,
        footer_buttons_left = not self.select_mode and DX.b:forListFooterLeft(focus_item, dont_show, base_icon_size),
        footer_buttons_right = not self.select_mode and DX.b:forListFooterRight(self),
        --! don't use after_close_callback or call ((XrayController#resetFilteredItems)), because then filtering items will not work at all!
        onMenuHold = self.onMenuHold,
        items_per_page = self.items_per_page,
        _manager = self,
    }
    self.xray_items_inner_menu = Menu:new(config)

    table_insert(self.xray_items_chooser_dialog, self.xray_items_inner_menu)
    self.xray_items_inner_menu.close_callback = function()
        UIManager:close(self.xray_items_chooser_dialog)
        KOR.dialogs:unregisterWidget(self.xray_items_chooser_dialog)
        self.xray_items_chooser_dialog = nil
    end

    local subject = self.select_mode and items_for_select or current_tab_items
    if has_text(self.needle_name_for_list_page) then
        self.xray_items_inner_menu:switchItemTable(title, subject, nil, {
            name = self.needle_name_for_list_page
        })
        self.needle_name_for_list_page = ""
    elseif select_number then
        self.xray_items_inner_menu:switchItemTable(title, subject, select_number)
    end
end

function XrayDialogs:showListWithRestoredArguments()
    self:showList(self.list_args.focus_item, self.list_args.dont_show)
end

--- @private
function XrayDialogs:showJumpToChapterDialog()
    KOR.dialogs:prompt({
        title = "Jump to chapter",
        description = _("Enter number as seen at the front of the items in the chapter list in tab 2 (current location will be added to location stack):"),
        input_type = "number",
        width = math_floor(Screen:getWidth() * 2.3 / 5),
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
            DX.pn:closePageNavigator()
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

function XrayDialogs:showList(focus_item, dont_show, select_mode)
    self.select_mode = select_mode

    --! important for generating texts of xray items in this list: ((XrayViewsData#generateListItemText))

    DX.fd:resetFormItemId()
    DX.pn:resetReturnToProps()

    --* this var will be set in ((XrayController#saveNewItem)) upon adding a new item; when set, we force update of the data and setting of correct new item index, so the list will display the subpage with the new item:
    local new_item = KOR.registry:getOnce("new_item")

    --! this condition is needed to prevent this call from triggering ((XrayViewsData#prepareData)) > ((XrayViewsData#indexItems)), because that last call will be done at the proper time via ((XrayDialogs#showList)) > ((XrayModel#getCurrentItemsForView)) > ((XrayViewsData#getCurrentListTabItems)) > ((XrayViewsData#prepareData)) > ((XrayViewsData#indexItems)):
    local current_tab_items = not new_item and DX.m:getCurrentItemsForView()

    local items_for_select = {}
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

    local key_events_module = "XrayItemsList"

    self:initListDialog(focus_item, dont_show, current_tab_items, items_for_select, key_events_module)
    self.list_is_opened = true

    KOR.keyevents:addHotkeysForXrayList(self, key_events_module)
    UIManager:show(self.xray_items_chooser_dialog)
    self:showActionResultMessage()

    KOR.dialogs:registerWidget(self.xray_items_chooser_dialog)
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

function XrayDialogs:closeListDialog()
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

--- @private
function XrayDialogs:_prepareViewerData(needle_item)
    DX.vd:getCurrentListTabItems(needle_item)
end

function XrayDialogs:showItemViewer(needle_item, called_from_list, tapped_word, skip_item_search)

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
    --* this can occur when we go back to the Viewer from an add new item dialog, before we even have visited the Items List (which would populate the current list tab items):
    if not DX.vd.current_tab_items then
        DX.vd:getCurrentListTabItems()
    end
    local current_items_count = DX.vd.current_tab_items and #DX.vd.current_tab_items or 0
    self:closeListDialog()

    --* this sometimes is needed when we made an update to the hits computation routines:
    DX.vd:updateChapterHtmlIfMissing(needle_item)

    --! if you want to show additional or specific props in the info, those props have to be added in ((XrayDataLoader#_loadAllData)) > ((set xray item props)), AND you have to add them to the menu_item props in ((XrayViewsData#filterAndPopulateItemTables))! Search for "mentioned_in" to see an example of this...
    local main_info, hits_info = DX.vd:getItemInfoHtml(needle_item)
    if not hits_info then
        hits_info = ""
    end

    local name = needle_item.name
    local icon = DX.vd:getItemTypeIcon(needle_item)

    local linked_items_info
    local linked_items = DX.vd:getLinkedItems(needle_item)
    if linked_items then
        linked_items_info = DX.ex:generateXrayItemsOverview(linked_items, "for_linked_items_tab")
    end

    --? hotfix: for some reason only viewer called from List doesn't have prop pos_chapter_quotes, so here we circumvent that by referencing DX.m.items_by_id, which DOES have the prop:
    --* also by using this circumvention we ensure dynamic update of the prop after quotes were saved in ((XrayQuotes#saveQuote)) - there DX.m.items_by_id[id].pos_chapter_quotes is being updated dynamically:
    local id = needle_item.id
    needle_item.pos_chapter_quotes = DX.m.items_by_id[id].pos_chapter_quotes
    local quotes_info = DX.q:generateQuotesList(needle_item)

    --! we need this when opening an item in the Item Viewer from Page Navigator:
    if not needle_item.index then
        needle_item.index = DX.vd:getItemIndexById(needle_item.id)
    end
    --* this sometimes happens when we only just added a new item from the ebook text and want to view it immediately:
    if needle_item.index > current_items_count then
        needle_item.index = current_items_count
    end
    local title = icon .. name .. " (" .. needle_item.index .. "/" .. current_items_count .. ")"

    self.needle_name_for_list_page = needle_item.name

    local key_events_module = "XrayItemViewer"
    local tabs = DX.b:getItemViewerTabs(main_info, hits_info, linked_items_info, quotes_info)

    self.item_viewer = KOR.dialogs:htmlBoxTabbed(1, {
        title = title,
        top_buttons_left = DX.b:forItemViewerTopLeft(self, needle_item),
        tabs = tabs,
        bottom_widget = DX.s.IV_show_occurrences_histogram and self:generateOccurrencesHistogram(needle_item),
        window_size = "max",
        box_font_size = DX.s.IV_font_size,
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        modal = false,
        fullscreen = true,
        key_events_module = key_events_module,
        text_padding_top_bottom = Screen:scaleBySize(25),
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayItemViewer(key_events_module)
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        next_item_callback = function()
            self:viewNextItem(DX.vd.current_item)
        end,
        prev_item_callback = function()
            self:viewPreviousItem(DX.vd.current_item)
        end,
        buttons_table = DX.b:forItemViewer(needle_item, called_from_list, tapped_word, book_hits),
    })
    self:showActionResultMessage()
end

function XrayDialogs:closeItemViewer()
    UIManager:close(self.item_viewer)
end

function XrayDialogs:generateOccurrencesHistogram(item)
    local chapters_count, ratio_per_chapter, occurrences_per_chapter = DX.pn:computeHistogramData(item)
    return DX.oh:generateChapterOccurrencesHistogram({
        occurrences_subject = item,
        occurrences_per_chapter = occurrences_per_chapter,
        ratio_per_chapter = ratio_per_chapter,
        current_chapter_index = KOR.toc:getTocIndexByPage(DX.u:getCurrentPage()),
        --* this is the width of a "max" HtmlBox:
        info_panel_width = Screen:getWidth() - 2 * Size.margin.default - Screen:scaleBySize(20),
        chapters_count = chapters_count,
        histogram_height = Screen:scaleBySize(DX.s.IV_occurrences_histogram_height),
        histogram_bottom_line_height = Size.line.thin,
    })
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
    DX.fd:setFormItemId(needle_item.id)

    --! if you want to show additional or specific props in the info, those props have to be added in ((XrayDataLoader#_loadAllData)) > ((set xray item props)), AND you have to add them to the menu_item props in ((XrayViewsData#filterAndPopulateItemTables))! Search for "mentioned_in" to see an example of this...
    local main_info, hits_info = DX.vd:getItemInfoHtml(needle_item)
    if not hits_info then
        hits_info = ""
    end

    local name = needle_item.name
    local icon = DX.vd:getItemTypeIcon(needle_item)

    local title = icon .. name .. " (" .. needle_item.tapped_index .. "/" .. current_items_count .. ")"

    self.needle_name_for_list_page = needle_item.name

    local key_events_module = "TappedWordViewer"
    local tabs = DX.b:getItemViewerTabs(main_info, hits_info)
    self.item_viewer = KOR.dialogs:htmlBoxTabbed(1, {
        title = title,
        top_buttons_left = DX.b:forItemViewerTopLeft(self, needle_item),
        tabs = tabs,
        window_size = "max",
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(25),
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayItemViewer(key_events_module)
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        next_item_callback = function()
            self:viewNextTappedWordItem()
        end,
        prev_item_callback = function()
            self:viewPreviousTappedWordItem()
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
        end,
        buttons_table = DX.b:forTappedWordItemViewer(needle_item, false, tapped_word, book_hits),
    })
    self:showActionResultMessage()
end

function XrayDialogs:viewLinkedItem(item, tapped_word)
    self:closeViewer()
    self:showItemViewer(item, "called_from_list", tapped_word)
end

function XrayDialogs:viewNextItem(item)
    self:closeViewer()
    local next_item = DX.vd:getNextItem(item)
    self:showItemViewer(next_item, nil, nil, "skip_item_search")
end

function XrayDialogs:viewPreviousItem(item)
    self:closeViewer()
    self:showItemViewer(DX.vd:getPreviousItem(item), nil, nil, "skip_item_search")
end

function XrayDialogs:viewNextTappedWordItem()
    self:closeViewer()
    self:viewTappedWordItem(DX.tw:getNextItem())
end

function XrayDialogs:viewPreviousTappedWordItem()
    self:closeViewer()
    self:viewTappedWordItem(DX.tw:getPreviousItem())
end

function XrayDialogs:showTagSelector(mode)
    local tags = DX.m.tags
    if has_no_items(tags) then
        KOR.messages:notify(_("you haven't assigned any tags to items yet"))
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
    tags_dialog = ButtonDialogTitle:new {
        title = _("tag groups"),
        subtitle = subtitle .. KOR.strings.ellipsis,
        width = dialog_width,
        buttons = buttons,
    }
    UIManager:show(tags_dialog)
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

    count = #input_fields
    local target_field_no
    for i = count, 1, -1 do
        if input_fields[i].custom_edit_button then
            target_field_no = i
            break
        end
    end
    if not target_field_no then
        KOR.messages:notify(_("target field could not be determined..."))
        return
    end

    --* unfocus all fields, except the xray type field:
    self:switchFocusFieldLoop(input_fields, 6, target_field_no)

    --* e.g. when user tapped on the choose xray type button:
    if not self.change_xray_type then
        return
    end

    input_fields[target_field_no]:setText(tostring(self.change_xray_type))
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
        if i ~= focus_field_no and input_fields[i] then
            input_fields[i]:onUnfocus()
        end
    end
    input_fields[focus_field_no]:onFocus()
end



--- =================== HOTKEY CALLBACKS ================
--* for usage by hotkeys defined in ((KeyEvents#addHotkeysForXrayUIpageInfoViewer))


function XrayDialogs:execShowHelpInfoCallback()
    return DX.i:showReliabilityIndicatorsExplanation()
end

--- @param iparent XrayDialogs
function XrayDialogs:execShowPageNavigatorCallback(iparent)
    --? strange: many closings and nextTick needed to ensure the dialogs get closed and the navigator shown ; why don't we need this for XrayDialogs:execShowListCallback?:
    UIManager:close(iparent.xray_ui_info_dialog)
    UIManager:close(XrayDialogs.xray_ui_info_dialog)
    UIManager:nextTick(function()
        DX.pn:showNavigator()
    end)
    return true
end

--- @param iparent XrayDialogs
function XrayDialogs:execShowListCallback(iparent)
    UIManager:close(iparent.xray_ui_info_dialog)
    iparent:showList()
    return true
end



--- ================= HELP INFORMATION =================

function XrayDialogs:setHelpText(key, help_info)
    self.help_texts[key] = help_info
end

function XrayDialogs:getControllerEntryName(entry)
    return _(entry)
end

function XrayDialogs:setProp(prop, value)
    self[prop] = value
end

return XrayDialogs
