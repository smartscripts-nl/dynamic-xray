local require = require

local Device = require("device")
local Input = Device.input
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_items = has_items
local pairs = pairs
local table_insert = table.insert
local tostring = tostring
local type = type

local count

--- @class KeyEvents
local KeyEvents = WidgetContainer:extend{
    shared_hotkeys = {},
}

--* here we add generic hotkeys for FilesBox, but a caller might already have added specific hotkeys for that module:
--- @param parent FilesBox
function KeyEvents:addHotkeysForFilesBox(parent, key_events_module)
    if not Device:hasKeys() then
        return
    end
    if not key_events_module then
        key_events_module = "FilesBox"
    end

    self:addCloseHotkey(parent)
end

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
        }
        self:addCloseHotkey(parent)
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
    }
    self:addCloseHotkey(parent)
    self:addAdditionalHotkeysHtmlBox(parent)
end

--* here we add generic hotkeys for NavigatorBox, but a caller might already have added specific hotkeys for that module:
--- @param parent NavigatorBox
function KeyEvents:addHotkeysForNavigatorBox(parent, key_events_module)
    if not Device:hasKeys() then
        return
    end
    if not key_events_module then
        key_events_module = "NavigatorBox"
    end

    parent.key_events = {
        ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
        ReadPrevItemWithShiftSpace = Input.group.ShiftSpace,
        ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
        ForceNextItem = { { Input.group.TabNext }, doc = "forceer volgend item" },
        ForcePrevItem = { { Input.group.TabPrevious }, doc = "forceer vorige item" },
    }
    self:addCloseHotkey(parent)
    self:addAdditionalHotkeysNavigatorBox(parent)
end

--* here we add global hotkeys for ReaderUI:
--- @param parent XrayController
function KeyEvents:addHotkeysForReaderUI(parent)
    local is_docless = KOR.ui == nil or KOR.ui.document == nil
    --* first condition: points to the event handler: don't create the method anew every time you open another ebook:
    if is_docless or KOR.ui.ShowXrayHelpUI or not Device:hasKeys() then
        return
    end

    local readerui = KOR.ui
    readerui.key_events.ShowXrayHelpUI = { { "Shift", { "H" } } }
    readerui.onShowXrayHelpUI = function()
        return DX.i:showPageNavigatorHelp(parent, 3)
    end

    readerui.key_events.ShowXrayListUI = { { "Shift", { "L" } } }
    readerui.onShowXrayListUI = function()
        DX.c:onShowList()
    end

    readerui.key_events.ShowCurrentSeriesUI = { { "Shift", { "M" } } }
    readerui.onShowCurrentSeriesUI = function()
        DX.c:onShowCurrentSeries()
    end

    readerui.key_events.ShowPageNavigatorUI = { { "Shift", { "X" } } }
    readerui.onShowPageNavigatorUI = function()
        DX.c:onShowPageNavigator()
    end
end

--* disable
function KeyEvents:disableHotkeysForReaderUI()
    local is_docless = KOR.ui == nil or KOR.document == nil
    --* first condition: points to the event handler: don't create the method anew every time you open another ebook:
    if is_docless or not Device:hasKeys() then
        return
    end

    local readerui = KOR.ui
    readerui.key_events.ShowXrayHelpUI = nil
    readerui.onShowXrayHelpUI = nil

    readerui.key_events.ShowXrayListUI = nil
    readerui.onShowXrayListUI = nil

    readerui.key_events.ShowCurrentSeriesUI = nil
    readerui.onShowCurrentSeriesUI = nil

    readerui.key_events.ShowPageNavigatorUI = nil
    readerui.onShowPageNavigatorUI = nil
end

