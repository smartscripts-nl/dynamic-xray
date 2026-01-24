
--* see ((Dynamic Xray: module info)) for more info

local require = require

local ButtonTable = require("extensions/widgets/buttontable")
local Font = require("extensions/modules/font")
local Geom = require("ui/geometry")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_no_items = has_no_items
local math_floor = math.floor
local table_insert = table.insert

local count

--- @class XraySidePanels
local XraySidePanels = WidgetContainer:new{
    active_item_marker = KOR.icons.active_tab_bare,
    active_side_buttons = { 1, 1 },
    active_side_tab = 1,
    filtered_item_marker = KOR.icons.filter,
    --* two sets, one for each side_panel:
    info_panel_texts = { {}, {} },
    side_buttons = {},
}

--- @private
function XraySidePanels:addSideButton(item, info_text)
    --* active marking of buttons will be done in ((XraySidePanels#markActiveSideButton))
    local label = item.name
    local button_index = #self.side_buttons + 1
    if button_index < 10 then
        label = button_index .. ". " .. label
    end
    local index = #self.side_buttons + 1
    if self.active_side_buttons[self.active_side_tab] == index then
        label = self.active_item_marker .. label
    end
    table_insert(self.info_panel_texts[self.active_side_tab], info_text)
    table_insert(self.side_buttons, {{
      text = label,
      xray_item = item,
      index = index,
      align = "left",
      --* force_item will be set when we return to the Page Navigator from ((XrayPageNavigator#returnToNavigator)):
      callback = function(force_return_to_item)
          self:setActiveSideButton("XraySidePanels:addSideButton button callback", index)
          --* in side tab no 2 taps on the current item must display info:
          if self.active_side_tab ~= 2 and not force_return_to_item and DX.pn.current_item and item.name == DX.pn.current_item.name then
              return true
          end
          --! only items in side panel no 1 (main items) may modify self.current_item:
          if self.active_side_tab == 1 then
              DX.pn:setCurrentItem(item)
          end
          DX.pn:setActiveScrollPage()
          DX.pn:reloadPageNavigator()
          return true
      end,

      --* for marking or unmarking an item as filter criterium:
      hold_callback = function()
          if DX.pn.active_filter_name == item.name then
              return DX.pn:resetFilter()
          end
          return DX.pn:setFilter(item)
      end,
  }})
end

--* compare ((XraySidePanels#resetActiveSideButtons)):
--- @private
function XraySidePanels:setActiveSideButton(context, active_side_button)
    if active_side_button and self.active_side_tab == 1 then
        self.active_side_buttons = { active_side_button, 1 }
        self.info_panel_texts[2] = {}
    elseif active_side_button then
        self.active_side_buttons = { self.active_side_buttons[1], active_side_button }
    end

    --* context was given here only for debugging:
    self.garbage = context
end

--* compare ((XraySidePanels#setActiveSideButton)):
--- @private
function XraySidePanels:resetActiveSideButtons(context)

    self.active_side_tab = 1
    self.active_side_buttons = { 1, 1 }
    self.info_panel_texts = { {}, {} }

    --* context was given here only for debugging:
    self.garbage = context
end

--* these side panel buttons were generated in ((XrayPageNavigator#markItemsFoundInPageHtml)) > ((XrayPageNavigator#markedItemRegister)):
--- @private
function XraySidePanels:markActiveSideButton()
    count = #self.side_buttons
    local button
    DX.pn:setProp("current_item", nil)

    --* these are rows with one button each:
    for r = 1, count do
        button = self:getSideButton(r)
        button.text = button.text
            :gsub(self.active_item_marker, "")
            :gsub(self.filtered_item_marker, "")
        if button.xray_item.name == DX.pn.active_filter_name then
            button.text = self.filtered_item_marker .. button.text
        end

        --* this might be set by ((XrayPages#handleItemHitFound)):
        if self.active_side_button_by_name and button.xray_item.name == self.active_side_button_by_name then
            DX.pn:setCurrentItem(button.xray_item)
            button.text = self.active_item_marker .. button.text
            self.active_side_buttons[1] = r
        end

        if r == self.active_side_buttons[self.active_side_tab] and not self.active_side_button_by_name then
            button.text = self.active_item_marker .. button.text
            --! only items in side panel no 1 (main items) may modify self.current_item:
            if self.active_side_tab == 1 then
                DX.pn:setCurrentItem(button.xray_item)
            end
        end
        if r == 1 and not self.active_side_button_by_name then
            self:generateInfoTextForFirstSideButton(button)
        end
    end
    self.active_side_button_by_name = nil
end

function XraySidePanels:getSideButton(i)
    return self.side_buttons[i] and self.side_buttons[i][1]
end

--* currently not used:
--- @private
function XraySidePanels:getSideButtonIndexByItem(item)
    local bcount = #self.side_buttons
    for i = 1, bcount do
        if item.name == self.side_buttons[i][1].xray_item.name then
            return self.side_buttons[i][1].index
        end
    end
end

--- @private
function XraySidePanels:generateInfoTextForFirstSideButton(button)
    --* the xray_item prop of these buttons was set in ((XrayPageNavigator#markedItemRegister)):
    local info_text = DX.pn:getItemInfoText(button.xray_item)
    button.xray_item.info_text = info_text
    DX.pn:setProp("first_info_panel_text", info_text)
    DX.pn:setProp("first_info_panel_item_name", button.xray_item.name)
end

--- @private
function XraySidePanels:populateLinkedItemsPanel()
    --* XrayPageNavigator.linked_items was computed in ((XrayPageNavigator#computeLinkedItems)):
    table_insert(DX.pn.linked_items, 1, DX.pn.current_item)
    count = #DX.pn.linked_items
    local info_panel_text
    for i = 1, count do
        info_panel_text = DX.vd:generateXrayItemInfo(DX.pn.linked_items, nil, i, DX.pn.linked_items[i].name, 2, "for_all_items_list")
        if i == 1 then
            DX.pn:setProp("first_info_panel_text", info_panel_text)
        end
        --* apply some hacks to get a correct, uniform lay-out for the info in the bottom panel (apparently we need this for side panel no 2, but not for side panel 1):
        info_panel_text = DX.pn:formatInfoPanelText(info_panel_text)
        self:addSideButton(DX.pn.linked_items[i], info_panel_text)
    end
end

function XraySidePanels:generateSidePanelTabActivators(has_linked_items, side_buttons_width)
    local tab1_config = {
        enabled = self.active_side_tab == 2,
        callback = function()
            self:activatePageNavigatorPanelTab(1)
        end,
    }
    local tab2_config = {
        enabled = self.active_side_tab == 1 and has_linked_items,
        callback = function()
            self:activatePageNavigatorPanelTab(2)
        end,
    }
    --* see for the buttons: ((ButtonInfoPopup#forXrayPageNavigatorContextButtons)) and ((ButtonInfoPopup#forXrayPageNavigatorMainButtons)):
    local active_marker = KOR.icons.active_tab_bare
    if self.active_side_tab == 1 and has_linked_items then
        tab1_config.text_icon = {
            text = active_marker,
            fgcolor = KOR.colors.lighter_indicator_color,
            icon = "page-light",
        }
        --* show no link icon when there are no linked items:
    elseif self.active_side_tab == 1 then
        tab2_config.text = " "
    else
        tab2_config.text_icon = {
            text = active_marker,
            fgcolor = KOR.colors.lighter_indicator_color,
            icon = "link",
        }
    end
    return ButtonTable:new{
        width = side_buttons_width,
        button_font_face = "x_smallinfofont",
        button_font_size = DX.s.PN_panels_font_size or 14,
        buttons = {{
            KOR.buttoninfopopup:forXrayPageNavigatorMainButtons(tab1_config),
            KOR.buttoninfopopup:forXrayPageNavigatorContextButtons(tab2_config),
        }},
        show_parent = self,
        button_font_weight = "normal",
    }
end

--- @private
function XraySidePanels:generateSidePanelButtons(side_buttons_width, screen_height)

    local side_buttons_table_separator = LineWidget:new{
        background = KOR.colors.line_separator,
        dimen = Geom:new{
            w = side_buttons_width,
            h = Size.line.medium,
        }
    }
    local side_buttons_table
    if has_no_items(self.side_buttons) then
        side_buttons_table = ScrollTextWidget:new{
            text = " ",
            face = Font:getFace("x_smallinfofont", DX.s.PN_panels_font_size or 14),
            line_height = 0.16,
            alignment = "left",
            justified = false,
            dialog = self,
            width = side_buttons_width,
            height = math_floor(screen_height * 0.18),
        }
        return side_buttons_table, side_buttons_table_separator
    end

    side_buttons_table = ButtonTable:new{
        width = side_buttons_width,
        button_font_face = "x_smallinfofont",
        button_font_size = DX.s.PN_panels_font_size or 14,
        buttons = self.side_buttons,
        show_parent = self,
        button_font_weight = "normal",
    }
    return side_buttons_table, side_buttons_table_separator
end

--- @private
function XraySidePanels:activatePageNavigatorPanelTab(tab_no)
    self.active_side_tab = tab_no
    local pn = DX.pn
    pn:setActiveScrollPage()
    pn:reloadPageNavigator()
end

function XraySidePanels:setSideButtons(buttons)
    self.side_buttons = buttons
end

function XraySidePanels:resetSideButtons()
    self.side_buttons = {}
end

function XraySidePanels:getCurrentTabItem()
    if self.active_side_tab == 1 then
        return DX.pn.current_item
    end

    local button_index = self.active_side_buttons[2]
    return self.side_buttons[button_index][1].xray_item
end

return XraySidePanels
