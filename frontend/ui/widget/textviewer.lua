--[[--
Displays some text in a scrollable view.

@usage
    local textviewer = TextViewer:new{
        title = _("I can scroll!"),
        text = _("I'll need to be longer than this example to scroll."),
    }
    UIManager:show(textviewer)
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local ButtonTableGenerators = require("extensions/buttontablegenerators")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Clipboard = require("extensions/clipboard")
local Colors = require("extensions/colors")
local Device = require("device")
-- ! use KOR.dialogs instead of Dialogs!
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Icons = require("extensions/icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local Messages = require("extensions/messages")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Registry = require("extensions/registry")
local ScreenHelpers = require("extensions/screenhelpers")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
-- ! use KOR.xrayhelpers instead of XrayHelpers!
local T = require("ffi/util").template
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local SCROLLING_SET_SCROLLBAR_DYNAMICALLY = 1
local SCROLLING_FORCE_SCROLLBAR = 2
local SCROLLING_FIXED_HEIGHT_WITHOUT_SCROLLBAR = 3

--- @class TextViewer
local TextViewer = InputContainer:extend{
    dialogs = nil,
    title = nil,
    text = nil,
    width = nil,
    width_factor = 1,
    height = nil,
    buttons_table = nil,
    -- See TextBoxWidget for details about these options
    -- We default to justified and auto_para_direction to adapt
    -- to any kind of text we are given (book descriptions,
    -- bookmarks' text, translation results...).
    -- When used to display more technical text (HTML, CSS,
    -- application logs...), it's best to reset them to false.
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = true,
    alignment_strict = false,

    next_item_callback = nil,
    prev_item_callback = nil,
    event_after_close = nil,

    title_face = Font:getFace("x_smalltfont"),
    title_multilines = nil, -- see TitleBar for details
    title_shrink_font_to_fit = nil, -- see TitleBar for details
    fixed_face = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    text_padding = Size.padding.large,
    text_padding_top_bottom = nil,
    text_padding_left_right = nil,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
    button_font_face = "cfont",
    button_font_size = 20,
    button_font_weight = "bold",

    -- Optional callback called on CloseWidget, set by the widget which showed us (e.g., to request a full-screen refresh)
    close_callback = nil,
    default_hold_callback = nil, -- on each default button
    find_centered_lines_count = 5, -- line with find results to be not far from the center

    -- added by SmartScripts:
    active_paragraph = nil,
    active_tab = nil,
    -- Bottom row with Close, Find buttons. Also added when no caller's buttons defined.
    add_default_buttons = nil,
    add_fullscreen_padding = false,
    -- when true, white border margins around dialog borders:
    add_margin = false,
    add_more_padding = false,
    add_padding = false,
    after_load_callback = nil,
    block_height_adaptation = false,
    covers_fullscreen = false,
    dont_pause_stats = false,
    fullscreen = false,
    extra_button = nil,
    extra_button_position = nil,
    extra_button2 = nil,
    extra_button2_position = nil,
    extra_button3 = nil,
    extra_button3_position = nil,
    full_height = false,
    fullscreen_padding = nil,
    no_overlay = false,
    overflow_correction = nil,
    overlay = nil,
    -- only upon tap-close will TextViewer close the overlay:
    overlay_managed_by_parent = false,
    paragraph_headings = nil,
    separator = nil,
    tabs_table_buttons = nil,
    title_alignment = "left",
    -- e.g. populated in ((Xray-item edit dialog: tab buttons in TitleBar)):
    title_tab_buttons = nil,
    -- title_tab_callbacks for title_tab_buttons, e.g. populated in ((XrayItems#getTabCallback)):
    title_tab_callbacks = nil,
    -- optional icon buttons at left and right side of TitleBar, e.g. defined in ((XrayHelpers#showXrayItemsInfo)):
    top_buttons_left = nil,
    top_buttons_right = nil,
    use_computed_height = false,
    use_low_height = false,
    use_scrolling_dialog = SCROLLING_SET_SCROLLBAR_DYNAMICALLY,

    -- when true, make sure a textviewer window is displayed above all other widgets, even with visible keyboard in dialogs:
    modal = false,
}

--- @class TextViewerInit
function TextViewer:init()
    self:setPadding()
    self:initForDevice()
    self:initTitleBar()
    self:initScrollCallbacks()
    self:setSeparator()
    self:initButtons()
    self:setFaceWidthLineHeight()
    self:initSpacers()
    self:computeHeights()

    self:initTextWidget()
    self:initWidgetFrame()

    -- will optionally restart ((TextViewer#init)) with new parameters:
    if self:applyOverflowCorrections() then
        return
    end
    self:finalizeWidget()
end

function TextViewer:onCloseWidget()
    if self.overlay then
        UIManager:close(self.overlay)
        self.overlay = nil
    end
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function TextViewer:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    return true
end

function TextViewer:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
    	self.garbage = arg
        KOR.dialogs:closeOverlay()
        self:onClose()
        self:triggerAfterCloseEvent()
        return true
    end
    -- Allow for changing item with tap (tap event will be first
    -- processed for scrolling definition by ScrollTextWidget, which
    -- will pop it up for us here when it can't scroll anymore).
    -- This allow for continuous reading of results' definitions with tap.
    if BD.flipIfMirroredUILayout(ges_ev.pos.x < Screen:getWidth() / 2) then
        self:onReadPrevItem()
    else
        self:onReadNextItem()
    end
    return true
end

function TextViewer:onClose()
    UIManager:close(self)
    return true
end

function TextViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            if self.next_item_callback then
                self:next_item_callback()
            else
            self.scroll_text_w:scrollText(1)
            end
            return true
        elseif direction == "east" then
            if self.prev_item_callback then
                self:prev_item_callback()
            else
            self.scroll_text_w:scrollText(-1)
            end
            return true
        else
            KOR.dialogs:closeOverlay()
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
    end
    -- Let our MovableContainer handle swipe outside of text
    return self.movable:onMovableSwipe(arg, ges)
end

-- The following handlers are similar to the ones in DictQuickLookup:
-- we just forward to our MoveableContainer the events that our
-- TextBoxWidget has not handled with text selection.
function TextViewer:onHoldStartText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function TextViewer:onHoldPanText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    -- We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function TextViewer:onHoldReleaseText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

-- These 3 event processors are just used to forward these events
-- to our MovableContainer, under certain conditions, to avoid
-- unwanted moves of the window while we are selecting text in
-- the definition widget.
function TextViewer:onForwardingTouch(arg, ges)
    -- This Touch may be used as the Hold we don't get (for example,
    -- when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.textw.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        -- Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function TextViewer:onForwardingPan(arg, ges)
    -- We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function TextViewer:onForwardingPanRelease(arg, ges)
    -- We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end


function TextViewer:findDialog()
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        input = self.search_value,
        buttons = {
            {
                {
                    icon = "back",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = Icons.first_bare,
                    callback = function()
                        self._find_next = false
                        self:findCallback(input_dialog)
                    end,
                },
                {
                    text = Icons.next_bare,
                    is_enter_default = true,
                    callback = function()
                        self._find_next = true
                        self:findCallback(input_dialog)
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
    input_dialog:onShowKeyboard(true)
end

-- when argument external_search_string not nil: called via ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) > ((XrayHelpers#generateParagraphInformation)) >
-- click on line with xray marker > ((XrayHelpers#showXrayItemsInfo)) - here match reliability icons and xray type icons injected for buttons > ((Dialogs#textBox)) > ((send external searchstring for xray info)) > ((TextViewer#showToc)) > ((TextViewer#getTocButton)) >
-- click on button > ((TextViewer#blockUp)) or ((TextViewer#blockDown)):
function TextViewer:findCallback(input_dialog, external_search_string, overrule_pos)
    if input_dialog then
        self.search_value = input_dialog:getInputText()
        if self.search_value == "" then return end
        UIManager:close(input_dialog)
    elseif external_search_string then
        self.search_value = KOR.xrayhelpers:removeHitReliabilityIcons(external_search_string)
        self._find_next = false
    end
    local start_pos = 1
    if self._find_next then
        local charpos, new_virtual_line_num = self.scroll_text_w:getCharPos()
        if math.abs(new_virtual_line_num - self._old_virtual_line_num) > self.find_centered_lines_count then
            start_pos = self.scroll_text_w:getCharPosAtXY(0, 0) -- first char of the top line
        elseif external_search_string then
            start_pos = 1
        else
            start_pos = (charpos or 0) + 1 -- previous search result
        end
    elseif overrule_pos then
        start_pos = overrule_pos
    end
    local char_pos = util.stringSearch(self.text, self.search_value, self.case_sensitive, start_pos)
    local msg
    if char_pos > 0 then
        self.scroll_text_w:moveCursorToCharPos(char_pos, self.find_centered_lines_count)
        --msg = T(_("Found, screen line %1."), self.scroll_text_w:getCharPosLineNum())
        self._find_next = true
        self._old_virtual_line_num = select(2, self.scroll_text_w:getCharPos())
    else
        msg = "zoekterm niet meer gevonden"
        self._find_next = false
        self._old_virtual_line_num = 1
    end
    if msg then
        Messages:notify(msg)
    end
    if self._find_next_button ~= self._find_next then
        self._find_next_button = self._find_next
        local find_button = self.button_table:getButtonById("find")
        --find_button:setText(button_text, find_button.width)
        find_button:setIcon("appbar.search", find_button.width)
        find_button:refresh()
    end
end

function TextViewer:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
    if self.text_selection_callback then
        self.text_selection_callback(text, hold_duration, start_idx, end_idx, to_source_index_func)
        return
    end
    if Device:hasClipboard() then
        Device.input.setClipboardText(text)
        local msg = start_idx == end_idx and _("Word copied to clipboard.")
        or _("Selection copied to clipboard.")
        Messages:notify(msg)
    end
end

-- Register DocumentRegistry auxiliary provider.
function TextViewer:register(registry)
    registry:addAuxProvider({
        provider_name = _("Text viewer"),
        provider = "textviewer",
        order = 20, -- order in OpenWith dialog
        enabled_func = function()
            return true -- all files
        end,
        callback = TextViewer.openFile,
        disable_file = true,
        disable_type = false,
    })
end

function TextViewer.openFile(file)
    local function _openFile(file_path)
        local file_handle = io.open(file_path, "rb")
        if not file_handle then return end
        local file_content = file_handle:read("*all")
        file_handle:close()
        UIManager:show(TextViewer:new{
            title = file_path,
            title_multilines = true,
            text = file_content,
            text_type = "file_content",
        })
    end
    local attr = lfs.attributes(file)
    if attr then
        if attr.size > 400000 then
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = T(_("This file is %2:\n\n%1\n\nAre you sure you want to open it?\n\nOpening big files may take some time."),
                        BD.filepath(file), util.getFriendlySize(attr.size)),
                ok_text = _("Open"),
                ok_callback = function()
                    _openFile(file)
                end,
            })
        else
            _openFile(file)
        end
    end
end

-- ========================= ADDED =========================

function TextViewer:onReadNextItem()
    if self.next_item_callback then
        self:next_item_callback()
    end
    return true
end

function TextViewer:onReadPrevItem()
    if self.prev_item_callback then
        self:prev_item_callback()
    end
    return true
end

function TextViewer:onAnyKeyPressed()
    UIManager:close(self)
    ScreenHelpers:refreshScreen()
    return true
end

function TextViewer:triggerAfterCloseEvent()
    if self.event_after_close then
        local ui = Registry:getUI()
        ui:handleEvent(Event:new(self.event_after_close))
    end
end

function TextViewer:applyOverflowCorrections()
    if self.fullscreen then
        return false
    end
    if not self.overflow_correction then

        local end_height = self.frame:getSize().h
        -- reduce height when overflowing screen edges:
        if end_height > self.screen_height then
            self.overflow_correction = self.screen_height - end_height
            self:init()
            return true
            -- if possible add extra height, if there's still a scrollbar visible:

        -- screen height for Kobo Forma = 1440:
        elseif Registry:get("has_scrollbar") and end_height < self.screen_height then
            local correction = 150
            local difference = self.screen_height - end_height
            if difference < correction then
                self.overflow_correction = difference
            else
                self.overflow_correction = correction
            end
            self:init()
            return true
        end
    end

    return false
end

function TextViewer:initTextWidget()
    local height = not self.text_padding_top_bottom and self.textw_height - 2 * self.text_padding - 2 * self.text_margin or self.textw_height - 2 * self.text_padding_top_bottom - 2 * self.text_margin

    if self.fullscreen_padding then
        self.computed_width = self.computed_width - 2 * self.fullscreen_padding
    end
    local padding_right = self.fullscreen and 40 or 0
    if self.block_height_adaptation or self.use_low_height or self.use_scrolling_dialog ~= SCROLLING_FIXED_HEIGHT_WITHOUT_SCROLLBAR then
        self.scroll_text_w = ScrollTextWidget:new{
            text = self.text,
            face = self.face,
            line_height = self.line_height,
            width = self.computed_width,
            height = height,
            dialog = self,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
            padding_right = padding_right,
            -- to make the scrollbar lighter for fullscreen ScrollTextWidgets:
            fullscreen = self.fullscreen,
        }

    -- show non scrollable text:
    else
        self.scroll_text_w = TextBoxWidget:new{
            text = self.text,
            face = self.face,
            line_height = self.line_height,
            width = self.computed_width,
            height = height,
            dialog = self,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
        }
    end
    self.textw = not self.text_padding_top_bottom and
    FrameContainer:new{
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w
    }
    or
    FrameContainer:new{
        padding_left = self.text_padding,
        padding_right = self.text_padding,
        padding_top = self.text_padding_top_bottom,
        padding_bottom = self.text_padding_top_bottom - 10,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w
    }
end

function TextViewer:getContextCss()
    -- Using Noto Sans because Nimbus doesn't contain the IPA symbols.
    -- 'line-height: 1.3' to have it similar to textboxwidget,
    -- and follow user's choice on justification
    local css = [[
        @page {
            margin: 0;
            font-family: 'Noto Sans';
        }

        body {
            margin: 0;
            line-height: 1.3;
        }

        blockquote, dd {
            margin: 0 1em;
        }

        ol, ul, menu {
            margin: 0; padding: 0 1.7em;
        }
    ]]
    -- For reference, MuPDF declarations with absolute units:
    --  "blockquote{margin:1em 40px}"
    --  "dd{margin:0 0 0 40px}"
    --  "ol,ul,menu {margin:1em 0;padding:0 0 0 30pt}"
    --  "hr{border-width:1px;}"
    --  "td,th{padding:1px}"
    --
    -- MuPDF doesn't currently scale CSS pixels, so we have to use a font-size based measurement.
    -- Unfortunately MuPDF doesn't properly support `rem` either, which it bases on a hard-coded
    -- value of `16px`, so we have to go with `em` (or `%`).
    --
    -- These `em`-based margins can vary slightly, but it's the best available compromise.
    --
    -- We also keep left and right margin the same so it'll display as expected in RTL.
    -- Because MuPDF doesn't currently support `margin-start`, this results in a slightly
    -- unconventional but hopefully barely noticeable right margin for <dd>.
    --
    -- For <ul> and <ol>, bullets and numbers are displayed in the margin/padding, so
    -- we need a bit more for them to not get truncated (1.7em allows for 2 digits list
    -- item numbers). Unfortunately, because we want this also for RTL, this space is
    -- wasted on the other side...

    if self.css then
        return css .. self.css
    end
    return css
end

function TextViewer:blockDown()
    if not self.active_paragraph then
        self.active_paragraph = 1
    else
        self.active_paragraph = self.active_paragraph + 1
        if self.active_paragraph > #self.paragraph_headings then
            self.active_paragraph = 1
        end
    end

    -- to make the entire last paragraph visbile:
    if self.active_paragraph == #self.paragraph_headings then
        self.scroll_text_w:scrollToTop()
        self:blockUp("force_active_paragraph")
        return
    end

    -- the paragraph headings were generated in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) >  > ((headings for use in TextViewer)):
    local start_pos = 1
    if self.active_paragraph > 1 then
        for i = 1, self.active_paragraph - 1 do
            start_pos = start_pos + self.paragraph_headings[i].length - 20
        end
    end
    -- these needles were defined in ((headings for use in TextViewer)):
    local needle = self.paragraph_headings[self.active_paragraph].needle
    self:findCallback(nil, needle, start_pos)
end

function TextViewer:blockUp(force_active_paragraph)
    if not force_active_paragraph then
        if not self.active_paragraph then
            self.active_paragraph = 1
        else
            self.active_paragraph = self.active_paragraph - 1
            if self.active_paragraph < 1 then
                self.active_paragraph = #self.paragraph_headings
            end
        end
    end

    -- the paragraph headings were generated in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) > ((headings for use in TextViewer)):
    local start_pos = 1
    if self.active_paragraph > 1 then
        for i = 1, self.active_paragraph - 1 do
            start_pos = start_pos + self.paragraph_headings[i].length - 20
        end
    end
    local needle = self.paragraph_headings[self.active_paragraph].needle
    self:findCallback(nil, needle, start_pos)
end

function TextViewer:computeHeights()
    local textw_height
    local button_table_height = self.button_table:getSize().h
    if self.tabs_table_buttons then
        self:generateTabsTable()
    end
    local tabs_table_height = self.tabs_table_buttons and self.tabs_table:getSize().h or 0
    local separator_height = self.separator:getSize().h
    local available_height = self.screen_height - button_table_height - separator_height - tabs_table_height
    local title_height = self.titlebar:getSize().h
    if self.title ~= "dummy" then
        available_height = available_height - title_height
    end

    if self.text_padding_top_bottom then
        available_height = available_height - (2 * self.text_padding_top_bottom)
    end
    if self.add_margin then
        available_height = available_height - (2 * Size.margin.default)
    end
    if self.text_margin then
        available_height = available_height - (2 * self.text_margin)
    end
    if self.text_padding then
        available_height = available_height - (2 * self.text_padding)
    end

    -- compute auto height for textbox:
    local computed_height = self.height
    local correction_start = 4
    local correction_end = 7
    if ScreenHelpers:isPortraitScreen() then
        correction_start = 6
        correction_end = 9
    end

    -- For correct showing of contents of Description dialog; %p stands for punctuation:
    self.text = self.text:gsub("([%pa-z ]\n)BESCHRIJVING", "%1\nBESCHRIJVING")

    if self.use_computed_height then

        local compare_widget = ScrollTextWidget:new{
            text = self.text,
            face = self.face,
            width = self.computed_width,
            height = self.height,
            dialog = self,
            line_height = self.line_height,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            for_measurement_only = true,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
        }
        computed_height = compare_widget:getSize().h
        compare_widget:free()

        local has_scrollbar = Registry:get("has_scrollbar")
        local increase_height = has_scrollbar or false
        if has_scrollbar and computed_height > available_height then
            increase_height = false
        end
        local step = 20
        for i = 1, 40 do
            -- check whether increasing the height in steps solves the problem:
            if increase_height then
                computed_height = self.height + i * step
                if computed_height > available_height then
                    computed_height = self.height + ((i - 1) * step)
                    break
                end
                --decreasing height:
            else
                computed_height = self.height - (i * step)
            end

            compare_widget = ScrollTextWidget:new{
                text = self.text,
                face = self.face,
                width = self.computed_width,
                height = computed_height,
                dialog = self,
                line_height = self.line_height,
                alignment = self.alignment,
                justified = self.justified,
                lang = self.lang,
                for_measurement_only = true,
                para_direction_rtl = self.para_direction_rtl,
                auto_para_direction = self.auto_para_direction,
                alignment_strict = self.alignment_strict,
            }
            computed_height = compare_widget:getSize().h
            compare_widget:free()

            has_scrollbar = Registry:get("has_scrollbar")
            if increase_height then
                if computed_height > available_height then
                    computed_height = computed_height - step
                    if computed_height > available_height - 10 then
                        computed_height = available_height - 10
                    end
                    break
                elseif not has_scrollbar then
                    local extra_height
                    local height_basis = computed_height
                    for e = correction_start, correction_end do
                        extra_height = height_basis + e * step
                        if extra_height < available_height - 10 then
                            computed_height = extra_height
                        end
                    end
                    break
                end

                -- when we reach situation WITH scrollbar after decreasing height:
            elseif has_scrollbar then
                computed_height = computed_height + step
                if computed_height > available_height - 10 then
                    computed_height = available_height - 10
                else
                    local height_basis = computed_height
                    local extra_height
                    for e = correction_start, correction_end do
                        extra_height = height_basis + e * step
                        if extra_height < available_height - 10 then
                            computed_height = extra_height
                        end
                    end
                end
                break
            end
        end
        compare_widget = nil
    end

    if self.use_computed_height then
        textw_height = self.overflow_correction and computed_height + self.overflow_correction or computed_height - self.top_spacer_height

    elseif self.title ~= "dummy" then

        -- self.height in init() set to this:
        -- self.height = self.height or Screen:getHeight() - Screen:scaleBySize(30)

        textw_height = self.height - separator_height - button_table_height - title_height - tabs_table_height - self.top_spacer_height
    else
        textw_height = self.height - separator_height - button_table_height - tabs_table_height - self.top_spacer_height
    end

    self.textw_height = textw_height
    self.tabs_table_height = tabs_table_height
    self.button_table_height = button_table_height
end

function TextViewer:generateTabsTable()
    for i, button in ipairs(self.tabs_table_buttons[1]) do
        if i == self.active_tab then
            if not button.text:match(Icons.active_tab_minimal_bare) then
                button.text = Icons.active_tab_minimal_bare .. " " .. button.text
            end
        end
    end
    self.tabs_table = ButtonTable:new{
        width = self.width,
        buttons = self.tabs_table_buttons,
        button_font_face = "cfont",
        button_font_size = 13,
        button_font_weight = "normal",
        decrease_top_padding = 5,
        padding = 1,
        show_parent = self,
    }
end

-- called from ((XrayHelpers#showXrayItemsInfo)) - see ((call TextViewer TOC)) - or from a callback:
function TextViewer:showToc(called_from_button)

    local button_table, buttons_count = ButtonTableGenerators:getVerticallyArrangedButtonTable(
    -- self.paragraph_headings were generated in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)):
        self.paragraph_headings,
        called_from_button,
        function(i)
            return self:getTocButton(i)
        end,
            {
                icon = "info",
                icon_size_ratio = 0.5,
                callback = function()
                    local message = KOR.xrayhelpers:getXrayHitsReliabilityExplanation()
                    KOR.dialogs:alertInfo("\n" .. message .. "\n")
                end
            },
    {
            text = Icons.back_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            callback = function()
                UIManager:close(self.toc_dialog)
                UIManager:close(self)
            end
        }
    )

    local xray_info_mode = G_reader_settings:readSetting("xray_info_mode") or "paragraph"
    local title = xray_info_mode == "paragraph" and "Xray items in deze alinea" or "Xray items op deze pagina"
    -- see((MOVE MOVABLES TO Y POSITION)) for more info how this toc will be moved to the top of the screen:
    self.toc_dialog = KOR.dialogs:showButtonDialog(buttons_count .. " " .. title, button_table, "no_overlay", self)
end

function TextViewer:setConfigForContainersWithTitlebar(radius, padding)

    local text_section = not self.block_height_adaptation and not self.use_low_height and self.use_scrolling_dialog > 1 and CenterContainer:new{
        dimen = Geom:new{
            w = self.frame_width,
            h = self.textw:getSize().h,
        },
        HorizontalGroup:new{
            self.padding_span,
            self.textw,
            self.padding_span,
        }
    }
    or
    CenterContainer:new{
        dimen = Geom:new{
            w = self.frame_width,
            h = self.textw:getSize().h,
        },
        self.textw,
    }

    return self.tabs_table and
    {
        radius = radius,
        padding = padding,
        margin = self.add_margin and Size.margin.default or 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.titlebar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.frame_width,
                    h = self.tabs_table_height,
                },
                self.tabs_table,
            },
            self.separator,
            self.top_spacer,
            text_section,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.frame_width,
                    h = self.button_table_height,
                },
                self.button_table,
            }
        }
    }
    or
    {
        radius = radius,
        padding = padding,
        margin = self.add_margin and Size.margin.default or 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.titlebar,
            self.top_spacer,
            text_section,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.frame_width,
                    h = self.button_table_height,
                },
                self.button_table,
            }
        }
    }
end

function TextViewer:setConfigForContainersWithoutTitlebar(radius, padding)
    return self.tabs_table and
    {
        radius = radius,
        padding = padding,
        margin = self.add_margin and Size.margin.default or 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.frame_width,
                    h = self.tabs_table_height,
                },
                self.tabs_table,
            },
            self.separator,
            self.top_spacer,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.button_table_height,
                },
                self.button_table,
            }
        }
    }
    or
    {
        radius = radius,
        padding = padding,
        margin = self.add_margin and Size.margin.default or 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.top_spacer,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.button_table_height,
                },
                self.button_table,
            }
        }
    }
