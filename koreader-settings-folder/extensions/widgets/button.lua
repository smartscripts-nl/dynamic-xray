--[[--
A button widget that shows text or an icon and handles callback when tapped.

@usage
    local Button = require("ui/widget/button")
    local button = Button:new{
        text = _("Press me!"),
        enabled = false, --* defaults to true
        callback = some_callback_function,
        width = Screen:scaleBySize(50),
        max_width = Screen:scaleBySize(100),
        bordersize = Screen:scaleBySize(3),
        margin = 0,
        padding = Screen:scaleBySize(2),
    }
--]]

local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/leftcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local TextWidget = require("extensions/widgets/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local tr = KOR:initCustomTranslations()
local Screen = Device.screen
local logger = require("logger")

local DX = DX
local G_reader_settings = G_reader_settings
local math = math
local table = table
local tostring = tostring
local type = type

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

--- @class Button
local Button = InputContainer:extend {
    text = nil, --* mandatory (unless icon is provided)
    text_func = nil,
    lang = nil,
    icon = nil,
    icon_width = nil,
    icon_height = nil,
    icon_rotation_angle = 0,
    align = "center", --* or "left"
    preselect = false,
    callback = nil,
    hold_callback = nil,
    show_hold_callback_indicator = false,
    enabled = true,
    hidden = false,
    allow_hold_when_disabled = false,
    margin = 0,
    bordersize = Size.border.button,
    bordercolor = KOR.colors.button_default,
    background = KOR.colors.background,
    radius = nil,
    padding = Size.padding.button,
    padding_h = nil,
    --* these two for buttons at the end of footer buttons, to make them more easily selectable:
    padding_left = nil,
    padding_right = nil,
    padding_v = nil,
    --* Provide only one of these two: 'width' to get a fixed width,
    --* 'max_width' to allow it to be smaller if text or icon is smaller.
    width = nil,
    max_width = nil,
    avoid_text_truncation = true,
    text_font_face = "cfont",
    text_font_size = 18,
    text_font_bold = true,
    fgcolor = nil,
    vsync = nil, --* when "flash_ui" is enabled, allow bundling the highlight with the callback, and fence that batch away from the unhighlight. Avoid delays when callback requires a "partial" on Kobo Mk. 7, c.f., ffi/framebuffer_mxcfb for more details.

    --* SmartScripts:
    additional_label_widget_icon = nil,
    alpha = nil,
    bordersize = nil,
    button_lines = 2,
    decrease_top_padding = 0,
    increase_top_padding = 0,
    --* alias for text_font_bold:
    font_bold = nil,
    font_cache = {},
    for_titlebar = false,
    inhibit_input_after_click = false,
    icon_icon = nil,
    icon_size_ratio = nil,
    icon_text = nil,
    indicator_color = KOR.colors.lighter_indicator_color,
    indicator_color_darker = KOR.colors.darker_indicator_color,
    indicator_max_width = 60,
    info_callback = nil,
    is_active_tab = false,
    is_tab_button = false,
    label_max_width = nil,
    readonly = false,
    readonly_inverted = false,
    text_icon = nil,
    texticon_text = nil,
}

function Button:init()
    self:computeFixedIconDims()
    self:setBasicButtonProps()
    self:setIconSizeRatioIfNeeded()
    self:setHoldCallback()
    self:setTextProps()
    self:setLabelMaxWidth()
    self:setLeftOrRightIndicator()
    self:initLabelWidget()
    self:adaptLabelSize()
    self:setWidgetContent()
    self:adaptPaddings()
    self:finalizeWidget()
end

--- @private
function Button:computeFixedIconDims()
    --* don't use forced icon dimensions on Bigme, because otherwise some icons then blackened:
    if self.icon_size_ratio_forced and not DX.s.is_mobile_device then
        local fixed_icon_height = math.floor(DGENERIC_ICON_SIZE * self.icon_size_ratio_forced)
        self.icon_height = fixed_icon_height
        self.icon_width = fixed_icon_height

    --! force uniform icon sizes (unless we have a confirm box):
    elseif not KOR.registry:getOnce("use_bigger_buttons") and not DX.s.is_mobile_device and not self.icon_height then
        local fixed_icon_height = KOR.buttonprops:getFixedIconHeight()
        self.icon_height = fixed_icon_height
        self.icon_width = fixed_icon_height
        self.icon_size_ratio = nil
        --* to make sure that the text label doesn't make a button higher:
        if self.text_font_size > 18 then
            self.text_font_size = 18
        end
    end
end

--- @private
function Button:setBasicButtonProps()
    if self.font_bold ~= nil then
        self.text_font_bold = self.font_bold
    end
    --* Prefer an optional text_func over text
    if self.text_func and type(self.text_func) == "function" then
        self.text = self.text_func()
    end

    --* to prevent errors in the match in the next code block when self.text is delivered as a number:
    if self.text then
        self.text = tostring(self.text)
    end
    -- #((hotfix for bold "edit" and "jump" buttons for xray items in page info TOC popup))
    --! hotfix for the Xray "jump" and "edit" buttons which are shown when the user longpresses a xray item in the Page/Paragraph Info TOC popup:
    if self.text and (self.text:match(tr("edit") .. "$") or self.text:match(tr("jump") .. "$")) then
        self.text_font_bold = true
        self.font_bold = true
        --* for consumption in ((Button#generateTextLabel)): edit and jump buttons will have bigger font size than the regular xray item buttons in the xray TOC longpress dialog:
        self.is_bigger_xray_item = true
    end

    if self.readonly and self.readonly_inverted then
        self.background = KOR.colors.black
    end

    --* Point tap_input to hold_input if requested
    if self.call_hold_input_on_tap then
        self.tap_input = self.hold_input
    end

    if not self.padding_h then
        self.padding_h = self.padding
    end
    if not self.padding_v then
        self.padding_v = self.padding
    end

    --* If this button could be made smaller while still not needing truncation
    --* or a smaller font size, we'll set this: it may allow an upper widget to
    --* resize/relayout itself to look more compact/nicer (as this size would
    --* depends on translations)
    self._min_needed_width = nil
    self._min_needed_additional_width = nil

    self.outer_pad_width = 2 * self.padding_h + 2 * self.margin + 2 * self.bordersize --* unscaled_size_check: ignore
end

--- @private
function Button:setLeftOrRightIndicator()
    --* this was set in ((Button#setHoldCallback)):
    if self.info_callbacks_show_indicators then
        self.right_indicator = self:generateTextLabel{
            text = ".",
            max_width = self.indicator_max_width,
            label_color = self.indicator_color,
            outer_pad_width = 0,
        }

    elseif self.show_hold_callback_indicator then
        self.left_indicator = self:generateTextLabel{
            text = KOR.icons.hold_callback_indicator_bare,
            max_width = self.indicator_max_width,
            label_color = self.indicator_color_darker,
            outer_pad_width = 0,
        }
    end
end

--- @private
function Button:setLabelMaxWidth()
    self.label_max_width = self.max_width or self.width
    if self.label_max_width then
        self.label_max_width = self.label_max_width - self.outer_pad_width
    end
end

--- @private
function Button:setTextProps()
    --? for which case is this used: close button?:
    if self.text == "X" and self.icon then
        self.icon = nil
    end

    if self.text and (self.icon or self.icon_icon or self.icon_text or self.text_icon) then
        self.text = nil
    end

    if self.icon_text and self.icon_text.text_icon then
        self.texticon_text = self.icon_text
        self.texticon_text.fgcolor = self.icon_text.fgcolor
        self.icon_text = nil
    end
end

--- @private
function Button:adaptLabelSize()
    local widget_size = self.label_widget:getSize()
    self.label_container_height = self.reference_height or widget_size.h
    if self.width then
        self.inner_width = self.width - self.outer_pad_width
        return
    end

    if self.icon_icon or self.icon_text or self.text_icon then
        self.inner_width = widget_size.w + self.additional_label_widget_icon:getSize().w

        if self.icon_icon and self.icon_icon.middle_text then
            self.inner_width = self.inner_width + self.middle_text_widget:getSize().w
        end
        return
    end
    if self.texticon_text then
        self.inner_width = widget_size.w + self.additional_label_widget_text:getSize().w
        return
    end

    self.inner_width = widget_size.w
end

--- @private
function Button:setWidgetContent()
    local widget
    if not self._min_needed_additional_width then
        widget = HorizontalGroup:new{ self.label_widget }

    elseif self.icon_icon and self.icon_icon.middle_text then
        widget = HorizontalGroup:new{
            self.label_widget_icon,
            self.middle_text_widget,
            self.additional_label_widget_icon,
        }
    elseif self.icon_icon then
        widget = HorizontalGroup:new{
            self.label_widget_icon,
            self.additional_label_widget_icon,
        }

    elseif self.text_icon then
        widget = HorizontalGroup:new{
            self.label_widget,
            self.additional_label_widget_icon,
        }

    elseif self.icon_text then
        widget = HorizontalGroup:new{
            self.additional_label_widget_icon,
            self.label_widget,
        }

    elseif self.texticon_text then
        widget = HorizontalGroup:new{
            self.additional_label_widget_text,
            self.label_widget,
        }
    end
    if self.left_indicator then
        table.insert(widget, 1, self.left_indicator)
    end
    if self.right_indicator then
        table.insert(widget, self.right_indicator)
    end

    local is_left_aligned = self.align == "left"
    if is_left_aligned then
        self.label_container = LeftContainer:new{
            dimen = Geom:new{
                w = self.inner_width,
                h = self.label_container_height,
            },
            widget,
        }
    else
        self.label_container = CenterContainer:new{
            dimen = Geom:new{
                w = self.inner_width,
                h = self.label_container_height,
            },
            widget,
        }
    end
end

--- @private
function Button:adaptPaddings()
    self.padding_bottom = self.padding_v
    self.padding_top = self.padding_v
    if self.decrease_top_padding and self.decrease_top_padding > 0 then
        self.padding_top = self.decrease_top_padding >= self.padding_v and 0 or self.padding_v - self.decrease_top_padding
    elseif self.increase_top_padding and self.increase_top_padding > 0 then
        self.padding_top = self.padding_v + self.increase_top_padding
    end
    if self.icon_text or self.icon_text then
        self.padding_bottom = self.padding_v - self.decrease_top_padding
        if self.padding_bottom < 0 then
            self.padding_bottom = 0
        end
    end
end

--- @private
function Button:setHoldCallback()
    self.info_callbacks_show_indicators = KOR.registry.info_callbacks_show_indicators and self.info_callback
    if self.info_callback then
        self.hold_callback = self.info_callback
    end
end

--- @private
function Button:finalizeWidget()
    self.frame = FrameContainer:new{
        margin = self.margin,
        show_parent = self.show_parent,
        bordersize = self.bordersize,
        color = self.bordercolor,
        background = self.background,
        radius = self.radius,
        padding_top = self.padding_top,
        padding_bottom = self.padding_bottom,
        --* these custom paddings can be set in ((Menu#instantiateButton))
        padding_left = self.padding_left or self.padding_h,
        padding_right = self.padding_right or self.padding_h,
        self.label_container,
        readonly = self.readonly,
        readonly_inverted = self.readonly_inverted,
    }
    if self.readonly and self.alpha then
        self.frame = MovableContainer:new{
            alpha = self.alpha,
            self.frame
        }
    end
    if self.preselect then
        self.frame.invert = true
    end
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    if not self.readonly then
        self.ges_events = {
            TapSelectButton = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
            HoldSelectButton = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
            },
            --* Safe-guard for when used inside a MovableContainer
            HoldReleaseSelectButton = {
                GestureRange:new{
                    ges = "hold_release",
                    range = self.dimen,
                },
            }
        }
    end
end

--- @private
function Button:getIcon(icon)
    self:ensureIconSize()
    return IconWidget:new{
        icon = icon,
        rotation_angle = self.icon_rotation_angle,
        dim = not self.enabled,
        width = self.icon_width,
        height = self.icon_height,
    }
end

--- @private
function Button:addWidth(w)
    self._min_needed_width = (self._min_needed_width or 0) + w
    self._min_needed_additional_width = w
end

--- @private
function Button:initLabelWidget()

    --* 1) Pure icon-only case:
    if not self.text and not self.icon_icon and not self.text_icon and not self.icon_text and not self.texticon_text then
        self:ensureIconSize()
        self.label_widget = self:getIcon(self.icon)
        self._min_needed_width = self.icon_width + self.outer_pad_width
        return
    end

    --* defaults:
    if self.enabled == nil then
        self.enabled = true
    end

    --* 2) Normalize variant → set text/icon/font once:
    local variant = self.icon_icon or
        self.icon_text or
        self.text_icon or
        self.texticon_text or
        self

    if self.icon_icon then
        self.icon = variant.icon
    elseif variant.text then
        self.text = variant.text
        --* if variant is self, self.fgcolor will be read:
        self:setFontProps(variant)
    end

    --* 3) Label color:
    local label_color = (self.readonly and self.readonly_inverted)
        and KOR.colors.readonly_inverted
        --* self.fgcolor makes color overrides possible:
        or (self.fgcolor or (self.enabled and KOR.colors.label_enabled or KOR.colors.label_disabled))

    local owidth = (not self.left_indicator and not self.right_indicator) and self.outer_pad_width or 0

    --* 4) Main text label:
    self.label_widget, self._min_needed_width = self:generateTextLabel{
        text = self.text,
        max_width = self.label_max_width,
        label_color = label_color,
        outer_pad_width = owidth,
    }

    --* 5) Variants that add extra widgets:
    if self.icon_icon then
        --* left icon:
        self.label_widget_icon = self:getIcon(self.icon_icon.icon)

        --* optional middle text:
        local middle_w = 0
        if self.icon_icon.middle_text then
            self.middle_text_widget, middle_w = self:generateTextLabel{
                text = self.icon_icon.middle_text,
                fgcolor = KOR.colors.lighter_text,
                max_width = self.label_max_width,
                label_color = label_color,
                outer_pad_width = owidth,
            }
        end

        --* right icon:
        self.additional_label_widget_icon = self:getIcon(self.icon_icon.icon2)

        self:addWidth(self.icon_width + self.outer_pad_width + middle_w)

    elseif self.text_icon or self.icon_text then
        local icon = (self.text_icon or self.icon_text).icon
        self.additional_label_widget_icon = self:getIcon(icon)
        self:addWidth(self.icon_width + self.outer_pad_width)

    elseif self.texticon_text then
        --* this is the "icon" text preceding the regular text:
        self.additional_label_widget_text = self:generateTextLabel{
            text = self.texticon_text.text_icon,
            is_icon_text = true,
            max_width = self.label_max_width,
            label_color = label_color,
            outer_pad_width = owidth,
        }
        self:addWidth(self.additional_label_widget_text:getSize().w + self.outer_pad_width)
    end
end

function Button:getMinNeededWidth()
    if self._min_needed_width and self._min_needed_width < self.width then
        return self._min_needed_width
    end
end

function Button:setText(text, width)
    if text and text ~= self.text then
        --* Don't trash the frame if we're already a text button, and we're keeping the geometry intact
        if self.text and width and width == self.width and not self.did_truncation_tweaks then
            self.text = text
            self.label_widget:setText(text)
        else
            self.text = text
            self.width = width
            self.label_widget:free()
            self:init()
        end
    end
end

function Button:setIcon(icon, width)
    if icon ~= self.icon then
        self.icon = icon
        self.width = width
        self.label_widget:free()
        self:init()
    end
end

function Button:onFocus()
    if self.no_focus then
        return
    end
    self.frame.invert = true
    return true
end

function Button:onUnfocus()
    if self.no_focus then
        return
    end
    self.frame.invert = false
    return true
end

function Button:enable()
    if not self.enabled then
        if self.text then
            self.label_widget.fgcolor = KOR.colors.button_default
            if self.label_widget.update then
                --* using a TextBoxWidget
                self.label_widget:update() --* needed to redraw with the new color
            end
        else
            self.label_widget.dim = false
        end
        self.enabled = true
    end
end

function Button:disable()
    if self.enabled then
        if self.text then
            self.label_widget.fgcolor = KOR.colors.button_disabled
            if self.label_widget.update then
                self.label_widget:update()
            end
        else
            self.label_widget.dim = true
        end
        self.enabled = false
    end
end

--* This is used by pagination buttons with a hold_input registered that we want to *sometimes* inhibit,
--* meaning we want the Button disabled, but *without* dimming the text...
function Button:disableWithoutDimming()
    self.enabled = false
    if self.text then
        self.label_widget.fgcolor = KOR.colors.button_default
    else
        self.label_widget.dim = false
    end
end

function Button:enableDisable(enable)
    if enable then
        self:enable()
    else
        self:disable()
    end
end

function Button:paintTo(bb, x, y)
    if self.enabled_func then
        --* state may change because of outside factors, so check it on each painting
        self:enableDisable(self.enabled_func())
    end
    InputContainer.paintTo(self, bb, x, y)
end

function Button:hide()
    if self.icon and not self.hidden then
        self.frame.orig_background = self.frame.background
        self.frame.background = nil
        self.label_widget.hide = true
        self.hidden = true
    end
end

function Button:show()
    if self.icon and self.hidden then
        self.label_widget.hide = false
        self.frame.background = self.frame.orig_background
        self.hidden = false
    end
end

function Button:showHide(show)
    if show then
        self:show()
    else
        self:hide()
    end
end

--* Used by onTapSelectButton to handle visual feedback when flash_ui is enabled
function Button:_doFeedbackHighlight()
    --* NOTE: self[1] -> self.frame, if you're confused about what this does vs. onFocus/onUnfocus ;).
    if self.text then
        --* We only want the button's *highlight* to have rounded corners (otherwise they're redundant, same color as the bg).
        --* The nil check is to discriminate the default from callers that explicitly request a specific radius.
        if self[1].radius == nil then
            self[1].radius = Size.radius.button
            --* And here, it's easier to just invert the bg/fg colors ourselves,
            --* so as to preserve the rounded corners in one step.
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
            --* We do *NOT* set the invert flag, because it just adds an invertRect step at the end of the paintTo process,
            --* and we've already taken care of inversion in a way that won't mangle the rounded corners.
        else
            self[1].invert = true
        end

        --* This repaints *now*, unlike setDirty
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
    else
        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
    end
    UIManager:setDirty(nil, "fast", self[1].dimen)
