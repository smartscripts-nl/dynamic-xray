--[[--
This extension is part of the Dynamic Xray plugin; it has all methods for making Xray items available and visible in ReaderView and ReaderHighlight.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayTranslations)), ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

--! info about TextViewer TOC functionality for Xray items: see ((TextViewer toc button))

local require = require

local Device = require("device")
local Font = require("ui/font")
local KOR = require("extensions/kor")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen

local DX = DX
local has_content = has_content
local has_no_text = has_no_text
local has_text = has_text
local math = math
local pairs = pairs
local table = table

local count

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
                and box.x + box.w >= x
                and box.y + box.h >= y then
            return true
        end
    end
end

--- @class XrayUI
local XrayUI = WidgetContainer:new{
    families_matched_by_multiple_parts = {},
    forbidden_words = {
        Look = 1,
        This = 1,
        Thou = 1,
    },
    hits = {},
    info_extra_button_rows = {},
    info_use_upper_case_names = false,
    info_extra_indent = "    ",
    info_indent = "     ",
    page = nil,
    page_text = nil,
    paragraph_explanations = nil,
    paragraph_hits = nil,
    paragraphs = nil,
    paragraphs_with_matches = nil,
    paragraph_texts = nil,
    rects_with_matches = nil,
    screen_width = nil,
    separator = " " .. KOR.icons.arrow_bare .. " ",
    skip_xray_items = nil,
    xray_context_props = nil,
    xray_info_found = false,
    xray_page_info_rects = nil,
}

