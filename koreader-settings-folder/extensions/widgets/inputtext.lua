
local require = require

local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FocusManager = require("extensions/widgets/focusmanager")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Font = require("extensions/modules/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local _ = require("gettext")

local DX = DX
local pairs = pairs
local select = select
local string = string
local table = table
local tostring = tostring
local type = type

local Keyboard -- Conditional instantiation
local FocusManagerInstance -- Delayed instantiation

--- @class InputText
local InputText = InputContainer:extend{
    text = "",
    hint = "demo hint",
    input_type = nil, --* "number" or anything else
    text_type = nil, --* "password" or anything else
    show_password_toggle = true,
    cursor_at_end = true, --* starts with cursor at end of text, ready for appending
    scroll = false, --* whether to allow scrolling (will be set to true if no height provided)
    disable_paste = false,
    focused = false,
    parent = nil, --* parent dialog that will be set dirty
    edit_callback = nil, --* called with true when text modified, false on init or text re-set
    scroll_callback = nil, --* called with (low, high) when view is scrolled (cf ScrollTextWidget)
    scroll_by_pan = false, --* allow scrolling by lines with Pan (needs scroll=true)

    width = nil,
    height = nil, --* when nil, will be set to original text height (possibly
                  --* less if screen would be overflowed) and made scrollable to
                  --* not overflow if some text is appended and add new lines
    force_one_line = nil,

    face = KOR.registry.default_dialog_font or Font:getDefaultDialogFontFace(),
    padding = Size.padding.default,
    margin = Size.margin.default,
    bordersize = Size.border.inputtext,

    --* See TextBoxWidget for details about these options
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = false,
    alignment_strict = false,

    --* for internal use
    text_widget = nil, --* Text Widget for cursor movement, possibly a ScrollTextWidget
    charlist = nil, --* table of individual chars from input string
    charpos = nil, --* position of the cursor, where a new char would be inserted
    top_line_num = nil, --* virtual_line_num of the text_widget (index of the displayed top line)
    is_password_type = false, --* set to true if original text_type == "password"
    is_text_editable = true, --* whether text is utf8 reversible and editing won't mess content
    is_text_edited = false, --* whether text has been updated
    for_measurement_only = nil, --* When the widget is a one-off used to compute text height
    do_select = false, --* to start text selection
    selection_start_pos = nil, --* selection start position
    is_keyboard_hidden = false, --* to be able to show the keyboard again when it was hidden

    default_color = nil,
    disabled_color = nil,

shift_key_translations = {
    ["1"] = "!",
    ["2"] = "@",
    ["3"] = "/",
    --["3"] = "#",
    --[[["4"] = "$",
    ["5"] = "%",
    ["6"] = "^",
    ["7"] = "&",
    ["8"] = "*",]]
    ["4"] = ": ",
    ["5"] = "; ",
    ["6"] = "-",
    ["7"] = "\"",
    ["8"] = "'",
    ["9"] = "(",
    ["0"] = ")",

    ["."] = ">",
    ["/"] = "?",
}
}

--* These may be (internally) overloaded as needed, depending on Device capabilities.
function InputText:initEventListener() end
function InputText:onFocus() end
function InputText:onUnfocus() end

local function initTouchEvents()
    --* only use PhysicalKeyboard if the device does not have touch screen
    if Device:isTouchDevice() or Device:hasDPad() then
        Keyboard = require("ui/widget/virtualkeyboard")
        if Device:isTouchDevice() then
            function InputText:initEventListener()
                self.ges_events = {
                    TapTextBox = {
                        GestureRange:new{
                            ges = "tap",
                            range = function() return self.dimen end
                        }
                    },
                    HoldTextBox = {
                        GestureRange:new{
                            ges = "hold",
                            range = function() return self.dimen end
                        }
                    },
                    HoldReleaseTextBox = {
                        GestureRange:new{
                            ges = "hold_release",
                            range = function() return self.dimen end
                        }
                    },
                    SwipeTextBox = {
                        GestureRange:new{
                            ges = "swipe",
                            range = function() return self.dimen end
                        }
                    },
                    --* These are just to stop propagation of the event to
                    --* parents in case there's a MovableContainer among them
                    --* Commented for now, as this needs work
                    -- HoldPanTextBox = {
                    --     GestureRange:new{ ges = "hold_pan", range = self.dimen }
                    -- },
                    -- PanTextBox = {
                    --     GestureRange:new{ ges = "pan", range = self.dimen }
                    -- },
                    -- PanReleaseTextBox = {
                    --     GestureRange:new{ ges = "pan_release", range = self.dimen }
                    -- },
                    -- TouchTextBox = {
                    --     GestureRange:new{ ges = "touch", range = self.dimen }
                    -- },
                }
            end

            --* For MovableContainer to work fully, some of these should
            --* do more check before disabling the event or not
            --* Commented for now, as this needs work
            -- local function _disableEvent() return true end
            -- InputText.onHoldPanTextBox = _disableEvent
            -- InputText.onHoldReleaseTextBox = _disableEvent
            -- InputText.onPanTextBox = _disableEvent
            -- InputText.onPanReleaseTextBox = _disableEvent
            -- InputText.onTouchTextBox = _disableEvent

            function InputText:onTapTextBox(arg, ges)
                if self.parent.onSwitchFocus then
                    self.parent:onSwitchFocus(self)
                else
                    if self.is_keyboard_hidden == true then
                        self:onShowKeyboard()
                        self.garbage = arg
                        self.is_keyboard_hidden = false
                    end
                end
                --* zh keyboard with candidates shown here has _frame_textwidget.dimen = nil.
                --* Check to avoid crash.
                if #self.charlist > 0 and self._frame_textwidget.dimen then --* Avoid cursor moving within a hint.
                    local textwidget_offset = self.margin + self.bordersize + self.padding
                    local x = ges.pos.x - self._frame_textwidget.dimen.x - textwidget_offset
                    local y = ges.pos.y - self._frame_textwidget.dimen.y - textwidget_offset
                    self.text_widget:moveCursorToXY(x, y, true) --* restrict_to_view=true
                    self.charpos, self.top_line_num = self.text_widget:getCharPos()
                end
                return true
            end

            function InputText:onHoldTextBox()
                if self.parent.onSwitchFocus then
                    self.parent:onSwitchFocus(self)
                end

                if self.disable_paste then
                    self._hold_handled = true
                    return
                end

                --* clipboard dialog
                self._hold_handled = nil
                if Device:hasClipboard() then
                    KOR.clipboard:clipboardDialog(self)
                end
                self._hold_handled = true
                return true
            end

            function InputText:onHoldReleaseTextBox()
                if self._hold_handled then
                    self._hold_handled = nil
                    return true
                end
                return false
            end

            function InputText:onSwipeTextBox(arg, ges)
                --* Allow refreshing the widget (actually, the screen) with the classic
                --* Diagonal Swipe, as we're only using the quick "ui" mode while editing
                if ges.direction == "northeast" or ges.direction == "northwest"
                        or ges.direction == "southeast" or ges.direction == "southwest" then
                    self.garbage = arg
                    if self.refresh_callback then self.refresh_callback() end
                    --* Trigger a full-screen HQ flashing refresh so
                    --* the keyboard can also be fully redrawn
                    UIManager:setDirty(nil, "full")
                end
                --* Let it propagate in any case (a long diagonal swipe may also be
                --* used for taking a screenshot)
                return false
            end
        end
    end
end

local function initDPadEvents()
    if Device:hasDPad() then
        function InputText:onFocus()
            --* Event called by the focusmanager
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            else
                self:onShowKeyboard()
            end
            self:focus()
            return true
        end

        function InputText:onUnfocus()
            --* Event called by the focusmanager
            self:unfocus()
            return true
        end
    end
end

--* only use PhysicalKeyboard if the device does not support touch input
function InputText.initInputEvents()
    FocusManagerInstance = nil

    if Device:isTouchDevice() or Device:hasDPad() then
        -- #((load virtual keyboard))
        Keyboard = require("ui/widget/virtualkeyboard")
        initTouchEvents()
        initDPadEvents()
    else
        -- #((load hardware keyboard))
        Keyboard = require("ui/widget/physicalkeyboard")
    end
end

InputText.initInputEvents()

function InputText:checkTextEditability()
    --* The split of the 'text' string to a table of utf8 chars may not be
    --* reversible to the same string, if 'text'  comes from a binary file
    --* (it looks like it does not necessarily need to be proper UTF8 to
    --* be reversible, some text with latin1 chars is reversible).
    --* As checking that may be costly, we do that only in init(), setText(),
    --* and clear().
    --* When not reversible, we prevent adding and deleting chars to not
    --* corrupt the original self.text.
    self.is_text_editable = true
    if self.text then
        --* We check that the text obtained from the UTF8 split done
        --* in :initTextBox(), when concatenated back to a string, matches
        --* the original text. (If this turns out too expensive, we could
        --* just compare their lengths)
        self.is_text_editable = table.concat(self.charlist, "") == self.text
    end
end

function InputText:isTextEditable(show_warning)
    if show_warning and not self.is_text_editable then
        KOR.messages:notify(_("Text may be binary content, and is not editable"))
    end
    return self.is_text_editable
end

function InputText:isTextEdited()
    return self.is_text_edited
end

function InputText:init()
    self.default_color, self.disabled_color = KOR.buttonprops:getButtonColors()

    if Device:isTouchDevice() then
        if self.text_type == "password" then
            --* text_type changes from "password" to "text" when we toggle password
            self.is_password_type = true
        end
    else
        --* focus move does not work with textbox and show password checkbox
        --* force show password for non-touch device
        self.text_type = "text"
        self.is_password_type = false
    end
    --* Beware other cases where implicit conversion to text may be done
    --* at some point, but checkTextEditability() would say "not editable".
    if self.input_type == "number" then
        if type(self.text) == "number" then
            --* checkTextEditability() fails if self.text stays not a string
            self.text = tostring(self.text)
        end
        if type(self.hint) == "number" then
            self.hint = tostring(self.hint)
        end
    end
    self:initTextBox(self.text)
    self:checkTextEditability()
    if self.readonly ~= true then
        self:initKeyboard()
        self:initEventListener()
    end
end

--* This will be called when we add or del chars, as we need to recreate
--* the text widget to have the new text splittted into possibly different
--* lines than before
function InputText:initTextBox(text, char_added)
    if self.text_widget then
        self.text_widget:free(true)
    end

    local charpos_correction = 0

    self.text = text
    local fgcolor
    local show_charlist
    local show_text = text
    if show_text == "" or show_text == nil then
        --* no preset value, use hint text if set
        show_text = self.hint
        fgcolor = self.disabled_color
        self.charlist = {}
        self.charpos = 1
    else
        fgcolor = self.default_color
        if self.text_type == "password" then
            show_text = self.text:gsub(
                "(.-).", function() return "*" end)
            if char_added then
                show_text = show_text:gsub(
                    "(.)$", function() return self.text:sub(-1) end)
            end
        end
        self.charlist = util.splitToChars(text)
        --* keep previous cursor position if charpos not nil
        if self.charpos == nil then
            if self.cursor_at_end then
                self.charpos = #self.charlist + 1
            else
                self.charpos = 1
            end
        end
        if charpos_correction then
            self.charpos = self.charpos + charpos_correction
        end
    end
    if self.is_password_type and self.show_password_toggle then
        self._check_button = self._check_button or CheckButton:new{
            text = _("Show password"),
            parent = self,
            width = self.width,
            callback = function()
                self.text_type = self._check_button.checked and "text" or "password"
                self:setText(self:getText(), true)
            end,
        }
        self._password_toggle = FrameContainer:new{
            bordersize = 0,
            padding = self.padding,
            padding_top = 0,
            padding_bottom = 0,
            margin = self.margin,
            self._check_button,
        }
    else
        self._password_toggle = nil
    end
    show_charlist = util.splitToChars(show_text)

    if not self.height then
        --* If no height provided, measure the text widget height
        --* we would start with, and use a ScrollTextWidget with that
        --* height, so widget does not overflow container if we extend
        --* the text and increase the number of lines.
        local text_width = self.width
        if text_width then
            --* Account for the scrollbar that will be used
            local scroll_bar_width = ScrollTextWidget.scroll_bar_width + ScrollTextWidget.text_scroll_span
            text_width = text_width - scroll_bar_width
        end
        local text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = show_charlist,
            face = self.face,
            width = text_width,
            lang = self.lang, --* these might influence height
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            for_measurement_only = true, --* flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        self.height = text_widget:getTextHeight()
        self.scroll = true
        text_widget:free(true)
    end
    if self.force_one_line then
        self.scroll = true
    end
    if self.scroll then
        self.text_widget = ScrollTextWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            top_line_num = self.top_line_num,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
            width = self.width,
            height = self.height,
            dialog = self.parent,
            scroll_callback = self.scroll_callback,
            scroll_by_pan = self.scroll_by_pan,
            for_measurement_only = self.for_measurement_only,
        }
    else
        self.text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            top_line_num = self.top_line_num,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
            width = self.width,
            height = self.height,
            dialog = self.parent,
            for_measurement_only = self.for_measurement_only,
        }
    end
    --* Get back possibly modified charpos and virtual_line_num
    self.charpos, self.top_line_num = self.text_widget:getCharPos()

    self._frame_textwidget = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = self.margin,
        color = self.focused and self.default_color or self.disabled_color,
        self.text_widget,
    }
    self._verticalgroup = VerticalGroup:new{
        align = "left",
        self._frame_textwidget,
        self._password_toggle,
    }
    self._frame = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        self._verticalgroup,
    }
    self[1] = self._frame
    self.dimen = self._frame:getSize()
    --- @fixme self.parent is not always in the widget stack (BookStatusWidget)
    --* Don't even try to refresh dummy widgets used for text height computations...
    if not self.for_measurement_only then
        UIManager:setDirty(self.parent, function()
            return "ui", self.dimen
        end)
    end
    if self.edit_callback then
        self.edit_callback(self.is_text_edited)
    end