end

function Button:_undoFeedbackHighlight(is_translucent)
    if self.text then
        if self[1].radius == Size.radius.button then
            self[1].radius = nil
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
        else
            self[1].invert = false
        end
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
    else
        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
    end

    if is_translucent then
        --* If our parent belongs to a translucent MovableContainer, we need to repaint it on unhighlight in order to honor alpha,
        --* because our highlight/unhighlight will have made the Button fully opaque.
        --* UIManager will detect transparency and then takes care of also repainting what's underneath us to avoid alpha layering glitches.
        UIManager:setDirty(self.show_parent, "ui", self[1].dimen)
    else
        --* In case the callback itself won't enqueue a refresh region that includes us, do it ourselves.
        --* If the button is disabled, switch to UI to make sure the gray comes through unharmed ;).
        UIManager:setDirty(nil, self.enabled and "fast" or "ui", self[1].dimen)
    end
end

--* pos can be used for ((Dialogs#alertInfo)), to show the info alert directly below a tapped button:
--* see ((MOVE_MOVABLES_TO_Y_POSITION)) for more info:
function Button:onTapSelectButton(irr, pos)
    irr = pos
    if self.enabled or self.allow_tap_when_disabled then
        if self.callback then
            if G_reader_settings:isFalse("flash_ui") then
                self.callback(pos, self.field_no)
            else
                --* NOTE: We have a few tricks up our sleeve in case our parent is inside a translucent MovableContainer...
                local is_translucent = self.show_parent and self.show_parent.movable and self.show_parent.movable.alpha

                --* Highlight
                self:_doFeedbackHighlight()

                --* Force the refresh by draining the refresh queue *now*, so we have a chance to see the highlight on its own, before whatever the callback will do.
                if not self.vsync then
                    --* NOTE: Except when a Button is flagged vsync, in which case we *want* to bundle the highlight with the callback, to prevent further delays
                    UIManager:forceRePaint()

                    --* NOTE: Yield to the kernel for a tiny slice of time, otherwise, writing to the same fb region as the refresh we've just requested may be race-y,
                    --*       causing mild variants of our friend the papercut refresh glitch ;).
                    --*       Remember that the whole eInk refresh dance is completely asynchronous: we *request* a refresh from the kernel,
                    --*       but it's up to the EPDC to schedule that however it sees fit...
                    --*       The other approach would be to *ask* the EPDC to block until it's *completely* done,
                    --*       but that's too much (because we only care about it being done *reading* the fb),
                    --*       and that could take upwards of 300ms, which is also way too much ;).
                    UIManager:yieldToEPDC()
                end

                --* Unhighlight

                --* We'll *paint* the unhighlight now, because at this point we can still be sure that our widget exists,
                --* and that anything we do will not impact whatever the callback does (i.e., that we draw *below* whatever the callback might show).
                --* We won't *fence* the refresh (i.e., it's queued, but we don't actually drain the queue yet), though, to ensure that we do not delay the callback, and that the unhighlight essentially blends into whatever the callback does.
                --* Worst case scenario, we'll simply have "wasted" a tiny subwidget repaint if the callback closed us,
                --* but doing it this way allows us to avoid a large array of potential interactions with whatever the callback may paint/refresh if we were to handle the unhighlight post-callback,
                --* which would require a number of possibly brittle heuristics to handle.
                --* NOTE: If a Button is marked vsync, we want to keep it highlighted for now (in order for said highlight to be visible during the callback refresh), we'll remove the highlight post-callback.
                if not self.vsync then
                    self:_undoFeedbackHighlight(is_translucent)
                end

                --* Callback

                self.callback(pos, self.field_no)

                --* Check if the callback reset transparency...
                is_translucent = is_translucent and self.show_parent.movable.alpha

                UIManager:forceRePaint() --* Ensures whatever the callback wanted to paint will be shown *now*...
                if self.vsync then
                    --* NOTE: This is mainly useful when the callback caused a REAGL update that we do not explicitly fence via MXCFB_WAIT_FOR_UPDATE_COMPLETE already, (i.e., Kobo Mk. 7).
                    UIManager:waitForVSync() --* ...and that the EPDC will not wait to coalesce it with the *next* update,
                    --* because that would have a chance to noticeably delay it until the unhighlight.
                end

                --* Unhighlight

                --* NOTE: If a Button is marked vsync, we have a guarantee from the programmer that the widget it belongs to is still alive and top-level post-callback,
                --*       so we can do this safely without risking UI glitches.
                if self.vsync then
                    self:_undoFeedbackHighlight(is_translucent)
                    UIManager:forceRePaint()
                end
            end

            --* Alex: for specific buttons prevent unintended presses upon underlying ui elements:
            if self.inhibit_input_after_click then
                KOR.system:inhibitInputOnHold()
            end

        elseif self.tap_input then
            self:onInput(self.tap_input)
        elseif type(self.tap_input_func) == "function" then
            self:onInput(self.tap_input_func())
        end
    end

    if self.readonly ~= true then
        return true
    end
