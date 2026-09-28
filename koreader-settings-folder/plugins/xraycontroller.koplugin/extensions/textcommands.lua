
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local string_rep = string_rep
local tonumber = tonumber

--- @class TextCommands
local TextCommands = WidgetContainer:extend{
    commands_info = {
        _("CALL THIS DIALOG"),
        " ",
        _("\"ii\" at end of line"),
        " ",
        _("DELETING TEXT QUICKLY (PARTIALLY)"),
        " ",
        _("Del = BackSpace"),
        _("Shift+Del = Delete"),
        _("1x, 2x etc. = remove this number of characters"),
        _("xx = remove last character"),
        _("ww = remove last word"),
        _("1w, 2w etc. = remove this number of Words"),
        _("sx = remove last sentence (part)"),
        _("ssx = remove the entire last sentence"),
        _("px = remove last paragraph"),
        _("space+x = remove double spaces"),
        " ",
        _("REPLACEMENTS"),
        " ",
        _("double space = \", \""),
        _("1k, 2k etc. = add a comma 1 or 2 words back, etc."),
        " ",
        _("TRANSFORMATIONS"),
        " ",
        _("upx = convert line to Uppercase format"),
        _("ucx = convert line to Ucfirst format"),
        " ",
        _("CURSOR PLACEMENT"),
        " ",
        _("1cs, 2cs etc. = position the cursor 1 or 2 sentences back, at the start of a sentence"),
        _("cps = place cursor at start of current text"),
        _("cpe = place cursor at end of current text"),
        " ",
        _("REDEFINED KEYS"),
        _("(for BT/hardware keyboards, because some keys, like comma, are not available in that case)"),
        " ",
        _("hash = /"),
        _("dollar = :"),
        _("procent = ;"),
        "^ = -",
        _("ampersand = \""),
        _("star = '"),
        _("slash (bottom of keyboard) = ,"),
        " ",
        _("CLOSING INPUT FIELD"),
        " ",
        _("[space]esc[space] at end of input field"),
        " ",
        _("SNIPPETS"),
        " ",
    },
 }

function TextCommands:execute(content, first_word_char, charlist)

    local a_command_was_executed, new_charpos
    local commands = {
        --* " esc ": close the form:
        { "CloseForm" },
        --* #w: remove n words from end:
        { "RemoveWords" },
        --* convert line to uppercase heading by appending "hex" to text + space on that line:
        { "LineToUppercase", first_word_char },
        --* convert sentence to ucfirst by appending "ucx" to text + space of that sentence:
        { "SentenceToUcFirst", first_word_char },
        --* #x: remove n chars from end:
        { "RemoveChars" },
        --* #k: inject comma n words from end:
        { "InsertComma" },
        --* ww: remove last word:
        { "RemoveLastWord" },
        --* #cr: position cursor # lines back:
        { "GoNLinesBack", first_word_char, charlist },
        --* cpe: position cursor at end of text in input field:
        { "GotoTextEnd", first_word_char, charlist },
        --* cps: position cursor at start of text in input field:
        { "GotoTextStart" },
        --* delete entire last sentence by appending " zzx" to it:
        { "RemoveLastSentence" },
        --* delete last sentence part (e.g. to comma, ; or :) by appending " zx" to it:
        { "RemoveLastSentencePart" },
        --* delete last char by appending "xx" to it (prefix space not required):
        { "RemoveLastChar" },
        --* delete entire last paragraph part by appending " ax" to it:
        { "CurrentParagraph" },
        --* show shortcuts explanation by typing " ii" at end of line:
        { "ShowSnippetsExplanation" },
    }
    local ccount = #commands
    for i = 1, ccount do
        content, a_command_was_executed, new_charpos = self["command" .. commands[i][1]](content, commands[i][2], commands[i][3])
        if a_command_was_executed then
            return content, true, new_charpos
        end
    end

    return content, false
end

--- @private
function TextCommands.commandGoNLinesBack(content, first_word_char, charlist)
    local lines_back_count = content:match(" (%d+)cr$")
    if not lines_back_count then
        TextCommands.garbage = first_word_char
        return content, false
    end
    content = content:gsub(" %d+cr$", "", 1)
    lines_back_count = tonumber(lines_back_count)
    if not content:match("[.?!]") then
        return content, true, 1
    end
    local lines = KOR.strings:split(content, "[.?!]")
    local lines_count = #lines
    if lines_count <= lines_back_count then
        return content, true, 1
    end
    local lines_before_cursor = lines_count - lines_back_count
    local new_charpos = 0
    for i = 1, lines_before_cursor do
        new_charpos = new_charpos + KOR.strings:length(lines[i]) + 1
    end
    while charlist[new_charpos + 1]:match("%s") do
        new_charpos = new_charpos + 1
    end
    return content, true, new_charpos + 1
