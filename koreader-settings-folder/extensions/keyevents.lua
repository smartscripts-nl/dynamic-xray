
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
    shared_hotkeys = {},
}

--* here we add generic hotkeys for HtmlBox, but a caller might already have added specific hotkeys for that module:
--- @param parent HtmlBox
function KeyEvents:addHotkeysForHtmlBox(parent, key_events_module)
    if not Device:hasKeys() then
        return
    end
    if not key_events_module then
        key_events_module = "HtmlBox"
    end

    if parent.active_tab and parent.tabs_table_buttons then

        parent.key_events = {
            ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
            ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
            ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
            ToPreviousTab = { { Input.group.PgBack }, doc = "naar vorige tab" },
            ToPreviousTabWithShiftSpace = Input.group.ShiftSpace,
            ToNextTab = { { Input.group.PgFwd }, doc = "naar volgende tab" },
            ForceNextTab = { { Input.group.TabNext }, doc = "forceer volgende tab" },
            ForcePreviousTab = { { Input.group.TabPrevious }, doc = "forceer vorige tab" },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
        }
        -- #((set additional key events))
        self:addAdditionalHotkeysHtmlBox(parent)

        --* see ((TABS)) for more info:
        --* initialize TabNavigator and callbacks:
        KOR.tabnavigator:init(parent.tabs_table_buttons, parent.active_tab, parent.parent)
        for i = 1, 8 do
            local current = i
            self:registerCustomKeyEvent(key_events_module, parent, current, "ActivateTab" .. current, function()
                --* these callbacks were generated dynamically in ((generate tab navigation event handlers)):
                return KOR.tabnavigator["onActivateTab" .. current](parent)
            end)
        end

        return
    end

    parent.key_events = {
        ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
        ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
        ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
        ForceNextItem = { { Input.group.TabNext }, doc = "forceer volgend item" },
        ForcePrevItem = { { Input.group.TabPrevious }, doc = "forceer vorige item" },
        Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
    }
    self:addAdditionalHotkeysHtmlBox(parent)
end

--- @param parent TextViewer
function KeyEvents:addHotkeysForTextViewer(parent, key_events_module)
    if not Device:hasKeys() then
        return
    end
    if not key_events_module then
        key_events_module = "TextViewer"
    end

    --* TextViewer instance with tabs:
    if parent.active_tab and parent.tabs_table_buttons then

        parent.key_events = {
            ToPreviousTab = { { Input.group.PgBack }, doc = "naar vorige tab" },
            ToPreviousTabWithShiftSpace = Input.group.ShiftSpace,
            ToNextTab = { { Input.group.PgFwd }, doc = "naar volgende tab" },
            ForceNextTab = { { Input.group.TabNext }, doc = "forceer volgende tab" },
            ForcePreviousTab = { { Input.group.TabPrevious }, doc = "forceer vorige tab" },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
        }
        --self:setKeyEventsForTabs(parent, 8)
        --* see ((TABS)) for more info:
        --* initialize TabNavigator and callbacks:
        KOR.tabnavigator:init(parent.tabs_table_buttons, parent.active_tab, parent.parent)
        for i = 1, 8 do
            local current = i
            self:registerCustomKeyEvent(key_events_module, parent, current, "ActivateTab" .. current, function()
                --* these callbacks were generated dynamically in ((generate tab navigation event handlers)):
                return KOR.tabnavigator["onActivateTab" .. current](parent)
            end)
        end

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
end

