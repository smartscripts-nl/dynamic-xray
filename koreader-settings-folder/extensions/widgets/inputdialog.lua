--[[--
Widget for taking user input.

Example:

    local InputDialog = require("ui/widget/inputdialog")
    local @{ui.uimanager|UIManager} = require("ui/uimanager")
    local @{logger} = require("logger")
    local @{gettext|_} = require("gettext")

    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = "default value",
        --* A placeholder text shown in the text box.
        input_hint = _("Hint text"),
        -- input_type = nil, --* default for text
        --* A description shown above the input.
        description = _("Some more description."),
        -- text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(sample_input)
                    end,
                },
                {
                    text = _("Save"),
                    --* button with is_enter_default set to true will be
                    --* triggered after user press the enter key from keyboard
                    is_enter_default = true,
                    callback = function()
                        logger.dbg("Got user input as raw text:", sample_input:getInputText())
                        logger.dbg("Got user input as value:", sample_input:getInputValue())
                    end,
                },
            }
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()

To get a full screen text editor, use:
    fullscreen = true, --* No need to provide any height and width.
    condensed = true,
    allow_newline = true,
    cursor_at_end = false,
    --* and one of these:
    add_scroll_buttons = true,
    add_nav_bar = true,

To add |Save|Close| buttons, use:
    save_callback = function(content, closing)
        --* ...Deal with the edited content...
        if closing then
            UIManager:nextTick(
                --* Stuff to do when InputDialog is closed, if anything.
            )
        end
        return nil --* sucess, default notification shown
        return true, success_notif_text
        return false, error_infomsg_text
    end

To additionally add a Reset button and have |Reset|Save|Close|, use:
    reset_callback = function()
        return original_content --* success
        return original_content, success_notif_text
        return nil, error_infomsg_text
    end

If you don't need more buttons than these, use these options for consistency
between dialogs, and don't provide any buttons.
Text used on these buttons and their messages and notifications can be
changed by providing alternative text with these additional options:
    reset_button_text
    save_button_text
    close_button_text
    close_unsaved_confirm_text
    close_cancel_button_text
    close_discard_button_text
    close_save_button_text
    close_discarded_notif_text

If it would take the user more than half a minute to recover from a mistake,
a "Cancel" button <em>must</em> be added to the dialog. The cancellation button
should be kept on the left and the button executing the action on the right.

