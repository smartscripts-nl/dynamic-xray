
local require = require

local KOR = require("extensions/kor")
local Utf8Proc = require("ffi/utf8proc")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

local DX = DX
local has_content = has_content
local has_no_content = has_no_content
local has_no_text = has_no_text
local select = select
local string = string
local table = table
local table_concat = table.concat
local table_insert = table.insert
local type = type

--- accented characters:
--- ÄËÏÖÜ äëïöü ÁÉÍÓÚ áéíóú ÀÈÌÒÙ àèìòù Çç ß
--- n-dash – m-dash —
--- ­ and   can be used in descriptions

--- @class Strings
local Strings = WidgetContainer:extend{
    curly_apo_l = "‘",
    curly_apo_r = "’",
    curly_quote_l = "“",
    curly_quote_r = "”",
    indent = "     ",
    m_dash = "—",
    n_dash = "–",
    poem_max_line_length = 50,
}

function Strings:cleanupSelectedText(text)
    if not text then
        return
    end
    --* trim spaces and new lines at start and end
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    --* trim spaces around newlines
    text = text:gsub(" *\n *", "\n")
    --* trim consecutive spaces (that would probably have collapsed
    --* in rendered CreDocuments)
    return text:gsub("  +", " ")
end

function Strings:cleanup(text)
    if not text then
        return
    end
    --* don't cleanup hyphen, so don't use %p (stands for punctuation), because that also removed hyphens, which are important to keep for dictionary lookups:
    return text:gsub("[”“‘’\"'—.,:;!¡?¿<>]", "")
end

function Strings:getKeywordsForMatchingFrom(subject, no_lower_case, add_singulars)
    if not subject then
        return {}
    end
    --* prevent problems with special characters:
    subject = self:cleanup(subject)
    if not no_lower_case then
        subject = subject:lower()
    end
    if #subject < 3 then
        return {}
    end
    local splitter = subject:match(",") and ", *" or " +"
    local keywords = self:split(subject, splitter, false)
    local singulars = {}
    local keyword, singular
    local count = #keywords
    for nr = 1, count do
        keyword = keywords[nr]
        keyword = keyword:gsub("%-", "%%-"):gsub("%.", "%%.")
        if add_singulars and keyword:match("s$") then
            singular = keyword:gsub("s$", "")
            table_insert(singulars, singular)
        end
        keywords[nr] = keyword
    end
    count = #singulars
    if add_singulars and count > 0 then
        for nr = 1, count do
            table_insert(keywords, singulars[nr])
        end
    end
    return KOR.tables:filter(keywords, function(ikeyword)
        return #ikeyword > 2 and ikeyword ~= "the"
    end)
end

function Strings:getFirstWordChar(text)
    local first_word_char, rest_of_word = text:match("%s%(?([%w\128-\255])([%w\128-\255]+)%)?%s?$")
    if not first_word_char then
        return nil, false
    end

    local has_non_ascii = self:hasNonAscii(first_word_char .. rest_of_word)

    if first_word_char:match("%d") then
        return first_word_char, has_non_ascii
    end

    return first_word_char:lower(), has_non_ascii
end

function Strings:hasNonAscii(text)
    return text and text:find("[\128-\255]") ~= nil
end

function Strings:limitLength(text, max_length)
    if text and text:len() > max_length then
        text = text:sub(1, max_length - 3) .. "..."
    end
    return text
end

--* count is meant for loops: only on first loop convert strings to singular:
function Strings:singular(text, count)
    if count == 1 then
        --* third substitution: personen -> persoon, fourth: boeken -> boek:
        return text:gsub("’s$", ""):gsub("s$", ""):gsub("onen$", "oon"):gsub("ken$", "k")
    end
    return text
end

function Strings:sortKeywords(text)
    local splitter = text:match(",") and ", *" or " +"
    local joiner = splitter == ", *" and ", " or " "
    local parts = self:split(text, splitter)
    table.sort(parts)
    return table_concat(parts, joiner)
end

function Strings:split(str, pat, capture_empty_entity)
    return util.splitToArray(str, pat, capture_empty_entity)
end

function Strings:substrCount(subject, needle)
    --* select() selects the indexed item of multiple vars returned:
    return select(2, subject:gsub(needle, ""))
end

