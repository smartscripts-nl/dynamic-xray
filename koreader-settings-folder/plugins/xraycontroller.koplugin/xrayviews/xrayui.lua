
--* see ((Dynamic Xray: module info)) for more info

local require = require

local Device = require("device")
local Font = require("ui/font")
local KOR = require("extensions/kor")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = Device.screen
local T = require("ffi/util").template

local DX = DX
local has_no_items = has_no_items
local has_no_text = has_no_text
local math_floor = math.floor
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber

local count, count2

local function inside_box(pos, box)
    if not pos then
        return false
    end
        local x, y = pos.x, pos.y
    return box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y
end

--- @class XrayUI
local XrayUI = WidgetContainer:new{
    book_needles_string = nil,
    cached_dims = {},
    cached_markers = nil,
    forbidden_words = {
        Look = 1,
        This = 1,
        Thou = 1,
    },
    hits = {},
    info_extra_button_rows = {},
    info_use_upper_case_names = false,
    marker_padding = Screen:scaleBySize(10),
    page = nil,
    page_text = nil,
    paragraph_explanations = nil,
    paragraph_hits = nil,
    paragraphs = nil,
    paragraphs_with_matches = nil,
    paragraph_texts = nil,
    rects_with_matches = nil,
    return_to_caller_callback = nil,
    screen_width = nil,
    separator = " " .. KOR.icons.arrow_bare .. " ",
    UI_modes = {
        page = {
            subject = " " .. _(" on this page"),
            new_UI_mode = _("PARAGRAPHS"),
            new_trigger = _("a paragraph marked with a star"),
        },
        paragraph = {
            subject = " " .. _(" in this paragraph"),
            new_UI_mode = _("the ENTIRE PAGE"),
            new_trigger = _("the first line marked with a lightning icon"),
        },
    },
    xray_context_props = nil,
    xray_info_found = false,
    xray_item_rects = {},
    xray_page_info_rects = nil,
}

