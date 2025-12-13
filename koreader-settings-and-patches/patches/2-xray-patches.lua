
--- @class XrayPatches

--[[
    Runtime KOReader patches executed ONLY on userpatch.before_exit
--]]

--! patches in this file:
-- ((PATCH CREDOCUMENT))
-- ((PATCH READERVIEW))
-- ((PATCH READERDICTIONARY))
--! I didn't patch DictQuickLookup, to add a add Xray item button to the dictionary dialog; dialog code for me too complicated to patch...
-- ((PATCH READERTOC))
-- ((PATCH READERHIGHLIGHT))
--* ((PATCH READERSEARCH)) some methods completely replaced...
-- ((PATCH LUASETTINGS))
-- ((PATCH MOVABLECONTAINER))


local require = require

--! VERY IMPORTANT: extend package.path and load the KOR system first!:
--* ============ LOAD EXTENSIONS SYSTEM ===============

package.path = "frontend/extensions/?.lua;" .. package.path
require("extensions/korinit")

--* =====================================================

local BD = require("ui/bidi")
local CanvasContext = require("document/canvascontext")
local CheckButton = require("ui/widget/checkbutton")
local CreDocument = require("document/credocument")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KOR = require("extensions/kor")
local LuaSettings = require("luasettings")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderView = require("apps/reader/modules/readerview")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local tr = KOR:initCustomTranslations()
local util = require("util")
local Screen = Device.screen
local Utf8Proc = require("ffi/utf8proc")
local T = require("ffi/util").template

local cre --* Delayed loading
local DX = DX
local error = error
local has_no_text = has_no_text
local math = math
local pcall = pcall
local table = table
local tonumber = tonumber

local help_text = _([[
Regular expressions allow you to search for a matching pattern in a text. The simplest pattern is a simple sequence of characters, such as `James Bond`. There are many different varieties of regular expressions, but we support the ECMAScript syntax. The basics will be explained below.

If you want to search for all occurrences of 'Mister Moore', 'Sir Moore' or 'Alfons Moore' but not for 'Lady Moore'.
Enter 'Mister Moore|Sir Moore|Alfons Moore'.

If your search contains a special character from ^$.*+?()[]{}|\/ you have to put a \ before that character.

Examples:
Words containing 'os' -> '[^ ]+os[^ ]+'
Any single character '.' -> 'r.nge'
Any characters '.*' -> 'J.*s'
Numbers -> '[0-9]+'
Character range -> '[a-f]'
Not a space -> '[^ ]'
A word -> '[^ ]*[^ ]'
Last word in a sentence -> '[^ ]*\.'

Complex expressions may lead to an extremely long search time, in which case not all matches will be shown.]])

local SRELL_ERROR_CODES = {}
SRELL_ERROR_CODES[102] = _("Wrong escape '\\'")
SRELL_ERROR_CODES[103] = _("Back reference does not exist.")
SRELL_ERROR_CODES[104] = _("Mismatching brackets '[]'")
SRELL_ERROR_CODES[105] = _("Mismatched parens '()'")
SRELL_ERROR_CODES[106] = _("Mismatched brace '{}'")
SRELL_ERROR_CODES[107] = _("Invalid Range in '{}'")
SRELL_ERROR_CODES[108] = _("Invalid character range")
SRELL_ERROR_CODES[110] = _("No preceding expression in repetition.")
SRELL_ERROR_CODES[111] = _("Expression too complex, some hits will not be shown.")
SRELL_ERROR_CODES[666] = _("Expression may lead to an extremely long search time.")


--- PATCH CREDOCUMENT
-- #((PATCH CREDOCUMENT))

function CreDocument:setDocument()
    local ok
    ok, self._document = pcall(cre.newDocView, CanvasContext:getWidth(), CanvasContext:getHeight(), self._view_mode)
    if not ok then
        error(self._document)  --* will contain error message
    end
end

--* populates self.paragraphs, to be used in ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation)):
function CreDocument:storeCurrentPageParagraphs(page_xp, starting_page)

    self.paragraphs = {}

    self.start_page_no = starting_page or self:getPageFromXPointer(page_xp)

    self.paragraphs = KOR.html:getAllHtmlContainersInCurrentPage(page_xp, self.start_page_no)
end

--* pattern %f[%w_] ... %f[^%w_] in normal matches emulates word boundaries, but this doesn't work in CreDocument context:
CreDocument.word_boundary_start = "[ .\"'\n‘“¡¿]"
CreDocument.word_boundary_end = "[ .,!?;:\"'\n’”]"
function CreDocument:findAllTextWholeWords(pattern, case_insensitive, nb_context_words, max_hits)
    local regex = true
    if not self._document then
        self:setDocument()
    end
    pattern = self.word_boundary_start .. pattern .. self.word_boundary_end
    return self._document:findAllText(pattern, case_insensitive, regex, max_hits, true, nb_context_words)
end



--- PATCH READERVIEW
-- #((PATCH READERVIEW))

-- #((ReaderView#resetIconPositionsRegistry))
function ReaderView:resetIconPositionsRegistry()
    self.icon_y_positions = { {}, {} }
