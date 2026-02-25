
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local has_text = has_text
local math_max = math.max
local math_min = math.min
local string = string
local table = table
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local tonumber = tonumber

local count

--- @class PageTexts
local PageTexts = WidgetContainer:extend{
    current_elem_no = nil,
    paragraph_end = nil,
    paragraph_start = nil,
    start_elem_no = nil,
    start_page_no = nil,
}

function PageTexts:countItemOccurrences(text, needles)

    local total_count = 0
    local rcount
    for i = 1, #needles do
        text, rcount = text:gsub("%f[%w_]" .. needles[i] .. "%f[^%w_]", "")
        total_count = total_count + rcount
    end

    return total_count
end

function PageTexts:getAllHtmlContainersInPage(page_xp, start_page_no, include_punctuation, toc_title_condition)
    local containers = {}
    local texts = {}
    local pos = page_xp
    self.start_page_no = start_page_no
    self.current_elem_no = self:getHtmlElementIndex(pos)
    self.start_elem_no = self.current_elem_no

    local exclude_current_chapter = toc_title_condition and toc_title_condition:match("^%-%-%-")
    if exclude_current_chapter then
        toc_title_condition = toc_title_condition:gsub("^%-%-%-", "")
    end

    --* guard clause: no element found:
    if not self.current_elem_no then
        return containers
    end

    local in_current_page, toc_title
    while true do
        self.paragraph_start = pos
        self.paragraph_end = pos

        --* loop through words until we reach a new element (next paragraph):
        self:loopThroughContainerWords(include_punctuation)
        if not self.paragraph_end then
            break
        end
        if
            not toc_title_condition
            or not exclude_current_chapter and toc_title == toc_title_condition
            or exclude_current_chapter and toc_title ~= toc_title_condition
        then
            self:addContainerToContainers(containers, texts)
        end
        if toc_title_condition then
            toc_title = KOR.toc:getTocTitleByPage(self.paragraph_start)
        end

        --* advance to next paragraph:
        pos = KOR.document:getNextVisibleWordEnd(self.paragraph_end)
        if not pos then
            break
        end

        self.current_elem_no = self:getHtmlElementIndex(pos)
        in_current_page = KOR.document:getPageFromXPointer(pos) == start_page_no
        if not in_current_page then
            break
        end
    end

    --! return paragraphs to CreDocument, where it will be stored in self.paragraphs for the current page!:
    return containers, texts
end

