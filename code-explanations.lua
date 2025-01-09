
--- @class CodeExplanationsWithBetterHighlights

--- SUBJECTS

-- ((BETTER TYPE HINTS))

-- ((MODIFICATIONS TO KOREADER SOURCE CODE))
-- ! required for use of Dynamic Xray Plugin:
-- ((EXTENSIONS SYSTEM FOR KOREADER))
-- ((EXTENSIONS: CALLING VIA KOR))

-- ((DYNAMIC XRAY PLUGIN))
-- ((MAX DIALOG HEIGHT))
-- ((MOVE MOVABLES TO Y POSITION))


-- ======================================================


-- #((BETTER TYPE HINTS))

-- ! @class
--- use --- @class for class declarations and easy opening of locations in PhpStorm

-- ! @field
--- use --- @field for class fields, to be named with name and type above the class declaration.
-- e.g. see start of ((KOR))

-- ! @type
--- use --- @type for variables (right above their declaration). Example:
--- @type XrayItems manager
local manager

-- ! @param
--- use --- @param for method arguments and loop params (with name of argument first and then type); example for loops:
local titlebars
--- @param v TitleBar
for _, v in ipairs(titlebars) do
    -- nonsense statement :-):
    manager:isXrayItem(v)
end

-- ! @see
--- use @see for links to specific places. Advantage over regular ((name)) references: green color, so stands out. Example:
--- @see TitleBar#init


-- #((MODIFICATIONS TO KOREADER SOURCE CODE))
--- MODIFICATIONS TO KOREADER SOURCE CODE

-- ! WATCH OUT: I have built the extensions system using KOReader version 2024.04! So don't just copy some modified main KOReader modules, because they won't be compatible to the most recent version of KOReader anymore.
-- the reason I had to do this is that with later KOReader versions I ran into trouble when trying to compile KOReader for Android. But probably you won't experience problems when integrating just the XrayItems plugin into KOReader.

--- MOST HEAVILY MODIFIED SOURCE FILES
--- titlebar.lua, textviewer.lua, multiinputdialog.lua
-- ! These files I have included unabridged. But watch out, don't simply copy them into an existing installation. That might break things. Instead compare these files with your version and adapt the code of the latter as needed.
-- For other regular KOReader source files I only have shown the adapted and added code blocks, with some context. So you can apply them to your source code yourself.