end

local orig_paintTo = ReaderView.paintTo
ReaderView.paintTo = function(self, bb, x, y)
    --! this statement is crucial, to make sure icons are not shifted below their original y position upon redraws:
    self:resetIconPositionsRegistry()

    orig_paintTo(self, bb, x, y)

    if not KOR.registry:get("ReaderSearch_active") then
        DX.u:ReaderViewGenerateXrayInformation(self.ui, bb, x, y)
    end
end

local orig_onReaderReady = ReaderView.onReaderReady
ReaderView.onReaderReady = function(self)
    self:resetIconPositionsRegistry()
    orig_onReaderReady(self)
end

local orig_recalculate = ReaderView.recalculate
ReaderView.recalculate = function(self)
    self:resetIconPositionsRegistry()
    orig_recalculate(self)
end


--- PATCH READERDICTIONARY
-- #((PATCH READERDICTIONARY))

local orig_onLookupWord = ReaderDictionary.onLookupWord
ReaderDictionary.onLookupWord = function(self, word, is_sane, boxes, highlight, link, dict_close_callback)
    --* if an Xray item was recognized, show its info instead of the Dictionary dialog:
    if DX.tw:getXrayItemAsDictionaryEntry(word) then
        highlight:clear()
        return true
    end

    return orig_onLookupWord(self, word, is_sane, boxes, highlight, link, dict_close_callback)
end


--- PATCH READERTOC
-- #((PATCH READERTOC))

function ReaderToc:getChapterStartPage(pn_or_xp)
    pn_or_xp = tonumber(pn_or_xp) or KOR.document:getPageFromXPointer(pn_or_xp)
    local ticks = self:getTocTicksFlattened(true)
    if not ticks or #ticks == 0 then
        return 1
    end
    --* isChapterStart also uses ticks; so if not available above, this call wouldn't make sense:
    if self:isChapterStart(pn_or_xp, ticks) then
        return pn_or_xp
    end
    local count = #ticks
    if pn_or_xp <= ticks[1] then
        return ticks[1]
    end
    for i = 2, count do
        if pn_or_xp < ticks[i] then
            return ticks[i - 1]
        end
    end
    --* no ticks[i] > pn_or_xp found, so return start_page of last chapter:
    return ticks[count]
end

--- @param pos0 string The pos0/page prop for the text for which we want to generate context_info
function ReaderToc:getTocLastChapterInfo(pos0, chapters)
    if not chapters then
        chapters = self:getFullTocTitleByPage(pos0)
    end
    --* this should be the title of the last chapter:
    return (table.remove(chapters) or "")
end


--- PATCH READERHIGHLIGHT
-- #((PATCH READERHIGHLIGHT))

local orig_init = ReaderHighlight.init
ReaderHighlight.init = function(self)
    orig_init(self)
    self:addToHighlightDialog("12_add_xray_item", function(this)
        return {
            text = tr("+ Xray item"),
            callback = function()
                local text = util.cleanupSelectedText(this.selected_text.text)
                text = KOR.strings:prepareForDisplay(text, "separate_paragraphs")
                this:onClose(true)
                DX.fd.saveNewItem(text)
            end,
        }
    end)
end

local orig_onTap = ReaderHighlight.onTap
ReaderHighlight.onTap = function(self, _, ges)
    if self.hold_pos then
        -- accidental tap while long-pressing
        return self:onHoldRelease()
    end
    if not ges then
        return false
    end
    local pos = self.view:screenToPageTransform(ges.pos)
    if KOR.xrayui:ReaderHighlightGenerateXrayInformation(pos) then
        return true
    end
    return orig_onTap(self, _, ges)
end


--- PATCH READERSEARCH
-- #((PATCH READERSEARCH))

local orig_search_init = ReaderSearch.init
ReaderSearch.init = function(self)
    orig_search_init(self)
    KOR:registerModule("readersearch", self)
end

ReaderSearch.whole_words_only = false

