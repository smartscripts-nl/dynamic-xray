
local Button = require("ui/widget/button")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Colors = require("extensions/colors")
local Device = require("device")
local Dialogs = require("extensions/dialogs")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FileDirNames = require("extensions/filedirnames")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local Icons = require("extensions/icons")
local InputDialog = require("ui/widget/inputdialog")
local KOR = require("extensions/kor")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Registry = require("extensions/registry")
local Size = require("ui/size")
local Strings = require("extensions/strings")
local Tables = require("extensions/tables")
local UIManager = require("ui/uimanager")
local XrayHelpers = require("extensions/xrayhelpers")
local Screen = require("device").screen

local viewer

--- @class XrayItems
local XrayItems = FocusManager:new{
    name = "xrayitems",
    active_list_tab = 1,
    context_buttons_max_buttons = 16,
    current_xray_item = nil,
    current_ebook_basename = nil,
    current_ebook_or_series = "",
    current_series = nil,
    delete_backup_files = false,
    description_field_face = Font:getFace("x_smallinfofont"),
    description_field_height = Registry.is_ubuntu_device and 130 or 240,
    edit_item_index = nil,
    filtered_count = 0,
    filtered_items = {},
    filter_icon = nil,
    filter_state = "unfiltered",
    filter_xray_types = nil,
    filter_string = "",
    has_series_index = false,
    is_doc_only = true,
    item_requested = nil,
    items_per_page = G_reader_settings:readSetting("items_per_page") or 16,
    item_table = {},
    max_buttons_per_row = 4,
    max_hits = 2048,
    max_line_length = 44,
    needle_for_subpage = "",
    other_ebooks = {},
    other_fields_face = Font:getFontFamily("Red Hat Text", 19),
    selected_text = "",
    switch_sur_and_last_name = false,
    -- #((Xray-item edit dialog: tab buttons in TitleBar))
    title_tab_buttons = { " xray-item ", " metadata " },
    xray_item_dialog = nil,
    xray_items_chooser_menu = nil,
    xray_items_inner_menu = nil,
    xray_type_description = "1 " .. Icons.arrow_bare .. " " .. Icons.user_bare .. "  2 " .. Icons.arrow_bare .. " " .. Icons.user_dark_bare .. "  3 " .. Icons.arrow_bare .. " " .. Icons.introduction_bare .. "  4 " .. Icons.arrow_bare .. " " .. Icons.introduction_done_bare,
    xray_type_icons = {
        Icons.user_bare,
        Icons.user_dark_bare,
        Icons.introduction_bare,
        Icons.introduction_done_bare,
    },
    -- toggle importance to important (dark) or normal (light) icon:
    xray_type_icons_importance_toggled = {
        Icons.user_dark_bare,
        Icons.user_bare,
        Icons.introduction_done_bare,
        Icons.introduction_bare,
    },
    -- toggle xray type from person to term or vice versa, while keeping the importance (dark or light icon) of the item:
    xray_type_icons_person_or_term_toggled = {
        Icons.introduction_bare,
        Icons.introduction_done_bare,
        Icons.user_bare,
        Icons.user_dark_bare,
    },
}

function XrayItems:init()
    self:dispatcherRegisterActions()
    KOR:registerUImodules(self.ui)
    KOR:registerPlugin("xrayitems", self)
end

function XrayItems:_initData()
    self.current_ebook_basename = FileDirNames:basename(self.view.document.file)
    self:setSeries()

    self.has_series_index = XrayHelpers:loadAllXrayItems(self.current_ebook_basename, self.current_series)

    if self.has_series_index then
        self.current_ebook_or_series = self.current_series
    else
        self.current_ebook_or_series = self.current_ebook_basename
        self:getOtherEbooks()
    end
 end

function XrayItems:dispatcherRegisterActions()
    Dispatcher:registerAction("show_items", { category="none", event="ShowXrayList", title = "Toon xray-items in dit boek/deze serie", rolling = true, paging = true })
end

function XrayItems:closeListDialog()
    if self.xray_items_chooser_menu then
        UIManager:close(self.xray_items_chooser_menu)
        self.xray_items_chooser_menu = nil
    end
end

function XrayItems:deleteXrayItem(delete_item)
    local xray_items = {}
    local position = 1
    for nr, xray_item in ipairs(XrayHelpers.xray_items) do
        if xray_item.id ~= delete_item.id then
            table.insert(xray_items, xray_item)
        else
            position = nr
        end
    end
    self:updateXrayItemsList(xray_items, "delete", delete_item.id)

    if position > #xray_items then
        position = #xray_items
    end
    if position == 0 then
        position = 1
    end
    return position
end

