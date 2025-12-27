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

-- #((patch: add Dynamic Xray to KOReader))
package.path = "frontend/extensions/?.lua;" .. package.path
require("extensions/xraycontroller/xraycontroller")

--* =====================================================

local BD = require("ui/bidi")
local Button = require("extensions/widgets/button")
local CanvasContext = require("document/canvascontext")
local CheckButton = require("ui/widget/checkbutton")
local CreDocument = require("document/credocument")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KOR = require("extensions/kor")
local LuaSettings = require("luasettings")
local Menu = require("extensions/widgets/menu")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderView = require("apps/reader/modules/readerview")
local TextBoxWidget = require("ui/widget/textboxwidget")
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
local G_reader_settings = G_reader_settings
local has_no_text = has_no_text
local has_text = has_text
local math = math
local next = next
local pcall = pcall
local table = table
local tonumber = tonumber
local tostring = tostring

local count

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
-- #((ReaderView#paintTo))
ReaderView.paintTo = function(self, bb, x, y)
    --! this statement is crucial, to make sure icons are not shifted below their original y position upon redraws:
    self:resetIconPositionsRegistry()

    orig_paintTo(self, bb, x, y)

    if not KOR.registry:get("ReaderSearch_active") then
        -- #((init xray sideline markers))
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
-- #((ReaderDictionary#onLookupWord))
ReaderDictionary.onLookupWord = function(self, word, is_sane, boxes, highlight, link, dict_close_callback)
    --* if an Xray item was recognized, show its info instead of the Dictionary dialog:
    if DX.tw:getXrayItemAsDictionaryEntry(word) then
        if highlight then
            highlight:clear()
        end
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
    count = #ticks
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

--- @param pos0 string The pos0/page prop for the text for which we want to generate context_info
--- @param context_info string
function ReaderToc:getTocPathInfoForText(pos0, context_info, has_own_title)
    local title
    if has_own_title then
        if not context_info then
            context_info = ""
        end
    else
        title = context_info or "Informatie"
        context_info = ""
    end
    local chapters = self:getFullTocTitleByPage(pos0)
    local last = "• " .. self:getTocLastChapterInfo(pos0, chapters)
    local indent = ""
    if next(chapters) ~= nil then
        count = #chapters
        for i = 1, count do
            context_info = context_info .. indent .. "▾ " .. chapters[i] .. "\n"
            indent = indent .. " "
        end
    end
    return context_info .. indent .. last, title
end

function ReaderToc:getPageFromItemTitle(title)
    count = #self.toc
    for i = 1, count do
        if self.toc[i].title == title then
            return self.toc[i].page
        end
    end
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
    if DX.u:ReaderHighlightGenerateXrayInformation(pos) then
        return true
    end
    return orig_onTap(self, _, ges)
end


--- PATCH READERSEARCH
-- #((PATCH READERSEARCH))

ReaderSearch.all_hits = {}
ReaderSearch.all_hits_current_item = 1
ReaderSearch.last_search_text = ""
ReaderSearch.whole_words_only = false
ReaderSearch.cached_select_number = 1

ReaderSearch.init = function(self)
    self.ui.menu:registerToMainMenu(self)

    --* number of words before and after the search string in All search results
    self.findall_nb_context_words = 80
    self.findall_results_per_page = G_reader_settings:readSetting("fulltext_search_results_per_page") or 14
    self.findall_results_max_lines = G_reader_settings:readSetting("fulltext_search_results_max_lines")

    KOR:registerModule("readersearch", self)
end

