
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
local has_content = has_content
local has_text = has_text
local math_floor = math.floor
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

--- @class XrayInfoPanel
local XrayInfoPanel = WidgetContainer:new{
    alias_indent = "   ",
    alias_indent_corrected = nil,
    info_indent = "     ",
    info_panel_text = nil,
    max_line_length = DX.s.PN_info_panel_max_line_length,
    upon_load_panel_text = nil,
}

function XrayInfoPanel:generateInfoPanel(data)

    self.info_panel_text = data.info_panel_text
    local screen_height = data.screen_height
    --* set the info panel height as a fraction of the screen height:
    self.info_panel_height = math_floor(screen_height * DX.s.PN_info_panel_height)
    self.info_panel_width = data.info_panel_width
    local content_height = data.content_height
    local info_panel_nav_buttons_height = data.info_panel_nav_buttons_height
    local histogram_height = data.histogram_height
    local histogram_bottom_line_height = data.histogram_bottom_line_height
    local ratio_per_chapter = data.ratio_per_chapter

    --* info_text was generated in ((XrayPageNavigator#showNavigator)) > ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markItem)) > ((XrayInfoPanel#getItemInfoText)):
    local info_text = self.info_panel_text or " "

    local info_panel = self:generateInfoPanelContent(info_text)
    local info_panel_separator = self:generateInfoPanelSeparator()

    --self.info_panel_height = self.info_panel:getSize().h
    local info_panel_separator_height = info_panel_separator:getSize().h
    content_height = content_height - self.info_panel_height - info_panel_separator_height - info_panel_nav_buttons_height
    local sheight = content_height
    if ratio_per_chapter then
        sheight = sheight - histogram_height - histogram_bottom_line_height
    end

    return info_panel, info_panel_separator, self.info_panel_height, info_panel_separator_height, sheight
end

--* this method will be called by ((XraySidePanels#activatePageNavigatorPanelTab)), when the use activated the side panel for linked items there:
function XrayInfoPanel:setParentReliabilityIndicator()
    local reliability_indicator = self.info_panel_text:match("^\n([^ ]+) ")
    --* for consumption in ((XrayViewsData#generateXrayExportOrLinkedItemItemInfo)):
    KOR.registry:set("parent_reliability_indicator", reliability_indicator)
end

--- @private
function XrayInfoPanel:returnEditedInfoPanelText(side_button)
    local id = side_button.xray_item.id
    side_button.xray_item.description = DX.m.items_by_id[id].description
    --? don't know why we need this to update info texts for linked items:
    DX.sp:resetInfoTexts()
    DX.pn:resetCachedInfoFor(side_button.xray_item)
    side_button.info_text = self:getItemInfoText(side_button.xray_item, "for_info_panel") or " "

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

    if has_text(self.upon_load_panel_text) and active_side_button == 1 then
        --* this text was generated for the first item via ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton))
        return self.upon_load_panel_text
    end

    --* xray_item.info_text for first button was generated in ((XraySidePanels#markActiveSideButton)) > ((XraySidePanels#generateInfoTextForFirstSideButton)):
    --* info_text for each button generated via ((XrayPages#markedItemRegister)) > ((XrayInfoPanel#getItemInfoText)) > ((XraySidePanels#addSideButton)):
    return side_button and (side_button.info_text or self:getItemInfoText(side_button.xray_item, "for_info_panel")) or " "
end

--- @private
function XrayInfoPanel:generateInfoPanelContent(info_text)

    --* info_text was generated in ((XrayPageNavigator#showNavigator)) > ((XrayPages#markItemsFoundInPageHtml)) > ((XrayPages#markItem)) > ((XrayInfoPanel#getItemInfoText)):
    return ScrollTextWidget:new{
        text = info_text,
        face = Font:getFace("x_smallinfofont", DX.s.PN_panels_font_size or 14),
        line_height = 0.16,
        alignment = "left",
        justified = false,
        dialog = self,
        --* info_panel_width was computed in ((NavigatorBox#generateInfoButtons)):
        width = self.info_panel_width,
        height = self.info_panel_height,
    }
end

function XrayInfoPanel:generateInfoPanelSeparator()
    return LineWidget:new{
        background = KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.info_panel_width,
            h = Size.line.thick,
        }
    }
end

--- @private
function XrayInfoPanel:getItemInfoIndentation()
    local indent = " "
    return indent:rep(DX.s.item_info_indent)
end

--- @private
function XrayInfoPanel:itemInfoAddHits(item, indent)
    --* when called from ((XrayViewsData#generateXrayExportOrLinkedItemItemInfo)) - so when generating an overview of all Xray items -, add no additional indentation:
    if not indent then
        indent = ""
    end
    local hits = ""
    local series_hits_added = false
    if DX.m.current_series and has_content(item.series_hits) then
        series_hits_added = true
        hits = KOR.icons.graph_bare .. " serie " .. tonumber(item.series_hits)
    end
    if has_content(item.book_hits) then
        local separator = series_hits_added and ", " or KOR.icons.graph_bare .. " "
        hits = hits .. separator .. "boek " .. tonumber(item.book_hits)
    end
    if has_text(hits) then
        return indent .. hits
    end
    return hits
end

--- @private
function XrayInfoPanel:itemInfoAddPropInfo(item, prop, icon, info_table, indent)
    if not item[prop] then
        return
    end

    local prop_info = self:splitLinesToMaxLength(item[prop], icon .. " " .. item[prop])
    if has_text(prop_info) then
        table_insert(info_table, indent .. prop_info .. "\n")
    end
end

--- @private
function XrayInfoPanel:splitLinesToMaxLength(prop, text)
    if not has_text(prop) then
        return ""
    end
    return KOR.strings:splitLinesToMaxLength(text, self.max_line_length - DX.s.item_info_indent, self.alias_indent_corrected, nil, "dont_indent_first_line")
end

--* this info will be consumed for the info panel in ((NavigatorBox#generateScrollWidget)):
--* compare for generation of info_text for linked items: ((XrayViewsData#generateXrayExportOrLinkedItemItemInfo)):
function XrayInfoPanel:getItemInfoText(item, for_info_panel)
    --* the reliability_indicators were added and cached via ((XrayUI#getXrayItemsFoundInText)) > ((XrayUI#matchNameInPageOrParagraph)) and ((XrayUI#matchAliasesToParagraph)) > ((XrayPageNavigator#cacheReliabilityIndicators)), or via this statement:
    DX.pn:cacheReliabilityIndicator(item, DX.pn.page_no)

    local reliability_indicator = item.reliability_indicator or DX.pn.cached_reliability_indicators[item.name] and DX.pn.cached_reliability_indicators[item.name][DX.pn.page_no]
    reliability_indicator = reliability_indicator and reliability_indicator .. " " or ""

    --* this cached info was set farther below in the current method:
    if DX.pn.cached_items_info[item.name] then
        --* if an item was cached, don't add linebreaks to the linebreak already present in the cached info:
        local prefix = for_info_panel and "" or "\n"
        local info = prefix .. reliability_indicator .. DX.pn.cached_items_info[item.name]
        if not info:match("^\n") then
            return "\n" .. info
        end
        return info:gsub("^\n\n", "\n")
    end

    reliability_indicator = self:generateItemMetaInfo(item, reliability_indicator)
    if DX.pn.navigation_tag then
        return reliability_indicator
    end

    return reliability_indicator .. DX.pn.cached_items_info[item.name]
end

--- @private
function XrayInfoPanel:generateItemMetaInfo(item, reliability_indicator)
    local reliability_indicator_placeholder = item.reliability_indicator and "  " or ""
    DX.pn:setProp("sub_info_separator", "")

    local icon = DX.vd:getItemTypeIcon(item, "bare")
    --* alias_indent suffixed with 2 spaces, because of icon .. " ":
    local info = icon .. " " .. item.name .. "\n"
    local description = item.description
    description = KOR.strings:splitLinesToMaxLength(self.alias_indent .. "  " .. description, self.max_line_length, self.alias_indent .. "  ", nil, "dont_indent_first_line")
    info = info .. "\n" .. reliability_indicator_placeholder .. description

    local info_table = {}
    local indent = self:getItemInfoIndentation()

    local hits_info = self:itemInfoAddHits(item, indent)
    if has_text(hits_info) then
        table_insert(info_table, hits_info .. "\n")
    end
    --* for use with ((XrayInfoPanel#splitLinesToMaxLength)):
    self.alias_indent_corrected = DX.s.is_mobile_device and self.alias_indent .. self.alias_indent .. self.alias_indent .. self.alias_indent or self.alias_indent
    self:itemInfoAddPropInfo(item, "aliases", KOR.icons.xray_alias_bare, info_table, indent)
    self:itemInfoAddPropInfo(item, "linkwords", KOR.icons.xray_link_bare, info_table, indent)
    self:itemInfoAddPropInfo(item, "tags", KOR.icons.tag_open_bare, info_table, indent)
    if #info_table > 0 then
        info = info .. " \n" .. table_concat(info_table, "")
    end

    --* remove reliability_indicator_placeholder:
    info = info:gsub("\n  ", "", 1)
    DX.pn:setCachedInfoFor(item, info)

    if DX.pn.navigation_tag then
        --? for some reason we only need this correction if a navigation tag is active:
        reliability_indicator = reliability_indicator:gsub("^\n+", "")
        return "\n" .. reliability_indicator .. DX.pn.cached_items_info[item.name]
    end
    if not reliability_indicator:match("^\n") then
        return "\n" .. reliability_indicator
    end
    return reliability_indicator
end

function XrayInfoPanel:setProp(prop, value)
    self[prop] = value
end

return XrayInfoPanel
