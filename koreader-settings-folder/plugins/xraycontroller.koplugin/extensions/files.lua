
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template

local io_open = io.open
local lfs_attributes = lfs.attributes

--- @class Files
local Files = WidgetContainer:extend{
    ui = nil,
}

function Files:fileGetContents(path)
    if (not self:exists(path)) then
        KOR.messages:notify(T(_("file %1 does not exist")), path)
        return false
    end

    local file = io_open(path, "r")
    local content = file:read("*all")
    file:close()
    file = nil
    return content
end

function Files:filePutcontents(path, content)
    self:fileSetContents(path, content)
end

function Files:fileSetContents(path, content)
    local target = io_open(path, "wb")
    if target then
        target:write(content)
        target:close()
        target = nil
        return
    end

    KOR.messages:notify(T(_("file %1 does not exist")), path)
end

function Files:openFile(full_path)

    KOR.dialogs:closeAllDialogs()

    if full_path and lfs_attributes(full_path, "mode") == "file" then

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
    return lfs_attributes(full_path) or false
end

return Files