--- @private
function XrayUI:drawMarker(c, rect)
    --* c was populated in ((XrayUI#uiInfoSetContextTable)):
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
        if DX.s.UI_mode == "page" then
            y_pos = y_pos - 7
        end

        --* determine vertical position of Xray page marker icon:
        local marker_height_corrected = c.marker_height + 10
        if DX.s.UI_mode == "page" and DX.s.UI_marker_position == "bottom" then
            y_pos = Screen:getHeight() - c.marker_height - 7 - KOR.footer:getHeight()
        elseif DX.s.UI_mode == "page" and DX.s.UI_marker_position == "middle" then
            y_pos = math_floor(Screen:getHeight() / 2) - marker_height_corrected
        else
            y_pos = y_pos - 5
        end

        marker:paintTo(bb, note_mark_pos_x, y_pos)
        marker_rect = {
            --* we make the rects somewhat wider and higher than the icons, to make them easily tappable:
            x = note_mark_pos_x - self.marker_padding,
            y = y_pos,
            --* these c props were set via ((XrayUI#uiInfoGenerateInformation)) > ((XrayUI#getMarker)) > ((XrayUI#uiInfoSetContextTable)):
            w = c.marker_width + 2 * self.marker_padding,
            h = marker_height_corrected,
        }
    end
    return marker_rect
end

--- @private
function XrayUI:drawXrayItemMarker(c, rect)
    --* c was populated in ((XrayUI#registerAndMarkXrayItemRects)):
    local bb = c.bb
    local marker = c.marker
    marker:paintTo(bb, rect.x, rect.y)

    --* return adapted rect; the additions and subtractions make the markers easier to tap:
    return {
        --* we make the rects somewhat wider and higher than the icons, to make them easily tappable:
        x = rect.x - self.marker_padding,
        y = rect.y - self.marker_padding,
        --* these c props were set via ((XrayUI#uiInfoGenerateInformation)) > ((XrayUI#getMarker)) > ((XrayUI#uiInfoSetContextTable)):
        w = c.marker_width + 2 * self.marker_padding,
        h = c.marker_height + 2 * self.marker_padding,
    }
end

--- @private
function XrayUI:getMarkerIconXpos(c, rect)
    local marker_width = c.marker_width
    local is_xray_page_mode = DX.s.UI_mode == "page"
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
    --* self.ui was set in ((XrayUI#uiInfoGenerateInformation)):
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
function XrayUI:getMarker(bb)
    if not bb then
        return
    end

    if not self.cached_markers then
        local face = "smallinfofont"
        local color = KOR.colors.xray_page_or_paragraph_match_marker
        self.cached_markers = {
            paragraph = TextWidget:new{
                text = KOR.icons.xray_item,
                face = Font:getFace(face, 10),
                fgcolor = color,
                padding = 0,
            },
            page = TextWidget:new{
                text = KOR.icons.lightning_bare,
                face = Font:getFace(face, 18),
                fgcolor = color,
                padding = 0,
            },
            items = TextWidget:new{
                text = KOR.icons.xray_item,
                face = Font:getFace(face, 13),
                fgcolor = color,
                padding = 0,
            },
        }
        -- #((set xray marker size))
        local icon_dims = self.cached_markers["paragraph"]:getSize()
        self.cached_dims["paragraph"] = {
            height = icon_dims.h,
            width = icon_dims.w,
        }

        icon_dims = self.cached_markers["page"]:getSize()
        self.cached_dims["page"] = {
            height = icon_dims.h,
            width = icon_dims.w,
        }

        icon_dims = self.cached_markers["items"]:getSize()
        self.cached_dims["items"] = {
            height = icon_dims.h,
            width = icon_dims.w,
        }
    end

    --* compare ((set xray marker position))

    return self.cached_markers[DX.s.UI_mode],
        self.cached_dims[DX.s.UI_mode].width,
        self.cached_dims[DX.s.UI_mode].height
end

--- @private
function XrayUI:setReturnCallback(xray_rects, nr, mode)
    --* this callback will be called in ((XrayDialogs#closeUiInfoDialog)), where it will set a DialogsQueue entry:
    self.return_to_caller_callback = function()
        self:showParagraphInformation(xray_rects, nr, mode)
    end
end

--- @private
function XrayUI:showParagraphInformation(xray_rects, nr, mode)
    if mode == "hold" then
        local current_epage = self:getCurrentPage()
        DX.pn:showNavigator(current_epage)
        return
    end

    --! this call is crucial to be able to return to the Page Information popup from other dialogs:
    self:setReturnCallback(xray_rects, nr, mode)

    local paragraph_text = self.paragraph_texts[nr]
    local paragraph_hits_names = {}
    local paragraph_hits_names2 = {}
    local paragraph_hits_names3 = {}
    local paragraph_hits_info = {}
    local paragraph_hits_info2 = {}
    local paragraph_hits_info3 = {}
    --* these items were generated via ((init xray sideline markers)) > ((XrayUI#uiInfoGenerateInformation)) > ((XrayUI#uiInfoInitParagraphsData)) > ((XrayUI#uiInfoRegisterHits)) ((XrayUI#getXrayItemsFoundInText)):
    local items = xray_rects.hits[nr]
    --* for consumption in ((XrayDialogs#showUiPageInfo)):
    KOR.registry:set("xray_ui_items", items)
    local paragraph_matches_count
    local xray_explanations = xray_rects.explanations[nr]

    --* hotfix for doubled names, as retrieved by ((XrayUI#getXrayItemsFoundInText)):
    local injected_names = {}
    local injected_nr = 0
    local more_button_added
    count = #items
    KOR.columntexts:initDisplayColumnsCount(count)
    for i = 1, count do
        injected_nr, more_button_added = self:addParagraphInfoItems(
                items,
                i,
                injected_names,
                xray_explanations,
                injected_nr,
                paragraph_hits_names,
                paragraph_hits_info
        )
        if more_button_added then
            break
        end
    end

    local names_separator = "\n"
    local info_separator = "\n\n"

    --* three column text:
    if #paragraph_hits_names >= 3 and DX.s.text_columns == 3 then

        --* prepare columns for the overview tab:
        paragraph_hits_names, paragraph_hits_names2, paragraph_hits_names3 = KOR.columntexts:getThreeColumnTexts(paragraph_hits_names, paragraph_hits_names2, paragraph_hits_names3, names_separator)

        --* prepare columns for the information tab:
        paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3 = KOR.columntexts:getThreeColumnTexts(paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3, info_separator)

    --* two column text:
    elseif #paragraph_hits_names >= 2 and DX.s.text_columns == 2 then
        --* prepare columns for the overview tab:
        --* paragraph_hits_names3 will be nil here:
        paragraph_hits_names, paragraph_hits_names2, paragraph_hits_names3 = KOR.columntexts:getTwoColumnTexts(paragraph_hits_names, paragraph_hits_names2, names_separator)

        --* prepare columns for the information tab:
        paragraph_hits_info, paragraph_hits_info2 = KOR.columntexts:getTwoColumnTexts(paragraph_hits_info, paragraph_hits_info2, info_separator)

    --* one column text:
    else
        --* prepare columns for the overview tab:
        --* paragraph_hits_names2 and paragraph_hits_names3 will be nil here:
        paragraph_hits_names, paragraph_hits_names2, paragraph_hits_names3 = KOR.columntexts:getOneColumnText(paragraph_hits_names, names_separator)

        --* prepare columns for the information tab:
        paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3 = KOR.columntexts:getOneColumnText(paragraph_hits_info, info_separator)
    end

    paragraph_matches_count = injected_nr
    --* correction for indentation of first line in dialog; this should not be necessary:
    paragraph_hits_info = paragraph_hits_info:gsub("^ +", "")

    -- #((xray paragraph info callback))
    --* callback defined in ((set xray info for paragraphs)) > ((XrayUI#uiInfoPopulateRects)) and calls ((XrayDialogs#showUiPageInfo)):
    xray_rects.callback(paragraph_hits_names, paragraph_hits_names2, paragraph_hits_names3, paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3, paragraph_matches_count, paragraph_text)
end

--- @private
function XrayUI:addParagraphInfoItems(items, i, injected_names, xray_explanations, injected_nr, paragraph_hits_names, paragraph_hits_info)
    local more_button_added

    local name = DX.vd:addNonBreakableIndicator(items[i].name, items[i])

    injected_names[name] = name
    injected_nr = injected_nr + 1

    if self.info_use_upper_case_names then
        name = KOR.strings:upper(name)
    end

    --* icon and match explanation were set in ((XrayUI#discoverXrayItems)):
    local match_reliability_icon = items[i].reliability_indicator
    --* only for matches by alias or short name match_explanation will be set:
    local match_explanation = items[i].match_explanation or ""

    local match_block, type_icon = DX.vd:generateXrayExportOrLinkedItemInfo(nil, items[i], xray_explanations[i], injected_nr)
    local fav_indicator = DX.ta:itemHasTag(items[i], _("Favorites")) and KOR.icons.favorite_closed_prefix or ""
    table_insert(paragraph_hits_names, type_icon .. match_reliability_icon .. " " .. name .. fav_indicator .. match_explanation)
    table_insert(paragraph_hits_info, match_block)

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

    return injected_nr, more_button_added
end

--* called from ((ReaderView#paintTo)):
function XrayUI:uiInfoGenerateInformation(ui, bb, x, y)

    self.ui = ui
    self.page = self:setParagraphsFromDocument()
    self.hits = {}
    local marker, marker_width, marker_height = self:getMarker(bb)
    self.xray_page_info_rects = nil
    self:uiInfoSetContextTable(marker, marker_width, marker_height, bb, x, y)

    -- #((set xray info for paragraphs))
    if self:uiInfoInitParagraphsData() and DX.vd:hasUnfilteredItems() then
        --! here callbacks are attached to the marker icon rects:
        self:uiInfoPopulateRects()
        if DX.s.UI_mode == "page" and DX.s.UI_mark_xray_items then
            self:registerAndMarkXrayItemRects(bb)
        end
    end
end

--- @private
--- @return boolean
function XrayUI:uiInfoInitParagraphsData()

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
    self.screen_width = Screen:getWidth()

    if has_no_items(self.paragraphs) or DX.vd:getBaseItemsCount() == 0 then
        return false
    end

    local para_count = #self.paragraphs
    --* when in page mode, this loop will be stopped as soon as a line is found that is long enough to be suitable for adding the xray marker; in this we assume that page_text does indeed have the full page text, so no loop through all paragraphs necessary:
    local do_break
    for p = 1, para_count do
        do_break = self:handleParagraphRegistration(p)
        if do_break then
            self:updateStatusInFooter()
            return self.xray_info_found
        end
    end

    self:updateStatusInFooter()
    return self.xray_info_found
end

--* if returns true, break loop in ((XrayUI#uiInfoInitParagraphsData)):
--- @private
--- @return boolean
function XrayUI:handleParagraphRegistration(p)
    if not self:uiInfoRegisterHits(p) then
        return false
    end

    local hits_marked = self:registerAndMarkRects(p)
    --! "break" in page mode:
    if DX.s.UI_mode == "page" and hits_marked then
        return true
    end

    return false
end

--- @private
function XrayUI:setBookNeedles()
    if self.book_needles_string then
        return
    end

    local needles = {}
    count = #DX.vd.items
    local items_table = DX.vd.items
    count = #items_table

    local xray_item, needle
    for i = 1, count do
        -- #((get xray_item for XrayUI))
        xray_item = items_table[i]
        count2 = #xray_item.needles
        for n = 1, count2 do
            --* remove word start and end markers; e.g. needdle %f[%a]Mistwalkers%f[%A]
            needle = "#" .. xray_item.needles[n].needle:gsub("%%f%[%%[aA]%]", "") .. "#"
            --* these needles will be used for matching in ((XrayUI#getWordPositions)):
            table_insert(needles, needle .. xray_item.id)
        end
    end

    self.book_needles_string = " " .. table_concat(needles, " ") .. " "
end

--- @private
function XrayUI:updateStatusInFooter()
    --* for consumption in footer:
    KOR.registry:set("xray_items_on_page_count", KOR.tables:getTableLength(self.hits))
    --* force update of footer, to show correct number of current Xray items on page:
    KOR.footer:onUpdateFooter()
end

--- @private
function XrayUI:uiInfoSetContextTable(marker, marker_width, marker_height, bb, x, y)
    self.xray_context_props = {
        marker = marker,
        marker_height = marker_height,
        marker_width = marker_width,
        bb = bb,
        x = x,
        y = y,
    }
end

function XrayUI:setMarkerXPosition()
    self.screen_width = Screen:getWidth()
    KOR.registry.half_screen_width = math_floor(self.screen_width / 2)
end

--* see ((XRAY_ITEMS)) for more info:
--- @private
function XrayUI:uiInfoRegisterHits(p)
    local ui_mode = DX.s.UI_mode

    --* self.page_text was set when storing self.paragraphs, in ((XrayUI#setParagraphsFromDocument)) > ((XrayUI#getFullPageText)):
    local haystack = ui_mode == "paragraph" and self.paragraphs[p].text or self.page_text
    local hits, explanations = self:getXrayItemsFoundInText(haystack)
    if not hits then
        return false
    end

    --* for debugging only:
    table_insert(self.paragraphs_with_matches, self.paragraphs[p].text)
    --* to be consumed in ((XrayUI#uiInfoShow)):
    table_insert(self.paragraph_hits, hits)
    table_insert(self.paragraph_explanations, explanations)
    self:registerHits(hits)

    return true
end

--- @private
function XrayUI:registerAndMarkXrayItemRects(bb)

    --* paragraphs[1] only starts with text on current page:
    if not self.paragraphs[1] then
        return
    end

    local c = {
        bb = bb,
        --* these cached marker_props are set in ((XrayUI#getMarker)):
        marker = self.cached_markers["items"],
        marker_width = self.cached_dims["items"].width,
        marker_height = self.cached_dims["items"].height,
    }

    --* some of these props have to be reset for every new page, via ((XrayUI#reset)):
    self:setBookNeedles()

    --* page_words here already are filtered on having a hit:
    local page_words_with_hits = self:getWordPositions(self.paragraphs[1].pos0)
    if has_no_items(page_words_with_hits) then
        return
    end
    count = #page_words_with_hits

    --* page_word has props word and position:
    local page_word, rect, posx, posy

    for i = 1, count do
        page_word = page_words_with_hits[i]
        posy, posx = KOR.document:getScreenPositionFromXPointer(page_word.position)

        c.y = posy - Screen:scaleBySize(8)
        c.x = posx - Screen:scaleBySize(5)
        rect = { x = c.x, y = c.y, w = c.marker_width, h = c.marker_height }
        rect = self:drawXrayItemMarker(c, rect)
        table_insert(self.xray_item_rects, {
            rect = rect,
            id = page_word.id,
        })

        --* handling of taps on XrayItemMarkers in ((ReaderHighlight#onTapOnXrayItemMarker))...
    end
end

--- @private
function XrayUI:addWordPosition(word_positions, start_pos, end_pos)
    local word = KOR.document:getTextFromXPointers(start_pos, end_pos)
    word = self:cleanupWordPositionWords(word)
    if not word then
        return
    end

    --* self.book_needles_string was generated in ((XrayUI#setBookNeedles)):
    --* the id's retrieved in current method will be used for showing the items in ((ReaderHighlight#onTapOnXrayItemMarker)):
    local item_id = self.book_needles_string:match("#" .. word:gsub("-", "%%-") .. "#(%d+)")
    if item_id then
        table_insert(word_positions, {
            id = tonumber(item_id),
            position = end_pos,
        })
    end
end

--- @private
function XrayUI:getWordPositions(pos0)

    --* self.book_needles_string used for matching below was generated in ((XrayUI#setBookNeedles))

    --? for some reason real current_page mostly not to be got in CreDocent for some reason, so we let ((XrayUI#registerAndMarkXrayItemRects)) deliver a pos0 derived from XrayUI.paragraphs[1].pos0 and compute the real current page from that:
    local current_page = KOR.document:getPageFromXPointer(pos0)
    local word_positions = {}
    local pos1 = KOR.document:getNextVisibleWordStart(pos0)
    local is_last_page = current_page == KOR.document:getPageCount()

    if KOR.document:getPageFromXPointer(pos1) ~= current_page then
        return
    end

    local pos0_next = pos1
    pos1 = KOR.document:getPrevVisibleChar(pos1)
    self:addWordPosition(word_positions, pos0, pos1)

    pos0 = pos0_next
    pos1 = KOR.document:getNextVisibleWordStart(pos0)

    local max_tries = 800
    local current_try = 0
    while KOR.document:getPageFromXPointer(pos1) == current_page do
        pos0_next = pos1
        pos1 = KOR.document:getPrevVisibleChar(pos1)
        self:addWordPosition(word_positions, pos0, pos1)

        pos0 = pos0_next
        pos1 = KOR.document:getNextVisibleWordStart(pos0_next)

        if is_last_page then
            current_try = current_try + 1
            if current_try == max_tries then
                break
            end
        end
    end

    if is_last_page then
        return word_positions
    end

    if KOR.document:getPageFromXPointer(pos0) == current_page then
        pos1 = KOR.document:getPrevVisibleChar(pos1)
        self:addWordPosition(word_positions, pos0, pos1)
    end

    --* these word_postions will now be used for generating rects in ((XrayUI#registerAndMarkXrayItemRects)):
    return word_positions
end

--- @private
function XrayUI:cleanupWordPositionWords(word)

    --* prevent hits by name parts like "of" or "for":
    if not word:match("[A-Z]") and word:len() <= 3 then
        return
    end

    return word
        --* to make matching in ((XrayUI#registerAndMarkXrayItemRects)) find more hits:
        :gsub("[,.:;?!+()%[%]%% ]", "")
        :gsub("‘", "")
        :gsub("“", "")
        :gsub("’.-$", "")
        :gsub("”.-$", "")
        --* remove plurals:
        :gsub("s$", "")
end

--- @private
function XrayUI:uiInfoPopulateRects()
    -- #((set xray page info rects))
    --* to be consumed in ((XrayUI#uiInfoShow)) > ((XrayUI#showParagraphInformation)):
    self.xray_page_info_rects = {
        paragraph_texts = self.paragraphs_with_matches,
        hits = self.paragraph_hits,
        explanations = self.paragraph_explanations,
        rects = self.rects_with_matches,
        --* paragraph_hits_info was generated in ((XrayUI#addParagraphInfoItems)):
        callback = function(paragraph_names, paragraph_names2, paragraph_names3, paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3, paragraph_text)

            if DX.s.UI_mode == "page" and DX.s.UI_marker_callback == "page_navigator" then
                DX.c:showPageNavigator()
                return
            end

            --* paragraph_text only needed for debugging purposes, to ascertain we are looking at the correct paragraph:
            DX.d:showUiPageInfo(paragraph_names, paragraph_names2, paragraph_names3, paragraph_hits_info, paragraph_hits_info2, paragraph_hits_info3, paragraph_text)
        end,
        hold_callback = function()
            if DX.s.UI_mode == "page" and DX.s.UI_marker_callback == "page_information_popup" then
                DX.c:showPageNavigator()
                return
            end
        end,
    }
end

--- @private
function XrayUI:registerHits(hits)
    local name
    count = #hits
    for xi = 1, count do
        name = hits[xi].name
        if not self.hits[name] then
            self.hits[name] = 1
            self.xray_info_found = true
        end
    end
end

--- @private
function XrayUI:registerAndMarkRects(p)
    --* this context table with props was set in ((set xray info for paragraphs)) > ((XrayUI#uiInfoSetContextTable)):
    local c = self.xray_context_props
    if not c.bb then
        return false
    end

    -- #((set half screen width))
    if not KOR.registry.half_screen_width then
        self:setMarkerXPosition()
    end
    local rect, icon_is_drawn, fallback_line = self:getMarkerYPosition(p)
    if not icon_is_drawn and fallback_line then
        rect = fallback_line
    end
    return self:drawMarkerIfDetermined(c, rect)
end

--- @private
function XrayUI:drawMarkerIfDetermined(c, rect)
    if not rect then
        return false
    end

    --* hotfix: on Boox Page rect and xray marker were sometimes incorrectly drawn on the right half of the screen:
    local marker_rect = self:drawMarker(c, rect)
    if marker_rect then
        table_insert(self.rects_with_matches, marker_rect)
    end
    return true
end

--- @private
function XrayUI:getMarkerYPosition(p)
    local lines = KOR.document:getScreenBoxesFromPositions(self.paragraphs[p].pos0, self.paragraphs[p].pos1, true)
    local lines_count = #lines
    -- #((xray page marker set target line for icon))
    local start = 1

    local current_column, fallback_line, rect
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
            return rect, icon_is_drawn, fallback_line
        end
    end
end

--- @private
function XrayUI:getCurrentColumn(x)
    return KOR.ui.document:getVisiblePageCount() > 1 and x > KOR.registry.half_screen_width and 2 or 1
end

--* content of self.paragraphs was generated in ((PageTexts#getAllHtmlContainersInPage)):
--- @private
function XrayUI:getFullPageText()
    if not self.paragraphs then
        return ""
    end
    return KOR.tables:concatField(self.paragraphs, "text", "\n")
end

--* these hits are to be consumed in ((XrayUI#uiInfoShow)) > ((XrayDialogs#showUiPageInfo))
--- @private
function XrayUI:getXrayItemsFoundInText(page_or_paragraph_text, tagged_items)

    local hits, explanations = self:discoverXrayItems(page_or_paragraph_text, tagged_items)

    if #hits == 0 then
        return
    end

    DX.pn:cacheReliabilityIndicators(hits)

    return hits, explanations
end

--- @private
function XrayUI:discoverXrayItems(page_or_paragraph_text, tagged_items)
    local items_found, explanations = {}, {}

    local xray_item, needle_props, needle, hit
    local subject = tagged_items or DX.vd.items
    --* we need to do this because we assign item_indicators to the items found per page or paragraph (see below: xray_item.reliability_indicator = needle.reliability_indicator):
    local items_table = KOR.tables:shallowCopy(subject)
    count = #items_table
    for i = 1, count do
        -- #((get xray_item for XrayUI))
        xray_item = items_table[i]
        count2 = #xray_item.needles
        for n = 1, count2 do
            needle_props = xray_item.needles[n]
            needle = needle_props.needle
            hit = page_or_paragraph_text:match(needle)
            if hit then
                --* first two props for consumption in
                xray_item.reliability_indicator = needle_props.reliability_indicator
                --* only for aliases and short names show an explanation of the match:
                xray_item.match_explanation = needle_props.reliability_indicator == KOR.icons.xray_alias_bare and " (" .. hit .. ")"
                table_insert(items_found, xray_item)
                table_insert(explanations, needle_props.explanation)
                break
            end
        end
    end

    return items_found, explanations
end

function XrayUI:uiInfoShow(pos, mode)

    if not self.xray_page_info_rects then
        return
    end

    --* this var, containing texts and hits info, was defined above in ((XrayUI#uiInfoGenerateInformation)) > ((XrayUI#getXrayItemsFoundInText)) > ((set xray info for paragraphs)):
    local xray_rects = self.xray_page_info_rects
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

--- @private
function XrayUI:setParagraphsFromDocument()

    --! hotfix: ui_page not updated anymore after visiting a page two or more times:
    local ui_page = KOR.document and KOR.document.start_page_no or 1

    --* KOR.document.getPageXPointer not available in pdf's and paragraphs not determined in that case:
    if not KOR.document or KOR.document.info.has_pages or not KOR.document.getPageXPointer then
        return ui_page
    end

    local check_page = self.ui:getCurrentPage()

    --! always retrieve page_text, for usage with VocabBuilder !!!:
    --* self.page_text can be reset by ((XrayUI#reset)):
    if ui_page ~= check_page or not self.page_text then -- DX.s.UI_mode == "pages" and
        self.page_text = KOR.document:getPageText(ui_page, "keep_hyphens")
    end

    --* in ui_mode "pages" we don't have to index every paragraph on the page:
    if DX.s.UI_mode == "pages" then
        return ui_page
    end

    --* before drawing sideline icons, first expand them with clickable xray item marks (lightning)....
    --* populated in ((CreDocument#storeCurrentPageParagraphs)):
    --! it's essential to reload this info from KOR.document; otherwise after tap on xray marker line and going back to the reader, the paragraphs info is lost and no sideline icon drawn:
    --? because information only generated on first page load?:
    self.paragraphs = KOR.document.paragraphs or {}

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

function XrayUI:reset()
    self.paragraphs = {}
    self.hits = {}
    self.info_extra_button_rows = {}
    self.paragraph_hits = nil
    self.paragraph_texts = nil
    self.paragraphs_with_matches = nil
    self.page_text = nil
    self.rects_with_matches = nil
    self.xray_page_info_rects = nil
    self.xray_items = nil
    self.xray_context_props = nil
    self.xray_info_found = false
    self.xray_item_rects = {}
end

--* only called upon opening a new ebook:
function XrayUI:resetBookNeedlesString()
    self.book_needles_string = nil
end

--- @param parent XrayDialogs
function XrayUI:toggleUiMode(parent, new_mode, new_trigger)
    local question = T(_([[Do you indeed want to toggle the Xray information display mode to %1?]]), new_mode, new_trigger)
    KOR.dialogs:confirm(question, function()
        DX.s:toggleSetting("UI_mode", { "page", "paragraph" })
        if parent then
            parent:closeUiInfoDialog()
        end
        UIManager:setDirty(nil, "full")
    end)
end

--- @param parent XrayDialogs
function XrayUI:toggleUiXrayItemMarkers(parent)
    DX.s:toggleBoolSetting("UI_mark_xray_items")
    local state = DX.s.UI_mark_xray_items and "ingeschakeld" or "uitgeschakeld"
    KOR.messages:notify("xray item-markers " .. state)
    if parent then
        parent:closeUiInfoDialog()
    end
    UIManager:setDirty(nil, "full")
end

return XrayUI
