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

-- sel_end will be initially page_xp when called from ((CreDocument#storeCurrentPageParagraphs)):
function CreDocument:expandToEntireParagraph(sel_end, element_number)

    if not element_number then
        return {
            pos0 = sel_end,
            pos1 = sel_end,
            text = "",
        }
    end

    -- set sel_start to start of paragraph, even if that is situated on previous page:
    local sel_start = sel_end
            :gsub("%[%d+%]%.%d+$", "[1].0")

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

        return {
            pos0 = sel_start,
            pos1 = validated_sel_end,
            text = self:getNotelessText(sel_start, validated_sel_end),
        }
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
    }
end

function CreDocument:expandSelectionToPunctuationMarks(element_number, validated_sel_end)

    local sel_end = validated_sel_end
    local next_char_position = self:getNextVisibleChar(sel_end)

    while KOR.xrayhelpers:getHtmlElementIndex(next_char_position) == element_number do
        sel_end = next_char_position
        validated_sel_end = sel_end
        next_char_position = self:getNextVisibleChar(next_char_position)
    end
    return validated_sel_end
end

function CreDocument:getNotelessText(sel_start, sel_end)
    local text = self:getTextFromXPointers(sel_start, sel_end)
    return KOR.strings:removeNotes(text)
end

-- populates self.paragraphs, to be used in ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation)):
function CreDocument:storeCurrentPageParagraphs(page_xp, starting_page)

    self.paragraphs = {}
    self.start_page_no = starting_page or self:getPageFromXPointer(page_xp)
    local element_number = KOR.xrayhelpers:getHtmlElementIndex(page_xp)

    local paragraph = self:expandToEntireParagraph(page_xp, element_number)
    paragraph.full_text = paragraph.text
    paragraph.element_no = element_number

    KOR.xrayhelpers:paragraphCleanForXrayMatching(paragraph)
    table.insert(self.paragraphs, paragraph)

    while self.next_paragraph_position do
        element_number = KOR.xrayhelpers:getHtmlElementIndex(self.next_paragraph_position)
        paragraph = self:expandToEntireParagraph(self.next_paragraph_position, element_number)
        paragraph.full_text = paragraph.text
        paragraph.element_no = element_number
        if paragraph.text then
            -- remove html tags and punctuation marks, for more accurate matching:
            KOR.xrayhelpers:paragraphCleanForXrayMatching(paragraph)
            table.insert(self.paragraphs, paragraph)
        end
    end
end

function CreDocument:getParagraphProps(xp)
    if not xp then
        return
    end
    local element_no = KOR.xrayhelpers:getHtmlElementIndex(xp)
    for p = 1, #self.paragraphs do
        local para = self.paragraphs[p]
        if para.element_no == element_no then
            -- info: make sure we select the real start of the html element (most often a paragraph), event if the element starts on a previous page:
            para.pos0 = para.pos0:gsub("%d+$", "0")
            return para.pos0, para.pos1, para.full_text, p
        end
    end
end

return CreDocument
