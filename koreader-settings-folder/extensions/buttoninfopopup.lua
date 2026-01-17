
--* Button props for buttons in button tables instantiated below by ((ButtonProps#set)) called from each method and then executed after button taps by ((ButtonProps#popupInfo))

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local ffiUtil = require("ffi/util")
local T = ffiUtil.template

local DX = DX

--* compare ((ButtonChoicePopup)) and ((ButtonProps))
--- @class ButtonInfoPopup
local ButtonInfoPopup = WidgetContainer:new{
	buttons = {},
	use_caching = true,
}

--* these methods return ALL PROPS for a button as a button definition table, to be used as argument for creating a button table

function ButtonInfoPopup:forInputDialogSearchFirst(props)
	return KOR.buttonprops:set({
		text = KOR.icons.first,
		font_bold = true,
		info = _("first-icon | Search first location with this search term."),
		callback_label = _("to first"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forInputDialogSearchNext(props)
	return KOR.buttonprops:set({
		text = KOR.icons.next,
		font_bold = true,
		info = _("next-icon | Search next location with this search term."),
		callback_label = ("next"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forMenuFilterButton(props)
	return KOR.buttonprops:set({
		--! all props defined by caller
	}, props)
end

function ButtonInfoPopup:forMenuGotoRandomPage(props)
	return KOR.buttonprops:set({
		icon = "dice",
		icon_size_ratio = 0.54,
		info = _("dice icon | Go to random (sub)page."),
		callback_label = _("random"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forMenuSearchItem(props)
	return KOR.buttonprops:set({
		icon = "appbar.search",
		icon_size_ratio = 0.54,
		info = _("loupe icon | Search a menu item."),
		callback_label = _("search"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forMenuToAuthorLetter(props)
	return KOR.buttonprops:set({
		text = KOR.icons.arrow_bare .. " A-Z",
		text_font_bold = false,
		info = _("Search for first character of author surname. Character + Enter also works."),
		callback_label = _("go"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forMenuToAuthorLetterOrSubpage(props)
	return KOR.buttonprops:set({
		icon = "yes",
		info = _("In case of character jump to first entry that starts with that. Or jump to specific subpage in case of numbers."),
		callback_label = _("go"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forMenuToLetter(props)
	return KOR.buttonprops:set({
		text = KOR.icons.arrow_bare .. " A-Z",
		text_font_bold = false,
		info = _("Jump to first item starting with the character you entered."),
		callback_label = _("go"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forResetField(props)
	return KOR.buttonprops:set({
		icon = "reset",
		info = _("reset icon | Reset above field, remove its contents."),
		callback_label = "reset",
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forSaveToXray(props)
	return KOR.buttonprops:set({
		text = KOR.icons.xray_person_bare .. "/" .. KOR.icons.xray_term_bare,
		font_bold = false,
		--! info defined by calling module
		callback_label = _("save"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forSearchAllLocations(props)
	return KOR.buttonprops:set({
		icon = "search-all",
		icon_size_ratio = 0.55,
		--! info defined by calling module
		callback_label = _("search"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forSearchAllLocationsGotoLocation(props)
	return KOR.buttonprops:set({
		icon = "goto-location",
		icon_size_ratio = 0.5,
		info = _("target icon | Jump to context of this search hit in book."),
		callback_label = _("jump"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forSearchNew(props)
	return KOR.buttonprops:set({
		text = KOR.icons.search_bare,
		info = _("loupe icon | Enter a new search term."),
		callback_label = _("search"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forSearchResetFilter(props)
	return KOR.buttonprops:set({
		icon = "reset",
		id = "reset",
		icon_size_ratio = 0.5,
		info = _("reset icon | Reset text in search field."),
		callback_label = _("reset"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forTextViewerCopy(props)
	return KOR.buttonprops:set({
		icon = "copy",
		icon_size_ratio = 0.5,
		info = _("copy icon | Copy the text to the clipboard."),
		callback_label = _("copy"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forTextViewerToBottom(props)
	return KOR.buttonprops:set({
		text = "⇲",
		id = "bottom",
		info = _("arrow icon | Jump to end of text."),
		callback_label = _("to end"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forTextViewerToTop(props)
	return KOR.buttonprops:set({
		text = "⇱",
		id = "top",
		info = _("arrow icon | Jump to start of text."),
		callback_label = _("to start"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayExport(props)
	return KOR.buttonprops:set({
		icon = "export-xray",
		info = T(_("export icon | Generate a copyable overview of all Xray items.\n\nYou could print this overview, to have it always ready next to your e-reader.\n\nHotkey %1 %2"), KOR.icons.arrow_bare, DX.s.hk_open_export_list_from_page_navigator),
		callback_label = _("generate"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayFilterByImportantType(props)
	return KOR.buttonprops:set({
		text = KOR.icons.xray_person_important_bare .. "/" .. KOR.icons.xray_term_important_bare,
		fgcolor = Blitbuffer.COLOR_GRAY_3,
		font_bold = false,
		info = _("dark icons | Filter the Xray items for important persons and terms."),
		callback_label = _("filter"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayFilterByText(props)
	return KOR.buttonprops:set({
		icon = "filter",
		info = _("filter icon | Filter the Xray items for text."),
		callback_label = _("filter"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayFromItemToChapter(props)
	return KOR.buttonprops:set({
		icon = "chapter",
		icon_size_ratio = 0.6,
		info = T([[book icon | Jump to a specific chapter.

Hotkey %1 %2]], KOR.icons.arrow_bare, DX.s.hk_open_chapter_from_viewer),
		callback_label = KOR.icons.arrow_bare .. _(" chapter..."),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayFromItemToDictionary(props)
	return KOR.buttonprops:set({
		icon = "book",
		icon_size_ratio = 0.6,
		info = _("book icon | Search for this word in the dictionary."),
		callback_label = _("dictionary"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemAdd(props)
	return KOR.buttonprops:set({
		--icon = "add",
		icon = "plus",
		info = T([[plus icon | Add Xray item..

Hotkey %1 %2]], KOR.icons.arrow_bare, DX.s.hk_add_item),
		callback_label = _("add"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemEdit(props)
	return KOR.buttonprops:set({
		icon = "edit-light",
		icon_size_ratio = 0.6,
		info = T([[edit icon | Edit description.

Hotkey %1 %2]], KOR.icons.arrow_bare, DX.s.hk_edit_item),
		callback_label = _("edit"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemSave(props)
	return KOR.buttonprops:set({
		icon = "save",
		info = _("floppy disk icon | Save modified Xray item."),
		callback_label = _("save"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemSaveAndShowModule(props)
	return KOR.buttonprops:set({
		icon_icon = {
			icon = "save",
			middle_text = KOR.icons.arrow,
			icon2 = props.icon,
			icon_size_ratio = 0.6,
		},
		info = T(_("floppy disk + %1 icon | Save Xray item and show it in the %2."), props.icon2_name, props.icon2_name),
		callback_label = _("save"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemsExportToFile(props)
	return KOR.buttonprops:set({
		icon = "export",
		icon_size_ratio = 0.53,
		info = _("export icon | Export this list to xray-items.txt in the settings folder of KOReader (in most cases named \"koreader\")."),
		callback_label = _("export"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayItemsIndex(props)
	return KOR.buttonprops:set({
		icon = "index",
		icon_size_ratio = 0.53,
		info = _("signpost icon | Show index of Xray items on this page or in this paragraph."),
		callback_label = _("show index"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayList(props)
	return KOR.buttonprops:set({
		icon = "list",
		info = T([[list icon | Show List of Items.

Hotkey %1 %2]], KOR.icons.arrow_bare, DX.s.hk_show_list),
		callback_label = _("list"),
		callback = function()
			DX.c:onShowList()
		end,
	}, props)
end

function ButtonInfoPopup:forXrayNextItem(props)
	return KOR.buttonprops:set({
		text = KOR.icons.next_bare,
		info = T(_([[arrow icon | Go to next Xray item. You can also use the space bar on your (BT) keyboard for this.

Alternate hotkey %1 %2]]), KOR.icons.arrow_bare, DX.s.hk_goto_next_item),
		callback_label = _("to next"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPageNavigator(props)
	return KOR.buttonprops:set({
		icon = "navigator_wheel",
		icon_size_ratio = 0.53,
		info = _("navigator icon | In a popup dialog navigate through the pages of the current ebook and see which Xray items they contain. For each Xray item you can request additional info about them."),
		callback_label = _("navigate"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPageNavigatorContextButtons(props)
	return KOR.buttonprops:set({
		icon = "link",
		icon_size_ratio = 0.53,
		info = "link-ikoon | Open het paneel met context-items bij het item dat op dit moment in het onderpaneel geladen is.",
		callback_label = "context-items",
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPageNavigatorFilter(props)
	local filter_info = _("filter icon | Filter pages for occurrences of the item currently displayed in the bottom info panel. So the Navigator only jump between pages which have this item.")
	local reset_filter_info = _("filter icon | Reset the filter for Page Navigator.")
	return KOR.buttonprops:set({
		icon = DX.pn.page_navigator_filter_item and "filter-reset" or "filter",
		icon_size_ratio = 0.53,
		info = DX.pn.page_navigator_filter_item and reset_filter_info or filter_info,
		callback_label = DX.pn.page_navigator_filter_item and _("reset filter") or _("filter"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPageNavigatorMainButtons(props)
	return KOR.buttonprops:set({
		icon = "page-light",
		icon_size_ratio = 0.53,
		info = "pagina-ikoon | Open het hoofdpaneel met items in de huidige pagina.",
		callback_label = "context-items",
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPageNavigatorShowPageBrowser(props)
	return KOR.buttonprops:set({
		icon = "pages",
		icon_size_ratio = 0.53,
		info = T(_("pages icon | Show page currently shown in Pagina Navigator in a page browser popup.\n\n You can use this to quickly jump many page back or forth in Page Navigator, by tapping on a thumnail in the page browser.\n\nHotkey %1 %2"), KOR.icons.arrow_bare, DX.s.hk_show_pagebrowser_from_page_navigator),
		callback_label = _("page browser"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayPreviousItem(props)
	return KOR.buttonprops:set({
		text = KOR.icons.previous_bare,
		info = T(_([[arrow icon | Go to previous Xray item. You can also use Shift+Space on your (BT) keyboard for this.

Alternate hotkey %1 %2]]), KOR.icons.arrow_bare, DX.s.hk_goto_previous_item),
		callback_label = _("to previous"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXraySettings(props)
	return KOR.buttonprops:set({
		icon = "appbar.settings",
		info = _("cog icon | Open list of Dynamic Xray settings and modify them if needed."),
		callback_label = _("settings"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayShowMatchReliabilityExplanation(props)
	return KOR.buttonprops:set({
		icon = "info-slender",
		icon_size_ratio = 0.5,
		info = T(_("information icon | Show explanation of reliability icons for hits found.\n\nHotkey %1 %2"), KOR.icons.arrow_bare, DX.s.hk_show_information),
		callback_label = _("show"),
		callback = function()
			return DX.d:showReliabilityIndicatorsExplanation()
		end,
	}, props)
end

function ButtonInfoPopup:forXrayToggleImportantItem(props)
	return KOR.buttonprops:set({
		fgcolor = Blitbuffer.COLOR_GRAY_3,
		font_bold = false,
		info = _("dark icons | Toggle to mark this xray-item as important or regular item."),
		callback_label = _("toggle"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayTogglePageOrParagraphInfo(props)
	return KOR.buttonprops:set({
		icon_size_ratio = 0.4,
		info = _("page or paragraph icon | Toggle between display of Xray information per page or paragraph."),
		callback_label = _("toggle"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayToggleBookOrSeriesMode(props)
	return KOR.buttonprops:set({
		icon = "book",
		--* info and callback_label props will be defined by caller
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayTogglePersonOrTerm(props)
	return KOR.buttonprops:set({
		fgcolor = Blitbuffer.COLOR_GRAY_3,
		font_bold = false,
		info = _("user of bulb icon | Toggle to mark this xray-item as person or term."),
		callback_label = _("toggle"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayToggleSortingMode(props)
	return KOR.buttonprops:set({
		icon = "sort",
		--* info and callback_label props will be defined by caller
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forTranslationEditorResetText(props)
	return KOR.buttonprops:set({
		icon = "reset",
		info = _("reset icon | Reset the text in the text editor to the untranslated, English text."),
		callback_label = _("reset"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forTranslationsResetAll(props)
	return KOR.buttonprops:set({
		icon = "reset",
		info = _("reset icon | Reset ALL(!) translations to the untranslated, English texts."),
		callback_label = _("reset"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayTranslations(props)
	return KOR.buttonprops:set({
		icon = "translate",
		info = "vertaal-ikoon | Vertaal teksten in de DX interface.",
		callback_label = "vertaal",
		callback = function()
			if DX.m:isPrivateDXversion() then
				return
			end
			DX.tm:manageTranslations()
		end,
	}, props)
end

function ButtonInfoPopup:forXrayTypeSet(props, add_horizontal_button_padding)
	local show_all_icons = true
	local label = show_all_icons
		and KOR.icons.xray_person_bare .. KOR.icons.xray_person_important_bare .. KOR.icons.xray_term_bare .. KOR.icons.xray_term_important_bare
		or
		KOR.icons.xray_person_bare .. "/" .. KOR.icons.xray_term_bare
	if add_horizontal_button_padding then
		label = "  " .. label .. "  "
	end
	return KOR.buttonprops:set({
		text = label,
		fgcolor = Blitbuffer.COLOR_GRAY_3,
		font_bold = false,
		info = _("user/bulb icons | Set Xray type."),
		callback_label = ("set"),
		--! callback defined by calling module
	}, props)
end

function ButtonInfoPopup:forXrayViewer(props)
	return KOR.buttonprops:set({
		icon = "view",
		info = _("eye icon | Open Xray Item Viewer for the item displayed in the bottom panel."),
		callback_label = _("open"),
		--! callback defined by calling module
	}, props)
end

return ButtonInfoPopup
