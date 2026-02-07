
--* see ((Dynamic Xray: module info)) for more info

local require = require

local ButtonDialog = require("extensions/widgets/buttondialog")
local DataStorage = require("datastorage")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local Size = require("ui/size")
local T = require("ffi/util").template

local DX = DX
local has_content = has_content
local has_text = has_text
local os_date = os.date
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

--- @type XrayModel parent
local parent

--- @class XrayPageNavigator
local XrayPageNavigator = WidgetContainer:new{
    active_filter_name = nil,
    alias_indent = "   ",
    cached_export_info = nil,
    cached_hits_by_needle = {},
    cached_html_and_buttons_by_page_no = {},
    cached_items = {},
    current_item = nil,
    initial_browsing_page = nil,
    key_events = {},
    max_line_length = 80,
    navigator_page_no = nil,
    movable_popup_menu = nil,
    page_navigator_filter_item = nil,
    --* we need this item for computing linked item buttons in side panel no 2:
    parent_item = nil,
    popup_buttons = nil,
    popup_menu = nil,
    return_to_current_item = nil,
    return_to_item_no = nil,
    return_to_page = nil,
    screen_width = nil,
    scroll_to_page = nil,
}

--- @param xray_model XrayModel
function XrayPageNavigator:initDataHandlers(xray_model)
    parent = xray_model
    self.screen_width = Screen:getWidth()
end

function XrayPageNavigator:restoreNavigator()
    self:showNavigator(self.initial_browsing_page)
end

