
-- #((Dynamic Xray: module info))
--[[
((XrayController)) is the controller for the Dynamic Xray plugin. DX has been structured in kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayPageNavigator)) and ((XrayCallbacks)) and ((XrayPages)) and ((XraySidePanels)) and ((XrayInfoPanel)) and ((XrayOccurrencesHistogram)), ((XrayTranslations)) and ((XrayTranslationsManager)), ((XrayDialogs)) and ((XrayButtons)) and ((XrayQuotes)) and ((XrayTags)), ((XrayCallbacks)), ((XrayInformation)), and ((ReferenceInformation)) and ((Glossary))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database. XrayTappedWords handles data requests resulting from users longpressing (partial) names of Xray items in the e-book text.

The views layer has three main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
3) Worthy to be specially mentioned is XrayPageNavigator, which offers the user the most Kindle-like experience: navigating through pages, with Xray items marked bold and button with which to show explanations of the items in the bottom panel. XrayPageNavigator does have some sub-modules, each responsible for one aspect of its views:
    a) XraySidePanels (DX.sp): responsible for the sidepanel (tabs) of the PageNavigator
    b) XrayInfoPanel (DX.ip): responsible for the information panel at the bottom of the PageNavigator
    c) XrayPages (DX.p): responsible for the main content op the Navigator, its pages. Handles navigation through these and marking of Xray items in them.
    d) NavigatorBox: responsible for drawing the Page Navigator and handling user interaction with the Navigator.
