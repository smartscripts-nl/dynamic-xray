-- luacheck: ignore

--- @class KORinit

local require = require

local util = require("util")

local G_reader_settings = G_reader_settings
local tostring = tostring
local type = type

--* this global var will be used as container for values in registry.lua:
AX_registry = {
    day_cache = {},
    hour_cache = {},
}

--* renewable registry, to be reset upon addition of new files etc.:
AXR_registry = {}

local KOR = require("extensions/kor")
KOR:initBaseExtensions()

-- #((initialize Xray modules))
--* helper class for shortened notation for Dynamic Xray modules; DX.b, DX.d (but indices DX.xraybuttons, DX.xraydialogs etc. are NOT available, because the very short notation is the point of table DX) instead of KOR.xraybuttons, KOR.xraydialogs etc.; will be populated from ((KOR#registerXrayModules)), ((XrayModel#initDataHandlers)) and ((XrayController#init)):
--- @class DX
--- @field b XrayButtons
--- @field c XrayController
--- @field d XrayDialogs
--- @field dl XrayDataLoader
--- @field ds XrayDataSaver
--- @field fd XrayFormsData
--- @field m XrayModel
--- @field s XraySettings
--- @field t XrayTranslations
--- @field tw XrayTappedWords
--- @field vd XrayViewsData
--- @field u XrayUI
DX = {
    --* shorthand notation for Buttons:
    b = nil,
    --* shorthand notation for Controller:
    c = nil,
    --* shorthand notation for Dialogs:
    d = nil,
    --* shorthand notation for DataLoader; this module will be initialized in ((XrayModel#initDataHandlers)):
    dl = nil,
    --* shorthand notation for DataStore; this module will be initialized in ((XrayModel#initDataHandlers)):
    ds = nil,
    --* shorthand notation for FormsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    fd = nil,
    --* shorthand notation for Model:
    m = nil,
    --* shorthand notation for Settings:
    s = nil,
    --* shorthand notation for TappedWords; this module will be initialized in ((XrayModel#initDataHandlers)):
    t = nil,
    --* shorthand notation for Translations; this module will be initialized in ((XrayModel#initDataHandlers)):
    tw = nil,
    --* shorthand notation for ViewsData; this module will be initialized in ((XrayModel#initDataHandlers)):
    vd = nil,
    --* shorthand notation for UI:
    u = nil,
}
function DX.setProp(name, value)
    DX[name] = value
end
function DX:registerController(controller)
    self.c = controller
end

--* returns the text if set, or boolean true if text is not empty and return_boolean == true:
function has_content(var, return_boolean)
    local return_value = return_boolean and true or var
    return var and var ~= "" and return_value
end

function has_no_content(var)
    return not var or var == ""
end

function has_text(var, return_boolean)
    local vtype = type(var)
    if vtype == "cdata" then
        return has_content(var, return_boolean)
    end
    if vtype ~= "string" or var == "" then
        return nil
    end
    if vtype == "number" then
        return return_boolean and true or tostring(var)
    end

    local return_value = return_boolean and true or var
    var = util.htmlEntitiesToUtf8(var)
    return var:match("[%-A-Za-z0-9ÄËÏÖÜäëïöáéíóúàèìòùÀÈÌÒÙÁÉÍÓÚÇçß]") and return_value
    --return var and var:match("%S") and not var:match("^%s*$") and return_value
end

function has_no_text(var)
    local itype = type(var)
    if itype == "cdata" or itype == "boolean" or var == nil then
        return true
    end
    var = tostring(var)
    return not has_text(var)
end

function has_items(table_or_count)
    if type(table_or_count) == "number" and table_or_count > 0 then
        return true
    end
    return type(table_or_count) == "table" and #table_or_count > 0 or false
end

function has_no_items(table_or_count)
    return not has_items(table_or_count)
end

function get_count(t)
    return type(t) == "table" and #t or 0
end

function last_file()
    return G_reader_settings:readSetting("lastfile")
end

--! Watch out: extensions which are loaded here MUST also be typed in ((KOR)) and have a @class declaration themselves, to have them available for code hinting!

--- @class ExtensionsInit
KOR:initEarlyExtensions()
KOR:initExtensions()
KOR:registerXrayModules()

return KOR
