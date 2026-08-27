
--* this is an extension for viewing Reference Information per e-book, with content saved from the text of an e-book. For example a timeline, even in HTML-format, can be viewed.
--* for filling the Reference Information with content, ((InformationMediator)) wil be used.

--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_no_items = has_no_items
local has_text = has_text
local string_gmatch = string_gmatch
local table_concat = table_concat
local table_insert = table_insert

local count

--- @class ReferenceInformation
local ReferenceInformation = WidgetContainer:extend{
	current_ebook_reference_information = nil,
	current_ebook_reference_information_css = nil,
	db_path = nil,
	headings = nil,
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

	--* text for searching for headings:
	self.information_for_matching = information

	if has_text(information) then
		self.headings = {}
		for icon_heading, heading in string_gmatch(information, "☀([^ ]+)([^\n]+)") do
			table_insert(self.headings, {
				heading = icon_heading .. heading,
				is_sub_heading = not icon_heading:match("█") and not icon_heading:match("▉")
			})
		end
		if #self.headings == 0 then
			self.headings = nil
		end

		--* text for display in TextViewer, remove sun icons:
		self.current_ebook_reference_information = information:gsub(KOR.registry.wiki_heading_needle, "")
	end

	self.current_ebook_reference_information_css = css
end

--* compare for erasing Glossary ((Glossary#erase)):
function ReferenceInformation:erase()
	local sql = KOR.databases:injectSafePath(self.queries.erase, self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:erase")
	conn:exec(sql)
	conn = KOR.databases:closeConnections(conn)
	self.current_ebook_reference_information = nil
	self.information_for_matching = nil

	KOR.messages:notify(_("reference information has been erased"))
end

function ReferenceInformation:addWikiContent(display_word, callback)
	local example = KOR.registry.wiki_content:sub(1, 130):gsub(" [^ ]+$", "") .. KOR.strings.ellipsis
	KOR.dialogs:confirm("Wil je inderdaad onderstaande Wikipedia-informatie toevoegen aan de Referentie Informatie voor het huidige e-book?\n\n________________________________\n\n" .. example, function()


		local content = KOR.registry.wiki_content
		   :gsub("(\u{2588})", "☀%1")
		   :gsub("(\u{2589})", "☀%1")
		   :gsub("(\u{25E4})", "☀%1")
		   :gsub("(\u{25C6})", "☀%1")
		   :gsub("(\u{273F})", "☀%1")
		   :gsub("(\u{2756})", "☀%1")

		content = display_word and "☀\u{2588} === " .. KOR.strings:upper(display_word) .. " === \u{2588}\n\n" .. content or content

		self:storeInformation(content)

		KOR.registry.wiki_content = nil
		KOR.messages:notify("wikipedia-informatie toegevoegd")
		if callback then
			--* the new content will be shown in ((ReferenceInformation#show)):
			callback()
		end
	end)
end

function ReferenceInformation:storeInformation(information, content_type)

	KOR.informationmediator:closeContentTypeChoiceDialog()
	local css
	content_type = self:getContentType(information, content_type)
	if content_type == "html" then
		information, css = self:prepareHtmlAndCssForSaving(information)
	end
	local current_content_type = self:getContentType(self.current_ebook_reference_information)
	local separator = content_type == "html" and "<br /> <br />\n" or "\n\n"

	--* if previous stored context was plain text, convert it to HTML if HTML content is added:
	if current_content_type and content_type == "html" and content_type ~= current_content_type then

		self.current_ebook_reference_information = KOR.html:textToHtml(self.current_ebook_reference_information)

		--* if previous stored context was HTML, convert plain text information to be added to HTML:
	elseif current_content_type and content_type == "text" and content_type ~= current_content_type then

		information = KOR.html:textToHtml(information)
		separator = "<br /> <br />\n"
	end

	if content_type == "text" then
		information = KOR.strings:indentText(information)
	end

	if current_content_type then
		information = self.current_ebook_reference_information .. separator .. information
	end
	if css and self.current_ebook_reference_information_css then
		css = self.current_ebook_reference_information_css .. "\n\n" .. css
	end
	self:store(information, css)
	self.current_ebook_reference_information = information
	if css then
		self.current_ebook_reference_information_css = css
	end
	self:show(information)
end

--- @private
function ReferenceInformation:getContentType(information, content_type)
	if not information then
		return
	end
	if content_type then
		return content_type
	end
	return information:match("<") and "html" or "text"
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

	--* compare showing Glossary first and Reference Information in second tab in ((Glossary#showViewer)):
	if is_tabbed then
		KOR.dialogs:htmlBoxTabbed(1, {
			title = _("Reference Information + Glossary"),
			is_reference_information_or_glossary = true,
			tabs = {
				-- #((reference info tab names))
				{
					tab = _("reference information"),
					html = self.current_ebook_reference_information,
					content_type = self.current_ebook_reference_information:match("<") and "html" or "text",
				},
				{
					tab = _("glossary"),
					--* Glossary is saved as plain-text, but shown as HTML:
					content_type = "html",
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
		is_reference_information_or_glossary = true,
		content = self.current_ebook_reference_information,
		headings = self.headings,
	})
	return true
end

return ReferenceInformation