function ReaderSearch:findAllText(search_text)
    local last_search_hash = (self.last_search_text or "") .. tostring(self.case_insensitive) .. tostring(self.use_regex)
    local not_cached = self.last_search_hash ~= last_search_hash
    if not_cached then
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()
        local completed, res = Trapper:dismissableRunInSubprocess(function()
            if not self.whole_words_only then
                return KOR.document:findAllText(search_text,
                        self.case_insensitive, self.findall_nb_context_words, self.findall_max_hits, self.use_regex)
            else
                return KOR.document:findAllTextWholeWords(search_text,
                        self.case_insensitive, self.findall_nb_context_words, self.findall_max_hits)
            end
        end, info)
        if not completed then
            return
        end
        UIManager:close(info)
        self.last_search_hash = last_search_hash
        self.findall_results = res
        self.findall_results_item_index = nil
    end
    if self.findall_results then
        self:onShowFindAllResults(not_cached)
    else
        local non_hit_needle = self.last_search_text
        self.last_search_text = ""
        self:onShowFulltextSearchInput()
        KOR.registry:set("notify_case_sensitive", true)
        KOR.messages:notify("geen treffers met " .. non_hit_needle, 5)
    end
end

function ReaderSearch:onShowFindAllResults(not_cached)
    if not self.last_search_hash or (not not_cached and self.findall_results == nil) then
        --* no cached results, show input dialog
        self:onShowFulltextSearchInput()
        return
    end

    --* for consumption in ((XrayDialogs#onMenuHold)):
    KOR.registry:set("reader_search_active", true)

    local select_number = not_cached and 1 or self.cached_select_number
    if self.ui.rolling and not_cached then
        count = #self.findall_results
        local item, word, pageno
        --* append context before and after the word
        local compact_context_wordcount = 7
        local current_page = self.ui:getCurrentPage()
        local t, ft = {}, {}
        for i = 1, count do
            --* items have a start and end prop, which are de facto pos0 and pos1:
            item = self.findall_results[i]
            --* PDF/Kopt shows full words when only some part matches; let's do the same with CRE
            word = item.matched_text or ""
            t = {}
            ft = {}
            --* [[[ and ]]] will be replaced by <b> and </b> in ((Dialogs#htmlBox)):
            table.insert(ft, "[[[")
            if item.matched_word_prefix then
                table.insert(ft, item.matched_word_prefix)
            end
            table.insert(ft, word)
            if item.matched_word_suffix then
                table.insert(ft, item.matched_word_suffix)
            end
            table.insert(ft, "]]]")

            --* Make this word bolder, using Poor Text Formatting provided by TextBoxWidget
            --* (we know this text ends up in a TextBoxWidget).
            table.insert(t, TextBoxWidget.PTF_BOLD_START)

            if item.matched_word_prefix then
                table.insert(t, item.matched_word_prefix)
            end
            table.insert(t, word)
            if item.matched_word_suffix then
                table.insert(t, item.matched_word_suffix)
            end
            table.insert(t, TextBoxWidget.PTF_BOLD_END)
            if item.prev_text then
                table.insert(ft, 1, item.prev_text)
                table.insert(ft, 2, " ")
                --* expand the bold texts in the list with a couple of words:
                self:injectCompactBoldHitContext(t, item.prev_text, -compact_context_wordcount, "at_start")
                table.insert(t, 2, " ")
            end
            if item.next_text then
                table.insert(ft, " ")
                table.insert(ft, item.next_text)
                table.insert(t, " ")
                --* expand the bold texts in the list with a couple of words:
                self:injectCompactBoldHitContext(t, item.next_text, compact_context_wordcount, false)
            end
            --* enable handling of our bold tags:
            table.insert(t, 1, TextBoxWidget.PTF_HEADER)
            item.text = table.concat(t, "")

            --* local pageref
            if self.ui.rolling then
                pageno = KOR.document:getPageFromXPointer(item.start)
            else
                pageno = item.start
            end
            if pageno <= current_page then
                select_number = i
            end
            item.mandatory = pageno --pageref or
            item.mandatory_dim = pageno > current_page
            item.full_text = table.concat(ft, "")
            item.nr = i
        end
        self.cached_select_number = select_number

        self.all_hits = self.findall_results
    end

    local last_search = self.last_search_text
    self.result_menu = Menu:new{
        title = T(_("Search results (%1)"), #self.findall_results),
        subtitle = T("zoekopdracht: %1", last_search),
        top_buttons_left = {
            {
                icon = "plus",
                callback = function()
                    DX.m.saveNewItem(last_search)
                end,
            }
        },
        footer_buttons_left = {
            Button:new(KOR.buttoninfopopup:forSearchNew({
                callback = function()
                    UIManager:close(self.result_menu)
                    self.last_search_text = ""
                    self:onShowFulltextSearchInput()
                end,
            })),
        },
        footer_buttons_right = {
            Button:new(KOR.buttoninfopopup:forSaveToXray({
                info = "gebruiker-lamp-ikoon | Voeg \"" .. last_search .. "\" toe als nieuw Xray-item.",
                callback = function()
                    UIManager:close(self.result_menu)
                    self.last_search_text = ""
                    DX.c:onShowNewItemForm(last_search)
                end,
            })),
        },
        item_table = self.findall_results,
        items_per_page = self.findall_results_per_page,
        items_max_lines = self.findall_results_max_lines,
        multilines_forced = true, --* to always have search_string in bold
        fullscreen = true,
        covers_fullscreen = true,
        enable_bold_words = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuChoice = function(xx, item)
            self:showHitWithContext(item, not_cached)
            self.garbage = xx
        end,
        onMenuHold = function(menu_self, item)
            local title
            local context_info = T(_("Page: %1"), item.mandatory) .. "\n"
            context_info, title = KOR.toc:getTocPathInfoForText(item.start, context_info)
            KOR.dialogs:niceAlert(title, context_info)
            self.garbage = menu_self
            return true
        end,
        close_callback = function()
            KOR.registry:unset("reader_search_active")
            self.findall_results_item_index = self.result_menu:getFirstVisibleItemIndex() --* save page number to reopen
            UIManager:close(self.result_menu)
        end,
    }
    self:updateAllResultsMenu(nil, self.findall_results_item_index)
    UIManager:show(self.result_menu)
    self:showErrorNotification(#self.findall_results)
end

--- @param text table
--- @param context string
function ReaderSearch:injectCompactBoldHitContext(text, context, words_limit, at_start)
    local words = KOR.strings:split(context, " ")
    words = KOR.tables:slice(words, 1, words_limit)
    count = #words
    if at_start then
        for i = count, 1, -1 do
            table.insert(text, 1, words[i])
            table.insert(text, 2, " ")
        end
        return
    end

    for i = 1, count do
        table.insert(text, words[i])
        table.insert(text, " ")
    end
end

function ReaderSearch:showHitWithContext(item, not_cached)
    self:closeHitviewer()
    KOR.dialogs:closeAllOverlays()

    local context_string = item.full_text
    --* [[[ and ]]] - injected in ((ReaderSearch#onShowFindAllResults)) - will be replaced by <b> and </b> in ((Dialogs#htmlBox))
    context_string = KOR.html:textToHtml(context_string)
    context_string = context_string
            :gsub("<p>", "<p>... ", 1)
            :gsub("</p>$", " ...</p>", 1)
    local toc_info = KOR.toc:getTocPathInfoForText(item.start, nil, "has_own_title")
    if has_text(toc_info) then
        toc_info = toc_info .. "\n\n"
    end
    context_string = toc_info .. "<p class='whitespace'>&nbsp;</p>\n" .. context_string

    self.all_hits_current_item = item.nr
    -- #((readersearch all hits navigation))
    local title = self.last_search_text .. ": " .. item.nr .. "/" .. #self.all_hits .. " - pagina " .. item.mandatory
    self.hit_viewer = KOR.dialogs:htmlBox({
        title = title,
        window_size = "fullscreen",
        html = context_string,
        next_item_callback = function()
            self:toNextHit()
        end,
        prev_item_callback = function()
            self:toPrevHit()
        end,
        buttons_table = {
            {
                {
                    icon = "list",
                    --[[icon = "search-all",
                    icon_size_ratio = 0.55,]]
                    callback = function()
                        self:closeHitviewer()
                        self:onShowFindAllResults(not_cached, item.nr)
                    end,
                },
                {
                    text = KOR.icons.first,
                    callback = function()
                        self:toFirstHit()
                    end,
                },
                {
                    text = KOR.icons.previous,
                    callback = function()
                        self:toPrevHit()
                    end,
                },
                KOR.buttoninfopopup:forSearchAllLocationsGotoLocation({
                    callback = function()
                        self:closeHitviewer("close_item_viewer")
                        KOR.dialogs:closeAllOverlays()
                        if self.ui.rolling then
                            KOR.link:addCurrentLocationToStack()
                            KOR.rolling:onGotoXPointer(item.start, item.start) --* show target line marker
                            KOR.document:getTextFromXPointers(item.start, item["end"], true) --* highlight
                        else
                            local page = item.mandatory
                            local boxes = {}
                            count = #item.boxes
                            for i = 1, count do
                                boxes[i] = KOR.document:nativeToPageRectTransform(page, item.boxes[i])
                            end
                            KOR.link:onGotoLink({ page = page - 1 })
                            self.view.highlight.temp[page] = boxes
                        end
                    end,
                }),
                {
                    text = KOR.icons.next,
                    callback = function()
                        self:toNextHit()
                    end,
                },
                {
                    text = KOR.icons.last,
                    callback = function()
                        self:toLastHit()
                    end,
                },
                {
                    icon = "back",
                    callback = function()
                        self:closeHitviewer()
                    end,
                },
            },
        }
    })
end

function ReaderSearch:closeHitviewer(close_item_viewer)
    if self.hit_viewer then
        KOR.dialogs:closeAllOverlays()
        UIManager:close(self.hit_viewer)
        self.hit_viewer = nil
    end
    if close_item_viewer then
        DX.d:closeViewer()
    end
end

function ReaderSearch:storeCurrentLocation()
    if self.ui.rolling then
        KOR.link:addCurrentLocationToStack()
    end
end

function ReaderSearch:toNextHit()
    self.all_hits_current_item = self.all_hits_current_item + 1
    if self.all_hits_current_item > #self.all_hits then
        self.all_hits_current_item = 1
    end
    self:showHitWithContext(self.all_hits[self.all_hits_current_item])
end

function ReaderSearch:toLastHit()
    self.all_hits_current_item = #self.all_hits
    self:showHitWithContext(self.all_hits[self.all_hits_current_item])
end

function ReaderSearch:toFirstHit()
    self.all_hits_current_item = 1
    self:showHitWithContext(self.all_hits[self.all_hits_current_item])
end

function ReaderSearch:toPrevHit()
    self.all_hits_current_item = self.all_hits_current_item - 1
    if self.all_hits_current_item < 1 then
        self.all_hits_current_item = #self.all_hits
    end
    self:showHitWithContext(self.all_hits[self.all_hits_current_item])
end

function ReaderSearch:showHitsHighlighted(current_page, valid_link)
    local other_page = current_page > 1 and current_page - 1 or current_page + 1
    local other_link = KOR.document:getPageXPointer(other_page)
    self.ui.link:onGotoLink({ xpointer = other_link }, "neglect_current_location")
    self.ui.link:onGotoLink({ xpointer = valid_link }, "neglect_current_location")
end

--* called from Labels.context button in ((XrayDialogs#onMenuHold)):
function ReaderSearch:onShowTextLocationsForNeedle(needle, case_insensitive)
    if has_no_text(needle) then
        KOR.messages:notify(_("you forgot to supply a search term..."))
        return
    end
    self:searchCallback(nil, needle, case_insensitive)
end

--* if reverse == 1 search backwards
function ReaderSearch:searchCallback(reverse, xray_item_or_highlight_text, case_insensitive)
    local search_text = xray_item_or_highlight_text or self.input_dialog:getInputText()
    if has_no_text(search_text) then
        return
    end

    --* search_text comes from our keyboard, and may contain multiple diacritics ordered
    --* in any order: we'd rather have them normalized, and expect the book content to
    --* be proper and normalized text.
    self.ui.doc_settings:saveSetting("fulltext_search_last_search_text", search_text)
    self.last_search_text = search_text --* if shown again, show it as it has been inputted
    search_text = Utf8Proc.normalize_NFC(search_text)
    if xray_item_or_highlight_text and not case_insensitive then
        self.use_regex = false
        self.case_insensitive = false
    elseif xray_item_or_highlight_text and case_insensitive then
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
        if not xray_item_or_highlight_text then
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
