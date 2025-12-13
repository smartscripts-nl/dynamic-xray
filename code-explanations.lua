
--- @class XrayInfo

--- SUBJECTS

-- ((BETTER TYPE HINTS))
-- ((DIALOGS))
-- ((TABS))
-- ((TAPPED_WORD_MATCHES))
-- ((XRAY_ITEMS))
-- ((XRAY_INFO_TOC_ADD_LINKED_ITEM_BUTTONS))
-- ((XRAY_VIEWER_CONTEXT_BUTTONS))

-- ======================================================


-- #((BETTER TYPE HINTS))

-- ! @class
--- use --- @class for class declarations and easy opening of locations in PhpStorm

-- ! @field
--- use --- @field for class fields, to be named with name and type above the class declaration.
-- e.g. see start of ((KOR))

-- ! @type
--- use --- @type for variables (right above their declaration). Example:
--- @type XrayModel model
local model

-- ! @param
--- use --- @param for method arguments and loop params (with name of argument first and then type); example for loops:
local titlebars
--- @param v TitleBar
for _, v in ipairs(titlebars) do
    -- nonsense statement :-):
    model:isXrayItem(v)
end

-- ! @see
--- use @see for links to specific places. Advantage over regular ((name)) references: green color, so stands out. Example:
--- @see TitleBar#init


local XrayInfo = {}

