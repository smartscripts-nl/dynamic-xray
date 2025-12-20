--[[--
This extension is part of the Dynamic Xray plugin; it initializes translations for all view related modules. The translations are stored in the database.

New translations encountered in the code will be automatically/lazily added to the database.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XrayTranslations)), ((XrayTappedWords)) and ((XrayViewsData)), ((XrayTranslations))
V = ((XrayUI)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local md5 = require("ffi/sha2").md5

local DX = DX

local count

--- @class XrayTranslations
local XrayTranslations = WidgetContainer:new{
    translations = nil,
}

function XrayTranslations:loadAllTranslations()
    self.translations = {}
    local conn = KOR.databases:getDBconnForBookInfo("XrayTranslations:load")
    local sql = "SELECT msgid, msgstr, md5 FROM xray_translations"
    local result = conn:exec(sql)
    conn = KOR.databases:closeInfoConnections(conn)

    if result then
        count = #result["msgid"]
        local index
        for i = 1, count do
            index = md5(result["msgid"][i])
            self.translations[index] = {
                msgid = result["msgid"][i],
                msgstr = result["msgstr"][i],
            }
        end
    end
    KOR.registry:set("database_translations_available", true)
end

function XrayTranslations.get(key)
    local self = DX.t
    if not self.translations then
        self:loadAllTranslations()
    end
    local index = md5(key)
    local translation = self.translations[index]
    if translation then
        return translation.msgstr
    end

    --* new entry, so store in database:
    local conn = KOR.databases:getDBconnForBookInfo("XrayTranslations:load")
    local sql = "INSERT OR IGNORE INTO xray_translations(msgid, msgstr, md5) VALUES(?, ?, ?)"
    local stmt = conn:prepare(sql)
    local db_key = KOR.databases:escape(key)
    --* untranslated as yet, so msgstr field is equal to msgid:
    stmt:reset():bind(db_key, db_key, index):step()
    conn, stmt = KOR.databases:closeConnAndStmt(conn, stmt)
    self.translations[index] = {
        msgid = key,
        msgstr = key,
    }

    return key
end

return XrayTranslations
