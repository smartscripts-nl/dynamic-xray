
local require = require

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local G_reader_settings = G_reader_settings
local tostring = tostring
local type = type

--* use global vars to quickly run built-in lua methods:
io_open = io.open
io_popen = io.popen
lfs_attributes = lfs.attributes
lfs_currentdir = lfs.currentdir
lfs_dir = lfs.dir
lfs_mkdir = lfs.mkdir
lfs_rmdir = lfs.rmdir
logger_err = logger.err
logger_info = logger.info
logger_warn = logger.warn
math_abs = math.abs
math_ceil = math.ceil
math_floor = math.floor
math_huge = math.huge
math_max = math.max
math_min = math.min
math_random = math.random
os_date = os.date
os_difftime = os.difftime
os_execute = os.execute
os_exit = os.exit
os_remove = os.remove
os_rename = os.rename
os_time = os.time
string_byte = string.byte
string_char = string.char
string_find = string.find
string_format = string.format
string_gmatch = string.gmatch
string_lower = string.lower
string_rep = string.rep
string_sub = string.sub
--* make T globally available:
T = require("ffi/util").template
table_concat = table.concat
table_insert = table.insert
table_move = table.move
table_pack = table.pack
table_remove = table.remove
table_sort = table.sort
util_gsplit = util.gsplit
util_trim = util.trim

--- @class HelperFunctions
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
    if table_or_count == nil then
        return false
    end
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
