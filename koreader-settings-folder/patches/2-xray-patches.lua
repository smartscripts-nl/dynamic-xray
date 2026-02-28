--- @class XrayPatches

--[[
    Runtime KOReader patches executed ONLY on userpatch.before_exit
--]]

--! patches in this file:
-- ((PATCH CREDOCUMENT))
-- ((PATCH READERVIEW))
-- ((PATCH UIMANAGER))
-- ((PATCH READERDICTIONARY))
--! I didn't patch DictQuickLookup, to add a add Xray item button to the dictionary dialog; dialog code for me too complicated to patch...
-- ((PATCH READERTOC))
-- ((PATCH READERHIGHLIGHT))
--* ((PATCH READERSEARCH)) some methods completely replaced...
-- ((PATCH LUASETTINGS))
-- ((PATCH BOOKSTATUSWIDGET))
-- ((PATCH PLUGINLOADER))


local require = require

--! VERY IMPORTANT: extend package.path and load the KOR system first!:
--* ============ LOAD EXTENSIONS SYSTEM ===============

local DataStorage = require("datastorage")

local package = package

-- #((patch: add Dynamic Xray to KOReader))
package.path = DataStorage:getDataDir() .. "/extensions/?.lua;" .. package.path
require("extensions/xraycontroller/xraycontroller")

--* =====================================================

local BD = require("ui/bidi")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local Button = require("extensions/widgets/button")
local CanvasContext = require("document/canvascontext")
local CheckButton = require("ui/widget/checkbutton")
--- @class CreDocument
local CreDocument = require("document/credocument")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KOR = require("extensions/kor")
local LuaSettings = require("luasettings")
local Menu = require("extensions/widgets/menu")
local PluginLoader = require("pluginloader")
--- @class ReaderDictionary
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
--- @class ReaderHighlight
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
--- @class ReaderSearch
local ReaderSearch = require("apps/reader/modules/readersearch")
--- @class ReaderToc
local ReaderToc = require("apps/reader/modules/readertoc")
--- @class ReaderView
local ReaderView = require("apps/reader/modules/readerview")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
--! only use tr for DX related modules:
local tr = KOR:initCustomTranslations()
local util = require("util")
local Screen = Device.screen
local Utf8Proc = require("ffi/utf8proc")
local T = require("ffi/util").template

local cre --* Delayed loading
local DX = DX
local error = error
local G_reader_settings = G_reader_settings
local has_no_items = has_no_items
local has_no_text = has_no_text
local has_text = has_text
local ipairs = ipairs
local math = math
local next = next
local pcall = pcall
local select = select
local table = table
local table_concat = table.concat
local table_insert = table.insert
local tonumber = tonumber
local tostring = tostring
local type = type

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

CreDocument.empty_line = " <br/>"
CreDocument.paragraphs_cached = {}
CreDocument.text_indent = "     "

function CreDocument:setDocument()
    local ok
    ok, self._document = pcall(cre.newDocView, CanvasContext:getWidth(), CanvasContext:getHeight(), self._view_mode)
    if not ok then
        error(self._document)  --* will contain error message
    end
end

