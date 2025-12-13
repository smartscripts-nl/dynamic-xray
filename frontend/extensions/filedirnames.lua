
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local G_reader_settings = G_reader_settings

--- @class FileDirNames
local FileDirNames = WidgetContainer:extend{}

function FileDirNames:basename(file, options)
    file = file:gsub("^.+/", "")
    if options and options.remove_extension then
        file = self:removeExtension(file)
    end
    if options and options.remove_authors then
        file = file:gsub("^.+ %- ", "")
    end
    if options and options.lower_case then
        file = KOR.strings:lower(file)
    end
    return file
end

--* only keep relative path, below home dir or even below _Finished, if file resides there:
function FileDirNames:getPathIndex(path)
    return path:gsub("[/.]", "_")
end

function FileDirNames:getRootPathIndex(path)
    local parent_path = G_reader_settings:readSetting("home_dir") .. "/"
    return path
        :gsub(parent_path, "")
        :gsub("[/.]", "_")
end

function FileDirNames:removeExtension(file)
    return file:gsub("%.[a-zA-Z0-9]+ ?$", "")
end

return FileDirNames
