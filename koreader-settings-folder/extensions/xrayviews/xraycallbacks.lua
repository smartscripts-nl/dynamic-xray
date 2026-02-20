
--* see ((Dynamic Xray: module info)) for more info

local require = require

local Event = require("ui/event")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX

--- @class XrayCallbacks
local XrayCallbacks = WidgetContainer:new{}

--* for calling through hotkeys - ((KeyEvents#addHotkeysForXrayPageNavigator)) - and as callbacks for usage in Xray buttons


--- @param iparent XrayPageNavigator
function XrayCallbacks:execAddCallback(iparent)
    iparent.return_to_page = iparent.page_no
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
    iparent:setProp("return_to_page", iparent.page_no)
    if #DX.sp.side_buttons > 0 then
        iparent:setProp("return_to_item_no", DX.sp.active_side_button)
        iparent:setProp("return_to_current_item", iparent.current_item)
    end
    DX.c:onShowEditItemForm(current_tab_item, false, 1)
    return true
end

--* compare ((XrayDialogs#showUiPageInfo))
function XrayCallbacks:execExportXrayItemsCallback()
    DX.ex:showExportXrayItemsDialog()
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
    KOR.ui:handleEvent(Event:new("GotoPage", iparent.page_no))
    return true
end

function XrayCallbacks:execJumpToPageCallback()
    DX.p:jumpToPage()
    return true
end

function XrayCallbacks:execPageNavigatorSearchItemCallback()
    DX.c:onShowList(nil, false, "next_or_previous_item")
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
    return DX.i:showPageNavigatorHelp()
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

    --* use PageBrowserWidget taps to navigate in Page Navigator, but reset location in reader to previous page:
    UIManager:nextTick(function()
        DX.pn:setProp("page_no", DX.u:getCurrentPage())
        --* undo page jump in the e-reader:
        KOR.link:onGoBackLink()
        DX.pn:restoreNavigator()
    end)
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execShowPageBrowserCallback(iparent)
    if not iparent.page_no then
        return true
    end
    local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    iparent.page_browser = PageBrowserWidget:new{
        --! via this prop PageBrowserWidget can call ((XrayCallbacks#onClose)):
        launcher = DX.cb,
        ui = KOR.ui,
        focus_page = iparent.page_no,
        cur_page = iparent.page_no,
    }
    UIManager:show(iparent.page_browser)
    iparent.page_browser:update()
    return true
end

--- @param iparent XrayPageNavigator
function XrayCallbacks:execShowPopupButtonsCallback(iparent)
    iparent:showPopupMenu()
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
