
--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_content = has_content
local has_no_text = has_no_text
local table_insert = table.insert

--- @class InformationMediator
local InformationMediator = WidgetContainer:extend{
	css_files = nil,
	information_boundaries = nil,
	information_names = {
		_("Glossary"),
		_("Reference Information"),
	},
	information_start = nil,
	--* either "reference_information" or "glossary":
	information_type = nil,
	save_information_format_choice_dialog = nil,
	TYPE_GLOSSARY = 1,
	TYPE_REFERENCE_INFORMATION = 2,
}

--* called from the Page Navigator popup menu:
--* compare ((InformationMediator#confirmAddInformationAfterExpansion))
--- @param information_type string "TYPE_GLOSSARY" or "TYPE_REFERENCE_INFORMATION"
function InformationMediator:confirmAddInformationFromScratch(information_type)
	information_type = self:getNumericalTypeValue(information_type)
	self.information_type = information_type
	local name = self.information_names[information_type]
	KOR.dialogs:confirm(_("Do you indeed want to save the text to be selected as the") .. "\n\n" .. name .. "\n\n" .. _("for the current e-book?"), function()
		DX.pn:closePageNavigator()
		self.information_boundaries = {}
		local hotkey = name == _("Glossary") and "Shift+G" or "Shift+R"
		KOR.dialogs:niceAlert(_("Adding ") .. name, T(_("Browse now:\n\n1) to the start of the information in the ebook and mark the beginning thereof with a text selection;\n2) next repeat this for the end of the information.\n\nAfter this is done, the Reference Information will be saved to the database and shown in a popup.\n\nYou can from now on view the %1 anytime, when in the current ebook, with %2 on your physical (BT) keyboard."), name, hotkey))
	end)

	return true
end

--* this will be called from the ReaderHighlight popup for a new text selection:
--* compare ((InformationMediator#confirmAddInformationFromScratch)):
--- @param parent ReaderHighlight
--- @param information_type string "TYPE_GLOSSARY" or "TYPE_REFERENCE_INFORMATION"
function InformationMediator:confirmAddInformationAfterExpansion(parent, information_type)

	self.information_type = self:getNumericalTypeValue(information_type)

	local name = self.information_names[self.information_type]

	UIManager:close(parent.highlight_dialog)
	parent.highlight_dialog = nil
	UIManager:forceRePaint()
	KOR.screenhelpers:refreshScreen()

	local dialog
	dialog = KOR.dialogs:multiConfirm(_("Do you want to add the selected text to the") .. "\n\n" .. name .. "?\n\n" .. _("Or do you want to first expand the text to be saved, by highlighting the end of that text?"), {{
		{
			icon = "back",
			callback = function()
				parent:onClose()
				UIManager:close(dialog)
				self.information_boundaries = nil
			end,
		},
		{
			text = _("save now"),
			callback = function()
				--* self.information_type was set at start of current method:
				if self.information_type == self.TYPE_REFERENCE_INFORMATION then
					--* Reference Info will be saved in ((InformationMediator#setInformationBoundaries)) and there will also be shown the Reference Info Viewer:
					self:addReferenceInformation({
						parent.selected_text.pos0,
						parent.selected_text.pos1,
					})
				else
					KOR.glossary:addInformation(parent:getSelectionText())
					KOR.messages:notify(_("text added to glossary"))
					KOR.glossary:showViewer()
				end
				parent:onClose()
				UIManager:close(dialog)
			end,
		},
		{
			text = _("expand"),
			--* after information end has been selected, information will be stored via ((InformationMediator#setInformationBoundaries)) > ((InformationMediator#addReferenceInformation)) for Reference Information, or ((Glossary#addInformation)) for Glossary:
			callback = function()
				local hotkey = name == _("Glossary") and "Shift+G" or "Shift+R"
				self.information_boundaries = {
					parent.selected_text.pos0,
				}
				parent:onClose()
				UIManager:close(dialog)
				KOR.dialogs:niceAlert(_("Expanding text for ") .. " " .. name, T(_("Browse now to the end of the information to be saved.\n\nAfter this is done, the %1 will be saved and shown in a popup.\n\nYou can from now on view the %1 anytime, when in the current ebook, with %2 on your physical (BT) keyboard."), name, hotkey))
			end,
		},
	}})

	return true
end

function InformationMediator:addReferenceInformation(information_boundaries)

	--* html_flags 0xE830 and last argument true are needed to get ebook css_files:
	local information
	--* the css_files prop will be used when displaying the reference information, in ((ReferenceInformation#prepareHtmlAndCssForSaving)):
	information, self.css_files = KOR.document:getHTMLFromXPointers(information_boundaries[1], information_boundaries[2], 0xE830, true)

	local information_text = KOR.document:getTextFromXPointers(information_boundaries[1], information_boundaries[2])
	self.information_boundaries = {}
	if has_no_text(information) then
		KOR.messages:notify(_("something went wrong during text-selection"))
		self.information_boundaries = nil
		return
	end

	local sample = information_text:sub(1, 250) .. KOR.strings.ellipsis
	self.save_information_format_choice_dialog = KOR.dialogs:niceAlert(_("Save Reference Information"), _("You can save the information either as HTML, or as text.\n\n* Advantage of HTML: may look nicer and be better readable.\n* Advantage of text: searchable.\n\nSTART OF SELECTED TEXT:") .. "\n\n" .. sample, {
		buttons = DX.b:forSaveReferenceInformation(information, information_text)
	})
end

function InformationMediator:closeContentTypeChoiceDialog()
	UIManager:close(self.save_information_format_choice_dialog)
	self.information_boundaries = nil
end

--- @param parent ReaderHighlight
--- @return boolean To let ReaderHighlight know whether text boundaries selection mode is active or not
function InformationMediator:setInformationBoundaries(parent)
	if not self.information_boundaries then
		return false
	end

	--* when we select a text from scratch:
	if #self.information_boundaries == 0 then
		table_insert(self.information_boundaries, parent.selected_text.pos0)
		parent:clear()
		KOR.messages:notify(_("start of text to be saved registered; now highlight its end"))
		return true
	end

	--* when the starting boundary has already been defined:
	table_insert(self.information_boundaries, parent.selected_text.pos1)

	--* self.information_type was set at start of ((InformationMediator#confirmAddInformationAfterExpansion)):
	if self.information_type == self.TYPE_REFERENCE_INFORMATION then
		self:addReferenceInformation(self.information_boundaries)
	else
		KOR.glossary:addInformation(parent:getSelectionText(self.information_boundaries[1], self.information_boundaries[2]))
		KOR.glossary:showViewer()
	end
	parent:clear()

	--! reset the information_boundaries, so we won't add the same text over and over again:
	self.information_boundaries = nil

	return true
end

--- @param information_type string "TYPE_GLOSSARY" or "TYPE_REFERENCE_INFORMATION"
function InformationMediator:showAlternativeViewer(information_type, information, glossary)
	if has_content(information) then
		return false
	end
	information_type = self:getNumericalTypeValue(information_type)
	local glossary_called = information_type == self.TYPE_GLOSSARY

	--* show Reference Information instead of missing Glossary:
	if glossary_called and KOR.referenceinformation.current_ebook_reference_information then
		KOR.messages:notify(T(_("no glossary available %1 show reference-info"), KOR.icons.arrow_bare), 4)
		KOR.referenceinformation:show()

	--* show Glossary instead of missing Reference Information:
	elseif information_type == self.TYPE_REFERENCE_INFORMATION and not KOR.referenceinformation and has_content(glossary) then
		KOR.messages:notify(T(_("no reference-info available %1 show glossary"), KOR.icons.arrow_bare), 4)
		KOR.glossary:showViewer()

	--* show reference types information:
	else
		local active_tab = glossary_called and 1 or 2
		DX.i:showReferenceInformation(active_tab)
	end

	return true
end

function InformationMediator:closeViewerInstance()
	UIManager:close(KOR.dialogs.last_dialog_instance)
	KOR.dialogs.last_dialog_instance = nil
end

function InformationMediator:eraseInformation(is_tabbed, target)

	local name = self.information_names[target]
	KOR.dialogs:confirm(T(_("Do you indeed want to erase the %1?"), name), function()

		self:closeViewerInstance()
		local erase_glossary = target == self.TYPE_GLOSSARY

		--* if there was no second type with other reference information, erase the information and don't open dialog again:
		if not is_tabbed and erase_glossary then
			KOR.glossary:erase()
			return
		elseif not is_tabbed then
			KOR.referenceinformation:erase()
			return
		end

		--* there will still be one remaining information tab, so when erasing Glossary show Reference Information and vice versa:
		if erase_glossary then
			KOR.glossary:erase()
			KOR.referenceinformation:show()
		else
			KOR.referenceinformation:erase()
			KOR.glossary:showViewer()
		end
	end)
end

--- @private
--- @param information_type string "TYPE_GLOSSARY" or "TYPE_REFERENCE_INFORMATION" =>  self.TYPE_GLOSSARY: 1, or self.TYPE_REFERENCE_INFORMATION: 2
--- @return number
function InformationMediator:getNumericalTypeValue(information_type)
	return self[information_type]
end

--- @param default_target string "TYPE_GLOSSARY" or "TYPE_REFERENCE_INFORMATION"
function InformationMediator:getViewerTargetTypeToBeErased(is_tabbed, default_target)
	default_target = self:getNumericalTypeValue(default_target)
	return not is_tabbed and default_target or KOR.dialogs.active_tab_name == _("glossary")
		and
		self.TYPE_GLOSSARY
		or
		self.TYPE_REFERENCE_INFORMATION
end

return InformationMediator
