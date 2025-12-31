
--local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local table = table
local type = type

--* see ((TABS)) for more info:

--- @class TabFactory
local TabFactory = WidgetContainer:extend{
    tabs_as_table = G_reader_settings:readSetting("tabs_as_table"),
}

--- @param tab_method string "htmlBoxTabbed" or "textBoxTabbed"
function TabFactory:setTabButtonAndContent(caller, tab_method, active_tab, args)

    if not active_tab then
        active_tab = 1
    end
    args.active_tab = active_tab

    --* for usage in resp. ((Dialogs#htmlBox)) and ((Dialogs#textBox)):
    local content_prop = tab_method == "htmlBoxTabbed" and "html" or "info"
    local tab_content --* can be html or plain text

    if args.tabs_as_table == nil then
        args.tabs_as_table = true
        args.tab_buttons_font = "x_smallinfofont"
        args.tab_buttons_font_size = 12
        args.tab_buttons_font_bold = false
    end

    local count
    --* tabs in button table row:
    if args.tabs_as_table or self.tabs_as_table then
        local buttons = { {} }
        local tab_is_enabled
        count = #args.tabs
        for i = 1, count do
            local current = i
            local label = args.tabs[current].tab
            tab_is_enabled = args.tabs[current].enabled ~= false
            if current == active_tab then
                --* other_factory currently not used anywhere:
                if not args.other_factory then
                    tab_content = type(args.tabs[current][content_prop]) == "function" and args.tabs[current][content_prop]() or args.tabs[current][content_prop]
                else
                    tab_content = args.other_factory()
                    args.other_factory = nil
                end
            end
            table.insert(buttons[1], {
                text = label,
                --* active tab will be marked with bold and slightly bigger text in ((Button#generateTextLabel)) > ((mark active tab bold)):
                is_active_tab = current == active_tab,
                --* to force non bold prop for not active tabs (for which is_active_tab is not true):
                is_tab_button = true,
                is_target_tab = args.tabs[current].is_target_tab,
                text_font_face = args.tab_buttons_font,
                text_font_size = args.tab_buttons_font_size,
                text_font_bold = args.tab_buttons_font_bold,
                font_bold = args.tab_buttons_font_bold,
                fgcolor = active_tab == current and KOR.colors.active_tab or KOR.colors.inactive_tab,

                --* these two props can be set using ((ButtonProps#getButtonState)):
                --* see also ((TabNavigator)) > ((generate tab navigation event handlers)), where the key event for activating a disabled tab is also disabled:
                enabled = tab_is_enabled,
                fgcolor = args.tabs[current].fgcolor,

                target_button_text = args.tabs[current].target_button_text,
                -- #((textboxTabbed tab button callbacks))
                -- #((htmlBoxTabbed tab button callbacks))
                callback = function()
                    local has_factory = type(args.tabs[current][content_prop]) == "function" or args.other_factory
                    if current == active_tab and not has_factory then
                        return
                    end
                    if has_factory and args.tabs[current].target_tab then
                        active_tab = args.tabs[current].target_tab
                        args.active_tab = active_tab
                        args.other_factory = args.tabs[current][content_prop]
                        caller[tab_method](caller, args.tabs[current].target_tab, args)
                        return
                    end
                    caller[tab_method](caller, current, args)
                end
            })
        end
        --* tabs table will be generated in ((HtmlBox#generateTabsTable)) or ((TextViewer#generateTabsTable))
        args.tabs_table_buttons = buttons
        args.title_alignment = "center"

    -- #((tabs in titlebar)):
    else
        local title_tab_buttons_left = {}
        local title_tab_callbacks = {}
        count = #args.tabs
        for i = 1, count do
            local tab_label = args.tabs[i].tab
            --* for title bar tabs add padding by spaces:
            tab_label = " " .. tab_label
            tab_label = tab_label .. " "
            if i == active_tab then
                tab_label = " •" .. tab_label
            end

            table.insert(title_tab_buttons_left, tab_label)
            if i == active_tab then
                tab_content = type(args.tabs[i][content_prop]) == "function" and args.tabs[i][content_prop]() or args.tabs[i][content_prop]
            end
            table.insert(title_tab_callbacks, function()
                if i == active_tab then
                    return
                end
                caller[tab_method](caller, i, args)
            end)
        end
        args.title_tab_buttons_left = title_tab_buttons_left
        args.title_tab_callbacks = title_tab_callbacks
    end

    --* set content of the tab; content_prop can be "html" or "info":
    args[content_prop] = tab_content
end

return TabFactory