function XrayPageNavigator:showNavigator(initial_browsing_page)

    if KOR.ui and KOR.ui.paging then
        KOR.messages:notify(_("the page navigator is only available in epubs etc..."))
        return
    end

    self.popup_buttons = self.popup_buttons or DX.b:forPageNavigatorPopupButtons(self)

    --! watch out: this is another var than navigator_page_no on the next line; if you make their names identical, then browsing to next or previous page is not possible anymore:
    --* initial_browsing_page is the page on which you started using the Navigator, while self.navigator_page_no is the actual page you are viewing in the Navigator after browsing to other pages:
    if not self.navigator_page_no or (initial_browsing_page and self.initial_browsing_page ~= initial_browsing_page) then
        self.navigator_page_no = DX.u:getCurrentPage()
        if not self.navigator_page_no then
            KOR.messages:notify("pagina kon niet worden bepaald")
            return
        end
    end
    self.initial_browsing_page = initial_browsing_page or DX.u:getCurrentPage()
    self:closePageNavigator()
    local html = self:loadDataForPage()

    local key_events_module = "XrayPageNavigator"
    KOR.anchorbutton:initButtonProps(2, #self.popup_buttons)
    self.page_navigator = KOR.dialogs:htmlBox({
        title = DX.m.current_title .. " - p." .. self.navigator_page_no,
        page_navigator = self,
        html = html,
        modal = false,
        info_panel_text = DX.ip:getInfoPanelText(),
        window_size = "fullscreen",
        --* no computations needed when popup_menu was already created:
        has_anchor_button = not self.popup_menu,
        key_events_module = key_events_module,
        no_buttons_row = true,
        top_buttons_left = DX.b:forPageNavigatorTopLeft(self),
        --* side_buttons were generated via ((XrayPages#markedItemRegister)) > ((XraySidePanels#addSideButton)):
        side_buttons = DX.sp.side_buttons,
        info_panel_buttons = DX.b:forPageNavigator(self),
        hotkeys_configurator = function()
            KOR.keyevents.addHotkeysForXrayPageNavigator(self, key_events_module)
        end,
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
            KOR.keyevents:unregisterSharedHotkeys(key_events_module)
        end,
        next_item_callback = function()
            DX.p:toNextNavigatorPage()
        end,
        prev_item_callback = function()
            DX.p:toPrevNavigatorPage()
        end,
    })

    --! have the popup menu available immediately, so we can compute its height in this method, for correct positioning above the anchor button:
    self:createPopupMenu()
end

--* this info will be consumed for the info panel in ((HtmlBox#generateScrollWidget)):
--- @private
function XrayPageNavigator:getItemInfoText(item)
    --* the reliability_indicators were added in ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)):
    local reliability_indicator = item.reliability_indicator and item.reliability_indicator .. " " or ""

    if self.cached_items[item.name] then
        return "\n" .. reliability_indicator .. self.cached_items[item.name]
    end

    self.max_line_length = DX.s.is_mobile_device and 40 or self.max_line_length

    local reliability_indicator_placeholder = item.reliability_indicator and "  " or ""
    self.sub_info_separator = ""

    local icon = DX.vd:getItemTypeIcon(item, "bare")
    --* alias_indent suffixed with 2 spaces, because of icon .. " ":
    local description = item.description
    description = KOR.strings:splitLinesToMaxLength(icon .. " " .. item.name .. ": " .. description, self.max_line_length, self.alias_indent .. "  ", nil, "dont_indent_first_line")
    local info = "\n" .. reliability_indicator_placeholder .. description .. "\n"

    local info_table = {}
    local indent = self:getItemInfoIndentation()

    local hits_info = self:itemInfoAddHits(item, indent)
    if has_text(hits_info) then
        table_insert(info_table, hits_info .. "\n")
    end
    --* for use with ((XrayPageNavigator#splitLinesToMaxLength)):
    self.alias_indent_corrected = DX.s.is_mobile_device and self.alias_indent .. self.alias_indent .. self.alias_indent .. self.alias_indent or self.alias_indent
    self:itemInfoAddPropInfo(item, "aliases", KOR.icons.xray_alias_bare, info_table, indent)
    self:itemInfoAddPropInfo(item, "linkwords", KOR.icons.xray_link_bare, info_table, indent)
    if #info_table > 0 then
        info = info .. " \n" .. table_concat(info_table, "")
    end

    --* remove reliability_indicator_placeholder:
    self.cached_items[item.name] = info:gsub("\n  ", "", 1)

    return "\n" .. reliability_indicator .. self.cached_items[item.name]
end

--- @private
function XrayPageNavigator:getItemInfoIndentation()
    local indent = " "
    return indent:rep(DX.s.item_info_indent)
end

--- @private
function XrayPageNavigator:itemInfoAddHits(item, indent)
    --* when called from ((XrayViewsData#generateXrayItemInfo)) - so when generating an overview of all Xray items -, add no additional indentation:
    if not indent then
        indent = ""
    end
    local hits = ""
    local series_hits_added = false
    if parent.current_series and has_content(item.series_hits) then
        series_hits_added = true
        hits = KOR.icons.graph_bare .. " " .. _("series") .. " " .. tonumber(item.series_hits)
    end
    if has_content(item.book_hits) then
        local separator = series_hits_added and ", " or KOR.icons.graph_bare .. " "
        hits = hits .. separator .. _("book") .. " " .. tonumber(item.book_hits)
    end
    if has_text(hits) then
        return indent .. hits
    end
    return hits
end

--- @private
function XrayPageNavigator:itemInfoAddPropInfo(item, prop, icon, info_table, indent)
    if not item[prop] then
        return
    end

    local prop_info = self:splitLinesToMaxLength(item[prop], icon .. " " .. item[prop])
    if has_text(prop_info) then
        table_insert(info_table, indent .. prop_info .. "\n")
    end
end

--- @private
function XrayPageNavigator:splitLinesToMaxLength(prop, text)
    if not has_text(prop) then
        return ""
    end
    return KOR.strings:splitLinesToMaxLength(text, self.max_line_length - DX.s.item_info_indent, self.alias_indent_corrected, nil, "dont_indent_first_line")
end

function XrayPageNavigator:resetFilter()
    self:setActiveScrollPage()
    self.page_navigator_filter_item = nil
    self.active_filter_name = nil
    DX.sp:resetActiveSideButtons("XrayPageNavigator:resetFilter")
    self:reloadPageNavigator()
    KOR.messages:notify(_("filter was reset"))
    return true
end

function XrayPageNavigator:setFilter(item)
    --* when called from reset filter button in ((XrayButtons#forPageNavigatorTopLeft)):
    if not item then
        item = self.current_item
    end
    self:setActiveScrollPage()
    self.active_filter_name = item.name
    self.page_navigator_filter_item = item
    DX.sp:resetActiveSideButtons("XrayPageNavigator:setFilter", "dont_reset_active_side_buttons")

    self:reloadPageNavigator()
    KOR.messages:notify(T(_("filter set to %1"), item.name))
    return true
end

--- @private
function XrayPageNavigator:setCurrentItem(item)
    self.current_item = item
    if not item then
        return
    end
    --* we need this item for computing linked item buttons in side panel no 2:
    self.parent_item = KOR.tables:shallowCopy(item)
end

--- @private
function XrayPageNavigator:reloadPageNavigator()
    --* this might be the case when current method called after adding/updating an Xray item, from ((XrayController#resetDynamicXray)):
    if not self.page_navigator then
        return
    end
    self:restoreNavigator()
    self:restoreActiveScrollPage()
end

--* this page will be consumed by ((XrayPageNavigator#reloadPageNavigator)) > ((XrayPageNavigator#restoreActiveScrollPage)):
--- @private
function XrayPageNavigator:setActiveScrollPage()
    self.scroll_to_page = self.page_navigator.html_widget.htmlbox_widget.page_number
end

--* the active scroll page was set in ((XrayPageNavigator#setActiveScrollPage)):
--- @private
function XrayPageNavigator:restoreActiveScrollPage()
    if self.scroll_to_page and self.scroll_to_page > 1 then
        for i = 1, self.scroll_to_page - 1 do
            self.page_navigator.html_widget:onScrollDown(i)
        end
    end
end

--- @private
function XrayPageNavigator:loadDataForPage()

    DX.sp:resetSideButtons()
    if self.current_item then
        DX.sp:computeLinkedItems()
        if DX.sp.active_side_tab == 2 and not self.active_filter_name then
            DX.sp:populateLinkedItemsPanel()
        end
    end

    --* get html and side_buttons from cache; these were stored in ((XrayPages#markItemsFoundInPageHtml)):
    if self.navigator_page_no and self.cached_html_and_buttons_by_page_no[self.navigator_page_no]

        --* don't use cache if a filtered item was set (with its additional html):
        and not self.active_filter_name
    then

        if DX.sp.active_side_tab == 1 then
            DX.sp:setSideButtons(self.cached_html_and_buttons_by_page_no[self.navigator_page_no].side_buttons)
            DX.sp:markActiveSideButton()
        end

        return self.cached_html_and_buttons_by_page_no[self.navigator_page_no].html
    end

    local html = DX.p:getPageHtmlForPage(self.navigator_page_no)
    --* self.cached_html_and_buttons_by_page_no will be updated here:
    --* side_buttons FOR SIDE PANEL TAB NO.1 de facto populated in ((XrayPages#markedItemRegister)) > ((XraySidePanels#addSideButton)):
    html = DX.p:markItemsFoundInPageHtml(html, self.navigator_page_no)

    --? eilas, when a filter has been set, linked items for side panel no 2 have to be recomputed for some reason:
    if DX.sp.active_side_tab == 2 and self.active_filter_name then
        DX.sp:computeLinkedItems()
        DX.sp:populateLinkedItemsPanel()
    end

    DX.sp:markActiveSideButton()

    return html
end

function XrayPageNavigator:resetCache()
    self.cached_export_info = nil
    self.cached_html_and_buttons_by_page_no = {}
    self.cached_hits_by_needle = {}
    self.cached_items = {}
    self.popup_menu = nil
    DX.sp:resetActiveSideButtons("XrayPageNavigator:resetCache")
    self.current_item = nil
end

function XrayPageNavigator:closePageNavigator()
    if self.page_navigator then
        self:closePopupMenu()
        UIManager:close(self.page_navigator)
        self.page_navigator = nil
    end
end

--* the popup menu was opened in ((XrayCallbacks#execShowPopupButtonsCallback)):
function XrayPageNavigator:closePopupMenu()
    UIManager:close(self.movable_popup_menu)
    self.movable_popup_menu = nil
end

function XrayPageNavigator:resetReturnToProps()
    self.return_to_page = nil
    self.return_to_item_no = nil
    self.return_to_current_item = nil
end

function XrayPageNavigator:returnToNavigator()
    --* set by ((XrayCallbacks#execEditCallback)):
    if self.return_to_page then
        --* this is needed so we can return to the page we were looking at:
        self.navigator_page_no = self.return_to_page
        self:restoreNavigator()
        local active_side_button = self.return_to_item_no or 1
        DX.sp:setActiveSideButton("XrayPageNavigator:returnToNavigator", active_side_button)
        --* re-open the last opened item; also set by ((XrayCallbacks#execEditCallback)):
        if self.return_to_item_no then
            self.current_item = self.return_to_current_item
            local side_button = DX.sp:getSideButton(self.return_to_item_no)
            if side_button then
                --* callback defined in ((XrayPages#markedItemRegister)):
                side_button.callback("force_return_to_item")
            end
        end
        self:resetReturnToProps()

        return true
    end

    return false
end

--- @private
function XrayPageNavigator:showExportXrayItemsDialog()
    local top_buttons_left = DX.b:forExportItemsTopLeft()
    local title = parent.current_series and _("All Xray items: series mode") or _("All Xray items: book mode")

    KOR.dialogs:textBox({
        title = title,
        info = self.cached_export_info,
        info_icon_less = self.cached_export_info_icon_less,
        fullscreen = true,
        copy_icon_less_text = true,
        extra_button = KOR.buttoninfopopup:forXrayItemsExportToFile({
            callback = function()
                title = title:gsub(": ([^\n]+)", " in \"" .. parent.current_title .. "\" (%1)")
                local info = title .. "\n" .. _("List generated") .. ": " .. os_date("%Y-%m-%d") .. "\n\n" .. self.cached_export_info_icon_less
                KOR.files:filePutcontents(DataStorage:getDataDir() .. "/xray-items.txt", info)
                KOR.messages:notify(_("list exported to xray-items.txt..."))
            end,
        }),
        extra_button_position = 3,
        top_buttons_left = top_buttons_left,
    })
    KOR.screenhelpers:refreshScreen()
end

--- @private
function XrayPageNavigator:createPopupMenu()
    if self.popup_menu then
        return
    end
    self.popup_menu = ButtonDialog:new{
        forced_width = KOR.anchorbutton.width,
        bordercolor = KOR.colors.line_separator,
        borderradius = Size.radius.default,
        additional_key_events = KOR.keyevents:addHotkeysForXrayPageNavigatorPopupMenu(self),
        tap_close_callback = function()
            self:closePopupMenu()
        end,
        --* these buttons were populated in ((XrayButtons#forPageNavigatorPopupButtons)):
        buttons = self.popup_buttons,
    }
end

--* called via hotkey "M" in ((KeyEvents#addHotkeysForXrayPageNavigator)) or button in ((XrayButtons#forPageNavigator)) > ((XrayCallbacks#execShowPopupButtonsCallback)):
function XrayPageNavigator:showPopupMenu()
    self.movable_popup_menu = MovableContainer:new{
        self.popup_menu,
        dimen = Screen:getSize(),
    }
    KOR.anchorbutton:setAnchorButtonCoordinates(self.popup_menu.inner_height, #self.popup_buttons)
    self.movable_popup_menu:moveToAnchor()
    UIManager:show(self.movable_popup_menu)
end

function XrayPageNavigator:setProp(prop, value)
    self[prop] = value
end

return XrayPageNavigator