end

--* Allow repainting and refreshing *a* specific Button, instead of the full screen/parent stack
function Button:refresh()
    --* We can only be called on a Button that's already been painted once, which allows us to know where we're positioned,
    --* thanks to the frame's geometry.
    --* e.g., right after a setText or setIcon is a no-go, as those kill the frame.
    --*       (Although, setText, if called with the current width, will conserve the frame).
    if not self[1].dimen then
        logger.dbg("Button:", tostring(self), "attempted a repaint in an unpainted frame!")
        return
    end
    UIManager:widgetRepaint(self[1], self[1].dimen.x, self.dimen.y)

    UIManager:setDirty(nil, function()
        return self.enabled and "fast" or "ui", self[1].dimen
    end)
end

function Button:onHoldSelectButton()
    --* If we're going to process this hold, we must make
    --* sure to also handle its hold_release below, so it's
    --* not propagated up to a MovableContainer
    self._hold_handled = nil
    if self.enabled or self.allow_hold_when_disabled then
        if self.hold_callback then
            --* Alex: to prevent pressing an underlying element unintentionally:
            KOR.system:inhibitInputOnHold()
            self.hold_callback()
            self._hold_handled = true
        elseif self.hold_input then
            self:onInput(self.hold_input, true)
            self._hold_handled = true
        elseif type(self.hold_input_func) == "function" then
            self:onInput(self.hold_input_func(), true)
            self._hold_handled = true
        end
    end
    if self.readonly ~= true then
        return true
    end
