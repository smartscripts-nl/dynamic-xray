
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

local has_no_text = has_no_text
local has_text = has_text
local table = table
local tonumber = tonumber

local count
local STATE_NORMAL = 0
local STATE_POETRY = 1

--- @class Html
local Html = WidgetContainer:extend{
    placeholder_br = "brbrbrbr",

    placeholder_ol_start = "⚑",
    placeholder_ol_end = "⚐",
    placeholder_ol_li = "➊",
    placeholder_ol_li_close = "①",

    placeholder_ul_start = "♥",
    placeholder_ul_end = "♡",
    placeholder_ul_li = "●",
    placeholder_ul_li_close = "⚬",

    poetry_limit_length = 60,
    poetry_limit_lines = 4,
}

function Html:htmlToPlainTextIfHtml(text)
    return util.htmlToPlainTextIfHtml(text)
end

function Html:plainTextListsPrettify(text)

    --* we don't want to see indents before html list items placeholders:
    text = self:removeListIndents(text)

    local ol_count = KOR.strings:substrCount(text, self.placeholder_ol_start)
    local ul_count = KOR.strings:substrCount(text, self.placeholder_ul_start)
    text = text
        :gsub("\n?\n?" .. self.placeholder_ul_start .. "\n?\n?", "\n<ul>")
        :gsub("\n?\n?" .. self.placeholder_ul_end .. "\n?\n?", "</ul>")
        :gsub("\n?\n?" .. self.placeholder_ol_start .. "\n?\n?", "\n<ol>")
        :gsub("\n?\n?" .. self.placeholder_ol_end .. "\n?\n?", "</ol>")
        --* remove first indentation in list items which have a linebreak:
        :gsub(self.placeholder_ol_li .. "([^\n" .. self.placeholder_ol_li_close .. "]-\n)[ \t ]+", self.placeholder_ol_li .. "%1")
        :gsub(self.placeholder_ul_li .. "([^\n" .. self.placeholder_ul_li_close .. "]-\n)[ \t ]+", self.placeholder_ul_li .. "%1")

    local marked_list, list_start, list_end, li_start, li_end, list_count, item_count, li_symbol, li_no
    --* loop through ul and ol:
    for list_type = 1, 2 do
        list_start = list_type == 1 and "<ul>" or "<ol>"
        list_end = list_type == 1 and "</ul>" or "</ol>"
        li_start = list_type == 1 and self.placeholder_ul_li or self.placeholder_ol_li
        li_end = list_type == 1 and self.placeholder_ul_li_close or self.placeholder_ol_li_close
        list_count = list_type == 1 and ul_count or ol_count
        --* replace list items in ul lists by bullet placeholder and in ol lists by "#" marker:
        li_symbol = list_type == 1 and "@@@@@" or "#"

        --* loop trough all list, sorted by ul and ol:
        for list_no = 1, list_count do
            marked_list = text:match(list_start .. ".-" .. list_end)
            item_count = KOR.strings:substrCount(marked_list, li_start)
            --* loop through all items of one list and add item numbers for ol lists:
            for i = 1, item_count do
                li_no = list_type == 1 and " " or i .. ". "
                marked_list = marked_list
                    :gsub("\n?\n?" .. li_end .. "\n?\n?", "")
                    :gsub("\n?\n?" .. li_start .. "\n?\n?", "\n\n" .. li_symbol .. li_no, 1)
            end
            marked_list = marked_list
                :gsub("@@@@@", li_start)
                :gsub("\n\n</?[ou]l>", "\n")
                :gsub("</?[ou]l>", "\n")
            text = text:gsub(list_start .. ".-" .. list_end, marked_list, 1)
            self.garbage = list_no
        end
    end
    text = text:gsub("[ \t ]+\n", "\n"):gsub("\n\n+", "\n\n")

    return text
end

function Html:removeListIndents(text)
    text = text
        :gsub(" +" .. self.placeholder_ul_li, self.placeholder_ul_li)
        :gsub(" +" .. self.placeholder_ol_li, self.placeholder_ol_li)
        :gsub(" +%[", "[")
        :gsub(self.placeholder_br .. "\n?", "\n   ")

    return text:gsub("\n\n +", "\n\n")
end

function Html:getAllHtmlContainersInCurrentPage(page_xp, start_page_no)
    local KDoc = KOR.document
    local containers = {}
    local pos = page_xp
    self.start_page_no = start_page_no
    self.current_elem_no = self:getHtmlElementIndex(pos)
    self.start_elem_no = self.current_elem_no

    --* guard clause: no element found:
    if not self.current_elem_no then
        return containers
    end

    local in_current_page
    while true do
        self.paragraph_start = pos
        self.paragraph_end = pos

        --* loop through words until we reach a new element (next paragraph):
        self:loopThroughContainerWords()
        if not self.paragraph_end then
            break
        end
        self:addContainerToContainers(containers, KDoc)

        --* advance to next paragraph:
        pos = KDoc:getNextVisibleWordEnd(self.paragraph_end)
        if not pos then
            break
        end

        self.current_elem_no = self:getHtmlElementIndex(pos)
        in_current_page = KDoc:getPageFromXPointer(pos) == start_page_no
        if not in_current_page then
            break
        end
    end

    --! return paragraphs to CreDocument, where it will be stored in self.paragraphs for the current page!:
    return containers
