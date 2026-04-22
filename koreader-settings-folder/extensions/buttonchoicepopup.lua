--* Button choice_callback props defined here instantiated by ((ButtonProps#set)) called from each method and then executed after button taps by ((ButtonProps#popupChoice))

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local ffiUtil = require("ffi/util")
local T = ffiUtil.template

local DX = DX

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

--* compare ((ButtonInfoPopup#forSeriesAll)):
function ButtonChoicePopup:forSeriesCurrentBook(props)
	return KOR.buttonprops:set({
		icon = "seriesmanager",
		info = T(_("series manager icon %1show all books of series to which the current e-book belongs%2show all series having more than one e-book on this device"), "| :", self.separator),
		callback_label = _("current book"),
		--! callback defined by calling module
		hold_callback_label = _("series overview"),
		--! hold_callback defined by calling module
	}, props)
end

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

function ButtonChoicePopup:forXrayGlossary(props)
	return KOR.buttonprops:set({
		icon = "index",
		info = "signpost icon | :show glossary" .. self.separator .. "add glossary",
		callback_label = _("show"),
		--! callback defined by calling module
		hold_callback_label = _("add"),
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
		info = T(_("bucket icon %1if the current book is part of a series, import Xray items from other books in the series, if they are also mentioned in the current book. Hits/occurrences for all Xray items in the current book will be refreshed.%2import items from another series"), "| :", self.separator),
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

function ButtonChoicePopup:forXrayShowTagsDialogForList(props)
	return KOR.buttonprops:set({
		icon = "tags",
		info = T(_("tags icon | :show popup for tag filters") .. self.separator .. _("show the tag-group-selector, to choose a specific tag-group to display"), KOR.icons.arrow_bare),
		callback_label = _("show"),
		--! callback defined by calling module
		hold_callback_label = _("tag-groups"),
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayPageNavigatorShowTagsDialog(props)
	--* the minus sign is a n_dash:
	local state_marker = DX.pn.navigation_tag and "–" or "+"
	return KOR.buttonprops:set({
		icon_text = {
			icon = "tags",
			text = " " .. state_marker,
		},
		icon = "tags",
		info = T(_("tags icon | Activate (+) or disabled (-) browsing between members of a tag group") .. self.separator .. _("show the tag-group-selector, to choose a specific tag-group to display"), KOR.icons.arrow_bare),
		callback_label = _("browse") .. " " .. state_marker,
		--! callback defined by calling module
		hold_callback_label = _("tag-groups"),
		--! hold_callback defined by calling module
	}, props)
end

function ButtonChoicePopup:forXrayPageNavigatorToCurrentPage(props)
	return KOR.buttonprops:set({
		icon = "goto-location",
		info = T(_("target icon %1in Page Navigator jump back to current page you are reading in your e-book%2in you e-book jump to the page you are currently viewing in Page Navigator"), "| :", self.separator),
		callback_label = _("navigator"),
		--! callback defined by calling module
		hold_callback_label = _("ebook"),
		--! hold_callback defined by calling module
	}, props)
end

return ButtonChoicePopup
