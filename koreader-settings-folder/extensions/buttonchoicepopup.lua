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
		info = T(_("loupe icon %1next or search dialog%2search dialog"), "| :", self.separator),
		callback_label = _("next"),
		--! callback defined by calling module
		hold_callback_label = _("search dialog"),
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayGoBackFromForm(props)
	return KOR.buttonprops:set({
		icon = "back",
		info = T(_("go back icon %1back to list (if that was opened)%2go back"), "| :", self.separator),
		callback_label = _("back to list"),
		--! callback defined by calling module
		hold_callback_label = _("back"),
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayItemsImport(props)
	return KOR.buttonprops:set({
		icon = "fill",
		icon_size_ratio = 0.53,
		info = T(_("fill icon %1if the current book is part of a series, import Xray items from other books in the series, if they are also mentioned in the current book. Hits/occurrences for all Xray items in the current book will be refreshed.%2import items from another series"), "| :", self.separator),
		callback_label = _("import"),
		--! callback defined by calling module
		hold_callback_label = _("external"),
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayItemDelete(props)
	return KOR.buttonprops:set({
		icon = "dustbin",
		icon_size_ratio = 0.5,
		info = T(_("dustbin icon %1delete item and go back to list%2delete item for all book in the current series\n\nHotkeys %3 D for delete, Shift+D for delete for series"), "| :", self.separator, KOR.icons.arrow_bare),
		callback_label = _("delete"),
		--! callback defined by calling module
		hold_callback_label = _("delete all"),
		--! hold_callback defined by calling module
	}, props)
end

--* see also ((Button#init)) > ((hotfix for bold "edit" and "jump" buttons for xray items in page info TOC popup)):
function ButtonChoicePopup:forXrayTocItemEdit(props)
	local args = {
		info = T(_("xray item %1go to this item in the list%2edit this item"), "| :", self.separator),
		is_xray_toc_item = true,
		callback_label = _("jump"),
		--! callback defined by calling module
		hold_callback_label = _("edit"),
		--! hold_callback defined by calling module
		--* extra_callbacks prop, with for each item a callback_label and a callback prop, can be dynamically inserted
	}
	return KOR.buttonprops:set(args, props)
end

return ButtonChoicePopup
