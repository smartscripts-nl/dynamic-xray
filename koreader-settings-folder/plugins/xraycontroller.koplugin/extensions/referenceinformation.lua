
--* this is an extension for viewing Reference Information per e-book, with content saved from the text of an e-book. For example a timeline, even in HTML-format, can be viewed.
--* for filling the Reference Information with content, ((InformationMediator)) wil be used.

--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

--* hotkey for the Reference Information Viewer defined in ((hotkey for Reference Information Viewer))

local require = require

local ButtonDialog = require("xrayviews/widgets/buttondialog")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local _ = KOR:initCustomTranslations()

local DX = DX
local has_items = has_items
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local string_gmatch = string_gmatch
local T = T
local table_concat = table_concat
local table_insert = table_insert
local tonumber = tonumber
local utf8upper = utf8upper

local count

--- @class ReferenceInformation
local ReferenceInformation = WidgetContainer:extend{
	current_ebook_reference_information = nil,
	current_ebook_reference_information_css = nil,
	db_path = nil,
	--* a table:
	headings = nil,
	headings_db = "",
	info_dialog = nil,
	loaded_for_book = nil,
	queries = {
		erase = [[
		UPDATE bookinfo SET
			reference_information = NULL,
			reference_information_headings = NULL,
			reference_information_css = NULL
		WHERE directory || filename = 'safe_path';]],

		load = "SELECT reference_information, reference_information_headings, reference_information_css FROM bookinfo WHERE directory || filename = 'safe_path';",

		update = [[
		UPDATE bookinfo SET
			reference_information = ?,
			reference_information_headings = ?,
			reference_information_css = ?
		WHERE directory || filename = ?;]],
	},
	--* these headings are used in ((ReferenceInformation#addWikiContent)):
	wiki_heading1 = "\u{2588}",
	wiki_heading2 = "\u{2589}",
	wiki_heading3 = "\u{25E4}",
	--* this combination-symbol might be injected in ReaderWikipedia:
	wiki_heading3_with_indent = "\u{00A0}\u{25E4}",
	wiki_heading4 = "\u{25C6}",
	wiki_heading5 = "\u{273F}",
	wiki_heading6 = "\u{2756}",
	--wiki_heading_needle = "█▉◤◆✿❖",
	wiki_heading_needle = "☀",
	--* these are the symbols used in ReaderWikipedia:
	wiki_heading_markers = {
		"█",
		"▉",
		" ◤",
		"◆",
		"✿",
		"❖",
	},
}

function ReferenceInformation:hasInfo()
	return has_text(self.current_ebook_reference_information, "return_boolean")
end

--* called from ((XrayController#onReaderReady)):
--* information was stored in ((ReferenceInformation#storeInformation)):
function ReferenceInformation:load(full_path)
	self.db_path = full_path
	local sql = KOR.databases:injectSafePath(self.queries.load, self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:load")
	local information, css
	information, self.headings_db, css = conn:rowexec(sql)
	conn = KOR.databases:closeConnections(conn)
	if has_no_text(self.headings_db) then
		self.headings_db = ""
		self.headings = nil
	else
		self.headings = KOR.strings:split(self.headings_db, "\n")
	end

	if has_no_text(information) then
		self.current_ebook_reference_information = nil
		self.current_ebook_reference_information_css = nil
		return
	end
	self.current_ebook_reference_information = information
	self.current_ebook_reference_information_css = css
end

--- @private
function ReferenceInformation:getWikiHeadingLevel(icon_heading)
	for i = 1, #self.wiki_heading_markers do
		if self.wiki_heading_markers[i]:match(icon_heading) then
			return i
		end
	end
end

--* compare for erasing Glossary ((Glossary#erase)):
function ReferenceInformation:erase()
	local sql = KOR.databases:injectSafePath(self.queries.erase, self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:erase")
	conn:exec(sql)
	conn = KOR.databases:closeConnections(conn)
	self:resetProps()

	KOR.messages:notify(_("reference information has been erased"))
end

function ReferenceInformation:addWikiContent(wikipedia_needle, callback)
	KOR.dialogs:confirm(_("Do you indeed want to add this Wikipedia article to the Reference Information for the current e-book?"), function()

		--* see for available text symbols ReaderWikipedia:
		--* this needle is only temporary, will be remove after headings have been determined:
		local replacement = self.wiki_heading_needle .. "%1"
		local content = KOR.registry.wiki_content
		   :gsub(T("(%1)", self.wiki_heading1), replacement)
		   :gsub(T("(%1)", self.wiki_heading2), replacement)
		   :gsub(T("(%1)", self.wiki_heading3), replacement)
		   :gsub(T("(%1)", self.wiki_heading4), replacement)
		   :gsub(T("(%1)", self.wiki_heading5), replacement)
		   :gsub(T("(%1)", self.wiki_heading6), replacement)

		--* prefix top level heading if Wikipedia search term determined:
		content = wikipedia_needle and T("%1%2 === %3 === %4\n\n", self.wiki_heading_needle, self.wiki_heading1, utf8upper(wikipedia_needle), self.wiki_heading1) .. content or content

		self:storeInformation(content)

		KOR.registry.wiki_content = nil
		KOR.messages:notify(_("wikipedia-information has been added"))
		if callback then
			--* the new content will be shown in ((ReferenceInformation#show)):
			callback()
		end
	end)
end

function ReferenceInformation:storeInformation(information, new_content_type)

	KOR.informationmediator:closeContentTypeChoiceDialog()

	local html_separator = "<p class='whitespace'> </p>\n"
	new_content_type = self:getContentType(information, new_content_type)
	if new_content_type == "html" then
		--* the CSS determined here will be used in ((ReferenceInformation#show)):
		information = self:prepareHtmlAndCssForSaving(information)
	else
		information = self:prepareWikiContentForSaving(information)
	end
	local current_content_type = self:getContentType(self.current_ebook_reference_information)
	local separator = (new_content_type == "html" or current_content_type == "html") and html_separator or "\n\n"

	--* if previous stored context was plain text, convert it to HTML if HTML content is added:
	--* headings for the older content have already been registered when it was stored:
	if current_content_type == "text" and new_content_type == "html" then

		self.current_ebook_reference_information = KOR.html:textToHtml(self.current_ebook_reference_information)

		--* if previous stored context was HTML, convert plain text information to be added to HTML:
	elseif current_content_type == "html" and new_content_type == "text" then
		--* Wikipedia-heading markers will also be converted to regular html headings here:
		information = KOR.html:textToHtml(information)
	end

	--* after determining headings and optionally converting text to html, this needle is not needed in the text anymore:
	information = information:gsub(self.wiki_heading_needle, "")

	if new_content_type == "text" then
		information = KOR.strings:cleanupPlainText(information)
	else
		information = KOR.html:makeFirstParaNonIndented(information)
	end
	if not self.current_ebook_reference_information then
		self.current_ebook_reference_information = ""
		separator = ""
	end
	self.current_ebook_reference_information = self.current_ebook_reference_information .. separator .. information

	if has_text(self.headings_db) then
		self.headings = KOR.strings:split(self.headings_db, "\n")
	end

	self:store()
	self:show()
end

--- @private
function ReferenceInformation:addWikiHeadings(information)

	--* sun icon markers were already injected here by ((ReferenceInformation#addWikiContent)):
	if not information:match(self.wiki_heading_needle) then
		return
	end

	local headings = {}
	--* these are "headings" in plain-text format:
	local matcher = self.wiki_heading_needle .. "([^ ]+)([^\n]+)"
	local level, indent
	for icon_heading, heading in string_gmatch(information, matcher) do
		level = self:getWikiHeadingLevel(icon_heading)
		indent = level > 2 and KOR.strings.indent_soft_more or ""
		table_insert(headings, indent .. icon_heading .. heading)
	end
	self.headings_db = self.headings_db .. table_concat(headings, "\n") .. "\n"
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
function ReferenceInformation:store()
	local conn = KOR.databases:getDBconn("ReferenceInformation.store")
	local stmt = conn:prepare(self.queries.update)
	stmt:reset():bind(self.current_ebook_reference_information, self.headings_db, self.current_ebook_reference_information_css, DX.m.current_ebook_full_path):step()
	conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--- @private
function ReferenceInformation:prepareHtmlAndCssForSaving(information)
	information = KOR.html:removeUnwantedElements(information)
	--* apparently this gets added by KOReader:
	information = information:gsub("<stylesheet[^<]+</stylesheet>", "")

	--* match for headings:
	local headings = {}
	local matcher = "<h(%d)>([^<]+)</h%d>"
	local indent, icon
	for level, heading in string_gmatch(information, matcher) do
		level = tonumber(level)
		icon = self.wiki_heading_markers[level]
		indent = level > 2 and KOR.strings.indent_soft_more or ""
		table_insert(headings, T("%1%2 %3", indent, icon, heading))
	end
	if #headings == 0 then
		local current_page = KOR.ui:getCurrentPage()
		local xp = KOR.document:getPageXPointer(current_page)
		local current_toc_title = KOR.toc:getTocTitleByPage(xp)
		if has_text(current_toc_title) then

			self.headings_db = self.headings_db .. self.wiki_heading_markers[1] .. " === " .. current_toc_title .. " === " .. self.wiki_heading_markers[1] .. "\n"

			--* prefix the chapter heading to the text:
			information = "<h1>"  .. self.wiki_heading_markers[1] .. " " .. current_toc_title .. " " .. self.wiki_heading_markers[1] .. "</h1>\n" .. information
		end

	--* add the icon markers to the regular h1 headings - the modified information will be stored in the db and used for displaying the Reference Information, so modification DOES have an effect:
	else
		information = information:gsub("<h(%d)([^>]*)>(.-)(</h%d>)", function(level, props, heading, closer)
			level = tonumber(level)
			return "<h" .. level .. props .. ">" .. self.wiki_heading_markers[level] .. " " .. heading .. closer
		end)
		self.headings_db = self.headings_db .. table_concat(headings, "\n") .. "\n"
	end

	--* this prop was set in ((InformationMediator#addReferenceInformation))
	local css_files = KOR.informationmediator.css_files
	if has_no_items(css_files) then
		return information
	end

	--* this CSS will be used for Reference Information in HTML-format; see ((ReferenceInformation#show)):
	local css = {}
	count = #css_files
	for i = 1, count do
		table_insert(css, KOR.document:getDocumentFileContent(css_files[i]) .. "\n")
	end
	css = table_concat(css, "\n")
	if not self.current_ebook_reference_information_css then
		self.current_ebook_reference_information_css = css
			:gsub("page%-break%-before: [^;]*;", "")
		return information
	end

	self.current_ebook_reference_information_css = self.current_ebook_reference_information_css .. "\n\n" .. css
		:gsub("page%-break%-before: [^;]*;", "")

	return information
end

--- @private
function ReferenceInformation:prepareWikiContentForSaving(information)
	self:addWikiHeadings(information)

	information = KOR.strings:parasIndent(information)
	--* apply corrections around headings:
	information = information
		:gsub("\n(" .. self.wiki_heading_needle .. "[^\n]+\n) *", "\n\n%1\n\n")
		--* this one is needed for level 3 headings:
		:gsub("\n( " .. self.wiki_heading_needle .. "[^\n]+\n) *", "\n\n%1\n\n")
		--* add an empty line after a level 1 heading:
		:gsub("(" .. self.wiki_heading_markers[1] .. "\n) *", "%1\n")
		--* remove extra markings from level 1 headings (these markings will be kept in the index-item):
		:gsub(" ===", "")
		:gsub("\n\n\n+", "\n\n")

	return information
end

--- @private
function ReferenceInformation:resetProps()
	self.loaded_for_book = nil
	self.current_ebook_reference_information = nil
	self.current_ebook_reference_information_css = nil
	self.headings = nil
	self.headings_db = ""
end

--* items for this XrayInformation were added in ((InformationMediator#addReferenceInformation)):
--* compare ((Glossary#showViewer)):
function ReferenceInformation:show()

	if not self.loaded_for_book or self.loaded_for_book ~= KOR.document.file then
		self:load(KOR.document.file)
		self.loaded_for_book = KOR.document.file
	end

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
	local buttons = DX.b:forReferenceInformationTopLeft(is_tabbed)
	local buttons_right = DX.b:forReferenceInformationTopRight(self)
	local extra_buttons = DX.s.Quizlet_button_enabled and has_items(DX.vd.items) and {
		KOR.buttoninfopopup:forQuizletMode({
			callback = function()
				UIManager:close(self.info_dialog)
				return DX.cb:execQuizletModeCallback()
			end
		})
	}
	local extra_buttons_startpos = 1

	--* compare showing Glossary first and Reference Information in second tab in ((Glossary#showViewer)):
	if is_tabbed then
		self.info_dialog = KOR.dialogs:htmlBoxTabbed(1, {
			title = _("Reference Information + Glossary"),
			extract_texts = true,
			is_reference_information_or_glossary = true,
			css = self.current_ebook_reference_information_css,
			headings = self.headings,
			tabs = {
				-- #((reference info tab names))
				{
					tab = _("reference information"),
					html = self.current_ebook_reference_information,
					content_type = self.current_ebook_reference_information:match("<") and "html" or "text",
					index_enabled = true,
				},
				{
					tab = _("glossary"),
					--* Glossary is saved as plain-text, but shown as HTML:
					content_type = "html",
					html = KOR.glossary:getHtmlList(glossary),
					index_enabled = false,
				},
			},
			top_buttons_left = buttons,
			top_buttons_right = buttons_right,
			no_back_button = true,
			extra_buttons = extra_buttons,
			extra_buttons_startpos = extra_buttons_startpos,
			fullscreen = true,
		})
		return true
	end

	self.info_dialog = KOR.dialogs:textOrHtmlBox({
		title = _("Reference Information"),
		top_buttons_left = buttons,
		top_buttons_right = buttons_right,
		no_back_button = true,
		extra_buttons = extra_buttons,
		extra_buttons_startpos = extra_buttons_startpos,
		fullscreen = true,
		extract_texts = true,
		is_reference_information_or_glossary = true,
		css = self.current_ebook_reference_information_css,
		content = self.current_ebook_reference_information,
		headings = self.headings,
	})
	return true
end

--- @param parent TextViewer|HtmlBox
function ReferenceInformation:generateButtonsIndex(parent, callback)
	local buttons = {}
	local dialog
	local width = Screen:scaleBySize(300)
	local spacer = {{
		 text = " ",
		 bordersize = 0,
		 width = width,
		 align = "left",
		 padding = 0,
		 callback = function() end
	 }}
	local row = 0
	local headings_count = #parent.headings
	--* these headings were generated in ((ReferenceInformation#load)):
	for i = 1, headings_count do
		local heading_label = parent.headings[i]
		if self:isMainHeadingLevel(heading_label) and row ~= 0 then
			table_insert(buttons, spacer)
		end
		row = row + 1
		table_insert(buttons, {{
			text = heading_label,
			bordersize = 0,
			width = width,
			align = "left",
			padding = 0,
			callback = function()
				UIManager:close(dialog)
				local current = i
				local heading = parent.headings[current]
					--* remove prefixed spaced inherited from index-item:
					:gsub("^ +", "")
					--* remove extra markings for level 1 headings, inherited from index-item:
					:gsub(" ===", "")
				callback(heading)
				UIManager:forceRePaint()
			end
		}})
	end

	--* only show this message once during a session:
	if not KOR.registry:get("textviewer_index_message_shown") then
		KOR.messages:notify(_("tap on a heading to jump to it"))
		KOR.registry:set("textviewer_index_message_shown", true)
	end
	dialog = ButtonDialog:new{
		button_width = 1,
		forced_width = width,
		font_weight = "normal",
		padding = 0,
		max_height = Screen:getHeight() - Screen:scaleBySize(70),
		sep_width = 0,
		no_bottom_spacer = true,
		modal = true,
		buttons = buttons,
	}
	UIManager:show(dialog)
end

--- @private
function ReferenceInformation:isMainHeadingLevel(heading)
	for i = 1, 2 do
		if heading:match(self.wiki_heading_markers[i]) then
			return true
		end
	end
	return false
end

return ReferenceInformation
