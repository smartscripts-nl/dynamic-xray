
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

--- @class TabbedList
local TabbedList = WidgetContainer:extend{
    tabbed_dialog = nil,
    tabbed_menu = nil,
}

function TabbedList:create(args)

    local caller = args.caller
    --- @type SettingsManager menu_manager
    local menu_manager = args.menu_manager
    local dimen = Screen:getSize()
    self.tabbed_dialog = CenterContainer:new{
        dimen = dimen,
        modal = true,
    }
    self.tabbed_menu = Menu:new{
        title_submenu_buttontable = KOR.tabfactory:generateTabButtons(args.caller_method, caller.active_tab, caller.tab_labels, dimen.w),
        show_parent = self.tabbed_dialog,
        no_overlay = true,
        width = dimen.w,
        height = dimen.h,
        is_borderless = true,
        is_popout = false,
        fullscreen = true,
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
    table.insert(self.tabbed_dialog, self.tabbed_menu)
    self.tabbed_menu.close_callback = function()
        UIManager:close(self.tabbed_dialog)
        KOR.dialogs:closeOverlay()
    end
    --* makes the menu_parent via the caller update it items:
    args.populate_tab_items_callback()
    self.tabbed_menu:switchItemTable(caller.list_title, menu_manager.item_table, self.tabbed_menu.page)

    return self.tabbed_dialog
end

return TabbedList
