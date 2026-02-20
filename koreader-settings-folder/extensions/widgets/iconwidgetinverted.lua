--[[
Subclass of ImageWidgetActive to show icons
]]

local require = require

local DataStorage = require("datastorage")
local ImageWidgetInverted = require("extensions/widgets/imagewidgetinverted")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")

local G_defaults = G_defaults
local table_insert = table.insert

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

-- Directories to look for icons by name, with any of the accepted suffixes
local ICONS_DIRS = {}
local user_icons_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(user_icons_dir, "mode") == "directory" then
    table_insert(ICONS_DIRS, user_icons_dir)
end
-- Default icons (material design light)
table_insert(ICONS_DIRS, "resources/icons/mdlight")
-- Fallback directories
table_insert(ICONS_DIRS, "resources/icons")
table_insert(ICONS_DIRS, "resources")

-- Supported icon suffixes
local ICONS_EXTS = { ".svg", ".png" }

-- Show this icon instead of crashing if we can't find any icon
local ICON_NOT_FOUND = "resources/icons/icon-not-found.svg"

-- Icon filepath location cache
local ICONS_PATH = {}

--- @class IconWidgetInverted
local IconWidgetInverted = ImageWidgetInverted:extend{
    -- The icon filename should be provided without any path
    icon = ICON_NOT_FOUND, -- show this if not provided
    -- See ImageWidgetActive for other available options,
    -- we only start with a few different defaults, that can
    -- be overriden by callers.
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    alpha = false, --- @note: Our icons have a transparent background, but, by default, we flatten them at caching time.
                   ---        Our caller may choose to override that by setting this to true, in which case,
                   ---        the alpha layer will be kept intact, and we'll do alpha-blending at blitting time.
    is_icon = true, -- avoid dithering in ((ImageWidgetActive#paintTo))
}

function IconWidgetInverted:init()
    if self.image or self.file then
        -- In case we're created with one of these: just be an ImageWidgetActive.
        return
    end
    -- See if already seen and full path cached
    self.file = ICONS_PATH[self.icon]
    if not self.file then
        local dir, ext, path
        -- Not yet seen, look for it
        local count = #ICONS_DIRS
        local count2 = #ICONS_EXTS
        for i = 1, count do
            dir = ICONS_DIRS[i]
            for e = 1, count2 do
                ext = ICONS_EXTS[e]
                path = dir .. "/" .. self.icon .. ext
                if lfs.attributes(path, "mode") == "file" then
                    self.file = path
                    break
                end
            end
            if self.file then
                break
            end
        end
        if not self.file then
            self.file = ICON_NOT_FOUND
        end
        ICONS_PATH[self.icon] = self.file
    end
end

return IconWidgetInverted
