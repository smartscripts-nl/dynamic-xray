
--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local has_no_text = has_no_text
local table_insert = table.insert

--- @class InformationCollector
local InformationCollector = WidgetContainer:extend{
	information_boundaries = nil,
	information_names = {
		glossary = _("Glossary"),
		reference_information = _("Reference Information"),
	},
	information_start = nil,
	--* either "reference_information" or "glossary":
	information_type = nil,
	save_information_format_choice_dialog = nil,
	--* will refer either to the Glossary Viewer or the Reference Information Viewer:
	viewer_instance = nil,
}

function InformationCollector:confirmAddInformationFromScratch(information_type)
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
--- @param parent ReaderHighlight
function InformationCollector:confirmAddInformationAfterExpansion(parent, information_type)
	self.information_type = information_type
	local name = self.information_names[information_type]

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
				if information_type == "reference_information" then
					--* Reference Info will be saved in ((InformationCollector#setInformationBoundaries)) and there will also be shown the Reference Info Viewer:
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
			--* after information end has been selected, information will be stored via ((InformationCollector#setInformationBoundaries)) > ((InformationCollector#addReferenceInformation)) for Reference Information or ((Glossary#addInformation)) for Glossary:
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

function InformationCollector:addReferenceInformation(information_boundaries)

	local information, css_files = KOR.document:getHTMLFromXPointers(information_boundaries[1], information_boundaries[2])
	local information_text = KOR.document:getTextFromXPointers(information_boundaries[1], information_boundaries[2])
	self.information_boundaries = {}
	if has_no_text(information) then
		KOR.messages:notify("er ging iets mis tijdens de tekstselectie")
		self.information_boundaries = nil
		return
	end

	local sample = information_text:sub(1, 250) .. KOR.strings.ellipsis
	self.save_information_format_choice_dialog = KOR.dialogs:niceAlert(_("Save Reference Information"), _("You can save the information either as HTML, or as text.\n\n* Advantage of HTML: looks nicer and is better readable.\n* Advantage of text: searchable.\n\nSTART OF SELECTED TEXT:") .. "\n\n" .. sample, {
		buttons = DX.b:forSaveReferenceInformation(information, information_text, css_files)
	})
end

function InformationCollector:closeContentTypeChoiceDialog()
	UIManager:close(self.save_information_format_choice_dialog)
	self.information_boundaries = nil
end

function InformationCollector:closeViewer()
	UIManager:close(self.viewer_instance)
	self.viewer_instance = nil
end

--- @param parent ReaderHighlight
--- @return boolean To let ReaderHighlight know whether text boundaries selection mode is active or not
function InformationCollector:setInformationBoundaries(parent)
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
	if self.information_type == "reference_information" then
		self:addReferenceInformation(self.information_boundaries)
	else
		KOR.glossary:addInformation(parent:getSelectionText(self.information_boundaries[1], self.information_boundaries[2]))
		KOR.glossary:showViewer()
	end
	parent:clear()

	return true
end

return InformationCollector