end

--- @private
function Html:loopThroughContainerWords()
    local next_word_end, next_elem_no, in_current_page
    local KDoc = KOR.document

    while true do
        next_word_end = KDoc:getNextVisibleWordEnd(self.paragraph_end)
        if not next_word_end then
            --* we're ready looping through this container, so break out of the loop:
            return
        end

        next_elem_no = self:getHtmlElementIndex(next_word_end)
        in_current_page = KDoc:getPageFromXPointer(next_word_end) == self.start_page_no

        --* stop at the end of the page, ignore any partial paragraph spilling to next page:
        if not in_current_page then
            self:setParagraphStart()
            --* we're ready looping through this container, so break out of the loop:
            return
        end

        --* reached next paragraph:
        if next_elem_no ~= self.current_elem_no then
            self:setParagraphStart()
            --* we're ready looping through this container, so break out of the loop:
            return
        end

        self.paragraph_end = next_word_end
    end
end

--- @private
function Html:addContainerToContainers(paragraphs, KDoc)
    --* extract text for the current paragraph
    local paragraph_text = KDoc:getTextFromXPointers(self.paragraph_start, self.paragraph_end)

    --* skip empty or image-only paragraphs:
    if has_text(paragraph_text) then
        paragraph_text = KOR.strings:cleanupSelectedText(paragraph_text)
        paragraph_text = KOR.strings:removeNotes(paragraph_text)
        table.insert(paragraphs, {
            pos0 = self.paragraph_start,
            pos1 = self.paragraph_end,
            text = paragraph_text,
        })
    end
end

--- @private
function Html:setParagraphStart()
    if self.current_elem_no ~= self.start_elem_no then
        self.paragraph_start = self.paragraph_start
        :gsub("%[%d+%]%.%d+$", "[1].0")
        :gsub("text%(%)%.%d+$", "text().0")
    end
end

function Html:getHtmlElementIndex(position)
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

function Html:textToHtml(text)

    text = text
        :gsub("\n\n\n+", "\n\n")
        :gsub("\n\n", "\n \n")

    --* remove (foot)note markings in html:
    text = KOR.strings:removeNotes(text)

    local lines = {}
    for s in text:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end

    self.in_poetry = 0
    local result = {}
    count = #lines
    for i = 1, count do
        self:formatHtmlLine(lines[i], result)
    end
    local html = table.concat(result, "\n")
    if self.in_poetry >= self.poetry_limit_lines then
        html = html .. "</div>"
    end

    return html
end

function Html:paragraph(text, is_blank)
    if is_blank then
        return "<p class='whitespace'>&#160;</p>"
    end
    return "<p>" .. text .. "</p>"
end

function Html:openPoetry(result, start_index)
    result[start_index] = "<div class='poezie'>" .. result[start_index]
end

function Html:closePoetry(result, p)
    table.insert(result, "</div>" .. p)
end

function Html:formatHtmlLine(line, result)

    local is_short = #line < self.poetry_limit_length
    local is_page = line:match("pagina %d+")
    local is_blank = has_no_text(line)

    local state = (self.in_poetry > 0) and STATE_POETRY or STATE_NORMAL

    --- PAGE NUMBER (always terminates poetry)
    if is_page then
        if state == STATE_POETRY and self.in_poetry <= self.poetry_limit_lines then
            self:openPoetry(result, i - self.in_poetry)
            table.insert(result, "</div><p class=\"export-page-number\">" .. line .. "</p>")
        else
            table.insert(result, "<p class=\"export-page-number\">" .. line .. "</p>")
        end
        self.in_poetry = 0
        return
    end

    --- POETRY STATE

    if state == STATE_POETRY then
        if is_short then
            table.insert(result, self:paragraph(line, is_blank))
            self.in_poetry = self.in_poetry + 1

            if self.in_poetry == self.poetry_limit_lines then
                self:openPoetry(result, i - self.poetry_limit_lines + 1)
            end
            return
        end

        -- poetry ends on long line
        self:closePoetry(result, self:paragraph(line, is_blank))
        self.in_poetry = 0
        return
    end

    --- NORMAL STATE

    if is_short then
        table.insert(result, self:paragraph(line, is_blank))
        self.in_poetry = 1
        return
    end

    table.insert(result, self:paragraph(line, is_blank))
    self.in_poetry = 0
end

return Html
