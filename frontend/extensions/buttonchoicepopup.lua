--* Button choice_callback props defined here instantiated by ((ButtonProps#set)) called from each method and then executed after button taps by ((ButtonProps#popupChoice))

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local ffiUtil = require("ffi/util")
local T = ffiUtil.template

--* compare ((ButtonInfoPopup)) and ((ButtonProps))
--* see also ((BUTTONCHOICEPROPS_MORE_THAN_2))
--- @class ButtonChoicePopup
local ButtonChoicePopup = WidgetContainer:new{
	buttons = {},
	scroll_toggle_message = "schakel scrollend dialoogvenster (1 = dynamisch, 2 = vaste hoogte MET scrollbar, 3 = vaste hoogte ZONDER scrollbar)",
	separator = "\n\n:",
	use_caching = true,
}

--* these methods return ALL PROPS for a button as a button definition table, to be used as argument for creating a button table

--* ":\n" and separator ":\n\n" in buttons in this class will be replaced by the label words, in ((ButtonProps#setOverruleProps)):

function ButtonChoicePopup:forTextViewerSearch(props)
	return KOR.buttonprops:set({
		icon = "appbar.search",
		icon_size_ratio = 0.6,
		id = "find",
		info = "loupe-ikoon | :volgende of zoekvenster" .. self.separator .. "zoekvenster",
		callback_label = "volgende",
		--! callback defined by calling module
		hold_callback_label = "zoekvenster",
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayGoBackFromForm(props)
	return KOR.buttonprops:set({
		icon = "back",
		info = "terug-ikoon | :terug naar lijst (indien die geopend was)" .. self.separator .. "terug",
		callback_label = "terug > lijst",
		--! callback defined by calling module
		hold_callback_label = "terug",
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayItemsImport(props)
	return KOR.buttonprops:set({
		icon = "fill",
		icon_size_ratio = 0.53,
		info = "vul-ikoon | :indien het boek deel uitmaakt van serie, importeer dan items uit de andere boeken daarin indien ze ook in het huidige boek voorkomen. Voor alle items wordt het aantal keren dat ze in het huidige boek voorkomen ververst." .. self.separator .. "importeer items vanuit een andere serie",
		callback_label = "importeer",
		--! callback defined by calling module
		hold_callback_label = "extern",
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayItemDelete(props)
	return KOR.buttonprops:set({
		icon = "dustbin",
		icon_size_ratio = 0.5,
		info = T("prullenmand-ikoon | :verwijder item en ga naar lijst" .. self.separator .. "verwijder item voor alle boeken uit de serie\n\nHotkeys %1 D voor verwijder, Shift+D voor verwijder alle", KOR.icons.arrow_bare),
		callback_label = "verwijder",
		--! callback defined by calling module
		hold_callback_label = "verwijder alle",
		--! hold_callback defined by calling module
	}, props)
end

--* see also ((Button#init)) > ((hotfix for bold "edit" and "jump" buttons for xray items in page info TOC popup)):
function ButtonChoicePopup:forXrayTocItemEdit(props)
	local args = {
		info = "xray item | :spring naar dit item in het overzicht" .. self.separator .. "bewerk dit item",
		is_xray_toc_item = true,
		callback_label = _("jump"),
		--! callback defined by calling module
		hold_callback_label = _("edit"),
		--! hold_callback defined by calling module
		--* extra_callbacks prop, with for each item a callback_label and a callback prop, can be dynamically inserted
	}
	return KOR.buttonprops:set(args, props)
end

function ButtonChoicePopup:getScrollMessage(main_function)
	local message = "pijl-ikoon | :" .. main_function .. self.separator .. self.scroll_toggle_message .. "\n\nhuidige instelling: " .. KOR.registry.use_scrolling_dialog .. ". " .. KOR.registry.scroll_messages[KOR.registry.use_scrolling_dialog]

	return message
end

return ButtonChoicePopup
