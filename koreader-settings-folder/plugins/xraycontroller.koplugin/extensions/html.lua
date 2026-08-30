
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

local DX = DX
local G_reader_settings = G_reader_settings
local has_no_text = has_no_text
local T = T
local table_concat = table_concat
local table_insert = table_insert
local util_htmlToPlainTextIfHtml = util.htmlToPlainTextIfHtml

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
    return util_htmlToPlainTextIfHtml(text)
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

function Html:textToHtml(text)

    text = text
        :gsub("\n\n\n+", "\n\n")
        :gsub("\n\n", "\n \n")

    --* remove (foot)note markings in html:
    text = KOR.strings:removeNotes(text)

    local lines = {}
    for s in text:gmatch("[^\r\n]+") do
        table_insert(lines, s)
    end

    local has_wiki_headings = text:match("☀")
    self.in_poetry = 0
    local result = {}
    count = #lines
    for i = 1, count do
        self:formatHtmlLine(lines, i, result, has_wiki_headings)
    end
    local html = table_concat(result, "\n")

    if has_wiki_headings then
        local wkh = KOR.referenceinformation.wiki_heading_markers
        local sun = KOR.referenceinformation.wiki_heading_needle
        for i = 1, 6 do
            --* in case of wkh[3] we have  ☀◤:
            if i == 3 then
                html = html
                    :gsub("<p> " .. sun .. "(◤ [^>]+)</p>", "<h3 class='wiki-heading'>%1</h3>")
            else
                html = html
                    :gsub("<p>" .. sun .. "(" .. wkh[i] .. " [^>]+)</p>", "<h" .. i .. " class='wiki-heading'>%1</h" .. i .. ">")
            end
    end
    end
    html = html
        :gsub("<p class='whitespace'>&#160;</p>\n(<h%d)", "\n%1")
        :gsub("(</h%d>)\n<p class='whitespace'>&#160;</p>", "%1\n")

    if not has_wiki_headings and self.in_poetry >= self.poetry_limit_lines then
        return html .. "</div>"
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
    table_insert(result, "</div>" .. p)
end

function Html:formatHtmlLine(lines, i, result, has_wiki_headings)
    local line = lines[i]

    local is_short = #line < self.poetry_limit_length
    local is_page = line:match("pagina %d+")
    local is_blank = has_no_text(line)

    local state = (not has_wiki_headings and self.in_poetry > 0) and STATE_POETRY or STATE_NORMAL

    --- PAGE NUMBER (always terminates poetry)
    if is_page then
        if not has_wiki_headings and state == STATE_POETRY and self.in_poetry <= self.poetry_limit_lines then
            self:openPoetry(result, i - self.in_poetry)
            table_insert(result, "</div><p class=\"export-page-number\">" .. line .. "</p>")
        else
            table_insert(result, "<p class=\"export-page-number\">" .. line .. "</p>")
        end
        self.in_poetry = 0
        return
    end

    --- POETRY STATE

    if not has_wiki_headings and state == STATE_POETRY then
        if is_short then
            table_insert(result, self:paragraph(line, is_blank))
            self.in_poetry = self.in_poetry + 1

            if self.in_poetry == self.poetry_limit_lines then
                self:openPoetry(result, i - self.poetry_limit_lines + 1)
            end
            return
        end

        --* poetry ends on long line:
        self:closePoetry(result, self:paragraph(line, is_blank))
        self.in_poetry = 0
        return
    end

    --- NORMAL STATE

    if not has_wiki_headings and is_short then
        table_insert(result, self:paragraph(line, is_blank))
        self.in_poetry = 1
        return
    end

    table_insert(result, self:paragraph(line, is_blank))
    self.in_poetry = 0
end

