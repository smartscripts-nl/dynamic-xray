
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local pairs = pairs
local string_rep = string_rep
local table_concat = table_concat
local table_insert = table_insert
local table_sort = table_sort
local tonumber = tonumber

local count

--- @class TextSnippets
local TextSnippets = WidgetContainer:extend{
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
    help_info = nil,
    --? for snippets we use optionally "t" as suffix instead of "z", which is reserved for input dialog commands in ((TextSnippets#handleCommands)) - is this info still relevant?:
    --* these are loaded via InformationManager from table text_snippets:
    --! this list is grouped by subitems with first chars of snippet names, so snippets["a"], etc.:
    snippets = nil,
    snippets_table = "snippets",
}

--- @private
function TextSnippets:init()
    if KOR.registry:get("is_koreader_start") then
        return
    end
    self:updateSnippetsList()
end

--- @private
--- @return table
function TextSnippets:getSnippetsList()
    self:init()
    --! don't remove this call, even though this call is also done in self#init, because otherwise KOReader would crash upon entering text in a dialog (probably because snippets were not populated upon KOReader start):
    self:updateSnippetsList()

    local keys = {}
    local snippets = {}
    for char, definitions in pairs(self.snippets) do
        --* because for each char we have the lowercase and the uppercase variant:
        if not char:match("[A-Z]") then
            for key, value in pairs(definitions) do
                table_insert(keys, key)
                snippets[key] = value
            end
            self.garbage = char
        end
    end
    table_sort(keys)
    count = #keys
    local list = {}
    for i = 1, count do
        table_insert(list, keys[i] .. " " .. KOR.icons.arrow_bare .. " " .. snippets[keys[i]])
    end
    return list
end

function TextSnippets:getSnippetsHelp()
    if self.help_info then
        return self.help_info
    end
    local snippets = self:getSnippetsList()
    self.help_info = table_concat(KOR.tables:merge(self.commands_info, snippets), "\n")
    return self.help_info
end

function TextSnippets:showManager()
    self:updateSnippetsList()
    KOR.informationmanager:onShowInformationManager({
        db_table = self.snippets_table,
        dialog_title = _("Snippets Manager"),
        top_buttons_left = {
            {
                icon = "info-slender",
                callback = function()
                    DX.i:showSnippetsExplanation(2)
                end,
            }
        },
        item_hint = _("snippet name"),
        item_name = _("snippet"),
        show_value_in_list_also = true,
        value_hint = _("snippet text"),
        after_save_callback = function(list, entry_name)
            --* returns a select_number:
            return self:updateSnippetsList(list, entry_name)
        end,
    })
end

function TextSnippets:updateSnippetsList(list, entry_name)
    self.help_info = nil
    local select_number = 1
    if list then
        self.snippets, select_number = KOR.informationmanager:getGroupedItems(list, entry_name)
    elseif not self.snippets then
        self.snippets = KOR.informationmanager:getGroupedItemsFromDb(self.snippets_table)
    end
    return select_number
end

--* called from ((InputText#initTextBox)):
--* first_word_char was determined by ((Strings#getFirstCharOfLastWord)):
--* we only replace snippets which were found at the end of text:
---@ param first_word_char string
function TextSnippets:insert(text, first_word_char)
    self:init()
    --! don't remove this call, even though this call is also done in self#init, because otherwise KOReader would crash upon entering text in a dialog (probably because snippets were not populated upon KOReader start):
    self:updateSnippetsList()
    if not text or not self.snippets[first_word_char] then
        --* in these cases we don't return a new charpos as second return value:
        return text
    end

    local uc_needle, uc_substitution
    local pre_marker = "(%s+[(\"']?)"
    local after_marker = "(%)?[ .,:;!?\"'])$"
    for needle, substitution in pairs(self.snippets[first_word_char]) do
        uc_needle = KOR.strings:ucfirst(needle, "force_only_first")
        uc_substitution = KOR.strings:ucfirst(substitution, "force_only_first")
        text = text
            :gsub(pre_marker .. needle .. after_marker, "%1" .. substitution .. "%2", 1)
            :gsub(pre_marker .. uc_needle .. after_marker, "%1" .. uc_substitution .. "%2", 1)
    end
    --* the second return value is the (new) charpos:
    return text, KOR.strings:length(text) + 1
end

--- @private
function TextSnippets:closeDialogUponEscapeString(content)

    if not content:match(" esc $") then
        return false
    end

    if KOR.dialogsqueue:getQueueCount() > 1 then
        KOR.dialogsqueue:restorePrevious()
        return true
    end

    UIManager:close(KOR.registry.dialog_widget)
    KOR.registry.dialog_widget = nil

    return true
end

function TextSnippets:handleCommands(content, first_word_char)

    if self:closeDialogUponEscapeString(content) then
        return "", false
    end

    --* #w: remove n words from end:
    local remove_words = content:match(" (%d+w)")
    if remove_words then
        local word_count = remove_words:gsub("w$", "", 1)
        word_count = tonumber(word_count)
        local needle = string_rep(" [^ ]- ?", word_count) .. remove_words
        return content
            --* created needles like :gsub(" [^ ]- ?1w$", " ", 1) etc.; replace the requested number of words by a space:
            :gsub(needle, " ", 1), true
    end

    --* convert line to uppercase heading by appending "hex" to text + space on that line:
    if first_word_char == "h" then
        local heading = content:match("([^\n]+) [Hh]ex")
        if heading then
            return content:gsub("[^\n]+ [Hh]ex", heading:upper(), 1), true
        end
    end

    --* convert sentence to ucfirst by appending "ucx" to text + space of that sentence:
    if first_word_char == "u" then
        local ucfirst = content:match("([^;:,.?!'\"\n]*) [Uu]cx")
        if ucfirst then
            ucfirst = KOR.strings:ucfirst(ucfirst, "force_only_first")
            return content:gsub("[^\n]+ [Uu]cx", ucfirst, 1), true
        end
    end

    --* #x: remove n chars from end:
    local remove_count = content:match(" (%d+)x$")
    if remove_count then
        content = content:gsub(" %d+x$", "", 1)
        remove_count = tonumber(remove_count)
        local base = "."
        local replace = base:rep(remove_count) .. "$"
        return content
            :gsub(replace, "", 1), true
    end

    --* #k: inject comma n words from end:
    local inject_comma = content:match(" (%d+k)$")
    if inject_comma then
        content = content:gsub(" (%d+k)$", "", 1)
        local word_count = inject_comma:gsub("k$", "", 1)
        word_count = tonumber(word_count)
        local needle = " +(" .. string_rep("[^ ]+ +", word_count)
        --* remove last space:
        needle = needle:gsub(" %+$", "", 1)
        needle = needle .. ")$"
        return content
            --* create needles like :gsub(" +([^ ]+ +[^ ]+ +[^ ]+)$", ", %1 ", 1)
            :gsub(needle, ", %1", 1), true
    end

    if content:match(" [Ww]w$") then
        return content
            --* delete last word by appending " ww" to it:
            :gsub(" [^ ]+ [Ww]w$", " ", 1), true
    end

    --* delete entire last sentence by appending " ssx" to it:
    if content:match(" [Ss]sx$") then
        return content
            :gsub("[^.?!\n]+[.?!'\"]? [Ss]sx$", "", 1)
    end

    if content:match(" [XxSsPp]x$") then
        return content
            --* delete last char by appending "xx" to it:
            :gsub(". ?[Xx]x$", "", 1)
            --* delete last sentence (part) by appending " sx" to it:
            :gsub("[^;:,.?!'\"\n]+[.?!'\"]? [Ss]x$", "", 1)
            --* delete entire last paragraph part by appending " px" to it:
            :gsub("[^\n]* [Pp]x$", "", 1), true
    end

    --* show shortcuts explanation by typing " ii" at end of line:
    if content:match(" ii$") then
        DX.i:showSnippetsExplanation(2)
        return content:gsub(" ii$", "", 1)
    end

    return content, false
end

return TextSnippets