end

function InputText:initKeyboard()
    local keyboard_layer = 2
    if self.input_type == "number" then
        keyboard_layer = 4
    end
    self.key_events = nil
    self.keyboard = Keyboard:new{
        keyboard_layer = keyboard_layer,
        inputbox = self,
    }
end

function InputText:unfocus()
    self.focused = false
    self.text_widget:unfocus()
    self._frame_textwidget.color = self.disabled_color
end

function InputText:focus()
    self.focused = true
    self.text_widget:focus()
    self._frame_textwidget.color = self.default_color
end

--* Handle real keypresses from a physical keyboard, even if the virtual keyboard
--* is shown. Mostly likely to be in the emulator, but could be Android + BT
--* keyboard, or a "coder's keyboard" Android input method.
function InputText:onKeyPress(key)
    --* only handle key on focused status, otherwise there are more than one InputText
    --* the first one always handle key pressed
    if not self.focused then
        return false
    end

    --* use Shift+Del for simulating Del (because Del converted to BackSpace below):
    if DX.s.is_tablet_device and key["Shift"] and key["Del"] then
        self:delNextChar()
        return true
    end

    local handled = true
    -- #((default hardware keys))
    --* Alt and Control were already skipped above:
    if not key["Shift"] then
        --* because my bt keyboard has not BackSpace, I've forced Del to behave as if it were a backspace:
        if key["Backspace"] then
            if DX.s.is_tablet_device then
                self:delNextChar()
            else
                self:delChar()
            end

        elseif key["Del"] then
            if DX.s.is_tablet_device then
                self:delChar()
            else
                self:delNextChar()
            end

        elseif key["Left"] then
            self:leftChar()
        elseif key["Right"] then
            self:rightChar()
        elseif key["Up"] then
            self:upLine()
        elseif key["Down"] then
            self:downLine()
        elseif key["End"] then
            self:goToEnd()
        elseif key["Home"] then
            self:goToHome()
        elseif key["Press"] then
            self:addChars("\n")
        elseif key["Tab"] then
            self:addChars("    ")
        elseif key["Back"] then
            if self.focused then
                self:unfocus()
            end
        else
            handled = false
        end
    elseif key["Ctrl"] and not key["Shift"] and not key["Alt"] then
        if key["U"] then
            self:delToStartOfLine()
        elseif key["H"] then
            self:delChar()
        else
            handled = false
        end
    else
        handled = false
    end
    if not handled then --!  and Device:hasDPad()

        --* FocusManager may turn on alternative key maps.
        --* These key map maybe single text keys.
        --* It will cause unexpected focus move instead of enter text to InputText
        if not FocusManagerInstance then
            FocusManagerInstance = FocusManager:new{}
        end
        local is_alternative_key = FocusManagerInstance:isAlternativeKey(key)
        if not is_alternative_key and Device:isSDL() then
            --* SDL already insert char via TextInput event
            --* Stop event propagate to FocusManager
            return true
        end
        --* if it is single text char, insert it
        local key_code = key.key --* is in upper case
        if not Device.isSDL() and #key_code == 1 then
            local has_shifted = false
            if not key["Shift"] then
                key_code = string.lower(key_code)
            else
                for ikey, translation in pairs(self.shift_key_translations) do
                    if key_code == ikey then
                        key_code = translation
                        has_shifted = true
                        break
                    end
                end
            end
            for modifier, flag in pairs(key.modifiers) do
                if modifier ~= "Shift" and flag then --* Other modifier: not a single char insert
                    return true
                end
            end
            --* to get access to typing comma with /:
            -- #((insert comma))
            if not has_shifted and key_code == "/" then
                key_code = ", "
            end
            if key_code == "o" then
                self:addChars(key_code)
                --* ignore key "o" for opening CrashLog (otherwise "o" added at start of log content), don't store it in a Registry var, but don't block calling of the event:
                return false
            end

            -- #((dont block event handling for key presses))
            if not key["Shift"] and not has_shifted then
                -- #((get pressed hardware key))
                KOR.registry:set("pressed_key", key_code)
            else
                self:addChars(key_code)
                --* no event handling needed anymore, so speed up:
                return true
            end
        end
        if is_alternative_key then
            return true --* Stop event propagate to FocusManager to void focus move
        end
    end
    return handled