--* information about available hotkeys in list shown in ((XrayDialogs#showItemViewer)) > ((XrayDialogs#showHelp)):
-- #((KeyEvents#addHotkeysForXrayItemViewer))
--* compare ((KeyEvents#setHotkeyForXrayPageNavigator)):
function KeyEvents.addHotkeysForXrayItemViewer(key_events_module)
    local self = KOR.keyevents
    local parent = DX.d
    self:registerSharedHotkeys(key_events_module, {
        ["E"] = function()
            parent:closeViewer()
            DX.c:onShowEditItemForm(DX.vd.current_item, false, 1)
            return true
        end,
        ["N"] = function()
            -- #((next related item via hotkey))
            if DX.m.use_tapped_word_data then
                parent:viewNextTappedWordItem()
                return true
            end
            parent:viewNextItem(DX.vd.current_item)
            return true
        end,
        ["L"] = function()
            parent:closeViewer()
            parent:showList(DX.vd.current_item)
            return true
        end,
        ["P"] = function()
            if DX.m.use_tapped_word_data then
                parent:viewPreviousTappedWordItem()
                return true
            end
            parent:viewPreviousItem(DX.vd.current_item)
            return true
        end,
    })

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
                return self:execTopMostSharedHotkey("E", key_events_module)
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
                return self:execTopMostSharedHotkey("L", key_events_module)
            end,
        },
        {
            label = "goto_next_item_viewer",
            hotkey = { { "N" } },
            callback = function()
                return self:execTopMostSharedHotkey("N", key_events_module)
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
                return self:execTopMostSharedHotkey("P", key_events_module)
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
        self:registerSharedHotkey("S", key_events_module, function()
            KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
            return true
        end)
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                return self:execTopMostSharedHotkey("S", key_events_module)
            end,
        })
    end

    --- SET HOTKEYS FOR HTMLBOXWIDGET INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", actions)

    count = #actions
    local hotkey, label
    local suffix = "XVC"
    for i = 1, count do
        hotkey = actions[i].hotkey
        label = actions[i].label
        local callback = actions[i].callback
        self:registerCustomKeyEvent(key_events_module, parent.item_viewer, hotkey, "action_" .. label .. suffix, function()
            return callback()
        end)
    end
end

--* information about available hotkeys in list shown in ((XrayButtons#forListTopLeft)) > ((XrayDialogs#showHelp)):
--- @param parent XrayDialogs
function KeyEvents:addHotkeysForXrayList(parent, key_events_module)
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
        self:registerSharedHotkey("S", key_events_module, function()
            KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
            return true
        end)
        table.insert(actions, {
            label = "show_serie",
            hotkey = { { "S" } },
            callback = function()
                return self:execTopMostSharedHotkey("S", key_events_module)
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
        self:registerCustomKeyEvent(key_events_module, parent.xray_items_inner_menu, hotkey, "action_" .. label, function()
            return callback()
        end)
    end

    --* for some reason "7" as hotkey doesn't work under Ubuntu, triggers no event:
    local current_page, per_page
    for i = 1, 9 do
        local current = i
        self:registerCustomKeyEvent(key_events_module, parent.xray_items_inner_menu, { { { tostring(i) } } }, "SelectItemNo" .. current, function()
            current_page = parent.xray_items_inner_menu.page
            per_page = parent.xray_items_inner_menu.perpage
            local item_no = (current_page - 1) * per_page + current
            UIManager:close(parent.xray_items_chooser_dialog)
            parent:showItemViewer(DX.vd:getItem(item_no))
            return true
        end)
    end
end

-- #((KeyEvents#setHotkeyForXrayPageNavigator))
--* compare ((KeyEvents#addHotkeysForXrayItemViewer)) and see comment in ((HtmlBox#initHotkeys)):
function KeyEvents.setHotkeyForXrayPageNavigator(key_events_module)
    local self = KOR.keyevents
    local parent = DX.pn

    self:registerSharedHotkeys(key_events_module, {
        ["E"] = function()
            return parent:execEditCallback(parent)
        end,
        ["L"] = function()
            return parent:execShowListCallback(parent)
        end,
        ["N"] = function()
            return parent:execGotoNextPageCallback(parent)
        end,
        ["P"] = function()
            return parent:execGotoPrevPageCallback(parent)
        end,
        ["S"] = function()
            return parent:execSettingsCallback(parent)
        end,
    })
    parent.hotkeys = {
        {
            label = "edit",
            hotkey = { { "E" } },
            callback = function()
                return self:execTopMostSharedHotkey("E", key_events_module)
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
                return self:execTopMostSharedHotkey("L", key_events_module)
            end,
        },
        {
            label = "goto_next_page_navigator",
            hotkey = { { "N" } },
            callback = function()
                return self:execTopMostSharedHotkey("N", key_events_module)
            end,
        },
        {
            label = "goto_previous_navigator",
            hotkey = { { "P" } },
            callback = function()
                return self:execTopMostSharedHotkey("P", key_events_module)
            end,
        },
        {
            label = "pn_settings",
            hotkey = { { { "S" } } },
            callback = function()
                return self:execTopMostSharedHotkey("S", key_events_module)
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

    --! definitions of numerical hotkeys can only be done after PageNavigator dialog has been defined, because only then side_buttons are also defined:
    --* display information of first nine items in side panel in bottom info panel, with hotkeys 1 through 9:
    for i = 1, 9 do
        local nhotkey = tostring(i)
        local side_button = parent:getSideButton(i)
        if not side_button then
            break
        end
        self:registerSharedHotkey(nhotkey, key_events_module, function()
            local nside_button = side_button
            nside_button[1].callback()
            return true
        end)
        table.insert(parent.hotkeys, {
            label = "show_item_info_" .. nhotkey,
            hotkey = { { nhotkey } },
            callback = function()
                return self:execTopMostSharedHotkey(nhotkey, key_events_module)
            end,
        })
    end

    --- SET HOTKEYS FOR HTMLBOXWIDGET INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", parent.hotkeys)

    count = #parent.hotkeys
    local hotkey, label
    local suffix = "XPN"
    for i = 1, count do
        hotkey = parent.hotkeys[i].hotkey
        label = parent.hotkeys[i].label
        local callback = parent.hotkeys[i].callback
        self:registerCustomKeyEvent(key_events_module, parent.page_navigator, hotkey, "action_" .. label .. suffix, function()
            return callback()
        end)
    end
end

function KeyEvents:addHotkeyForFilterButton(parent, filter_active, callback, reset_callback)

    --* because in FileManagerHistory "F" hotkey has been used for activation of Fiction tab, only there use Shift+F:
    local hotkey = KOR.registry:get("history_active") and { { "Shift", { "F" } } } or { { "F" } }
    self:registerCustomKeyEvent("Menu", parent, hotkey, "FilterMenu", function()
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

function KeyEvents:registerCustomKeyEvent(key_events_module, parent, hotkey, callback_label, callback)
    --! hotfix, shouldn't be necessary, but is:
    if not parent then
        parent = DX.d
    end
    if type(hotkey) == "number" then
        hotkey = { { tostring(hotkey) } }
    elseif type(hotkey) ~= "table" then
        hotkey = { { hotkey } }
    end
    self:registerSharedHotkey(hotkey, key_events_module, function()
        return callback()
    end)

    parent["on" .. callback_label] = function()
        return self:execTopMostSharedHotkey(hotkey, key_events_module)
    end
    parent.key_events[callback_label] = hotkey
end

--- @param parent Menu
function KeyEvents:registerTabHotkeys(parent)
    local action, hotkey
    count = #parent.tab_labels
    for i = 1, count do
        local current = i
        action = parent.tab_labels[current]
        hotkey = action:sub(1, 1):upper()
        self:registerCustomKeyEvent("Menu", parent, hotkey, "ActivateTab_" .. action, function()
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

function KeyEvents:execTopMostSharedHotkey(key, key_events_module)
    local keys_registry = self.shared_hotkeys[key]
    if not keys_registry or #keys_registry == 0 or keys_registry[#keys_registry][1] ~= key_events_module then
        return false
    end
    --* exec the callback for the hotkey:
    return keys_registry[#keys_registry][2]()
end

--- @private
function KeyEvents:registerSharedHotkey(key, key_events_module, callback)
    local keys_registry = self.shared_hotkeys[key]
    if not keys_registry then
        self.shared_hotkeys[key] = {}
        keys_registry = self.shared_hotkeys[key]
    end

    if #keys_registry > 0 and keys_registry[#keys_registry][1] == key_events_module then
        return
    end

    table.insert(self.shared_hotkeys[key], { key_events_module, callback })
end

--- @private
function KeyEvents:registerSharedHotkeys(key_events_module, shared_hotkeys)
    for key, callback in pairs(shared_hotkeys) do
        self:registerSharedHotkey(key, key_events_module, callback)
    end
end

function KeyEvents:unregisterSharedHotkeys(key_events_module)
    for key, key_props in pairs(self.shared_hotkeys) do
        count = #key_props
        for i = count, 1, -1 do
            if key_props[i][1] ~= key_events_module then
                break
            end
            self.shared_hotkeys[key][i] = nil
        end
    end
end

return KeyEvents
