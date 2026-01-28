
--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local has_text = has_text

--- @class XrayInfoPanel
local XrayInfoPanel = WidgetContainer:new{}

--* called from ((XraySidePanels#populateLinkedItemsPanel)):
function XrayInfoPanel:formatInfoPanelText(info_panel_text)
    return info_panel_text
    --* apply some hacks to get a correct, uniform lay-out for the info of linked items in the bottom panel:
        :gsub(DX.vd.info_indent, DX.vd.alias_indent)
        :gsub(DX.vd.alias_indent, "", 1)
        :gsub("\n" .. DX.vd.alias_indent, ": ", 1)
        :gsub(DX.vd.alias_indent .. KOR.icons.graph_bare, "\n" .. DX.vd.alias_indent .. DX.vd.alias_indent .. KOR.icons.graph_bare, 1)
end

--- @private
function XrayInfoPanel:getInfoPanelText()
    if #DX.sp.side_buttons == 0 then
        return " "
    end

    local active_side_button = DX.sp.active_side_buttons[DX.sp.active_side_tab]

    --* the info panel texts per button were computed in ((XraySidePanels#addSideButton)):
    if has_text(DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]) then
        return DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]
    end

    if has_text(DX.pn.first_info_panel_text) and active_side_button == 1 then
        --* this text was generated for the first item via ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton))
        return DX.pn.first_info_panel_text
    end

    local side_button = DX.sp:getSideButton(active_side_button)

    --* xray_item.info_text for first button was generated in ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton)):
    --* info_text for each button generated via ((XrayPages#markedItemRegister)) > ((XrayPageNavigator#getItemInfoText)) > ((XraySidePanels#addSideButton)):
    return side_button and (side_button.info_text or DX.pn:getItemInfoText(side_button.xray_item)) or " "
end

return XrayInfoPanel