end

--* Handle text coming directly as text from the Device layer (eg. soft keyboard
--* or via SDL's keyboard mapping).
function InputText:onTextInput(text)
    --* for more than one InputText, let the focused one add chars
    if self.focused then
        self:addChars(text)
        return true
    end
    return false
end

function InputText:onShowKeyboard(ignore_first_hold_release)
    Device:startTextInput()
    self.keyboard.ignore_first_hold_release = ignore_first_hold_release
    UIManager:show(self.keyboard)
    return true
end

function InputText:onCloseKeyboard()
    UIManager:close(self.keyboard)
    Device:stopTextInput()
    self.is_keyboard_hidden = true
end

function InputText:onCloseWidget()
    if self.keyboard then
        self.keyboard:free()
    end
    self:free()
end

function InputText:getTextHeight()
    return self.text_widget:getTextHeight()
end

function InputText:getLineHeight()
    return self.text_widget:getLineHeight()
end

function InputText:getKeyboardDimen()
    if self.readonly then
        return Geom:new{w = 0, h = 0}
    end
    return self.keyboard.dimen
end

--* calculate current and last (original) line numbers
function InputText:getLineNums()
    local cur_line_num, last_line_num = 1, 1
    for i = 1, #self.charlist do
        if self.text_widget.charlist[i] == "\n" then
            if i < self.charpos then
                cur_line_num = cur_line_num + 1
            end
            last_line_num = last_line_num + 1
        end
    end
    return cur_line_num, last_line_num
end

--* calculate charpos for the beginning of (original) line
function InputText:getLineCharPos(line_num)
    local char_pos = 1
    if line_num > 1 then
        local j = 1
        for i = 1, #self.charlist do
            if self.charlist[i] == "\n" then
                j = j + 1
                if j == line_num then
                    char_pos = i + 1
                    break
                end
            end
        end
    end
    return char_pos
end

--* Get start and end positions of the substring
--* delimited with the delimiters and containing char_pos.
--* If char_pos not set, current charpos assumed.
function InputText:getStringPos(left_delimiter, right_delimiter, char_pos)
    char_pos = char_pos and char_pos or self.charpos
    local start_pos, end_pos = 1, #self.charlist
    local done = false
    if char_pos > 1 then
        for i = char_pos, 2, -1 do
            for j = 1, #left_delimiter do
                if self.charlist[i-1] == left_delimiter[j] then
                    start_pos = i
                    done = true
                    break
                end
            end
            if done then break end
        end
    end
    done = false
    if char_pos < #self.charlist then
        for i = char_pos, #self.charlist do
            for j = 1, #right_delimiter do
                if self.charlist[i] == right_delimiter[j] then
                    end_pos = i - 1
                    done = true
                    break
                end
            end
            if done then break end
        end
    end
    return start_pos, end_pos
end

--- Return the character at the given offset. If is_absolute is truthy then the
--* offset is the absolute position, otherwise the offset is added to the current
--* cursor position (negative offsets are allowed).
function InputText:getChar(offset, is_absolute)
    local idx
    if is_absolute then
        idx = offset
    else
        idx = self.charpos + offset
    end
    if idx < 1 or idx > #self.charlist then return end
    return self.charlist[idx]
end

function InputText:addChars(chars)
    if not chars then
        --* VirtualKeyboard:addChar(key) gave us 'nil' once (?!)
        --* which would crash table.concat()
        return
    end
    if self.enter_callback and chars == "\n" then
        UIManager:scheduleIn(0.3, function() self.enter_callback() end)
        return
    end
    if self.readonly or not self:isTextEditable(true) then
        return
    end

    self.is_text_edited = true
    if #self.charlist == 0 then --* widget text is empty or a hint text is displayed
        self.charpos = 1 --* move cursor to the first position
    end

    --* remove spaces before punctuation:
    if self.charlist[self.charpos - 1] and self.charlist[self.charpos - 1] == " " and chars:match("^[,.?!:;] ?$") then
        self.charlist[self.charpos - 1] = chars
        self.charpos = self.charpos + #util.splitToChars(chars) - 1
    else
        table.insert(self.charlist, self.charpos, chars)
        self.charpos = self.charpos + #util.splitToChars(chars)
    end

    self:initTextBox(table.concat(self.charlist), true, chars)
end

function InputText:delChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    self.is_text_edited = true
    table.remove(self.charlist, self.charpos)
    self:initTextBox(table.concat(self.charlist))
end

function InputText:delNextChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos > #self.charlist then return end
    self.is_text_edited = true
    table.remove(self.charlist, self.charpos)
    self:initTextBox(table.concat(self.charlist))
end

function InputText:delToStartOfLine()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end
    --* self.charlist[self.charpos] is the char after the cursor
    if self.charlist[self.charpos-1] == "\n" then
        --* If at start of line, just remove the \n and join the previous line
        self.charpos = self.charpos - 1
        table.remove(self.charlist, self.charpos)
    else
        --* If not, remove chars until first found \n (but keeping it)
        while self.charpos > 1 and self.charlist[self.charpos-1] ~= "\n" do
            self.charpos = self.charpos - 1
            table.remove(self.charlist, self.charpos)
        end
    end
    self.is_text_edited = true
    self:initTextBox(table.concat(self.charlist))
end

--* For the following cursor/scroll methods, the text_widget deals
--* itself with setDirty'ing the appropriate regions
function InputText:leftChar()
    if self.charpos == 1 then return end
    self.text_widget:moveCursorLeft()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:rightChar()
    if self.charpos > #self.charlist then return end
    self.text_widget:moveCursorRight()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToStartOfLine()
    local new_pos = select(1, self:getStringPos({"\n", "\r"}, {"\n", "\r"}))
    self.text_widget:moveCursorToCharPos(new_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToEndOfLine()
    local new_pos = select(2, self:getStringPos({"\n", "\r"}, {"\n", "\r"})) + 1
    self.text_widget:moveCursorToCharPos(new_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToHome()
    self.text_widget:moveCursorHome()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToEnd()
    self.text_widget:moveCursorEnd()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:moveCursorToCharPos(char_pos)
    self.text_widget:moveCursorToCharPos(char_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:upLine()
    self.text_widget:moveCursorUp()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:downLine()
    if #self.charlist == 0 then return end --* Avoid cursor moving within a hint.
    self.text_widget:moveCursorDown()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollDown()
    self.text_widget:scrollDown()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollUp()
    self.text_widget:scrollUp()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollToTop()
    self.text_widget:scrollToTop()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollToBottom()
    self.text_widget:scrollToBottom()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:clear()
    self.charpos = nil
    self.top_line_num = 1
    self.is_text_edited = true
    self:initTextBox("")
    self:checkTextEditability()
end

function InputText:getText()
    return self.text
end

function InputText:setText(text, keep_edited_state)
    --* Keep previous charpos and top_line_num
    self:initTextBox(text)
    if not keep_edited_state then
        --* assume new text is set by caller, and we start fresh
        self.is_text_edited = false
        self:checkTextEditability()
    end
end


--* ==================== SMARTSCRIPTS =====================

function InputText:getCharPos()
    return self.charpos
end

--* so we can minimize the on screen keyboard in this case:
InputText.onPhysicalKeyboardConnected = function()
    KOR.registry:set("physical_keyboard_connected", true)
end

InputText.onPhysicalKeyboardDisconnected = function()
    KOR.registry:unset("physical_keyboard_connected")
end

return InputText
