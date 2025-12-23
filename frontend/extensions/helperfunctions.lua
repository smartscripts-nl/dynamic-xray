
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
