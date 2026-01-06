
local require = require

local Device = require("device")
local Input = Device.input
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_items = has_items
local pairs = pairs
local table = table
local tostring = tostring
local type = type

local count

--- @class KeyEvents
local KeyEvents = WidgetContainer:extend{
    shared_hotkey_modules = {},
}

--* here we add generic hotkeys for HtmlBox, but a caller might already have added specific hotkeys for that module:
--- @param parent HtmlBox
function KeyEvents:addHotkeysForHtmlBox(parent)
    if not Device:hasKeys() then
        return
    end

    if parent.active_tab and parent.tabs_table_buttons then

        --* see ((TABS)) for more info:
        --* initialize TabNavigator and callbacks:
        KOR.tabnavigator:init(parent.tabs_table_buttons, parent.active_tab, parent.parent)
        for i = 1, 8 do
            local current = i
            --* these callbacks were generated dynamically in ((generate tab navigation event handlers)):
            parent["onActivateTab" .. current] = function()
                return KOR.tabnavigator["onActivateTab" .. current](parent)
            end
        end

        --! don't use self.key_events = {... here, because that might overwrite key_events already defined by a caller:
        self:addKeyEvents(parent, {
            ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
            ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
            ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
            ToPreviousTab = { { Input.group.PgBack }, doc = "naar vorige tab" },
            ToPreviousTabWithShiftSpace = Input.group.ShiftSpace,
            ToNextTab = { { Input.group.PgFwd }, doc = "naar volgende tab" },
            ForceNextTab = { { Input.group.TabNext }, doc = "forceer volgende tab" },
            ForcePreviousTab = { { Input.group.TabPrevious }, doc = "forceer vorige tab" },
            ActivateTab1 = { { "1" } },
            ActivateTab2 = { { "2" } },
            ActivateTab3 = { { "3" } },
            ActivateTab4 = { { "4" } },
            ActivateTab5 = { { "5" } },
            ActivateTab6 = { { "6" } },
            ActivateTab7 = { { "7" } },
            ActivateTab8 = { { "8" } },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
        })
        -- #((set additional key events))
        self:addAdditionalHotkeysHtmlBox(parent)

        return
    end

    --! don't use self.key_events = {... here, because that might overwrite key_events already defined by a caller:
    self:addKeyEvents(parent, {
        ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
        ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
        ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
        ForceNextItem = { { Input.group.TabNext }, doc = "forceer volgend item" },
        ForcePrevItem = { { Input.group.TabPrevious }, doc = "forceer vorige item" },
        Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
    })
    self:addAdditionalHotkeysHtmlBox(parent)
end

--- @param parent TextViewer
function KeyEvents:addHotkeysForTextViewer(parent)
    if not Device:hasKeys() then
        return
    end

    --* TextViewer instance with tabs:
    if parent.active_tab and parent.tabs_table_buttons then

        --* see ((TABS)) for more info:
        --* initialize TabNavigator and callbacks:
        KOR.tabnavigator:init(parent.tabs_table_buttons, parent.active_tab, parent.parent)
        for i = 1, 8 do
            local current = i
            parent["onActivateTab" .. current] = function()
                return KOR.tabnavigator["onActivateTab" .. current](parent)
            end
        end

        parent.key_events = {
            ToPreviousTab = { { Input.group.PgBack }, doc = "naar vorige tab" },
            ToPreviousTabWithShiftSpace = Input.group.ShiftSpace,
            ToNextTab = { { Input.group.PgFwd }, doc = "naar volgende tab" },
            ForceNextTab = { { Input.group.TabNext }, doc = "forceer volgende tab" },
            ForcePreviousTab = { { Input.group.TabPrevious }, doc = "forceer vorige tab" },
            ActivateTab1 = { { "1" } },
            ActivateTab2 = { { "2" } },
            ActivateTab3 = { { "3" } },
            ActivateTab4 = { { "4" } },
            ActivateTab5 = { { "5" } },
            ActivateTab6 = { { "6" } },
            ActivateTab7 = { { "7" } },
            ActivateTab8 = { { "8" } },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
        }
        self:setKeyEventsForTabs(parent, 8)

    --* TextViewer instance without tabs:
    else
        parent.key_events = {
            ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
            ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
            ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
            ForceNextItem = { { Input.group.TabNext }, doc = "forceer volgend item" },
            ForcePrevItem = { { Input.group.TabPrevious }, doc = "forceer vorige item" },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
        }
    end

    self:addExtraButtonsHotkeys(parent, 1)
    self:addAdditionalHotkeysTextViewer(parent)

    --* replace hotkey M for FileManager with M for edit Metadata:
    if parent.add_metadata_edit_hotkey_callback then
        self:addMetadataEditHotkey(parent, "TV")
    end
