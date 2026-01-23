
local require = require

local ButtonTable = require("extensions/widgets/buttontable")
local KOR = require("extensions/kor")
local Size = require("extensions/modules/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local math = math
local table_insert = table.insert
local type = type

--* see ((TABS)) for more info:

--- @class TabFactory
local TabFactory = WidgetContainer:extend{
    tab_buttons_font = "x_smallinfofont",
    tab_buttons_font_size = 14,
    tabs_as_table = G_reader_settings:readSetting("tabs_as_table"),
}

--- @param tab_method string "htmlBoxTabbed" or "textBoxTabbed":
function TabFactory:setTabButtonAndContent(caller, tab_method, active_tab, args)

    if not active_tab then
        active_tab = 1
    end
    args.active_tab = active_tab

    --* for usage with resp. ((Dialogs#htmlBox)), ((Dialogs#textBox)):
    local content_prop = tab_method == "htmlBoxTabbed" and "html" or "info"
    local tab_content --* can be html or plain text

    if args.tabs_as_table == nil then
        args.tabs_as_table = true
        args.tab_buttons_font = "x_smallinfofont"
        args.tab_buttons_font_size = 14
        args.tab_buttons_font_weight = "normal"
    end

    local count
    --* tabs in button table row:
    if args.tabs_as_table or self.tabs_as_table then
        local buttons = { {} }
        local tab_is_enabled, is_current_tab
        count = #args.tabs
        for i = 1, count do
            local current = i
            local tab = args.tabs[current]
            local label = tab.tab
            tab_is_enabled = tab.enabled ~= false
            is_current_tab = current == active_tab
            if is_current_tab then
                --* other_factory currently not used anywhere:
                if not args.other_factory then
                    tab_content = type(tab[content_prop]) == "function" and tab[content_prop]() or tab[content_prop]
                else
                    tab_content = args.other_factory()
                    args.other_factory = nil
                end
            end
            tab.is_active_tab = current == active_tab
            table_insert(buttons[1], {
                text = label,
                --* active tab will be marked with bold and slightly bigger text in ((Button#generateTextLabel)) > ((mark active tab bold)):
                is_active_tab = current == active_tab,
                --* to force non bold prop for not active tabs (for which is_active_tab is not true):
                is_tab_button = true,
                is_target_tab = tab.is_target_tab,
                text_font_face = args.tab_buttons_font,
                text_font_size = is_current_tab and math.floor(args.tab_buttons_font_size * 1.1) or args.tab_buttons_font_size,
                text_font_weight = is_current_tab and "bold" or "normal",
                text_font_bold = is_current_tab,
                font_bold = is_current_tab,
                fgcolor = is_current_tab and KOR.colors.active_tab or KOR.colors.inactive_tab,

                --* these two props can be set using ((ButtonProps#getButtonState)):
                --* see also ((TabNavigator)) > ((generate tab navigation event handlers)), where the key event for activating a disabled tab is also disabled:
                enabled = tab_is_enabled,
                fgcolor = tab.fgcolor,

                target_button_text = tab.target_button_text,
                -- #((textboxTabbed tab button callbacks))
                -- #((htmlBoxTabbed tab button callbacks))
                callback = function()
                    local has_factory = type(tab[content_prop]) == "function" or args.other_factory
                    if current == active_tab and not has_factory then
                        return
                    end
                    if has_factory and tab.target_tab then
                        active_tab = tab.target_tab
                        args.active_tab = active_tab
                        args.other_factory = tab[content_prop]
                        caller[tab_method](caller, tab.target_tab, args)
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

            table_insert(title_tab_buttons_left, tab_label)
            if i == active_tab then
                tab_content = type(args.tabs[i][content_prop]) == "function" and args.tabs[i][content_prop]() or args.tabs[i][content_prop]
            end
            table_insert(title_tab_callbacks, function()
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

--* for custom tabs in cases where the normal tabfactory method would not work:
function TabFactory:generateTabButtons(caller_method, active_tab, tab_labels, width, base_font_size)
    local buttons = { {} }
    base_font_size = base_font_size or self.tab_buttons_font_size
    local font_bold, font_size
    for i = 1, #tab_labels do
        font_bold, font_size = self:getActiveTabFontProps(active_tab, i, base_font_size)
        table_insert(buttons[1], {
            text = i == active_tab and KOR.icons.active_tab_bare .. tab_labels[i] or tab_labels[i],
            text_font_size = font_size,
            font_bold = font_bold,
            text_font_bold = font_bold,
            font_weight = font_bold and "bold" or "normal",
            callback = function()
                local current = i
                --* points e.g. to ((XraySettings#showSettingsManager)):
                caller_method(current, tab_labels)
            end,
        })
    end

    return ButtonTable:new{
        width = width - 2 * Size.margin.default,
        button_font_face = "x_smallinfofont",
        button_font_size = font_size,
        buttons = buttons,
        zero_sep = true,
        show_parent = KOR.ui,
        button_font_weight = "normal",
    }
end

function TabFactory:getActiveTabFontProps(active_tab, i, font_size)
    if not font_size then
        font_size = self.tab_buttons_font_size
    end
    if i == active_tab then
        return true, math.floor(font_size * 1.15)
    end

    return false, font_size
end

return TabFactory
