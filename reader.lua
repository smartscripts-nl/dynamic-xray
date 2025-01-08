#!./luajit

-- Enforce line-buffering for stdout (this is the default if it points to a tty, but we redirect to a file on most platforms).
io.stdout:setvbuf("line")
-- Enforce a reliable locale for numerical representations
os.setlocale("C", "numeric")

io.write([[
---------------------------------------------
                launching...
  _  _____  ____                _
 | |/ / _ \|  _ \ ___  __ _  __| | ___ _ __
 | ' / | | | |_) / _ \/ _` |/ _` |/ _ \ '__|
 | . \ |_| |  _ <  __/ (_| | (_| |  __/ |
 |_|\_\___/|_| \_\___|\__,_|\__,_|\___|_|

 It's a scroll... It's a codex... It's KOReader!

 [*] Current time: ]], os.date("%x-%X"), "\n")

-- Set up Lua and ffi search paths
require("setupkoenv")
local util = require("util")

-- #((reader.lua modification block 1))
-- ============= MODIFICATION 1/2 =============
local extensions = {}
-- call with extension("extension_name") or extension("plugins/extension_name")
-- example: return extension('extensionb'):getMenuText()
function extension(name)
    local index = name
    if name:match("/") then
        index = name:gsub("/", "")
    end
    if extensions[index] then
        return extensions[index]
    end
    if name ~= "readcollection" then
        name = "extensions/" .. name
    end
    extensions[index] = require(name)

    return extensions[index]
end

-- =============== END MODIFICATION 1/2 ==============


-- [...]

-- Inform once about color rendering on newly supported devices
-- (there are some android devices that may not have a color screen,
-- and we are not (yet?) able to guess that fact)
if Device:hasColorScreen() and not G_reader_settings:has("color_rendering") then
    -- [...]
end


--- @class Reader
-- #((reader.lua modification block 2))
-- ================= MODIFICATION 2/2 =================
-- =============== EXTRA READER MODULES ===============

-- this global var will be used as container for values in registry.lua:
AX_registry = {
    day_cache = {},
    hour_cache = {},
}
local Registry = require("extensions/registry")
Registry:set("is_koreader_start", true)
-- SmartScripts: here we populate Registry.ereader_model
-- #((store ereader model))
Registry:get("ereader_model")

-- returns the text if set, or boolean true if text is not empty and return_boolean == true:
function has_content(var, return_boolean)
    local return_value = return_boolean and true or var
    return var and var ~= "" and return_value or nil
end
function has_text(var, return_boolean)
    local return_value = return_boolean and true or var
    if var == "" then
        return nil
    end
    if var then
        var = util.htmlEntitiesToUtf8(var)
    end
    return var and var:match("[%-A-Za-z0-9ÄËÏÖÜäëïöáéíóúàèìòùÀÈÌÒÙÁÉÍÓÚ]") and return_value or nil
end

-- ================ END MODIFICATION 2/2 ===============

-- Conversely, if color is enabled on a Grayscale screen (e.g., after importing settings from a color device), warn that it'll break stuff and adversely affect performance.

-- [...]

-- Apply exit user patches and execute user scripts
userpatch.applyPatches(userpatch.on_exit)

-- Close the Lua state on exit
os.exit(reader_retval, true)