function XrayInfo:DIALOGS()

    -- main dialogs:

    -- ((Dialogs#niceAlert)) pretty dialogs
    -- ((Dialogs#textBox)) interface for TextViewer, for scrolling through many paragraps
    -- ((Dialogs#htmlBox)) same as textBox, but now text is presented as HTML, which of course results in more formatting options
    -- ((Dialogs#textBoxTabbed)) and ((Dialogs#htmlBoxTabbed)): for plain text and html in a tabbed interface
end

function XrayInfo:TABS()
    -- for tabbed dialogs: ((Dialogs#htmlBoxTabbed)) or ((Dialogs#textBoxTabbed)) > ((TabFactory#setTabButtonAndContent))

    -- for navigating through these tabs: e.g. ((HtmlBox#initKeyEvents)) > ((TabNavigator#init)) > ((generate tab navigation event handlers))
    -- edge case: when we navigate back in a scrolling html widget, ((ScrollHtmlWidget#scrollText)) > code below direction < 0 ensures we activate the previous tab if we navigate back from the top of the content

    -- for tabbed submenu in dialogs: ((ButtonTableFactory#getTabsTable))

    -- Menu instance with sub tabbuttons: ((XrayDialogs#initListDialog)) with tab_labels and activate_tab_callback > ((Menu#registerTabHotkeys)). These buttons were generated in ((XrayButtons#forListSubmenu)) > ((XrayButtons#getListSubmenuButton)) and the callback for pressing the start characters of tab items is ((XrayModel#activateListTabCallback))
end

function XrayInfo:TAPPED_WORD_MATCHES()
    -- called from ReaderHighlight: ((XrayTappedWords#getXrayItemAsDictionaryEntry)); placing exact partial matches in name or linkwords at top and marking them bold: ((XrayTappedWords#collectionPopulateAndSort)); placing exact fullname matches at position 1: ((XrayTappedWords#getCollection)) in case of needle_matches_fullname == true, which was set in ((XrayViewsData#upgradeNeedleItem))
end

function XrayInfo:XRAY_ITEMS()

    --* see ((Dynamic Xray: module info))

    --! linchpin method: ((XrayUI#ReaderViewGenerateXrayInformation))

    --! skipping paragraph indexing and so xray items for certain kinds of books: ((CreDocument#storeCurrentPageParagraphs)) > ((CreDocument#skipParagraphIndexingForNoXrayBooks))

    -- drawing rects for xray info: ((ReaderView#paintTo)) > ((XrayUI#setParagraphsFromDocument)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#ReaderViewInitParaOrPageData)) > ((XrayUI#ReaderViewLoopThroughParagraphOrPage)) > ((xray page marker set target line for icon)) in page mode

    -- adding match reliability indicators for the page/paragraph info popup: ((XrayUI#matchNameInPageOrParagraph))
    -- using these indicators: ((XrayUI#generateParagraphInformation)) > ((xray items dialog add match reliability explanations)) & ((use xray match reliability indicators))

    -- show paragraph matches: ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#getParaMarker)) and ((CreDocument#storeCurrentPageParagraphs)) > ((XrayUI#getXrayItemsFoundInText)): here matches on page or paragraphs evaluated > ((XrayUI#drawMarker)) > ((set xray page info rects)) KOR.registry:set("xray_page_info_rects") > ((ReaderHighlight#onTapXPointerSavedHighlight)) > here the information in the popup gets combined: ((XrayUI#ReaderHighlightGenerateXrayInformation)) > ((headings for use in TextViewer)) > ((XrayDialogs#showItemsInfo))

    -- max line length in popup info for xray items on page: XrayModel.max_line_length

    -- determining valid needles for matching on page: ((XrayModel#isValidNeedle)) > needle >= 4 characters, OR contains an uppercase character

    -- positioning of page markers: ((XrayUI#ReaderViewLoopThroughParagraphOrPage)) > ((XrayUI#drawMarker)).

    -- automatic toc upon loading of dialog: definition of after_load_callback in ((xray paragraph info: after load callback)) > ((TextViewer execute after load callback)) > ((XrayUI#onInfoPopupLoadShowToc)) > ((TextViewer#showToc))
    -- adding toc buttons: ((TextViewer#getTocIndexButton))

    --- SVG icons
    -- most svg icons downloaded from https://www.onlinewebfonts.com/icon: icons here are licensed by CC BY 4.0
    -- some free svg icons were downloaded from https://www.svgrepo.com
    -- I sometimes have renamed icons, to clarify their function in Dynamic Xray
end

function XrayInfo:XRAY_INFO_TOC_ADD_LINKED_ITEM_BUTTONS()
    -- adding extra linked xray items buttons if available: ((TextViewer#getTocIndexButton)) (for one specific xray item) > ((ButtonChoicePopup#forXrayTocItemEdit)) > set prop extra_callbacks by calling ((TextViewer#addLinkedItemsToTocButton)); also optionally set extra_wide_dialog to true, when linked items found, for more space to display their buttons > ((ButtonProps#injectAdditionalChoiceCallbacks)) > ((ButtonTableFactory#injectButtonIntoTargetRows)); compare ((XRAY_VIEWER_CONTEXT_BUTTONS)).
    -- setting extra wide popup width IF indeed linked items were found: set prop: ((TextViewer#getTocIndexButton)) > ((set extra wide popup for xray items with linked items)) > read prop: ((ButtonProps#popupChoice)) > ((linked xray items in popup))

    -- automatic move of toc popup to top of screen: prop "move_to_top" true in ((Dialogs#showButtonDialog)), called from ((TextViewer#showToc)) > ((move ButtonDialogTitle to top))

    -- adding button to popup toc for closing toc AND paragraph info dialog: ((TextViewer toc popup: add close button for popup and info dialog))

    -- list: ((XrayController#onShowList)) > ((XrayDialogs#showList))

    -- showing list conditionally after saving an item: ((XrayModel#saveNewItem)) or ((XrayController#initAndShowEditItemForm)) > ((XrayController#showListConditionally))

    -- viewer, show item: ((XrayDialogs#viewItem))
end

function XrayInfo:XRAY_VIEWER_CONTEXT_BUTTONS()
    -- viewer, ((multiple related xray items found)) and adding linked items to that dialog: ((XrayButtons#forItemViewerBottomContextButtons))
    -- compare ((XRAY_INFO_TOC_ADD_LINKED_ITEM_BUTTONS))

    -- button for creating new xray items: ((XrayButtons#addTappedWordCollectionButton))

    -- edit item: ((XrayController#initAndShowEditItemForm)) > ((XrayDialogs#showEditItemForm))

    -- generating linked items button rows for item viewer: ((XrayButtons#forItemViewerBottomContextButtons))

    -- filter xray items: ((XrayController#onShowList)) > ((XrayViewsData#updateItemsTable)) > for text filter ((XrayViewsData#filterAndPopulateItemTables)) > continue with ((XrayController#onShowList)) > ((XrayDialogs#showList))

    -- storing new xray items: called from save button generated with ((XrayButtons#forItemAddOrEditForm)) > ((XrayController#saveNewItem)) > ((XrayModel#saveNewItem)) > ((XrayModel#storeNewItem)) > ((XrayController#showListConditionally)) > ((XrayViewsData#updateItemsTable))

    -- storing edited xray items: called from save button generated with ((XrayButtons#forItemAddOrEditForm)) > ((XrayController#saveUpdatedItem)) > ((XrayFormsData#getAndStoreEditedItem)) > ((XrayFormsData#storeItemUpdates)) > ((XrayModel#storeUpdatedItem)) > ((XrayController#showListConditionally)) > ((XrayViewsData#updateItemsTable))
end
