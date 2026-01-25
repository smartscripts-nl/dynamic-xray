
--* see ((Dynamic Xray: module info)) for more info

local require = require

local ButtonDialog = require("extensions/widgets/buttondialog")
local Event = require("ui/event")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local Size = require("ui/size")

local DX = DX
local math_ceil = math.ceil

--- @class XrayCallbacks
local XrayCallbacks = WidgetContainer:new{}

--* for calling through hotkeys - ((KeyEvents#addHotkeysForXrayPageNavigator)) - and as callbacks for usage in Xray buttons


--- @param iparent XrayPageNavigator
function XrayCallbacks:execAddCallback(iparent)
    iparent.return_to_page = iparent.navigator_page_no
    iparent:closePageNavigator()
    DX.c:resetFilteredItems()
    DX.c:onShowNewItemForm()
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execEditCallback(iparent)
    local current_tab_item = DX.sp:getCurrentTabItem()
    if not current_tab_item then
        KOR.messages:notify(_("there was no item to be edited..."))
        return true
    end
    DX.fd:setFormItemId(current_tab_item.id)
    iparent:closePageNavigator()
    DX.c:setProp("return_to_viewer", false)
    --* to to be consumed in ((XrayButtons#forItemEditor)) > ((XrayPageNavigator#returnToNavigator)):
    iparent:setProp("return_to_page", iparent.navigator_page_no)
    if #DX.sp.side_buttons > 0 then
        iparent:setProp("return_to_item_no", DX.sp.active_side_button)
        iparent:setProp("return_to_current_item", iparent.current_item)
    end
    DX.c:onShowEditItemForm(current_tab_item, false, 1)
    return true
end

--* compare ((XrayDialogs#showUiPageInfo))
function XrayCallbacks:execExportXrayItemsCallback()

    if DX.pn.cached_export_info then
        DX.pn:showExportXrayItemsDialog()
        return true
    end

    local items = DX.vd.items
    if not items then
        return true
    end
    local cached_export_info, cached_export_info_icon_less = DX.vd:generateXrayItemsOverview(items)
    DX.pn:setProp("cached_export_info", cached_export_info)
    DX.pn:setProp("cached_export_info_icon_less", cached_export_info_icon_less)

    DX.pn:showExportXrayItemsDialog()
    return true
end

function XrayCallbacks:execGotoNextPageCallback(goto_next_item)
    if goto_next_item then
        goto_next_item = DX.sp:getCurrentTabItem()
    end
    DX.p:toNextNavigatorPage(goto_next_item)
    return true
end

function XrayCallbacks:execGotoPrevPageCallback(goto_prev_item)
    if goto_prev_item then
        goto_prev_item = DX.sp:getCurrentTabItem()
    end
    DX.p:toPrevNavigatorPage(goto_prev_item)
    return true
end

function XrayCallbacks:execJumpToCurrentPageInNavigatorCallback()
    KOR.messages:notify(_("jumped back to start page..."))
    DX.p:toCurrentNavigatorPage()
    return true
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execJumpToCurrentPageInEbookCallback(iparent)
    iparent:closePageNavigator()
    KOR.ui.link:addCurrentLocationToStack()
    KOR.ui:handleEvent(Event:new("GotoPage", iparent.navigator_page_no))
    return true
end

function XrayCallbacks:execJumpToPageCallback()
    DX.p:jumpToPage()
    return true
end

function XrayCallbacks:execPageNavigatorSearchItemCallback()
    DX.c:onShowList(nil, false, "select_mode")
    --* after a selection in the list, the item will be searched in ((XrayPages#gotoPageHitForItem)), with option search_also_in_opposite_direction set to true
    return true
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execSettingsCallback(iparent)
    iparent:closePageNavigator()
    DX.s.showSettingsManager()
    return true
end

function XrayCallbacks:execShowHelpInfoCallback()
    return KOR.informationdialog:forPageNavigator()
end

function XrayCallbacks:execShowListCallback()
    DX.c:onShowList()
    return true
end

function XrayCallbacks:execShowItemOccurrencesCallback()
    local current_tab_item = DX.sp:getCurrentTabItem()
    if not current_tab_item then
        return true
    end

    if not current_tab_item then
        KOR.messages:notify(_("no item to display found on this page..."))
        return true
    end
    DX.c:viewItemHits(current_tab_item.name)
    return true
end

--! needed for ((XrayCallbacks#execShowPageBrowserCallback)) > show PageBrowserWidget > tap on a page > ((PageBrowserWidget#onClose)) > call laucher:onClose():
function XrayCallbacks:onClose()
    DX.pn:closePageNavigator()
    local initial_page = DX.pn.initial_browsing_page

    --* use PageBrowserWidget taps to navigate in Page Navigator, but reset location in reader to previous page:
    UIManager:nextTick(function()
        DX.pn:setProp("navigator_page_no", DX.u:getCurrentPage())
        --* undo page jump in the e-reader:
        KOR.link:onGoBackLink()
        DX.pn:showNavigator(initial_page)
    end)
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execShowPageBrowserCallback(iparent)
    if not iparent.navigator_page_no then
        return true
    end
    local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    iparent.page_browser = PageBrowserWidget:new{
        --! via this prop PageBrowserWidget can call ((XrayCallbacks#onClose)):
        launcher = DX.cb,
        ui = KOR.ui,
        focus_page = iparent.navigator_page_no,
        cur_page = iparent.navigator_page_no,
    }
    UIManager:show(iparent.page_browser)
    iparent.page_browser:update()
    return true
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execShowPopupButtonsCallback(iparent)
    --* these anchor dims - computed based on the widths and heights of HtmlBox elements - were set in ((HtmlBox#generateWidget)):
    local anchor = KOR.registry:get("anchor_button")
    local popup_menu = ButtonDialog:new{
        forced_width = anchor.w,
        bordercolor = KOR.colors.line_separator,
        borderradius = Size.radius.default,
        additional_key_events = {
            ClosePopupMenu = {
                { { DX.s.hk_page_navigator_popup_menu } }, function()
                    iparent:closePopupMenu()
                    return true
                end
            },
        },
        tap_close_callback = function()
            iparent:closePopupMenu()
        end,
        buttons = iparent.popup_buttons,
    }
    anchor.y = anchor.parent_y - math_ceil(DX.s.PN_popup_ypos_factor * popup_menu.inner_height)
    iparent.movable_popup_menu = MovableContainer:new{
        popup_menu,
        dimen = Screen:getSize(),
    }

    iparent.movable_popup_menu:moveToAnchor(anchor)
    UIManager:show(iparent.movable_popup_menu)
    return true
end

function XrayCallbacks:execViewItemCallback()
    local current_tab_item = DX.sp:getCurrentTabItem()
    if not current_tab_item then
        return true
    end
    DX.d:showItemViewer(current_tab_item)
    return true
end

return XrayCallbacks