end

--- @private
function TextCommands.commandCloseForm(content)
    if not content:match(" esc $") then
        return content, false
    end

    if KOR.dialogsqueue:getQueueCount() > 1 then
        KOR.dialogsqueue:restorePrevious()
        return content, true
    end

    UIManager:close(KOR.registry.dialog_widget)
    KOR.registry.dialog_widget = nil

    return content, true
end

local command
--- @private
function TextCommands.commandGotoTextEnd(content, first_word_char, charlist)
    command = " cpe$"
    if content:match(command) then
        content = content:gsub(command, " ", 1)
        return content, true, #charlist + 1
    end
    TextCommands.garbage = first_word_char
    return content, false
end

--- @private
function TextCommands.commandGotoTextStart(content)
    command = " cps$"
    if content:match(command) then
        content = content:gsub(command, " ", 1)
        return content, true, 1
    end
    return content, false
end

--- @private
function TextCommands.commandInsertComma(content)
    local inject_comma = content:match(" (%d+k)$")
    if not inject_comma then
        return content, false
    end

    local needle
    content = content:gsub(" (%d+k)$", "", 1)
    local word_count = inject_comma:gsub("k$", "", 1)
    word_count = tonumber(word_count)
    needle = " +(" .. string_rep("[^ ]+ +", word_count)
    --* remove last space:
    needle = needle:gsub(" %+$", "", 1)
    needle = needle .. ")$"
    return content
        --* create needles like :gsub(" +([^ ]+ +[^ ]+ +[^ ]+)$", ", %1 ", 1)
        :gsub(needle, ", %1", 1), true
end

--- @private
function TextCommands.commandLineToUppercase(content, first_word_char)
    if first_word_char == "h" then
        local heading = content:match("([^\n]+) [Hh]ex")
        if heading then
            return content:gsub("[^\n]+ [Hh]ex", heading:upper(), 1), true
        end
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveChars(content)
    local remove_count = content:match(" (%d+)x$")
    if remove_count then
        content = content:gsub(" %d+x$", "", 1)
        remove_count = tonumber(remove_count)
        local base = "."
        local replace = base:rep(remove_count) .. "$"
        return content
            :gsub(replace, "", 1), true
    end
    return content, false
end

--- @private
function TextCommands.commandCurrentParagraph(content)
    if content:match(" [Aa]x$") then
        return content
            :gsub("[^\n]+ [Aa]x$", "", 1), true
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveLastChar(content)
    command = ". ?[Xx]x$"
    if content:match(command) then
        return content
            :gsub(command, "", 1), true
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveLastSentence(content)
    if content:match(" [Zz]zx$") then
        return content
            :gsub("[^.?!\n]+[.?!'\"]? [Zz]zx$", "", 1)
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveLastSentencePart(content)
    if content:match(" [Zz]x$") then
        return content
            :gsub("[^;:,.?!'\"\n]+[.?!'\"]? [Zz]x$", "", 1)
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveLastWord(content)
    if content:match(" [Ww]w$") then
        return content
            --* delete last word by appending " ww" to it:
            :gsub(" [^ ]+ [Ww]w$", " ", 1), true
    end
    return content, false
end

--- @private
function TextCommands.commandRemoveWords(content)
    local needle
    local word_count = content:match(" (%d+)w$")
    if not word_count then
        return content, false
    end

    word_count = tonumber(word_count)
    needle = string_rep(" [^ ]+ ?", word_count) .. "$"
    return content
        --* created needles like :gsub(" [^ ]+ ?$", " ", 1) etc.; replace the requested number of words by a space:
        :gsub(needle, " ", 1), true
end

--- @private
function TextCommands.commandSentenceToUcFirst(content, first_word_char)
    if first_word_char == "u" then
        local ucfirst = content:match("([^;:,.?!'\"\n]*) [Uu]cx")
        if ucfirst then
            ucfirst = KOR.strings:ucfirst(ucfirst, "force_only_first")
            return content:gsub("[^\n]+ [Uu]cx", ucfirst, 1), true
        end
    end
    return content, false
end

--- @private
function TextCommands.commandShowSnippetsExplanation(content)
    if content:match(" ii$") then
        DX.i:showSnippetsExplanation(2)
        return content:gsub(" ii$", "", 1), true
    end
    return content, false
end

return TextCommands