end

function Button:onHoldReleaseSelectButton()
    if self._hold_handled then
        self._hold_handled = nil
        return true
    end
    return false
end


--* ==================== SMARTSCRIPTS =====================

function Button:ensureIconSize()
    --* Alex: if fixed icon_height given, then use that:
    if self.icon_height then
        return
    end
    local size = self.icon_size_ratio and DGENERIC_ICON_SIZE * self.icon_size_ratio or DGENERIC_ICON_SIZE
    self.icon_height = Screen:scaleBySize(size)
    self.icon_width = self.icon_height --* our icons are square
end

function Button:generateTextLabel(label)
    --* when is_icon_text prop == true: for texticon_text labels the first text is an icon and must have a fixed, lighter color and not be bold:
    local label_color = not label.is_icon_text and label.label_color or KOR.colors.button_label
    local is_bold = not label.is_icon_text and self.text_font_bold or false
    local font_size = (self.text_font_size or not label.is_icon_text) and self.text_font_size or self.text_font_size * 1.15

    --* first var might be set in ((hotfix for bold "edit" and "jump" buttons for xray items in page info TOC popup)):
    if not self.is_bigger_xray_item and KOR.registry:get("xray_toc_dialog_shown") then
        font_size = 17
    end

    -- #((mark active tab bold))
    --* ((TabFactory#setTabButtonAndContent)) can set this prop:
    if self.is_active_tab then
        font_size = font_size * 1.1
        is_bold = true

    --* force non active tab button to not be bold; this prop also set by ((TabFactory#setTabButtonAndContent)):
    elseif self.is_tab_button and not self.is_active_tab then
        is_bold = false
    end

    --local index = self.text_font_face .. font_size
    local face = Font:getFace(self.text_font_face, font_size) --self.font_cache[index] or
    --self.font_cache[index] = face

    local label_widget = TextWidget:new{
        text = label.text,
        lang = self.lang,
        max_width = label.max_width,
        fgcolor = label_color,
        bold = is_bold,
        face = face,
        padding = 0,
    }
    --* Our button's text may end up using a smaller font size, and/or be multiline.
    --* We will give the button the height it would have if no such tweaks were
    --* made. LeftContainer and CenterContainer will vertically center the
    --* TextWidget or TextBoxWidget in that height (hopefully no ink will overflow)
    self.reference_height = label_widget:getSize().h
    local _min_needed_width
    if not label_widget:isTruncated() then
        _min_needed_width = label_widget:getSize().w + label.outer_pad_width
    end
    if self.button_lines > 2 then
        self.reference_height = self.reference_height * (self.button_lines + 1) / 2
    end
    self:doTruncationTweaks(label_widget, label, label_color, is_bold)

    return label_widget, _min_needed_width
end

--- @private
function Button:doTruncationTweaks(label_widget, label, label_color, is_bold)
    self.did_truncation_tweaks = false
    if self.avoid_text_truncation and label_widget.face.orig_size and label_widget:isTruncated() then
        self.did_truncation_tweaks = true
        local font_size_2_lines = TextBoxWidget:getFontSizeToFitHeight(self.reference_height, self.button_lines, 0)
        while label_widget:isTruncated() do
            local new_size = label_widget.face.orig_size - 1
            if new_size <= font_size_2_lines then
                --* Switch to a 2-lines TextBoxWidget
                label_widget:free(true)
                label_widget = TextBoxWidget:new{
                    text = label.text,
                    lang = self.lang,
                    line_height = 0,
                    alignment = "center",
                    padding = 0,
                    width = label.max_width,
                    height = self.reference_height,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                    fgcolor = label_color,
                    bold = is_bold,
                    face = Font:getFace(self.text_font_face, new_size)
                }
                if not label_widget.has_split_inside_word then
                    break
                end
                --* No good wrap opportunity (split inside a word): ignore this TextBoxWidget
                --* and go on with a TextWidget with the smaller font size
            end
            if new_size < 8 then
                --* don't go too small
                break
            end
            label_widget:free(true)
            label_widget = TextWidget:new{
                text = label.text,
                lang = self.lang,
                padding = 0,
                max_width = label.max_width,
                fgcolor = label_color,
                bold = is_bold,
                face = Font:getFace(self.text_font_face, new_size)
            }
        end
    end
end

function Button:setIconSizeRatioIfNeeded()
    if self.icon_height then
        return
    end
    if self.icon then
        if self.icon == "home" or self.icon == "back" then
            self.icon_size_ratio = 0.8
            return
        end
        if self.icon == "leesplan" then
            self.icon_size_ratio = 0.45
            return
        end
    end
    local icon_types = { "icon", "icon_text", "text_icon", "icon_icon" }
    local icon_type
    local count = #icon_types
    for i = 1, count do
        icon_type = icon_types[i]
        if self[icon_type] and self[icon_type].icon_size_ratio then
            self.icon_size_ratio = self[icon_type].icon_size_ratio
            return
        end
    end
    self.icon_size_ratio = self.icon_size_ratio or 0.6
end

function Button:setFontProps(icon_or_text, force_normal)
    local is_table_prop = type(icon_or_text) == "table"
    self.fgcolor = is_table_prop and icon_or_text.fgcolor or KOR.colors.lighter_text
    if self.text_font_bold ~= false then
        if is_table_prop and (icon_or_text.font_bold == false or icon_or_text.text_font_bold == false) then
            self.text_font_bold = false
        elseif force_normal then
            self.text_font_bold = false
        else
            self.text_font_bold = true
        end
    end
    if is_table_prop and icon_or_text.text_font_face and icon_or_text.font_size then
        self.text_font_face = icon_or_text.text_font_face
        self.text_font_size = icon_or_text.font_size
    end
end

function Button:getTitlebarTabButton(is_active, label, portrait_length, callback)
    --* shorten button labels if we are in portrait display:
    --* in ((TitleBar#injectTabButtonsLeft)) and ((TitleBar#injectTabButtonsRight)) we also use smaller separators in case of portrait screen:
    label = KOR.screenhelpers:isLandscapeScreen() and label or label:sub(1, portrait_length)
    label = " " .. label .. " "
    local props = {
        text_func = function()
            label = label:gsub("^.+/", " ")

            if is_active then
                return " " .. KOR.icons.active_tab_bare .. label
            end
            return label
        end,
        callback = callback,
    }
    self:addTitleBarTabButtonProps(props, is_active)
    return props
end

function Button:addTitleBarTabButtonProps(props, active_condition_true)
    props.bordersize = 2
    props.radius = Screen:scaleBySize(5) --Size.radius.window
    props.text_font_face = "smalltfont"
    props.text_font_size = 13
    props.text_font_bold = active_condition_true
    props.padding_h = Size.padding.small
    if DX.s.is_android then
        props.padding_v = active_condition_true and 9 or 7
    else
        props.padding_v = active_condition_true and 2 or 0
    end
    props.margin = Size.margin.fine_tune
    props.fgcolor = active_condition_true and KOR.colors.active_tab or KOR.colors.inactive_tab
    props.bordercolor = active_condition_true and KOR.colors.button_default or KOR.colors.inactive_tab
end

return Button
