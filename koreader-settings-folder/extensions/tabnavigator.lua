
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--* see ((TABS)) for more info:
--* for generating the tab buttons see ((ButtonTableFactory#getTabsTable)):
--- @class TabNavigator
local TabNavigator = WidgetContainer:extend{
    active_tab = nil,
    parent = nil,
    tabs_table_buttons = nil,
}

local tn = TabNavigator

function TabNavigator:init(tabs_table_buttons, active_tab, parent)
    tn.active_tab = active_tab
    tn.parent = parent
    tn.tabs_table_buttons = tabs_table_buttons
end

function TabNavigator:broadcastActivatedTab()
    KOR.registry:set("active_tab", tn.active_tab)
    if tn.parent then
        tn.parent.active_tab = tn.active_tab
    end
end

--* add support for navigating to next tab with hardware keys:
function TabNavigator:onToNextTab()
    tn.active_tab = tn.active_tab + 1
    if tn.active_tab > #tn.tabs_table_buttons[1] then
        tn.active_tab = 1
    end
    UIManager:close(self)
    tn.broadcastActivatedTab()
    tn.tabs_table_buttons[1][tn.active_tab]:callback()
    return true
end

--* add support for navigating to previous tab with hardware keys:
function TabNavigator:onToPreviousTab()
    tn.active_tab = tn.active_tab - 1
    if tn.active_tab < 1 then
        tn.active_tab = #tn.tabs_table_buttons[1]
    end
    UIManager:close(self)
    tn.broadcastActivatedTab()
    tn.tabs_table_buttons[1][tn.active_tab]:callback()
    return true
end

function TabNavigator:onForcePreviousTab()
    --! fix a crash in the Xray Page Navigator, upon a gesture:
    if not tn.tabs_table_buttons or not tn.active_tab then
        return false
    end
    tn.active_tab = tn.active_tab - 1
    if tn.active_tab < 1 then
        tn.active_tab = #tn.tabs_table_buttons[1]
    end
    UIManager:close(self)
    tn.broadcastActivatedTab()
    tn.tabs_table_buttons[1][tn.active_tab]:callback()
    return true
end

--* add support for navigating to previous tab with hardware keys:
function TabNavigator:onForceNextTab()
    tn.active_tab = tn.active_tab + 1
    if tn.active_tab > #tn.tabs_table_buttons[1] then
        tn.active_tab = 1
    end
    tn.broadcastActivatedTab()
    UIManager:close(self)
    tn.tabs_table_buttons[1][tn.active_tab]:callback()
    return true
end

-- #((generate tab navigation event handlers))
for i = 1, 8 do
    TabNavigator["onActivateTab" .. i] = function(self)
        --! self here is the caller!

        --* TabNavigator.tabs_table_buttons[1] is the row of buttons:
        if not tn.tabs_table_buttons or not tn.tabs_table_buttons[1] or #tn.tabs_table_buttons[1] < i or tn.active_tab == i or tn.tabs_table_buttons[1][i].enabled == false then
            return false
        end
        UIManager:close(self)
        tn.active_tab = i
        tn:broadcastActivatedTab()
        --* callbacks defined in ((htmlBoxTabbed tab button callbacks)):
        tn.tabs_table_buttons[1][tn.active_tab]:callback()
        return true
    end
end

function TabNavigator:onActivateTab(tab_no)
    if not tn.tabs_table_buttons or not tn.tabs_table_buttons[1] or tn.tabs_table_buttons[1][tab_no].enabled == false or #tn.tabs_table_buttons[1] < tab_no or tn.active_tab == tab_no then
        return false
    end

    tn.active_tab = tab_no
    tn.broadcastActivatedTab()
    tn.tabs_table_buttons[1][tn.active_tab]:callback()

    return true
end

return TabNavigator
