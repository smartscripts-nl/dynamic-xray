
local BD = require("ui/bidi")
local Button = require("ui/widget/button")
local Colors = require("extensions/colors")
local Device = require("device")
local Dialogs = require("extensions/dialogs")
local FocusManager = require("ui/widget/focusmanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Icons = require("extensions/icons")
local Registry = require("extensions/registry")
local ScreenHelpers = require("extensions/screenhelpers")
local Size = require("ui/size")
local System = require("extensions/system")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Screen = Device.screen

--[[--
Widget that displays a shortcut icon for menu item.
--]]

-- [...]

--- @class Menu
--- @field title_bar TitleBar
local Menu = FocusManager:extend{

    -- [...]

    top_buttons_left = nil,
    top_buttons_right = nil,

    title_tab_buttons = nil,
    title_submenu_buttontable = nil,

    -- order for these buttons - generated with Button in the calling module! - is from the inside/center to the outside:
    -- max left footer buttons is 6:
    footer_buttons_left = nil,
    -- max right footer buttons is 5:
    footer_buttons_right = nil,

    -- close_callback is a function, which is executed when menu is closed
    -- it is usually set by the widget which creates the menu
    close_callback = nil,
    linesize = Size.line.medium,
    line_color = Colors.menu_line,
    ui = nil,

    no_close_button = false,

    after_close_callback = nil,

    filter = nil,
    show_filtered_count = false,
}

-- [...]

function Menu:init()
    self:setUI()

    self.show_parent = self.show_parent or self

    -- [...]

    -----------------------------------
    -- start to set up widget layout --
    -----------------------------------
    if self.show_path or not self.no_title then
        if self.subtitle == nil then
            if self.show_path then
                self.subtitle = BD.directory(filemanagerutil.abbreviate(self.path))
            elseif self.title_bar_fm_style then
                self.subtitle = ""
            end
        end

        -- #((TitleBar for Menu))
        -- compare ((TitleBar for TextViewer)):
        --left_icon_size_ratio = self.title_bar_fm_style and 1,
        local title_bar_config = {
            width = self.dimen.w,
            fullscreen = self.fullscreen,
            align = "center",
            for_collection = self.collection,
            with_bottom_line = self.with_bottom_line,
            bottom_line_color = self.bottom_line_color,
            bottom_line_h_padding = self.bottom_line_h_padding,
            title = self.title,
            title_face = self.title_face,
            title_multilines = self.title_multilines,
            title_shrink_font_to_fit = true,
            subtitle = self.show_path and BD.directory(filemanagerutil.abbreviate(self.path)) or self.subtitle,
            subtitle_truncate_left = self.show_path,
            subtitle_fullwidth = self.show_path or self.subtitle,
            button_padding = self.title_bar_fm_style and Screen:scaleBySize(5),

            -- callbacks for these buttons defined as callback, to be converted to regular callbacks in ((TitleBar#init)):
            -- buttons in these three groups must be tables of real Buttons:
            top_buttons_left = self.top_buttons_left,
            top_buttons_right = self.top_buttons_right,
            tab_buttons = self.title_tab_buttons,
            submenu_buttontable = self.title_submenu_buttontable,
            -- to make menu instance availabe in callbacks of left or right titlebar icons:
            menu_instance = self,

            close_callback = not self.no_close_button and function()
                self:onClose()
            end or nil,
            show_parent = self.show_parent or self,
        }
        self.title_bar = TitleBar:new(title_bar_config)
    end

    -- [...]

    local footer_nav_elems = {
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_spacer,
        self.page_info_text,
        self.page_info_spacer,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    -- info: here also filtered items counted, if applicable:
    self:injectFooterButtons(footer_nav_elems)

    self.page_info = HorizontalGroup:new(footer_nav_elems)

    -- return button

    -- [...]

    self:_recalculateDimen()
    self.content_group = self.no_title and VerticalGroup:new{
        align = "left",
        body,
    }
    or
    VerticalGroup:new{
        align = "left",
        self.title_bar,
        body,
    }

    -- [...]

    if self.path_items then
        self:refreshPath()
    else
        self:updateItems()
    end

    Dialogs:showOverlay()
end

-- [...]

function Menu:onCloseWidget()
    -- [...]

    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    if (FileManager.instance and not FileManager.instance.tearing_down)
            or (ReaderUI.instance and not ReaderUI.instance.tearing_down) then
        UIManager:setDirty(nil, "ui")
    end

    if self.after_close_callback then
        self:after_close_callback()
    end
    Dialogs:closeOverlay()
end

function Menu:updatePageInfo(select_number)
    -- SmartScripts: hotfix:
    self.perpage = tonumber(self.perpage)

    -- [...]
end

function Menu:updateItems(select_number)

    -- [...]

    self:updatePageInfo(select_number)
    if self.show_path then
        self.title_bar:setSubTitle(BD.directory(filemanagerutil.abbreviate(self.path)))
    end

    -- ! SmartScripts: removed this call here:
    -- self:mergeTitleBarIntoLayout()

    -- #((menu add titlebar))
    table.insert(self.layout, self.title)

    -- [...]
end

-- ! SmartScripts: removed Menu:mergeTitleBarIntoLayout()

--[[
    the itemnumber parameter determines menu page number after switching item table
    1. itemnumber >= 0
        the page number is calculated with items per page
    2. itemnumber == nil
        the page number is 1
    3. itemnumber is negative number
        the page number is not changed, used when item_table is appended with
        new entries

    alternatively, itemmatch may be provided as a {key = value} table,
    and the page number will be the page containing the first item for
    which item.key = value
--]]
function Menu:switchItemTable(new_title, new_item_table, select_number, itemmatch, new_subtitle)
    if select_number == nil then
        self.page = 1
    elseif select_number > 0 then
        self.page = math.ceil(select_number / self.perpage)
    else
        self.page = 1
    end

    if type(itemmatch) == "table" then

        local key, value = next(itemmatch)
        local has_item_filter = key == "filter" and type(value) == "table" and has_text(value.filter)
        local first_filtered_item_found = false

        for num, item in ipairs(new_item_table) do
            if key ~= "filter" and item[key] == value then
                self.page = math.floor((num-1) / self.perpage) + 1
                break
            elseif has_item_filter then
                local filter = value.filter:lower()
                local target_key = value.target_key
                if item[target_key]:lower():match(filter) then
                    if not first_filtered_item_found then
                        self.page = math.floor((num - 1) / self.perpage) + 1
                    end
                    first_filtered_item_found = true
                    item.bold = true
                else
                    item.bold = false
                end
            end
        end
    end

    if self.title_bar then
        if not new_title and self.show_filtered_count and self:isFilterActive() then
            new_title = self.title
        end
        if new_title then
            new_title = self:showFilteredItemsCountInTitle(new_title)
            self.title_bar:setTitle(new_title, true)
        end
        if new_subtitle then
            self.title_bar:setSubTitle(new_subtitle, true)
        end
    end

    -- make sure current page is in right page range
    if new_item_table then
        local max_pages = math.ceil(#new_item_table / self.perpage)
        if self.page > max_pages then
            self.page = max_pages
        end
        if self.page <= 0 then
            self.page = 1
        end

        self.item_table = new_item_table
    end
    self:updateItems()
end

-- [...]

function Menu:onNextPage()

    -- [...]

    self:refreshScreenForFullscreenMenus("register_collection_subpage")
    return true
end

function Menu:onPrevPage()

    -- [...]

    self:refreshScreenForFullscreenMenus("register_collection_subpage")
    return true
end

function Menu:onFirstPage()
    self.page = 1
    self:updateItems()
    self:refreshScreenForFullscreenMenus("register_collection_subpage")
    return true
end

function Menu:onLastPage()
    self.page = self.page_num
    self:updateItems()
    self:refreshScreenForFullscreenMenus("register_collection_subpage")
    return true
end

function Menu:onGotoPage(page)
    self.page = page
    self:updateItems()
    self:refreshScreenForFullscreenMenus("register_collection_subpage")
    return true
end

-- [...]

function Menu:onClose()

    -- [...]

    ScreenHelpers:refreshUI()
    return true
end

-- [...]

function Menu:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
        self.garbage = arg

    -- ! adapted by SmartScripts:
    elseif System:isClosingGesture(direction) then
        if not self.no_title then
            -- If there is a close button displayed (so, this Menu can be
            -- closed), allow easier closing with swipe south.
            self:onClose()
        end

        -- If there is no close button, it's a top level Menu and swipe
        -- [...]
    end
end

-- [...]

function Menu:setTitleBarLeftIcon(icon)
    self.title_bar:setLeftIcon(icon)
end

function Menu:onLeftNavButtonTap() -- to be overriden and implemented by the caller
end

-- [...]

-- ==================== ADDED ====================

-- fix for KOReaders fullscreen Menus not updating when navigating through subpages or closing them:
function Menu:refreshScreenForFullscreenMenus()
    if self.covers_fullscreen then
        ScreenHelpers:refreshUI()
    end
end

function Menu:setUI()
    self.ui = Registry:getUI()
end

function Menu:getCurrentPage(select_number)
    return math.floor(select_number / self.perpage) + 1
end

function Menu:getFilterButton(callback, reset_callback)
    local filter_active = self:isFilterActive()
    local filter_button = {
        text = not filter_active and Icons.filter_bare or Icons.filter_reset_bare,
        fgcolor = Colors.lighter_text,
        font_bold = false,
        callback = function()
            self:resetAllBoldItems()
            if filter_active then
                reset_callback()
            else
                callback()
            end
        end,
        show_parent = self.show_parent,
    }
    return Button:new(filter_button)
end

-- insert footer buttons; additionally optionally inserts a filter button at the left end:
function Menu:injectFooterButtons(footer_nav_elems)

    local nav_spacer = self.page_info_spacer
    if self.footer_buttons_left then
        for _, button in ipairs(self.footer_buttons_left) do
            if type(button) == "table" then
                button = Button:new(button)
            end
            table.insert(footer_nav_elems, 1, button)
            table.insert(footer_nav_elems, 2, nav_spacer)
        end
    end
    if self.footer_buttons_right then
        for _, button in ipairs(self.footer_buttons_right) do
            if type(button) == "table" then
                button = Button:new(button)
            end
            table.insert(footer_nav_elems, nav_spacer)
            table.insert(footer_nav_elems, button)
        end
    end

    if self.filter then
        local f = self.filter
        local filter_button = self:getFilterButton(f.callback, f.reset_callback, f.hold_callback)
        table.insert(footer_nav_elems, 1, nav_spacer)
        table.insert(footer_nav_elems, 1, filter_button)
    end
end

function Menu:calculatePageNum()
    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then
        self.page = self.page_num
    end
end

function Menu:isFilterActive()
    if not self.filter then
        return false
    end
    -- info: self.filter.state can be defined for non text filtering, e.g. in ((XrayItems#onShowXrayList)) > ((filter table example)):
    return self.filter.state == "filtered" or has_text(self.filter.filter)
end

function Menu:isBoldItem(i)
    if not self:isFilterActive() then
        return self.item_table.current == i
    end
    return self.item_table[i].bold == true
end

function Menu:resetAllBoldItems()
    for i = 1, #self.item_table do
        self.item_table[i].bold = false
    end
end

function Menu:showFilteredItemsCountInTitle(new_title)
    if not new_title then
        return
    end
    if self.show_filtered_count and self:isFilterActive() then
        local filtered_count = 0
        for i = 1, #self.item_table do
            if self.item_table[i].bold == true then
                filtered_count = filtered_count + 1
            end
        end

        new_title = new_title .. " (" .. self.filter.filter .. ": " .. filtered_count .. ")"
    end
    return new_title
end

return Menu
