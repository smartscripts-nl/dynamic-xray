
--* compare ((Glossary)); glossary there is stored in the ebook sidecar file, but here reference information is stored in the database

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_no_items = has_no_items

--- @class ReferenceInformation
local ReferenceInformation = WidgetContainer:extend{
	current_ebook_reference_information = nil,
	db_path = nil,
	db_field = "reference_information",
	--* viewer_instance will be registered to InformationCollector.viewer_instance ...
}

--* called from ((XrayController#onReaderReady)):
function ReferenceInformation:load(full_path)
	self.db_path = full_path
	local sql = KOR.databases:injectSafePath("SELECT " .. self.db_field .. " FROM bookinfo WHERE directory || filename = 'safe_path';", self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:load")
	local information = conn:rowexec(sql)
	conn = KOR.databases:closeConnections(conn)
	self.current_ebook_reference_information = information
end

--* compare for erasing Glossary ((Glossary#erase)):
function ReferenceInformation:erase()
	local sql = KOR.databases:injectSafePath("UPDATE bookinfo SET " .. self.db_field .. " = NULL WHERE directory || filename = 'safe_path';", self.db_path)
	local conn = KOR.databases:getDBconn("ReferenceInformation:erase")
	conn:exec(sql)
	conn = KOR.databases:closeConnections(conn)
	self.current_ebook_reference_information = nil

	KOR.informationcollector:closeViewer()
	KOR.messages:notify(_("reference information erased"))
end

function ReferenceInformation:storeInformation(information, content_type, css_files)
	KOR.informationcollector:closeContentTypeChoiceDialog()
	if content_type == "html" then
		information = self:prepareHtml(information, css_files)
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
	self:store(information)
	self.current_ebook_reference_information = information
	self:show(information)
end

--- @private
function ReferenceInformation:store(information)
	local conn = KOR.databases:getDBconn("ReferenceInformation.store")
	local stmt = conn:prepare("UPDATE bookinfo SET " .. self.db_field .. " = ? WHERE filename = ?;")
	stmt:reset():bind(information, DX.m.current_ebook_basename):step()
	conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
end

--- @private
function ReferenceInformation:prepareHtml(information, css_files)
	local remove = { "DocFragment", "body", "section", "a", "inlineBox", "autoBoxing" }
	for i = 1, #remove do
		information = information
			:gsub("</" .. remove[i] .. ">", "")
			:gsub("<" .. remove[i] .. "[^>]*>", "")
	end
	information = "<html><body>" .. information .. "</body></html>"
	if has_no_items(css_files) then
		return information
	end

	local css = ""
	for i = 1, #css_files do
		css = css .. KOR.document:getDocumentFileContent(css_files[i]) .. "\n"
	end
	css = css:gsub("page%-break%-before: always[^;]*;", "")
	css = css .. [[
h1, h2, h3, h4, h5, h6 {
    margin-top: 1.5em !important;
}
]]
	return "<style>" .. css .. "</style>\n" .. information
end

--* items for this XrayInformation were added in ((InformationCollector#addReferenceInformation)):
--* compare ((Glossary#showViewer)):
function ReferenceInformation:show()
	local glossary = KOR.glossary:get()
	if not self.current_ebook_reference_information then
		if glossary then
			--* show Glossary instead of missing Reference Information:
			KOR.glossary:showViewer()
			return true
		end
		return KOR.informationcollector:confirmAddInformationFromScratch("reference_information")
	end

	local information = self.current_ebook_reference_information

	local css = information:match("<style>([^>]+)</style>")
	if css then
		information = information:gsub("^.+</style>", "", 1)
	end

	local is_tabbed = glossary
	local buttons = DX.b:forReferenceInfoTopLeft(self, is_tabbed)

	--* compare showing Glossary first and Reference Information in second tab in ((Glossary#showViewer)):
	if is_tabbed then
		KOR.informationcollector.viewer_instance = KOR.dialogs:htmlBoxTabbed(1, {
			title = _("Reference Information + Glossary"),
			tabs = {
				{
					tab = _("reference information"),
					html = information,
					content_type = information:match("<") and "html" or "text",
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

	KOR.informationcollector.viewer_instance = KOR.dialogs:textOrHtmlBox({
		title = _("Reference Information"),
		top_buttons_left = buttons,
		fullscreen = true,
		css = css,
		content = information,
	})
	return true
end

return ReferenceInformation