end

--* information about available hotkeys in list shown in ((XrayDialogs#viewItem)) > ((XrayDialogs#showHelp))
--- @param parent XrayDialogs
function KeyEvents:addHotkeysForXrayItemViewer(parent, event_keys_module)
    self:registerSharedHotkey("E", event_keys_module, function()
        parent:closeViewer()
        DX.c:onShowEditItemForm(DX.vd.current_item, false, 1)
        return true
    end)
    self:registerSharedHotkey("N", event_keys_module, function()
        -- #((next related item via hotkey))
        if DX.m.use_tapped_word_data then
            parent:viewNextTappedWordItem()
            return true
        end
        parent:viewNextItem(DX.vd.current_item)
        return true
    end)
    self:registerSharedHotkey("L", event_keys_module, function()
        parent:closeViewer()
        parent:showList(DX.vd.current_item)
        return true
    end)
    self:registerSharedHotkey("P", event_keys_module, function()
        if DX.m.use_tapped_word_data then
            parent:viewPreviousTappedWordItem()
            return true
        end
        parent:viewPreviousItem(DX.vd.current_item)
        return true
    end)
    local actions = {
        {
            label = "add",
            hotkey = { { "A" } },
            callback = function()
                parent:closeViewer()
                DX.c:resetFilteredItems()
                parent:initAndShowNewItemForm()
                return true
            end,
        },
        {
            label = "delete_for_book",
            hotkey = { { "D" } },
            callback = function()
                parent:showDeleteItemConfirmation(DX.vd.current_item, parent.item_viewer)
                return true
            end,
        },
        {
            label = "delete_for_series",
            hotkey = { { "Shift", { "D" } } },
            callback = function()
                parent:showDeleteItemConfirmation(DX.vd.current_item, parent.item_viewer, "remove_all_instances_in_series")
                return true
            end,
        },
        {
            label = "edit",
            hotkey = { { "E" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("E", event_keys_module)
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
                parent:showHelp(2)
                return true
            end,
        },
        {
            label = "goto_list",
            hotkey = { { "L" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("L", event_keys_module)
            end,
        },
        {
            label = "goto_next_item_viewer",
            hotkey = { { "N" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("N", event_keys_module)
            end,
        },
        {
            label = "open_chapter",
            hotkey = { { "O" } },
            callback = function()
                parent:showJumpToChapterDialog()
                return true
            end,
        },
        {
            label = "goto_previous_item_viewer",
            hotkey = { { "P" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("P", event_keys_module)
            end,
        },
        {
            label = "search_hits",
            hotkey = { { "Shift", { "S" } } },
            callback = function()
                if DX.vd.current_item and has_items(DX.vd.current_item.book_hits) then
                    DX.c:viewItemHits(DX.vd.current_item.name)
                else
                    parent:_showNoHitsNotification(DX.vd.current_item.name)
                end
                return true
            end,
        },
    }
    if DX.m.current_series then
        self:registerSharedHotkey("S", event_keys_module, function()
            KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
            return true
        end)
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("S", event_keys_module)
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
        self:registerCustomKeyEvent(parent.item_viewer, hotkey, "action_" .. label .. suffix, function()
            return callback()
        end)
    end
end

--* information about available hotkeys in list shown in ((XrayButtons#forListTopLeft)) > ((XrayDialogs#showHelp)):
--- @param parent XrayDialogs
function KeyEvents:addHotkeysForXrayList(parent, event_keys_module)
    local actions = {
        {
            label = "import",
            hotkey = { { "I" } },
            callback = function()
                parent:showRefreshHitsForCurrentEbookConfirmation()
                return true
            end,
        },
        {
            label = "show_info",
            hotkey = { { "Shift", { "I" } } },
            callback = function()
                parent:showHelp(1)
                return true
            end,
        },
        {
            label = "toggle_book_series",
            hotkey = { { "M" } },
            callback = function()
                parent:showToggleBookOrSeriesModeDialog(parent.list_args.focus_item, parent.list_args.dont_show)
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
                parent:showImportFromOtherSeriesDialog()
                return true
            end,
        },
    }
    if DX.m.current_series then
        self:registerSharedHotkey("S", event_keys_module, function()
            KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
            return true
        end)
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("S", event_keys_module)
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
        self:registerCustomKeyEvent(parent.xray_items_inner_menu, hotkey, "action_" .. label, function()
            return callback()
        end)
    end

    --* for some reason "7" as hotkey doesn't work under Ubuntu, triggers no event:
    local current_page, per_page
    for i = 1, 9 do
        local current = i
        self:registerCustomKeyEvent(parent.xray_items_inner_menu, { { { tostring(i) } } }, "SelectItemNo" .. current, function()
            current_page = parent.xray_items_inner_menu.page
            per_page = parent.xray_items_inner_menu.perpage
            local item_no = (current_page - 1) * per_page + current
            UIManager:close(parent.xray_items_chooser_dialog)
            parent:viewItem(DX.vd:getItem(item_no))
            return true
        end)
    end
end

--- @param parent XrayPageNavigator
function KeyEvents:addHotkeysForXrayPageNavigator(parent, event_keys_module)
    self:registerSharedHotkey("E", event_keys_module, function()
        return parent:execEditCallback(parent)
    end)
    self:registerSharedHotkey("L", event_keys_module, function()
        return parent:execShowListCallback(parent)
    end)
    self:registerSharedHotkey("N", event_keys_module, function()
        return parent:execGotoNextPageCallback(parent)
    end)
    self:registerSharedHotkey("P", event_keys_module, function()
        return parent:execGotoPrevPageCallback(parent)
    end)
    self:registerSharedHotkey("S", event_keys_module, function()
        return parent:execSettingsCallback(parent)
    end)
    local actions = {
        {
            label = "edit",
            hotkey = { { "E" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("E", event_keys_module)
            end,
        },
        {
            label = "show_info",
            hotkey = { { "I" } },
            callback = function()
                return parent:execShowHelpInfoCallback(parent)
            end,
        },
        {
            label = "jump_navigator",
            hotkey = { { "J" } },
            callback = function()
                return parent:execJumpToCurrentPageInNavigatorCallback(parent)
            end,
        },
        {
            label = "jump_ebook",
            hotkey = { { "Shift", { "J" } } },
            callback = function()
                return parent:execJumpToCurrentPageInEbookCallback(parent)
            end,
        },
        {
            label = "goto_list",
            hotkey = { { "L" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("L", event_keys_module)
            end,
        },
        {
            label = "goto_next_page_navigator",
            hotkey = { { "N" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("N", event_keys_module)
            end,
        },
        {
            label = "goto_previous_navigator",
            hotkey = { { "P" } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("P", event_keys_module)
            end,
        },
        {
            label = "pn_settings",
            hotkey = { { { "S" } } },
            callback = function()
                return KOR.keyevents:execLastSharedHotkey("S", event_keys_module)
            end,
        },
        {
            label = "pn_viewer",
            hotkey = { { { "V" } } },
            callback = function()
                return parent:execViewItemCallback(parent)
            end,
        },
    }

    --* display inforation of first nine items in side panel in bottom info panel, with hotkeys 1 through 9:
    for i = 1, 9 do
        table.insert(actions, {
            label = "show_item_info_" .. i,
            hotkey = { { { tostring(i) } } },
            callback = function()
                if parent.side_buttons and parent.side_buttons[i] then
                    parent.side_buttons[i][1].callback()
                end
                --* we return false instead of true, so the Xray Page Navigator help dialog can activate tabs with number hotkeys:
                if i < 4 then
                    return false
                end
                return true
            end,
        })
    end

    --- SET HOTKEYS FOR HTMLBOX INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initEventKeys)):
    KOR.registry:set("scrolling_html_eventkeys", actions)

    count = #actions
    local hotkey, label
    local suffix = "XPN"
    for i = 1, count do
        hotkey = actions[i].hotkey
        label = actions[i].label
        local callback = actions[i].callback
        self:registerCustomKeyEvent(parent.page_navigator, hotkey, "action_" .. label .. suffix, function()
            return callback()
        end)
    end
end

function KeyEvents:addMetadataEditHotkey(parent, suffix)
    parent.key_events["MetadataEdit" .. suffix] = { { "M" } }
end

function KeyEvents:addHotkeyForFilterButton(parent, filter_active, callback, reset_callback)

    --* because in FileManagerHistory "F" hotkey has been used for activation of Fiction tab, only there use Shift+F:
    local hotkey = KOR.registry:get("history_active") and { { "Shift", { "F" } } } or { { "F" } }
    self:registerCustomKeyEvent(parent, hotkey, "FilterMenu", function()
        parent:resetAllBoldItems()
        if filter_active then
            reset_callback()
        else
            callback()
        end
        return true
    end)
end

--! this method assumes event handler onActivateTab exists in caller:
--- @param parent TextViewer
function KeyEvents:setKeyEventsForTabs(parent, tab_count)
    --* alternate way of handling tab activations; advantage maybe that we only have one, fixed, event handler - ((TextViewer#onActivateTab)):
    for i = 1, tab_count do
        --* format for sending args to event handler: self.key_events.YKey = { { "Y" }, event = "FirstRowKeyPress", args = 0.55 }
        parent.key_events["HandleTabActivation" .. i] = { { tostring(i) }, event = "ActivateTab", args = i }
    end
end

function KeyEvents:registerHotkeysInputDialog(parent)
    if not Device:hasKeys() then
        return
    end

    parent.key_events.CloseDialog = { { Input.group.CloseDialog } }
    --! this one really needed to handle BT keyboard input:
    --* @see ((onGetHardwareInput)):
    parent.key_events.GetHardwareInput = { { Input.group.FieldInput } }
    parent.key_events.IgnoreAltSpace = Input.group.AltSpace

    if parent.activate_tab_callback and parent.tabs_count then
        self:registerTabHotkey(parent)
    end
end

--- @param parent Menu
function KeyEvents:registerHotkeysMenu(parent)
    if not Device:hasKeyboard() then
        --* remove menu item shortcut for K4
        parent.is_enable_shortcut = false
    end

    if Device:hasKeys() then
        --* set up keyboard events
        parent.key_events.Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
        parent.key_events.NextPage = { { Input.group.PgFwd } }
        parent.key_events.PrevPage = { { Input.group.PgBack } }
        parent.key_events.PrevPageWithShiftSpace = Input.group.ShiftSpace

        if parent.tab_labels and parent.activate_tab_callback then
            self:registerTabHotkeys(parent)
        end
    end

    if Device:hasDPad() then
        --* we won't catch presses to "Right", leave that to MenuItem.
        parent.key_events.FocusRight = nil
        --* shortcut icon is not needed for touch device
        if parent.is_enable_shortcut then
            parent.key_events.SelectByShortCut = { { parent.item_shortcuts } }
        end
        parent.key_events.Right = { { "Right" } }
    end
end

--- @param parent InputDialog
function KeyEvents:registerTabHotkey(parent)
    --* for the input field we filtered Shift+Space hotkeys out, to enable this tab activation; see ((enable tab activation with Shift+Space)) above:
    parent.key_events.ActivateNextTab = Input.group.AltT
end

--- @param parent TextViewer
function KeyEvents:addExtraButtonsHotkeys(parent, no)
    if parent.extra_button_callback and parent.extra_button_hotkey then
        parent["onExtraButtonCallback" .. no] = function()
            return parent.extra_button_callback()
        end
        parent.key_events["ExtraButtonCallback" .. no] = parent.extra_button_hotkey
    end
end

--* these additional_key_events might have been set by the caller of HtmlBox:
--- @param parent HtmlBox
function KeyEvents:addAdditionalHotkeysHtmlBox(parent)
    if parent.additional_key_events then
        for label, hk_data in pairs(parent.additional_key_events) do
            local close_box = hk_data[3] and true or false
            if close_box then
                UIManager:close(parent)
            end
            parent["on" .. label .. "HB"] = function()
                return hk_data[2]()
            end
            parent.key_events[label] = hk_data[1]
        end
    end
end

--- @param parent TextViewer
function KeyEvents:addAdditionalHotkeysTextViewer(parent)
    if parent.additional_key_events then
        for label, hk_data in pairs(parent.additional_key_events) do
            local keep_textviewer_open = hk_data[3] and true or false
            parent["on" .. label .. "_TV"] = function()
                if not keep_textviewer_open then
                    UIManager:close(parent)
                end
                return hk_data[2]()
            end
            parent.key_events[label .. "_TV"] = hk_data[1]
        end
    end
end

function KeyEvents:registerCustomKeyEvent(parent, hotkey, handler_label, handler_callback)
    parent["on" .. handler_label] = handler_callback
    parent.key_events[handler_label] = type(hotkey) == "table" and hotkey or { { hotkey } }
end

--- @param parent Menu
function KeyEvents:registerTabHotkeys(parent)
    local action, hotkey
    count = #parent.tab_labels
    for i = 1, count do
        local current = i
        action = parent.tab_labels[current]
        hotkey = action:sub(1, 1):upper()
        self:registerCustomKeyEvent(parent, hotkey, "ActivateTab_" .. action, function()
            return self:activateTab(parent, current)
        end)
    end
end

--- @param parent Menu
function KeyEvents:activateTab(parent, tab_no)
    parent.activate_tab_callback(tab_no)
end

--- @param parent Menu
function KeyEvents:updateHotkeys(parent)
    if parent.hotkey_updater then
        parent.hotkey_updater()
    end
end

function KeyEvents:execLastSharedHotkey(key, module)
    local module_key = self.shared_hotkey_modules[key]
    if not module_key or #module_key == 0 or module_key[#module_key][1] ~= module then
        return false
    end
    --* exec the callback for the hotkey:
    return module_key[#module_key][2]()
end

function KeyEvents:registerSharedHotkey(key, module, callback)
    local module_key = self.shared_hotkey_modules[key]
    if not module_key then
        self.shared_hotkey_modules[key] = {}
        module_key = self.shared_hotkey_modules[key]
    end

    if #module_key > 0 and module_key[#module_key][1] == module then
        return
    end

    table.insert(self.shared_hotkey_modules[key], {module, callback})
    --KOR.messages:notify("registered: " .. key .. " > " .. #self.shared_hotkey_modules[key])
end

function KeyEvents:unregisterSharedHotkeys(module)
    for key, imodule in pairs(self.shared_hotkey_modules) do
        count = #imodule
        for i = count, 1, -1 do
            if imodule[i][1] ~= module then
                break
            end
            self.shared_hotkey_modules[key][i] = nil
        end
        --KOR.messages:notify("hoera: " .. module .. " > " .. #self.shared_hotkey_modules[key])
    end
end

--- @private
function KeyEvents:addKeyEvents(parent, events)
    if not parent.key_events then
        parent.key_events = {}
    end
    count = #events
    for i = 1, count do
        table.insert(parent.key_events, events[i])
    end
end

function KeyEvents:getHotkeysInformation()

    local in_filemanager = KOR.registry:get("infilemanager")
    if not in_filemanager then
        return {
            "Dit venster oproepbaar met sneltoets \"2\"...",
            "De letter- en de shift-cijfer-sneltoetsen hieronder werken ook vanuit dit dialoogvenster...",
            "",
            "/ = naar vorige boek",
            "Cmd+Del = ESC/Back: terug naar vorige locatie",
            "Omlaag = sluit dialoogvenster",
            "Enter = toon ondermenu",
            "Spatie = blader vooruit",
            "Shift+Spatie/Del = blader terug",
            "",
            "1 = ga naar begin document (eerste cijfer)",
            "0 = ga naar einde document (laatste cijfer)",
            "Shift+0 = toon globale lijst van getagde bladwijzers",
            "2 = toon overzicht gebaren",
            "3 = toon SeriesManager",
            "4 = blader",
            "5 = blader hier",
            "Shift+5 = toon lijst 5-sterren boeken",
            "6 = zoek boek",
            "Shift+6 = toon lijst 6-sterren boeken",
            "7 = zoek tekst in huidig boek",
            "8 = spring naar laatst gelezen pagina",
            "9 = spring naar vorige locatie",
            "",
            ". = toon snelle statistieken",
            "A = toon Aanwinsten getegeld",
            "Shift+A = toon maandAgenda",
            "B = toon Bladwijzers",
            "Shift+B = toon Bladwijzer filterpaneel",
            "C = toon boek preview",
            "Shift+C = toon Collecties overzicht",
            "D = toon Description dialog",
            "E = toon Eerstvolgend getegeld",
            "Shift+E = toon mEeste pagina’s gelezen per maand",
            "F = toon Favorieten / toon Filterdialoog in Menus",
            "Shift+F = toon keuze-popup voor Finished boeken / toon Filterdialoog in Geschiedenis",
            "G = toon Gelezen boeken",
            "Shift+G = toon bookmarksnavigator voor Globale bladwijzers",
            "H = toon History",
            "I = toon hIstogram venster voor dagen / discription Indicator uitleg, waar van toepassing",
            "Shift+I = toon overzicht Inleidingsideeën",
            "J = Jump naar laatste gelogde pagina",
            "K = toon leesdagen boeK",
            "L = toon Leesplan getegeld",
            "Shift+L = toon geLogde ebook pagina’s voor huidige boek",
            "M = ga naar fileManager / edit Metadata in dialogen met tag-button",
            "Shift+M = toon boektitels per Maand",
            "N = toon impressioNs",
            "Shift+N = toon bookmarksNavigator voor huidig boek",
            "O = toon crashlOgviewer",
            "Shift+O = toon wOorden die je vandaag bekeek",
            "P = toggle Privacy filter",
            "Q = Quick screen refresh",
            "Shift+Q = exit/Quit KOReader",
            "R = toon Reader progress",
            "Shift+R = toon pagina’s gelezen per maand",
            "S = Save all Settings",
            "Shift+S = boek-impressieS: lijst",
            "T = toon readinglisTs",
            "Shift+T = toon Timeline (dag-agenda)",
            "U = toon leesUren per boek",
            "Shift+U = toon lijst belangrijke teksten (Uitzonderlijk)",
            "V = toon ModulesDialog",
            "Shift+V = toon DeveloperTools",
            "W = toon Winnaars getegeld",
            "Shift+W = toon genomineerd getegeld",
            "X = toon inhoudsopgave/indeX",
            "Shift+X = toon Xray page navigator",
            "Z = Toon shortcuts dialog",
            "Shift+Z = Toon xray items (lijst)",
            "",
            "MODULES",
            "",
            "Geschiedenis: activeer tab met beginletter",
            "Menu: filterbutton (reset) = Shift+F",
        }
    end

    return {
        "FILEMANAGER",
        "Dit venster oproepbaar met sneltoets Shift+2...",
        "",
        "1 t/m 9 = open dit boeknummer uit de actieve subpagina",
        "\"/\" = naar vorige boek",
        "",
        "B = Blader hier",
        "H = geschiedenis (History)",
        "I = toon uitleg status-Indicatoren",
        "",
        "J = ga naar map Jaarboeken",
        "M = ga naar map Meditatie",
        "P = ga naar map Programmeren",
        "R = ga naar map Romans",
        "S = ga naar map Science Fiction",
        "T = ga naar map spirtualiTeit",
        "V = ga naar map samenVattingen",
        "Y = ga naar map mYstiek",
    }
end

return KeyEvents