--* only return ucfirst variant of string if it not contains uppercase characters:
function Strings:lcfirst(str, force_only_first)
    --* %u matches upper case characters:
    return (force_only_first and Utf8Proc.lowercase(util.fixUtf8(str, "?")) or str:gsub("^%u", string.lower))
end

--* only return ucfirst variant of string if it not contains uppercase characters:
function Strings:ucfirst(str, force_only_first)
    --* %l matches lower case characters:
    return (force_only_first and str:sub(1, 1):upper() .. Utf8Proc.lowercase(util.fixUtf8(str:sub(2), "?")) or str:gsub("^%l", string.upper))
end

--* return utf8-safe lowercase string:
function Strings:lower(text)
    return Utf8Proc.lowercase_dumb(util.fixUtf8(text, "?"))
end

function Strings:lowerFirst(str)
    return Utf8Proc.lowercase(util.fixUtf8(str:sub(1, 1), "?")) .. str:sub(2)
end

--* return utf8-safe uppercase string:
function Strings:upper(text)
    return Utf8Proc.uppercase_dumb(util.fixUtf8(text, "?"))
end

function Strings:formatListItemNumber(nr, title, use_spacer)
    local spacer = ""
    if use_spacer then
        if nr < 10 then
            spacer = "    "
        elseif nr < 100 then
            spacer = "  "
        end
    end
    return nr .. ". " .. spacer .. self:removeListItemNumber(title)
end

--- @class DescriptionDialogTextFormat
function Strings:prepareForDisplay(text, separate_paragraphs)

    if has_no_text(text) then
        return ""
    end

    text = text:gsub("^\n+", ""):gsub("\n+$", "")

    local indent = DX.s.is_ubuntu and "   " or self.indent
    local add_indents = true

    --* preserve numbers like 10,000 and 25.400:
    text = text:gsub("([0-9])([.,])([0-9])", "%1=%2=%3")

    --* replace non breakable spaces by regular ones:
    text = text:gsub(" ", " ")

    text = util.htmlToPlainTextIfHtml(text)

    --* first remove all existing indents:
    text = text:gsub("\n +", "\n")

    if separate_paragraphs then
        text = text:gsub(" @ .+$", ""):gsub("\n", "\n\n"):gsub("\n\n\n", "\n\n")
    else
        --* now re-add indents:
        --* first one is for pagemarkers?:
        text = text:gsub(" @ .+$", ""):gsub("\n", "\n" .. indent)

        text = text:gsub("(\n" .. indent .. "\n)" .. indent, "%1")
    end

    text = text:gsub(" +([.,!?;:])", "%1")

    --* replacing special characters included in a group in a text leads to garbled quotes etc in the text; so here we do that separately:
    text = text:gsub("(”)[0-9]+", "%1")

    --* for author names in capitals below texts:
    if add_indents then
        text = text:gsub("\n" .. indent .. "([A-Z][A-Z])", "\n\n%1")
    end

    text = text:gsub("([a-z])  +", "%1 ")

    if add_indents then
        --* for aligning items of table_of_contents to the left:
        text = text:gsub("\n" .. indent .. "([Cc]hapter)", "\n%1")
        text = text:gsub("\n" .. indent .. "([0-9])", "\n%1")

        --* make sure indents are always the same size:
        text = text:gsub("\n[ \t]+", "\n" .. indent)
    end

    text = self:removeNotes(text)

    text = text:gsub(" +noindent: ?", "")
    text = text:gsub("noindent: ?", "")

    --* used for formatting white lines in some ebooks:
    text = text:gsub("==", "")

    --* fix for " v.\nChr. " in ebook De heilige natuur:
    text = text:gsub(" v%.\n +", " v. ")

    --* hotfix for initials in names:
    for i = 1, 4 do
        if i < 5 then
            text = text:gsub("([A-Z]%.)\n" .. indent .. "([A-Z]%.)", "%1%2")
        end
    end

    text = text
        --* for author names below quotes:
        :gsub("\n  +—", "\n—"):gsub("\n  +–", "\n–")

        --* restore numbers like 10,000 and 25.400:
        :gsub("([0-9])=([.,])=([0-9])", "%1%2%3")

        --* place text which start with m-dash, n-dash or hyphen always at start of line:
        :gsub("\n" .. indent .. "—", "\n—")
        :gsub("\n" .. indent .. "–", "\n–")
        :gsub("\n" .. indent .. "%–", "\n-")

    text = KOR.html:plainTextListsPrettify(text)

    return text:gsub("(’%.?)[0-9]+", "%1")