--* this method should set self.paragraph_end (or not), to be used in ((PageTexts#getAllHtmlContainersInPage)):
--- @private
function PageTexts:loopThroughContainerWords(include_punctuation)
    local next_word_end, next_elem_no, in_current_page
    local add_text_by = "word"
    while true do
        if add_text_by == "word" then
            next_word_end = KOR.document:getNextVisibleWordEnd(self.paragraph_end)
        else
            next_word_end = KOR.document:getNextVisibleChar(self.paragraph_end)
        end

        if not next_word_end and include_punctuation and add_text_by == "word" then
            add_text_by = "char"
            next_word_end = KOR.document:getNextVisibleChar(self.paragraph_end)
        end

        if not next_word_end then
            self:setParagraphStart()
            --* we're ready looping through this container, so break out of the loop:
            return
        end

        next_elem_no = self:getHtmlElementIndex(next_word_end)
        in_current_page = KOR.document:getPageFromXPointer(next_word_end) == self.start_page_no

        --* stop at the end of the page, ignore any partial paragraph spilling to next page:
        if not in_current_page then
            self:setParagraphStart()
            --* we're ready looping through this container, so break out of the loop:
            return
        end

        --* reached next paragraph:
        if include_punctuation and add_text_by == "word" and next_elem_no ~= self.current_elem_no then
            add_text_by = "char"

        elseif next_elem_no ~= self.current_elem_no then
            self:setParagraphStart()
            --* we're ready looping through this container, so break out of the loop:
            return

        else
            --! this is the value we are interested in:
            self.paragraph_end = next_word_end
        end
    end
end

--- @private
function PageTexts:addContainerToContainers(paragraphs, texts)
    --* extract text for the current paragraph
    local paragraph_text = KOR.document:getTextFromXPointers(self.paragraph_start, self.paragraph_end)

    --* skip empty or image-only paragraphs:
    if has_text(paragraph_text) then
        paragraph_text = KOR.strings:cleanupSelectedText(paragraph_text)
        paragraph_text = KOR.strings:removeNotes(paragraph_text)
        table_insert(paragraphs, {
            pos0 = self.paragraph_start,
            pos1 = self.paragraph_end,
            text = paragraph_text,
            element_no = self.current_elem_no,
        })
        table_insert(texts, paragraph_text)
    end
end

--- @private
function PageTexts:setParagraphStart()
    if self.current_elem_no ~= self.start_elem_no then
        self.paragraph_start = self.paragraph_start
        :gsub("%[%d+%]%.%d+$", "[1].0")
        :gsub("text%(%)%.%d+$", "text().0")
    end
end

function PageTexts:getHtmlElementIndex(position)
    if not position then
        return 1
    end

    --* bookmark / highlight positions have these formats:
    --[[
    /body/DocFragment[13]/body/section/section[1]/p[8]/text()[1].93,
    or
    /body/DocFragment[12]/body/p[179]/text().157
    or
    /body/DocFragment[13]/body/section/section[1]/p[18]/sup[5]/a/text().0
    or
    /body/DocFragment[13]/body/div[1]/p[16]/text()[1].0
    ]]

    position = position
        :gsub("^/body.+/body/", "", 1)
        :gsub("su[bp]%[%d+%]/", "", 1)
        :gsub("/text%(%)%[%d+%]", "", 1)
        :gsub("/text%(%)", "", 1)
    --* previous replacements reduce above markers to:
    --[[
    section/section[1]/p[8].93,
    or
    p[179].157
    or
    section/section[1]/p[18]/a/.0
    or
    div[1]/p[16].0
    ]]
    --* so if there are 3 numerical indices, then we have a container element, so we remove the container index number here:
    position = position:gsub("%[%d+%](/[a-zA-Z0-9]+%[%d+%])", "%1", 1)
    --* result:
    --[[
    section/section/p[8].93,
    or
    p[179].157
    or
    section/section/p[18]/a/.0
    or
    div/p[16].0
    ]]

    local element_type, element_number = position:match("([piv])%[(%d+)")
    if element_type == "p" then
        element_type = "paragraph"
    elseif element_type == "i" then --* for "li"
        element_type = "list"
    elseif element_type == "v" then
        element_type = "div"
    end
    if not element_number then
        element_type = "paragraph"
        element_number = 0
    end

    --* return main html elem number (is first number match in tail of position):
    return tonumber(element_number), element_type
end

--- @private
function PageTexts:getNonCurrentChapterLinesCount(current_toc_title, page, xp)
    local texts
    self.garbage, texts = self:getAllHtmlContainersInPage(xp, page, true, "---" .. current_toc_title)
    return #texts
end

local function utf8_char_positions(str)
    local positions = {}
    local i = 1
    local len = #str

    while i <= len do
        table_insert(positions, i)

        local byte = string.byte(str, i)
        if byte < 0x80 then
            i = i + 1
        elseif byte < 0xE0 then
            i = i + 2
        elseif byte < 0xF0 then
            i = i + 3
        else
            i = i + 4
        end
    end

    return positions
end

function PageTexts:compressTextAroundMarkers(html, context)
    context = context or 300

    local char_pos = utf8_char_positions(html)
    local total_chars = #char_pos
    local ranges = {}
    local from_char, to_char, char_start, char_end

    --* search strong blocks (bytepositions):
    for byte_start, byte_end in html:gmatch("()<strong>.-</strong>()") do

        --* find associated character-index:
        for i = 1, total_chars do
            if char_pos[i] == byte_start then
                char_start = i
            end
            if char_pos[i] >= byte_end then
                char_end = i
                break
            end
        end

        if char_start and char_end then
            from_char = math_max(1, char_start - context)
            to_char = math_min(total_chars, char_end + context)

            table_insert(ranges, {
                from_char = from_char,
                to_char = to_char
            })
        end
    end

    if #ranges == 0 then
        return ""
    end

    table.sort(ranges, function(a, b)
        return a.from_char < b.from_char
    end)

    --* merge:
    local merged = { ranges[1] }
    for i = 2, #ranges do
        local last = merged[#merged]
        local cur = ranges[i]

        if cur.from_char <= last.to_char then
            last.to_char = math_max(last.to_char, cur.to_char)
        else
            table_insert(merged, cur)
        end
    end

    --* rebuild:
    local result = {}

    local byte_from, byte_to, line, r
    count = #merged
    for i = 1, count do
        r = merged[i]
        byte_from = char_pos[r.from_char]
        byte_to = char_pos[r.to_char + 1]
        byte_to = byte_to and (byte_to - 1) or #html
        line = html:sub(byte_from, byte_to):gsub("^[,.?!;:a-z] ", "")
        table_insert(result, line)
    end

    return table_concat(result, "\n…\n________\n")
end

function PageTexts:getChapterHits(chapter_index, needles, start_page, xp, end_xp)
    local chapter_text = KOR.document:getTextFromXPointers(xp, end_xp)
    local chapter_props = KOR.toc:getChapterPropsByIndex(chapter_index)
    local title = chapter_props.title
    local non_current_chapter_start_lines = self:getNonCurrentChapterLinesCount(title, start_page, xp)

    local lines = KOR.strings:split(chapter_text, "\n")
    for r = 1, non_current_chapter_start_lines do
        table_remove(lines, 1)
        self.garbage = r
    end
    chapter_text = table_concat(lines, "\n")

    return self:countItemOccurrences(chapter_text, needles)
end

function PageTexts:getChapterText(as_html, needles, current_page)
    current_page = current_page or KOR.ui:getCurrentPage()
    local xp = KOR.document:getPageXPointer(current_page)
    local current_toc_title = KOR.toc:getTocTitleByPage(xp)

    local chapter_start_page = KOR.toc:getChapterStartPage(xp)
    local start_xp = KOR.document:getPageXPointer(chapter_start_page)
    local next_chapter_start_page = KOR.toc:getNextChapter(current_page)
    local end_xp = KOR.document:getPageXPointer(next_chapter_start_page)
    local text = KOR.document:getTextFromXPointers(start_xp, end_xp)

    local non_current_chapter_start_lines = self:getNonCurrentChapterLinesCount(current_toc_title, chapter_start_page, start_xp)

    if needles then
        local needle
        count = #needles
        for i = 1, count do
            needle = "%f[%w_](" .. needles[i] .. ")%f[^%w_]"
            text = text:gsub(needle, "<strong>%1</strong>")
        end
        text = self:compressTextAroundMarkers(text, 300)
    end

    local lines = KOR.strings:split(text, "\n")
    for r = 1, non_current_chapter_start_lines do
        table_remove(lines, 1)
        self.garbage = r
    end

    if as_html then
        return "<p>" .. table_concat(lines, "</p>\n<p>") .. "</p>\n", current_toc_title
    end

    return table_concat(lines, "\n"), current_toc_title
end

return PageTexts