It is strongly recommended to use a text describing the action to be
executed, as demonstrated in the example above. If the resulting phrase would be
longer than three words it should just read "OK".

]]

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("extensions/widgets/button")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FocusManager = require("extensions/widgets/focusmanager")
local Font = require("extensions/modules/font")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local Input = require("extensions/modules/input")
local InputText = require("extensions/widgets/inputtext")
local KOR = require("extensions/kor")
local MovableContainer = require("ui/widget/container/movablecontainer")
local MultiConfirmBox = require("extensions/widgets/multiconfirmbox")
local Size = require("extensions/modules/size")
local TitleBar = require("extensions/widgets/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local util = require("util")
local _ = require("gettext")

local has_no_text = has_no_text
local has_text = has_text
local math = math
local table = table
local tonumber = tonumber
local type = type

local count

--- @class InputDialog
--- @field _input_widget InputText
local InputDialog = FocusManager:extend {
    is_always_active = true,
    title = nil,
    input = "",
    input_hint = "",
    description = nil,
    buttons = nil,
    input_type = nil,
    deny_keyboard_hiding = false, --* don't hide keyboard on tap outside
    enter_callback = nil,
    strike_callback = nil, --* call this on every keystroke (used by Terminal plugin's TermInputText)
    inputtext_class = InputText, --* (Terminal plugin provides TermInputText)
    readonly = false, --* don't allow editing, will not show keyboard
    allow_newline = false, --* allow entering new lines (this disables any enter_callback)
    cursor_at_end = true, --* starts with cursor at end of text, ready for appending
    use_available_height = false, --* adjust input box to fill available height on screen
    fullscreen = false, --* adjust to full screen minus keyboard
    condensed = false, --* true will prevent adding air and balance between elements
    add_scroll_buttons = false, --* add scroll Up/Down buttons to first row of buttons

    add_nav_bar = false, --* append a row of page navigation buttons
    --* add_nav_bar will be set to true if allow_new_line is true, but this prop, if true, prevents that:
    force_no_navbar = false,

    --* note that the text widget can be scrolled with Swipe North/South even when no button

    keyboard_hidden = false, --* start with keyboard hidden in full fullscreen mode
    --* needs add_nav_bar to have a Show keyboard button to get it back


    scroll_by_pan = false, --* allow scrolling by lines with Pan (= Swipe, but wait a bit at end
    --* of gesture before releasing) (may conflict with movable)

    --* If save_callback provided, a Save and a Close buttons will be added to the first row
    --* if reset_callback provided, a Reset button will be added (before Save) to the first row
    save_callback = nil, --* Called with the input text content when Save (and true as 2nd arg
    --* if closing, false if non-closing Save).
    --* Should return nil or true on success, false on failure.
    --* (This save_callback can do some syntax check before saving)
    reset_callback = nil, --* Called with no arg, should return the original content on success,
    --* nil on failure.
    --* Both these callbacks can return a string as a 2nd return value.
    --* This string is then shown:
    --* - on success: as the notification text instead of the default one
    --* - on failure: in an InfoMessage
    close_callback = nil, --* Called when closing (if discarded or saved, after save_callback if saved)
    edited_callback = nil, --* Called on each text modification

    --* For use by TextEditor plugin:
    view_pos_callback = nil, --* Called with no arg to get initial top_line_num/charpos,
    --* called with (top_line_num, charpos) to give back position on close.

    --* Set to false if movable gestures conflicts with subwidgets gestures
    is_movable = true,

    width = nil,

    text_width = nil,
    text_height = nil,

    bottom_v_padding = 0,
    --input_face = DX.s.is_android and getFace("x_smallinfofont", 18.5) or getFace("x_smallinfofont", 12),
    input_face = Font:getDefaultDialogFontFace(),
    description_face = Font:getDefaultDialogFontFace(),
    input_padding = Size.padding.default,
    input_margin = Size.margin.default,
    button_padding = Size.padding.default,
    border_size = Size.border.window,

    --* see TextBoxWidget for details about these options
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = false,
    alignment_strict = false,

    --* for activating tabs with character hotkeys:
    active_tab = nil,
    tabs_count = nil,
    activate_tab_callback = nil,

    modal = true,
    titlebar_alignment = "center",
    force_save_enabled = false,
    button_font_weight = "bold",
    submenu_buttontable = nil,
    title_shrink_font_to_fit = true,
    title_multilines = false,
    title_tab_buttons_left = nil,
    _input_widget = nil,

    --* for internal use
    _text_modified = false, --* previous known modified status
    _top_line_num = nil,
    _charpos = nil,
    _buttons_edit_callback = nil,
    _buttons_scroll_callback = nil,
    _buttons_backup_done = false,
    _buttons_backup = nil,
}

function InputDialog:init()
    self.layout = { {} }
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if self.fullscreen then
        self.is_movable = false
        self.border_size = 0
        self.width = self.screen_width - 2 * self.border_size
        self.covers_fullscreen = true --* hint for ((UIManager#_repaint))
    else
        self.width = self.width or math.floor(math.min(self.screen_width, self.screen_height) * 0.8)
    end
    if self.condensed then
        self.text_width = self.width - 2 * (self.border_size + self.input_padding + self.input_margin)
    else
        self.text_width = self.text_width or math.floor(self.width * 0.9)
    end
    if self.readonly then
        --* hide keyboard if we can't edit
        self.keyboard_hidden = true
    end

    if not self.force_no_navbar and (self.keyboard_hidden or self.allow_newline) then
        self.add_nav_bar = true
    end

    if self.fullscreen or self.add_nav_bar then
        self.deny_keyboard_hiding = true
    end

    local tab_buttons_left, top_buttons_left, submenu_buttontable, button_props, text
    --* can be set from MultiInputDialog:
    if self.title_tab_buttons_left then
        tab_buttons_left = {}
        count = #self.title_tab_buttons_left
        for i = 1, count do
            text = self.title_tab_buttons_left[i]
            if i == self.active_tab then
                text = " " .. KOR.icons.active_tab_bare .. " " .. text
            end
            button_props = {
                text = text,
                callback = function()
                    self.tab_callback(i)
                end,
            }
            Button:addTitleBarTabButtonProps(button_props, i == self.active_tab)
            table.insert(tab_buttons_left, Button:new(button_props))
        end
    elseif self.submenu_buttontable then
        submenu_buttontable = {}
        count = #self.submenu_buttontable
        for i = 1, count do
            text = self.submenu_buttontable[i]
            if i == self.active_tab then
                text = " " .. KOR.icons.active_tab_bare .. " " .. text
            end
            button_props = {
                text = text,
                callback = function()
                    self.tab_callback(i)
                end,
            }
            Button:addTitleBarTabButtonProps(button_props, i == self.active_tab)
            table.insert(submenu_buttontable, Button:new(button_props))
        end
    else
        top_buttons_left = self.top_buttons_left
    end

    --* title & description
    self.title_bar = self.title and TitleBar:new{
        width = self.width,
        fullscreen = self.fullscreen,
        align = self.titlebar_alignment,
        with_bottom_line = true,
        title = self.title,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        title_multilines = self.title_multilines,
        subtitle = self.subtitle,
        close_callback = self.close_callback,
        bottom_v_padding = self.bottom_v_padding,
        --* this is a description line above an input field:
        info_text = self.description,
        info_text_face = self.description_face or Font:getFace("x_smallinfofont"),
        submenu_buttontable = submenu_buttontable,
        tab_buttons_left = tab_buttons_left,
        top_buttons_left = top_buttons_left,
        show_parent = self,
    } or nil

    --* Vertical spaces added before and after InputText
    --* (these will be adjusted later to center the input text if needed)
    --* (can be disabled by setting condensed=true)
    local padding_width = self.condensed and 0 or Size.padding.default
    local vspan_before_input_text = VerticalSpan:new{ width = padding_width }
    local vspan_after_input_text = VerticalSpan:new{ width = padding_width }

    --* buttons
    --* In case of re-init(), keep backup of original buttons and restore them
    self:_backupRestoreButtons()
    --* If requested, add predefined buttons alongside provided ones
    if self.save_callback then
        --* If save_callback provided, adds (Reset) / Save / Close buttons
        self:_addSaveCloseButtons()
    end
    if self.add_nav_bar then
        --* Home / End / Up / Down buttons
        self:_addScrollButtons(true)
    elseif self.add_scroll_buttons then
        --* Up / Down buttons
        self:_addScrollButtons(false)
    end
    --* buttons table
    self.button_table = ButtonTable:new{
        width = self.width - 2 * self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        button_font_weight = self.button_font_weight,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }
    local buttons_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    }

    --* remember provided text_height if any (to restore it on keyboard height change)
    if self.orig_text_height == nil then
        if self.text_height then
            self.orig_text_height = self.text_height
        else
            self.orig_text_height = false
        end
    end

    --* inputText
    if not self.text_height or self.fullscreen then
        --* We need to find the best height to avoid screen overflow
        --* Create a dummy input widget to get some metrics
        local input_widget = self.inputtext_class:new{
            text = self.fullscreen and "-" or self.input,
            input_type = self.input_type,
            face = self.input_face,
            focused = true,
            width = self.text_width,
            padding = self.input_padding,
            margin = self.input_margin,
            lang = self.lang, --* these might influence height
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            for_measurement_only = true, --* flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        local text_height = input_widget:getTextHeight()
        local line_height = input_widget:getLineHeight()
        local input_pad_height = input_widget:getSize().h - text_height
        local keyboard_height = 0
        if not self.keyboard_hidden then
            keyboard_height = input_widget:getKeyboardDimen().h
        end
        input_widget:onCloseWidget() --* free() textboxwidget and keyboard
        --* find out available height
        local title_bar_height = self.title_bar and self.title_bar:getHeight() or 0
        local available_height = self.screen_height
                - 2 * self.border_size
                - title_bar_height
                - vspan_before_input_text:getSize().h
                - input_pad_height
                - vspan_after_input_text:getSize().h
                - buttons_container:getSize().h
                - keyboard_height

        if self.fullscreen or self.use_available_height or text_height > available_height then
            --* Don't leave unusable space in the text widget, as the user could think
            --* it's an empty line: move that space in pads after and below (for centering)
            self.text_height = math.floor(available_height / line_height) * line_height
            local pad_height = available_height - self.text_height
            local pad_before = math.ceil(pad_height / 2)
            local pad_after = pad_height - pad_before
            vspan_before_input_text.width = vspan_before_input_text.width + pad_before
            vspan_after_input_text.width = vspan_after_input_text.width + pad_after
            if text_height > available_height then
                self.cursor_at_end = false --* stay at start if overflowed
            end
        else
            --* Don't leave unusable space in the text widget
            self.text_height = text_height
        end
    end
    if self.view_pos_callback then
        --* Get initial cursor and top line num from callback
        --* (will work in case of re-init as these are saved by onClose()
        self._top_line_num, self._charpos = self.view_pos_callback()
    end
    self._input_widget = self.inputtext_class:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        focused = true,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
        width = self.text_width,
        height = self.text_height or nil,
        padding = self.input_padding,
        margin = self.input_margin,
        input_type = self.input_type,
        text_type = self.text_type,
        enter_callback = self.enter_callback or function()
            local btn_row, btn
            for r = 1, #self.buttons do
                btn_row = self.buttons[r]
                for b = 1, #btn_row do
                    btn = btn_row[b]
                    if btn.is_enter_default then
                        btn.callback()
                        return
                    end
                end
            end
        end,
        strike_callback = self.strike_callback,
        edit_callback = self._buttons_edit_callback, --* nil if no Save/Close buttons
        scroll_callback = self._buttons_scroll_callback, --* nil if no Nav or Scroll buttons
        scroll = true,
        scroll_by_pan = self.scroll_by_pan,
        cursor_at_end = self.cursor_at_end,
        readonly = self.readonly,
        parent = self,
        is_text_edited = self._text_modified,
        top_line_num = self._top_line_num,
        charpos = self._charpos,
    }
    table.insert(self.layout[1], self._input_widget)
    if self.allow_newline then
        --* remove any enter_callback
        self._input_widget.enter_callback = nil
    end
    self:mergeLayoutInVertical(self.button_table)
    self:refocusWidget()
    --* complementary setup for some of our added buttons
    if self.save_callback then
        local save_button = self.button_table:getButtonById("save")
        if self.readonly then
            save_button:setText(_("Read only"), save_button.width)
        elseif not self._input_widget:isTextEditable() then
            save_button:setText(_("Not editable"), save_button.width)
        end
    end

    --* combine all
    if self.title and self.title_bar then
        self.vgroup = VerticalGroup:new{
            align = "left",
            self.title_bar,
            vspan_before_input_text,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self._input_widget:getSize().h,
                },
                self._input_widget,
            },
            --* added widgets may be inserted here
            vspan_after_input_text,
            buttons_container,
        }
    else
        self.vgroup = VerticalGroup:new{
            align = "left",
            vspan_before_input_text,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self._input_widget:getSize().h,
                },
                self._input_widget,
            },
            --* added widgets may be inserted here
            vspan_after_input_text,
            buttons_container,
        }
    end

    --* Final widget
    self.dialog_frame = FrameContainer:new{
        radius = self.fullscreen and 0 or Size.radius.window,
        padding = 0,
        margin = 0,
        bordersize = self.border_size,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
    }
    local frame = self.dialog_frame
    if self.is_movable then
        self.movable = MovableContainer:new{ --* (UIManager expects this as 'self.movable')
            self.dialog_frame,
        }
        frame = self.movable
    end
    local keyboard_height = self.keyboard_hidden and 0
            or self._input_widget:getKeyboardDimen().h
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = self.screen_width,
            h = self.screen_height - keyboard_height,
        },
        ignore_if_over = "height",
        frame,
    }
    if Device:isTouchDevice() then
        --* is used to hide the keyboard with a tap outside of inputbox
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self[1].dimen, --* screen above the keyboard
            },
        }
    end
    self:registerHotkeys()
    if self._added_widgets then
        local widget
        for i = 1, #self._added_widgets do
            widget = self._added_widgets[i]
            self:addWidget(widget, true)
        end
    end
