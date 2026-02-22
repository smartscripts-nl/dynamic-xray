
local require = require

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local MovableContainer = require("extensions/widgets/container/movablecontainer")
local ScrollHtmlWidget = require("extensions/widgets/scrollhtmlwidget")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local Size = require("extensions/modules/size")
local TitleBar = require("extensions/widgets/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Input = require("extensions/modules/input")
local Screen = Device.screen

local DX = DX
local G_reader_settings = G_reader_settings
local math = math
local table = table
local tonumber = tonumber

-- this widget only loaded in ((Dialogs#htmlBox))
--- @class HtmlWidget
local HtmlWidget = InputContainer:extend{
    height = nil,
    context_link_tapped = nil,
    html = nil,
    -- refresh_callback will be called before we trigger full refresh in onSwipe
    refresh_callback = nil,
    title = nil,
    width = nil,

    -- Static class member, holds a ref to the currently opened widgets (in instantiation order).
    window_list = {},
}

function HtmlWidget:init()

    if Device:hasKeys() then
        self.key_events = {
            ReadPrevResult = { { Input.group.PgBack } },
            ReadNextResult = { { Input.group.PgFwd } },
            Close = DX.s.is_ubuntu and { { Input.group.Back } } or { { Input.group.CloseDialog } },
        }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            Tap = {
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
            -- Allow selection of one or more words (see textboxwidget.lua) :
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
                -- callback function when HoldReleaseText is handled as args, upon holding a page number jump to that page:
                args = function(page_no)
                    if page_no:match("^%d+$") then
                        self:onClose()
                        UIManager:close(self.parent)
                        self.ui.link:addCurrentLocationToStack()
                        self.ui:handleEvent(Event:new("GotoPage", tonumber(page_no)))
                    end
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end

    -- code below adapted from ((DictQuickLookup#init))
    local font_size = G_reader_settings:readSetting("dict_font_size") or 20
    local content_face = Font:getFace("cfont", font_size)
    local width = Screen:getWidth()
    local frame_bordersize = 0
    local inner_width = width - 2 * frame_bordersize
    local content_padding_h = Size.padding.large
    local content_padding_v = Size.padding.large -- added via VerticalSpan
    local content_width = inner_width - 2 * content_padding_h

    self.character_title = TitleBar:new{
        width = inner_width,
        title = self.title,
        with_bottom_line = true,
        bottom_v_padding = 0, -- padding handled below
        close_callback = function()
            self:onClose()
        end,
        close_hold_callback = function()
            self:onHoldClose()
        end,
        align = "left",
        show_parent = self,
        lang = "en",
    }

    local buttons = {{
        {
            id = "close",
            icon = "back",
            icon_size_ratio = 0.8,
            callback = function()
                self:onClose()
            end,
            hold_callback = function()
                self:onHoldClose()
            end,
        },
        KOR.buttoninfopopup:forHtmlCopy({
            callback = function()
                local text = self.html:gsub("</?[^>]+>", "")
                KOR.clipboard:copy(text)
                KOR.messages:notify("tekst naar klembord gekopieerd...")
            end,
        }),
        {
            icon = "export",
            callback = function()
                local text = self.html:gsub("</?[^>]+>", "")
                KOR.dialogs:export(text)
                KOR.messages:notify("tekst naar export.txt geëxporteerd...")
            end,
            hold_callback = function()
                KOR.dialogs:alertInfo("Exporteer getoonde HTML als platte tekst naar export.txt.")
            end,
        },
    }}
    -- Bottom buttons get a bit less padding so their line separators
    -- reach out from the content to the borders a bit more
    local buttons_padding = Size.padding.default
    local buttons_width = inner_width - 2 * buttons_padding
    local button_table = ButtonTable:new{
        width = buttons_width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
        button_font_weight = "normal",
    }

    -- Spans between components
    local top_to_context_span = VerticalSpan:new{ width = content_padding_v }
    local definition_to_bottom_span = VerticalSpan:new{ width = content_padding_v }

    -- Available height for definition + components
    local margin_top = Size.margin.default
    local margin_bottom = Size.margin.default
    local avail_height = Screen:getHeight() - margin_top - margin_bottom
    local others_height = frame_bordersize * 2
            + self.character_title:getHeight()
            + top_to_context_span:getSize().h
            + definition_to_bottom_span:getSize().h
            + button_table:getSize().h
    local height = avail_height
    local html_window_height = height - others_height

    if not self.definition_line_height then
        local test_widget = ScrollTextWidget:new{
            text = "z",
            face = content_face,
            width = content_width,
            height = html_window_height,
            for_measurement_only = true, -- flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        self.definition_line_height = test_widget:getLineHeight()
        test_widget:free(true)
    end

    local nb_lines = math.floor(html_window_height / self.definition_line_height)
    html_window_height = nb_lines * self.definition_line_height

    self:adaptHtml()
    self.text_widget = ScrollHtmlWidget:new{
        html_body = self.html,
        css = self:getContextCss(),
        default_font_size = Screen:scaleBySize(font_size),
        width = content_width,
        height = html_window_height,
        dialog = self,
        html_link_tapped_callback = function(link)
            self.context_link_tapped(self.dictionary, link)
        end,
    }

    self.list_widget = FrameContainer:new{
        padding = 0,
        padding_left = content_padding_h,
        padding_right = content_padding_h,
        margin = 0,
        bordersize = 0,
        self.text_widget,
    }

    self.list_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = frame_bordersize,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.character_title,
            top_to_context_span,
            CenterContainer:new{
                dimen = Geom:new{
                    w = inner_width,
                    h = self.list_widget:getSize().h,
                },
                self.list_widget,
            },
            definition_to_bottom_span,
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = inner_width,
                    h = button_table:getSize().h,
                },
                button_table,
            }
        }
    }

    self.movable = MovableContainer:new{
        -- We'll handle these events ourselves, and call appropriate
        -- MovableContainer's methods when we didn't process the event
        ignore_events = {
            -- These have effects over the definition widget, and may
            -- or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            -- These do not have direct effect over the definition widget,
            -- but may happen while selecting text: we need to check
            -- a few things before forwarding them
            "touch", "pan", "pan_release",
        },
        self.list_frame,
    }

    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }

    -- We're a new window
    table.insert(HtmlWidget.window_list, self)

    UIManager:setDirty(self, function()
        return "partial", self.list_frame.dimen
    end)

    -- make Contexts dialog closeable with ((Dialogs#closeAllWidgets)):
    self.parent:registerWidget(self)
end

function HtmlWidget:getContextCss()
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

        .redhat {
            font-family: 'Red Hat Text' !important;
        }

        blockquote, dd {
            margin: 0 1em;
        }

        p {
            margin: 0 !important;
        }

        ul, menu {
            margin: 0; padding: 0 1.7em;
        }

        ol {
            margin: 0; padding: 0 2.2em;
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

function HtmlWidget:onCloseWidget()
    -- Our TextBoxWidget/HtmlBoxWidget/TextWidget/ImageWidget are proper child widgets,
    -- so this event will propagate to 'em, and they'll free their resources.

    -- Drop our ref from the static class member
    for i = #HtmlWidget.window_list, 1, -1 do
        local window = HtmlWidget.window_list[i]
        -- We should only find a single match, but, better safe than sorry...
        if window == self then
            table.remove(HtmlWidget.window_list, i)
        end
    end

    -- NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
end

function HtmlWidget:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self.list_frame.dimen
    end)
    return true
end

-- #((HtmlWidget#onTap))
function HtmlWidget:onTap(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.list_frame.dimen) then
        self:onClose()
        KOR.registry:unset("dictionary_context")
        self.garbage = arg
        return true
    end

    return true
end

function HtmlWidget:onClose()

    UIManager:close(self)
    KOR.highlight:clear()
    KOR.link:onGoBackLink()

    return true
end

function HtmlWidget:onHoldClose(no_clear)
    local window
    -- Pop the windows FILO
    local count = #HtmlWidget.window_list
    for i = count, 1, -1 do
        window = HtmlWidget.window_list[i]
        window:onClose(no_clear)
    end
    return true
end

function HtmlWidget:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.list_widget.dimen) then
    -- if we want changeDict to still work with swipe outside window :
    -- or not ges.pos:intersectWith(self.list_frame.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self:changeToNextDict()
        elseif direction == "east" then
            self:changeToPrevDict()
        else
            if self.refresh_callback then self.refresh_callback() end
            -- update footer (time & battery)
            KOR.footer:onUpdateFooter(true)
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
        return true
    end
    -- Let our MovableContainer handle swipe outside of definition
    return self.movable:onMovableSwipe(arg, ges)
end

function HtmlWidget:onHoldStartText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function HtmlWidget:onHoldPanText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    -- We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function HtmlWidget:onHoldReleaseText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

-- These 3 event processors are just used to forward these events
-- to our MovableContainer, under certain conditions, to avoid
-- unwanted moves of the window while we are selecting text in
-- the definition widget.
function HtmlWidget:onForwardingTouch(arg, ges)
    -- This Touch may be used as the Hold we don't get (for example,
    -- when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.list_widget.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        -- Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function HtmlWidget:onForwardingPan(arg, ges)
    -- We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function HtmlWidget:onForwardingPanRelease(arg, ges)
    -- We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end

--* ==================== SMARTSCRIPTS =====================

function HtmlWidget:adaptHtml()
    self.html = self.html:gsub("</?section[^>]*>", ""):gsub("<p[^>]+>", "<p>"):gsub("</?div[^>]*>", ""):gsub("</?body[^>]*>", ""):gsub("</?a[^>]*>", ""):gsub("<DocFragment[^>]+>", "<DocFragment lang=\"en\">")
end

function HtmlWidget:clearSelectionByID()
    if self.highlight then
        -- delay unhighlight of selection, so we can see where we stopped when
        -- back from our journey into dictionary
        local clear_id = self.highlight:getClearId()
        UIManager:scheduleIn(0.5, function()
            self.highlight:clear(clear_id)
        end)
    end
end

function HtmlWidget:clearSelection(clear_by_id)
    if clear_by_id then
        self:clearSelectionByID()
        return
    end
    if self.ui.document.info.has_pages then
        self.view.highlight.temp = {}
    else
        self.ui.document:clearSelection()
    end
end

function HtmlWidget:close_callback()
    -- to prevent hold action triggering another handler:
    self.parent:showOverlay()
    self:onClose()
    UIManager:scheduleIn(1, function()
        self.parent:closeOverlay()
    end)
end

return HtmlWidget
