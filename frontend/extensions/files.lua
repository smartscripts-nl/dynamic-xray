
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

--- @class Files
local Files = WidgetContainer:extend{
    ui = nil,
}

function Files:openFile(full_path)

    KOR.dialogs:closeAllDialogs()

    if full_path and lfs.attributes(full_path, "mode") == "file" then

        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(full_path)
        return true
    end
    return false
end

function Files:exists(full_path)
    if not (full_path) then
        return false
    end
    return lfs.attributes(full_path) or false
end

return Files
