
--* saved reference info can be shown instead of DictQuickLookup widget if a term was found in the reference info; see ((ReaderDictionary#onLookupWord)) > ((show reference info instead of dictionary popup))

local require = require

local Device = require("device")
local Font = require("modules/font")
local InputDialog = require("xrayviews/widgets/inputdialog")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local has_content = has_content
local has_text = has_text
local table_insert = table.insert
local type = type

--* class for maintaining reference info pertaining to current ebook (e.g. list of characters, word explanations, etc.)
--- @class ReferenceInfo
local ReferenceInfo = WidgetContainer:extend{
    line_end = "\n",
    reference_info_last_edit_pos = nil,
}

function ReferenceInfo:get(remove_whitespace_at_end)
    --* this info could have been saved from the Referentie-button in ReaderHighlight:
    local doc_settings = KOR.ui.doc_settings
    local info = doc_settings:readSetting("reference_info") or false
    if not has_text(info) then
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

function ReferenceInfo:addInfo(info)
    local previous_info = self:get("remove_whitespace_at_end")
    if not previous_info or not previous_info:match("[a-z]") then
        previous_info = ""
    else
        previous_info = previous_info .. "\n\n========================\n\n"
    end
    self:save(previous_info .. info)
end

function ReferenceInfo:edit(referenced_info, scroll_to_text)
    --* in the case called from the description dialog:
    if referenced_info then
        UIManager:close(self.viewer)
    else
        referenced_info = self:get()
    end
    local has_info = has_content(referenced_info)
    if not referenced_info then
        referenced_info = ""
    end
    --- @type InputDialog editor
    local editor
    local action = has_info and _("View/edit") or _("Add:")
    local title = action .. " " .. _("reference-info")
    local buttons = {
        {
            KOR.buttoninfopopup:forReferenceInfoErase({
                callback = function()
                    KOR.dialogs:confirm(_("Are you sure you want to remove ALL reference information?"), function()
                        UIManager:close(editor)
                        self:save(nil)
                    end)
                end,
            }),
            KOR.buttoninfopopup:forReferenceInfoCopy({
                callback = function()
                    local info = has_content(editor:getInputText()) or nil
                    if info then
                        info = KOR.strings:trim(info)
                        Device.input.setClipboardText(info)
                        KOR.messages:notify(_("reference-information copied"))
                    end
                end,
            }),
            KOR.buttoninfopopup:forReferenceInfoSave({
                callback = function()
                    local info = has_content(editor:getInputText()) or nil
                    UIManager:close(editor)
                    info = self:addWhiteSpaceAtEnd(info)
                    self:save(info)
                    KOR.messages:notify(_("reference-information saved"))
                end,
            }),
            {
                icon = "back",
                icon_size_ratio = 0.7,
                callback = function()
                    UIManager:close(editor)
                end
            },
        },
    }
    if has_text(scroll_to_text) then
        title = title .. " - " .. scroll_to_text

        table_insert(buttons[1], 2, KOR.buttoninfopopup:forReferenceInfoSwitchToDictionary({
            callback = function()
                UIManager:close(editor)
                KOR.registry:set("skip_reference_info", true)
                KOR.ui.dictionary:onLookupWord(scroll_to_text)
            end,
        }))
    end
    editor = InputDialog:new{
        title = title,
        input = referenced_info,
        input_hint = "",
        input_face = Font:getFace("smallinfofont", 14),
        para_direction_rtl = false,
        lang = "en",
        fullscreen = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = buttons,
        search_value = scroll_to_text,
        --* Set/save view and cursor position callback
        view_pos_callback = function(top_line_num, charpos)
            --* This same callback is called with no argument to get initial position, and with arguments to give back final position when closed.
            if top_line_num and charpos then
                self.reference_info_last_edit_pos = { top_line_num, charpos }
            else
                local prev_pos = self.reference_info_last_edit_pos
                if type(prev_pos) == "table" and prev_pos[1] and prev_pos[2] then
                    return prev_pos[1], prev_pos[2]
                end
                return nil, nil --* no previous position known
            end
        end,
        copy_button_text = _("Copy"),
        copy_callback = function()
            Device.input.setClipboardText(editor:getInputText())
        end,
    }
    UIManager:show(editor)
    editor:onShowKeyboard(true)
    if has_info then
        editor:toggleKeyboard("force_hidden")
    end
    if scroll_to_text then
        KOR.registry:set("scroll_to_text", scroll_to_text)
        --* to display found entry at the top of the dialog, if possible, or otherwise somewhere in the center:
        editor:scrollToBottom()
        editor:findCallback("force_hidden", nil, true)
    end
end

function ReferenceInfo:getReferenceInfoAsDictionaryEntry(tapped_word)

    local reference_info = self:get()
    if not reference_info then
        return false
    end

    local is_lower_case = not tapped_word:match("[A-Z]") or tapped_word:match("^[-a-z0-9 ,.:;!?]+$")
    local singular = tapped_word:gsub("s$", "")
    if singular == tapped_word then
        singular = nil
    end

    local spaces_count = KOR.strings:substrCount(tapped_word, " ")
    --* don't allow larger strings which contain a saved name to trigger matches:
    if spaces_count <= 1 then
        local needle, needle_singular
        if is_lower_case then
            reference_info = reference_info:lower()
            needle = tapped_word .. ":"
            if singular then
                needle_singular = singular .. ":"
            end
        else
            needle = tapped_word
            needle_singular = singular
        end
        if reference_info:match(needle) then
            self:edit(reference_info, needle)
            return true
        elseif needle_singular and reference_info:match(needle_singular) then
            self:edit(reference_info, needle_singular)
            return true
        end
    end
    return false
end

--* add extra whitespace to the end of the reference_info, so searches after tapping on a person in the book which is mentioned in the reference info will always be shown at the top of the editor:
function ReferenceInfo:addWhiteSpaceAtEnd(info)
    if not info then
        return info
    end
    if not info:match("\n\n\n\n$") then
        return info .. self.line_end:rep(20)
    end
    return info
end

function ReferenceInfo:removeWhiteSpaceAtEnd(info)
    if not info then
        return info
    end
    if info:match("\n\n\n\n$") then
        local lines = self.line_end:rep(20)
        info = info:gsub(lines, "")
    end
    return info
end

function ReferenceInfo:save(info)
    KOR.ui.doc_settings:saveSetting("reference_info", info)
    KOR.ui.doc_settings:flush()
    KOR.ui.doc_settings.reference_info = info
end

return ReferenceInfo