-- ! REQUIRED MODIFICATION BY USER:
-- Via ((store ereader model)) > ((Registry#get)) device types are stored in the Registry. This detection is tailored for my situation and devices. So you will have to rewrite that code, to fit your or a more generic situation. Probably the KOReader developers can write better code for this.


-- #((EXTENSIONS SYSTEM FOR KOREADER))
--- EXTENSIONS SYSTEM FOR KOREADER

--- essential modifications:
-- essential modifications to original KOReader to be able to use extensions system:
-- setupkoenv.lua:
-- ((extensions system: add frontend/extensions to package paths))
-- reader.lua:
-- ((reader.lua modification block 1)) for function ((extension));
-- ((reader.lua modification block 2)) for usage of extension ((Registry)) and for often used functions ((has_content)) and ((has_text)). Also here is defined global variable ((AX_registry)), which is required for ((Registry)).
-- initialisation of extensions:
-- making them also available via ((KOR)) extension: ((ReaderUI#registerExtensions)).
-- see ((EXTENSIONS: CALLING VIA KOR)) for an example how to call extension methods.

--- you can also register plugins to KOR:
-- by calling ((KOR#registerPlugin)) from their init method. For example we register the XrayItems plugin by calling KOR:registerPlugin("xrayitems", self) in ((XrayItems#init)).
--- the great advantage of this is that we can call plugin methods directly and dont have to rely on sending events. These calls will be handled noticably quicker because of this alternative way of calling methods.

--- registering main KOReader modules:
-- also the extension system links main KOReader modules to KOR via ((KOR#registerUImodules)), called in the init method of ONLY ONE plugin. For example in ((XrayItems#init)), like so: KOR:registerUImodules(self.ui).
-- by doing so we get clickable calls and code hints for these calls. E.g. KOR.link:onGotoLink() will be clickable in the code and and then jump to ((ReaderLink#onGotoLink)).
-- ! for code hints to work it is important that you define a class type at the start of each module, e.g.:
--- @class ReaderLink


-- #((EXTENSIONS: CALLING VIA KOR))
--- EXTENSIONS: CALLING VIA KOR

-- normally you will call an extension method by loading the extension at the start of a lua file and then call the method.
--- local Dialogs = require("extensions/dialogs")
--- Dialogs:alertInfo("information")

-- ! but sometimes loading an extension in that way will lead to a KOReader crash, because of circular dependencies.
-- in that case use indirect calls in the calling module, like shown below:
-- at the start of modules, where required modules are listed, for your own reference and to prevent accidently causing crashes, show a warning like this:

-- ! use KOR.dialogs instead of Dialogs!
local KOR = require("extensions/kor")
-- [...]
-- and somewhere in your code:
KOR.dialogs:alertInfo("information")


-- #((DYNAMIC XRAY PLUGIN))
--- DYNAMIC XRAY PLUGIN

-- drawing rects for xray info: ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation)) > ((XrayHelpers#ReaderViewInitParaOrPageData)) > ((XrayHelpers#ReaderViewLoopThroughParagraphOrPage))

-- adding match reliability indicators for the page/paragraph info popup: ((XrayHelpers#matchNameInPageOrParagraph))
-- using these indicators: ((XrayHelpers#generateParagraphInformation)) > ((xray items dialog add match reliability explanations)) & ((use xray match reliability indicators))

-- show paragraph matches: ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation)) > ((XrayHelpers#getXrayMarker)) and ((CreDocument#storeCurrentPageParagraphs)) > ((CreDocument#paragraphCleanForXrayMatching)) > ((XrayHelpers#getXrayInfoMatches)): here matches on page or paragraphs evaluated > ((XrayHelpers#drawMarker)) > ((set xray page info rects)) Registry:set("xray_page_info_rects") > ((ReaderHighlight#onTapXPointerSavedHighlight)) > here the information in the popup gets combined: ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) > ((headings for use in TextViewer)) > ((XrayHelpers#showXrayItemsInfo))

-- automatic toc upon loading of dialog: ((xray paragraph info: after load callback)) > ((TextViewer#showToc))
-- automatic move of toc popup to top of screen: prop "move_to_top" true in ((Dialogs#showButtonDialog)) - called from ((TextViewer#showToc)) - > ((move ButtonDialogTitle to top))

-- adding button to popup toc for closing toc AND paragraph info dialog: ((TextViewer toc popup: add close button for popup and info dialog))

-- #((tapped word matches)): called from 2 locations in ReaderHighlight: ((ReaderHighlight#onShowHighlightMenu)) and ((ReaderHighlight#lookup)) > ((XrayHelpers#getXrayItemAsDictionaryEntry)); placing exact partial matches in name or linkwords at top and marking them bold: ((XrayHelpers#sortByBoldProp)); placing exact fullname matches at position 1: ((XrayHelpers#getRelatedItems)) in case of needle_matches_fullname == true, which was set in ((XrayHelpers#upgradeNeedleItem))

-- list: ((XrayItems#onShowXrayList))

-- showing list conditionally after saving an item: ((XrayItems#onSaveNewXrayItem)) or ((XrayItems#onEditXrayItem)) > ((XrayItems#showListConditionally))

-- adding an "add xray item" button to the ReaderHighlight popup for a newly selected selection: ((add xray item button for selected text popup in ReaderHighlight))

-- viewer, show item: ((XrayItems#onShowXrayItem))

-- viewer, ((multiple related xray items found)) and adding linked items to that dialog: ((XrayItems#addContextButtons))

-- add xray item button: ((XrayHelpers#addButton))

-- edit item: ((XrayItems#onEditXrayItem))

-- generating linked items button rows for item viewer: ((XrayItems#addContextButtons))

-- filter xray items: ((XrayItems#onShowXrayList)) > ((XrayItems#updateXrayItemsTable)) > for text filter ((XrayItems#filterByText)) or for icon filter ((XrayItems#filterByIcon)) > continue with ((XrayItems#onShowXrayList))

-- storing new xray items: called from save button generated with ((XrayItems#getFormButtons)) > ((XrayItems#saveItemCallback)) with modus "add" > ((XrayItems#onSaveNewXrayItem)) > ((XrayHelpers#storeAddedXrayItem)) > ((XrayItems#showListConditionally)) > ((XrayItems#updateXrayItemsTable))

-- storing edited xray items: called from save button generated with ((XrayItems#getFormButtons)) > ((XrayItems#saveItemCallback)) with modus "edit" > ((XrayItems#renameXrayItem)) > ((XrayItems#updateXrayItemsList)) > ((XrayHelpers#storeUpdatedXrayItem)) > ((XrayItems#showListConditionally)) > ((XrayItems#updateXrayItemsTable))


-- #((MAX DIALOG HEIGHT))
--- MAX DIALOG HEIGHT
-- keyboard height will be stored automatically via ((InputDialog#init)) > ((InputDialog#storeKeyboardHeight)).
-- the resulting max dialog height will be computed with ((MultiInputDialog#init)) > ((Dialogs#getKeyboardHeight)).


-- #((MOVE MOVABLES TO Y POSITION))
--- MOVE MOVABLES TO Y POSITION
-- ButtonDialogTitle (e.g. for index of paragraph Xray info popup: call ((TextViewer#showToc)) with click on index button, or on load of paragraph Xray info dialog, with ((XrayHelpers#showXrayItemsInfo)): call showToc from after_load_callback, to be executed in ((TextViewer execute after load callback)) > ((Dialogs#showButtonDialog)) > set prop move_to_top to true > ((ButtonDialogTitle#init)) > ((ButtonDialogTitle move to top)) > ((ScreenHelpers#moveMovableToYpos))
-- Help text popup dialog for text info icons: e.g. props info_popup_text in ((XrayItems#getFormFields)) > ((Button#onTapSelectButton)) > self.callback(pos) > ((Dialogs#alertInfo)) > set prop move_to_y_pos = pos.pos.y + 24 for InfoMessage > ((InfoMessage#init)) > ((move InfoMessage to y pos)) > ((ScreenHelpers#moveMovableToYpos))
