
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Messages = require("extensions/messages")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Registry = require("extensions/registry")
local ScreenHelpers = require("extensions/screenhelpers")
local Size = require("ui/size")
local Strings = require("extensions/strings")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

--- @class Dialogs
local Dialogs = WidgetContainer:extend {
    current_overlay_instance = 0,
    items_per_page = G_reader_settings:readSetting("items_per_page") or 16,
    overlay = nil,
    overlays = {},
}

-- use timeout = nil for second argument when calling for no timeout:
function Dialogs:alertError(message, timeout, dismiss_callback)
    UIManager:show(InfoMessage:new{ text = message, icon = "notice-exclamation", timeout = timeout, dismiss_callback = dismiss_callback, modal = false })
end

-- use timeout = nil for second argument when calling for no timeout:
function Dialogs:alertInfo(message, timeout, dismiss_callback, pos)

    local y_pos
    if pos and pos.pos then
        y_pos = pos.pos.y + 24
    end
    local config = { text = message, timeout = timeout, dismiss_callback = dismiss_callback, move_to_y_pos = y_pos }
    local instance = InfoMessage:new(config)
    UIManager:show(instance)
    return instance
end

function Dialogs:getFullWidthDialogWidth()
    return Screen:getWidth() - 15
end

function Dialogs:getTwoThirdDialogWidth()
    local orientation = Screen:getScreenMode()
    local iwidth = (2 * Screen:getWidth() / 3) + 20
    if orientation == "portrait" then
        iwidth = Screen:getWidth() - 80
    end
    return iwidth
end

function Dialogs:confirm(question, callback, cancel_callback, wide_dialog, show_icon, face)
    if self.messages[question] then
        question = self.messages[question]
    end
    if show_icon == nil then
        show_icon = true
    end
    local dialog = ConfirmBox:new{
        text = question,
        wide_dialog = wide_dialog,
        face = face or Font:getFace("x_smallinfofont"),
        ok_icon = "yes",
        cancel_icon = "back",
        show_icon = show_icon,
        ok_callback = function()
            callback()
        end,
        cancel_callback = function()
            if cancel_callback ~= nil then
                cancel_callback()
            end
        end,
    }
    UIManager:show(dialog)
    return dialog
end

