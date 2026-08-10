
--* this is an extension for viewing Reference Information per e-book, with content saved from the text of an e-book. For example a timeline, even in HTML-format, can be viewed.
--* for filling the Reference Information with content, ((InformationMediator)) wil be used.

--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_no_items = has_no_items
local table_concat = table.concat
local table_insert = table.insert

local count

--- @class ReferenceInformation
local ReferenceInformation = WidgetContainer:extend{
	current_ebook_reference_information = nil,
	current_ebook_reference_information_css = nil,
	db_path = nil,
	queries = {
		erase = "UPDATE bookinfo SET reference_information = NULL, reference_information_css = NULL WHERE directory || filename = 'safe_path';",
		load = "SELECT reference_information, reference_information_css FROM bookinfo WHERE directory || filename = 'safe_path';",
		update = "UPDATE bookinfo SET reference_information = ?, reference_information_css = ? WHERE filename = ?;",
	},
}

--* called from ((XrayController#onReaderReady)):
--* information was stored in ((ReferenceInformation#storeInformation)):
function ReferenceInformation:load(full_path)
	self.db_path = full_path
	local sql = KOR.databases:injectSafePath(self.queries.load, self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:load")
	local information, css = conn:rowexec(sql)
	conn = KOR.databases:closeConnections(conn)
	self.current_ebook_reference_information = information
	self.current_ebook_reference_information_css = css
end

--* compare for erasing Glossary ((Glossary#erase)):
function ReferenceInformation:erase()
	local sql = KOR.databases:injectSafePath(self.queries.erase, self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:erase")
	conn:exec(sql)
	conn = KOR.databases:closeConnections(conn)
	self.current_ebook_reference_information = nil

	KOR.messages:notify(_("reference information has been erased"))
end

function ReferenceInformation:storeInformation(information, content_type)
	KOR.informationmediator:closeContentTypeChoiceDialog()
	local css
	if content_type == "html" then
		information, css = self:prepareHtmlAndCssForSaving(information)
	end
	--* don't overwrite previously stored reference information in the same format (HTML or text):
	if self.current_ebook_reference_information
	and (
		(content_type == "html" and self.current_ebook_reference_information:match("<"))
		or
		(content_type == "text" and not self.current_ebook_reference_information:match("<"))
	)
	then
		local separator = content_type == "html" and "<br /> <br />\n" or "\n\n"
		information = self.current_ebook_reference_information .. separator .. information
	end
	self:store(information, css)
	self.current_ebook_reference_information = information
	self.current_ebook_reference_information_css = css
	self:show(information)
end

--- @private
function ReferenceInformation:store(information, css)
	local conn = KOR.databases:getDBconn("ReferenceInformation.store")
	local stmt = conn:prepare(self.queries.update)
	stmt:reset():bind(information, css, DX.m.current_ebook_basename):step()
	conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--- @private
function ReferenceInformation:prepareHtmlAndCssForSaving(information)
	local remove = { "DocFragment", "body", "inlineBox", "autoBoxing" } --"section", "a",
	count = #remove
	for i = 1, count do
		information = information
			:gsub("</" .. remove[i] .. ">", "")
			:gsub("<" .. remove[i] .. "[^>]*>", "")
	end
	--* apparently this gets added by KOReader:
	information = information:gsub("<stylesheet[^<]+</stylesheet>", "")
	information = "<html><body>" .. information .. "</body></html>"

	--* this prop was set in ((InformationMediator#addReferenceInformation))
	local css_files = KOR.informationmediator.css_files
	if has_no_items(css_files) then
		return information
	end

	local css = {}
	count = #css_files
	for i = 1, count do
		table_insert(css, KOR.document:getDocumentFileContent(css_files[i]) .. "\n")
	end
	css = table_concat(css, "")

	css = css
		:gsub("page%-break%-before: always[^;]*;", "")
		.. [[
h1, h2, h3, h4, h5, h6 {
    margin-top: 1.5em !important;
}
]]
	return information, css
end

--* items for this XrayInformation were added in ((InformationMediator#addReferenceInformation)):
--* compare ((Glossary#showViewer)):
function ReferenceInformation:show()
	local glossary = KOR.glossary:get()
	if KOR.informationmediator:showAlternativeViewer("TYPE_REFERENCE_INFORMATION", self.current_ebook_reference_information, glossary) then
		return true
	end

	KOR.dialogsqueue:register({
		id = "show_reference_information",
		restore = function()
			self:show()
		end,
	})

	local is_tabbed = glossary
	local buttons = DX.b:forReferenceInfoTopLeft(is_tabbed)

	local css = self.current_ebook_reference_information_css
	if css then
		local ebook_stylesheet = KOR.ui.typeset.css
		local book_css = KOR.files:fileGetContents(ebook_stylesheet)
		if book_css then
			css = css .. "\n" .. book_css
		end
	end

	--* compare showing Glossary first and Reference Information in second tab in ((Glossary#showViewer)):
	if is_tabbed then
		KOR.dialogs:htmlBoxTabbed(1, {
			title = _("Reference Information + Glossary"),
			css = css,
			tabs = {
				-- #((reference info tab names))
				{
					tab = _("reference information"),
					html = self.current_ebook_reference_information,
					content_type = self.current_ebook_reference_information:match("<") and "html" or "text",
				},
				{
					tab = _("glossary"),
					html = KOR.glossary:getHtmlList(glossary),
				},
			},
			top_buttons_left = buttons,
			fullscreen = true,
		})
		return true
	end

	KOR.dialogs:textOrHtmlBox({
		title = _("Reference Information"),
		top_buttons_left = buttons,
		fullscreen = true,
		css = css,
		content = self.current_ebook_reference_information,
	})
	return true
end

return ReferenceInformation
