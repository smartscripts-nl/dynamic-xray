--- @class XrayPatches1

--[[
    Runtime KOReader patches executed ONLY on userpatch.before_exit
--]]

local require = require

--! VERY IMPORTANT: extend package.path and load the KOR system first!:
--* ============ LOAD EXTENSIONS SYSTEM ===============

local lfs = require("libs/libkoreader-lfs")

local lfs_attributes = lfs.attributes

local controller_path
local function locatePatcher()
    local table_insert = table.insert
    local type = type
    local count
    --* code adapted from PluginLoader:
    local DEFAULT_PLUGIN_PATH = "plugins"
    local lookup_path_list = { DEFAULT_PLUGIN_PATH }
    local extra_paths = G_reader_settings:readSetting("extra_plugin_paths")
    if extra_paths then
        if type(extra_paths) == "string" then
            extra_paths = { extra_paths }
        end
        if type(extra_paths) == "table" then
            count = #extra_paths
            local extra_path, extra_path_mode
            for i = 1, count do
                extra_path = extra_paths[i]
                extra_path_mode = lfs_attributes(extra_path, "mode")
                if extra_path_mode == "directory" and extra_path ~= DEFAULT_PLUGIN_PATH then
                    table_insert(lookup_path_list, extra_path)
                end
            end
        else
            require("logger").err("extra_plugin_paths config only accepts string or table value")
        end
    end

    count = #lookup_path_list
    local lfs_dir = lfs.dir
    local lookup_path
    for i = 1, count do
        lookup_path = lookup_path_list[i]
        for entry in lfs_dir(lookup_path) do
            local plugin_root = lookup_path .. "/" .. entry
            local mode = lfs_attributes(plugin_root, "mode")
            if mode == "directory" and entry == "xraycontroller.koplugin" then
                controller_path = plugin_root
                break
            end
        end
    end
end

--! try to load most of the DX code from the xraycontroller.koplugin folder...

local data_dir = require("datastorage"):getDataDir()
if data_dir ~= "." then
    local user_extra_path = data_dir .. "/plugins/"
    if lfs_attributes(user_extra_path .. "/xraycontroller.koplugin", "mode") == "directory" then
        controller_path = user_extra_path .. "/xraycontroller.koplugin"
    end
end

if not controller_path then
    locatePatcher()
end
if not controller_path then
    return
end

-- #((patch: add Dynamic Xray to KOReader))
package.path = controller_path .. "/?.lua;" .. package.path

require("xraycontroller/xraycontroller")
require("dx-patches")
