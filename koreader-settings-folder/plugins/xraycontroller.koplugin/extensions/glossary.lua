
--* this is an extension for viewing Glossaries per e-book, with content saved from the glossary in an e-book. The Glossary will be stored in text format, to make it searchable.
--* for filling the Glossary with content, ((InformationMediator)) wil be used.

--* saved glossary info can be shown instead of DictQuickLookup widget if a term was found in the Glossary; see ((ReaderDictionary#onLookupWord)) > ((show glossary popup instead of dictionary popup))

--* compare ((ReferenceInformation)); reference_information there is stored in the database, but here the Glossary is stored in the ebook sidecar file

--! the glossary must have entries on separate lines, with the item names at the start of lines !

local require = require

local Device = require("device")
local Font = require("modules/font")
local InputDialog = require("xrayviews/widgets/inputdialog")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_content = has_content
local has_no_text = has_no_text
local has_text = has_text
local table_concat = table_concat
local table_insert = table_insert
local type = type

local count

--* class for maintaining a glossary pertaining to current ebook (e.g. list of characters, word explanations, etc.)
--- @class Glossary
--- @field editor InputDialog
local Glossary = WidgetContainer:extend {
    editor = nil,
    last_edit_pos = nil,
    line_end = "\n",
    --* viewer_instance will be registered to InformationMediator.viewer_instance ...
}

function Glossary:get(remove_whitespace_at_end)
    --* this info could have been saved from the Glossary-button in ReaderHighlight:
    local doc_settings = KOR.ui.doc_settings
    self:convertFromOldFormat(doc_settings)
    local info = doc_settings.glossary or doc_settings:readSetting("glossary") or false
    if not info then
        return false
    end
    if remove_whitespace_at_end then
        info = self:removeWhiteSpaceAtEnd(info)
    else
        local expanded_info = self:addWhiteSpaceAtEnd(info)
        if expanded_info ~= info then
            info = expanded_info
            self:save(info)
        end
    end
    return info
end

--* compare for erasing Reference Information ((ReferenceInformation#erase)):
function Glossary:erase()
    KOR.ui.doc_settings:delSetting("glossary")
    KOR.ui.doc_settings:flush()
    KOR.ui.doc_settings.glossary = nil

    KOR.messages:notify(_("glossary has been erased"))
end

--- @private
function Glossary:convertFromOldFormat(doc_settings)
    local old_info = doc_settings.reference_info or doc_settings:readSetting("reference_info") or false
    if not old_info then
        return
    end

    doc_settings.glossary = old_info
    doc_settings:saveSetting("glossary", old_info)
    doc_settings.reference_info = nil
    doc_settings:delSetting("reference_info")
    doc_settings:flush()
end

function Glossary:addInformation(info)
    local previous_info = self:get("remove_whitespace_at_end")
    if has_no_text(previous_info) then
        previous_info = ""
    else
        previous_info = previous_info .. "\n"
    end
    self:save(previous_info .. info)
end

function Glossary:showEditor(glossary, scroll_to_text)
    if not glossary then
        glossary = self:get()
    end
    local has_info = has_content(glossary)
    if not glossary then
        glossary = ""
    end
    local action = has_info and _("Lookup in/edit") or _("Add to")
    local title = action .. " " .. _("Glossary")
    local buttons = {
        {
            KOR.buttoninfopopup:forGlossaryErase({
                callback = function()
                    KOR.dialogs:confirm(_("Are you sure you want to remove the entire Glossary?"), function()
                        UIManager:close(self.editor)
                        self:save(nil)
                    end)
                end,
            }),
            KOR.buttoninfopopup:forGlossaryCopy({
                callback = function()
                    local info = has_content(self.editor:getInputText()) or nil
                    if info then
                        info = KOR.strings:trim(info)
                        Device.input.setClipboardText(info)
                        KOR.messages:notify(_("glossary copied"))
                    end
                end,
            }),
            KOR.buttoninfopopup:forGlossarySave({
                callback = function()
                    local info = has_content(self.editor:getInputText()) or nil
                    UIManager:close(self.editor)
                    info = self:addWhiteSpaceAtEnd(info)
                    self:save(info)
                    KOR.messages:notify(_("information added to glossary"))
                end,
            }),
            {
                icon = "back",
                icon_size_ratio = 0.7,
                callback = function()
                    UIManager:close(self.editor)
                end
            },
        },
    }
    if has_text(scroll_to_text) then
        title = title .. " - " .. scroll_to_text
        table_insert(buttons[1], 2, KOR.buttoninfopopup:forGlossarySwitchToDictionary({
            callback = function()
                UIManager:close(self.editor)
                KOR.registry:set("skip_glossary", true)
                KOR.dictionary:onLookupWord(scroll_to_text)
            end,
        }))
    end

    self.editor = InputDialog:new{
        title = title,
        input = glossary,
        input_hint = "",
        input_face = Font:getFontFamily("x_smallinfofont", 14),
        para_direction_rtl = false,
        lang = "en",
        fullscreen = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = buttons,
        search_value = scroll_to_text,
        case_sensitive = true,
        top_buttons_left = DX.b:forGlossaryEditorTopLeft(self),
        --* Set/save view and cursor position callback
        view_pos_callback = function(top_line_num, charpos)
            --* This same callback is called with no argument to get initial position, and with arguments to give back final position when closed.
            if top_line_num and charpos then
                self.last_edit_pos = { top_line_num, charpos }
            else
                local prev_pos = self.last_edit_pos
                if type(prev_pos) == "table" and prev_pos[1] and prev_pos[2] then
                    return prev_pos[1], prev_pos[2]
                end
                return nil, nil --* no previous position known
            end
        end,
        copy_button_text = _("Copy"),
        copy_callback = function()
            Device.input.setClipboardText(self.editor:getInputText())
        end,
    }
    UIManager:show(self.editor)
    self.editor:onShowKeyboard(true)
    if has_info then
        self.editor:toggleKeyboard("force_hidden")
    end
    if scroll_to_text then
        --* to display found entry at the top of the dialog, if possible, or otherwise somewhere in the center:
        self.editor:scrollToBottom()
        self.editor:findCallback("force_hidden", nil, true)
    end
end

--* only shown when Glossary was called through a gesture:
--* information for this Glossary was added via ((Glossary#addInformation)):
--* compare ((ReferenceInformation#show))
function Glossary:showViewer()
    local glossary = self:get()
    if KOR.informationmediator:showAlternativeViewer("TYPE_GLOSSARY", glossary) then
        return true
    end

    KOR.dialogsqueue:register({
        id = "glossary_viewer",
        restore = function()
            self:showViewer()
        end,
    })

    local is_tabbed = KOR.referenceinformation.current_ebook_reference_information
    local buttons = DX.b:forGlossaryViewerTopLeft(self, is_tabbed)

    --* if Reference Information available, show that in a second tab:
    --* compare showing Reference Information first and Glossary in second tab in ((ReferenceInformation#show)):
    if is_tabbed then
        KOR.dialogs:htmlBoxTabbed(1, {
            title = _("Glossary + Xray Reference Information"),
            is_reference_information_or_glossary = true,
            tabs = {
                {
                    tab = _("glossary"),
                    --* Glossary is saved as plain-text, but shown as HTML:
                    content_type = "html",
                    html = self:getHtmlList(glossary),
                },
                {
                    tab = _("reference information"),
                    html = KOR.referenceinformation.current_ebook_reference_information,
                    content_type = KOR.referenceinformation.current_ebook_reference_information:match("<") and "html" or "text",
                },
            },
            top_buttons_left = buttons,
            fullscreen = true,
        })
        return true
    end

    KOR.dialogs:htmlBox({
        title = _("Glossary"),
        html = self:getHtmlList(glossary),
        is_reference_information_or_glossary = true,
        top_buttons_left = buttons,
        fullscreen = true,
    })
    return true
end

function Glossary:getHtmlList(glossary)
    local lines = KOR.strings:split(glossary, "\n")
    count = #lines
    local has_two_line_entries = not lines[1]:match(" ")
    if has_two_line_entries then
        for i = 1, count, 2 do
            lines[i] = "<li class='glossary'><strong>" .. lines[i] .. "</strong><br />"
            lines[i + 1] = lines[i + 1] .. "</li>"
        end
        return "<body><html><ul>" .. table_concat(lines, "\n") .. "</ul></body></html>"
    end

    local separator = lines[1]:match(":") or lines[1]:match(" %-") or lines[1]:match("—") or lines[1]:match("–")
    if not separator then
        separator = " "
    end
    for i = 1, count do
        lines[i] = lines[i]:gsub("^([^%" .. separator .. "]+)", "<li class='glossary'><strong>%1</strong>", 1) .. "</li>"
    end
    return "<body><html><ul>" .. table_concat(lines, "\n") .. "</ul></body></html>"
end

function Glossary:getGlossaryEntryAsDictionaryEntry(tapped_word)

    --* don't allow larger strings which contain a saved name to trigger matches:
    if tapped_word:match(" ") then
        return false
    end

    local glossary = self:get()
    if not glossary then
        return false
    end

    local needle_singular
    local match_needle_singular = tapped_word:gsub("s$", "")
    if match_needle_singular == tapped_word then
        match_needle_singular = nil
    else
        needle_singular = match_needle_singular
        match_needle_singular = "(^|\n)" .. match_needle_singular .. "%f[%A]"
    end

    local match_needle = "(^|\n)" .. tapped_word .. "%f[%A]"
    --* make search for needles more specific: only register hits when term is at the start or the start of a line of the glossary, and the end of the needle is at a word_boundary:
    if KOR.strings:group_match(glossary, match_needle) then
        self:showEditor(glossary, tapped_word)
        return true
    elseif match_needle_singular and KOR.strings:group_match(glossary, match_needle_singular) then
        self:showEditor(glossary, needle_singular)
        return true
    end
    return false
end

--* add extra whitespace to the end of the glossary, so searches after tapping on a person in the book which is mentioned in the glossary will always be shown at the top of the editor:
--- @private
function Glossary:addWhiteSpaceAtEnd(info)
    if not info then
        return info
    end
    if not info:match("\n\n\n\n$") then
        return info .. self.line_end:rep(20)
    end
    return info
end

--- @private
function Glossary:removeWhiteSpaceAtEnd(info)
    if not info then
        return info
    end
    if info:match("\n\n\n\n$") then
        local lines = self.line_end:rep(20)
        info = info:gsub(lines, "")
    end
    return info
end

--- @private
function Glossary:save(info)
    KOR.ui.doc_settings:saveSetting("glossary", info)
    KOR.ui.doc_settings:flush()
    KOR.ui.doc_settings.glossary = info
end

return Glossary
