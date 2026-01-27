
local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local KOR = require("extensions/kor")
local Menu = require("extensions/widgets/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen

local math_floor = math.floor
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
    caller.width = math_floor(dimen.w * 0.8)
    self.menu = Menu:new{
        show_parent = KOR.ui,
        height = math_floor(dimen.h * 0.8),
        width = caller.width,
        is_borderless = false,
        is_popout = true,
        fullscreen = false,
        with_bottom_line = true,
        perpage = caller.items_per_page,
        menu_name = "xray_settings",
        top_buttons_left = args.top_buttons_left,
        after_close_callback = function()
            KOR.dialogs:closeOverlay()
        end,
        onMenuHold = menu_manager.onMenuHoldSettings,
        _manager = menu_manager,
    }
    table.insert(self.dialog, self.menu)
    self.menu.close_callback = function()
        UIManager:close(self.dialog)
        KOR.dialogs:closeOverlay()
    end
    self.menu:switchItemTable(args.list_title, menu_manager.item_table)

    return self.dialog
end

return List