--* populates self.paragraphs, to be used in ((ReaderView#paintTo)) > ((XrayUI#ReaderViewGenerateXrayInformation)):
function CreDocument:storeCurrentPageParagraphs(page_xp, starting_page)

    self.start_page_no = starting_page or self:getPageFromXPointer(page_xp)
    if self.paragraphs_cached[self.start_page_no] then
        self.paragraphs = self.paragraphs_cached[self.start_page_no]
        return
    end

    self.paragraphs = {}

    self.paragraphs = KOR.pagetexts:getAllHtmlContainersInPage(page_xp, self.start_page_no)
    self.paragraphs_cached[self.start_page_no] = self.paragraphs
end

function CreDocument:resetParagraphsCache()
    self.paragraphs_cached = {}
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

function CreDocument:getPageText(page_no)
    local xp = self:getPageXPointer(page_no)
    if has_no_text(xp) then
        return ""
    end
    local next_page_no = page_no + 1
    local next_page_xp = self:getPageXPointer(next_page_no)

    --* if we have the xp of a next page, we can get the page text much quicker:
    if has_text(next_page_xp) then
        return self:getPageTextFromXPs(xp, next_page_xp)
    end

    local texts = select(2, KOR.pagetexts:getAllHtmlContainersInPage(xp, page_no))
    if has_no_items(texts) then
        return ""
    end
    return table_concat(texts, "\n" .. self.text_indent)
end

function CreDocument:getPageHtml(page_no, mark_text)
    local xp = self:getPageXPointer(page_no)
    if has_no_text(xp) then
        return ""
    end
    local html

    --* if we have the xp of a next page, we can get the page text much quicker:
    local next_page_no = page_no + 1
    local next_page_xp = self:getPageXPointer(next_page_no)
    if has_text(next_page_xp) then
        html = self:getPageTextFromXPs(xp, next_page_xp, "as_html")
        if mark_text then
            return html:gsub(mark_text, "<strong>" .. mark_text .. "</strong>")
        end
        return html
    end

    local texts = select(2, KOR.pagetexts:getAllHtmlContainersInPage(xp, page_no, "include_punctuation"))
    if has_no_items(texts) then
        return ""
    end
    html = table_concat(texts, "<br/>" .. self.text_indent)
    if mark_text then
        html = html:gsub(mark_text, "<strong>" .. mark_text .. "</strong>")
    end
    return html
end

--* return page text, format it with indents and add whitespace around separators in the text:
--- @private
function CreDocument:getPageTextFromXPs(xp, next_page_xp, as_html)
    local text = self:getTextFromXPointers(xp, next_page_xp)
    text = text:gsub("\n[ \t]+", "\n")
    local formatted = {}
    local lb = as_html and "<br/>" or "\n"
    local parts = KOR.strings:split(text, "\n")
    count = #parts
    local separator_was_inserted = false
    for i = 1, count do
        if i == 1 then
            table_insert(formatted, parts[i] .. lb)
        --* handle separators in the text:
        elseif not parts[i]:match("[A-Za-z0-9]") then
            separator_was_inserted = true
            table.insert(formatted, self.empty_line)
            if as_html then
                table_insert(formatted, "<p style='text-align: center'>" .. parts[i] .. "</p>")
            else
                table_insert(formatted, parts[i] .. lb)
            end
            table.insert(formatted, self.empty_line)
        else
            local prefix = not separator_was_inserted and self.text_indent or ""
            table_insert(formatted, prefix .. parts[i] .. lb)
            separator_was_inserted = false
        end
    end
    return table_concat(formatted, "")
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


--- PATCH UIMANAGER
-- #((PATCH UIMANAGER))
--* called from ((Files#openFile)):
function UIManager:closeAllWidgetsExceptMainScreen()
    --* i bigger than 1: we keep window 1, the reader or FileManager screen:
    count = #self._window_stack
    local w
    for i = count, 2, -1 do
        w = self._window_stack[i].widget
        w:handleEvent(Event:new("FlushSettings"))
        --* ...and notify it that it ought to be gone now.
        w:handleEvent(Event:new("CloseWidget"))
    end
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

ReaderToc.cached_positions = {}
ReaderToc.cached_positions_index = {}
ReaderToc.cached_titles = {}
ReaderToc.cached_titles_index = nil

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

function ReaderToc:getPageFromItemIndex(index)
    self:fillToc()
    if self.toc[index] then
        return self.toc[index].page
    end
end

function ReaderToc:getPageFromItemTitle(title)
    self:fillToc()
    count = #self.toc
    for i = 1, count do
        if self.toc[i].title == title then
            return self.toc[i].page
        end
    end
end

function ReaderToc:getTocXpointers(file)
    if not file then
        file = KOR.registry.current_ebook
    end
    local index = KOR.tables:normalizeTableIndex(file)
    if index and self.cached_positions_index == index then
        return self.cached_positions[index]
    end
    self.cached_positions_index = index
    self.cached_positions[index] = {}
    self:fillToc()
    if not self.toc then
        return
    end
    count = #self.toc
    for i = 1, count do
        table_insert(self.cached_positions[index], {
            self.toc[i].xpointer,
            self.toc[i].page,
        })
    end
    return self.cached_positions[index]
end

function ReaderToc:getTocTitles(file)
    file = file or DX.m.current_ebook_full_path
    local index = KOR.tables:normalizeTableIndex(file)
    if index and self.cached_titles_index == index then
        return self.cached_titles[index]
    end
    self.cached_titles_index = index
    self.cached_titles[index] = {}
    self:fillToc()
    if not self.toc then
        return
    end
    count = #self.toc
    for i = 1, count do
        table_insert(self.cached_titles[index], self.toc[i].title)
    end
    return self.cached_titles[index]
end

function ReaderToc:getChapterPropsByIndex(n)
    self:fillToc()
    if not self.toc then
        return
    end
    return self.toc[n]
end



--- PATCH READERHIGHLIGHT
-- #((PATCH READERHIGHLIGHT))

local orig_init = ReaderHighlight.init
ReaderHighlight.init = function(self)
    orig_init(self)
    self:addToHighlightDialog("40_add_xray_item", function(this)
        return {
            text = tr("+ Xray item"),
            callback = function()
                local text = util.cleanupSelectedText(this.selected_text.text)
                text = KOR.strings:prepareForDisplay(text, "separate_paragraphs")
                this:onClose()
                DX.fd.saveNewItem(text)
            end,
        }
    end)
    self:addToHighlightDialog("41_add_xray_quote", function(this)
        return {
            text = tr("+ Xray quote"),
            callback = function()
                local pos0 = self.selected_text.pos0
                local quote = util.cleanupSelectedText(this.selected_text.text)
                this:onClose()
                -- #((Xray quote from existing bookmark))
                KOR.registry:set("xray_quote_props", {
                    pos0 = pos0,
                    quote = quote,
                })
                --* see ((XrayDialogs#_prepareItemsForList)) for the callback to be supplied with the selected item:
                DX.c:onShowList(nil, false, "save_quote")
            end,
        }
    end)
end

local orig_onShowHighlightMenu = ReaderHighlight.onShowHighlightMenu
ReaderHighlight.onShowHighlightMenu = function(self, index)
    local glossary_boundaries = KOR.registry:get("mark_glossary_boundaries")
    if glossary_boundaries then
        if #glossary_boundaries == 0 then
            table_insert(glossary_boundaries, self.selected_text.pos0)
            self:onClose()
            KOR.messages:notify(tr("start of glossary has been registered; now mark the end of it"))
            return
        end
        table_insert(glossary_boundaries, self.selected_text.pos1)
        self:onClose()
        DX.pn:addGlossary(glossary_boundaries)
        return
    end
    orig_onShowHighlightMenu(self, index)
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
    if DX.u:ReaderHighlightGenerateXrayInformation(pos, "tap") then
        return true
    end
    return orig_onTap(self, _, ges)
end

local orig_onHold = ReaderHighlight.onHold
ReaderHighlight.onHold = function(self, arg, ges)
    if self.document.info.has_pages and self.panel_zoom_enabled then
        local res = self:onPanelZoom(arg, ges)
        if res or not self.panel_zoom_fallback_to_text_selection then
            return res
        end
    end

    self:clear() --* clear previous highlight (delayed clear may not have done it yet)
    self.hold_ges_pos = ges.pos --* remember hold original gesture position
    self.hold_pos = KOR.view:screenToPageTransform(ges.pos)
    if not self.hold_pos then
        return false
    end

    if DX.u:ReaderHighlightGenerateXrayInformation(self.hold_pos, "hold") then
        return true
    end
    return orig_onHold(self, arg, ges)
end

local orig_saveHighlight = ReaderHighlight.saveHighlight
-- #((ReaderHighlight#saveHighlight))
ReaderHighlight.saveHighlight = function(self, extend_to_sentence)
    orig_saveHighlight(self, extend_to_sentence)
    local acount = self.ui.annotation.annotations and #self.ui.annotation.annotations
    KOR.seriesmanager:setAnnotationsCount(DX.m.current_ebook_full_path, acount)
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
            table_insert(ft, "[[[")
            if item.matched_word_prefix then
                table_insert(ft, item.matched_word_prefix)
            end
            table_insert(ft, word)
            if item.matched_word_suffix then
                table_insert(ft, item.matched_word_suffix)
            end
            table_insert(ft, "]]]")

            --* Make this word bolder, using Poor Text Formatting provided by TextBoxWidget
            --* (we know this text ends up in a TextBoxWidget).
            table_insert(t, TextBoxWidget.PTF_BOLD_START)

            if item.matched_word_prefix then
                table_insert(t, item.matched_word_prefix)
            end
            table_insert(t, word)
            if item.matched_word_suffix then
                table_insert(t, item.matched_word_suffix)
            end
            table_insert(t, TextBoxWidget.PTF_BOLD_END)
            if item.prev_text then
                table_insert(ft, 1, item.prev_text)
                table_insert(ft, 2, " ")
                --* expand the bold texts in the list with a couple of words:
                self:injectCompactBoldHitContext(t, item.prev_text, -compact_context_wordcount, "at_start")
                table_insert(t, 2, " ")
            end
            if item.next_text then
                table_insert(ft, " ")
                table_insert(ft, item.next_text)
                table_insert(t, " ")
                --* expand the bold texts in the list with a couple of words:
                self:injectCompactBoldHitContext(t, item.next_text, compact_context_wordcount, false)
            end
            --* enable handling of our bold tags:
            table_insert(t, 1, TextBoxWidget.PTF_HEADER)
            item.text = table_concat(t, "")

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
            item.full_text = table_concat(ft, "")
            item.nr = i
        end
        self.cached_select_number = select_number

        self.all_hits = self.findall_results
    end

    local last_search = self.last_search_text
    self.result_menu = Menu:new{
        title = T(tr("Search results (%1)"), #self.findall_results),
        subtitle = T(tr("search term: %1"), last_search),
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
                info = T(tr("user lamp icon | Add \"%1\" as new Xray-item."), last_search),
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
            local context_info = T(tr("Page: %1"), item.mandatory) .. "\n"
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
            table_insert(text, 1, words[i])
            table_insert(text, 2, " ")
        end
        return
    end

    for i = 1, count do
        table_insert(text, words[i])
        table_insert(text, " ")
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
                    icon = "first",
                    callback = function()
                        self:toFirstHit()
                    end,
                },
                {
                    icon = "previous",
                    callback = function()
                        self:toPrevHit()
                    end,
                },
                KOR.buttoninfopopup:forSearchAllLocationsGotoLocation({
                    callback = function()
                        self:closeHitviewer("close_item_viewer")
                        KOR.dialogs:closeAllOverlays()
                        DX.pn:closePageNavigator()
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
                KOR.buttoninfopopup:forSearchAllLocationsGotoPageNavigator({
                    callback = function()
                        self:closeHitviewer("close_item_viewer")
                        KOR.dialogs:closeAllOverlays()
                        local page = KOR.document:getPageFromXPointer(item.start)
                        -- #((jump from ReaderSearch to Xray Page Navigator))
                        DX.sp:resetActiveSideButtons("ReaderSearch:showHitWithContext")
                        DX.pn:setProp("page_no", page)
                        DX.pn:restoreNavigator()
                    end,
                }),
                {
                    icon = "next",
                    callback = function()
                        self:toNextHit()
                    end,
                },
                {
                    icon = "last",
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

--* called from Labels.context button in ((XrayDialogs#onMenuHold)):
function ReaderSearch:onShowTextLocationsForNeedle(needle, case_insensitive)
    if has_no_text(needle) then
        KOR.messages:notify(tr("you forgot to supply a search term..."))
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
    self.whole_words_only = self.check_whole_words_only and self.check_whole_words_only.checked or false
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
        return
    end

    --* no regex error:
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
        return
    end

    Trapper:wrap(function()
        self:findAllText(search_text)
    end)
end

function ReaderSearch:onShowFulltextSearchInput()
    local backward_text = "◁"
    local forward_text = "▷"
    if BD.mirroredUILayout() then
        backward_text, forward_text = forward_text, backward_text
    end
    -- #((initial readersearch dialog))
    self.input_dialog = InputDialog:new{
        title = tr("Enter text to search for"),
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


--- PATCH BOOKSTATUSWIDGET
-- #((PATCH BOOKSTATUSWIDGET))
local orig_onChangeBookStatus = BookStatusWidget.onChangeBookStatus
BookStatusWidget.onChangeBookStatus = function(self, option_name, option_value)
    if option_name[option_value] == "complete" then
        KOR.seriesmanager:setBookFinishedStatus(DX.m.current_ebook_full_path)
    end
    orig_onChangeBookStatus(self, option_name, option_value)
end
local orig_setStar = BookStatusWidget.setStar
BookStatusWidget.setStar = function(self, num)
    orig_setStar(self, num)
    KOR.seriesmanager:setStars(DX.m.current_ebook_full_path, num)
end


--- PATCH PLUGINLOADER
-- #((PATCH PLUGINLOADER))

local DEFAULT_PLUGIN_PATH = "plugins"
function PluginLoader:_addXrayPluginFolder(data_dir, extra_paths, lookup_path_list)
    local extra_path = data_dir .. "/plugins"
    local extra_path_mode = lfs.attributes(extra_path, "mode")
    if extra_path_mode ~= "directory" or extra_path == DEFAULT_PLUGIN_PATH then
        return
    end

    extra_paths = extra_paths or {}
    if KOR.tables:tableHasNot(extra_paths, extra_path) then
        table_insert(lookup_path_list, extra_path)
        table_insert(extra_paths, extra_path)
        G_reader_settings:saveSetting("extra_plugin_paths", extra_paths)
    end
end

--! here we overwrite the original 2025.10 loader:
function PluginLoader:_discover()
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
    if type(plugins_disabled) ~= "table" then
        plugins_disabled = {}
    end

    local discovered = {}
    local lookup_path_list = { DEFAULT_PLUGIN_PATH }
    local extra_paths = G_reader_settings:readSetting("extra_plugin_paths")
    local data_dir = DataStorage:getDataDir()
    if extra_paths then
        if type(extra_paths) == "string" then
            extra_paths = { extra_paths }
        end
        if type(extra_paths) == "table" then
            for _, extra_path in ipairs(extra_paths) do
                local extra_path_mode = lfs.attributes(extra_path, "mode")
                if extra_path_mode == "directory" and extra_path ~= DEFAULT_PLUGIN_PATH then
                    table_insert(lookup_path_list, extra_path)
                end
            end
        else
            logger.err("extra_plugin_paths config only accepts string or table value")
        end
    else
        if data_dir ~= "." then
            local extra_path = data_dir .. "/plugins"
            extra_paths = { extra_path }
            G_reader_settings:saveSetting("extra_plugin_paths", extra_paths)
            table_insert(lookup_path_list, extra_path)
        end
    end

    --! addition for Dynamic Xray:
    self:_addXrayPluginFolder(data_dir, extra_paths, lookup_path_list)

    for _, lookup_path in ipairs(lookup_path_list) do
        logger.info("Looking for plugins in directory:", lookup_path)
        for entry in lfs.dir(lookup_path) do
            local plugin_root = lookup_path .. "/" .. entry
            local mode = lfs.attributes(plugin_root, "mode")
            -- A valid KOReader plugin directory ends with .koplugin
            if mode == "directory" and entry:sub(-9) == ".koplugin" then
                local mainfile = plugin_root .. "/main.lua"
                local metafile = plugin_root .. "/_meta.lua"
                local disabled = false
                if plugins_disabled and plugins_disabled[entry:sub(1, -10)] then
                    mainfile = metafile
                    disabled = true
                end
                local name = select(2, util.splitFilePathName(plugin_root))

                table_insert(discovered, {
                    ["main"] = mainfile,
                    ["meta"] = metafile,
                    ["path"] = plugin_root,
                    ["disabled"] = disabled,
                    ["name"] = name,
                })
            end
        end
    end
    return discovered
end
