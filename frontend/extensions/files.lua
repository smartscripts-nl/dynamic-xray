
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local G_reader_settings = G_reader_settings

--- @class Files
local Files = WidgetContainer:extend{
    home_dir_with_end_slash = nil,
    ui = nil,
}

function Files:init()
    local home_dir = G_reader_settings:readSetting("home_dir")
    if not home_dir then
        local Device = require("device")
        home_dir = Device.home_dir or lfs.currentdir() or "."
    end
    self.home_dir_with_end_slash = home_dir .. "/"
end

Files:init()

function Files:openFile(full_path, next_tick, skip_close_all_widgets)

    --! needed for edge case: we select an item by numerical hotkey from History, but then this var not unset, which means that Menu will use Shift+F instead of F for calling filter functionality:
    KOR.registry:unset("history_active")

    --* needed for when we want to open a file from History:
    local in_file_manager = KOR.registry:get("infilemanager")
    if not skip_close_all_widgets then
        KOR.dialogs:closeAllDialogs()
    end

    if full_path and lfs.attributes(full_path, "mode") == "file" then

        if not in_file_manager then
            if not next_tick then
                KOR.ui:switchDocument(full_path, true)
            else
                UIManager:nextTick(function()
                    KOR.ui:switchDocument(full_path, true)
                end)
            end

        --* in FileManager (switchDocument would lead to a crash):
        else
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(full_path)
        end
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