end

function InputDialog:addWidget(widget, re_init)
    table.insert(self.layout, #self.layout, { widget })
    if not re_init then
        --* backup widget for re-init
        widget = CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget:getSize().h,
            },
            widget,
        }
        if not self._added_widgets then
            self._added_widgets = {}
        end
        table.insert(self._added_widgets, widget)
    end
    --* insert widget before the bottom buttons and their previous vspan
    table.insert(self.vgroup, #self.vgroup - 1, widget)
end

function InputDialog:getAddedWidgetAvailableWidth()
    return self._input_widget.width
end

function InputDialog:onTap()
    if self.deny_keyboard_hiding then
        return
    end
    if self._input_widget.onCloseKeyboard then
        self._input_widget:onCloseKeyboard()
    end
end

function InputDialog:getInputText()
    return self._input_widget:getText()
end

function InputDialog:getInputValue()
    local text = self:getInputText()
    if self.input_type == "number" then
        return tonumber(text)
    else
        return text
    end
end

function InputDialog:setInputText(text, edited_state)
    self._input_widget:setText(text)
    if edited_state ~= nil and self._buttons_edit_callback then
        self._buttons_edit_callback(edited_state)
    end
end

function InputDialog:isTextEditable()
    return self._input_widget:isTextEditable()
end

function InputDialog:isTextEdited()
    return self._input_widget:isTextEdited()
end

function InputDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onCloseWidget()
    self:onClose()
    UIManager:setDirty(nil, self.fullscreen and "full" or function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onShowKeyboard(ignore_first_hold_release)
    if self._input_widget and not self.readonly and not self.keyboard_hidden then
        self._input_widget:onShowKeyboard(ignore_first_hold_release)
    end
end

function InputDialog:toggleKeyboard(force_hidden)
    if force_hidden and self.keyboard_hidden then
        return
    end
    self.keyboard_hidden = not self.keyboard_hidden
    self.input = self:getInputText() --* re-init with up-to-date text
    self:onClose() --* will close keyboard and save view position
    self:free()
    self:init()
    if not self.keyboard_hidden then
        self:onShowKeyboard()
    end
end

function InputDialog:onKeyboardHeightChanged()
    self.input = self:getInputText() --* re-init with up-to-date text
    self:onClose() --* will close keyboard and save view position
    self._input_widget:onCloseWidget() --* proper cleanup of InputText and its keyboard
    if self._added_widgets then
        --* prevent these externally added widgets from being freed as :init() will re-add them
        for i = 1, #self._added_widgets do
            table.remove(self.vgroup, #self.vgroup - 2)
            self.garbage = i
        end
    end
    self:free()
    --* Restore original text_height (or reset it if none to force recomputing it)
    self.text_height = self.orig_text_height or nil
    self:init()
    if not self.keyboard_hidden then
        self:onShowKeyboard()
    end
    --* Our position on screen has probably changed, so have the full screen refreshed
    UIManager:setDirty("all", "flashui")
end

function InputDialog:onCloseDialog()
    local close_button = self.button_table:getButtonById("close")
    if close_button and close_button.enabled then
        close_button.callback()
        return true
    end
    return false
end

function InputDialog:onClose()
    --* Remember current view & position in case of re-init
    self._top_line_num = self._input_widget.top_line_num
    self._charpos = self._input_widget.charpos
    if self.view_pos_callback then
        --* Give back top line num and cursor position
        self.view_pos_callback(self._top_line_num, self._charpos)
    end
    self._input_widget:onCloseKeyboard()
end

function InputDialog:refreshButtons()
    --* Using what ought to be enough:
    --*   return "ui", self.button_table.dimen
    --* causes 2 non-intersecting refreshes (because if our buttons
    --* change, the text widget did) that may sometimes cause
    --* the button_table to become white.
    --* Safer to refresh the whole widget so the refreshes can
    --* be merged into one.
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:_backupRestoreButtons()
    --* In case of re-init(), keep backup of original buttons and restore them
    if self._buttons_backup_done then
        --* Move backup and override current, and re-create backup from original,
        --* to avoid duplicating the copy code)
        self.buttons = self._buttons_backup --* restore (we may restore 'nil')
    end
    if self.buttons then
        --* (re-)create backup
        self._buttons_backup = {} --* deep copy, except for the buttons themselves
        local row
        for i = 1, #self.buttons do
            row = self.buttons[i]
            if row then
                local row_copy = {}
                self._buttons_backup[i] = row_copy
                for j = 1, #row do
                    row_copy[j] = row[j]
                end
            end
        end
    end
    self._buttons_backup_done = true
end

function InputDialog:_addSaveCloseButtons()
    if not self.buttons then
        self.buttons = { {} }
    end
    --* Add them to the end of first row
    local row = self.buttons[1]
    local button = function(id)
        --* shortcut for more readable code
        return self.button_table:getButtonById(id)
    end
    --* Callback to enable/disable Reset/Save buttons, for feedback when text modified
    self._buttons_edit_callback = function(edited)
        if self._text_modified and not edited then
            self._text_modified = false
            button("save"):disable()
            if button("reset") then
                button("reset"):disable()
            end
            self:refreshButtons()
        elseif edited and not self._text_modified then
            self._text_modified = true
            button("save"):enable()
            if button("reset") then
                button("reset"):enable()
            end
            self:refreshButtons()
        end
        if self.edited_callback then
            self.edited_callback()
        end
    end
    if self.copy_callback then
        table.insert(row, {
            icon = "copy",
            id = "copy",
            icon_size_ratio = 0.57,
            callback = function()
                self.copy_callback()
            end
        })
    end
    if self.reset_callback then
        --* if reset_callback provided, add button to restore
        --* test to some previous state
        table.insert(row, {
            text = KOR.icons.reset_bare,
            id = "reset",
            enabled = self._text_modified,
            callback = function()
                --* Wrapped via Trapper, to allow reset_callback to use Trapper
                --* to show progress or ask questions while getting original content
                require("ui/trapper"):wrap(function()
                    local content, msg = self.reset_callback()
                    if content then
                        self:setInputText(content)
                        self._buttons_edit_callback(false)
                        KOR.messages:notify(_("Text reset"))
                    else
                        --* nil content, assume failure and show msg
                        if msg ~= false then
                            --* false allows for no InfoMessage
                            UIManager:show(InfoMessage:new{
                                text = msg or _("Resetting failed."),
                            })
                        end
                    end
                end)
            end,
        })
    end
    table.insert(row, {
        icon = "save",
        id = "save",
        enabled = self._text_modified or self.force_save_enabled,
        callback = function()
            --* Wrapped via Trapper, to allow save_callback to use Trapper
            --* to show progress or ask questions while saving
            require("ui/trapper"):wrap(function()
                if self._text_modified or self.force_save_enabled then
                    local success, msg = self.save_callback(self:getInputText())
                    if success == false then
                        if msg ~= false then
                            --* false allows for no InfoMessage
                            UIManager:show(InfoMessage:new{
                                text = msg or _("Saving failed."),
                            })
                        end
                    else
                        --* nil or true
                        self._buttons_edit_callback(false)
                        if not msg then
                            msg = _("Saved")
                        end
                        KOR.messages:notify(msg)
                    end
                end
            end)
        end,
    })
    local cancel_button = {
        id = "close",
        callback = function()
            if self._text_modified then
                UIManager:show(MultiConfirmBox:new{
                    text = self.close_unsaved_confirm_text or _("You have unsaved changes."),
                    cancel_text = self.close_cancel_button_text or _("Cancel"),
                    choice1_text = self.close_discard_button_text or _("Discard"),
                    choice1_callback = function()
                        if self.close_callback then
                            self.close_callback()
                        end
                        UIManager:close(self)
                        local text = self.close_discarded_notif_text or _("Changes discarded")
                        KOR.messages:notify(text)
                    end,
                    choice2_text = self.close_save_button_text or _("Save"),
                    choice2_callback = function()
                        --* Wrapped via Trapper, to allow save_callback to use Trapper
                        --* to show progress or ask questions while saving
                        require("ui/trapper"):wrap(function()
                            local success, msg = self.save_callback(self:getInputText(), true)
                            if success == false then
                                if msg ~= false then
                                    --* false allows for no InfoMessage
                                    UIManager:show(InfoMessage:new{
                                        text = msg or _("Saving failed."),
                                    })
                                end
                            else
                                --* nil or true
                                if self.close_callback then
                                    self.close_callback()
                                end
                                UIManager:close(self)
                                if not msg then
                                    msg = _("Saved")
                                end
                                KOR.messages:notify(msg)
                            end
                        end)
                    end,
                })
            else
                --* Not modified, exit without any message
                if self.close_callback then
                    self.close_callback()
                end
                UIManager:close(self)
            end
        end,
    }
    if self.close_button_text then
        cancel_button.text = self.close_button_text
    else
        cancel_button.icon = "back"
        cancel_button.icon_size_ratio = 0.7
    end
    table.insert(row, cancel_button)
end

function InputDialog:_addScrollButtons(nav_bar)
    local row
    if nav_bar then
        --* Add Home / End / Up / Down buttons as a last row
        if not self.buttons then
            self.buttons = {}
        end
        row = {} --* Empty additional buttons row
        table.insert(self.buttons, row)
    else
        --* Add the Up / Down buttons to the first row
        if not self.buttons then
            self.buttons = { {} }
        end
        row = self.buttons[1]
    end
    if nav_bar then
        --* Add the Home & End buttons
        --* Also add Keyboard hide/show button if we can
        if self.fullscreen and not self.readonly then
            table.insert(row, {
                text = self.keyboard_hidden and "↑⌨" or "↓⌨",
                id = "keyboard",
                callback = function()
                    self:toggleKeyboard()
                end,
            })
        end
        if self.fullscreen then
            --* add a button to search for a string in the edited text
            table.insert(row, {
                icon = "appbar.search",
                icon_size_ratio = 0.6,
                callback = function()
                    local keyboard_hidden_state = not self.keyboard_hidden
                    self:toggleKeyboard(true) --* hide text editor keyboard
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter text to search for"),
                        stop_events_propagation = true, --* avoid interactions with upper InputDialog
                        input = self.search_value,
                        buttons = {
                            {
                                {
                                    icon = "back",
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                        self.keyboard_hidden = keyboard_hidden_state
                                        self:toggleKeyboard()
                                    end,
                                },
                                {
                                    text = KOR.icons.first_bare,
                                    callback = function()
                                        self:findCallback(keyboard_hidden_state, input_dialog, true)
                                    end,
                                },
                                {
                                    text = KOR.icons.next_bare,
                                    is_enter_default = true,
                                    callback = function()
                                        self:findCallback(keyboard_hidden_state, input_dialog)
                                    end,
                                },
                            },
                        },
                    }

                    self.check_button_case = CheckButton:new{
                        text = _("Case sensitive"),
                        checked = self.case_sensitive,
                        parent = input_dialog,
                        callback = function()
                            self.case_sensitive = self.check_button_case.checked
                        end,
                    }
                    input_dialog:addWidget(self.check_button_case)

                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            })
            table.insert(row, KOR.buttoninfopopup:forInputDialogSearchFirst({
                id = "search_next",
                callback = function()
                    if has_text(self.search_value) then
                        self:findCallback("force_hidden", nil, true, "force_next")
                    else
                        KOR.messages:notify("nog geen zoekterm opgegeven...")
                    end
                end,
            }))
            table.insert(row, KOR.buttoninfopopup:forInputDialogSearchNext({
                id = "search_next",
                callback = function()
                    if has_text(self.search_value) then
                        self:findCallback("force_hidden", nil, false, "force_next")
                    else
                        KOR.messages:notify("nog geen zoekterm opgegeven...")
                    end
                end,
            }))
            --* Add a button to go to the line by its number in the file
            table.insert(row, {
                icon = "goto-line",
                icon_size_ratio = 0.7,
                callback = function()
                    local keyboard_hidden_state = not self.keyboard_hidden
                    self:toggleKeyboard(true) --* hide text editor keyboard
                    local cur_line_num, last_line_num = self._input_widget:getLineNums()
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter line number"),
                        --* @translators %1 is the current line number, %2 is the last line number
                        input_hint = T(_("%1 (1 - %2)"), cur_line_num, last_line_num),
                        input_type = "number",
                        stop_events_propagation = true, --* avoid interactions with upper InputDialog
                        buttons = { {
                                        {
                                            icon = "back",
                                            id = "close",
                                            callback = function()
                                                UIManager:close(input_dialog)
                                                self.keyboard_hidden = keyboard_hidden_state
                                                self:toggleKeyboard()
                                            end,
                                        },
                                        {
                                            text = _("Go to line"),
                                            is_enter_default = true,
                                            callback = function()
                                                local new_line_num = tonumber(input_dialog:getInputText())
                                                if new_line_num and new_line_num >= 1 and new_line_num <= last_line_num then
                                                    UIManager:close(input_dialog)
                                                    self.keyboard_hidden = keyboard_hidden_state
                                                    self:toggleKeyboard()
                                                    self._input_widget:moveCursorToCharPos(self._input_widget:getLineCharPos(new_line_num))
                                                end
                                            end,
                                        },
                                    },
                        },
                    }
                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            })
        end
        table.insert(row, {
            text = "⇱",
            id = "top",
            vsync = true,
            callback = function()
                self._input_widget:scrollToTop()
            end,
        })
        table.insert(row, {
            text = "⇲",
            id = "bottom",
            vsync = true,
            callback = function()
                self._input_widget:scrollToBottom()
            end,
        })
    end

    --* Add the Up & Down buttons
    table.insert(row, {
        text = "△",
        id = "up",
        callback = function()
            self._input_widget:scrollUp()
        end,
    })
    table.insert(row, {
        text = "▽",
        id = "down",
        callback = function()
            self._input_widget:scrollDown()
        end,
    })
    --* I disabled this, because I always want to have the buttons available for quick navigation:
    --* Callback to enable/disable buttons, for at-top/at-bottom feedback
    --[[local prev_at_top = false --* Buttons were created enabled
    local prev_at_bottom = false
    local button = function(id) --* shortcut for more readable code
        return self.button_table:getButtonById(id)
    end

    self._buttons_scroll_callback = function(low, high)
        local changed = false
        if prev_at_top and low > 0 then
            button("up"):enable()
            if button("top") then button("top"):enable() end
            prev_at_top = false
            changed = true
        elseif not prev_at_top and low <= 0 then
            button("up"):disable()
            if button("top") then button("top"):disable() end
            prev_at_top = true
            changed = true
        end
        if prev_at_bottom and high < 1 then
            button("down"):enable()
            if button("bottom") then button("bottom"):enable() end
            prev_at_bottom = false
            changed = true
        elseif not prev_at_bottom and high >= 1 then
            button("down"):disable()
            if button("bottom") then button("bottom"):disable() end
            prev_at_bottom = true
            changed = true
        end
        if changed then
            self:refreshButtons()
        end
    end]]
