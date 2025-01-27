
local Dialogs = require("extensions/dialogs")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local XrayHelpers = require("extensions/xrayhelpers")

--- @class ReaderHighlight
local ReaderHighlight = InputContainer:extend{
    -- [...]
}

-- [...]

function ReaderHighlight:init()
    -- [...]
    self._highlight_buttons = {
        -- highlight and add_note are for the document itself,
        -- so we put them first.
        ["01_select"] = function(this)
            return {
                text = _("Select"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:startSelection()
                    this:onClose()
                end,
            }
        end,
        -- [...]
        ["12_search"] = function(this)
            return {
                text = _("Search"),
                callback = function()
                    this:onHighlightSearch()
                    -- We don't call this:onClose(), crengine will highlight
                    -- search matches on the current page, and self:clear()
                    -- would redraw and remove crengine native highlights
                end,
            }
        end,
        -- #((add xray item button for selected text popup in ReaderHighlight))
        ["13_add_xray_item"] = function(this)
            return {
                text = "+ Add xray item",
                callback = function()
                    -- SmartScripts: maybe the next statements are now old code for KOReader?:
                    self:highlightFromHoldPos()
                    if self.selected_text then
                        KOR.xrayitems:onSaveNewXrayItem(self.selected_text)
                        self:onClearHighlight()
                        this:onClose()
                    else
                        Dialogs:alertError("Xray-item kon niet worden bepaald vanuit de tekst", 3)
                    end
                end,
            }
        end,
    }

    --[...]
end

-- [...]

function ReaderHighlight:onReaderReady()
    KOR:registerUImodules(self.ui)
    self:setupTouchZones()
end

-- [...]

function ReaderHighlight:onTapXPointerSavedHighlight(ges)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    local cur_view_top, cur_view_bottom
    local pos = self.view:screenToPageTransform(ges.pos)

    if XrayHelpers:ReaderHighlightGenerateXrayInformation(pos) then
        return true
    end

    -- [...]
end

-- [...]

function ReaderHighlight:lookup(selected_text, selected_link)
    -- convert sboxes to word boxes
    local word_boxes = {}
    for i, sbox in ipairs(selected_text.sboxes) do
        word_boxes[i] = self.view:pageToScreenTransform(self.hold_pos.page, sbox)
    end

    -- if we extracted text directly
    if #selected_text.text > 0 and self.hold_pos then

        if XrayHelpers:getXrayItemAsDictionaryEntry(selected_text.text, self.ui) then
            self:clear()
            return
        end

        self.ui:handleEvent(Event:new("LookupWord", selected_text.text, false, word_boxes, self, selected_link))
    -- or we will do OCR
    elseif selected_text.sboxes and self.hold_pos then
        -- [...]
    end
end

-- [...]

function ReaderHighlight:onShowHighlightMenu(page, index)
    if not self.selected_text then
        return
    elseif XrayHelpers:getXrayItemAsDictionaryEntry(self.selected_text.text, self.ui) then
        self:onClearHighlight()
        return
    end

    -- [...]
end

-- [...]

return ReaderHighlight
