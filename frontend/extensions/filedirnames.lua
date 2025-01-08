
local Strings = require("extensions/strings")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class FileDirNames
local FileDirNames = WidgetContainer:extend{}

function FileDirNames:basename(file, options)
    file = file:gsub("^.+/", "")
    if options and options.remove_extension then
        file = self:removeExtension(file)
    end
    if options and options.lower_case then
        file = Strings:lower(file)
    end
    return file
end

function FileDirNames:removeExtension(file)
    return file:gsub("%.[a-zA-Z0-9]+$", "")
end

return FileDirNames
