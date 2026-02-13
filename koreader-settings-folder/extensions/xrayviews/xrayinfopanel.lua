
--* see ((Dynamic Xray: module info)) for more info

local require = require

local Font = require("extensions/modules/font")
local Geom = require("ui/geometry")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Size = require("extensions/modules/size")

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
function XrayInfoPanel:returnEditedInfoPanelText(side_button)
    local id = side_button.xray_item.id
    side_button.xray_item.description = DX.m.items_by_id[id].description
    --? don't know why we need this to update info texts for linked items:
    DX.sp:resetInfoTexts()
    DX.pn:resetCachedInfoFor(side_button.xray_item)
    side_button.info_text = DX.pn:getItemInfoText(side_button.xray_item, "for_info_panel") or " "

    return side_button.info_text
end

--- @private
function XrayInfoPanel:getInfoPanelText()
    if #DX.sp.side_buttons == 0 then
        return " "
    end

    local active_side_button = DX.sp.active_side_buttons[DX.sp.active_side_tab]
    local side_button = DX.sp:getSideButton(active_side_button)

    if KOR.registry:getOnce("edited_xray_item") and side_button then
        return self:returnEditedInfoPanelText(side_button)
    end

    --* the info panel texts per button were computed in ((XraySidePanels#addSideButton)):
    if has_text(DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]) then
        return DX.sp.info_panel_texts[DX.sp.active_side_tab][active_side_button]
    end

    if has_text(DX.pn.first_info_panel_text) and active_side_button == 1 then
        --* this text was generated for the first item via ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton))
        return DX.pn.first_info_panel_text
    end

    --* xray_item.info_text for first button was generated in ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton)):
    --* info_text for each button generated via ((XrayPages#markedItemRegister)) > ((XrayPageNavigator#getItemInfoText)) > ((XraySidePanels#addSideButton)):
    return side_button and (side_button.info_text or DX.pn:getItemInfoText(side_button.xray_item, "for_info_panel")) or " "
end

function XrayInfoPanel:generateInfoPanel(info_text, height, width, parent)

    --* info_text was generated in ((XrayPageNavigator#showNavigator)) > ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markItem)) > ((XrayPageNavigator#getItemInfoText)):
    return ScrollTextWidget:new{
        text = info_text,
        face = Font:getFace("x_smallinfofont", DX.s.PN_panels_font_size or 14),
        line_height = 0.16,
        alignment = "left",
        justified = false,
        dialog = parent,
        --* info_panel_width was computed in ((NavigatorBox#generateInfoButtons)):
        width = width,
        height = height,
    }
end

function XrayInfoPanel:generateInfoPanelSeparator(width)
    return LineWidget:new{
        background = KOR.colors.line_separator,
        dimen = Geom:new{
            w = width,
            h = Size.line.thick,
        }
    }
end

return XrayInfoPanel