4) Also mentionable is the fact that some DX dialogs have shared hotkeys, in which case the hotkeys of the top most dialog will be used, not that same hotkey for an underlying dialog. See ((XRAY_DIALOGS_SHARED_HOTKEYS)) for an explanation.
5) DX has a ((SeriesManager)) for listing the books in a series. The items in this Manager have action buttons, for viewing large covers, descriptions, opening the e-book, etc. The user can also edit the metadata of ebooks from the Manager: authors, titles, series name, series index, page count, publication year, book description. The Manager uses ((Dialogs#filesBox)) > ((FilesBox)) to generate its dialog. The user can call it by tapping on the series manager icon in some DX dialogs, or by pressing Shift+M.
6) Thanks to ((XrayQuotes)) the user can add quotes from the ebook to the Xray item, for display in a tab "Quotes" in the Xray Item Viewer. So the user has important quotes at hand quickly. The quotes can be added to the item (selected from a popup with al list of all items) via the ReaderHighlight popup shown after text selection in the ebook.
7) Through Page Navigator you can quickly reference a glossary for the current ebook through the hotkey Shift+G (or the gesture "Show/add glossary for current book"). If a glossary hasn't been defined yet, this same hotkey or gesture will lead the user to a dialog from which to start the import of the ebook glossary into Page Navigator by marking its boundaries in the ebook text.
8) The Items List has a checkbox-button in the top left corner to select multiple items and to assign a tag to all those items in one fell swoop (or remove that tag for items which already had it). See ((XrayTags#toggleItemsForTagsSelection)) > ((XrayTags#initiateItemTagsSelection)) > ((XrayTags#addTagsToItems)) > ((XrayDataSaver#storeItemsTags)), and images 3b... and 3c... in the README. The tag-groups created in this way can be viewed in the 4th tab of the Xray Exporter.
    Tag-groups can be very handy to e.g. see all persons/terms belonging to one party in a conflict together, or to group logically linked concepts together.

9) DX has a Reference Information popup. It can be called with the index-button in de Page Navigator popup menu, or with the global hotkey Shift+R, or from the popup menu after the user selected a text in the e-book). See ((XrayController#onShowReferenceInformation)) > ((ReferenceInformation#show)).
 It can e.g. be used to store timeline-information for a book, even in the format of a HTML table.
 For starting the proces of text addition, see ((InformationCollector#confirmAddInformationFromScratch)) - when called from the Page Navigator popup menu - or ((InformationCollector#confirmAddInformationAfterExpansion)), when called from the ReaderHighlight new text selection popup. In both these cases the information is saved via ((InformationCollector#setInformationBoundaries)) > ((InformationCollector#addReferenceInformation)).
 The user can assign a gesture for calling this popup outside of Page Navigator.

10) DX also has a Glossary popup, to show a Glossary from the book stored there. See ((Glossary#showViewer)).
This Glossary can be used to quickly lookup a term in the e-book text. When the user longpresses a word in the ebook text and that word is an item in the Glossary, the explanation for that item will be shown in the Glossary popup; see ((Glossary#showEditor))
 For starting the proces of text addition, see ((InformationCollector#confirmAddInformationAfterExpansion)), when called from the ReaderHighlight new text selection popup. The information will be saved to the Glossary via ((InformationCollector#setInformationBoundaries)) > ((Glossary#addInformation)).

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

for existing items: ((XrayController#saveUpdatedItem)) > ((XrayFormsData#saveUpdatedItem)) > ((XrayFormsData#storeItemUpdates)) > ((XrayDataSaver#storeUpdatedItem))

for new items: ((XrayController#saveNewItem)) > ((XrayFormsData#saveNewItem)) > ((XrayDataSaver#storeNewItem))

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

((XrayButtons#forItemsCollectionPopup)) > ((XrayTappedWords#itemsRegister)) > click on a button in the popup > triggers ((related item button callback)) > ((XrayDialogs#viewTappedWordItem)) (like Item Viewer ((XrayDialogs#viewItem)) for normal items, but now specifically and only for related items).

When navigating through the items ((XrayDialogs#viewNextTappedWordItem)) or ((XrayDialogs#viewPreviousTappedWordItem)) are called, either triggered with a button or by a key event.

Via buttons: e.g. ((next related item via button)) (for this to work also next_item_callback and next_item_callback props of the Item Viewer in ((XrayDialogs#viewTappedWordItem)) have to be set).
For a key event e.g.: ((next related item via hotkey))

--* DISPLAYING HELP INFO

((XrayInformation#showListAndViewerHelp))
]]

--- @class XrayCodeProcedures
local XrayCodeProcedures = {}

--* information for DeepWiki: extension XrayHelpers does NOT exist anymore and methods Strings#hasUnmodifiedMatch, Strings#isFullWordMatch also do NOT exist anymore; they replaced by the routines in ((XrayTappedWords#matchItemToTappedWord)). Strings#wholeWordMatch has been renamed to ((Strings#hasWholeWordMatch)).

function XrayCodeProcedures:BUTTONCHOICEPROPS_MORE_THAN_2()

    -- extra callbacks added in ((ButtonProps#injectAdditionalChoiceCallbacks))
end

function XrayCodeProcedures:DIALOGS()

    -- main dialogs:

    -- ((Dialogs#niceAlert)) pretty dialogs
    -- ((Dialogs#textBox)) interface for TextViewer, for scrolling through many paragraps
    -- ((Dialogs#htmlBox)) same as textBox, but now text is presented as HTML, which of course results in more formatting options
    -- ((Dialogs#textBoxTabbed)) and ((Dialogs#htmlBoxTabbed)): for plain text and html in a tabbed interface
end

function XrayCodeProcedures:TABS()
    -- for tabbed dialogs: ((Dialogs#htmlBoxTabbed)) or ((Dialogs#textBoxTabbed)) > ((TabFactory#setTabButtonAndContent))

    -- for navigating through these tabs: e.g. ((KeyEvents#addHotkeysForHtmlBox)) > ((TabNavigator#init)) > ((generate tab navigation event handlers))
    -- edge case: when we navigate back in a scrolling html widget, ((ScrollHtmlWidget#scrollText)) > code below direction < 0 ensures we activate the previous tab if we navigate back from the top of the content

    -- for tabbed submenu in dialogs: ((ButtonTableFactory#getTabsTable))

    -- Menu instance with sub tabbuttons: ((XrayDialogs#initListDialog)) with tab_labels and activate_tab_callback > ((KeyEvents#registerTabHotkeys)). These buttons were generated in ((XrayButtons#forListSubmenu)) > ((XrayButtons#getListSubmenuButton)) and the callback for pressing the start characters of tab items is ((XrayModel#activateListTabCallback))
end

function XrayCodeProcedures:TAPPED_WORD_MATCHES()
    -- called from ReaderHighlight: ((XrayTappedWords#getXrayItemAsDictionaryEntry)); placing exact partial matches in name or linkwords at top and marking them bold: ((XrayTappedWords#collectionPopulateAndSort)); placing exact fullname matches at position 1: ((XrayTappedWords#getCollection)) in case of needle_matches_fullname == true, which was set in ((XrayViewsData#upgradeNeedleItem))
end

function XrayCodeProcedures:XRAY_DIALOGS_SHARED_HOTKEYS()

    -- DX supports shared hotkeys, e.g. like "N" and "P" to navigate to the next/previous page or item in resp. XrayPageNavigator or the Xray Item Viewer.
    -- this means that when the XrayPageNavigator is active, N and P will navigate to the next or previous page; but when we load the Xray Item Viewer from the Navigator, then N and P will navigate to the next and previous item in the viewer.
    -- also: in the Navigator the hotkey "E" opens the Xray item editor, but when the viewer is loaded from the Navigator, the same hotkey will trigger still the same functionality, but WITHOUT the viewer loosing focus. De facto is now triggered on the viewer instance (or to be precise: its HtmlBoxWidget instance).
    -- when the user closes the viewer, the Navigator hotkeys take over once again.

    --* setting up this functionality (always in combination with a HtmlBox):
        -- 1 the caller instantiates HtmlBox, with props hotkeys_configurator and after_close_callback. See ((XrayPageNavigator#showNavigator)) for an example.
        -- 2 the hotkeys_configurator is called from ((HtmlBox#initHotkeys)).
        -- 3 e.g. for the Navigator this configuator calls ((KeyEvents#addHotkeysForXrayPageNavigator)), which registers shared hotkeys with ((KeyEvents#registerSharedHotkeys)) and ((KeyEvents#registerSharedHotkey)) > set registry var "add_parent_hotkeys" > read this var in ((HtmlBoxWidget#initHotkeys)), which uses it to add additional hotkeys (of the parent) to the HtmlBoxWidget instance
        -- 4 the HtmlBox instance calls it's after_close_callback, to unset the registry var "add_parent_hotkeys" and to unset only its own shared hotkeys (but not those same shared hotkeys attached to other modules!) via ((KeyEvents#unregisterSharedHotkeys))
end

function XrayCodeProcedures:XRAY_INFO_TOC_ADD_LINKED_ITEM_BUTTONS()
    -- adding button to popup toc for closing toc AND Page/Paragraph Info Popup: ((TextViewer toc popup: add close button for popup and info dialog))

    -- list: ((XrayController#onShowList)) > ((XrayDialogs#showList))

    -- showing list conditionally after saving an item: ((XrayController#saveNewItem)) or ((onShowEditItemForm)) > ((XrayController#showListConditionally))

    -- viewer, show item: ((XrayDialogs#viewItem))
end

function XrayCodeProcedures:XRAY_ITEMS()

    --* see ((Dynamic Xray: module info))

    --- MAIN DATA METHODS

    --* see ((XRAY_ITEMS_DATA_FLOW))

    --- XRAY UI

    -- module names: (Xray) Items List, (Xray) Item Viewer, Page Navigator, Page Information Popup

    --* see ((Dynamic Xray: module info))

    --! linchpin method: ((XrayUI#ReaderViewGenerateXrayInformation))

    -- drawing rects for xray info: ((ReaderView#paintTo)) > ((XrayUI#setParagraphsFromDocument)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > here callbacks are attached to the info rects > ((XrayUI#ReaderViewInitParaOrPageData)) > ((XrayUI#ReaderViewLoopThroughParagraphOrPage)) > ((xray page marker set target line for icon)) in page mode

    -- adding match reliability indicators for the Page/Paragraph Info Popup:
    -- using these indicators: ((XrayUI#showParagraphInformation)) > ((xray items dialog add match reliability explanations))

    -- show paragraph matches: ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#getMarker)) and ((CreDocument#storeCurrentPageParagraphs)) > ((XrayUI#getXrayItemsFoundInText)): here matches on page or paragraphs evaluated > ((XrayUI#drawMarker)) > ((set xray page info rects)) KOR.registry:set("xray_page_info_rects") > here the information in the popup gets combined: ((XrayUI#ReaderHighlightGenerateXrayInformation)) > ((XrayDialogs#showUiPageInfo))

    -- max line length in popup info for xray items on page: DX.s.max_info_line_length

    -- determining valid needles for matching on page: ((XrayModel#isValidNeedle)) > needle >= 4 characters, OR contains an uppercase character

    -- positioning of page markers: ((XrayUI#ReaderViewLoopThroughParagraphOrPage)) > ((XrayUI#drawMarker)).

    --- PAGE NAVIGATOR

    -- ((XrayPageNavigator#showNavigator)) > ((CreDocument#getPageHtml)) > ((XrayPages#markItemsFoundInPageHtml)) for html and buttons > ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#discoverXrayItems)) > ((XrayPages#markedItemRegister)) here callback and hold_callback are attached > ((XrayInfoPanel#getItemInfoText)) > ((Dialogs#htmlBox)) > ((NavigatorBox#generateSidePanelButtons)) > ((NavigatorBox#generateInfoPanel)) > ((XrayInfoPanel#generateInfoPanel))

    --- FILTERING

    -- applying filters: ((XrayButtons#forFilterDialog)) > ((XrayController#filterItemsByImportantTypes)) or ((XrayController#filterItemsByText))
    -- resetting filters: ((XrayDialogs#initListDialog)) > ((XrayDialogs#getListFilter)) supplies filter callback and reset_callback to Menu > ((XrayController#resetFilteredItems))

    --- SVG icons
    -- most svg icons downloaded from https://www.onlinewebfonts.com/icon: icons here are licensed by CC BY 4.0
    -- some free svg icons were downloaded from https://www.svgrepo.com
    -- I sometimes have renamed icons, to clarify their function in Dynamic Xray
end

function XrayCodeProcedures:XRAY_ITEMS_DATA_FLOW()

    --- MAIN DATA METHODS

    -- ((XrayDataLoader#_loadAllData)) > ((XrayDataLoader#_loadDataForBook)) and ((XrayDataLoader#_loadDataForSeries))
                        -->
    -- ((XrayDataLoader#addMatchingProps)) > ((XrayDataLoader#addMatchingPropsForName)) > populate item.needles and item.needles_for_ui: ((XrayModel#getNameParts)) here weighted matching strings, with indicator icons
    -- ((XrayDataLoader#addMatchingProps)) > ((XrayDataLoader#addMatchingPropsForName)) and ((XrayDataLoader#addMatchingPropsForAliasesAndShortNames))

    -- setting views data: ((XrayDataLoader#_loadAllData)) > ((XrayViewsData#setItems)). Here we also add last-name needles, because now all items available: ((XrayViewsData#addFamilyNameNeedle))

    -- getting items for Items List: ((XrayModel#getCurrentItemsForView)) > ((XrayViewsData#getCurrentListTabItems)) > ((XrayViewsData#filterAndAddItemToItemTables))

    --* marking items in Page Navigator HTML (using item.needles_for_ui): ((XrayPages#markItemsFoundInPageHtml)) > ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#discoverXrayItems))
end

function XrayCodeProcedures:XRAY_VIEWER_CONTEXT_BUTTONS()
    -- viewer, ((multiple related xray items found)) and adding linked items to that dialog: ((XrayButtons#forItemViewerBottomContextButtons))
    -- compare ((XRAY_INFO_TOC_ADD_LINKED_ITEM_BUTTONS))

    -- button for creating new xray items: ((XrayButtons#addTappedWordCollectionButton))

    -- edit item: ((onShowEditItemForm)) > ((XrayDialogs#showEditItemForm))

    -- generating linked items button rows for item viewer: ((XrayButtons#forItemViewerBottomContextButtons))

    -- filter xray items: ((XrayController#onShowList)) > ((XrayViewsData#updateItemsTable)) > for text filter ((XrayViewsData#filterAndPopulateItemTables)) > continue with ((XrayController#onShowList)) > ((XrayDialogs#showList))

    -- storing new xray items: called from save button generated with ((XrayButtons#forItemEditor)) > ((XrayController#saveNewItem)) > ((XrayFormsData#saveNewItem)) > ((XrayDataSaver#storeNewItem)) > ((XrayController#showListConditionally)) > ((XrayViewsData#updateItemsTable))

    -- storing edited xray items: called from save button generated with ((XrayButtons#forItemEditor)) > ((XrayController#saveUpdatedItem)) > ((XrayFormsData#saveUpdatedItem)) > ((XrayFormsData#storeItemUpdates)) > ((XrayDataSaver#storeUpdatedItem)) > ((XrayController#showListConditionally)) > ((XrayViewsData#updateItemsTable))
end
