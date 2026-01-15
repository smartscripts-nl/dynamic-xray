
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

--- @class TabbedList
local TabbedList = WidgetContainer:extend{}

function TabbedList:create(args)

    local caller = args.caller
    local menu_manager = args.menu_manager
    local dimen = Screen:getSize()
    self.settings_dialog = CenterContainer:new{
        dimen = dimen,
        modal = true,
    }
    caller.width = math_floor(dimen.w * 0.8)
    local tab_label_fontsize = 16
    self.settings_menu = Menu:new{
        title_submenu_buttontable = KOR.tabfactory:generateTabButtons(args.caller_method, caller.active_tab, caller.tab_labels, caller.width, tab_label_fontsize),
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
    table.insert(self.settings_dialog, self.settings_menu)
    self.settings_menu.close_callback = function()
        UIManager:close(self.settings_dialog)
        KOR.dialogs:closeOverlay()
    end
    --* makes the menu_parent via the caller update it items:
    args.populate_tab_items_callback()
    self.settings_menu:switchItemTable(caller.list_title, menu_manager.item_table)

    return self.settings_dialog
end

return TabbedList