-- keyboard_height was determined and stored in ((InputDialog#init)) > ((InputDialog#storeKeyboardHeight)):
function Dialogs:getKeyboardHeight()
    local height = G_reader_settings:readSetting("keyboard_height")
    if height then
        return height
    end
    if Registry.is_ubuntu_device then
        return 269
    end
    return 506
end

-- timeout 0 lets the notification remain on the screen:
function Dialogs:notify(message, timeout, dont_inhibit_input, at_right_top)
    message = tostring(message)
    if not Registry:getOnce("notify_case_sensitive") then
        message = message:lower()
    end
    return Messages:notify(message, timeout, dont_inhibit_input, at_right_top)
end

--- @param args table, containing: value, hint, callback, cancel_callback
function Dialogs:prompt(args)
    local allow_newline = args.allow_newline or false
    local prompt_dialog, cancel_button, save_button

    -- ! if args.buttons is set, then the callbacks of those buttons MUST retrieve the entered value with getInputText method !!!!

    if not args.buttons then
        cancel_button = {
            callback = function()
                UIManager:close(prompt_dialog)
                if args.cancel_callback then
                    args.cancel_callback()
                end
            end,
        }
        cancel_button.icon = args.cancel_button_icon or "back"
        save_button = {
            is_enter_default = not allow_newline,
            callback = function()
                local newval = args.fields and prompt_dialog:getFields() or prompt_dialog:getInputText()
                UIManager:close(prompt_dialog)
                args.callback(newval)
            end,
        }
        save_button.icon = args.save_button_icon or "save"
    end
    local buttons = args.buttons or {{
        cancel_button,
        save_button,
    }}
    if args.middle_callback and args.middle_callback_icon then
        table.insert(buttons, 2, {
            icon = args.middle_callback_icon,
            callback = function()
                local newval = args.fields and prompt_dialog:getFields() or prompt_dialog:getInputText()
                UIManager:close(prompt_dialog)
                args.middle_callback(newval)
            end,
        })
    elseif args.middle_callback and args.middle_callback_text then
        table.insert(buttons, 2, {
            text = args.middle_callback_text,
            callback = function()
                local newval = args.fields and prompt_dialog:getFields() or prompt_dialog:getInputText()
                UIManager:close(prompt_dialog)
                args.middle_callback(newval)
            end,
        })
    end
    local config = {
        title = args.title or "Bewerk",
        -- if not forced to fullscreen, width MUST be set, to not get problems with CheckButton, if that widget must be included in the dialog:
        width = args.width or self:getTwoThirdDialogWidth(),
        fullscreen = args.fullscreen or false,
        auto_field_height = args.auto_field_height,
        buttons = buttons,
    }
    if args.fields then
        config.fields = args.fields
        config.has_field_rows = args.has_field_rows
        config.auto_field_height = args.auto_field_height
    else
        config.input = args.input or ""
        config.input_hint = args.input_hint
        config.input_type = args.input_type
        config.text_type = args.is_password and "password" or "text"
        config.description = args.description
        config.description_face = args.description_face or Font:getFace("x_smallinfofont")
        config.allow_newline = allow_newline
        config.cursor_at_end = args.cursor_at_end or true
    end
    local widget = args.fields and MultiInputDialog or InputDialog
    prompt_dialog = widget:new(config)
    UIManager:show(prompt_dialog)
    prompt_dialog:onShowKeyboard()

    return prompt_dialog
end

function Dialogs:promptWide(args)

    local callback = args.callback
    if not callback and not args.buttons then
        return
    end
    args.fullscreen = true
    args.covers_fullscreen = true
    return self:prompt(args)
end

function Dialogs:closeOverlay()
    if self.current_overlay_instance > 1 then
        self:closeAllOverlays()
        return
    end

    UIManager:close(self.overlays[self.current_overlay_instance])
    self.overlays[self.current_overlay_instance] = nil
    self.current_overlay_instance = self.current_overlay_instance - 1
end

function Dialogs:closeAllOverlays()
    if self.current_overlay_instance == 0 then
        return
    end
    for i = self.current_overlay_instance, 1, -1 do
        UIManager:close(self.overlays[i])
        self.overlays[i] = nil
    end
    self.current_overlay_instance = 0
    self.overlays = {}
end

function Dialogs:showOverlay(close_previous_instance)
    if close_previous_instance and self.overlays[self.current_overlay_instance] then
        self:closeOverlay()
    elseif self.overlays[self.current_overlay_instance] then
        return
    end

    local config = {
        text = "",
        alignment = "center",
        height = Screen:getHeight(),
        width = Screen:getWidth(),
        show_icon = false,
        covers_fullscreen = true,
        -- force this frame to be painted UNDER other frames (true would force it to be painted ABOVE all other widgets then present):
        modal = false,
    }
    self.current_overlay_instance = self.current_overlay_instance + 1
    self.overlays[self.current_overlay_instance] = InfoMessage:new(config)
    UIManager:show(self.overlays[self.current_overlay_instance])

    return self.overlays[self.current_overlay_instance]
end

function Dialogs:showOverlayReloaded()
    -- info: especially handy to force an overlay behind an InputDialog:
    self:closeOverlay()
    self:showOverlay()
end

--[[
Example of textbox with custom buttons:
local lang = "nl"
if path:match("Romans %- EN") then
	lang = "en"
end
local viewer
viewer = Dialogs:textBox({ title = "Circa " .. count .. " ebooks toegevoegd", info = files_list })
]]
function Dialogs:textBox(args)

    -- here only props which are needed for computations:
    local height = args.height or Screen:getHeight() - 80
    local info = args.info or ""
    info = Strings:htmlToPlainTextIfHtml(info)
    -- hotfix for initials in names:
    info = info:gsub("([A-Z]%.)\n([A-Z]%.)", "%1%2")
    local width_factor = args.width_factor or 1
    local title = args.title
    local use_scrolling_dialog = 1
    if args.use_scrolling_dialog ~= nil then
        use_scrolling_dialog = args.use_scrolling_dialog
    end
    if args.fixed_face and type(args.fixed_face) == "string" then
        args.fixed_face = Font:getFace(args.fixed_face)
    end

    local config = {
        active_tab = args.active_tab,
        add_fullscreen_padding = args.add_fullscreen_padding,
        add_margin = args.add_margin,
        add_more_padding = args.add_more_padding,
        add_padding = args.add_padding,
        after_load_callback = args.after_load_callback,
        block_height_adaptation = args.block_height_adaptation,
        button_font_face = args.button_font_face or "cfont",
        button_font_size = args.button_font_size or 20,
        button_font_weight = args.button_font_weight or "bold",
        buttons_table = args.buttons_table,
        close_button_font_size = args.close_button_font_size or 30,
        close_callback = args.close_callback,
        covers_fullscreen = args.covers_fullscreen,
        dont_pause_stats = args.dont_pause_stats,
        event_after_close = args.event_after_close,
        extra_button = args.extra_button,
        extra_button_position = args.extra_button_position,
        extra_button2 = args.extra_button2,
        extra_button2_position = args.extra_button2_position,
        extra_button3 = args.extra_button3,
        extra_button3_position = args.extra_button3_position,
        extra_button_rows = args.extra_button_rows,
        fixed_face = args.fixed_face,
        full_height = args.full_height,
        fullscreen = args.fullscreen,
        height = height,
        justified = false,
        lang = args.lang or "en",
        -- if modal is true, then make sure a textviewer window is displayed fully, even with visible keyboard in dialogs:
        modal = args.modal,
        next_item_callback = args.next_item_callback,
        no_overlay = args.no_overlay,
        overlay_managed_by_parent = args.overlay_managed_by_parent,
        paragraph_headings = args.paragraph_headings,
        prev_item_callback = args.prev_item_callback,
        text_margin = args.text_margin or Size.margin.small,
        text_padding = args.text_padding or Size.padding.large,
        text_padding_top_bottom = args.text_padding_top_bottom,
        title = title,
        title_face = args.title_face,
        title_shrink_font_to_fit = args.title_shrink_font_to_fit or false,
        title_tab_buttons = args.title_tab_buttons,
        title_tab_callbacks = args.title_tab_callbacks,
        tabs_table_buttons = args.tabs_table_buttons,
        title_alignment = args.title_alignment,
        text = info,
        top_buttons_left = args.top_buttons_left,
        top_buttons_right = args.top_buttons_right,
        use_scrolling_dialog = use_scrolling_dialog,
        use_low_height = args.low_height,
        width_factor = width_factor,
    }

    if not args.low_height then
        local text_padding_left_right = args.text_padding_left_right
        local use_wide_description_dialog = false
        if use_wide_description_dialog and args.for_description_dialog then
            width_factor = args.for_description_dialog and 0.99 or 0.98
            text_padding_left_right = ScreenHelpers:isLandscapeScreen() and Screen:scaleBySize(105) or Screen:scaleBySize(35)
        elseif args.narrow_text_window or args.for_description_dialog then
            width_factor = ScreenHelpers:isLandscapeScreen() and 0.87 or 0.95
            text_padding_left_right = Screen:scaleBySize(35)
        end
        config.use_low_height = nil
        config.height = height or math.floor(Screen:getHeight() * 0.8)
        config.use_computed_height = args.use_computed_height or false
        config.text_padding_left_right = text_padding_left_right
    end

    -- you can optionally add a buttons_table setting:
    local textviewer
    textviewer = TextViewer:new(config)
    UIManager:show(textviewer)

    -- optionally search for a externally transmitted search string:
    local external_search_string = Registry:getOnce("textviewer_needle")
    if external_search_string then
        title = title .. " - zoek: " .. external_search_string
        -- #((send external searchstring for xray info))
        textviewer:findCallback(nil, external_search_string)
    end

    -- return the instance, so we can close it
    -- from a custom button table:
    return textviewer
end

function Dialogs:textBoxTabbed(active_tab, args)
    if self.tabbed_textbox then
        UIManager:close(self.tabbed_textbox)
    end
    if not active_tab then
        active_tab = 1
    end
    local info
    -- tabs in buttons table row:
    if G_reader_settings:readSetting("tabs_as_table") then
        local buttons = {{}}
        for i = 1, #args.tabs do
            local label = args.tabs[i].tab
            if i == active_tab then
                if args.other_factory then
                    info = args.other_factory()
                    args.other_factory = nil
                else
                    info = type(args.tabs[i].info) == "function" and args.tabs[i].info() or args.tabs[i].info
                end
            end
            table.insert(buttons[1], {
                text = label,
                is_target_tab = args.tabs[i].is_target_tab,
                target_button_text = args.tabs[i].target_button_text,
                callback = function()
                    local has_text_factory = type(args.tabs[i].info) == "function" or args.other_factory
                    if i == active_tab and not has_text_factory then
                        return
                    end
                    if has_text_factory and args.tabs[i].target_tab then
                        active_tab = args.tabs[i].target_tab
                        args.active_tab = active_tab
                        args.other_factory = args.tabs[i].info
                        self:textBoxTabbed(args.tabs[i].target_tab, args)
                        return
                    end
                    self:textBoxTabbed(i, args)
                end
            })
        end
        -- tabs table will be generated in ((TextViewer#generateTabsTable))
        args.tabs_table_buttons = buttons
        args.title_alignment = "center"

    -- tabs in title bar:
    else
        local title_tab_buttons = {}
        local title_tab_callbacks = {}
        for i = 1, #args.tabs do
            local tab_label = args.tabs[i].tab
            -- for title bar tabs add padding by spaces:
            tab_label = " " .. tab_label
            tab_label = tab_label .. " "
            if i == active_tab then
                tab_label = " •" .. tab_label
            end

            table.insert(title_tab_buttons, tab_label)
            if i == active_tab then
                info = type(args.tabs[i].info) == "function" and args.tabs[i].info() or args.tabs[i].info
            end
            table.insert(title_tab_callbacks, function()
                if i == active_tab then
                    return
                end
                self:textBoxTabbed(i, args)
            end)
        end
        args.title_tab_buttons = title_tab_buttons
        args.title_tab_callbacks = title_tab_callbacks
    end
    args.info = info
    args.active_tab = active_tab
    if not args.no_fullscreen then
        args.fullscreen = true
    end
    self.tabbed_textbox = self:textBox(args)
    return self.tabbed_textbox
end

function Dialogs:showButtonDialog(title, button_table, no_overlay, show_parent)
    if not no_overlay then
        self:showOverlay()
    end
    local dialog
    dialog = ButtonDialogTitle:new{
        title = title,
        no_overlay = no_overlay,
        move_to_top = true,
        use_low_title = true,
        button_font_face = Font:getFace("x_smallinfofont"),
        button_font_size = 17,
        button_font_bold = false,
        button_font_weight = "normal",
        title_align = "center",
        width_factor = 0.95,
        show_parent = show_parent,
        buttons = button_table,
    }
    UIManager:show(dialog)
    self:closeOverlay()
    return dialog
end

return Dialogs
