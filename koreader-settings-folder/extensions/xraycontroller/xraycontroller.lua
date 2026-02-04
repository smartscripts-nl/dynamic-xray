-- #((Dynamic Xray: module info))
--[[--
This is the controller for the Dynamic Xray plugin. It has been structured in kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayPageNavigator)) and ((XrayCallbacks)) and ((XrayPages)) and ((XraySidePanels)) and ((XrayInfoPanel)), ((XrayTranslations)) and ((XrayTranslationsManager)), ((XrayDialogs)) and ((XrayButtons)), ((XrayCallbacks)), ((XrayInformation))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database. XrayTappedWords handles data requests resulting from users longpressing (partial) names of Xray items in the e-book text.

The views layer has three main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
3) Worthy to be specially mentioned is XrayPageNavigator, which offers the user the most Kindle-like experience: navigating through pages, with Xray items marked bold and button with which to show explanations of the items in the bottom panel. XrayPageNavigator does have some sub-modules, each responsible for one aspect of its views:
    a) XraySidePanels (DX.sp): responsible for the sidepanel (tabs) of the PageNavigator
    b) XrayInfoPanel (DX.ip): responsible for the information panel at the bottom of the PageNavigator
    c) XrayPages (DX.p): responsible for the main content op the Navigator, its pages. Handles navigation through these and marking of Xray items in them.