function Html:getHtmlWidgetCss(is_reference_information_or_glossary, book_css)
    --* Using Noto Sans because Nimbus doesn't contain the IPA symbols.
    --* 'line-height: 1.3' to have it similar to textboxwidget,
    --* and follow user's choice on justification
    local css_justify = G_reader_settings:isTrue("dict_justify") and "text-align: justify;" or "text-align: left !important;"
    local css = [[
        @page {
            margin: 0;
            font-family: 'Red Hat Text', 'Noto Sans', sans-serif !important;
        }

        body {
            margin: 0 !important;
            padding: 0 !important;
            line-height: 1.3;
            ]] .. css_justify .. [[
            font-size: ]] .. DX.s.html_box_font_size .. [[ !important;
        }

        * {
            ]] .. css_justify .. [[
        }

        body > :first-child, body > :first-child > :first-child {
            margin-top: 0 !important;
            padding-top: 0 !important;
        }

        div.redhat, div.redhat * {
            font-family: 'Red Hat Text' !important;
        }

        h1, h2, h3, h4, h5, h6 {
            page-break-inside: avoid !important;
            page-break-before: avoid !important;
            page-break-after: avoid !important;
            margin-top: 1.1em !important;
            margin-bottom: .5em !important;
            padding: 0 !important;
        }

        h1 {
            text-align: center !important;
        }

        h3 {
            font-style: italic !important;
            font-size: 120% !important;
        }

        h1.wiki-heading, h2.wiki-heading, h3.wiki-heading, h4.wiki-heading, h5.wiki-heading, h6.wiki-heading {
            margin-top: 1.1em !important;
            margin-bottom: .5em !important;
            padding: 0 !important;
        }

        blockquote, dd {
            margin: 0 1em;
        }

        ol, ul, menu {
            margin: 0; padding: 0 1.7em;
        }

        p {
            margin: 0;
        }

        p + p {
            text-indent: 1.5em;
        }

        p.separator {
            margin-bottom: 1em;
            text-align: center;
        }

        h1 + p, h2 + p, h3 + p, h4 + p, p + p.chaptertitle, p.noindent, p.no-indent, p.whitespace + p, div.poezie p, div.noindent p, div.no-indent p, p + p.separator, p.heading, p.top-block, p.next-block, table + p, th p, td p {
            text-indent: 0 !important;
        }

        p.top-block {
            margin-top: .7em !important;
        }

        p.heading {
            margin-top: 1em;
            margin-bottom: .3em;
            font-weight: bold;
        }

        p.next-block {
            margin-top: 1em;
        }

        th p, td p {
            margin-top: 0 !important;
        }

        li.glossary {
            margin-bottom: .2em;
            /* this is a hotfix, don't know why the face of list-items in the Glossary is bigger then that of the Reference Information text: */
            font-size: 85%;
        }
    ]]
    --* For reference, MuPDF declarations with absolute units:
    --*  "blockquote{margin:1em 40px}"
    --*  "dd{margin:0 0 0 40px}"
    --*  "ol,ul,menu {margin:1em 0;padding:0 0 0 30pt}"
    --*  "hr{border-width:1px;}"
    --*  "td,th{padding:1px}"
    --*
    --* MuPDF doesn't currently scale CSS pixels, so we have to use a font-size based measurement.
    --* Unfortunately MuPDF doesn't properly support `rem` either, which it bases on a hard-coded
    --* value of `16px`, so we have to go with `em` (or `%`).
    --*
    --* These `em`-based margins can vary slightly, but it's the best available compromise.
    --*
    --* We also keep left and right margin the same so it'll display as expected in RTL.
    --* Because MuPDF doesn't currently support `margin-start`, this results in a slightly
    --* unconventional but hopefully barely noticeable right margin for <dd>.
    --*
    --* For <ul> and <ol>, bullets and numbers are displayed in the margin/padding, so
    --* we need a bit more for them to not get truncated (1.7em allows for 2 digits list
    --* item numbers). Unfortunately, because we want this also for RTL, this space is
    --* wasted on the other side...

    local force_font_sizes = [[

    p, span, bold, strong, table, tr, th, td {
        font-size: 100% !important;
    }

    /* in HtmlBoxes by default a serif font is used for texts in this format, so here we force it to the body font-face: */
    em, i, span.ITAL, span.ital, span.italic, span.cursive {
        font-family: 'Red Hat Text', 'Noto Sans', sans-serif !important;
    }
]]

    if not is_reference_information_or_glossary then
        return css .. force_font_sizes
    end

    local koreader_css = self:getBookCss()
    if koreader_css then
        css = css .. "\n" .. koreader_css .. force_font_sizes
    end
    --* book_css here might have been set from the book css via ((ReferenceInformation#prepareHtmlAndCssForSaving)):
    if book_css then
        return css .. "\n" .. book_css .. force_font_sizes
    end
    return css .. force_font_sizes
end

--- @private
function Html:getBookCss()
    local ebook_stylesheet = KOR.ui.typeset.css
    local book_css = KOR.files:fileGetContents(ebook_stylesheet)
    if not book_css then
        return ""
    end

    --! in the context of HtmlBox and TextViewer instances the CRE css hints in html5.css would only lead to errors:
    return book_css
        --* the CRE hints etc. e.g. in html5.css imported here would trigger errors:
        :gsub("@import url[^;]-;", "")
        :gsub(":where[^}]+}", "")
        :gsub("-cr-only-if:[^;]+;", "")
        --* e.g. replaces @media (-cr-max-cre-dom-version: 20180527) at end of epub.css:
        :gsub("@media.+$", "")
end

function Html:removeUnwantedElements(html)
    local elements = { "DocFragment", "body", "html", "inlineBox", "autoBoxing", "section", "a" }
    count = #elements
    for i = 1, count do
        html = html:gsub(T("</?%1[^>]*>", elements[i]), "")
    end
    return html
end

function Html:makeFirstParaNonIndented(html)
    if html:match("<p[^>]+class=[\"'][^\"']+") then

        return html:gsub("<p[^>]+class=([\"'])([^\"']+)", "<p class=%1%2 no-indent", 1)
    end

    return html:gsub("<p[^>]+>", "<p class='no-indent'>", 1)
end

return Html