end

function Strings:removeListItemNumber(text)
    if not text then
        return
    end
    if type(text) == "table" and text.text then
        text = text.text
    end
    --* protected ratings like 4.53 at start of line:
    text = text:gsub("^([0-9]+)[.]([0-9])", "%1|%2")
    text = text:gsub("^[0-9]+[.][ ]*", "")
    return text:gsub("^([0-9]+)%|([0-9])", "%1.%2")
end

function Strings:removeNotes(text)
    if not text then
        return text
    end
    --* remove (foot)note markings in text:
    --* double colon excluded, because otherwise clock hours destroyed:
    --* exclude h, so we don't damage html headings:
    text = text
        :gsub("([a-g,i-z?!;)])[0-9]+", "%1")
        :gsub("([a-zA-Z][.,])[0-9]+([ \n\r])", "%1%2")
        :gsub("%.[0-9]+$", "")
        :gsub("(”%.?)[0-9]+", "%1")
        :gsub("(’%.?)[0-9]+", "%1")
        --* remove notes in bracketed format, e.g. "[6]":
        :gsub("%[%d-%]", "")

    return text:gsub(" ?%*", ""):gsub(" ?%†", ""):gsub(" ?%‡", "")
end

function Strings:splitLinesToMaxLength(text, max_length, indent, first_word, dont_indent_first_line, after_first_line_indent)
    if has_no_content(text) then
        return ""
    end
    if has_content(first_word) then
        text = first_word .. text
    end
    local test = text
    if indent and not dont_indent_first_line then
        test = indent .. text
    end
    if test:len() <= max_length then
        return test
    end
    local words = self:split(text, " ")
    local lined_text = { "" }
    local index = 1
    local word, for_next_line, for_previous_line, parts, insert
    local count = #words
    for i = 1, count do
        word = words[i]
        if word:match("\n") then
            parts = self:split(word, "\n")
            for_previous_line = parts[1]
            for_next_line = parts[2]
            test = lined_text[index] .. for_previous_line
        else
            test = lined_text[index] .. word
        end
        if test:len() < max_length then
            lined_text[index] = test .. " "
            if for_next_line then
                index = index + 1
                table_insert(lined_text, for_next_line .. " ")
            end
        else
            index = index + 1
            if for_previous_line then
                table_insert(lined_text, for_previous_line)
                index = index + 1
            end
            insert = for_previous_line or word
            table_insert(lined_text, insert .. " ")
        end
    end

    count = #lined_text
    for i = 1, count do
        if indent and (not dont_indent_first_line or i > 1) then
            lined_text[i] = indent .. lined_text[i]
        end
        if after_first_line_indent and i > 1 then
            lined_text[i] = after_first_line_indent .. lined_text[i]
        end
        lined_text[i] = lined_text[i]:gsub(" $", "")
    end
    return table_concat(lined_text, "\n")
end

--* remove trailing and leading whitespace from string.
--* @param s String
function Strings:trim(s)
    --* from PiL2 20.4
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function Strings:hasWholeWordMatch(haystack, haystack_lower, needle)
    if not needle then
        return false
    end

    --* case sensitive search, mostly for Xray persons:
    if needle:match("[A-Z]") then
        --* %A = non alpha characters:
        if haystack:match("%A" .. needle .. "%A") or haystack:match("^" .. needle .. "%A") or haystack:match("%A" .. needle .. "$") then
            return true
        end

        --* search for uppercase names at start of chapters:
        needle = needle:upper()
        return haystack:match("%A" .. needle .. "%A") or haystack:match("^" .. needle .. "%A") or haystack:match("%A" .. needle .. "$")
    end

    --* case insensitive, mostly for Xray terms (non persons):
    if haystack_lower:match("%A" .. needle .. "%A") or haystack_lower:match("^" .. needle .. "%A") or haystack_lower:match("%A" .. needle .. "$")
        then return true
    end

    --* search for uppercase things/entities at start of chapters:
    needle = needle:upper()
    return haystack:match("%A" .. needle .. "%A") or haystack:match("^" .. needle .. "%A") or haystack:match("%A" .. needle .. "$")
end

function Strings:getNameSwapped(name)
    if not name:match(", ") then
        return
    end
    local parts = self:split(name, ", +")
    if #parts == 2 then
        return parts[2] .. " " .. parts[1]
    end
end

return Strings
