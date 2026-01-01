--[[--
This extension is part of the Dynamic Xray plugin; it initializes translations for all view related modules. The translations are stored in the database.

New translations encountered in the code will be automatically/lazily added to the database.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayPageNavigator)), ((XrayTranslations)) and ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
--local logger = require("logger")
local md5 = require("ffi/sha2").md5
local T = require("ffi/util").template

local DX = DX
local table = table

local count

--* instantiated in ((XrayModel#initDataHandlers)):
--- @class XrayTranslations
local XrayTranslations = WidgetContainer:new{
    prune_orphan_translations = " msgid LIKE '%1 person' OR msgid LIKE '%1 important%' OR msgid LIKE '%1 term'",
    prune_orphan_translations_version = 2,
    translated_indicator = "✓",
    translations = nil,
    translation_separator = "\n\n_________________________\n\n",
    translation_separator_viewer = "   " .. KOR.icons.arrow_bare .. "   ",
    translations_for_manager = nil,
}

--- @private
function XrayTranslations:pruneOrphanTranslations()
    DX.ds:runExternalStmt("XrayTranslations:pruneOrphanTranslations", "prune_orphan_translations", self.prune_orphan_translations)
end

function XrayTranslations:loadAllTranslations()
    self.translations = {}
    self.translations_for_manager = {}
    local result = DX.dl:execExternalQuery("XrayTranslations:loadAllTranslations", "get_all_translations")
    if result then
        count = #result["msgid"]
        for i = 1, count do
            self:generateItemForDataTables({
                msgid = KOR.databases:unescape(result["msgid"][i]),
                msgstr = KOR.databases:unescape(result["msgstr"][i]),
                is_translated = result["is_translated"][i],
                md5 = result["md5"][i],
            }, i)
        end
    end
    DX.tm:setTranslations(self.translations_for_manager)
end

--* compare ((XrayTranslations#generateItemForManagerList)), called for generating items for display in list in ((XrayTranslationsManager#updateTranslationsTable)):
--- @private
function XrayTranslations:generateItemForDataTables(translation, translations_nr)
    local msgid = translation.msgid
    local msgstr = translation.msgstr
    translation.msgid_v = msgid:gsub("^ +", "")
    translation.msgstr_v = msgstr:gsub("^ +", "")
    local index = md5(msgid)
    self.translations[index] = {
        msgid = msgid,
        msgstr = msgstr,
    }
    self:generateItemTexts(translation)
    table.insert(self.translations_for_manager, {
        text = translation.text,
        viewer_text = translation.viewer_text,
        heading = msgid:len() < 100 and msgid,
        msgid = msgid,
        msgstr = msgstr,
        --* needed to find the right item to update:
        md5 = translation.md5,
        --* this prop handy for marking translated entries with a checkmark in ((XrayTranslationsManager)):
        is_translated = translation.is_translated,
        translation_nr = translations_nr,
    })
end

--* compare ((XrayTranslations#generateItemForDataTables)):
function XrayTranslations:generateItemForManagerList(item, nr)
    return {
        text_func = function()
            return KOR.strings:formatListItemNumber(nr, item.text)
        end,
        text = item.text,
        viewer_text = item.viewer_text,
        heading = item.heading,
        bold = item.is_translated == 1,
        msgid = item.msgid,
        msgstr = item.msgstr,
        msgid_v = item.msgid_v,
        msgstr_v = item.msgstr,
        is_translated = item.is_translated,
        translation_nr = item.translation_nr,
        md5 = item.md5,
    }
end

--- @private
function XrayTranslations:generateItemTexts(translation)
    local translated_indicator = translation.is_translated == 1 and self.translated_indicator .. " " or ""
    local template = "%1%2%3%4"

    if not translation.msgid_v then
        translation.msgid_v = translation.msgid:gsub("^ +", "", 1)
    end
    if not translation.msgstr_v then
        translation.msgstr_v = translation.msgstr:gsub("^ +", "", 1)
    end

    translation.text = T(template, translated_indicator, translation.msgid_v, self.translation_separator_viewer, translation.msgstr_v)

    translation.viewer_text = T(template, translated_indicator, translation.msgid_v, self.translation_separator, translation.msgstr_v)
end

-- #((XrayTranslations#get))
function XrayTranslations.get(key)
    --logger.warn(tostring(key))
    local self = DX.t
    if not self.translations then
        self:pruneOrphanTranslations()
        self:loadAllTranslations()
    end
    local index = md5(key)
    local translation = self.translations[index]
    if translation then
        return translation.msgstr
    end
    --* new entry, so store in database:
    --* untranslated as yet, so msgstr field is equal to msgid, hence 2 times key:
    DX.ds:runExternalStmt("XrayTranslations.get", "add_translation_item", { key, key, index })
    self:generateItemForDataTables({
        msgid = key,
        msgstr = key,
        is_translated = 0,
        md5 = index,
    }, 1)

    KOR.tables:sortByPropAscending(self.translations_for_manager, "msgid")
    count = #self.translations_for_manager
    for i = 1, count do
        self.translations_for_manager[i].translation_nr = i
    end

    DX.tm:setTranslations(self.translations_for_manager)
    return key
end

--- @private
function XrayTranslations:reAttachWhiteSpace(item, updated_translation)
    --* make sure whitespace at start and end of original translation is re-attached exactly the same:
    local prefix = item.msgid:match("^ ")
    if prefix then
        updated_translation = updated_translation:gsub("^ +", prefix, 1)
    end
    local suffix = item.msgid:match(" $")
    if suffix then
        updated_translation = updated_translation:gsub(" +$", suffix, 1)
    end
    return updated_translation
end

--* called from ((XrayTranslationsManager#saveUpdatedTranslation)):
function XrayTranslations:updateTranslation(item, translation)
    count = #self.translations_for_manager
    local t_item
    for i = 1, count do
        t_item = self.translations_for_manager[i]
        if t_item.md5 == item.md5 then

            translation = self:reAttachWhiteSpace(item, translation)
            t_item.msgstr = translation
            t_item.is_translated = 1
            self:generateItemTexts(t_item)
            self.translations[item.md5] = t_item

            DX.ds:runExternalStmt("XrayTranslations:save", "update_translation", { translation, item.md5 })

            return t_item, self.translations_for_manager
        end
    end
end

return XrayTranslations
