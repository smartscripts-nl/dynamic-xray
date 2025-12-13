
local require = require

local WidgetContainer = require("ui/widget/container/widgetcontainer")

--* initialization of extensions, plugins etc. below is done through ((ExtensionsInit)), called from reader.lua or the init methods of plugins
--- @class KOR
--- @field buttonchoicepopup ButtonChoicePopup
--- @field buttoninfopopup ButtonInfoPopup
--- @field buttonprops ButtonProps
--- @field buttontablefactory ButtonTableFactory
--- @field colors Colors
--- @field databases Databases
--- @field dialogs Dialogs
--- @field document CreDocument
--- @field filedirnames FileDirNames
--- @field files Files
--- @field html Html
--- @field icons Icons
--- @field labels Labels
--- @field messages Messages
--- @field registry Registry
--- @field screenhelpers ScreenHelpers
--- @field settingsmanager SettingsManager
--- @field strings Strings
--- @field system System
--- @field tabfactory TabFactory
--- @field tabnavigator TabNavigator
--- @field tables Tables
--- @field xraybuttons XrayButtons
--- @field xraycontroller XrayController
--- @field xraydialogs XrayDialogs
--- @field xraymodel XrayModel
--- @field xraysettings XraySettings
--- @field xrayui XrayUI
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

	--* EXTENSIONS THROUGH ((ExtensionsInit)), called from ((reader.lua))

	buttonprops = nil,
	buttontablefactory = nil,
	buttonchoicepopup = nil,
	clipboard = nil,
	colors = nil,
	databases = nil,
	dialogs = nil,
	filedirnames = nil,
	files = nil,
	html = nil,
	icons = nil,
	buttoninfopopup = nil,
	labels = nil,
	messages = nil,
	registry = nil,
	screenhelpers = nil,
	settingsmanager = nil,
	statisticshelpers = nil,
	strings = nil,
	system = nil,
	tabfactory = nil,
	tabnavigator = nil,
	tables = nil,
	xraybuttons = nil,
	--* xraycontroller farther below, in plugins list...
	xraydialogs = nil,
	xraymodel = nil,
	xraysettings = nil,
	xrayui = nil,

	--- PLUGINS

	--! register extensions which are also loaded as plugin (in folder extensions/plugins) as such, so not as extension;
	readersearch = nil,
	xraycontroller = nil,

	extensions_list = {
		--! this first block contains extensions which are needed by other extensions and therefor must be initialized first:
		"databases",
		"dialogs",
		"files",
		"tables",

		"buttonprops",
		"buttontablefactory",
		"buttonchoicepopup",
		"buttoninfopopup",
		"filedirnames",
		"html",
		"labels",
		"messages",
		"screenhelpers",
		"strings",
		"system",
		"tabfactory",
		"tabnavigator",
		"xraybuttons",
		"xraydialogs",
		"xraymodel",
		"xrayui",
	},
}

function KOR:initBaseExtensions()
	self.registry = require("extensions/registry")
end

function KOR:initEarlyExtensions()
	KOR.colors = require("extensions/colors")
	KOR.icons = require("extensions/icons")
	KOR.settingsmanager = require("extensions/settingsmanager")
	KOR.xraysettings = require("extensions/xraysettings")
	KOR.xraysettings:setUp()
	DX.s = KOR.xraysettings
end

function KOR:initExtensions()
	--! if you want to have support for self.ui when using these extensions as a module somewhere, load them not via require, but refence their methods like so: KOR.extension_name:method() ...
	local name, extension, instance
	local count = #self.extensions_list
	for i = 1, count do
		name = self.extensions_list[i]
		if not self[name] then
			--* PageJumper will later on be initialized as plugin:
			if name == "pagejumper" then
				extension = require("extensions/plugins/" .. name)
			else
				extension = name ~= "readcollection" and
				require("extensions/" .. name)
				or
				require("frontend/" .. name)
			end
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

--* see ((SYNTACTIC SUGAR)):
function KOR:registerXrayModules()
	--* XrayController will register itself to DX from ((XrayController#init)):
	local DX = DX

	DX.b = KOR.xraybuttons
	DX.d = KOR.xraydialogs
	DX.m = KOR.xraymodel
	DX.u = KOR.xrayui
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

function KOR:registerModule(KOR_name, plugin)
	self[KOR_name] = plugin
end

function KOR:registerPlugin(KOR_name, plugin)
	self[KOR_name] = plugin
end

function KOR:registerWidget(KOR_name, widget)
	self[KOR_name] = widget
end

function KOR:initCustomTranslations()
	local translator = require("extensions/translations/getmoduletext")

	local file = KOR.registry:get("module_translations_source", function()
		local lfs = require("libs/libkoreader-lfs")
		return lfs.currentdir() .. "/frontend/extensions/translations/xray-translations.po"
	end)
	file = file:gsub("koreader.po", "xray-translations.po")
	translator.openTranslationsSource(file)

	return translator
end

return KOR