--* called from Labels.context button in ((XrayDialogs#onMenuHold)):
function ReaderSearch:onShowTextLocationsForNeedle(item, case_insensitive)
    if has_no_text(item) then
        KOR.messages:notify("geen geldige zoekterm opgegeven")
        return
    end
    self:searchCallback(nil, item, case_insensitive)
end

--* if reverse == 1 search backwards
function ReaderSearch:searchCallback(reverse, xray_item_or_highlight, case_insensitive)
    local search_text = xray_item_or_highlight or self.input_dialog:getInputText()
    if has_no_text(search_text) then
        return
    end

    --* search_text comes from our keyboard, and may contain multiple diacritics ordered
    --* in any order: we'd rather have them normalized, and expect the book content to
    --* be proper and normalized text.
    self.ui.doc_settings:saveSetting("fulltext_search_last_search_text", search_text)
    self.last_search_text = search_text --* if shown again, show it as it has been inputted
    search_text = Utf8Proc.normalize_NFC(search_text)
    if xray_item_or_highlight and not case_insensitive then
        self.use_regex = false
        self.case_insensitive = false
    elseif xray_item_or_highlight and case_insensitive then
        self.use_regex = false
        self.case_insensitive = true
    else
        self.use_regex = self.check_button_regex.checked
        self.case_insensitive = not self.check_button_case.checked
    end
    --* when search dialog activated from Xray dialog, nog check_whole_words_only checkbox is available; so in that case assume true:
    self.whole_words_only = self.check_whole_words_only and self.check_whole_words_only.checked or true
    local regex_error = self.use_regex and KOR.document:checkRegex(search_text)
    if self.use_regex and regex_error ~= 0 then
        logger.dbg("ReaderSearch: regex error", regex_error, SRELL_ERROR_CODES[regex_error])
        local error_message
        if SRELL_ERROR_CODES[regex_error] then
            error_message = T(_("Invalid regular expression:\n%1"), SRELL_ERROR_CODES[regex_error])
        else
            error_message = _("Invalid regular expression.")
        end
        UIManager:show(InfoMessage:new{ text = error_message })

        --* no regex error:
    else
        --* when searchAllText triggered from XrayController plugin context menu, there is no input menu to be closed:
        if not xray_item_or_highlight then
            UIManager:close(self.input_dialog)
        end
        --* can be 0 or 1 in this case:
        if reverse then
            self.last_search_hash = nil
            --* calls the bottom button dialog!!!:
            --* so this is another dialog then ((ReaderSearch#onShowFulltextSearchInput)):
            self:onShowSearchDialog(search_text, reverse, self.use_regex, self.case_insensitive)
        else
            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                self:findAllText(search_text)
            end)
        end
    end
end

function ReaderSearch:onShowFulltextSearchInput()
    local backward_text = "◁"
    local forward_text = "▷"
    if BD.mirroredUILayout() then
        backward_text, forward_text = forward_text, backward_text
    end
    -- #((initial readersearch dialog))
    self.input_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9),
        input = self.last_search_text or self.ui.doc_settings:readSetting("fulltext_search_last_search_text"),
        buttons = {
            {
                {
                    icon = "back",
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                KOR.buttoninfopopup:forSearchResetFilter({
                    callback = function()
                        self.input_dialog:setInputText("")
                    end
                }),
                KOR.buttoninfopopup:forSearchAllLocations({
                    is_enter_default = true,
                    info = tr([[search-list-icon | Show all occurrences of this Xray item in the current ebook.
Hotkey %1 H]]),
                    callback = function()
                        self:searchCallback()
                    end,
                }),
                {
                    text = backward_text,
                    callback = function()
                        self:storeCurrentLocation()
                        --* calls the bottom button dialog:
                        self:searchCallback(1)
                    end,
                },
                {
                    text = forward_text,
                    is_enter_default = true,
                    callback = function()
                        self:storeCurrentLocation()
                        --* calls the bottom button dialog:
                        self:searchCallback(0)
                    end,
                },
            },
        },
    }

    self.check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = not self.case_insensitive,
        parent = self.input_dialog,
    }
    self.input_dialog:addWidget(self.check_button_case)
    self.check_button_regex = CheckButton:new{
        text = _("Regular expression (long-press for help)"),
        checked = self.use_regex,
        parent = self.input_dialog,
        hold_callback = function()
            UIManager:show(InfoMessage:new{
                text = help_text,
                width = Screen:getWidth() * 0.9,
            })
        end,
    }
    self.check_whole_words_only = CheckButton:new{
        text = "Whole words",
        checked = self.whole_words_only,
        parent = self.input_dialog,
    }
    if self.ui.rolling then
        self.input_dialog:addWidget(self.check_button_regex)
        self.input_dialog:addWidget(self.check_whole_words_only)
    end

    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

--* if regex == true, use regular expression in pattern
--* if case == true or nil, the search is case insensitive
function ReaderSearch:search(pattern, origin, regex, case_insensitive)
    local direction = self.direction
    local page = self.view.state.page
    if case_insensitive == nil then
        case_insensitive = true
    end
    Device:setIgnoreInput(true)
    local retval, words_found
    if self.whole_words_only then
        retval, words_found = KOR.document:findTextWholeWord(pattern, origin, direction, case_insensitive, self.max_hits)
    else
        retval, words_found = KOR.document:findText(pattern, origin, direction, case_insensitive, page, regex, self.max_hits)
    end

    Device:setIgnoreInput(false)
    self:showErrorNotification(words_found, regex, self.max_hits)
    return retval
end



--- PATCH LUASETTINGS
-- #((PATCH LUASETTINGS))

function LuaSettings:isNilOrFalse(key)
    return self.data[key] == nil or self.data[key] == false
end


--- PATCH MOVABLECONTAINER
-- #((PATCH MOVABLECONTAINER))

function MovableContainer:moveToYPos(target_y_pos)
    if not target_y_pos then
        target_y_pos = 0
    end
    self.dimen = self:getSize()

    self._orig_y = math.floor((Screen:getHeight() - self.dimen.h) / 2)
    self._orig_x = math.floor((Screen:getWidth() - self.dimen.w) / 2)

    local move_by = 0 - self._orig_y + target_y_pos
    self:_moveBy(0, move_by, "restrict_to_screen")
end
