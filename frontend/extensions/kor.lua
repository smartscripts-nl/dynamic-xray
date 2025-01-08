
local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- initialization of extensions, plugins etc. below is done through ((ReaderUI#registerExtensions)) or the init methods of plugins
-- see ((EXTENSIONS: CALLING VIA KOR)) for more info
--- @class KOR
--- @field annotation ReaderAnnotation
--- @field bookmark ReaderBookmark
--- @field dialogs Dialogs
--- @field doc_settings DocSettings
--- @field doc_lua_settings LuaSettings
--- @field document CreDocument
--- @field filedirnames FileDirNames
--- @field highlight ReaderHighlight
--- @field history FileManagerHistory
--- @field link ReaderLink
--- @field screenhelpers ScreenHelpers
--- @field status ReaderStatus
--- @field thumbnail ReaderThumbnail
--- @field toc ReaderToc
--- @field view ReaderView
--- @field xrayitems XrayItems
--- @field xrayhelpers XrayHelpers
local KOR = WidgetContainer:new{

	--- NATIVE KOREADER UI MODULES

	-- UI modules are defined by KOReader in ((ReaderUI#init))
	-- registered with ((XrayItems#init)) or ((ReaderHighlight#onReaderReady)) > KOR:registerUImodules(self.ui) > ((KOR#registerUImodules)):
	annotation = nil,
	bookmark = nil,
	doc_settings = nil,
	document = nil,
	highlight = nil,
	history = nil,
	link = nil,
	status = nil,
	thumbnail = nil,
	toc = nil,
	view = nil,

	--- EXTENSIONS REGISTERED THROUGH READERUI

	-- registered through ((ReaderUI#registerExtensions)):
	dialogs = nil,
	filedirnames = nil,
	screenhelpers = nil,
	xrayhelpers = nil,

	--- PLUGINS

	-- registered from their init methods; e.g. ((XrayItems#init)) > KOR:registerPlugin("xrayitems", self) > ((KOR#registerPlugin)):
	-- ! register extensions which are also loaded as plugin (in folder extensions/plugins) as such, so not as extension:
	xrayitems = nil,

	-- tells ((ReaderUI)) which extensions to load:
	extensions_list = {
		"dialogs",
		"filedirnames",
		"screenhelpers",
		"xrayhelpers",
	},

	--- FOR DEBUGGING

	extensions_without_constructor = {},
}

-- registered with ((XrayItems#init)) or ((ReaderHighlight#onReaderReady)) > KOR:registerUImodules(self.ui) > ((KOR#registerUImodules)):
function KOR:registerUImodules(ui)
	self.annotation = ui.annotation
	self.bookmark = ui.bookmark
	self.doc_settings = ui.doc_settings
	-- overloaded by DocSettings:
	self.doc_lua_settings = ui.doc_settings
	-- different from self.view.document, e.g. for determining self.view.document.file:
	self.document = ui.document
	self.highlight = ui.highlight
	self.history = ui.history
	self.link = ui.link
	self.status = ui.status
	self.thumbnail = ui.thumbnail
	self.toc = ui.toc
	self.view = ui.view
end

function KOR:registerPlugin(KOR_name, plugin)
	self[KOR_name] = plugin
end

return KOR