end

function TextViewer:getDefaultButtons()
    local default_buttons = {
        {
            icon = "appbar.search",
            icon_size_ratio = 0.6,
            id = "find",
            callback = function()
                if self._find_next then
                    self:findCallback()
                else
                    self:findDialog()
                end
            end,
            hold_callback = function()
                if self._find_next then
                    self:findDialog()
                else
                    if self.default_hold_callback then
                        self.default_hold_callback()
                    end
                end
            end,
        },
        {
            text = Icons.copy_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            callback = function()
                self:onClose()
                --ScreenHelpers:refreshScreen()
                Clipboard:copy(self.text)
                KOR.dialogs:notify("tekst naar klembord gekopieerd...")
            end,
            hold_callback = function()
                KOR.dialogs:alertInfo("Copy text in the viewer to clipboard.")
            end,
        },
        {
            text = Icons.back_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            text = "⇱",
            id = "top",
            callback = function()
                if self.paragraph_headings then
                    self.active_paragraph = nil
                end
                self.scroll_text_w:scrollToTop()
            end,
            hold_callback = self.default_hold_callback,
        },
        {
            text = Icons.back_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            text = "⇲",
            id = "bottom",
            callback = function()
                if self.paragraph_headings then
                    self.active_paragraph = #self.paragraph_headings
                end
                self.scroll_text_w:scrollToBottom()
            end,
            hold_callback = self.default_hold_callback,
        },
        {
            text = Icons.back_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            callback = function()
                self:onClose()
                --ScreenHelpers:refreshScreen()
            end,
            hold_callback = self.default_hold_callback,
        },
    }
    if self.paragraph_headings then
        -- #((TextViewer toc button))
        -- the items for this and the next two buttons were generated in ((XrayHelpers#ReaderHighlightGenerateXrayInformation)) > ((headings for use in TextViewer)):
        -- info: compare the buttons for Xray items list as injected in ((inject xray list buttons)):
        table.insert(default_buttons, 1, {
            text = Icons.list_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            callback = function()
                self:showToc("called_from_button")
            end,
            hold_callback = function()
                KOR.dialogs:alertInfo("Show toc of xray items in current page or in current paragraph.")
            end,
        })
        table.insert(default_buttons, 2, {
            id = "previ",
            icon = Icons.previous_bare,
            fgcolor = Colors.lighter_text,
            font_bold = false,
            callback = function()
                self:blockUp()
            end,
            hold_callback = function()
                KOR.dialogs:alertInfo("Goto previous or last item in toc.")
            end,
        })
        table.insert(default_buttons, 3, {
            fgcolor = Colors.lighter_text,
            font_bold = false,
            id = "nexti",
            callback = function()
                self:blockDown()
            end,
            hold_callback = function()
                KOR.dialogs:alertInfo("Goto next or first item in toc.")
            end,
        })
    end

    return default_buttons
end

function TextViewer:finalizeWidget()
    self.overflow_correction = nil
    self.movable = MovableContainer:new{
        -- We'll handle these events ourselves, and call appropriate
        -- MovableContainer's methods when we didn't process the event
        ignore_events = {
            -- These have effects over the text widget, and may
            -- or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            -- These do not have direct effect over the text widget,
            -- but may happen while selecting text: we need to check
            -- a few things before forwarding them
            "touch", "pan", "pan_release",
        },
        self.frame,
    }
    if not self.no_overlay and not self.fullscreen then
        self.overlay = KOR.dialogs:showOverlay()
    end
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)

    -- e.g. defined in ((xray paragraph info: after load callback)):
    -- #((TextViewer execute after load callback))
    if self.after_load_callback then
        UIManager:nextTick(function()
            self.after_load_callback(self)
        end)
    end
end

function TextViewer:initButtons()
    local default_buttons = self:getDefaultButtons()

    local buttons = self.buttons_table or {}
    if self.add_default_buttons or not self.buttons_table then
        -- ! hotfix to prevent double addition of default buttons row:
        local last_row = self.buttons_table and self.buttons_table[#self.buttons_table] or nil
        if not last_row or not last_row[1] or (last_row[1].icon ~= "appbar.search" and last_row[1].text ~= _("Find")) then
            table.insert(buttons, default_buttons)
        end
    end
    if self.extra_button then
        local position = self.extra_button_position or #buttons[1]
        table.insert(buttons[1], position, self.extra_button)
    end
    if self.extra_button2 then
        local position = self.extra_button2_position or #buttons[1]
        table.insert(buttons[1], position, self.extra_button2)
    end
    if self.extra_button3 then
        local position = self.extra_button3_position or #buttons[1]
        table.insert(buttons[1], position, self.extra_button3)
    end
    if self.extra_button_rows then
        for i = 1, #self.extra_button_rows do
            table.insert(buttons, self.extra_button_rows[i])
        end
    end
    self.button_table = ButtonTable:new{
        width = self.frame_width - 2 * self.button_padding,
        button_font_face = self.button_font_face,
        button_font_size = self.button_font_size,
        button_font_weight = self.button_font_weight,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
end

function TextViewer:setFaceWidthLineHeight()
    local face
    local line_height = Registry.line_height
    local factor = 2
    local width = not self.text_padding_left_right and self.width - factor * self.text_padding - factor * self.text_margin or self.width - factor * self.text_padding_left_right - factor * self.text_margin
    self.text_padding_top_bottom = Screen:scaleBySize(10)

    if not self.block_height_adaptation and not self.use_low_height and self.use_scrolling_dialog == SCROLLING_FIXED_HEIGHT_WITHOUT_SCROLLBAR then
        self.use_computed_height = false

        self.height = self.screen_height - Screen:scaleBySize(10)

        self.text_padding = Screen:scaleBySize(50)

        face = self.fixed_face or Font:getFace("x_smallinfofont")

        factor = 0.5
        width = not self.text_padding_left_right and self.width - factor * self.text_padding - factor * self.text_margin or self.width - factor * self.text_padding_left_right - factor * self.text_margin

    elseif not self.block_height_adaptation and not self.use_low_height and self.use_scrolling_dialog == SCROLLING_FORCE_SCROLLBAR then
        self.use_computed_height = false

        self.height = self.screen_height - Screen:scaleBySize(10)

        self.text_padding = Screen:scaleBySize(50)

        face = self.fixed_face or Font:getFace("x_smallinfofont")
        line_height = Registry.line_height

        factor = 0.5
        width = not self.text_padding_left_right and self.width - factor * self.text_padding - factor * self.text_margin or self.width - factor * self.text_padding_left_right - factor * self.text_margin

    elseif self.fixed_face then
        face = self.fixed_face
        line_height = Registry.line_height
    else
        face, line_height = Font:setFontByTextLength(self.text)
    end

    self.face = face
    self.computed_width = width
    self.line_height = line_height
end

function TextViewer:initWidgetFrame()
    local radius = self.fullscreen and 0 or Size.radius.window
    local padding = self.add_padding and Size.padding.default or 0
    if self.add_more_padding then
        padding = Size.padding.fullscreen
    end
    local config
    if self.title ~= "dummy" then
        config = self:setConfigForContainersWithTitlebar(radius, padding)

        -- no title, so don't use a separator for title:
    else
        config = self:setConfigForContainersWithoutTitlebar(radius, padding)
    end
    -- hide the border around fullscreen TextViewer dialogs:
    if self.fullscreen then
        config.bordersize = 0
        config.covers_fullscreen = self.covers_fullscreen
    end
    self.frame = FrameContainer:new(config)
end

function TextViewer:getTocButton(i)
    return {
        text = i .. ". " .. self.paragraph_headings[i].needle,
        font_bold = false,
        text_font_face = Font:getFace("x_smallinfofont"),
        font_size = 18,
        callback = function()
            -- if you want this to be closable, store the dialog in ((Dialogs#showButtonDialog)) in Registry and close it here...
            self.active_paragraph = i
            self.scroll_text_w:scrollToBottom()
            self:blockUp("force_active_paragraph")
        end,
        hold_callback = function()
            -- source: see ((headings for use in TextViewer)):
            -- paragraph headings were defined in((XrayHelpers#ReaderHighlightGenerateXrayInformation)):
            KOR.xrayitems:onEditXrayItem(self.paragraph_headings[i].xray_item)
        end,
    }
end

function TextViewer:getTopSpacer()
    local decrease_padding_factor = 0.4
    local top_spacer = self.fullscreen_padding and CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = math.floor(decrease_padding_factor * self.fullscreen_padding),
        },
        self.padding_span,
    }
    or
    CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = 0,
        },
        self.padding_span,
    }
    if not self.fullscreen_padding then
        return top_spacer, 0
    end

    return top_spacer, top_spacer:getSize().h
end

function TextViewer:initForDevice()
    self.side_padding = Screen:scaleBySize(20)
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()

    -- calculate window dimension
    self.align = "center"
    self.region = Geom:new{
        x = 0, y = 0,
        w = self.screen_width,
        h = self.screen_height,
    }
    self:setDialogWidthAndHeight()
    self:initTouch()
end

function TextViewer:initScrollCallbacks()
    -- Callback to enable/disable buttons, for at-top/at-bottom feedback
    local prev_at_top = false -- Buttons were created enabled
    local prev_at_bottom = false
    local function button_update(id, enable)
        local button = self.button_table:getButtonById(id)
        if button then
            if enable then
                button:enable()
            else
                button:disable()
            end
            button:refresh()
        end
    end
    self._buttons_scroll_callback = function(low, high)
        if prev_at_top and low > 0 then
            button_update("top", true)
            prev_at_top = false
        elseif not prev_at_top and low <= 0 then
            button_update("top", false)
            prev_at_top = true
        end
        if prev_at_bottom and high < 1 then
            button_update("bottom", true)
            prev_at_bottom = false
        elseif not prev_at_bottom and high >= 1 then
            button_update("bottom", false)
            prev_at_bottom = true
        end
    end
end

function TextViewer:initSpacers()
    self.padding_span = HorizontalSpan:new{ width = self.side_padding }
    self.top_spacer, self.top_spacer_height = self:getTopSpacer()
end

function TextViewer:initTitleBar()
    local tab_buttons
    if self.title_tab_buttons then
        tab_buttons = {}
        for i = 1, #self.title_tab_buttons do
            local text = self.title_tab_buttons[i]
            table.insert(tab_buttons, Button:new{
                text = text,
                callback = function()
                    self.title_tab_callbacks[i]()
                end,
                bordersize = 2,
                radius = Screen:scaleBySize(5), --Size.radius.window
                text_font_face = "smalltfont",
                text_font_size = 13,
                text_font_bold = false,
                padding_h = Size.padding.small,
                padding_v = 0,
                margin = 0,
            })
        end
    end

    -- #((TitleBar for TextViewer))
    -- compare ((TitleBar for Menu)), e.g. for Collections:
    local title_bar_config = {
        width = self.width,
        align = self.title_alignment,
        with_bottom_line = true,
        title = self.title,
        title_face = self.title_face,
        title_multilines = self.title_multilines,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        fullscreen = self.fullscreen,
        no_close_button_padding = true,
        close_callback = function()
            self:onClose()
        end,
        tab_buttons = tab_buttons,
        show_parent = self,
        top_buttons_left = self.top_buttons_left,
        top_buttons_right = self.top_buttons_right,
    }
    if self.tabs_table_buttons and self.fullscreen then
        title_bar_config.bottom_line_color = Colors.title_bar_bottom_line
        title_bar_config.bottom_line_thickness = Size.line.small
    end
    self.titlebar = TitleBar:new(title_bar_config)

    if not self.title then
        self.title = "dummy"
    end
end

function TextViewer:initTouch()
    self._find_next = false
    self._find_next_button = false
    self._old_virtual_line_num = 1

    if Device:hasKeys() then
        if self.active_tab and self.tabs_table_buttons then
            self.key_events = {
                ToPreviousTab = { { Input.group.PgBack }, doc = "naar vorige tab" },
                ToNextTab = { { Input.group.PgFwd }, doc = "naar volgende tab" },
                Close = { { "Back" }, doc = "close text viewer" }
            }
        else
            self.key_events = {
                ReadPrevItem = { { Input.group.PgBack }, doc = "read prev item" },
                ReadNextItem = { { Input.group.PgFwd }, doc = "read next item" },
                Close = { { "Back" }, doc = "close text viewer" }
            }
        end
    end

    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = range,
                },
            },
            MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = range,
                },
            },
            -- Allow selection of one or more words (see textboxwidget.lua):
            HoldStartText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldReleaseText = {
                GestureRange:new{
                    ges = "hold_release",
                    range = range,
                },
                -- callback function when HoldReleaseText is handled as args
                args = function(text, hold_duration, start_idx, end_idx, to_source_index_func)
                    self:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end
end

-- add support for navigating to next tab with hardware keys:
function TextViewer:onToNextTab()
    self.active_tab = self.active_tab - 1
    if self.active_tab < 1 then
        self.active_tab = #self.tabs_table_buttons[1]
    end
    self.tabs_table_buttons[1][self.active_tab]:callback()
end

-- add support for navigating to previous tab with hardware keys:
function TextViewer:onToPreviousTab()
    self.active_tab = self.active_tab + 1
    if self.active_tab > #self.tabs_table_buttons[1] then
        self.active_tab = 1
    end
    self.tabs_table_buttons[1][self.active_tab]:callback()
end

function TextViewer:setDialogWidthAndHeight()
    local default_width = self.screen_width - Screen:scaleBySize(30)
    if self.fullscreen or self.full_height then
        if self.fullscreen then
            self.width = self.screen_width
        else
            self.width = self.width or default_width
            self.width = self.width_factor * self.width
        end
        if self.add_fullscreen_padding then
            self.fullscreen_padding = Screen:scaleBySize(80)
        end
        -- extra 6 pixels to hide borders:
        self.height = self.screen_height + 6
        self.block_height_adaptation = true
        self.use_low_height = false
        self.add_margin = false
        if self.fullscreen then
            self.covers_fullscreen = true
            -- set a block against showing the footer:
            Registry:set("fullscreen_dialog_active", true)
        end
    else
        self.width = self.width or default_width
        self.width = self.width_factor * self.width
        self.height = self.height or self.screen_height - Screen:scaleBySize(30)
    end
    self.frame_width = self.width

    if not self.fullscreen and not self.block_height_adaptation and not self.use_low_height and self.use_scrolling_dialog > SCROLLING_SET_SCROLLBAR_DYNAMICALLY then
        local extra_width = 2 * self.side_padding
        if self.frame_width + extra_width <= self.screen_width then
            self.frame_width = self.width + extra_width
        end
    end
end

function TextViewer:setPadding()
    if self.add_more_padding then
        self.text_padding = Screen:scaleBySize(60)
    end
end

function TextViewer:setSeparator()
    self.separator = LineWidget:new{
        background = Colors.line_separator,
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
end

return TextViewer