4) Also mentionable is the fact that some DX dialogs have shared hotkeys, in which case the hotkeys of the top most dialog will be used, not that same hotkey for an underlying dialog. See ((XRAY_DIALOGS_SHARED_HOTKEYS)) for an explanation.
5) DX has a ((SeriesManager)) for listing the books in a series. The items in this Manager have action buttons, for viewing large covers, descriptions, opening the e-book, etc. The user can also edit the metadata of ebooks from the Manager: authors, titles, series name, series index, page count, publication year, book description. The Manager uses ((Dialogs#filesBox)) > ((FilesBox)) to generate its dialog. The user can call it by tapping on the series manager icon in some DX dialogs, or by pressing Shift+M.


The user will have the most Kindle-like experience when he/she opens the Page Navigator - see ((XrayController#onShowPageNavigator)). In this navigator all Xray items in a page will be marked bold and they will be mentioned in a side panel. Tapping on items in the side panel will put an explanation of that item in the bottom panel. You can even filter the content of the Navigator for a specific Xray item, so it will only show pages which contain that item.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! important info for programmers
--[[
DX.vd.list_display_mode == "series" or "book" determines in which mode lists and hits counts in book/series will be displayed.

book_hits can be determined with ((XrayViewsData#getAllTextHits)) and will be stored in item.book_hits and in the database.

For retrieving book_hits, chapter_hits and series_hits per item from the database see ((XrayDataLoader#_loadAllData))

local var current_series will also be set for a book which is part of a series when DX.vd.list_display_mode == "book"

--* TWO STREAMS

The Dynamic Xray module/plugin has two streams:

1: for displaying xray sideline markers in the book text, starting from ((ReaderView#paintTo)) > ((init xray sideline markers)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#setParagraphsFromDocument)) etc.

2: plugin/controller and modules for providing lists and dialogs and crud actions for managing xray items (they are listed at the top of this file).

--* GLOBAL HOTKEYS

Some important DX modules can be called while reading, by global hotkeys:

Shift + H: show Xray Help information
Shift + L: show Xray List
Shift + M: show Series Manager
Shift + X: show Xray Page Navigator

--* SYNTACTIC SUGAR
-- #((SYNTACTIC SUGAR))

Calling DX modules: DX.b:[method](), DX.m:[method](), etc. This functionality was realised using ((KOR#initDX)), which populates the ((DX)) helper class. The same goes for XrayController, which registers itself to DX via ((XrayController#init)), setting DX.c to self.

--* ADDING ITEMS FROM SELECTED TEXT

E.g. ((ReaderDictionary#onLookupWord)) > ((XrayController#saveNewItem)) > ((XrayDataSaver#storeNewItem)) > ((XrayController#guardIsExistingItem)) > ((XrayController#onShowNewItemForm))

--* SAVING ITEMS

((XrayButtons#forItemEditor)) and then:

for existing items: ((XrayController#saveUpdatedItem)) > ((XrayFormsData#getAndStoreEditedItem)) > ((XrayFormsData#storeItemUpdates)) > ((XrayDataSaver#storeUpdatedItem))

for new items: ((XrayController#saveNewItem)) > ((XrayDataSaver#storeNewItem))

--* UPDATE ITEMS IN MEMORY AFTER EDITS AND ADDITIONS

-- ((XrayViewsData#updateAndSortAllItemTables)) > ((XrayViewsData#applyFilters)). So we don't have to reload data from the database after each and every modification.

--* DELETING ITEMS

((XrayDialogs#showDeleteItemConfirmation)) > ((XrayDataSaver#deleteItem)) > ((XrayDataSaver#storeDeletedItem)) depending on argument current_series set all instances in a series will be deleted or only that in the current ebook.

--* GENERATE ITEM INFO FOR DISPLAY

in list: ((XrayViewsData#generateListItemText))
in viewer: ((XrayViewsData#getItemInfo))

--* BUTTONS

list: ((XrayButtons#forListFooterLeft)), ((XrayButtons#forListFooterRight)), ((XrayButtons#forListContext))
viewer: ((XrayButtons#forItemViewer))

--* NAVIGATING THROUGH RELATED ITEMS SHOWN IN A POPUP BUTTONDIALOG UPON LONGPRESSING ON A WORD IN THE READER

((XrayButtons#forItemsCollectionPopup)) > ((XrayTappedWords#itemsRegister)) > click on a button in the popup > triggers ((related item button callback)) > ((XrayDialogs#viewTappedWordItem)) (like Item Viewer ((XrayDialogs#showItemViewer)) for normal items, but now specifically and only for related items).

When navigating through the items ((XrayDialogs#viewNextTappedWordItem)) or ((XrayDialogs#viewPreviousTappedWordItem)) are called, either triggered with a button or by a key event.

Via buttons: e.g. ((next related item via button)) (for this to work also next_item_callback and next_item_callback props of the Item Viewer in ((XrayDialogs#viewTappedWordItem)) have to be set).
For a key event e.g.: ((next related item via hotkey))

--* DISPLAYING HELP INFO

((XrayInformation#showListAndViewerHelp))
]]

local require = require

local Dispatcher = require("dispatcher")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
require("extensions/helperfunctions")
local _ = KOR:initCustomTranslations()

local has_no_text = has_no_text
local pairs = pairs

KOR:initBaseExtensions()

-- #((initialize Xray modules))
--* helper class for shortened notation for Dynamic Xray modules; DX.b, DX.d (but indices DX.xraybuttons, DX.xraydialogs etc. are NOT available, because the very short notation is the point of table DX) instead of KOR.xraybuttons, KOR.xraydialogs etc.; will be populated from ((KOR#initDX)), ((XrayModel#initDataHandlers)) and ((XrayController#init)):
--- @class DX
--- @field b XrayButtons
--- @field c XrayController
--- @field cb XrayCallbacks
--- @field d XrayDialogs
--- @field dl XrayDataLoader
--- @field ds XrayDataSaver
--- @field fd XrayFormsData
--- @field i XrayInformation
--- @field ip XrayInfoPanel
--- @field m XrayModel
--- @field pn XrayPageNavigator
--- @field s XraySettings
--- @field sp XraySidePanels
--- @field t XrayTranslations
--- @field tm XrayTranslationsManager
--- @field tw XrayTappedWords
--- @field vd XrayViewsData
--- @field u XrayUI
--- @field p XrayPages
DX = {
    --* shorthand notation for Buttons:
    b = nil,
    --* shorthand notation for Controller:
    c = nil,
    --* shorthand notation for Callbacks; this module will be initialized in ((KOR#initDX)):
    cb = nil,
    --* shorthand notation for Dialogs:
    d = nil,
    --* shorthand notation for DataLoader; this module will be initialized in ((XrayModel#initDataHandlers)):
    dl = nil,
    --* shorthand notation for DataStore; this module will be initialized in ((XrayModel#initDataHandlers)):
    ds = nil,
    --* shorthand notation for FormsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    fd = nil,
    --* shorthand notation for Information; this module will be initialized in ((KOR#initDX)):
    i = nil,
    --* shorthand notation for InfoPanel; this module will be initialized in ((KOR#initDX)):
    ip = nil,
    --* shorthand notation for Model:
    m = nil,
    --* shorthand notation for Pages; this module will be initialized in ((KOR#initDX)):
    p = nil,
    --* shorthand notation for PageNavigator; this module will be initialized in ((XrayModel#initDataHandlers)):
    pn = nil,
    --* shorthand notation for Settings; this module will be initialized in ((KOR#initDX)):
    s = nil,
    --* shorthand notation for SidePanels; this module will be initialized in ((KOR#initDX)):
    sp = nil,
    --* shorthand notation for Translations; this module will be initialized in ((XrayModel#initDataHandlers)):
    t = nil,
    --* shorthand notation for TranslationsManager; this module will be initialized in ((KOR#initDX)):
    tm = nil,
    --* shorthand notation for TappedWords; this module will be initialized in ((XrayModel#initDataHandlers)):
    tw = nil,
    --* shorthand notation for ViewsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    vd = nil,
    --* shorthand notation for UI:
    u = nil,
}
function DX.setProp(name, value)
    DX[name] = value
end
function DX:registerController(controller)
    self.c = controller
end

--! Watch out: extensions which are loaded here MUST also be typed in ((KOR)) and have a @class declaration themselves, to have them available for code hinting!

--! this class will be loaded in 2 locations: in the DX patch (for early initialisation of the KOR and DX systems - via ((XrayController#initKORandDynamicXray)) - AND in plugins/xraycontroller.koplugin/main.lua:
--- @class XrayController
local XrayController = WidgetContainer:new{
    name = "xraycontroller",
    --* this prop can be set in ((XrayButtons#forItemViewer)) > ((enable return to viewer)), when the user opens an add or edit form:
    return_to_viewer = false,
}

--* called in a earlier phase then ((XrayController#init)), from ((patch: add Dynamic Xray to KOReader)) > current method:
function XrayController:initKORandDynamicXray()
    --- @class ExtensionsInit
    KOR:initEarlyExtensions()
    --* XrayModel will also load its data handlers here:
    KOR:initDX()
    KOR:initExtensions()
    --* for now loads only extension XrayTranslations for repository version of DX:
    DX.d:initViewHelpers()
    --* see ((SYNTACTIC SUGAR)):
    DX:registerController(self)
end
--! init KOR and DX:
XrayController:initKORandDynamicXray()

--* normal init in plugin mode:
function XrayController:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

--- @private
function XrayController:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_items", { category = "none", event = "ShowList", title = DX.d:getControllerEntryName("Show xray-items in this book/series"), reader = true })
    Dispatcher:registerAction("show_xray_page_navigator", { category = "none", event = "ShowPageNavigator", title = DX.d:getControllerEntryName("Show Xray Page Navigator"), rolling = true })
    Dispatcher:registerAction("add_xray_item", { category = "none", event = "AddNewXrayItem", title = DX.d:getControllerEntryName("Add an Xray item"), reader = true })
    Dispatcher:registerAction("show_series_manager", { category = "none", event = "ShowSeriesManager", title = _("Show Series Manager"), reader = true })
    Dispatcher:registerAction("show_series_manager_current_ebook", { category = "none", event = "ShowCurrentSeries", title = _("Show series and/or metadata for current e-book"), reader = true })
end

function XrayController:doBatchImport(count, callback)
    local percentage, loop_end
    local start = 1
    local loops = 0
    local notification, initial_notification
    local limit = DX.s.batch_count_for_import + 1
    while not loop_end or loop_end <= count do
        UIManager:close(notification)
        --* callbacks defined in ((XrayDataSaver#processItemsInBatches)):
        start, loop_end, percentage = callback(start, count)
        --* this initial notification was set in ((XrayDialogs#showRefreshHitsForCurrentEbookConfirmation)):
        initial_notification = KOR.registry:getOnce("import_notification")
        if initial_notification then
            UIManager:close(initial_notification)
        end
        notification = KOR.messages:notify(percentage .. " " .. DX.d:getControllerEntryName("imported"), 4)
        UIManager:forceRePaint()
        loops = loops + 1
        if percentage:match("100") or loops > limit then
            break
        end
    end
    --* by forcing refresh, we reload items from the database:
    DX.vd.initData("force_refresh")
    DX.vd.prepareData()
    DX.d:showList()
end

function XrayController:listHasReloadOrDontShowRequest(focus_item, dont_show)
    --* if no hits found with a filter, all lists and filters have been reset and we restart the list:
    --* self.list_title is set in ((XrayDialogs#initListDialog)):
    if DX.d.list_title == false then
        self:resetFilteredItems()
        DX.d:setActionResultMessage("geen items gevonden met opgegeven filter...")
        DX.d:showList(focus_item, dont_show)
        return true
    end

    --* dont_show can be set to true via ((XrayDialogs#showItemViewer)), when looking up an XrayItem from ReaderHighlight, when XrayController list had not been shown yet:
    return dont_show
end

--* in event name format because of gesture:
--* select_mode will be truthy when called from ((XrayCallbacks#execPageNavigatorSearchItemCallback)), so list can be used as an item selector for the item to search in Page Navigator:
function XrayController:onShowList(focus_item, dont_show, select_mode)
    DX.d:showList(focus_item, dont_show, select_mode)
end

function XrayController:onShowPageNavigator()
    self:showPageNavigator()
    return true
end

function XrayController:onShowSeriesManager()
    KOR.seriesmanager:onShowSeriesList()
    return true
end

function XrayController:onShowCurrentSeries()
    KOR.seriesmanager:showContextDialogForCurrentEbook()
    return true
end

function XrayController:onReaderReady()

    KOR:registerUI(self.ui)

    if not DX.m then
        KOR.messages:notify("dynamic xray could not be initiated...")
        return
    end
    KOR.keyevents:addHotkeysForReaderUI(self)
    self:resetDynamicXray()
end

function XrayController:onSetRotationMode()
    self:resetDynamicXray()
end

function XrayController:onScreenResize()
    self:resetDynamicXray()
end

function XrayController:filterItemsByImportantTypes()
    DX.d:setProp("filter_state", "filtered")
    DX.d:setProp("filter_icon", KOR.icons.xray_person_important_bare .. "/" .. KOR.icons.xray_term_important_bare)
    DX.vd:setFilterTypes({ 2, 4 })
    --! this reset is essential to make filtering possible:
    DX.vd:updateItemsTable(nil, "reset_item_table_for_filter")
    DX.m:setTabDisplayCounts()
    DX.d:showListWithRestoredArguments()
end

function XrayController:filterItemsByText(filter_string)
    DX.vd:setProp("filter_string", filter_string)
    --! this reset is essential to make filtering possible:
    DX.vd:updateItemsTable(nil, "reset_item_table_for_filter")
    DX.d:showListWithRestoredArguments()
end

function XrayController:resetFilteredItems()
    --* otherwise data would be reset and retrieved many times:
    if self.filter_state == "unfiltered" then
        return
    end

    DX.d:setProp("filter_icon", nil)
    DX.d:setProp("filter_state", "unfiltered")
    DX.m:resetData("force_refresh")
end

function XrayController:saveNewItem(return_modus)
    local fields = DX.d.add_item_input:getAllTabsFieldsValues()
    --* if name is not set:
    if has_no_text(fields[2]) and return_modus == "return_to_list" then
        self:showListConditionally(nil, return_modus)
    --* return_modus == "return_to_navigator_page":
    elseif has_no_text(fields[2]) then
        return DX.pn:returnToNavigator()
    end

    DX.fd:resetFormItemId()
    local new_item = DX.fd:convertFieldValuesToItemProps(fields)
    --* these hits props (book_hits, chapter_hits, series_hits) were set in ((XrayDialogs#showNewItemForm)):
    if DX.vd.new_item_hits then
        for key, value in pairs(DX.vd.new_item_hits) do
            new_item[key] = value
        end
        DX.vd:setProp("new_item_hits", nil)
    end
    self.return_to_viewer = false
    DX.d:closeForm("add")
    DX.fd.saveNewItem(new_item)
    self:resetDynamicXray()
    --* to force an update of the list of items in ((XrayDialogs#showList)):
    KOR.registry:set("new_item", new_item)

    if return_modus == "return_to_navigator_page" then
        return DX.pn:returnToNavigator()
    end
    self:showListConditionally(new_item, return_modus)
end

function XrayController:saveUpdatedItem(item_copy, return_modus, reload_manager)
    if return_modus then
        self.return_to_viewer = false
    end
    local field_values = DX.d.edit_item_input:getAllTabsFieldsValues()
    --* here the edited item will also be saved to the db:
    local updated_item = DX.fd:getAndStoreEditedItem(item_copy, field_values)
    DX.fd:setProp("edit_item_index", nil)

    if not updated_item then
        DX.d:closeForm("edit")
        self.return_to_viewer = false
        return
    end

    DX.vd:updateAndSortAllItemTables(updated_item)
    --* item data was updated, so previous Item Viewer instances must be closed:
    DX.d:closeItemViewer()
    self:resetDynamicXray("is_prepared")

    if self.return_to_viewer then
        --* return to updated viewer instance via closeForm:
        DX.d:closeForm("edit")
        self.return_to_viewer = false
        return
    end

    DX.d:closeForm("edit")
    if return_modus == "return_to_list" then
        self:showListConditionally(updated_item, reload_manager or return_modus)
    elseif return_modus == "return_to_navigator_page" then
        DX.pn:returnToNavigator()
    end
end

--* compare form for editing Xray items: ((XrayController#onShowEditItemForm)):
--* see also method ((XrayController#guardIsExistingItem)), through which current method is called and which ensures no duplicated items are created:
function XrayController:onShowNewItemForm(name_from_selected_text, active_form_tab, item)
    local title, item_copy, prefilled_field = DX.fd:initNewItemFormProps(name_from_selected_text, active_form_tab, item)
    DX.d:showNewItemForm({
        title = title,
        active_form_tab = active_form_tab,
        item_copy = item_copy,
        name_from_selected_text = name_from_selected_text,
        prefilled_field = prefilled_field,
        --* in case of pre-filled content in description field or no pre-filled content was given, make name the focus field; when name prefilled, make description the focus field:
        focus_field = (prefilled_field == "description" or has_no_text(name_from_selected_text)) and 2 or 1,
    })
end

--*compare ((XrayController#onShowNewItemForm)):
function XrayController:onShowEditItemForm(needle_item, reload_manager, active_form_tab)

    local m_item, item_copy = DX.fd:initEditFormProps(needle_item, reload_manager, active_form_tab)

    --! hotfix to prevent crash when an edit item request was done (after holding an xray item and choosing "edit") from the page/paragraph toc index popup; see ((TextViewer#getTocIndexButton)) > ((edit xray item from toc popup)):
    if not needle_item.idx then
        needle_item.idx = needle_item.index
    end
    DX.d:showEditItemForm({
        active_form_tab = active_form_tab,
        item = m_item,
        item_copy = item_copy,
        reload_manager = reload_manager,
    })
end

function XrayController:showListConditionally(focus_item, show_list)

    --* this prop can be set in ((XrayButtons#forItemViewer)) > ((enable return to viewer)), when the user opens an add or edit form:
    if self.return_to_viewer then
        DX.d:showItemViewer(focus_item)
        return
    end

    if (show_list or DX.d.called_from_list) and not DX.d.xray_item_chooser and not DX.d.edit_item_input and not DX.u.xray_ui_info_dialog then
        DX.d:showList(focus_item)
    end
end

function XrayController:openPageNavigatorFromList()
    DX.d:closeListDialog()
    self:showPageNavigator()
    return true
end

function XrayController:showPageNavigator()
    local current_epage = DX.u:getCurrentPage()
    DX.pn:showNavigator(current_epage)
end

--- @param mode string "series" or "book"
function XrayController:toggleBookOrSeriesMode(mode, focus_item, dont_show)
    DX.vd.initData("force_refresh", mode)
    DX.d:showList(focus_item, dont_show)
end

function XrayController:refreshItemHitsForCurrentEbook()
    DX.ds.refreshItemHitsForCurrentEbook()
end

function XrayController:toggleSortingMode()
    local mode = DX.m:toggleSortingMode()
    --* ((XrayController#toggleBookOrSeriesMode)) acts as a kind of reloader/refresher of data:
    local focus_item = DX.d.list_args and DX.d.list_args.focus_item
    local dont_show = DX.d.list_args and DX.d.list_args.dont_show
    if not DX.d.list_args then
        dont_show = true
    end
    self:toggleBookOrSeriesMode(mode, focus_item, dont_show)
end

--- @private
function XrayController:guardIsExistingItem(needle_name)
    if has_no_text(needle_name) then
        return false
    end

    local already_existing_item = DX.tw:itemExists(needle_name, nil, "is_exists_check")
    if already_existing_item then
        DX.d:setActionResultMessage(DX.d:getControllerEntryName("an xray item with this name already exists..."))
        DX.d:showItemViewer(already_existing_item)
        return true
    end
end

function XrayController:viewItemHits(item_name)
    --* for persons, as opposed to ideas/definitions/terms, only search by first part of name (starting with an uppercase character):
    if DX.m:isXrayItem(item_name) then
        item_name = DX.m:getRealFirstOrSurName(item_name)
    end
    KOR.readersearch:onShowTextLocationsForNeedle(item_name)
end

function XrayController:addToMainMenu(menu_items)
    local icon = KOR.icons.seriesmanager_bare
    menu_items.series_manager = {
        text = icon .. " Series Manager",
        sub_item_table = {
            {
                text = icon .. " " .. _("Show all series"),
                callback = function()
                    self:onShowSeriesManager()
                end
            },
            {
                text = icon .. " " .. _("Show series or metadata for the current e-book"),
                callback = function()
                    self:onShowCurrentSeries()
                end
            },
        }
    }
    icon = KOR.icons.lightning_bare
    menu_items.dynamic_xray = {
        text = icon .. DX.d:getControllerEntryName(" Dynamic Xray"),
        sub_item_table = {
            {
                text = icon .. DX.d:getControllerEntryName(" Show list"),
                callback = function()
                    DX.d:showList()
                end
            },
            {
                text = icon .. DX.d:getControllerEntryName(" Show Page Navigator"),
                enabled_func = function()
                    if self.ui.paging then
                        return false
                    end
                    return true
                end,
                callback = function()
                    self:showPageNavigator()
                end
            },
            {
                text = icon .. DX.d:getControllerEntryName(" Add item"),
                callback = function()
                    self:resetFilteredItems()
                    self:onShowNewItemForm()
                end
            },
            {
                text = icon .. DX.d:getControllerEntryName(" Translate interface"),
                callback = function()
                    DX.tm:manageTranslations()
                end
            },
            {
                text = KOR.icons.xray_settings_bare .. DX.d:getControllerEntryName(" Settings"),
                callback = function()
                    DX.s.showSettingsManager()
                end
            },
        }
    }
end

--- @private
function XrayController:resetDynamicXray(is_prepared)
    --? this method is not always called from a plugin context, but mostly (or even always?) from an extension context; that's the reason to use KOR.document, instead of self.view.document:
    local full_path = KOR.document.file
    DX.m:setTitleAndSeries(full_path)
    --! don't call DX.u:reset() here, because then Xray markers in page would disappear...
    KOR.document:resetParagraphsCache()
    DX.pn:resetCache()
    DX.sp:resetActiveSideButtons("XrayController:resetDynamicXray")
    DX.vd:resetAllFilters()
    DX.p:resetCache()
    --* when current method called after saving an item from a form:
    if is_prepared then
        return
    end
    DX.m:resetData("force_refresh", full_path)
    --* make data available for display of xray items on page or in paragraphs:
    DX.vd.initData(true, false, full_path)
    DX.vd.prepareData()
end

function XrayController:setProp(prop, value)
    self[prop] = value
end

return XrayController