end

function InputDialog:findCallback(keyboard_hidden_state, input_dialog, find_first, force_next)

    if not force_next then
        if has_no_text(self.search_value) and input_dialog then
            self.search_value = input_dialog:getInputText()
            if self.search_value == "" then
                return
            end
            UIManager:close(input_dialog)
        end
    end
    if keyboard_hidden_state == "force_hidden" then
        self.keyboard_hidden = true
        self:toggleKeyboard("force_hidden")
    else
        self.keyboard_hidden = keyboard_hidden_state
        self:toggleKeyboard()
    end
    local start_pos = find_first and 1 or self._charpos + 1
    local char_pos = util.stringSearch(self.input, self.search_value, self.case_sensitive, start_pos)
    local msg
    if char_pos > 0 then
        --* always display hits at top of screen:
        self:scrollToBottom()
        self._charpos = char_pos
        --* call ((InputText#moveCursorToCharPos)):
        self._input_widget:moveCursorToCharPos(char_pos)
        msg = T(_("Found in line %1."), self._input_widget:getLineNums())
    else
        msg = _("Not found.")
    end
    KOR.messages:notify(msg)
end

--* ==================== SMARTSCRIPTS =====================

function InputDialog:scrollToBottom()
    self._input_widget:scrollToBottom()
end

function InputDialog:showNonAsciiAlert(insertion)
    if not insertion then
        insertion = ""
    end
    KOR.dialogs:niceAlert("Let op!", "Non-ascii tekens aangetroffen, gebruik daarom " .. insertion .. "enkel het onscreen toetsenbord.\n\nTekstsnippets en -commando's niet beschikbaar voor het onscreen toetsenbord...", {
        delay = 3,
    })
end

--* this method can get called because of ((dont block event handling for key presses)) in ((InputText)):
function InputDialog:onGetHardwareInput()

    --! see also ((load virtual keyboard)), ((load hardware keyboard))

    --* see ((get pressed hardware key)):
    local key = KOR.registry:getOnce("pressed_key")
    --* see ((get active modifier key)):
    if key then

        local modifier = KOR.registry:getOnce("pressed_modifier")

        -- #((enable tab activation with Shift+Space))
        if key == " " and modifier then
            return false
        end

        local prev_content = self._input_widget:getText()
        if KOR.strings:hasNonAscii(prev_content) then
            self:showNonAsciiAlert()
            return false
        end
        local current_pos = self._input_widget:getCharPos()
        local string_pos = current_pos - 1
        local content_length = prev_content:len()

        local enable_before_end_input = true
        local new_content, is_command_handled, first_word_char, has_non_ascii

        --* somewhere in the middle of the input:
        if enable_before_end_input and content_length > 0 and string_pos ~= content_length then

            local pre = prev_content:sub(1, string_pos)
            local after = prev_content:sub(string_pos + 1)
            new_content = pre .. key
            local unmodified_length = new_content:len()

            --* do nothing if non ascii chars encountered:
            first_word_char, has_non_ascii = KOR.strings:getFirstWordChar(new_content)
            if has_non_ascii then
                self:showNonAsciiAlert("verder ")
                new_content = new_content .. after
                self._input_widget:setText(new_content)
                --* call ((InputText#moveCursorToCharPos)):
                self._input_widget:moveCursorToCharPos(current_pos + 1)
                return
            end

            new_content, is_command_handled = KOR.substitutions:handleCommands(new_content, first_word_char)

            if is_command_handled then
                current_pos = current_pos + new_content:len() - unmodified_length - 1

            elseif KOR.substitutions.enabled then
                local charpos_correction
                new_content, charpos_correction = KOR.substitutions:insert(new_content, first_word_char, "text_end_only")
                current_pos = current_pos + charpos_correction
            end

            new_content = new_content .. after
            new_content = KOR.substitutions:removeRedundantWhitespace(new_content)

            self._input_widget:setText(new_content)
            --* call ((InputText#moveCursorToCharPos)):
            self._input_widget:moveCursorToCharPos(current_pos + 1)
            --self._input_widget.charpos = current_pos + 1

            --* at the end of the input:
        else

            new_content = prev_content .. key

            first_word_char, has_non_ascii = KOR.strings:getFirstWordChar(new_content)
            if has_non_ascii then
                self:showNonAsciiAlert("verder ")
                self._input_widget:setText(new_content)
                --* call ((InputText#goToEnd)):
                self._input_widget:goToEnd()
                return
            end

            new_content = KOR.substitutions:removeRedundantWhitespace(new_content)

            new_content, is_command_handled = KOR.substitutions:handleCommands(new_content, first_word_char)

            --* no charpos_correction needed here, because we call ((InputText#goToEnd)):
            if not is_command_handled and KOR.substitutions.enabled then
                new_content = KOR.substitutions:insert(new_content, first_word_char, "text_end_only")
            end

            self._input_widget:setText(new_content)
            --* call ((InputText#goToEnd)):
            self._input_widget:goToEnd()
        end
    end

    return true
end

function InputDialog:onIgnoreAltSpace()
    return false
end

function InputDialog:registerHotkeys()
    if Device:hasKeys() then
        self.key_events.CloseDialog = { { Input.group.CloseDialog } }
        --! this one really needed to handle BT keyboard input:
        --* @see ((onGetHardwareInput)):
        self.key_events.GetHardwareInput = { { Input.group.FieldInput } }
        self.key_events.IgnoreAltSpace = Input.group.AltSpace

        if self.activate_tab_callback and self.tabs_count then
            self:registerTabHotkey()
        end
    end
end

function InputDialog:registerCustomKeyEvent(hotkey, handler_label, handler_callback)
    self["on" .. handler_label] = handler_callback
    self.key_events[handler_label] = type(hotkey) == "table" and hotkey or { { hotkey } }
end

function InputDialog:onActivateNextTab()
    if not self.active_tab then
        self.active_tab = 1
    end
    self.active_tab = self.active_tab + 1
    if self.active_tab > self.tabs_count then
        self.active_tab = 1
    end
    self.activate_tab_callback(self.active_tab)
    return true
end

function InputDialog:registerTabHotkey()

    --* for the input field we filtered Shift+Space hotkeys out, to enable this tab activation; see ((enable tab activation with Shift+Space)) above:
    self.key_events.ActivateNextTab = Input.group.AltT
end

return InputDialog