function XrayItems:deleteXrayItemDialog(delete_item, dialog, return_to_list)
    Dialogs:confirm("Wil je dit xray-item inderdaad verwijderen?", function()
        UIManager:close(dialog)
        -- call ((XrayItems#deleteXrayItem)):
        local position = self:deleteXrayItem(delete_item)
        self:updateXrayItemsTable(position)
        if return_to_list then
            self:onShowXrayList()
        end
    end,
    function()
        UIManager:close(dialog)
        if return_to_list then
            self:onShowXrayList(delete_item)
        end
    end)
end

function XrayItems:addXrayItem(name_from_selected_text)
    if has_text(name_from_selected_text) then
        local items_found = XrayHelpers:itemExists(name_from_selected_text, nil, "match_by_name_only")
        if items_found and #items_found > 0 then

            -- #((add xray_item pre dialog))
            -- compare the pre dialog in ((xray_item as dictionary plugin pre dialog)):

            local buttons = {}
            local items_per_row = 2
            for nr, item in ipairs(items_found) do
                if nr == 1 or (nr - 1) % items_per_row == 0 then
                    table.insert(buttons, {})
                end
                local current_row = #buttons
                local icon = XrayHelpers:getIcon(item)
                local text = icon .. " " .. item.name
                table.insert(buttons[current_row], {
                    text = text,
                    text_font_bold = item.name:match(name_from_selected_text),
                    callback = function()
                        --UIManager:close(self.xray_item_chooser)
                        self:onShowXrayItem(item, nil, name_from_selected_text)
                    end,
                    hold_callback = function()
                        Dialogs:textBox({
                            title = text,
                            info = XrayHelpers:getInfo(item),
                            use_computed_height = true,
                        })
                    end,
                })
            end
            local last_row = #buttons
            if last_row > 0 and #buttons[last_row] < items_per_row then
                table.insert(buttons[#buttons], {
                    icon = "add",
                    callback = function()
                        UIManager:close(self.xray_item_chooser)
                        self:onAddXrayItemShowForm(name_from_selected_text)
                    end
                })
            else
                table.insert(buttons, {
                    {
                        icon = "add",
                        callback = function()
                            UIManager:close(self.xray_item_chooser)
                            self:onAddXrayItemShowForm(name_from_selected_text)
                        end
                    }
                })
            end
            self.xray_item_chooser = ButtonDialogTitle:new{
                title = "Toon of voeg toe",
                title_align = "center",
                use_low_title = true,
                buttons = buttons,
            }
            UIManager:show(self.xray_item_chooser)
            return
        end
    end
    -- name_from_selected_text can be nil when we want to type and add a completely new item:
    self:onAddXrayItemShowForm(name_from_selected_text)
end

-- compare form for editing Xray items: ((XrayItems#onEditXrayItem)):
function XrayItems:onAddXrayItemShowForm(name_from_selected_text, active_form_tab, xray_item)
    self.active_form_mode = "add"
    local target_field = "name"
    if has_text(name_from_selected_text) and Strings:substrCount(name_from_selected_text, " ") > 3 then
        target_field = "description"
    end
    -- active_form_tab can be higher than 1 when the tab callback has been called and set this argument to a higher number:
    if not active_form_tab then
        active_form_tab = 1
    end
    local xray_type = xray_item and xray_item.xray_type or 1
    -- this concerns the active tab of the Xray items list:
    if self.active_list_tab == 3 then
        xray_type = 3
    end
    local item_copy = xray_item and Tables:shallowCopy(xray_item) or {
        description = "",
        name = "",
        short_names = "",
        linkwords = "",
        aliases = "",
        xray_type = xray_type,
        hits = 0,
    }

    -- show how many times the selected text occurs in the book:
    local search_text = name_from_selected_text or item_copy.name
    local title = "Voeg xray-item toe"
    if has_text(search_text) then
        local hits_in_book = self:getAllTextCount(search_text)
        title = self:addHitsToFormOrDialogTitle(item_copy, title, hits_in_book)
    end

    local fields = self:getFormFields(item_copy, target_field, name_from_selected_text)
    self.add_item_input = MultiInputDialog:new{
        title = title,
        title_tab_buttons = self.title_tab_buttons,
        active_tab = active_form_tab,
        tab_callback = self:getTabCallback("add", active_form_tab, item_copy),
        has_field_rows = true,
        fields = fields,
        -- to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#storeInputFieldsInRegistry)):
        input_registry = "xray_item",
        description_face = self.other_fields_face,
        fullscreen = true,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        input = "",
        condensed = true,
        buttons = self:getFormButtons("add", item_copy, active_form_tab),
    }
    UIManager:show(self.add_item_input)
    self.add_item_input:onShowKeyboard()
end

--compare ((XrayItems#onAddXrayItemShowForm)):
function XrayItems:onEditXrayItem(xray_item, reload_manager, active_form_tab)
    self.active_form_mode = "edit"

    -- this can be the case on longpressing an toc-item in TextViewer; see ((TextViewer toc button)):
    if not xray_item.index or (not xray_item.xray_type and not xray_item.aliases) then
        xray_item = XrayHelpers:upgradeNeedleItem(xray_item, {
            include_name_matches = true,
            match_by_name_only = true,
        })
    end

    local title = "Bewerk xray-item"
    -- info: when xray items are shown for a series of books, the count will be updated here for only the current ebook:
    local hits_in_current_book = self:getAllTextCount(xray_item)
    if hits_in_current_book then
        xray_item.hits = hits_in_current_book
    end
    local hits_for_title = hits_in_current_book or xray_item.hits
    -- ! because of tabs in edit form, we need to re-attach the "hidden" item id after switching between tabs:
    if self.form_item_id then
        xray_item.id = self.form_item_id
    end
    title = self:addHitsToFormOrDialogTitle(xray_item, title, hits_for_title)

    -- active_form_tab can be higher than 1 when the tab callback has been called and set the argument to a higher number:
    if not active_form_tab then
        active_form_tab = 1
    end
    if not xray_item.index then
        XrayHelpers:prepareData()
        xray_item = XrayHelpers:upgradeNeedleItem(xray_item, {
            include_name_matches = true,
        })
    end
    local item_copy = Tables:shallowCopy(xray_item)
    self.edit_item_index = xray_item.index
    self.edit_item_input = MultiInputDialog:new{
        title = title,
        title_tab_buttons = self.title_tab_buttons,
        -- always start with first tab in form:
        active_tab = active_form_tab,
        tab_callback = self:getTabCallback("edit", active_form_tab, item_copy),
        has_field_rows = true,
        fields = self:getFormFields(item_copy),
        -- to store the fields created in a corresponding Registry prop; see ((MultiInputDialog#storeInputFieldsInRegistry))
        input_registry = "xray_item",
        description_face = self.other_fields_face,
        fullscreen = true,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        condensed = true,
        -- saving edits: ((XrayItems#saveItemCallback)) > ((XrayItems#renameXrayItem))
        buttons = self:getFormButtons("edit", item_copy, active_form_tab, reload_manager),
    }
    UIManager:show(self.edit_item_input)
    self.edit_item_input:onShowKeyboard()
end

function XrayItems:closeForm(modus)
    if modus == "add" then
        UIManager:close(self.add_item_input)
        self.add_item_input = nil
    else
        UIManager:close(self.edit_item_input)
        self.edit_item_input = nil
    end
    Dialogs:closeAllOverlays()
end

function XrayItems:getEditOrXrayTypeButton(active_form_tab)
    if active_form_tab == 1 then
        return {
            icon = "edit",
            icon_size_ratio = 0.6,
            callback = function()
                self:onSwitchFocus()
            end,
        }
    end
    return {
        text = Icons.user_bare .. "/" .. Icons.introduction_bare,
        fgcolor = Colors.lighter_text,
        font_bold = false,
        callback = function()
            -- input fields were stored in Registry in ((MultiInputDialog#init)) > ((MultiInputDialog#storeInputFieldsInRegistry)):
            local input_fields = Registry:get("xray_item")
            -- local parent_form = self.active_form_mode == "add" and self.add_item_input or self.edit_item_input
            local current_field_values = {}
            for i = 1, 4 do
                -- these values will be restored in ((XrayItems#onSwitchFocus)):
                table.insert(current_field_values, input_fields[i]:getText())
            end
            local buttons = {
                {},
                {},
                {
                    {
                        icon = "back",
                        icon_size_ratio = 0.5,
                        callback = function()
                            UIManager:close(self.xray_type_chooser)
                        end,
                    }
                }
            }
            local order = { 1, 3, 2, 4 }
            for i = 4, 1, -1 do
                local row = i <= 2 and 1 or 2
                local type = order[i]
                table.insert(buttons[row], 1, {
                    text = type .. " " .. self.xray_type_icons[type],
                    callback = function()
                        self:changeXrayType(type)
                    end,
                })

            end
            self.xray_type_chooser = ButtonDialogTitle:new{
                title = "Kies xray-type",
                title_align = "center",
                no_overlay = true,
                modal = true,
                buttons = buttons,
            }
            UIManager:show(self.xray_type_chooser)
        end,
        hold_callback = function()
            Dialogs:alertInfo("Stel het Xray type in.")
        end,
    }
end

function XrayItems:onSwitchFocus()
    local description_field = Registry:get("edit_button_target")
    if description_field then
        self:editDescription(description_field, function(updated_description)
            description_field:setText(updated_description)
            description_field:onFocus()
        end,
        function()
            description_field:onFocus()
        end)
    end
    -- this set of fields values can be set in ((XrayItems#getEditOrXrayTypeButton)) > ((XrayItems#changeXrayType)):
    if self.change_xray_type then
        -- input fields were stored in Registry in ((MultiInputDialog#init)) > ((MultiInputDialog#storeInputFieldsInRegistry)):
        local input_fields = Registry:get("xray_item")

        -- make sure only xray item type field has focus:
        for i = 1, 4 do
            -- this is the xray type field:
            if i ~= 3 then
                input_fields[i]:onUnfocus()
            end
        end
        input_fields[3]:onFocus()
        input_fields[3]:setText(tostring(self.change_xray_type))
        self.change_xray_type = nil
    end
end

function XrayItems:editDescription(description_field, callback, cancel_callback)
    local edit_description_dialog
    edit_description_dialog = InputDialog:new{
        title = "Bewerk beschrijving",
        input = description_field:getText() or "",
        input_hint = "",
        input_type = "text",
        scroll = true,
        allow_newline = true,
        cursor_at_end = true,
        fullscreen = true,
        input_face = Font:getFace("smallinfofont", 18),
        width = Screen:getWidth() * 0.9,
        buttons = {
            {
                {
                    icon = "back",
                    icon_size_ratio = 0.7,
                    id = "close",
                    callback = function()
                        UIManager:close(edit_description_dialog)
                        if cancel_callback then
                            cancel_callback()
                        end
                    end,
                },
                {
                    text = Icons.save_bare,
                    is_enter_default = true,
                    callback = function()
                        local description = edit_description_dialog:getInputText()
                       UIManager:close(edit_description_dialog)
                        if callback then
                            callback(description)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(edit_description_dialog)
    edit_description_dialog:onShowKeyboard()
end

function XrayItems:filterXrayItems()
    local filter_xray_items_input
    local face = Font:getFace("x_smallinfofont")
    Dialogs:showOverlayReloaded()
    filter_xray_items_input = InputDialog:new{
        title = "Filter xray-items",
        description = "Tekstfilters zijn hoofdletter-gevoelig (behalve voor items zonder hoofdletters):",
        input = self.filter_string,
        -- these fonts only set in InputDialog are ignored, so we have to define them here:
        input_face = face,
        description_face = face,
        button_font_weight = "normal",
        input_type = "text",
        allow_newline = false,
        cursor_at_end = true,
        buttons = {
            {
                {
                    text = Icons.filter_reset,
                    callback = function()
                        Dialogs:closeOverlay()
                        UIManager:close(filter_xray_items_input)
                        self:resetFilteredXrayItems()
                        self:onShowXrayList()
                    end,
                    hold_callback = function()
                        Dialogs:alertInfo("Reset the filter")
                    end
                },
                {
                    text = Icons.user_dark_bare .. "/" .. Icons.introduction_done_bare,
                    fgcolor = Colors.lighter_text,
                    font_bold = false,
                    callback = function()
                        Dialogs:closeOverlay()
                        self.filter_state = "filtered"
                        self.filter_icon = Icons.user_dark_bare .. "/" .. Icons.introduction_done_bare
                        self.filter_xray_types = { 2, 4 }
                        UIManager:close(filter_xray_items_input)
                        self:onShowXrayList()
                    end,
                    hold_callback = function()
                        Dialogs:alertInfo("Filter xray items: only show important (black icon) persons and terms.")
                    end,
                },
                {
                    text = Icons.filter_bare,
                    is_enter_default = true,
                    callback = function()
                        -- items de facto filtered by text in ((XrayItems#filterByText)):
                        self.filter_string = filter_xray_items_input:getInputText()
                        Dialogs:closeOverlay()
                        UIManager:close(filter_xray_items_input)
                        if self.filter_string == "" then
                            return
                        end
                        self.filter_state = "filtered"
                        self:onShowXrayList()
                    end,
                    hold_callback = function()
                        Dialogs:alertInfo("Filter the xray items by text")
                    end,
                },
                {
                    icon = "back",
                    callback = function()
                        Dialogs:closeOverlay()
                        UIManager:close(filter_xray_items_input)
                    end,
                }
            }
        },
    }
    UIManager:show(filter_xray_items_input)
    filter_xray_items_input:onShowKeyboard()
end

function XrayItems:getNextXrayItem(item)
    local next = item.index + 1
    if next > #self.item_table then
        next = 1
    end
    return self.item_table[next]
end

function XrayItems:_getHtmlElementIndex(index)
    if not index then
        return 1
    end
    -- bookmark / highlight positions have this format:
    -- "/body/DocFragment[12]/body/p[179]/text().157"
    -- so second number in line is the current HTML element
    index = index:gsub("^.+body/", "")
    index = index:match("[0-9]+")

    return tonumber(index)
end

function XrayItems:getOtherEbooks()
    if #self.other_ebooks == 0 then
        -- determine other ebooks:
        for file, _ in pairs(XrayHelpers.ebooks) do
            if file ~= self.current_ebook_basename then
                table.insert(self.other_ebooks, file)
            end
        end
    end
end

function XrayItems:getPreviousXrayItem(item)
    local next = item.index - 1
    if next < 1 then
        next = #self.item_table
    end
    return self.item_table[next]
end

function XrayItems:importXrayItems(nr, book)
    local other_ebook = self.other_ebooks[nr]
    XrayHelpers.xray_items = XrayHelpers.ebooks[other_ebook] or {}
    -- optionally set to a value by ((XrayHelpers#itemExists)), so here we reset it:
    self.filter_string = ""
    XrayHelpers:storeImportedXrayItems(self.current_ebook_or_series)
    XrayHelpers.ebooks[self.current_ebook_or_series] = XrayHelpers.xray_items
    self:onShowXrayList()
    Dialogs:alertInfo("Xray-items gekopieerd vanuit " .. book .. " ", 2)
end

function XrayItems:onShowXrayList(focus_item, dont_show, filter_immediately)
    self:initDataJIT()
    self.item_requested = focus_item
    self.called_from_list = false
    if self.xray_items_chooser_menu then
        UIManager:close(self.xray_items_chooser_menu)
    end
    local select_number = 1
    if focus_item and focus_item.index then
        select_number = focus_item.index
    end
    -- info: optionally items are filtered here also:
    local title = self:updateXrayItemsTable(select_number)

    -- if no hits found with a filter, all lists and filters have been reset and we restart the list:
    if title == false then
        self:onShowXrayList(focus_item, dont_show, filter_immediately)
        return
    end

    if filter_immediately then
        Dialogs:showOverlay()
        self:filterXrayItems()
        return
    end
    -- can be set from ((XrayItems#onShowXrayItem)), when looking up an XrayItem from ReaderHighlight, when XrayItems list had not been shown yet:
    if dont_show then
        return
    end
    self.filter_state = has_text(self.filter_string) and "filtered" or "unfiltered"
    self.xray_items_chooser_menu = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    local is_filtered_list = self.filter_state == "filtered" or has_content(self.filter_xray_types)
    local xray_items_count = is_filtered_list and #self.filtered_items[1] or #XrayHelpers.xray_items
    local xray_items_persons_count = is_filtered_list and #self.filtered_items[2] or #XrayHelpers.xray_items_persons
    local xray_items_terms_count = is_filtered_list and #self.filtered_items[3] or #XrayHelpers.xray_items_terms

    local active_marker = Icons.active_tab_bare
    local title_submenu_buttontable = ButtonTable:new{
        width = Screen:getWidth(),
        button_font_face = Font:getFace("x_smallinfofont"),
        button_font_size = 17,
        buttons = {{
            {
                text = self.active_list_tab == 1 and active_marker .. " all (" .. xray_items_count .. ")" or "all (" .. xray_items_count .. ")",
                fgcolor = self.active_list_tab == 1 and Colors.active_tab or Colors.inactive_tab,
                text_font_bold = self.active_list_tab == 1,

                callback = function()
                    if self.active_list_tab ~= 1 and xray_items_count > 0 then
                        self.active_list_tab = 1
                        self:onShowXrayList(focus_item, dont_show, filter_immediately)
                    end
                end,
            },
            {
                text = self.active_list_tab == 2 and active_marker .. " persons (" .. xray_items_persons_count .. ")" or "persons (" .. xray_items_persons_count .. ")",
                fgcolor = self.active_list_tab == 2 and Colors.active_tab or Colors.inactive_tab,
                text_font_bold = self.active_list_tab == 2,
                callback = function()
                    if self.active_list_tab ~= 2 and xray_items_persons_count > 0 then
                        self.active_list_tab = 2
                        self:onShowXrayList(focus_item, dont_show, filter_immediately)
                    end
                end,
            },
            {
                text = self.active_list_tab == 3 and active_marker .. " terms (" .. xray_items_terms_count .. ")" or "terms (" .. xray_items_terms_count .. ")",
                fgcolor = self.active_list_tab == 3 and Colors.active_tab or Colors.inactive_tab,
                text_font_bold = self.active_list_tab == 3,
                callback = function()
                    if self.active_list_tab ~= 3 and xray_items_terms_count > 0 then
                        self.active_list_tab = 3
                        self:onShowXrayList(focus_item, dont_show, filter_immediately)
                    end
                end,
            },
        }},
        zero_sep = true,
        show_parent = self,
        button_font_weight = "normal",
    }
    local current_mode = self.has_series_index and "series" or "book"
    -- icon size for filter button set in ((Menu#getFilterButton)):
    local config = {
        show_parent = self.xray_items_chooser_menu,
        fullscreen = true,
        no_title = false,
        parent = nil,
        has_close_button = true,
        is_popout = false,
        covers_fullscreen = true,
        is_borderless = true,
        -- #((filter table example))
        filter = {
            state = self.filter_state,
            callback = function()
                self:filterXrayItems()
            end,
            reset_callback = function()
                self:resetFilteredXrayItems()
                self:onShowXrayList()
            end,
        },
        title_submenu_buttontable = title_submenu_buttontable,
        -- self.current_series should have been set from the doc_props in ((XrayItems#initDataJIT)) > ((XrayItems#_initData)) > ((XrayItems#setSeries)):
        footer_buttons_left = self.current_series and {
            Button:new({
                text = Icons.book_bare,
                callback = function()
                    local question = self.has_series_index and "\nOmschakelen van serie-modus\n\nNAAR BOEK-MODUS?\n" or "\nOmschakelen van boek-modus\n\nNAAR SERIE-MODUS?\n"
                    Dialogs:confirm(question, function()
                        local new_source = self.has_series_index and self.current_ebook_basename or self.current_series
                        self:setEbookOrSeriesMode(new_source, focus_item, dont_show)
                    end)
                end,
                hold_callback = function()
                    local info = "Schakel tussen weergave van Xray items in boek- of in serie-modus. In serie-modus worden alle items voor de hele serie weergeven.\n\nHuidige weergave ingesteld op: " .. current_mode .. "."
                    Dialogs:alertInfo(info)
                end,
                show_parent = self,
            }),
        } or nil,
        footer_buttons_right = {
            Button:new{
                text = "+",
                callback = function()
                    self.called_from_list = true
                    self:addXrayItem()
                end,
                bordersize = 0,
                padding = 0,
                margin = 0,
                radius = 0,
                show_parent = self,
            }
        },
        -- ! don't use after_close_callback or call ((XrayItems#resetFilteredXrayItems)), because then filtering items will not work at all!
        onMenuHold = self.onMenuHold,
        perpage = self.items_per_page,
        _manager = self,
    }
    self.xray_items_inner_menu = Menu:new(config)

    table.insert(self.xray_items_chooser_menu, self.xray_items_inner_menu)
    self.xray_items_inner_menu.close_callback = function()
        UIManager:close(self.xray_items_chooser_menu)
        self.xray_items_chooser_menu = nil
    end
    -- goto page where recently displayed xray_item can be found in the manager:
    -- this is the case after editing, deleting or adding xray_items:
    if select_number then
        self.xray_items_inner_menu:switchItemTable(title, self.item_table, select_number)
    elseif has_text(self.needle_for_subpage) then
        self.xray_items_inner_menu:switchItemTable(title, self.item_table, nil, {
            xray_item = self.needle_for_subpage
        })
        self.needle_for_subpage = ""
    end
    UIManager:show(self.xray_items_chooser_menu)
end

function XrayItems:onMenuHold(item)
    local xray_items_context_dialog
    --- @type XrayItems manager
    local manager = self._manager
    local importance_label = (item.xray_type == 2 or item.xray_type == 4) and Icons.user_bare .. "/" .. Icons.introduction_bare .. " normaal" or Icons.user_dark_bare .. "/" .. Icons.introduction_done_bare .. " belangrijk"
    local buttons = {
        {
            {
                text = "new",
                callback = function()
                    UIManager:close(xray_items_context_dialog)
                    manager:addXrayItem()
                    return false
                end,
                hold_callback = function()
                    Dialogs:alertInfo(manager.button_info.add_item)
                end,
            },
            {
                text = "edit",
                callback = function()
                    UIManager:close(xray_items_context_dialog)
                    manager:onEditXrayItem(item, "reload_manager")
                end,
                hold_callback = function()
                    Dialogs:alertInfo(manager.button_info.edit_item)
                end,
            },
            {
                text = "search",
                callback = function()
                    manager:onShowXrayItemLocations(item.text)
                end,
                hold_callback = function()
                    Dialogs:alertInfo(manager.button_info.show_context)
                end,
            },
        },
        {
            {
                text = "remove",
                callback = function()
                    -- call ((XrayItems#deleteXrayItemDialog)):
                    manager:deleteXrayItemDialog(item, xray_items_context_dialog, "return_to_list")
                end,
                hold_callback = function()
                    manager:deleteXrayItemDialog(item, xray_items_context_dialog)
                end,
            },
            {
                text = importance_label,
                fgcolor = Colors.lighter_text,
                callback = function()
                    UIManager:close(xray_items_context_dialog)
                    local position = manager:toggleIsImportantXrayItem(item)
                    manager:updateXrayItemsTable(position)
                    XrayHelpers:prepareData()
                    manager:onShowXrayList()
                    return false
                end,
                hold_callback = function()
                    Dialogs:alertInfo(manager.button_info.toggle_main_xray_item)
                end,
            },
            {
                text = "show",
                callback = function()
                    UIManager:close(xray_items_context_dialog)
                    local info = XrayHelpers:getInfo(item)
                    Dialogs:alertInfo(info)
                    return false
                end,
                hold_callback = function()
                    Dialogs:alertInfo(manager.button_info.show_item)
                end,
            },
        },
    }
    manager:removeContextButtonWhenReaderSearchActive(buttons)
    xray_items_context_dialog = ButtonDialogTitle:new{
        title = item.name,
        title_align = "center",
        use_low_title = true,
        buttons = buttons
    }
    UIManager:show(xray_items_context_dialog)
    return true
end

function XrayItems:onReaderReady()
    XrayHelpers:resetData()
end

-- called from add dialog and other ReaderDictionary and other plugins:
function XrayItems:onSaveNewXrayItem(xray_item, return_to_list)

    -- when using plus icon in top left of ReaderSearch results dialog:
    if type(xray_item) == "string" then
        self:addXrayItem(xray_item)
        return
    end

    local name_from_reader_highlight = not xray_item.name and xray_item.text
    if has_text(name_from_reader_highlight) then
        self:addXrayItem(name_from_reader_highlight)
        return
    end

    -- optionally change a suggested name like Joe Glass to Glass, Joe:
    xray_item.name = self:switchSurAndLastName(xray_item.name)

    -- insert into XrayHelpers.xray_items, because no xray_items will have been removed from this table after showing random xray_items (as is needed in the case of the Ideas plugin):
    table.insert(XrayHelpers.xray_items, xray_item)

    -- optionally set to a value by ((XrayHelpers#itemExists)), so here we reset it:
    self.filter_string = ""
    XrayHelpers:storeAddedXrayItem(self.current_ebook_or_series, xray_item)
    XrayHelpers.ebooks[self.current_ebook_or_series] = XrayHelpers.xray_items

    self:showListConditionally(xray_item, return_to_list)
end

function XrayItems:showListConditionally(xray_item, show_list)

    XrayHelpers:prepareData()
    self:updateXrayItemsTable()

    if (show_list or self.called_from_list) and not XrayHelpers.xray_item_chooser and not self.edit_item_input and not XrayHelpers.paragraph_info_dialog then
        self:onShowXrayList(xray_item)
    end
end

function XrayItems:onShowNextXrayItem(item)
    UIManager:close(viewer)
    self:onShowXrayItem(self:getNextXrayItem(item))
end

function XrayItems:onShowPreviousXrayItem(item)
    UIManager:close(viewer)
    self:onShowXrayItem(self:getPreviousXrayItem(item))
end

function XrayItems:renameXrayItem(field_values)
    if not self.edit_item_index then
        Dialogs:alertError("XrayItems.edit_item_index van het te bewerken item is niet gezet.")
        return
    end
    -- current method is called from ((XrayItems#saveItemCallback)) in edit modus; hits count was added to the edited item there:
    local new_props = self:convertFieldValuesToXrayProps(field_values)
    self:itemAddHiddenFieldValues(new_props)
    -- name field MUST be present:
    if has_text(new_props.name) then
        self.needle_for_subpage = ""
        local edited_item = {
            id = new_props.id,
            name = new_props.name,
            description = new_props.description,
            short_names = new_props.short_names,
            linkwords = new_props.linkwords,
            aliases = new_props.aliases,
            index = self.edit_item_index,
            xray_type = new_props.xray_type,
            hits = new_props.hits,
        }
        -- self.edit_item_index was set in ((XrayItems#onEditXrayItem)):
        XrayHelpers.xray_items[self.edit_item_index] = edited_item
        -- here items are also saved:
        self:updateXrayItemsList(XrayHelpers.xray_items, "edit", edited_item.id, edited_item)
        if self.filter_state == "unfiltered" then
            self.item_table = XrayHelpers.xray_items

        -- update for filtered list:
        else
            for nr, item in ipairs(self.item_table) do
                if item.index == self.edit_item_index then
                    self.item_table[nr].id = new_props.id
                    self.item_table[nr].name = new_props.name
                    self.item_table[nr].text = self:generateListItemText(new_props, nr)
                    self.item_table[nr].description = new_props.description
                    self.item_table[nr].short_names = new_props.short_names
                    self.item_table[nr].aliases = new_props.aliases
                    self.item_table[nr].linkwords = new_props.linkwords
                    self.item_table[nr].xray_type = new_props.xray_type
                    self.item_table[nr].hits = new_props.hits
                    break
                end
            end
        end
        return edited_item
    else
        Dialogs:alertError("Geen naam beschikbaar voor het te bewerken Xray item.")
    end
end

function XrayItems:resetFilteredXrayItems()
    self.filter_xray_types = nil
    self.filter_icon = nil
    self.filter_string = ""
    self.filtered_items = {}
    self.filter_state = "unfiltered"
end

-- direction 0 is forward, 1 is backward
function XrayItems:searchFromStart(pattern)
    self.direction = 0
    self._expect_back_results = true
    -- returns table with hits_positions and the words_count:
    return self:search(pattern, -1)
end

function XrayItems:searchFromEnd(pattern)
    self.direction = 1
    self._expect_back_results = false
    -- returns table with hits_positions and the words_count:
    return self:search(pattern, -1)
end

function XrayItems:searchFromCurrent(pattern, direction)
    self.direction = direction
    self._expect_back_results = direction == 1
    -- returns table with hits_positions and the words_count:
    return self:search(pattern, 0)
end

-- ignore current page and search next occurrence
function XrayItems:searchNext(pattern, direction)
    self.direction = direction
    self._expect_back_results = direction == 1
    return self:search(pattern, 1)
end

function XrayItems:search(pattern, origin)
    if not has_content(pattern) then
        return
    end
    local direction = self.direction
    local page = self.view.state.page
    local case_insensitive = false

    local hits_positions, words_count = self.ui.document:findText(pattern, origin, direction, case_insensitive, page, nil, self.max_hits)
    Device:setIgnoreInput(false)
    if words_count and words_count > self.max_hits then
        Dialogs:notify("Te veel treffers...", 4)
    end

    --Dialogs:alertMulti({ "hits_positions", hits_positions, "type hp", type(hits_positions), "words_count", words_count })

    return hits_positions, words_count
end

function XrayItems:do_search(search_func, _text, param)
    return function()
        -- To avoid problems with edge cases, crengine may now give us links
        -- that are on previous/next page of the page we should show. And
        -- sometimes even xpointers that resolve to no page.
        -- We need to loop thru all the results until we find one suitable,
        -- to follow its link and go to the next/prev page with occurences.
        local valid_link

        local no_results = true
        local words_positions, words_count = search_func(self, _text, param)
        if words_positions then
            if self.ui.document.info.has_pages then
                no_results = false
                KOR.link:onGotoLink({ page = words_positions.page - 1 }, self.neglect_current_location)
                self.view.highlight.temp[words_positions.page] = words_positions
            else
                -- Was previously just:
                --   KOR.link:onGotoLink(res[1].start, neglect_current_location)

                -- If backward search, results are already in a reversed order, so we'll
                -- start from the nearest to current page one.
                for _, r in ipairs(words_positions) do
                    -- result's start and end may be on different pages, we must
                    -- consider both
                    local r_start = r["start"]
                    local r_end = r["end"]
                    local r_start_page = self.ui.document:getPageFromXPointer(r_start)
                    local r_end_page = self.ui.document:getPageFromXPointer(r_end)
                    local bounds = {}
                    if self._expect_back_results then
                        -- Process end of occurence first, which is nearest to current page
                        table.insert(bounds, { r_end, r_end_page })
                        table.insert(bounds, { r_start, r_start_page })
                    else
                        table.insert(bounds, { r_start, r_start_page })
                        table.insert(bounds, { r_end, r_end_page })
                    end
                    for _, b in ipairs(bounds) do
                        local xpointer = b[1]
                        local page = b[2]
                        -- Look if it is valid for us
                        if page then
                            -- it should resolve to a page
                            if not self.current_epage then
                                -- initial search
                                -- We can (and should if there are) display results on current page
                                self.current_epage = self.ui.document:getCurrentPage()
                                if (self._expect_back_results and page <= self.current_epage) or
                                (not self._expect_back_results and page >= self.current_epage) then
                                    valid_link = xpointer
                                end
                            else
                                -- subsequent searches
                                -- We must change page, so only consider results from
                                -- another page, in the adequate search direction
                                self.current_epage = self.ui.document:getCurrentPage()
                                if (self._expect_back_results and page < self.current_epage) or
                                (not self._expect_back_results and page > self.current_epage) then
                                    valid_link = xpointer
                                end
                            end
                        end
                        if valid_link then
                            break
                        end
                    end
                    if valid_link then
                        break
                    end
                end
                if valid_link then
                    no_results = false
                    KOR.link:onGotoLink({ xpointer = valid_link }, self.neglect_current_location)
                end
            end
            -- Don't add result pages to location ("Go back") stack
            self.neglect_current_location = true
        end
        if no_results then
            return
        end

        return words_positions, words_count
    end
end

function XrayItems:showImportMenu()
    self.import_menu = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    local inner_menu = Menu:new{
        show_parent = self.import_menu,
        width = Dialogs:getTwoThirdDialogWidth(),
        height = Screen:getHeight() - 120,
        no_title = false,
        parent = nil,
        has_close_button = true,
        is_popout = true,
        is_borderless = false,
        perpage = self.items_per_page,
    }
    table.insert(self.import_menu, inner_menu)
    inner_menu.close_callback = function()
        UIManager:close(self.import_menu)
    end

    local item_table = self:updateOtherBooksTable()
    inner_menu:switchItemTable(tostring(#self.other_ebooks) .. " andere boeken", item_table)
    UIManager:show(self.import_menu)
end

function XrayItems:removeContextButtonWhenReaderSearchActive(buttons)
    -- reader_search_active is set in ((ReaderSearch#onShowFindAllResults)):
    if Registry:get("reader_search_active") then
        table.remove(buttons[1], #buttons[1])
    end
end

function XrayItems:onShowXrayItem(needle_item, called_from_list, tapped_word)
    self:initDataJIT()
    self.called_from_list = called_from_list
    -- this will sometimes be the case when we first call up a definition through ReaderHighlight:
    if #self.item_table == 0 then
        self:onShowXrayList(needle_item, "dont_show")
    end
    -- this step is necessary when this method was called through an event:
    if self.filter_state == "unfiltered" then
        for i = 1, #self.item_table do
            self.item_table[i].index = i
            if self.item_table[i].name == needle_item.name then
                needle_item = self.item_table[i]
            end
        end
    end
    self.current_xray_item = needle_item
    self:closeListDialog()
    local info = XrayHelpers:getInfo(needle_item, "ucfirst")
    local name = needle_item.name
    local icon = XrayHelpers:getIcon(needle_item)
    local title = icon .. name .. " (" .. needle_item.index .. "/" .. #self.item_table .. ")"
    title = self:addHitsToFormOrDialogTitle(needle_item, title, needle_item.hits)
    Registry:set("force_non_bold_buttons", true)
    local buttons = {
        {
            {
                text = Icons.list_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    UIManager:close(viewer)
                    self:onShowXrayList(needle_item)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Show list of xray items.")
                end,
            },
            {
                text = Icons.filter_bare,
                callback = function()
                    UIManager:close(viewer)
                    self:resetFilteredXrayItems()
                    self:onShowXrayList(nil, false, "filter_immediately")
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Show list of xray items and filter that immediately.")
                end,
            },
            {
                text = Icons.previous_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    self:onShowPreviousXrayItem(needle_item)
                end,
            },
            {
                text = Icons.next_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    self:onShowNextXrayItem(needle_item)
                end,
            },
            {
                text = Icons.back_bare,
                fgcolor = Colors.lighter_text,
                font_bold = false,
                callback = function()
                    self:deleteXrayItemDialog(needle_item, viewer, "return_to_list")
                    UIManager:close(viewer)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Delete xray item and return to previous context.")
                end,
            },
            {
                text = "+",
                fgcolor = Colors.lighter_text,
                callback = function()
                    UIManager:close(viewer)
                    self:resetFilteredXrayItems()
                    local hname = self.selected_text and self.selected_text.text
                    self:addXrayItem(hname)
                    self.selected_text = nil
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Add xray item.")
                end,
            },
            {
                icon = "edit",
                icon_size_ratio = 0.6,
                callback = function()
                    UIManager:close(viewer)
                    self:onEditXrayItem(needle_item, false, 1)
                end,
            },
            {
                text = self.xray_type_icons_importance_toggled[needle_item.xray_type],
                fgcolor = Colors.lighter_text,
                font_bold = false,
                callback = function()
                    UIManager:close(viewer)
                    local position, toggled_item = self:toggleIsImportantXrayItem(needle_item)
                    self:updateXrayItemsTable(position)
                    self:onShowXrayItem(toggled_item, called_from_list, tapped_word)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Toggle the status of this xray item between important (black icon) and normal (light icon).")
                end,
            },
            {
                text = self.xray_type_icons_person_or_term_toggled[needle_item.xray_type],
                fgcolor = Colors.lighter_text,
                font_bold = false,
                callback = function()
                    UIManager:close(viewer)
                    local position, toggled_item = self:toggleIsPersonOrTerm(needle_item)
                    self:updateXrayItemsTable(position)
                    self:onShowXrayItem(toggled_item, called_from_list, tapped_word)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Toggle the type of this xray item between \"person\" and \"term\".")
                end,
            },
            {
                icon = "appbar.search",
                icon_size_ratio = 0.6,
                enabled = has_text(needle_item.name),
                callback = function()
                    self:onShowXrayItemLocations(needle_item.name)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Show all text locations where the name of this xray item is being mentioned in the current book.")
                end,
            },
            {
                text = Icons.book_bare,
                fgcolor = Colors.lighter_text,
                enabled = has_text(needle_item.name),
                callback = function()
                    local first_name = needle_item.name:gsub(" .+$", "")
                    self.ui:handleEvent(Event:new("LookupWord", first_name))
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Search for this word in the Dictionary.")
                end,
            },
            {
                text = Icons.back_bare,
                fgcolor = Colors.lighter_text,
                font_bold = false,
                callback = function()
                    UIManager:close(viewer)
                    if called_from_list then
                        self:showListConditionally()
                    end
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Close viewer and go back to the list of items (if that list was opened previously).")
                end,
            },
        }
    }
    self:removeContextButtonWhenReaderSearchActive(buttons)
    self:addContextButtons(buttons, needle_item, tapped_word)
    Dialogs:closeAllOverlays("skip_show_footer")
    Dialogs:showOverlay()
    viewer = Dialogs:textBox({
        title = title,
        info = info,
        narrow_text_window = true,
        use_computed_height = true,
        button_font_weight = "normal",
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(25),
        next_item_callback = function()
            self:onShowNextXrayItem(self.current_xray_item)
        end,
        prev_item_callback = function()
            self:onShowPreviousXrayItem(self.current_xray_item)
        end,
        buttons_table = buttons,
    })
end

function XrayItems:isXrayItem(name)
    return name:gsub(":.+$", ""):match("[A-Z]")
end

function XrayItems:onShowXrayItemLocations(user_name)
    -- for persons, as opposed to ideas/definitions/terms, only search by first name:
    if self:isXrayItem(user_name) then
        user_name = user_name:gsub(" .+$", "")
    end
    KOR.readersearch:onShowTextLocationsForNeedle(user_name)
end

function XrayItems:expandHitToContext(hit, context_words)

    local translated = {
        pos0 = hit["start"],
        pos1 = hit["end"],
    }
    for _ = 1, context_words do
        local new_pos0 = self.ui.document:getPrevVisibleWordStart(translated.pos0)
        local new_pos1 = self.ui.document:getNextVisibleWordEnd(translated.pos1)
        if new_pos0 then
            translated.pos0 = new_pos0
        end
        if new_pos1 then
            translated.pos1 = new_pos1
        end
    end
    hit["start"] = translated.pos0
    hit["end"] = translated.pos1

    return hit
end

-- change a suggested name like Joe Glass to Glass, Joe. If self.switch_sur_and_last_name is set to true:
function XrayItems:switchSurAndLastName(name)
    if self.switch_sur_and_last_name and name:match(" ") then
        local name_parts = Strings:split(name, " ", false)
        local parts = {}
        table.insert(parts, name_parts[2] .. ",")
        for nr, part in ipairs(name_parts) do
            if nr ~= 2 then
                table.insert(parts, part)
            end
        end
        name = table.concat(parts, " ")
    end
    return name
end

-- info: this method called upon rename/edit, delete, toggle importance, toggle person/term of Xray item:
function XrayItems:updateXrayItemsList(items, modus, xray_item_id, updated_value)
    XrayHelpers.xray_items = items
    -- optionally set to a value by ((XrayHelpers#itemExists)), so here we reset it:
    self.filter_string = ""

    if modus == "delete" and xray_item_id then
        XrayHelpers:storeDeletedXrayItem(self.current_ebook_or_series, xray_item_id)
        -- modus has this value when called from ((XrayItems#toggleIsPersonOrTerm)) or ((XrayItems#toggleIsImportantXrayItem)):
    elseif modus == "toggle_xray_type" and xray_item_id and updated_value then
        XrayHelpers:storeUpdatedXrayItemType(self.current_ebook_or_series, xray_item_id, updated_value)
    elseif modus == "edit" and xray_item_id and updated_value then
        -- updated_value in this case is a xray item:
        XrayHelpers:storeUpdatedXrayItem(self.current_ebook_or_series, xray_item_id, updated_value)
    end

    XrayHelpers.ebooks[self.current_ebook_or_series] = XrayHelpers.xray_items
end

function XrayItems:updateXrayItemsTable(select_number)
    local source = self.has_series_index and "series " .. Strings.curly_quote_l .. self.current_series .. Strings.curly_quote_r or "current book"
    self.item_table = {}
    local xray_items, xray_items_persons, xray_items_terms = self:getItems()
    self.filtered_count = 0
    if #xray_items > 0 then
        -- in these calls self.filtered_count must be updated:
        local subjects = {
            xray_items,
            xray_items_persons,
            xray_items_terms,
        }
        if has_content(self.filter_xray_types) then
            select_number = self:filterByIcon(subjects, select_number)
            xray_items = self.filtered_items[1]
            xray_items_persons = self.filtered_items[2]
            xray_items_terms = self.filtered_items[3]
        else
            select_number = self:filterByText(subjects, select_number)
            if has_text(self.filter_string) then
                xray_items = self.filtered_items[1]
                xray_items_persons = self.filtered_items[2]
                xray_items_terms = self.filtered_items[3]
            end
        end
    end
    local title

    local title_prefix = "Xray-items bij "
    if self.filter_xray_types then
        -- when no xray_items found with the current filter:
        if self.filtered_count == 0 then
            self:noItemsFoundWithFilterHandler("no items found of this type...")
            return false
        else
            title = self.filter_icon .. " " .. title_prefix .. source
        end

    elseif self.filter_string:len() >= 3 then
        -- when no xray_items found with the current filter:
        if #xray_items == 0 then
            select_number, title = self:noItemsFoundWithFilterHandler("nothing found with \"" .. self.filter_string .. "\"...")
            return false
        else
            title = title_prefix .. source .. " - " .. self.filter_string
        end
    else
        title = title_prefix .. source
    end
    if #xray_items == 0 then
        title = "Xray-items"
    end
    return title
end

function XrayItems:noItemsFoundWithFilterHandler(message)
    Dialogs:notify(message, 4)
    self:resetFilteredXrayItems()
end

function XrayItems:updateOtherBooksTable()
    local item_table = {}
    local books = self.other_ebooks
    if #books > 0 then
        Tables:sortAlphabetically(books)
        for nr, book in ipairs(books) do
            if book ~= self.current_ebook_or_series then
                local menu_item = {
                    text = Strings:formatListItemNumber(nr, book),
                    callback = function()
                        UIManager:close(self.import_menu)
                        self:importXrayItems(nr, book)
                    end,
                }
                table.insert(item_table, menu_item)
            end
        end
    else
        Dialogs:alertError("No other books with xray items found", 2)
        return false
    end
    return item_table
end

function XrayItems:filterByIcon(xray_items_tables, select_number)
    self.filtered_items = {
        {}, -- all
        {}, -- persons
        {}, -- terms
    }
    self.filtered_count = 0
    for subject_table_nr, item_table in ipairs(xray_items_tables) do
        for _, item in ipairs(item_table) do
            for _, icon_no in ipairs(self.filter_xray_types) do
                if item.xray_type == icon_no then

                    -- info: filter item lists of all types:
                    table.insert(self.filtered_items[subject_table_nr], item)

                    -- info: filter the active item list, set by self.active_list_tab:
                    if subject_table_nr == self.active_list_tab then
                        self.filtered_count = self.filtered_count + 1
                        local bold = self.item_requested and select_number and select_number == #self.item_table + 1
                        if bold then
                            self.item_requested = nil
                        end
                        local menu_item
                        menu_item = {
                            text = self:generateListItemText(item, self.filtered_count),
                            id = item.id,
                            name = item.name,
                            description = item.description,
                            short_names = item.short_names,
                            linkwords = item.linkwords,
                            aliases = item.aliases,
                            xray_type = item.xray_type,
                            hits = item.hits,
                            bold = bold,
                            index = #self.item_table + 1,
                            callback = function()
                                UIManager:close(self.xray_items_chooser_menu)
                                self.needle_for_subpage = item
                                self:onShowXrayItem(menu_item)
                            end,
                        }
                        table.insert(self.item_table, menu_item)
                    end
                end
            end
        end
    end
    return select_number
end

-- filter list by text; compare finding matching items for tapped text ((tapped word hits)) & ((XrayHelpers#getXrayItemAsDictionaryEntry)):
function XrayItems:filterByText(xray_items_tables, select_number)
    local keywords
    if has_text(self.filter_string) then
        keywords = Strings:getKeywordsForMatchingFrom(self.filter_string, "no_lower_case")
    end

    self.filtered_items = {
        {}, -- all
        {}, -- persons
        {}, -- terms
    }
    self.filtered_count = 0
    for subject_table_nr, item_table in ipairs(xray_items_tables) do
        for nr, item in ipairs(item_table) do
            local filter_has_a_match
            if keywords and #keywords > 0 then
                filter_has_a_match = XrayHelpers:hasTextFilterMatch(item, keywords)
                -- info: for lowercase Xray items match for lowercase AND ucfirst variants; compare ((tapped word matches for text variant)):
                if not filter_has_a_match and not item.name:match("[A-Z]") then
                    -- #((xray items list matches for text variant))
                    local uc_first_name = Strings:ucfirst(item.name, "force_only_first")
                    if uc_first_name ~= item.name then
                        filter_has_a_match = XrayHelpers:hasTextFilterMatch(item, keywords, uc_first_name)
                    end
                end
                -- info: filter item lists of all types:
                if filter_has_a_match then
                    table.insert(self.filtered_items[subject_table_nr], item)
                end

                -- info: filter the active item list, set by self.active_list_tab:
                if subject_table_nr == self.active_list_tab and filter_has_a_match then
                    self.filtered_count = self.filtered_count + 1
                end
            end

            if not keywords or filter_has_a_match then

                if subject_table_nr == self.active_list_tab then
                    local item_no = filter_has_a_match and self.filtered_count or nr
                    local bold = self.item_requested and select_number and select_number == #self.item_table + 1
                    if bold then
                        self.item_requested = nil
                    end
                    local menu_item
                    menu_item = {
                        text = self:generateListItemText(item, item_no),
                        id = item.id,
                        name = item.name,
                        description = item.description,
                        xray_type = item.xray_type,
                        short_names = item.short_names,
                        linkwords = item.linkwords,
                        aliases = item.aliases,
                        hits = item.hits,
                        bold = bold,
                        index = #self.item_table + 1,
                        callback = function()
                            UIManager:close(self.xray_items_chooser_menu)
                            self.needle_for_subpage = item
                            self:onShowXrayItem(menu_item, "called_from_list")
                        end
                    }
                    table.insert(self.item_table, menu_item)
                end
            end
        end
    end
    return select_number
end

-- context buttons with linked xray items for dialog for viewing an Xray item:
function XrayItems:addContextButtons(buttons, needle_item, tapped_word)
    if has_text(needle_item.name) then
        local copies = XrayHelpers:getLinkedItems(needle_item)

        local add_more_button = #copies > self.context_buttons_max_buttons
        for nr, item in ipairs(copies) do
            if nr == 1 or (nr - 1) % self.max_buttons_per_row == 0 then
                table.insert(buttons, {})
            end
            local current_row = #buttons
            if add_more_button and nr == self.context_buttons_max_buttons then
                ButtonDialogTitle:addMoreButton(buttons, {
                    -- popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons - this prop to be consumed in ((ButtonDialogTitle#handleMoreButtonClick)):
                    max_total_buttons_after_first_popup = self.context_buttons_max_buttons + 16,
                    max_total_buttons = self.context_buttons_max_buttons,
                    current_row = current_row,
                    popup_buttons_per_row = self.max_buttons_per_row,
                    source_items = copies,
                    title = " extra xray-items:",
                    icon_generator = XrayHelpers,
                    parent_dialog = viewer,
                    item_callback = function(citem)
                        self:resetFilteredXrayItems()
                        self:onShowXrayItem(citem, nil, tapped_word)
                    end,
                    item_hold_callback = function(citem, icon)
                        Dialogs:textBox({
                            title = icon .. citem.name,
                            info = XrayHelpers:getInfo(citem),
                            use_computed_height = true,
                        })
                    end,
                })
                break
            end
            local icon = XrayHelpers:getIcon(item)
            local linked_item_hits = item.hits and item.hits > 0 and " (" .. item.hits .. ")" or ""
            table.insert(buttons[current_row], {
                text = Icons.xray_link_bare .. icon .. " " .. item.name:lower() .. linked_item_hits,
                font_bold = item.is_bold,
                text_font_face = Font:getFace("x_smallinfofont"),
                font_size = 18,
                callback = function()
                    self:resetFilteredXrayItems()
                    UIManager:close(viewer)
                    self:onShowXrayItem(item, nil, tapped_word)
                end,
                hold_callback = function()
                    Dialogs:textBox({
                        title = icon .. " " .. item.name,
                        title_shrink_font_to_fit = true,
                        info = XrayHelpers:getInfo(item),
                        use_computed_height = true,
                    })
                end,
            })
        end
    end
end

function XrayItems:getAllTextCount(search_text_or_item)
    --- @type CreDocument document
    local document = self.ui.document

    local aliases
    local alias_table = {}
    if type(search_text_or_item) == "table" then
        aliases = search_text_or_item.aliases
        search_text_or_item = search_text_or_item.name
    end
    if has_text(aliases) then
        alias_table = XrayHelpers:splitByCommaOrSpace(aliases)
    end

    -- info: if applicable, we only search for first names (then probably more accurate hits count):
    search_text_or_item = search_text_or_item:gsub(" .+$", "")
    -- info: for lowercase needles (terms instead of persons), we search case insensitive:
    local case_insensitive = search_text_or_item:match("[A-Z]") and true or false
    -- ? we set nb_context_words to zero, so hopefully query faster?:
    local results = document:findAllText(search_text_or_item, case_insensitive, 0, 2000, false)
    local count = results and #results or 0

    -- add the occurrence count for aliases:
    for _, alias in ipairs(alias_table) do
        case_insensitive = alias:match("[A-Z]") and true or false
        results = document:findAllText(alias, case_insensitive, 0, 2000, false)
        if results then
            count = count + #results
        end
    end

    return count
end

function XrayItems:getAliasesText(item)
    if not has_text(item.aliases) then
        return nil
    end
    local noun = item.aliases:match(" ") and "aliases " or "alias "
    noun = noun .. Icons.arrow_bare .. " "
    return Strings:limitLength(noun .. item.aliases, self.max_line_length)
end

function XrayItems:getLinkwordsText(item)
    if not has_text(item.linkwords) then
        return nil
    end
    local noun = item.linkwords:match(" ") and "link-terms " or "link-term "
    noun = noun .. Icons.arrow_bare .. " "
    return Strings:limitLength(noun .. item.linkwords, self.max_line_length)
end

--- @param modus string either "add" or "edit"
function XrayItems:getFormButtons(modus, item_copy, active_form_tab, reload_manager)
    local edit_button = self:getEditOrXrayTypeButton(active_form_tab)
    return {
        {
            {
                text = Icons.back_bare,
                fgcolor = Colors.lighter_text,
                font_bold = false,
                callback = function()
                    self:closeForm(modus)
                    if self.called_from_list then
                        self:onShowXrayList()
                    end
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Close viewer and go back to the list of items (if that list was opened previously).")
                end,
            },
            {
                text = Icons.list_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    Dialogs:confirm("This will close the add dialog.\n\nContinue?", function()
                        self:closeForm(modus)
                        self:onShowXrayList(self.item_requested)
                    end)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Close form and show list of xray items.")
                end,
            },
            {
                text = Icons.xray_link_bare,
                callback = function()
                    Dialogs:confirm("This will close this form.\n\nContinue?", function()
                        self:closeForm(modus)
                        self.filter_string = item_copy.name:gsub(" .+$", "")
                        KOR.xrayitems:onShowXrayList()
                    end)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Close form and show all xray items which are connected to the current item.")
                end,
            },
            edit_button,
            {
                text = Icons.save_bare .. Icons.arrow .. Icons.list_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    self:saveItemCallback(modus, "return_to_list", reload_manager)
                end,
                hold_callback = function()
                    Dialogs:alertInfo("Save xray item and goto list of xray items.")
                end,
            },
            {
                text = Icons.save_bare,
                fgcolor = Colors.lighter_text,
                callback = function()
                    Dialogs:closeAllOverlays()
                    self:saveItemCallback(modus, false, reload_manager)
                end,
            },
        }
    }
end

--- @param modus string either "add" or "edit"
function XrayItems:saveItemCallback(modus, return_to_list, reload_manager)
    if modus == "edit" then
        local field_values = self.edit_item_input:getValues()
        local edited_item = self:renameXrayItem(field_values)
        self:closeForm(modus)
        if edited_item then
            self.edit_item_index = nil
            for i = 1, #XrayHelpers.xray_items do
                if XrayHelpers.xray_items[i].id == edited_item.id then
                    XrayHelpers.xray_items[i] = edited_item
                    break
                end
            end
            self:showListConditionally(edited_item, reload_manager or return_to_list)
        end

    -- add modus:
    else
        local fields = self.add_item_input:getValues()
        -- if name is set:
        if has_text(fields[2]) then
            local new_xray_item = self:convertFieldValuesToXrayProps(fields)
            self:closeForm(modus)
            self:itemAddHiddenFieldValues(new_xray_item)
            self:onSaveNewXrayItem(new_xray_item, return_to_list)
        end
    end
end

-- compare ((XrayItems#onEditXrayItem)):
function XrayItems:getFormFields(item_copy, target_field, name_from_selected_text)
    local aliases = self:getAliasesText(item_copy)
    local linkwords = self:getLinkwordsText(item_copy)
    local icon = XrayHelpers:getIcon(item_copy, "bare")
    return {
        {
            text = target_field == "description" and name_from_selected_text or item_copy.description or "",
            input_type = "text",
            description = linkwords and "Description (" .. linkwords .. "):" or "Description:",
            info_popup_text = "If the xray item has to be found with a search term in its description, then in case of:\n\nPERSONS\nlet them be present therein with capitals at start of first and last name;\n\nTERMS\nlet them be present therein with only lowercase characters.",
            tab = 1,
            height = self.description_field_height,
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
            description = aliases and "Name (" .. aliases .. "):  " .. icon or "Name:  " .. icon,
            info_popup_text = "PERSONS\nIt's best to enter them with uppercase characters at the start of their first and last name [A-Za-z], because then the plugin will search for them CASE SENSITIVE in the text of the book.\n\nTERMS\nThese you can best enter using only lowercase characters [a-z], because then the script will search CASE INSENSITIVE for them in the text of the book, and so find more instances. It will then find both \"term\" and \"Term\" (at the start of sentences).",
            tab = 1,
            input_face = self.other_fields_face,
            cursor_at_end = true,
            scroll = true,
            -- force fixed height for this field in ((force one line field height)):
            force_one_line_height = true,
            allow_newline = false,
            margin = Size.margin.small,
        },
        -- two field row:
        {
            {
                text = item_copy.aliases,
                input_type = "text",
                description = "Aliassen:",
                -- splitting of items done by ((XrayHelpers#splitByCommaOrSpace)):
                info_popup_text = "Aliases: enter terms separated by spaces or by commas (\", \"). Aliases are an additional way to find persons or terms, next to the main name defined in the first tab. Can e.g. be a title or a nickname of a person.\n\nBy using aliases:\n1) main names will be found by their aliases in the list of xray items in a page or in paragraphs;\n2) the item will be shown when the user long presses an alias in the text of the book.",
                tab = 2,
                cursor_at_end = true,
                input_face = self.other_fields_face,
                scroll = true,
                allow_newline = false,
                force_one_line_height = true,
                margin = Size.margin.small,
            },
            {
                text = item_copy.linkwords,
                input_type = "text",
                description = "Link-termen:",
                -- splitting of items done by ((XrayHelpers#splitByCommaOrSpace)):
                info_popup_text = "Link-terms: terms separated by spaces or commas (\", \") of (parts of) the main name of other xray items. By defining these you link the current item to those other items.\n\nWhen a user long presses the name or the alias of that other item, the linked items will be accessible via extra buttons at the bottom of the xray item viewer popup.",
                tab = 2,
                cursor_at_end = true,
                input_face = self.other_fields_face,
                scroll = true,
                allow_newline = false,
                force_one_line_height = true,
                margin = Size.margin.small,
            },
        },
        -- two field row:
        {
            {
                text = tostring(item_copy.xray_type) or "1",
                input_type = "number",
                description = self:getXrayTypeLabel(item_copy) .. "\n  " .. self.xray_type_description,
                tab = 2,
                input_face = self.other_fields_face,
                cursor_at_end = true,
                scroll = false,
                allow_newline = false,
                force_one_line_height = true,
                disable_paste = true,
                margin = Size.margin.small,
            },
            {
                text = item_copy.short_names,
                input_type = "text",
                description = "Short names",
                info_popup_text = "Short names: comparable to aliases. But they are comma separated variants of the main name in the first tab. Especially handy when that main name contains many titles and/or additional terms.\n\nFor the popup list of xray items in the page or in paragraphs the script will initially search for these short names (when defined) in their entirety, or in second instance for the first and last name derived from a short name.",
                tab = 2,
                input_face = self.other_fields_face,
                cursor_at_end = true,
                scroll = true,
                allow_newline = false,
                force_one_line_height = true,
                margin = Size.margin.small,
            },
        },
    }
end

function XrayItems:convertFieldValuesToXrayProps(field_values)
    local xray_type = tonumber(field_values[5])
    if not xray_type or xray_type == 0 then
        xray_type = 1
    elseif xray_type > 4 then
        xray_type = 4
    end
    return {
        description = has_text(field_values[1]) or "",
        name = field_values[2],
        aliases = has_text(field_values[3]) or "",
        linkwords = has_text(field_values[4]) or "",
        xray_type = xray_type,
        short_names = has_text(field_values[6]) or "",
    }
end

function XrayItems:getTabCallback(modus, active_form_tab, item_copy)
    return function(form_tab)
        if form_tab == active_form_tab then
            return
        end
        --- @type MultiInputDialog source
        local source = modus == "add" and self.add_item_input or self.edit_item_input
        item_copy = self:convertFieldValuesToXrayProps(source:getValues())
        --[[Dialogs:alertMulti({
            id = item.id,
            name = item.name,
            xray_type = item.xray_type,
            description = item.description,
            short_names = item.short_names,
            linkwords = item.linkwords,
            aliases = item.aliases,
            hits = item.hits,
        })]]
        self:closeForm(modus)
        if modus == "edit" then
            self.edit_item_input = nil
            -- this one is crucial to switch between tabs and preserve changed values!:
            item_copy.index = self.edit_item_index
            self:onEditXrayItem(item_copy, false, form_tab)
        else
            self.add_item_input = nil
            self:onAddXrayItemShowForm(nil, form_tab, item_copy)
        end
    end
end

function XrayItems:getXrayTypeLabel(item)
    return has_text(item.name) and Strings:limitLength(item.name, self.max_line_length) .. ": " or ""
end

function XrayItems:setEbookOrSeriesMode(new_source, item, dont_show)
    XrayHelpers:setEbookOrSeriesIndex(self.current_ebook_or_series, new_source)
    self.current_ebook_or_series = new_source
    self.has_series_index = XrayHelpers:loadAllXrayItems(self.current_ebook_basename, self.current_series, "force_refresh")
    self:onShowXrayList(item, dont_show)
end

function XrayItems:toggleIsImportantXrayItem(toggle_item)
    local xray_items = {}
    local position = 1
    for nr, item in ipairs(XrayHelpers.xray_items) do
        if item.id == toggle_item.id then
            if toggle_item.xray_type == 2 or toggle_item.xray_type == 4 then
                item.xray_type = item.xray_type - 1
            else
                item.xray_type = item.xray_type + 1
            end
            toggle_item.xray_type = item.xray_type
            position = nr
        end
        table.insert(xray_items, item)
    end
    self:updateXrayItemsList(xray_items, "toggle_xray_type", toggle_item.id, toggle_item.xray_type)

    return position, toggle_item
end

function XrayItems:toggleIsPersonOrTerm(toggle_item)
    local xray_items = {}
    local position = 1
    for nr, item in ipairs(XrayHelpers.xray_items) do
        if item.id == toggle_item.id then
            if toggle_item.xray_type <= 2 then
                item.xray_type = item.xray_type + 2
            else
                item.xray_type = item.xray_type - 2
            end
            toggle_item.xray_type = item.xray_type
            position = nr
        end
        table.insert(xray_items, item)
    end
    self:updateXrayItemsList(xray_items, "toggle_xray_type", toggle_item.id, toggle_item.xray_type)

    return position, toggle_item
end

function XrayItems:changeXrayType(new_xray_type)
    -- to be effectuated in ((XrayItems#onSwitchFocus)):
    self.change_xray_type = new_xray_type
    UIManager:close(self.xray_type_chooser)
    self:onSwitchFocus()
end

function XrayItems:generateListItemText(xray_item, nr)
    local icon = XrayHelpers:getIcon(xray_item)
    local hits = has_content(xray_item.hits) and xray_item.hits > 0 and " (" .. xray_item.hits .. ")" or ""
    local text = icon .. xray_item.name .. hits .. ": " .. Strings:lcfirst(xray_item.description)

    return Strings:formatListItemNumber(nr, text, "use_spacer")
end

function XrayItems:setSeries()
    self.current_series = self.ui and self.ui.doc_props and self.ui.doc_props.series
    if not has_text(self.current_series) then
        self.current_series = nil
        return
    end
    self.current_series = self.current_series:gsub(" #%d+", "")
end

function XrayItems:getItems()
    return XrayHelpers.xray_items or {}, XrayHelpers.xray_items_persons or {}, XrayHelpers.xray_items_terms or {}
end

function XrayItems:itemAddHiddenFieldValues(xray_item)
    -- these "hidden" field values were set in ((XrayItems#addHitsToFormOrDialogTitle)):
    if self.form_item_id then
        -- ! never set this value to nil, because we need it when switching between form tabs in the edit form:
        xray_item.id = self.form_item_id
    end
    if self.form_item_hits then
        xray_item.hits = self.form_item_hits
        self.form_item_hits = nil
    end
end

function XrayItems:addHitsToFormOrDialogTitle(xray_item, title, hits_in_book)
    if not hits_in_book or hits_in_book == 0 then
        return title
    end
    local hit_noun = hits_in_book == 1 and " hit" or " hits"
    title = title .. " - " .. hits_in_book .. hit_noun .. " in boek"
    xray_item.hits = hits_in_book

    -- "hidden" fields, re-attached to item after form updates in ((XrayItems#itemAddHiddenFieldValues)):
    self.form_item_id = xray_item.id
    self.form_item_hits = hits_in_book

    return title
end

function XrayItems:initDataJIT()
    self:_initData()
    XrayHelpers:prepareData()
end

return XrayItems
