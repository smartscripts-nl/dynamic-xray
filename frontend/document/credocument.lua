local CanvasContext = require("document/canvascontext")
local Document = require("document/document")
local KOR = require("extensions/kor")
local cre -- Delayed loading

-- [...]

--- @class CreDocument
local CreDocument = Document:extend{
    -- [...]

    _document = false,
    -- SmartScripts: hotfix:
    _global_call_cache = {},

    -- [...]

    paragraphs = {},
}

-- [...]

function CreDocument:getXPointer()
    if not self._document then
        self:setDocument()
    end
    local xp = self._document:getXPointer()
    self:storeCurrentPageParagraphs(xp)
    return xp
end

-- [...]

-- ======================= ADDED ======================

function CreDocument:setDocument()
    local ok
    ok, self._document = pcall(cre.newDocView, CanvasContext:getWidth(), CanvasContext:getHeight(), self._view_mode)
    if not ok then
        error(self._document)  -- will contain error message
    end
end

function CreDocument:expandToParagraphEnd(paragraph, sel_end, element_number)
    local next_word_position = self:getNextVisibleWordStart(sel_end)
    while KOR.xrayhelpers:getHtmlElementIndex(next_word_position) == element_number and self:getPageFromXPointer(next_word_position) == self.start_page_no do
        --
        sel_end = next_word_position
        next_word_position = self:getNextVisibleWordStart(next_word_position)
    end
    local next_paragraph_position = next_word_position
    if self:getPageFromXPointer(next_paragraph_position) == self.start_page_no then
        self.next_paragraph_position = next_paragraph_position
    else
        self.next_paragraph_position = nil
    end
    local next_char_position = self:getNextVisibleChar(sel_end)
    while KOR.xrayhelpers:getHtmlElementIndex(next_char_position) == element_number and self:getPageFromXPointer(next_char_position) == self.start_page_no do
        --
        sel_end = next_char_position
        next_char_position = self:getNextVisibleChar(next_char_position)
    end
    paragraph.pos1 = sel_end
    paragraph.text = self:getTextFromXPointers(paragraph.pos0, paragraph.pos1)
end

-- populates self.paragraphs, to be used in ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation)):
function CreDocument:storeCurrentPageParagraphs(page_xp, starting_page)

    self.paragraphs = {}
    self.start_page_no = starting_page or self:getPageFromXPointer(page_xp)
    local element_number = KOR.xrayhelpers:getHtmlElementIndex(page_xp)
    local paragraph = {
        pos0 = page_xp,
        pos1 = page_xp,
        text = "",
    }
    self:expandToParagraphEnd(paragraph, page_xp, element_number)
    KOR.xrayhelpers:paragraphCleanForXrayMatching(paragraph)
    table.insert(self.paragraphs, paragraph)
    while self.next_paragraph_position do
        element_number = KOR.xrayhelpers:getHtmlElementIndex(self.next_paragraph_position)
        paragraph = {
            pos0 = self.next_paragraph_position,
            pos1 = self.next_paragraph_position,
            text = "",
        }
        self:expandToParagraphEnd(paragraph, self.next_paragraph_position, element_number)
        if paragraph.text then
            -- remove html tags and reading signs, for more accurate matching:
            KOR.xrayhelpers:paragraphCleanForXrayMatching(paragraph)
            table.insert(self.paragraphs, paragraph)
        end
    end
end

-- sel_end will be initially page_xp when called from ((CreDocument#storeCurrentPageParagraphs)):
function CreDocument:expandToEntireParagraph(sel_start, sel_end)
    if not sel_end then
        sel_end = sel_start
    end
    local element_number = KOR.xrayhelpers:getHtmlElementIndex(sel_end)
    if not element_number then
        return {
            pos0 = sel_start,
            pos1 = sel_end,
            text = "",
        }, nil -- for usage with CreDocument we try to return the element_number of sel_start
    end

    -- set sel_start to start of paragraph, even if that is situated on previous page:
    sel_start = sel_start
            :gsub("%[%d+%]%.%d+$", "[1].0")
            :gsub("text%(%)%.%d+$", "text().0")
    local start_element_number = KOR.xrayhelpers:getHtmlElementIndex(sel_start)

    local validated_sel_end = sel_end
    local next_para_index = element_number + 1
    local next_para_pos = sel_end
            :gsub("%[" .. element_number .. "%]/text%(%)", "[" .. next_para_index .. "]/text()")
            :gsub("%.%d+$", ".0")
            :gsub("%[%d+%]%.%d+$", "[1].0")

    -- info: next para DOES exist inside current doc section:
    local page_no = self:getPageFromXPointer(next_para_pos)
    if page_no and self.start_page_no and page_no >= self.start_page_no then
        self.next_paragraph_position = next_para_pos
        sel_end = self:getPrevVisibleWordEnd(next_para_pos)
        validated_sel_end = self:expandSelectionToPunctuationMarks(element_number, sel_end)
        validated_sel_end = self:removeEndNoteMarkerFromSelection(sel_start, validated_sel_end)

        return {
            pos0 = sel_start,
            pos1 = validated_sel_end,
            text = self:getNotelessText(sel_start, validated_sel_end),
        }, start_element_number
    end

    -- info: next para DOESNOT exist inside current doc section:
    self.next_paragraph_position = nil

    local next_word_position = self:getNextVisibleWordStart(sel_end)

    while KOR.xrayhelpers:getHtmlElementIndex(next_word_position) == element_number do
        sel_end = next_word_position
        validated_sel_end = sel_end
        next_word_position = self:getNextVisibleWordStart(next_word_position)
    end

    validated_sel_end = self:expandSelectionToPunctuationMarks(element_number, validated_sel_end)

    return {
        pos0 = sel_start,
        pos1 = validated_sel_end,
        text = self:getNotelessText(sel_start, validated_sel_end),
    }, start_element_number
end

function CreDocument:expandSelectionToPunctuationMarks(element_number, validated_sel_end)

    local sel_end = validated_sel_end
    local next_char_position = self:getNextVisibleChar(sel_end)
    -- don't include notes at end of paragraph:
    if self:isNoteMarker(sel_end, next_char_position) then
        return sel_end
    end

    while KOR.xrayhelpers:getHtmlElementIndex(next_char_position) == element_number do
        sel_end = next_char_position
        validated_sel_end = sel_end
        next_char_position = self:getNextVisibleChar(next_char_position)
        -- don't include notes at end of paragraph:
        if self:isNoteMarker(sel_end, next_char_position) then
            return validated_sel_end
        end
    end
    return validated_sel_end
end

function CreDocument:getNotelessText(sel_start, sel_end)
    local text = self:getTextFromXPointers(sel_start, sel_end)
    return KOR.strings:removeNotes(text)
end

function CreDocument:isNoteMarker(sel_end, next_char_position)
    local next_char_text = self:getTextFromXPointers(sel_end, next_char_position)
    return next_char_text:match("%d")
end

function CreDocument:removeEndNoteMarkerFromSelection(sel_start, sel_end)
    local text = self:getTextFromXPointers(sel_start, sel_end)
    while text:match("%d$") do
        sel_end = self:getPrevVisibleChar(sel_end)
        text = self:getTextFromXPointers(sel_start, sel_end)
    end
    return sel_end
end

return CreDocument
