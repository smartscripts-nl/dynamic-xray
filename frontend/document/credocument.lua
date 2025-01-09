local CanvasContext = require("document/canvascontext")
local Document = require("document/document")
local Strings = require("extensions/strings")
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

function CreDocument:_getHtmlElementIndex(index)
    if not index then
        return 1
    end
    -- bookmark / highlight positions have this format:
    -- "/body/DocFragment[12]/body/p[179]/text().157"
    -- so second number in line is the current HTML element
    index = index:gsub("^.+body/", "")
    index = index:match("[0-9]+")

    return tonumber(index)
end

function CreDocument:expandToParagraphEnd(paragraph, sel_end, element_number)
    local next_word_position = self:getNextVisibleWordStart(sel_end)
    while self:_getHtmlElementIndex(next_word_position) == element_number and self:getPageFromXPointer(next_word_position) == self.start_page_no do --
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
    while self:_getHtmlElementIndex(next_char_position) == element_number and self:getPageFromXPointer(next_char_position) == self.start_page_no do --
        sel_end = next_char_position
        next_char_position = self:getNextVisibleChar(next_char_position)
    end
    paragraph.pos1 = sel_end
    paragraph.text = self:getTextFromXPointers(paragraph.pos0, paragraph.pos1)
end

-- populates self.paragraphs, to be used in ((ReaderView#paintTo)) > ((XrayHelpers#ReaderViewGenerateXrayInformation)):
function CreDocument:storeCurrentPageParagraphs(xp, starting_page)

    self.paragraphs = {}
    self.start_page_no = starting_page or self:getPageFromXPointer(xp)
    local element_number = self:_getHtmlElementIndex(xp)
    local paragraph = {
        pos0 = xp,
        pos1 = xp,
        text = "",
    }
    self:expandToParagraphEnd(paragraph, xp, element_number)
    self:paragraphCleanForXrayMatching(paragraph)
    table.insert(self.paragraphs, paragraph)
    while self.next_paragraph_position do
        element_number = self:_getHtmlElementIndex(self.next_paragraph_position)
        paragraph = {
            pos0 = self.next_paragraph_position,
            pos1 = self.next_paragraph_position,
            text = "",
        }
        self:expandToParagraphEnd(paragraph, self.next_paragraph_position, element_number)
        if paragraph.text then
            -- remove html tags and reading signs, for more accurate matching:
            self:paragraphCleanForXrayMatching(paragraph)
            table.insert(self.paragraphs, paragraph)
        end
    end
end

function CreDocument:paragraphCleanForXrayMatching(paragraph)
    -- matching on these texts afterwards performed in ((XrayHelpers#matchNameInPageOrParagraph)) > ((XrayHelpers#isFullWordMatch)) > ((Strings#wholeWordMatch)):
    if paragraph and paragraph.text then
        paragraph.text = paragraph.text
            :gsub("<[^>]+>", "")
            :gsub("[-.,!?:;()]", "")
            :gsub(Strings.curly_apo_l, "")
            :gsub(Strings.curly_apo_r, "")
            :gsub(Strings.curly_quote_l, "")
            :gsub(Strings.curly_quote_r, "")
            :gsub("\n", " \n")
            --remove footnote numbers:
            :gsub("([a-z])%d+ ", "%1 ")
    end
end

return CreDocument
