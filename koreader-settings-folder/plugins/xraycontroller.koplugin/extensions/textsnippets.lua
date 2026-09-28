
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local pairs = pairs
local table_concat = table_concat
local table_insert = table_insert
local table_sort = table_sort

local count

--- @class TextSnippets
local TextSnippets = WidgetContainer:extend{
    help_info = nil,
    --* these are loaded via InformationManager from table snippets:
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
    self.help_info = table_concat(KOR.tables:merge(KOR.textcommands.commands_info, snippets), "\n")
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

return TextSnippets
