
local require = require

local DocSettings = require("docsettings")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local has_no_text = has_no_text

--- @class Sidecar
local Sidecar = WidgetContainer:extend{}

--* get a set of sidecar file settings
--* format of ...: key1, key2, etc.
--* table returned: { key1 = value1, key2 = value 2}, etc.:
--[[
Example:
local filesettings = Sidecar:get(path, "embedded_fonts", "font_face")
if filesettings and filesettings.embedded_fonts then
    font_face = "Souvenir Lt BT / ingesloten font"
else
    ...
end
]]
function Sidecar:get(full_path, ...)
    if has_no_text(full_path) or not DocSettings:hasSidecarFile(full_path) then
        return
    end
    local docsettings = DocSettings:open(full_path)
    if not docsettings then
        return
    end

    local result = {}
    local props = { ... }
    local prop, val
    local count = #props
    for i = 1, count do
        prop = props[i]
        val = docsettings:readSetting(prop)
        result[prop] = val
    end
    return result
end

return Sidecar