--* here we add generic hotkeys for ScrollTextWidget, but a caller might already have added specific hotkeys for that module:
--- @param parent ScrollTextWidget
function KeyEvents:addHotkeysForScrollTextWidget(parent, key_events_module)
    if not Device:hasKeys() then
        return
    end
    if not key_events_module then
        key_events_module = "ScrollTextWidget"
    end

    parent.key_events = {
        ScrollDown = { { Input.group.PgFwdScrollText } },
        ScrollUp = { { Input.group.PgBackScrollText } },
        -- #((navigate up in ScrollTextWidget with shift+space))
        ScrollUpWithShiftSpace = Input.group.ShiftSpace,
    }
    self:addCloseHotkey(parent)
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
        }
    end
    self:addCloseHotkey(parent)
    self:addExtraButtonsHotkeys(parent, 1)
    self:addAdditionalHotkeysTextViewer(parent)

    --* examples of hotkeys configurators: ((KeyEvents#addHotkeysForXrayPageNavigator)) and ((KeyEvents#addHotkeysForXrayItemViewer)):
    if parent.hotkeys_configurator then
        parent.hotkeys_configurator()
    end
end

--* information about available hotkeys in list shown in ((XrayDialogs#showItemViewer)) > ((XrayInformation#showListAndViewerHelp)):
-- #((KeyEvents#addHotkeysForXrayItemViewer))
--* compare ((KeyEvents#addHotkeysForXrayPageNavigator)):
function KeyEvents.addHotkeysForXrayItemViewer(key_events_module)
    local self = KOR.keyevents
    local parent = DX.d
    self:registerSharedHotkeys(key_events_module, {
        [DX.s.hk_edit_item] = function()
            parent:closeViewer()
            DX.c:onShowEditItemForm(DX.vd.current_item, false, 1)
            return true
        end,
        [DX.s.hk_goto_next_item] = function()
            -- #((next related item via hotkey))
            if DX.m.use_tapped_word_data then
                parent:viewNextTappedWordItem()
                return true
            end
            parent:viewNextItem(DX.vd.current_item)
            return true
        end,
        [DX.s.hk_show_list] = function()
            parent:closeViewer()
            parent:showList(DX.vd.current_item)
            return true
        end,
        [DX.s.hk_goto_previous_item] = function()
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
            hotkey = { { DX.s.hk_add_item } },
            callback = function()
                parent:closeViewer()
                DX.c:resetFilteredItems()
                parent:showNewItemForm()
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
            hotkey = { { DX.s.hk_edit_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_edit_item, key_events_module)
            end,
        },
        {
            label = "hits",
            hotkey = { { DX.s.hk_show_item_occurrences } },
            callback = function()
                if DX.vd.current_item and has_items(DX.vd.current_item.book_hits) then
                    DX.c:viewItemHits(DX.vd.current_item.name)
                else
                    parent:_showNoHitsNotification(DX.vd.current_item.name)
                end
                return true
            end,
        },
        {
            label = "show_info",
            hotkey = { { DX.s.hk_show_information } },
            callback = function()
                return DX.i:showListAndViewerHelp(2)
            end,
        },
        {
            label = "goto_list",
            hotkey = { { DX.s.hk_show_list } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_show_list, key_events_module)
            end,
        },
        {
            label = "goto_next_item_viewer",
            hotkey = { { DX.s.hk_goto_next_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_goto_next_item, key_events_module)
            end,
        },
        {
            label = "open_chapter",
            hotkey = { { DX.s.hk_open_chapter_from_viewer } },
            callback = function()
                parent:showJumpToChapterDialog()
                return true
            end,
        },
        {
            label = "goto_previous_item_viewer",
            hotkey = { { DX.s.hk_goto_previous_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_goto_previous_item, key_events_module)
            end,
        },
    }
    self:addSeriesManagerHotkey(actions)

    --- SET HOTKEYS FOR HTMLBOXWIDGET INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", actions)
end

--* information about available hotkeys in list shown in ((XrayButtons#forListTopLeft)) > ((XrayInformation#showListAndViewerHelp)):
--* compare for filtering Menu lists in general ((KeyEvents#addHotkeyForFilterButton)):
--- @param parent XrayDialogs
function KeyEvents:addHotkeysForXrayList(parent, key_events_module)
    local actions = {
        {
            label = "add",
            hotkey = { { DX.s.hk_add_item } },
            callback = function()
                DX.c:onShowNewItemForm()
                return true
            end,
        },
        {
            label = "import",
            hotkey = { { "Shift", { "I" } } },
            callback = function()
                parent:showRefreshHitsForCurrentEbookConfirmation()
                return true
            end,
        },
        {
            label = "show_info",
            hotkey = { { DX.s.hk_show_information } },
            callback = function()
                return DX.i:showListAndViewerHelp(1)
            end,
        },
        {
            label = "show_navigator",
            hotkey = { { DX.s.hk_open_page_navigator_from_list } },
            callback = function()
                return DX.c:openPageNavigatorFromList()
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
            label = "import_from_other_serie",
            hotkey = { { "X" } },
            callback = function()
                parent:showImportFromOtherSeriesDialog()
                return true
            end,
        },
    }
    self:addSeriesManagerHotkey(actions)

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

    --? for some reason "7" as hotkey doesn't work under Ubuntu, triggers no event:
    local current_page, per_page
    for i = 1, 9 do
        local current = i
        self:registerCustomKeyEvent(key_events_module, parent.xray_items_inner_menu, { { { tostring(i) } } }, "SelectItemNo" .. current, function()
            current_page = parent.xray_items_inner_menu.page
            per_page = parent.xray_items_inner_menu.perpage
            local item_no = (current_page - 1) * per_page + current
            UIManager:close(parent.xray_items_chooser_dialog)
            local item = DX.vd:getItem(item_no)
            if parent.select_mode then
                parent.select_mode = false
                DX.p:toPrevOrNextNavigatorPage(item)
            else
                parent:showItemViewer(item)
            end
            return true
        end)
    end
end

-- #((KeyEvents#addHotkeysForXrayPageNavigator))
--* compare ((KeyEvents#addHotkeysForXrayItemViewer)) and see comment in ((HtmlBox#initHotkeys)):
function KeyEvents.addHotkeysForXrayPageNavigator(key_events_module)
    local self = KOR.keyevents
    local parent = DX.pn

    self:registerSharedHotkeys(key_events_module, {
        [DX.s.hk_edit_item] = function()
            return DX.cb:execEditCallback(parent)
        end,
        [DX.s.hk_show_list] = function()
            return DX.cb:execShowListCallback(parent)
        end,
        [DX.s.hk_goto_next_item] = function()
            return DX.cb:execGotoNextPageCallback()
        end,
        [DX.s.hk_goto_previous_item] = function()
            return DX.cb:execGotoPrevPageCallback()
        end,
        ["S"] = function()
            return DX.cb:execSettingsCallback(parent)
        end,
    })
    local actions = {
        {
            label = "pagebrowser",
            hotkey = { { DX.s.hk_show_pagebrowser_from_page_navigator } },
            callback = function()
                return DX.cb:execShowPageBrowserCallback(parent)
            end,
        },
        {
            label = "edit",
            hotkey = { { DX.s.hk_edit_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_edit_item, key_events_module)
            end,
        },
        {
            label = "export_items",
            hotkey = { { DX.s.hk_open_export_list } },
            callback = function()
                return DX.cb:execExportXrayItemsCallback()
            end,
        },
        {
            label = "show_info",
            hotkey = { { DX.s.hk_show_information } },
            callback = function()
                return DX.cb:execShowHelpInfoCallback(parent)
            end,
        },
        {
            label = "jump_navigator",
            hotkey = { { "J" } },
            callback = function()
                return DX.cb:execJumpToCurrentPageInNavigatorCallback()
            end,
        },
        {
            label = "jump_ebook",
            hotkey = { { "Shift", { "J" } } },
            callback = function()
                return DX.cb:execJumpToCurrentPageInEbookCallback(parent)
            end,
        },
        {
            label = "jump_to_page_no",
            hotkey = { { DX.s.hk_page_navigator_jump_to_page_no } },
            callback = function()
                return DX.cb:execJumpToPageCallback()
            end,
        },
        {
            label = "goto_list",
            hotkey = { { DX.s.hk_show_list } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_show_list, key_events_module)
            end,
        },
        {
            label = "goto_next_page_navigator",
            hotkey = { { DX.s.hk_goto_next_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_goto_next_item, key_events_module)
            end,
        },
        {
            label = "goto_previous_navigator",
            hotkey = { { DX.s.hk_goto_previous_item } },
            callback = function()
                return self:execTopMostSharedHotkey(DX.s.hk_goto_previous_item, key_events_module)
            end,
        },
        {
            label = "pn_settings",
            hotkey = { { { DX.s.hk_open_xray_settings_from_page_navigator } } },
            callback = function()
                return self:execTopMostSharedHotkey("S", key_events_module)
            end,
        },
        {
            label = "pn_search_item",
            hotkey = { { "Shift", { "S" } } },
            callback = function()
                return DX.cb:execPageNavigatorSearchItemCallback()
            end,
        },
        {
            label = "pn_popup_menu",
            --* in ((XrayCallbacks#execShowPopupButtonsCallback)) an additional key_event with the same hotkey will be added to the popup menu, to close it again:
            hotkey = { { DX.s.hk_page_navigator_popup_menu } },
            callback = function()
                return DX.cb:execShowPopupButtonsCallback(parent)
            end,
        },
        {
            label = "pn_viewer",
            hotkey = { { { DX.s.hk_view_item_from_list_or_navigator } } },
            callback = function()
                return DX.cb:execViewItemCallback()
            end,
        },
    }

    --! definitions of numerical hotkeys can only be done after PageNavigator dialog has been defined, because only then side_buttons are also defined:
    --* display information of first nine items in side panel in bottom info panel, with hotkeys 1 through 9:
    for i = 1, 9 do
        local nhotkey = tostring(i)
        local side_button = DX.sp:getSideButton(i)
        if not side_button then
            break
        end
        self:registerSharedHotkey(nhotkey, key_events_module, function()
            local nside_button = side_button
            --* callback defined in ((XrayPages#markedItemRegister)):
            nside_button.callback()
            return true
        end)
        table_insert(actions, {
            label = "show_item_info_" .. nhotkey,
            hotkey = { { nhotkey } },
            callback = function()
                return self:execTopMostSharedHotkey(nhotkey, key_events_module)
            end,
        })
    end

    self:addSeriesManagerHotkey(actions)

    --- SET HOTKEYS FOR HTMLBOXWIDGET INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((HtmlBoxWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", actions)
end

--- @param parent XrayPageNavigator
function KeyEvents:addHotkeysForXrayPageNavigatorPopupMenu(parent)
    return {
        --* this is a toggle, which now closes the popup menu with the same hotkey with which it was opened:
        ClosePopupMenu = {
            { { DX.s.hk_page_navigator_popup_menu } }, function()
                parent:closePopupMenu()
                return true
            end
        },
        ShowList = {
            { { DX.s.hk_show_list } }, function()
                parent:closePopupMenu()
                DX.d:showList(DX.vd.current_item)
                return true
            end
        },
        ShowExportList = {
            { { DX.s.hk_open_export_list } }, function()
                parent:closePopupMenu()
                return DX.cb:execExportXrayItemsCallback()
            end
        },
        ShowPageBrowser = {
            { { DX.s.hk_show_pagebrowser_from_page_navigator } }, function()
                parent:closePopupMenu()
                return DX.cb:execShowPageBrowserCallback(parent)
            end
        },
        ShowSeriesManager = {
            { { "Shift", { "M" } } }, function()
                parent:closePopupMenu()
                KOR.seriesmanager:showContextDialogForCurrentEbook(DX.m.current_ebook_full_path)
                return true
            end
        },
        ViewItemHits = {
            { { DX.s.hk_show_item_occurrences } }, function()
                parent:closePopupMenu()
                return DX.cb:execShowItemOccurrencesCallback()
            end
        },
    }
end

--- @param parent Menu
function KeyEvents:addHotkeysForXraySettings(parent)
    local module = DX.s
    count = #module.tab_labels
    for i = 1, count do
        local current = i
        self:registerCustomKeyEvent("XraySettings", parent, tostring(current), "show_settings_tab_" .. current, function()
            if parent.active_tab == current then
                return
            end
            module.showSettingsManager(current)
        end)
    end
    self:registerCustomKeyEvent("XraySettings", parent, DX.s.hk_show_information, "show_settings_information", function()
        return KOR.settingsmanager:showSettingsManagerInfo()
    end)
end

-- #((KeyEvents#addHotkeysForXrayUIpageInfoViewer))
--* compare ((KeyEvents#addHotkeysForXrayItemViewer)) and see comment in ((HtmlBox#initHotkeys)):
function KeyEvents.addHotkeysForXrayUIpageInfoViewer()
    local parent = DX.d
    local self = KOR.keyevents

    --* no shared hotkeys here...
    local actions = {
        {
            label = "list",
            hotkey = { { DX.s.hk_show_list } },
            callback = function()
                return parent:execShowListCallback(parent)
            end,
        },
        {
            label = "pagenavigator",
            hotkey = { { DX.s.hk_view_item_from_list_or_navigator } },
            callback = function()
                return parent:execShowPageNavigatorCallback(parent)
            end,
        },
        {
            label = "show_info",
            hotkey = { { DX.s.hk_show_information } },
            callback = function()
                return parent:execShowHelpInfoCallback()
            end,
        },
    }

    self:addSeriesManagerHotkey(actions)

    --- SET HOTKEYS FOR SCROLLTEXTWIDGET INSTANCE

    --! this ensures that hotkeys will even be available when we are in a scrolling html box. These actions will be consumed in ((ScrollTextWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", actions)
end

--- @param parent ButtonDialog
function KeyEvents:addHotkeysForButtonDialog(parent)
    if not Device:hasKeys() then
        return
    end

    self:addCloseHotkey(parent)
    if parent.additional_key_events then
        for label, set in pairs(parent.additional_key_events) do
            parent["on" .. label] = function()
                return set[2]()
            end
            parent.key_events[label] = set[1]
        end
    end
end

--- @param parent Menu
function KeyEvents:addHotkeyForFilterButton(parent, filter_active, callback, reset_callback)

    local hotkey = { { DX.s.hk_show_list_filter_dialog } }
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

    self:addCloseHotkey(parent)
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
        self:addCloseHotkey(parent)
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

    if parent.menu_name == "xray_settings" then
        self:addHotkeysForXraySettings(parent)
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

--* these additional_key_events might have been set by the caller of NavigatorBox:
--- @param parent NavigatorBox
function KeyEvents:addAdditionalHotkeysNavigatorBox(parent)
    if parent.additional_key_events then
        for label, hk_data in pairs(parent.additional_key_events) do
            local close_box = hk_data[3] and true or false
            if close_box then
                UIManager:close(parent)
            end
            parent["on" .. label .. "NB"] = function()
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

function KeyEvents:addCloseHotkey(parent)
    if not parent.key_events then
        parent.key_events = {}
    end
    parent.key_events["Close"] = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } }
end

function KeyEvents:addSeriesManagerHotkey(actions)
    table_insert(actions, {
        label = "show_serie",
        hotkey = { { "Shift", { "M" } } },
        callback = function()
            KOR.seriesmanager:showContextDialogForCurrentEbook(DX.m.current_ebook_full_path)
            return true
        end,
    })
end

--- @param parent Menu
function KeyEvents:updateHotkeys(parent)
    if parent.hotkey_updater then
        parent.hotkey_updater()
    end
end

--* shared hotkey actions must be registered by calling ((KeyEvents#registerSharedHotkey)) from the method which registers hotkeys for a specific module:
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

    table_insert(self.shared_hotkeys[key], { key_events_module, callback })
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
