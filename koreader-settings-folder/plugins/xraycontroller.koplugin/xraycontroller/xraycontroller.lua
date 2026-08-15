
--* for information about DX's modules and MVC pattern and explanations about some of its code procedures see ((Dynamic Xray: module info)) and ((XrayCodeProcedures)) in ((xray-info.lua))

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local Dispatcher = require("dispatcher")
local KOR = require("extensions/kor")
--* to be instantiated in ((XrayController#resetDynamicXray)):
local NavigatorBox
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
require("extensions/helperfunctions")
local _ = KOR:initCustomTranslations()

local G_reader_settings = G_reader_settings
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
--- @field ex XrayExporter
--- @field fd XrayFormsData
--- @field i XrayInformation
--- @field ip XrayInfoPanel
--- @field m XrayModel
--- @field oh XrayOccurrencesHistogram
--- @field p XrayPages
--- @field pn XrayPageNavigator
--- @field q XrayQuotes
--- @field s XraySettings
--- @field sp XraySidePanels
--- @field t XrayTranslations
--- @field ta XrayTags
--- @field tm XrayTranslationsManager
--- @field tw XrayTappedWords
--- @field vd XrayViewsData
--- @field u XrayUI
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
    --* shorthand notation for Exporter; this module will be initialized in ((KOR#initDX)):
    ex = nil,
    --* shorthand notation for FormsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    fd = nil,
    --* shorthand notation for Information; this module will be initialized in ((KOR#initDX)):
    i = nil,
    --* shorthand notation for InfoPanel; this module will be initialized in ((KOR#initDX)):
    ip = nil,
    --* shorthand notation for Model:
    m = nil,
    --* shorthand notation for OccurrencesHistogram; this module will be initialized in ((KOR#initDX)):
    oh = nil,
    --* shorthand notation for Pages; this module will be initialized in ((KOR#initDX)):
    p = nil,
    --* shorthand notation for PageNavigator; this module will be initialized in ((XrayModel#initDataHandlers)):
    pn = nil,
    --* shorthand notation for Quotes; this module will be initialized in ((KOR#initDX)):
    q = nil,
    --* shorthand notation for Settings; this module will be initialized in ((KOR#initDX)):
    s = nil,
    --* shorthand notation for SidePanels; this module will be initialized in ((KOR#initDX)):
    sp = nil,
    --* shorthand notation for Translations; this module will be initialized in ((XrayModel#initDataHandlers)):
    t = nil,
    --* shorthand notation for Tags; this module will be initialized in ((KOR#initDX)):
    ta = nil,
    --* shorthand notation for TranslationsManager; this module will be initialized in ((KOR#initDX)):
    tm = nil,
    --* shorthand notation for TappedWords; this module will be initialized in ((XrayModel#initDataHandlers)):
    tw = nil,
    --* shorthand notation for UI:
    u = nil,
    --* shorthand notation for ViewsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    vd = nil,
}

--* this global var will be initialized through ((XrayController#initKORandDynamicXray)) > ((XrayController#initButtonPropsExtension)), and then used locally in ((ButtonChoicePopup)) and ((ButtonInfoPopup)), for speeding up button generation:
KorButtonProps = nil

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

--- @private
function XrayController:initButtonPropsExtension()
    KorButtonProps = KOR.buttonprops
    KOR.buttonchoicepopup:setKorButtonProps()
    KOR.buttoninfopopup:setKorButtonProps()
end

--* called in a earlier phase then ((XrayController#init)), from ((patch: add Dynamic Xray to KOReader)) > current method:
function XrayController:initKORandDynamicXray()
    --- @class ExtensionsInit
    KOR:initEarlyExtensions()
    --* XrayModel will also load its data handlers here:
    KOR:initDX()
    KOR:initExtensions()

    self:initButtonPropsExtension()

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

    -- #((event handler for Reference Information))
    --* compare ((show book Glossary event handler)) and the help information under ((XrayInformation#showReferenceInformation)):
    Dispatcher:registerAction("show_reference_information", { category = "none", event = "ShowReferenceInformation", title = _("Reference Information: show/add"), reader = true })

    --* compare event handler for showing Xray Information: ((XrayController#onShowReferenceInformation)) and the help information under ((XrayInformation#showReferenceInformation)):
    -- #((show book Glossary event handler))
    Dispatcher:registerAction("show_glossary", { category = "none", event = "ShowGlossary", title = _("Show Glossary"), reader = true })


    Dispatcher:registerAction("show_tag_group_selector", { category = "none", event = "ShowTagGroupSelector", title = _("Show the Xray tag-group selector"), reader = true })
end

function XrayController:doBatchImport(conn, stmt, count, callback)
    local percentage, loop_end
    local start = 1
    local loops = 0
    local notification, initial_notification
    local limit = DX.s.batch_count_for_import + 1
    while not loop_end or loop_end <= count do
        UIManager:close(notification)
        --* callbacks defined in ((XrayDataSaver#processItemsInBatches)):
        start, loop_end, percentage = callback(start, count)
        --* this initial notification was set in ((XrayDataSaver#setSeriesHitsForImportedItems)):
        initial_notification = KOR.registry:getOnce("import_notification")
        if initial_notification then
            UIManager:close(initial_notification)
        end
        --* needed to ensure positioning at top of screen of next progress messages:
        UIManager:forceRePaint()
        notification = KOR.messages:notify(percentage .. " geïmporteerd…", 4)
        UIManager:forceRePaint()
        loops = loops + 1
        if percentage:match("100") or loops > limit then
            break
        end
    end
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
    --* by forcing refresh, we reload items from the database:
    DX.vd.initData("force_refresh")
    DX.vd.prepareData()
    DX.d:showList()
    return conn, stmt
end

function XrayController:itemToggleFavoritesTag(item, favorites_name, is_favorite)
    if is_favorite then
        DX.ta:itemRemoveTag(item, favorites_name)
        KOR.messages:notify(_("item removed from tag-group") .. " " .. favorites_name)
    else
        DX.ta:itemAddTag(item, favorites_name)
        KOR.messages:notify(_("item added to tag-group") .. " " .. favorites_name)
    end
    DX.ds.storeUpdatedItem(item)
    DX.vd:registerUpdatedItem(item)
    DX.d:closeItemViewer()
    DX.ta:resetTagGroups()
    DX.m:updateAllTags()
    KOR.dialogsqueue:reloadLastDialog()
end

function XrayController:itemToggleLocationsTag(item, locations_name, is_location)
    if is_location then
        DX.ta:itemRemoveTag(item, locations_name)
        KOR.messages:notify(_("item removed from tag-group") .. " " .. locations_name)
    else
        DX.ta:itemAddTag(item, locations_name)
        KOR.messages:notify(_("item added to tag-group") .. " " .. locations_name)
    end
    DX.ds.storeUpdatedItem(item)
    DX.vd:registerUpdatedItem(item)
    DX.d:closeItemViewer()
    DX.ta:resetTagGroups()
    DX.m:updateAllTags()
    KOR.dialogsqueue:reloadLastDialog()
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

    --* dont_show can be set to true via ((XrayDialogs#viewItem)), when looking up an XrayItem from ReaderHighlight, when XrayController list had not been shown yet:
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

function XrayController:onShowGlossary()
    KOR.glossary:showGlossaryViewer()
    return true
end

function XrayController:onShowReferenceInformation()
    KOR.referenceinformation:show()
    return true
end

function XrayController:onShowCurrentSeries()
    KOR.seriesmanager:showContextDialogForCurrentEbook()
    return true
end

function XrayController:onShowTagGroupSelector()
    DX.ta:showTagGroupSelector()
    return true
end

function XrayController:onReaderReady()

    KOR:registerUI(self.ui)

    --! in pdf's etc. DX is not available:
    if self.ui.paging then
        return
    end
    if not DX.m then
        KOR.messages:notify("dynamic xray could not be initiated...")
        return
    end
    KOR.referenceinformation:load(self.document.file)
    self:addGlobalHotkeys()
    self:resetDynamicXray(false, "do_full_update")
    DX.pn:resetFilterDouble("on_reader_ready")
end

function XrayController:addGlobalHotkeys()
    KOR.keyevents:addHotkeysForReaderUI(self)
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

function XrayController:filterItemsByTag(filter_tag)
    DX.vd:setProp("filter_tag", filter_tag)
    --! this reset is essential to make filtering possible:
    DX.vd:updateItemsTable(nil, "reset_item_table_for_filter")
    DX.d:closeListDialog()
    DX.d:showListWithRestoredArguments()
end

function XrayController:filterItemsByText(filter_string)
    DX.vd:setProp("filter_string", filter_string)
    --! this reset is essential to make filtering possible:
    DX.vd:updateItemsTable(nil, "reset_item_table_for_filter")
    DX.d:showListWithRestoredArguments()
end

function XrayController:resetFilteredItems(force_data_update)

    DX.vd:resetAllFilters()
    DX.d:setProp("filter_icon", nil)
    DX.d:setProp("filter_state", "unfiltered")

    if force_data_update then
        DX.m:resetData("force_refresh")
    end
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
    self:resetDynamicXray(nil, "do_full_update")
    --* to force an update of the Items List in ((XrayDialogs#showList)):
    KOR.registry:set("new_item", new_item)

    if return_modus == "return_to_navigator_page" then
        return DX.pn:returnToNavigator()
    end
    self:showListConditionally(new_item, return_modus)
end

function XrayController:saveUpdatedItem(return_modus, reload_manager)
    if return_modus then
        self.return_to_viewer = false
    end
    local field_values = DX.d.edit_item_input:getAllTabsFieldsValues()
    --* here the edited item will also be saved to the db:
    local updated_item = DX.fd:saveUpdatedItem(field_values)
    DX.fd:setProp("edit_item_index", nil)

    if not updated_item then
        DX.d:closeForm("edit")
        self.return_to_viewer = false
        return
    end

    DX.vd:updateAndSortAllItemTables(updated_item)
    --* item data was updated, so previous Item Viewer instances must be closed:
    DX.d:closeItemViewer()

    local do_full_update = DX.fd:needsFullUpdate(updated_item)
    self:resetDynamicXray("is_prepared", do_full_update)

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
        --* edited to support a hotfix that solves disappearing sidebar items after editing a linked item in the Page Navigator:
        KOR.registry:set("edited_xray_item", updated_item)
        DX.pn:returnToNavigator()
    end
end

--* compare form for editing Xray items: ((XrayController#onShowEditItemForm)):
--* see also method ((XrayController#guardIsExistingItem)), through which current method is called and which ensures no duplicated items are created:
function XrayController:onShowNewItemForm(name_from_selected_text, active_form_tab, item)

    DX.vd:resetAllFilters()

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

    DX.vd:resetAllFilters()

    KOR.registry:set("edit_item", KOR.tables:shallowCopy(needle_item))
    --! we need this to ensure updated item id will be remembered and item saved, in ((XrayFormsData#storeItemUpdates)) > ((XrayFormsData#reAttachViewerItemId)):
    KOR.registry:set("edit_item_id", needle_item.id)

    local m_item, item_copy = DX.fd:initEditFormProps(needle_item, reload_manager, active_form_tab)

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
        DX.d:viewItem(focus_item)
        return
    end

    if (show_list or DX.d.called_from_list) and not DX.d.xray_tapped_word_items_dialog and not DX.d.edit_item_input and not DX.u.xray_ui_info_dialog then
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

function XrayController:showQuotesManager()
    DX.d:closeItemViewer()
    local name = DX.d.current_viewer_item.name
    local quotes = DX.dl.getQuotesForItemByName(name)
    KOR.itemsmanager:showList({
        list_title = _("Manage quotes"),
        edit_title = _("Edit quote"),
        view_title = _("Quote"),
        list_footer_buttons_left = {
            KOR.buttoninfopopup:forXrayItemViewer({
                info = _("eye icon | Return to Xray item to which these quotes belong."),
                callback_label = _("show"),
                callback = function()
                    KOR.itemsmanager:closeDialogs()
                    --* for consumption in ((XrayDialogs#showItemViewer)):
                    KOR.registry:set("active_tab", 4)
                    DX.d:viewItem(DX.d.current_viewer_item)
                end,
            }),
        },
        items = quotes,
        delete_callback = function(item_no, id)
            DX.q:quoteDelete(item_no, id, DX.d.current_viewer_item)
            KOR.messages:notify(_("quote deleted"))
        end,
        save_callback = function(item_no, id, value)
            DX.q:quoteUpdate(item_no, id, value, DX.d.current_viewer_item)
            KOR.messages:notify(_("quote updated"))
        end,
    })
end

--- @param mode string "series" or "book"
function XrayController:toggleBookOrSeriesMode(mode, focus_item, dont_show)
    DX.vd.initData("force_refresh", mode)
    DX.d:showList(focus_item, dont_show)
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

function XrayController:getPath()
    return self.path
end

--- @private
function XrayController:guardIsExistingItem(needle_name)
    if has_no_text(needle_name) then
        return false
    end

    local already_existing_item = DX.tw:itemExists(needle_name, nil, "is_exists_check")
    if already_existing_item then
        DX.d:setActionResultMessage(DX.d:getControllerEntryName("an xray item with this name already exists..."))
        DX.d:viewItem(already_existing_item)
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

--* @param do_full_update string will be not nill when called from onReaderReady or when an item was added or when ((XrayController#saveUpdatedItem)) determined via ((XrayFormsData#needsFullUpdate)) that critical data were edited, which could impact the item marking in the html:
function XrayController:resetDynamicXray(is_prepared, do_full_update)
    --! in pdf's etc. DX is not available:
    if self.ui.paging then
        return
    end

    --? this method is not always called from a plugin context, but mostly (or even always?) from an extension context; that's the reason to use KOR.document, instead of self.view.document:
    local full_path = KOR.document.file
    if do_full_update then
        DX.m:setTitleAndSeries(full_path)
        DX.u:resetBookNeedlesString()
        DX.u:reset()
        --! don't call DX.u:reset() here, because then Xray markers in page would disappear...
        KOR.document:resetParagraphsCache()
        DX.p:resetCache()
    end
    self:toggleNightModeColors()
    --* to force a refresh of the texts in the bottom info panel:
    DX.sp:resetInfoTexts()
    DX.ip:resetProps()
    DX.sp:resetActiveSideButtons("XrayController:resetDynamicXray")
    DX.sp:resetSideButtons()
    DX.pn:resetCache()
    DX.pn:setCurrentItem(nil)
    if not NavigatorBox then
        NavigatorBox = require("xrayviews/widgets/navigatorbox")
    end
    NavigatorBox:reset()
    DX.u:reset()
    KOR.columntexts:resetCache()
    --? I don't know why we need this:
    if not DX.ex then
        DX.ex = require("xrayviews/xrayexporter")
    end
    DX.ex:resetCache()
    DX.ta:resetTagGroups()
    DX.vd:resetAllFilters()
    --* to reset Xray marker x-position upon screen rotation:
    DX.u:setMarkerXPosition()
    --* e.g. when current method called after saving an item from a form:
    if is_prepared or not do_full_update then
        return
    end

    DX.m:resetData("force_refresh", full_path)
    --* make data available for display of xray items on page or in paragraphs:
    DX.vd.initData(true, false, full_path)
    DX.vd.prepareData()
end

function XrayController:toggleNightModeColors()

    if G_reader_settings:isFalse("night_mode") then
        for entry, color in pairs(KOR.colors.day_colors) do
            KOR.colors[entry] = color
        end
        return
    end

    local inverted = Blitbuffer.COLOR_BLACK
    if DX.s.night_mode_color > 0 and DX.s.night_mode_color <= 5 then
        inverted = Blitbuffer["COLOR_GRAY_" .. DX.s.night_mode_color]
    end
    for entry in pairs(KOR.colors.day_colors) do
        KOR.colors[entry] = inverted
    end
end

function XrayController:setProp(prop, value)
    self[prop] = value
end

return XrayController
