
local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local KOR = require("extensions/kor")
local Menu = require("extensions/widgets/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen

local table = table

--- @class List
local List = WidgetContainer:extend{}

function List:create(args)

    local caller = args.caller or args.parent
    local menu_manager = args.menu_manager
    local dimen = Screen:getSize()
    self.dialog = CenterContainer:new{
        dimen = dimen,
        modal = true,
    }
    self.menu = Menu:new{
        show_parent = KOR.ui,
        is_borderless = true,
        is_popout = false,
        fullscreen = true,
        with_bottom_line = true,
        perpage = caller.items_per_page,
        menu_name = "xray_settings",
        no_overlay = true,
        top_buttons_left = args.top_buttons_left,
        onMenuHold = menu_manager.onMenuHoldSettings,
        _manager = menu_manager,
    }
    table.insert(self.dialog, self.menu)
    self.menu.close_callback = function()
        UIManager:close(self.dialog)
    end
    self.menu:switchItemTable(args.list_title, menu_manager.item_table)

    return self.dialog
end

return List
