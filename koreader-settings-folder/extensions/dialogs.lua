
local require = require

local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local ConfirmBox = require("extensions/widgets/confirmbox")
local Font = require("extensions/modules/font")
local HtmlBox = require("extensions/widgets/htmlbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("extensions/widgets/inputdialog")
local KOR = require("extensions/kor")
local MultiInputDialog = require("extensions/widgets/multiinputdialog")
local NiceAlert = require("extensions/widgets/nicealert")
local TextViewer = require("extensions/widgets/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local math = math
local table = table
local type = type

--- @class Dialogs
local Dialogs = WidgetContainer:extend{
    overlay = nil,
    widgets = {},
}

--* this method will be called by ((KOR#initExtensions)):
function Dialogs:init()
    KOR:registerWidget("nicealert", NiceAlert)
end

--* dialogs closed here were registered with ((Dialogs#registerWidget)):
--* alas, we can't use UIManager:broadcastEvent(Event:new("Close")) here, because that also closes KOReader:
function Dialogs:closeAllWidgets()
    local widget
    for i = #self.widgets, 1, -1 do
        widget = self.widgets[i]
        UIManager:close(widget)
        self.widgets[i] = nil
    end
    KOR.screenhelpers:refreshDialog()
    self.widgets = {}
end

function Dialogs:computePagePosition(dialogOrPage)
    if not dialogOrPage then
        return 1
    end
    local select_number = 1
    if type(dialogOrPage) == "table" and dialogOrPage.page and dialogOrPage.perpage then
        select_number = (dialogOrPage.page - 1) * dialogOrPage.perpage + 1
    elseif type(dialogOrPage) == "number" then
        select_number = (dialogOrPage - 1) * 16 + 1
    end
    return select_number
end

function Dialogs:registerWidget(widget)
    table.insert(self.widgets, widget)
end

function Dialogs:unregisterWidget(iwidget)
    KOR.tables:filterIpairsTable(self.widgets, iwidget)
end

function Dialogs:registerContextOverlay(overlay)
    self.context_overlay = overlay
end

function Dialogs:closeContextOverlay()
    UIManager:close(self.context_overlay)
    self.context_overlay = nil
end

function Dialogs:getTwoThirdDialogWidth()
    local orientation = Screen:getScreenMode()
    local iwidth = (2 * Screen:getWidth() / 3) + 20
    if orientation == "portrait" then
        iwidth = Screen:getWidth() - 80
    end
    return iwidth
end

function Dialogs:getThreeQuarterDialogWidth()
    local orientation = Screen:getScreenMode()
    local iwidth = (3 * Screen:getWidth() / 4) + 20
    if orientation == "portrait" then
        iwidth = Screen:getWidth() - 80
    end
    return iwidth
end

--* see ((DIALOGS))
--* compare ((niceAlert)) for plain text message windows:
function Dialogs:htmlBox(args)

    --* args/config.window_size can be: "fullscreen", "max", "large", "medium" or "small", or a table with props h and w:
    --* you also can set args.title_tab_buttons_left and args.title_tab_callbacks:
    local config = args
    config.html = config.html
      :gsub("%[%[%[", "<b>")
      :gsub("%]%]%]", "</b>")

    local box = HtmlBox:new(config)
    UIManager:show(box)

    --* because htmlBoxTabbed already registered in its own method:
    if not args.tabs then
        self:registerWidget(box)
    end

    return box
end

--* see ((DIALOGS))
--* compare ((textBoxTabbed)):
function Dialogs:htmlBoxTabbed(active_tab, args)
    if self.tabbed_htmlbox then
        UIManager:close(self.tabbed_htmlbox)
    end

    KOR.tabfactory:setTabButtonAndContent(self, "htmlBoxTabbed", active_tab, args)

    --* in most cases make the tab fullscreen:
    if not args.no_fullscreen and not args.window_size == "max" then
        args.window_size = "fullscreen"
    end

    self.tabbed_htmlbox = self:htmlBox(args)
    self:registerWidget(self.tabbed_htmlbox)

    return self.tabbed_htmlbox
end

function Dialogs:confirm(question, callback, cancel_callback, wide_dialog, show_icon, face)

    if not question:match("^\n") then
        question = "\n" .. question
    end
    if not question:match("\n$") then
        question = question .. "\n"
    end
    if show_icon == nil then
        show_icon = true
    end
    local buttons = {{
          {
              icon = "back",
              is_enter_default = false,
              icon_size_ratio = 0.7,
              callback = function()
                  UIManager:close(self.confirm_dialog)
                  if cancel_callback ~= nil then
                      cancel_callback()
                  end
              end
          },
          {
              icon = "yes",
              is_enter_default = true,
              callback = function()
                  UIManager:close(self.confirm_dialog)
                  callback()
              end
          },
      }}
    local confirm_middle_button = KOR.registry:get("confirm_middle_button")
    if confirm_middle_button then
        local old_callback = confirm_middle_button.callback
        confirm_middle_button.callback = function()
            UIManager:close(self.confirm_dialog)
            old_callback()
        end
        table.insert(buttons[1], 2, confirm_middle_button)
    end
    self.confirm_dialog = ConfirmBox:new{
        text = question,
        wide_dialog = wide_dialog,
        face = face or Font:getDefaultDialogFontFace(),
        show_icon = show_icon,
        buttons = buttons,
    }
    UIManager:show(self.confirm_dialog)
    return self.confirm_dialog
end

--- @param args table, which can contain items: value, hint, callback, cancel_callback, middle_callback, allow_newline, fields
function Dialogs:prompt(args)
    local prompt_dialog, cancel_button, save_button

    --* example call:
--[[
    KOR.dialogs:prompt({
        input = "",
        description = "toelichting:",
        callback = function(new_text)
        end,
        cancel_callback = function()
        end,
        save_button_text = "voer uit"
    })
]]

    --! if args.buttons is set, then the callbacks of those buttons MUST retrieve the entered value with getInputText method !!!!

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
            is_enter_default = not args.allow_newline,
            icon_size_ratio = args.save_button_icon_size_ratio or 0.7,
            callback = function()
                local newval = args.fields and prompt_dialog:getFields() or prompt_dialog:getInputText()
                UIManager:close(prompt_dialog)
                args.callback(newval)
            end,
        }
        save_button.icon = args.save_button_icon or "yes"
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
    local config = args
    config.title = args.title or "Bewerk"
    --* if not forced to fullscreen, width MUST be set, to not get problems with CheckButton, if that widget must be included in the dialog:
    config.width = args.width or self:getTwoThirdDialogWidth()
    args.close_callback = function()
        UIManager:close(prompt_dialog)
    end
    config.buttons = buttons
    if not args.fields then
        config.text_type = args.is_password and "password" or "text"
        config.description_face = args.description_face or Font:getDefaultDialogFontFace()
        config.cursor_at_end = args.cursor_at_end ~= false
    end
    local widget = args.fields and MultiInputDialog or InputDialog
    prompt_dialog = widget:new(config)
    UIManager:show(prompt_dialog)
    prompt_dialog:onShowKeyboard()

    return prompt_dialog
end

function Dialogs:closeOverlay()
    if KOR.registry:get("fullscreen_dialog_active") then
        return
    end

    UIManager:close(self.overlay)
end

function Dialogs:closeAllDialogs()
    KOR.descriptiondialog:closeAllInstances()
    KOR.contextdialog:closeContextDialog()
    self:closeAllOverlays()
    self:closeAllWidgets()
    UIManager:closeAllWidgetsExceptMainScreen()
end

function Dialogs:closeAllOverlays()
    if not self.overlay then
        return
    end
    UIManager:close(self.overlay)
    self.overlay = nil
end

function Dialogs:showOverlay(caller_hint, modal)
    if self.overlay then
        UIManager:close(self.overlay)
    end
    if modal == nil then
        modal = false
    end
    local debug_overlay = false
    local config = {
        text = "",
        alignment = "center",
        height = Screen:getHeight(),
        width = Screen:getWidth(),
        show_icon = false,
        covers_fullscreen = true,
        modal = modal,
    }
    if debug_overlay then
        local text = "overlay"
        if caller_hint then
            text = text .. ": " .. caller_hint
        end
        config.text = text
    end
    self.overlay = InfoMessage:new(config)
    UIManager:show(self.overlay)

    return self.overlay
end

function Dialogs:showOverlayReloaded(caller_hint, modal)
    --* especially handy to force an overlay behind an InputDialog:
    self:closeAllOverlays()
    return self:showOverlay(caller_hint, modal)
end

--[[
Example of textbox with custom buttons:
local lang = "nl"
if path:match("Romans %- EN") then
	lang = "en"
end
local viewer
viewer = KOR.dialogs:textBox({ title = "Circa " .. count .. " ebooks toegevoegd", info = files_list })

]]
--* see ((DIALOGS))
function Dialogs:textBox(args)

    --* here only props which are needed for computations:
    local org_height = args.height or Screen:getHeight() - 80
    local info = args.info or ""
    info = KOR.html:htmlToPlainTextIfHtml(info)
    --* hotfix for initials in names:
    info = info:gsub("([A-Z]%.)\n([A-Z]%.)", "%1%2")

    args.text = info

    args.width_factor = args.width_factor or 1
    --local use_scrolling_dialog = args.use_scrolling_dialog or 1
    if args.fixed_face and type(args.fixed_face) == "string" then
        args.fixed_face = Font:getFace(args.fixed_face)
    end

    if not args.low_height then
        local text_padding_left_right = args.text_padding_left_right
        local use_wide_description_dialog = false
        if use_wide_description_dialog and args.for_description_dialog then
            args.width_factor = args.for_description_dialog and 0.99 or 0.98
            text_padding_left_right = KOR.screenhelpers:isLandscapeScreen() and Screen:scaleBySize(105) or Screen:scaleBySize(35)
        elseif args.narrow_text_window or args.for_description_dialog then
            args.width_factor = KOR.screenhelpers:isLandscapeScreen() and 0.87 or 0.95
            text_padding_left_right = Screen:scaleBySize(35)
        elseif args.fullscreen then
            --* to hide the borders:
            local overflow = 10
            args.height = Screen:getHeight() + overflow
            args.width = Screen:getWidth() + overflow
            text_padding_left_right = Screen:scaleBySize(35)
            args.border = 0
            args.width_factor = 1
            args.use_computed_height = false
        else
            args.height = org_height or math.floor(Screen:getHeight() * 0.8)
            args.use_computed_height = args.use_computed_height or false
            args.text_padding_left_right = text_padding_left_right
        end
    end

    --* optionally search for a externally transmitted search string:
    local external_search_string = KOR.registry:getOnce("textviewer_needle")
    if external_search_string then
        args.title = args.title .. " - zoek: " .. external_search_string
    end

    local config = args
    if args.no_fullscreen then
        config.fullscreen = false
    end
    --* you can optionally add a buttons_table setting:
    local textviewer
    textviewer = TextViewer:new(config)
    UIManager:show(textviewer)

    --* because textBoxTabbed already registered in its own method:
    if not args.tabs then
        self:registerWidget(textviewer)
    end

    -- #((send external searchstring for xray info))
    if external_search_string then
        textviewer:findCallback(nil, external_search_string)
    end

    --* return the instance, so we can close it
    --* from a custom button table:
    return textviewer
end

--* see ((DIALOGS))
--* compare ((htmlBoxTabbed)):
function Dialogs:textBoxTabbed(active_tab, args)
    if self.tabbed_textbox then
        UIManager:close(self.tabbed_textbox)
    end

    KOR.tabfactory:setTabButtonAndContent(self, "textBoxTabbed", active_tab, args)

    self.tabbed_textbox = self:textBox(args)
    self:registerWidget(self.tabbed_textbox)

    return self.tabbed_textbox
end

function Dialogs:showButtonDialog(title, button_table)
    local dialog
    dialog = ButtonDialogTitle:new{
        title = title,
        no_overlay = true,
        modal = true,
        move_to_top = true,
        use_low_title = true,
        button_font_face = "x_smallinfofont",
        button_font_size = 14,
        button_font_bold = false,
        button_font_weight = "normal",
        title_align = "center",
        width_factor = 0.95,
        button_width = 0.33,
        show_parent = KOR.ui,
        buttons = button_table,
        after_close_callback = function()
            KOR.registry:unset("xray_toc_dialog_shown")
        end
    }
    UIManager:show(dialog)
    --KOR.registryset("TextViewer_index", dialog)
    return dialog
end

--* see ((DIALOGS))
--- this alert looks very pretty, has a titlebar and optionally buttons at the bottom
--* compare ((Dialogs#htmlBox)) for html message windows:
--! buttons use UIManager:close(dialog) for closing niceAlert instance, so dialog must always be set here, returned and handled in calling context!
function Dialogs:niceAlert(title, info, options)
    if not options then
        options = {}
    end
    local buttons = options.buttons
    local width = options.width
    local delay = options.delay
    local no_white_space_prefix = options.no_white_space_prefix
    --[[
    --* example call:
    local dialog
    --* define buttons, which also call UIManager:close(dialog)
    dialog = KOR.dialogs:niceAlert(title, info, {
        buttons = buttons,
    })
    ]]
    if not title then
        title = "Ter informatie"
    end
    local prefix = no_white_space_prefix and "" or "\n"
    local dialog
    dialog = KOR.nicealert:new{
        info_text = prefix .. info .. "\n",
        mono_face = options.mono_face,
        info_buttons = buttons,
        title = title,
        called_externally = true,
        width = width,
        ui = KOR.ui,
        show_parent = KOR.ui,
    }
    UIManager:show(dialog)
    if delay then
        UIManager:scheduleIn(delay + 1, function()
            UIManager:close(dialog)
        end)
        return nil
    end
    return dialog
end

--* use timeout = nil for second argument when calling for no timeout:
--* pos can be set by ((Button#onTapSelectButton)):
function Dialogs:alertInfo(message, timeout, dismiss_callback, pos)
    KOR.messages:cancelPatience()

    local use_nice_alert = false
    if use_nice_alert then
        local dialog = self:niceAlert("info", message)
        if timeout then
            UIManager:scheduleIn(timeout, function()
                UIManager:close(dialog)
            end)
        end
        return dialog
    end

    local y_pos
    if pos and pos.pos then
        y_pos = pos.pos.y + 24
    end
    local config = { text = message, timeout = timeout, dismiss_callback = dismiss_callback, move_to_y_pos = y_pos }
    local instance = InfoMessage:new(config)
    UIManager:show(instance)
    return instance
end

return Dialogs