--- @private
--- @private
function XrayUI:drawMarker(c, rect)
    --* c was populated in ((XrayUI#ReaderViewSetXrayContextProps)):
    local bb = c.bb
    local xi = c.x
    local yi = c.y
    local marker = c.marker

    --* garbage collection:
    self.garbage = xi
    xi = yi -- luacheck: no unused

    --* first condition hotfix for portrait files?
    if not rect or not marker then
        return
    end

    local note_mark_pos_x = self:getMarkerIconXpos(c, rect)

    --* when we underline bookmarks to indicate notes, we also want to draw the custom marker icon:
    --* note_mark_pos_x will only be not null for bookmarks with tags:
    local marker_rect
    if note_mark_pos_x then
        local y_pos_shift = DX.s.is_ubuntu and 6 or 12
        local y_pos = rect.y + y_pos_shift
        if DX.s.ui_mode == "page" then
            y_pos = y_pos - 7
        end
        marker:paintTo(bb, note_mark_pos_x, y_pos)
        marker_rect = {
            --* we make the rects somewhat wider and higher than the icons, to make them easily tappable:
            x = note_mark_pos_x - 5,
            y = y_pos - 5,
            --* these c props were set via ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#getParaMarker)) > ((XrayUI#ReaderViewSetXrayContextProps)):
            w = c.marker_width + 10,
            h = c.marker_height + 10,
        }
    end
    return marker_rect
end

function XrayUI:getMarkerIconXpos(c, rect)
    local marker_width = c.marker_width
    local is_xray_page_mode = DX.s.ui_mode == "page"
    local is_xray_paragraph_marker = not is_xray_page_mode

    local x = rect.x
    local note_mark_pos_x

    local half_screen_width = KOR.registry.half_screen_width
    --* the bigger this correction, the more to the left the marker:
    local middle_correction = marker_width - 4
    local right_xpos_reduction = marker_width
    if DX.s.is_ubuntu then
        right_xpos_reduction = right_xpos_reduction + 2
    else
        right_xpos_reduction = right_xpos_reduction + Screen:scaleBySize(2)
    end

    --* compare ((set xray marker size))
    local increase_amount = DX.s.is_tablet_device and Screen:scaleBySize(8) or 5
    local xpos_increase = is_xray_page_mode and increase_amount or 0

    --* page 1 in one-page mode
    --* self.ui was set in ((XrayUI#ReaderViewGenerateXrayInformation)):
    if self.ui.document:getVisiblePageCount() == 1 then
        return self.screen_width - right_xpos_reduction

    --* page 1 in two-page mode in xray page mode:
    elseif is_xray_page_mode and x < half_screen_width then
        return half_screen_width - middle_correction + xpos_increase

    --* page 1 in two-page mode in paragraph mode:
    elseif x < half_screen_width then
        -- #((set xray marker position))

        --* we need more whitespace before marking stars:
        xpos_increase = xpos_increase + Screen:scaleBySize(4)
        note_mark_pos_x = half_screen_width - middle_correction + xpos_increase

        --* but shift star markers in the first column more to the left, closer to the text they are marking:
        if is_xray_paragraph_marker then
            note_mark_pos_x = note_mark_pos_x - 7
        end
        return note_mark_pos_x
    end

    --* page 2 in two page mode:
    --note_mark_pos_x = self.tags_mark_pos_x2
    return self.screen_width - right_xpos_reduction
end

--- @private
function XrayUI:getParaMarker(bb)
    local marker, marker_width, marker_height
    if bb then
        -- #((set xray marker size))
        --* compare ((set xray marker position))
        local font_size = DX.s.ui_mode == "paragraph" and 10 or 18
        marker = TextWidget:new{
            text = DX.s.ui_mode == "paragraph" and KOR.icons.xray_item or KOR.icons.lightning_bare,
            face = Font:getFace("smallinfofont", font_size),
            fgcolor = KOR.colors.xray_page_or_paragraph_match_marker,
            padding = 0,
        }
        local icon_dims = marker:getSize()
        marker_height = icon_dims.h
        marker_width = icon_dims.w
    end
    return marker, marker_width, marker_height
end

--- @private
function XrayUI:showParagraphInformation(xray_rects, nr, mode)
    if mode == "hold" then
        local current_epage = self:getCurrentPage()
        DX.d:showPageXrayItemsNavigator(current_epage)
        return
    end

    local paragraph_text = self.paragraph_texts[nr]
    local paragraph_hits_info = ""
    local paragraph_headings = {}
    --* these items were generated via ((init xray sideline markers)) > ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#ReaderViewInitParaOrPageData)) > ((XrayUI#ReaderViewLoopThroughParagraphOrPage)) ((XrayUI#getXrayItemsFoundInText)):
    local items = xray_rects.hits[nr]
    local paragraph_matches_count
    local xray_explanations = xray_rects.explanations[nr]
    -- #((skip partial name hits if familiy member with full name also found))
    --* xray items with partial family name hits that must be removed, because a family member with full name has been found:
    local skip_xray_items = xray_rects.skip_xray_items[nr]

    --* hotfix for doubled names, as retrieved by ((XrayUI#getXrayItemsFoundInText)):
    local injected_names = {}
    local injected_nr = 0
    local more_button_added
    local item
    count = #items
    for i = 1, count do
        item = items[i]
        injected_nr, paragraph_hits_info, more_button_added = self:addParagraphInfoItems(
            items,
            i,
            injected_names,
            xray_explanations,
            skip_xray_items,
            paragraph_headings,
            injected_nr,
            paragraph_hits_info
        )
        if more_button_added then
            break
        end
    end
    paragraph_matches_count = injected_nr
    --* correction for indentation of first line in dialog; this should not be necessary:
    paragraph_hits_info = paragraph_hits_info:gsub("^ +", "")

    -- #((xray paragraph info callback))
    --* callback defined in ((set xray info for paragraphs)) and calls ((XrayDialogs#showItemsInfo)):
    xray_rects.callback(paragraph_hits_info, paragraph_headings, paragraph_matches_count, self.info_extra_button_rows, paragraph_text)
end

function XrayUI:addParagraphInfoItems(items, i, injected_names, xray_explanations, skip_xray_items, paragraph_headings, injected_nr, paragraph_hits_info)
    local prefix, first_line, match_block, description, noun, xray_type_icon, aliases, linkwords, explanation, more_button_added

    local name = items[i].name
    if injected_names[name] or (skip_xray_items and skip_xray_items[name]) then
        return injected_nr, paragraph_hits_info
    end

    injected_names[name] = name
    injected_nr = injected_nr + 1
    prefix = injected_nr == 1 and "" or "\n"
    if self.info_use_upper_case_names then
        name = KOR.strings:upper(name)
    end
    description = KOR.strings:splitLinesToMaxLength(items[i].description, DX.vd.max_line_length, self.info_indent)
    aliases, linkwords, explanation = "", "", ""
    if has_text(items[i].aliases) then
        noun = items[i].aliases:match(" ") and _("aliases: ") or _("alias: ")
        noun = KOR.strings:ucfirst(noun, "force_only_first")
        aliases = KOR.strings:splitLinesToMaxLength(items[i].aliases, DX.vd.max_line_length, self.info_indent, noun) .. "\n"
    end
    if has_text(items[i].linkwords) then
        noun = items[i].linkwords:match(" ") and _("link terms: ") or _("link term: ")
        noun = KOR.strings:ucfirst(noun, "force_only_first")
        linkwords = KOR.strings:splitLinesToMaxLength(items[i].linkwords, DX.vd.max_line_length, self.info_indent, noun) .. "\n"
    end
    -- #((use xray match reliability indicators))
    local xray_match_reliability_icon = DX.tw.match_reliability_indicators.full_name
    --! don't use has_text here, because for full name hits we don't add a text (i.e. the full name) after the reliability weight icon)! Under Ubuntu this is not a problem, but using has_text under Android causes explanation not to be shown:
    if has_content(xray_explanations[i]) then
        explanation = xray_explanations[i]
        xray_match_reliability_icon = explanation:match(self.separator .. "([^ ]+)")
    end

    xray_type_icon = DX.vd:getItemTypeIcon(items[i])
    local hits = DX.vd.list_display_mode == "series" and items[i].series_hits or items[i].book_hits

    --* here the info gets combined:
    -- #((xray items dialog add match reliability explanations))
    first_line = prefix .. xray_type_icon .. name .. " " .. hits .. explanation
    first_line = KOR.strings:splitLinesToMaxLength(first_line, DX.vd.max_line_length, self.info_indent) .. "\n"
    match_block = first_line .. description .. "\n" .. aliases .. linkwords
    paragraph_hits_info = paragraph_hits_info .. match_block

    -- #((headings for use in TextViewer))
    --* needles will be used in ((TextViewer#blockDown)) and  ((TextViewer#blockUp)):
    table.insert(paragraph_headings, {
        name = name,
        --* in paragraph/page info popup first show icon for type of item and importance thereof, and only after that the match reliability indicator icon:
        needle = xray_type_icon .. xray_match_reliability_icon .. " " .. name,
        --* this label will be the button text; by using name:sub we ensure that the text will not be too long:
        label = xray_type_icon .. xray_match_reliability_icon .. " " .. name:sub(1, 14),
        length = match_block:len(),
        xray_item = items[i],
    })

    more_button_added = DX.b:addTappedWordCollectionButton(self.info_extra_button_rows, nil, nil, items[i], {
        nr = injected_nr,
        max_total_buttons = DX.b.info_max_total_buttons,
        max_buttons_per_row = DX.b.max_buttons_per_row,
        source_items = items,
        callback = function()
            DX.c:onShowEditItemForm(items[i])
        end,
        extra_item_callback = function(citem)
            DX.c:onShowEditItemForm(citem)
        end,
    })

    return injected_nr, paragraph_hits_info, more_button_added
end

--* called from ReaderView:
function XrayUI:ReaderViewGenerateXrayInformation(ui, bb, x, y)

    self.ui = ui
    self.page = self:setParagraphsFromDocument()
    self.hits = {}
    local marker, marker_width, marker_height = self:getParaMarker(bb)
    self.xray_page_info_rects = nil
    self:ReaderViewSetXrayContextProps(marker, marker_width, marker_height, bb, x, y)
    -- #((set xray info for paragraphs))
    if self:ReaderViewInitParaOrPageData() then
        --! here callbacks are attached to the marker icon rects:
        self:ReaderViewPopulateInfoRects()
    end
end

--- @private
function XrayUI:ReaderViewInitParaOrPageData()

    --* self.page_text is computed in ((XrayUI#setParagraphsFromDocument)) > ((XrayUI#getFullPageText)):
    if has_no_text(self.page_text) then
        return
    end

    --* text of paragraphs, for debugging:
    self.paragraphs_with_matches = {}
    self.paragraph_hits = {}
    self.paragraph_explanations = {}
    self.rects_with_matches = {}
    self.xray_info_found = false
    --* register partial hits to be skipped per paragraph. This filter will be executed upon clicking on the first line of the concerned paragraph. See ((skip partial name hits if familiy member with full name also found)):
    self.skip_xray_items = {}
    self.screen_width = Screen:getWidth()
    local para_count = #self.paragraphs
    if self.paragraphs and para_count > 0 and #DX.vd.items > 0 then

        --* when in page mode, this loop will be stopped (see break below) as soon as a line is found that is long enough to be suitable for adding the xray marker; in this we assume that page_text does indeed have the full page text, so no loop through all paragraphs necessary:
        local marker_line_found
        for p = 1, para_count do
            marker_line_found = self:ReaderViewLoopThroughParagraphOrPage(p)
            if DX.s.ui_mode == "page" and marker_line_found then
                return self.xray_info_found
            end
        end
    end
    return self.xray_info_found
end

--- @private
function XrayUI:ReaderViewSetXrayContextProps(marker, marker_width, marker_height, bb, x, y)
    self.xray_context_props = {
        marker = marker,
        marker_height = marker_height,
        marker_width = marker_width,
        bb = bb,
        x = x,
        y = y,
    }
end

--* see ((XRAY_ITEMS)) for more info:
--- @private
function XrayUI:ReaderViewLoopThroughParagraphOrPage(p)
    local ui_mode = DX.s.ui_mode

    --* self.page_text was set when storing self.paragraphs, in ((XrayUI#setParagraphsFromDocument)) > ((XrayUI#getFullPageText)):
    local haystack = ui_mode == "paragraph" and self.paragraphs[p].text or self.page_text
    local hits, explanations, skip_items = self:getXrayItemsFoundInText(haystack)
    if hits then
        --* for debugging only:
        table.insert(self.paragraphs_with_matches, self.paragraphs[p].text)
        --* to be consumed in ((XrayUI#ReaderHighlightGenerateXrayInformation)):
        table.insert(self.paragraph_hits, hits)
        table.insert(self.paragraph_explanations, explanations)
        table.insert(self.skip_xray_items, skip_items)
        local name
        count = #hits
        for xi = 1, count do
            name = hits[xi].name
            if not self.hits[name] then
                self.hits[name] = 1
                self.xray_info_found = true
            end
        end
        --* this context table with props was set in ((set xray info for paragraphs)):
        local c = self.xray_context_props
        if c.bb then
            --* call ((CreDocument#getScreenBoxesFromPositions)):
            local lines = KOR.document:getScreenBoxesFromPositions(self.paragraphs[p].pos0, self.paragraphs[p].pos1, true)
            local lines_count = #lines
            -- #((xray page marker set target line for icon))
            local start = 1

            -- #((set half screen width))
            if not KOR.registry.half_screen_width then
                self.screen_width = Screen:getWidth()
                --* this Registry var can be updated upon rotation in ((ReaderView#onRotationUpdate)):
                KOR.registry.half_screen_width = math.floor(self.screen_width / 2)
            end

            local rect, current_column, fallback_line
            local icon_is_drawn = false
            for l = start, lines_count do
                current_column = self:getCurrentColumn(lines[l]["x"])
                --* use this line if bookmark sideline icons have taken all available y positions (lines) => icons will overlap, but better that than not showing the icon at all:
                fallback_line = not fallback_line and lines[l]

                --* because xray marker lines are drawn later then bookmark highlights, tapping on them still works, even when they have an underlying bookmark highlight...

                if not KOR.view.icon_y_positions[current_column][lines[l].y] then
                    --* lines only have position and dimensions data, no text: x, y, w, h:
                    rect = lines[l]
                    icon_is_drawn = true
                    break
                end
            end
            if not icon_is_drawn and fallback_line then
                rect = fallback_line
            end

            if rect then
                local marker_rect = self:drawMarker(c, rect)
                if marker_rect then
                    table.insert(self.rects_with_matches, marker_rect)
                end
                return true
            end
        end
    end
    return false
end

--- @private
function XrayUI:ReaderViewPopulateInfoRects()
    -- #((set xray page info rects))
    --* to be consumed in ((XrayUI#ReaderHighlightGenerateXrayInformation)) > ((XrayUI#showParagraphInformation)):
    self.xray_page_info_rects = {
        paragraph_texts = self.paragraphs_with_matches,
        hits = self.paragraph_hits,
        skip_xray_items = self.skip_xray_items,
        explanations = self.paragraph_explanations,
        rects = self.rects_with_matches,
        --* the buttons in extra_button_rows were generated in ((TextViewer#getDefaultButtons)) > ((XrayButtons#forXrayUiInfo)):
        callback = function(paragraph_hits_info, extra_button_rows, paragraph_text)
            --* paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
            DX.d:showItemsInfo(paragraph_hits_info, extra_button_rows, paragraph_text)
        end
    }
end

--- @private
function XrayUI:getCurrentColumn(x)
    return KOR.ui.document:getVisiblePageCount() > 1 and x > KOR.registry.half_screen_width and 2 or 1
end

--* content of self.paragraphs was generated in ((Html#getAllHtmlContainersInPage)):
--- @private
function XrayUI:getFullPageText()
    if not self.paragraphs then
        return ""
    end
    return KOR.tables:concatField(self.paragraphs, "text", "\n")
end

--* these hits are to be consumed in ((XrayUI#ReaderHighlightGenerateXrayInformation)) > ((XrayDialogs#showItemsInfo))
--- @private
function XrayUI:getXrayItemsFoundInText(page_or_paragraph_text)

    local partial_hits, hits, explanations = {}, {}, {}
    --local multiple_parts_count = 0
    local a_name_matched, an_alias_matched = false, false
    self.families_matched_by_multiple_parts = {}

    local xray_item, xname, hit_found, alias_match_found, names, short_names, xray_name, names_count
    count = #DX.vd.items
    for i = 1, count do
        -- #((get xray_item for XrayUI))
        xray_item = DX.vd.items[i]
        short_names = has_text(xray_item.short_names)
        xray_name = xray_item.name
        names = short_names and KOR.strings:split(short_names, ", *") or { xray_name }

        --* for case insensitive matching:
        local lower_text = KOR.strings:lower(page_or_paragraph_text)
        names_count = #names
        for nr = 1, names_count do
            xname = names[nr]
            hit_found = self:matchNameInPageOrParagraph(page_or_paragraph_text, lower_text, xname, hits, partial_hits, explanations, xray_item, nr)
            if hit_found then
                a_name_matched = true
                break
            end
            if has_text(xray_item.aliases) then
                alias_match_found = self:matchAliasesToParagraph(page_or_paragraph_text, hits, explanations, xray_item)
                if alias_match_found then
                    an_alias_matched = true
                    break
                end
            end
        end
    end

    local skip_items = {}
    if (a_name_matched or an_alias_matched) then

        hits, explanations = self:reduceParagraphHits(hits, partial_hits, explanations)

        hits, explanations, skip_items = self:removePartialHitsIfFullNameHitFound(hits, explanations, partial_hits)
    end

    if #hits == 0 then
        return
    end
    return hits, explanations, skip_items
end

--- @private
function XrayUI:matchAliasesToParagraph(paragraph, book_hits, explanations, item)
    local aliases = item.aliases
    local alias_table = DX.m:splitByCommaOrSpace(aliases)
    local alias
    count = #alias_table
    for i = 1, count do
        alias = alias_table[i]
        if paragraph:match(alias) then
            self:registerParagraphMatch(book_hits, explanations, item, self.separator .. DX.tw.match_reliability_indicators.alias .. " " .. alias)
            item.reliability_indicator = DX.tw.match_reliability_indicators.alias
            return true
        end
    end
    return false
end

--* loop with all xray items through this function:
--- @private
function XrayUI:matchNameInPageOrParagraph(text, lower_text, needle, hits, partial_hits, explanations, item)
    local xray_name = item.name
    local has_family_name = needle:match(" ")
    local is_single_word = not has_family_name
    local is_lower_case = not xray_name:match("[A-Z]")
    local name_parts = KOR.strings:split(needle, " ")
    local family_name
    local multiple_parts_count = 0
    if has_family_name and not is_lower_case then
        family_name = name_parts[#name_parts]
    end

    local matcher = needle:gsub("%-", "%%-")
    local plural_matcher
    if not matcher:match("s$") then
        plural_matcher = matcher .. "s"
    end

    if KOR.strings:hasWholeWordMatch(text, lower_text, matcher) or (plural_matcher and KOR.strings:hasWholeWordMatch(text, lower_text, plural_matcher))
    then
        --* for full name hits don't add the xray_needle to the explanation, that would lead to stupid repetion of the full name:
        self:registerParagraphMatch(hits, explanations, item, self.separator .. DX.tw.match_reliability_indicators.full_name)
        item.reliability_indicator = DX.tw.match_reliability_indicators.full_name

        -- #((log family name))
        if has_family_name and not is_lower_case then
            self.families_matched_by_multiple_parts[family_name] = 0
            partial_hits[xray_name] = 0
            return true, 2
        end
        return true, 1
    end

    --* for lowercase words and words without spaces we don't match by word parts:
    if is_lower_case or is_single_word then
        return false, 0
    end

    local subject = matcher or needle
    --* when items have uppercase characters, remove lowercase words from them; e.g. remove "of" from "Constitorial Court of Discpline", which gives many false positives in texts:
    if subject:match("[A-Z]") then
        subject = subject:gsub(" [a-z]+ ", " ")
    end
    local mparts = matcher and KOR.strings:split(subject, " ")
    local match_found, left_side_match_found, right_side_match_found = false, false, false
    local matching_parts = ""
    local part
    count = #name_parts
    for nr = 1, count do
        part = name_parts[nr]
        --* lower case needles must be at least 4 characters long, but for names with upper case characters in them no such condition is required:
        if DX.m:isValidNeedle(part) and KOR.strings:hasWholeWordMatch(text, lower_text, mparts[nr]) then
            match_found = true
            if nr == 1 then
                left_side_match_found = true
            elseif nr == #name_parts then
                right_side_match_found = true
            end
            multiple_parts_count = multiple_parts_count + 1
            matching_parts = matching_parts .. part .. ", "
        end
    end
    if multiple_parts_count > 0 then
        partial_hits[xray_name] = multiple_parts_count
    end

    --* when a full name for a specific family already has been found above, we don't want hits for only their surname; see ((log family name)):
    if self.families_matched_by_multiple_parts[family_name] and multiple_parts_count == 1 then
        return false, 0
    end

    if has_family_name and multiple_parts_count > 1 then
        self.families_matched_by_multiple_parts[family_name] = multiple_parts_count
    end

    if match_found then
        local match_reliability_indicator = DX.tw.match_reliability_indicators.partial_match
        matching_parts = matching_parts:gsub(", $", "")
        if left_side_match_found then
            match_reliability_indicator = DX.tw.match_reliability_indicators.first_name
        elseif right_side_match_found then
            match_reliability_indicator = DX.tw.match_reliability_indicators.last_name
        end
        self:registerParagraphMatch(hits, explanations, item, self.separator .. match_reliability_indicator .. " " .. matching_parts)
        item.reliability_indicator = match_reliability_indicator
    end
    return match_found, multiple_parts_count
end

--- @private
--- @param textviewer TextViewer
function XrayUI:onInfoPopupLoadShowToc(textviewer, headings)
    KOR.registry:unset("toc_info_button_injected")
    --* only show the toc automatically when there are more than 2 xray items:
    if #headings > 2 then
        -- #((call TextViewer TOC))
        --* call ((TextViewer#init)) > ((TextViewer execute after load callback)) > current method > ((TextViewer#showToc)) after a short delay:
        textviewer:showToc()
    end
end

function XrayUI:ReaderHighlightGenerateXrayInformation(pos, mode)

    --* this var, containing texts and hits info, was defined above in ((XrayUI#ReaderViewGenerateXrayInformation)) > ((XrayUI#getXrayItemsFoundInText)) > ((set xray info for paragraphs)):
    local xray_rects = self.xray_page_info_rects
    if xray_rects then
        self.paragraph_texts = xray_rects.paragraph_texts
        local rects = xray_rects.rects
        self.info_extra_button_rows = {}
        local rect
        count = #rects
        for nr = 1, count do
            rect = rects[nr]
            if inside_box(pos, rect) then
                self:showParagraphInformation(xray_rects, nr, mode)
                return true
            end
        end
    end
end

--* remove duplicated hits and hits by incorrect names matching another item's surname
--- @private
function XrayUI:reduceParagraphHits(hits, partial_hits, explanations)
    --* when hits found for families with name and surname, remove all items which only match on surname:
    local reduced = {}
    local reduced_explanations = {}
    local processed_names = {}
    local xray_item, xray_name, first_name_matches_a_surname, has_family_name, family_name, partial_hits_count, multiple_hits_count, skip_partial_match, first_name
    count = #hits
    for nr = 1, count do
        xray_item = hits[nr]

        xray_name = xray_item.name

        first_name_matches_a_surname = false
        has_family_name = xray_name:match(" ") and xray_name:match("[A-Z]")
        family_name = xray_name:gsub("^.+ ", "")
        partial_hits_count = partial_hits[xray_name]
        multiple_hits_count = self.families_matched_by_multiple_parts[family_name]
        skip_partial_match = multiple_hits_count == 0 and partial_hits_count and partial_hits_count > 0
        if not processed_names[xray_name] then
            --* whole name hits must always be kept:
            if multiple_hits_count == 0 and partial_hits_count == 0 then
                table.insert(reduced, xray_item)
                table.insert(reduced_explanations, explanations[nr])
                processed_names[xray_name] = 1

                --* when full name and surname found in a paragraph, e.g. Thomas Carlyle), but also found the single name Carlyle, prevent Carlyle Foster to be counted as a hit:
            elseif not skip_partial_match and partial_hits_count == 1 and has_family_name then
                first_name = DX.m:getRealFirstOrSurName(xray_name)
                if self.families_matched_by_multiple_parts[first_name] then
                    first_name_matches_a_surname = true
                end
            end
            if not first_name_matches_a_surname and (not multiple_hits_count or partial_hits_count) then
                table.insert(reduced, xray_item)
                table.insert(reduced_explanations, explanations[nr])
                processed_names[xray_name] = 1
            end
        end
    end
    return reduced, reduced_explanations
end

--- @private
function XrayUI:registerParagraphMatch(hits, explanations, item, message)
    table.insert(hits, item)
    table.insert(explanations, message)
end

--- @private
function XrayUI:removePartialHitsIfFullNameHitFound(hits, explanations, partial_hits)
    local pruned_collection = {}
    local pruned_explanations = {}
    local is_pruned = false
    local skip_items = {}
    local xray_item, skip_item, xray_name
    for full_fam_name_hit, hit_count in pairs(self.families_matched_by_multiple_parts) do
        --* loop through full name and surname hits:
        if hit_count == 0 then
            count = #hits
            for nr = 1, count do
                xray_item = hits[nr]
                skip_item = false
                xray_name = xray_item.name
                if partial_hits[xray_name] and partial_hits[xray_name] > 0 then
                    local item_fam_name = xray_name:gsub("^.+ ", "")
                    skip_item = item_fam_name == full_fam_name_hit
                    if skip_item then
                        skip_items[xray_name] = 1
                        is_pruned = true
                    end
                end
                if not skip_item then
                    table.insert(pruned_collection, xray_item)
                    table.insert(pruned_explanations, explanations[nr])
                end
            end
        end
    end
    if is_pruned then
        return pruned_collection, pruned_explanations, skip_items
    end

    return hits, explanations, {}
end

--- @private
function XrayUI:setParagraphsFromDocument()

    --! hotfix: ui_page not updated anymore after visiting a page two or more times:
    local ui_page = KOR.document and KOR.document.start_page_no or 1

    --* KOR.document.getPageXPointer not available in pdf's and paragraphs not determined in that case:
    if not KOR.document or not KOR.document.getPageXPointer then
        self.paragraphs = {}
        return ui_page
    end

    --* before drawing sideline icons, first expand them with clickable xray item marks (lightning)....
    --* populated in ((CreDocument#storeCurrentPageParagraphs)):
    --! it's essential to reload this info from KOR.document; otherwise after tap on xray marker line and going back to the reader, the paragraphs info is lost and no sideline icon drawn:
    --? because information only generated on first page load?:
    self.paragraphs = KOR.document.paragraphs or {}

    local check_page = KOR.document.info.has_pages and self.ui.paging.current_page or self.ui:getCurrentPage()

    if ui_page == check_page and #self.paragraphs > 0 then
        return ui_page
    end

    if ui_page ~= check_page then
        ui_page = check_page
        local page_xp = KOR.document:getPageXPointer(ui_page)
        KOR.document:storeCurrentPageParagraphs(page_xp, ui_page)

        self.paragraphs = KOR.document.paragraphs
        --* generated from self.paragraphs; self.paragraphs populated in ((XrayUI#setParagraphsFromDocument)) > ((CreDocument#storeCurrentPageParagraphs)) above:
        self.page_text = self:getFullPageText()
    end

    --* if something went wrong while indexing paragraphs, or when we have an inspirational book and xray info is not important:
    if not self.paragraphs or #self.paragraphs == 0 then
        self.paragraphs = {}
        return ui_page
    end

    return ui_page
end

function XrayUI:getCurrentPage()
    if KOR.document.info.has_pages and KOR.view.paging then
        return KOR.view.paging.current_page
    elseif not KOR.document.info.has_pages then
        return KOR.document:getCurrentPage()
    end
end

return XrayUI
