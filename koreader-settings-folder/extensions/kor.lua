
local require = require

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local pairs = pairs

--* initialization of extensions, plugins etc. below is done through ((ExtensionsInit)), called from reader.lua or the init methods of plugins
--- @class KOR
--- @field anchorbutton AnchorButton
--- @field bookinfomanager BookInfoManager
--- @field buttonchoicepopup ButtonChoicePopup
--- @field buttoninfopopup ButtonInfoPopup
--- @field buttonprops ButtonProps
--- @field buttontablefactory ButtonTableFactory
--- @field colors Colors
--- @field databases Databases
--- @field dialogs Dialogs
--- @field document CreDocument
--- @field ebookmetadata EbookMetadata
--- @field filedirnames FileDirNames
--- @field files Files
--- @field html Html
--- @field icons Icons
--- @field keyevents KeyEvents
--- @field labels Labels
--- @field list List
--- @field messages Messages
--- @field registry Registry
--- @field screenhelpers ScreenHelpers
--- @field seriesmanager SeriesManager
--- @field settingsmanager SettingsManager
--- @field sidecar Sidecar
--- @field statisticshelpers StatisticsHelpers
--- @field strings Strings
--- @field system System
--- @field tabbedlist TabbedList
--- @field tabfactory TabFactory
--- @field tabnavigator TabNavigator
--- @field tables Tables
local KOR = WidgetContainer:new{

	--- NATIVE KOREADER UI MODULES

	bookmark = nil,
	dictionary = nil,
	doc_settings = nil,
	document = nil,
	filemanagercollection = nil,
	footer = nil,
	highlight = nil,
	history = nil,
	link = nil,
	rolling = nil,
	pagemap = nil,
	paging = nil,
	status = nil,
	thumbnail = nil,
	toc = nil,
	ui = nil,
	uimanager = nil,
	view = nil,

	--* EXTENSIONS THROUGH ((ExtensionsInit)):

	anchorbutton = nil,
	bookinfomanager = nil,
	buttonprops = nil,
	buttontablefactory = nil,
	buttonchoicepopup = nil,
	buttoninfopopup = nil,
	clipboard = nil,
	colors = nil,
	dialogs = nil,
	ebookmetadata = nil,
	filedirnames = nil,
	files = nil,
	html = nil,
	icons = nil,
	keyevents = nil,
	labels = nil,
	list = nil,
	messages = nil,
	registry = nil,
	screenhelpers = nil,
	seriesmanager = nil,
	settingsmanager = nil,
	sidecar = nil,
	statisticshelpers = nil,
	strings = nil,
	system = nil,
	tabbedlist = nil,
	tabfactory = nil,
	tabnavigator = nil,
	tables = nil,

	--- PLUGINS

	--! register extensions which are also loaded as plugin (in folder extensions/plugins) as such, so not as extension;
	readersearch = nil,

	extensions_list = {
		--! this first block contains extensions which are needed by other extensions and therefor must be initialized first:
		"dialogs",
		"files",
		"tables",
		"keyevents",

		"anchorbutton",
		"bookinfomanager",
		"buttonprops",
		"buttontablefactory",
		"buttonchoicepopup",
		"buttoninfopopup",
		"ebookmetadata",
		"filedirnames",
		"html",
		"labels",
		"list",
		"messages",
		"screenhelpers",
		"seriesmanager",
		"sidecar",
		"statisticshelpers",
		"strings",
		"system",
		"tabfactory",
		"tabnavigator",
	},

	translations_source = nil,
}

--* see ((SYNTACTIC SUGAR)):
function KOR:initDX()
	local DX = DX

	DX.s = require("extensions/xraymodel/xraysettings")
	DX.s:setUp()
	DX.m = require("extensions/xraymodel/xraymodel")
	--* only for repository version set database_filename (so DON'T set this var yourself!):
	if DX.m:isPublicDXversion() then
		DX.m:setDatabaseFile()
	end
	--* if we would use this and consequently would reference DX.c.model instead of DX.m in the other DX modules, data would be reloaded from database onReaderReady for each new book:
	DX.m:initDataHandlers()

	local modules = {
		b = "extensions/xrayviews/xraybuttons",
		cb = "extensions/xrayviews/xraycallbacks",
		d = "extensions/xrayviews/xraydialogs",
		i = "extensions/xrayviews/xrayinformation",
		ip = "extensions/xrayviews/xrayinfopanel",
		p = "extensions/xrayviews/xraypages",
		sp = "extensions/xrayviews/xraysidepanels",
		u = "extensions/xrayviews/xrayui",
	}
	for key, module in pairs(modules) do
		DX[key] = require(module)
	end
	if DX.m:isPublicDXversion() then
		DX.tm = require("extensions/xrayviews/xraytranslationsmanager")
	end
end

function KOR:initBaseExtensions()
	self.registry = require("extensions/registry")
end

function KOR:initEarlyExtensions()
	KOR.colors = require("extensions/colors")
	KOR.databases = require("extensions/databases")
	KOR.icons = require("extensions/icons")
	KOR.tabbedlist = require("extensions/tabbedlist")
	KOR.settingsmanager = require("extensions/settingsmanager")
end

function KOR:initExtensions()
	--! if you want to have support for self.ui when using these extensions as a module somewhere, load them not via require, but refence their methods like so: KOR.extension_name:method() ...
	local name, extension, instance
	local count = #self.extensions_list
	for i = 1, count do
		name = self.extensions_list[i]
		if not self[name] then
			extension = name ~= "readcollection" and
			require("extensions/" .. name)
			or
			require("frontend/" .. name)
			if extension.new then
				instance = extension:new{}
			else
				instance = extension
			end
			instance.name = "reader" .. name
			KOR[name] = instance

			if instance.init then
				instance:init()
			end
		end
	end
end

function KOR:registerUI(ui)
	self.bookmark = ui.bookmark
	self.doc_settings = ui.doc_settings
	--* overloaded by DocSettings:
	self.doc_lua_settings = ui.doc_settings
	--* different from self.view.document, e.g. for determining self.view.document.file:
	self.document = ui.document
	self.highlight = ui.highlight
	self.history = ui.history
	self.link = ui.link
	self.pagemap = ui.pagemap
	--! only initiated when opening pdfs etc.:
	self.paging = ui.paging
	--! only initiated when opening epubs etc.:
	self.rolling = ui.rolling
	self.status = ui.status
	self.thumbnail = ui.thumbnail
	self.toc = ui.toc
	self.ui = ui
	self.view = ui.view
end

function KOR:registerModule(KOR_name, module)
	self[KOR_name] = module
end

function KOR:registerPlugin(KOR_name, plugin)
	self[KOR_name] = plugin
end

function KOR:registerWidget(KOR_name, widget)
	self[KOR_name] = widget
end

function KOR:initCustomTranslations()
	return self.getTranslation
end

--* this method is made available for outside modules by ((KOR#initCustomTranslations)), in a call like this:
--* local _ = KOR:initCustomTranslations()
--- @private
function KOR.getTranslation(key)
	local DX = DX
	--* this prop will only be set in ((XrayTranslations#loadAllTranslations)):
	if not DX.t then
		--* if DX.t not initialized yet, return simply the key as "translation":
		return key
	end

	--* in this method the translations will be instantiated, if that hasn't happened yet:
	return DX.t.get(key)
end

return KOR
