--[[--
Widget for taking multiple user inputs.
--]]--

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("extensions/widgets/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("extensions/widgets/inputdialog")
local InputText = require("extensions/widgets/inputtext")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("extensions/modules/size")
local TextBoxWidget = require("extensions/widgets/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DX = DX
local math = math
local table = table

local count
local LEFT_SIDE = 1
local RIGHT_SIDE = 2

--* if we extend FocusManager here, then crash because of ((MultiInputDialog#init)) > InputDialog.init(self)
--- @class MultiInputDialog
local MultiInputDialog = InputDialog:extend{
    --* to make the FocusManager work correctly, even under Ubuntu; this prop will be initially set by ((MultiInputDialog#insertFieldContainers)) and will upon switching between fields be dynamically updated to the active field by ((MultiInputDialog#onSwitchFocus)):
    _input_widget = nil,
    a_field_was_focussed = false,
    auto_height_field = nil,
    auto_height_field_index = nil,
    bottom_v_padding = Size.padding.small,
    description_face = Font:getDefaultDialogFontFace(),
    description_padding = Size.padding.small,
    description_prefix = "  ",
    description_margin = Size.margin.small,
    field_spacer = VerticalSpan:new{ width = Screen:scaleBySize(10) },
    field_nr = 0,
    fields = nil, --* array, mandatory
    focus_field = nil,
    has_field_rows = false,
    input_face = Font:getDefaultDialogFontFace(),
    input_fields = {}, --* array
    keyboard_height = nil,
    --! leave the props below alone, because consumed by inputdialog:
    field_values = {},
    input_registry = nil,
    initial_auto_field_height = 10,
    one_line_height = DX.s.is_ubuntu and 15 or 30,
    submenu_buttontable = nil,
    title_tab_buttons_left = nil,
    title_tab_callbacks = nil,
}

function MultiInputDialog:init()
    --* NB: title and buttons are initialized in base class
    self:initMainContainers()
    self:initWidgetProps()
    self:insertRows()
    self:registerInputFields()
    self:insertButtonGroup()
    --* adapt content of MiddleContainer: either a field with auto field height, or a spacer, to push the buttons to just above the keyboard:
    self:adaptMiddleContainerHeight()
    self:finalizeWidgetMID()
    self:focusFocusField()
    KOR.dialogs:registerWidget(self)
end

--* Returns an array of our input field's *text* fields:
function MultiInputDialog:getFields()
    local field_values = {}
    local field
    count = #self.input_fields
    for i = 1, count do
        field = self.input_fields[i]
        table.insert(field_values, field:getText())
    end
    return field_values
end

function MultiInputDialog:getValues()
    local field
    count = #self.input_fields
    for i = 1, count do
        field = self.input_fields[i]
        local value_index = field.value_index
        self.field_values[value_index] = field:getText()
    end
    local values = {}
    count = #self.field_values
    for i = 1, count do
        table.insert(values, self.field_values[i])
    end
    return values
end

--- @private
function MultiInputDialog:onSwitchFocus(inputbox)
    --* unfocus current inputbox
    self._input_widget:unfocus()
    self._input_widget:onCloseKeyboard()
    self:refreshDialog()
    --* focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
end

--- @private
function MultiInputDialog:insertFieldContainers(field_source, is_field_row)
    self.halved_descriptions = {}
    self.halved_fields = {}
    self.fields_count = is_field_row and #field_source or 1
    local has_two_fields_per_row = is_field_row and self.fields_count > 1
    self.edit_button_width = 0
    --* insert a edit button at the right side of each field in a two field row:
    if has_two_fields_per_row then
        local measure_edit_button = self:getEditFieldButton(0)
        self.edit_button_width = measure_edit_button:getSize().w
        measure_edit_button:free()
    end
    for field_side = 1, self.fields_count do
        self:generateRows(field_side, field_source, is_field_row)
        --* handle rows with multipe fields:
        if self.fields_count > 1 then
            self:generateDescriptionContainers(field_side)
        end
    end

    --* self.halved_fields and self.halved_descriptions are reset to empty table after each row; see ((MultiInputDialog#insertFieldContainers)):
    if #self.halved_descriptions == 0 and #self.halved_fields == 0 then
        return
    end
    if #self.halved_descriptions > 0 then
        self.halved_descriptions.align = "center"
        self:insertIntoTargetContainer(HorizontalGroup:new(self.halved_descriptions))
    end
    local field_1 = self.halved_fields[1]
    local field_2 = self.halved_fields[2]
    local field1_container = self:getFieldContainer(field_1)
    local field2_container = self:getFieldContainer(field_2)

    local group = HorizontalGroup:new{
        align = "center",
        field1_container,
        field2_container,
    }
    self:insertIntoTargetContainer(group)
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:generateRows(field_side, field_source, is_field_row)
    self.force_one_line_field = is_field_row
    local field_config = is_field_row and field_source[field_side] or field_source
    if self.force_one_line_field then
        field_config.scroll = true
    end
    if field_side == RIGHT_SIDE then
        --* self.field_nr counts ALL fields, even those in different tabs:
        self.field_nr = self.field_nr + 1
    end
    self:fieldAddToInputs(field_config, field_side)
    self.current_field = #self.input_fields

    --* self.fields_count is either 1 or 2 (for two field row):
    if self.fields_count > 1 then
        table.insert(self.halved_fields, self.input_fields[self.current_field])
    end
    if field_config.is_edit_button_target then
        KOR.registry:set("edit_button_target", self.input_fields[self.current_field])
    end
    self:insertFieldDescription(field_config)
    self:insertFieldByRowType(field_side)
end

--- @private
function MultiInputDialog:generateCustomEditButton(field)
    if not field.custom_edit_button then
        return false
    end
    field.custom_edit_button = Button:new(field.custom_edit_button)
    self.custom_edit_button_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(4),
    }

    local custom_edit_button_spacer_width = self.custom_edit_button_spacer:getSize().w
    self.field_width = self.field_width - field.custom_edit_button:getSize().w - custom_edit_button_spacer_width

    return true
end

--- @private
function MultiInputDialog:setFieldWidth(field)
    self.field_width = math.floor(self.width * 0.9)
    if self.fields_count > 1 then
        --! don't make this factor bigger, because then in some situations fields don't fit and jump to next row:
        local factor = 0.49
        self.field_width = math.floor(self.field_width * factor)
        if not self:generateCustomEditButton(field) and field.input_type ~= "number" then
            self.field_width = self.field_width - self.edit_button_width
        end

    --* make single row long field align with halved fields:
    elseif self.has_field_rows then
        self.field_width = math.floor(self.field_width * 1.045)
    end
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:fieldAddToInputs(field_config, field_side)
    self:setFieldWidth(field_config)
    self:setFieldProps(field_config, field_side)

    --* the field with computed autoheight will be inserted into the form in ((MultiInputDialog#insertComputedHeightField)):
    if field_config.height == "auto" then
        --! auto_height_field is the field of which the height is to be adapted, in ((MultiInputDialog#adaptMiddleContainerHeight)):
        self.auto_height_field = KOR.tables:shallowCopy(self.field_config)
        --! we need this index to replace the temporary input field with the field with computed height:
        self.auto_height_field_index = #self.input_fields + 1
        self.field_config.height = self.initial_auto_field_height
        table.insert(self.input_fields, InputText:new(self.field_config))
        return
    end

    local field = InputText:new(self.field_config)
    table.insert(self.input_fields, field)
    if self.field_config.focused then
        --* sets the field to which scollbuttons etc. are coupled:
        self._input_widget = field
    end
end

--* compare ((MultiInputDialog#isFocusField)):
--- @private
function MultiInputDialog:focusFocusField()
    if not self.focus_field or self.focus_field == 1 or (self.active_tab and self.active_tab > 1) then
        return
    end
    --* to indeed change the focus to field no 2 or higher under tab no 1, we always have to focus field no 1 first and then focus the field we want to focus:
    self:onSwitchFocus(self.input_fields[1])
    self:onSwitchFocus(self.input_fields[self.focus_field])
end

--* compare ((MultiInputDialog#insertComputedHeightField)) > ((conditionally give auto height field focus)), where a computed height field might be given focus:
--* in case of self.focus_field being set, focus will be applied by ((MultiInputDialog#focusFocusField)):
--- @private
function MultiInputDialog:isFocusField(height, field_side)

    --* self.focus_field is only set in case of adding a new item:
    if self.focus_field and self.active_tab == 1 and #self.input_fields + 1 == self.focus_field then
        self.a_field_was_focussed = true
        return true
    end

    --* give focus to first left_side field or to auto height field:
    if
        (height == "auto" and (not self.focus_field or self.focus_field == 1))
        or
        (self.active_tab > 1 and field_side == LEFT_SIDE and not self.a_field_was_focussed)
    then
        self.a_field_was_focussed = true
        return true
    end

    return false
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:setFieldProps(field, field_side)

    local force_one_line = self.force_one_line_field or field.force_one_line_height
    local height = not field.height and force_one_line and self.one_line_height or field.height
    if height == "auto" then
        self.auto_height_field_present = true
    end

    self.field_config = {
        value_index =
            self.field_nr,
        text =
            self:setFieldProp(field.text, ""),
        hint =
            self:setFieldProp(field.hint, ""),
        description =
            field.description,
        info_popup_title =
            field.info_popup_title,
        info_popup_text =
            field.info_popup_text,
        --* this can be used to give the field with the dscription focus upon clicking on its info_popup_text label; see ((focus field upon click on info label)):
        info_icon_field_no =
            #self.input_fields + 1,
        tab =
            field.tab,
        --* e.g. used to insert a button for setting xray_type of an Xray item in ((XrayDialogs#getFormFields)):
        custom_edit_button =
            field.custom_edit_button,
        disable_paste =
            self:setFieldProp(field.disable_paste, false),
        left_side =
            self:setFieldProp(field.left_side, false),
        right_side =
            self:setFieldProp(field.right_side, false),
        width =
            self:setFieldProp(field.width, self.field_width),
        height =
            height,
        -- #((force one line field height))
        force_one_line =
            force_one_line,
        allow_newline =
            self:setFieldProp(field.allow_newline, false),
        cursor_at_end =
            field.cursor_at_end == true,
        top_line_num =
            self:setFieldProp(field.top_line_num, 1),
        is_adaptable =
            self:setFieldProp(field.is_adaptable, false),
        input_type =
            self:setFieldProp(field.input_type, "string"),
        text_type =
            field.text_type,
        face =
            self:setFieldProp(field.input_face, self.input_face),
        --* this prop is used by InputText:
        focused =
            self:isFocusField(height, field_side),
        scroll =
            self:setFieldProp(field.scroll, false),
        scroll_by_pan =
            self:setFieldProp(field.scroll_by_pan, false),
        parent =
            self,
        padding =
            field.padding,
        margin =
            field.info_popup_text and 0 or field.margin,

        --* allow these to be specified per field if needed
        alignment =
            self:setFieldProp(field.alignment, self.alignment),
        justified =
            self:setFieldProp(field.justified, self.justified),
        lang =
            self:setFieldProp(field.lang, self.lang),
        para_direction_rtl =
            self:setFieldProp(field.para_direction_rtl, self.para_direction_rtl),
        auto_para_direction =
            self:setFieldProp(field.auto_para_direction, self.auto_para_direction),
        alignment_strict =
            self:setFieldProp(field.alignment_strict, self.alignment_strict),
    }
end

--- @private
function MultiInputDialog:insertFieldDescription(field)
    --* for single field rows:
    if (not self.has_field_rows and field.description) or (self.fields_count == 1 and field.description) then
        local description_height
        self.input_description[self.current_field], description_height = self:getDescription(field, math.floor(self.width * 0.9))
        local group = LeftContainer:new{
            dimen = Geom:new{
                w = self.full_width,
                h = description_height,
            },
        self.input_description[self.current_field],
        }
        self:insertIntoTargetContainer(group)

    --* for rows with more than one field and no descriptions: when no title bar present, add some extra margin above the fields:
    elseif not self.title then
        local group = CenterContainer:new{
            dimen = Geom:new{
                w = self.full_width,
                h = 2 * self.description_margin,
            },
            VerticalSpan:new{ width = self.description_padding + self.description_margin },
        }
        self:insertIntoTargetContainer(group)
    end
end

--- @private
function MultiInputDialog:insertIntoTargetContainer(group, is_field)
    if is_field and self.auto_height_field_present and not self.auto_height_field_injected then
        self.auto_height_field_injected = true
        return
    end
    if self.auto_height_field and self.auto_height_field_injected then
        table.insert(self.BottomContainer, group)
    else
        table.insert(self.TopContainer, group)
    end
end

--- @private
function MultiInputDialog:insertFieldByRowType()
    --* for one field rows immediately insert the input field:
    if not self.has_field_rows or self.fields_count == 1 then
        self:insertSingleFieldInRow()
    end
end

--- @private
function MultiInputDialog:insertSingleFieldInRow()
    local field_height = self.input_fields[self.current_field]:getSize().h
    local group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = field_height,
        },
        self.input_fields[self.current_field],
    }
    self:insertIntoTargetContainer(group, "is_field")
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:generateDescriptionContainers(field_side)
    local tile_width = self.full_width / self.fields_count
    local has_description = self.input_fields[self.current_field].description
    local description_label = has_description and self:getDescription(self.input_fields[self.current_field], tile_width) or nil
    if field_side == LEFT_SIDE then
        if has_description then
            self.input_description[self.current_field] = FrameContainer:new{
                padding = self.description_padding,
                margin = 0,
                bordersize = 0,
                --* description in a multiple field row:
                description_label,
            }
            table.insert(self.halved_descriptions, LeftContainer:new{
                dimen = Geom:new{
                    w = tile_width,
                    h = self.input_description[self.current_field]:getSize().h,
                },
                self.input_description[self.current_field],
            })
        end
        return
    end
    --* this means that the right side field doesn't have a description:
    if not has_description then
        return
    end

    --* insert right side field (field_side == RIGHT_SIDE here):
    self.input_description[self.current_field] = FrameContainer:new{
        padding = self.description_padding,
        margin = 0,
        bordersize = 0,
        description_label,
    }
    table.insert(self.halved_descriptions, LeftContainer:new{
        dimen = Geom:new{
            w = tile_width,
            h = self.input_description[self.current_field]:getSize().h,
        },
        self.input_description[self.current_field],
    })
end

--- @private
function MultiInputDialog:getDescription(field, width)
    local text = field.info_popup_text and
        Button:new{
        text_icon = {
            text = self.description_prefix .. " " .. field.description .. " ",
            text_font_bold = false,
            text_font_face = "x_smallinfofont",
            font_size = 18,
            icon = "info-slender",
            icon_size_ratio = 0.48,
        },
        padding = 0,
        margin = 0,
        text_font_face = "x_smallinfofont",
        text_font_size = 19,
        text_font_bold = false,
        align = "left",
        bordersize = 0,
        width = width,
        --* y_pos for the popup dialog - not used now anymore - was detected and set in ((Button#onTapSelectButton)) - look for two statements with self.callback(pos):
        callback = function() --ypos
            -- #((focus field upon click on info label))
            --* this prop can be set in ((MultiInputDialog#insertFieldContainers)):
            if field.info_icon_field_no then
                self:onSwitchFocus(self.input_fields[field.info_icon_field_no])
            end
            --* info_popup_title and info_popup_text e.g. defined in ((XrayDialogs#getFormFields)):
            KOR.dialogs:niceAlert(field.info_popup_title, field.info_popup_text)
        end,
    }
    or
    TextBoxWidget:new{
        text = self.description_prefix .. field.description,
        face = self.description_face or Font:getFace("x_smallinfofont"),
        width = width,
        padding = 0,
    }
    local label = FrameContainer:new{
        padding = self.description_padding,
        margin = self.description_margin,
        bordersize = 0,
        text,
    }

    return label, label:getSize().h
end

--- @private
function MultiInputDialog:editField(input, input_type, field_hint, allow_newline, callback)
    local title = "Bewerk veldinhoud"
    if field_hint then
        title = title .. ": " .. field_hint
    end
    if not allow_newline then
        title = title .. " (geen regeleindes)"
    end
    local edit_dialog
    edit_dialog = InputDialog:new{
        title = title,
        input = input or "",
        input_hint = field_hint,
        input_type = input_type or "text",
        scroll = allow_newline,
        allow_newline = allow_newline,
        cursor_at_end = true,
        fullscreen = true,
        input_face = Font:getFace("smallinfofont", 18),
        buttons = {
            {
                {
                    icon = "back",
                    icon_size_ratio = 0.7,
                    id = "close",
                    callback = function()
                        UIManager:close(edit_dialog)
                    end,
                },
                KOR.buttoninfopopup:forResetField({
                    callback = function()
                        edit_dialog:setInputText("")
                    end,
                }),
                {
                    icon = "save",
                    is_enter_default = not allow_newline,
                    callback = function()
                        local edited_text = edit_dialog:getInputText()
                        UIManager:close(edit_dialog)
                        callback(edited_text)
                    end,
                },
            },
        },
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
end

--- @private
function MultiInputDialog:getFieldContainer(field)
    local tile_width = self.full_width / self.fields_count
    local tile_height = self.halved_fields[1]:getSize().h
    local has_no_button = field.input_type == "number" and not field.custom_edit_button

    --* don't add edit field buttons for regular number fields without a custom edit button:
    if has_no_button then
        return CenterContainer:new{
        dimen = Geom:new{
            w = tile_width,
            h = tile_height,
        },
        field,
    }
    end

    --* for custom edit button add spacer between field and button:
    --* see ((MultiInputDialog#generateCustomEditButton)) for custom edit button generation:
    if field.custom_edit_button then
        self.custom_edit_button = field.custom_edit_button
        KOR.registry:set("xray_type_button", self.custom_edit_button)

        return CenterContainer:new{
            dimen = Geom:new{
                w = tile_width,
                h = tile_height,
            },
            HorizontalGroup:new{
                align = "center",
                field,
                self.custom_edit_button_spacer,
                self.custom_edit_button,
            }
        }
    end

    return CenterContainer:new{
        dimen = Geom:new{
            w = tile_width,
            h = tile_height,
        },
        HorizontalGroup:new{
            align = "center",
            field,
            self:getEditFieldButton(field),
        }
    }
end

--- @private
function MultiInputDialog:getEditFieldButton(field)
    return Button:new{
        icon = "edit-light",
        bordersize = 0,
        callback = function()
            local input = field:getText()
            self:editField(input, field.input_type, field.hint, field.allow_newline, function(edited_text)
                field:setText(edited_text)
            end)
        end,
    }
end

--- @private
function MultiInputDialog:insertButtonGroup()
    table.insert(self.BottomContainer, self.field_spacer)
    self.button_table_height = self.button_table:getSize().h
    self.button_group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = self.button_table_height,
        },
        self.button_table,
    }
    table.insert(self.BottomContainer, self.button_group)
end

--- @private
function MultiInputDialog:registerInputFields()
    if self.input_registry then
        --* input_fields were populated in ((MultiInputDialog#fieldAddToInputs)):
        KOR.registry:set(self.input_registry, self.input_fields)
    end
end

--- @private
function MultiInputDialog:initMainContainers()
    InputDialog.init(self)
    if self.title and self.title_bar then
        self.TopContainer = VerticalGroup:new{
            align = "left",
            self.title_bar,
        }
    else
        self.TopContainer = VerticalGroup:new{
            align = "left",
        }
    end
    --* this MiddleContainer will either receive a field with computed height to push the buttons to just above the keyboard, or a spacer with computed height to do the same:
    self.MiddleContainer = VerticalGroup:new{
        align = "left",
    }
    --* if a auto height field was provided, then this container will receive the fields that came after that field:
    --* in any case, this container will always receive the form's buttontable as last of all form elements:
    self.BottomContainer = VerticalGroup:new{
        align = "left",
    }
end

--- @private
function MultiInputDialog:initWidgetProps()
    --* don't use halved input fields in portrait display:
    if KOR.screenhelpers:isPortraitScreen() then
        self.has_field_rows = false
    end
    self.input_description = {}
    --* Alex: for some reason (maybe because of InputDialog.init above?) we have to force the font here:
    self.input_face = self.input_face or Font:getDefaultDialogFontFace()
    KOR.registry:unset("edit_button_target")
    self.full_width = self.title_bar and self.title_bar:getSize().w or self.width
    self.auto_height_field_present = false
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
    --* keyboard was initialised in ((InputText#initKeyboard)):
    self.keyboard_height = self._input_widget:getKeyboardDimen().h
    KOR.registry:set("keyboard_height", self.keyboard_height)
    self.max_dialog_height = self.screen_height - self.keyboard_height
end

--- @private
function MultiInputDialog:adaptMiddleContainerHeight()
    local difference = self.screen_height - self.TopContainer:getSize().h - self.BottomContainer:getSize().h - self.keyboard_height

    if self:insertComputedHeightField(difference) then
        return
    end

    --* insert simple spacer to push the buttons to just above the keyboard:
    table.insert(self.MiddleContainer, VerticalSpan:new{ width = difference })
end

--- @private
function MultiInputDialog:insertComputedHeightField(difference)

    --* self.auto_height_field will be set in ((MultiInputDialog#fieldAddToInputs)), when a field there has height = "auto":
    if not self.auto_height_field then
        return false
    end

    --* for margin above and below auto height field:
    difference = difference - 2 * self.field_spacer:getSize().h
    self.auto_height_field.height = difference
    --* auto_height_field_index was set in ((MultiInputDialog#fieldAddToInputs)):
    self.input_fields[self.auto_height_field_index]:free()

    --* force the auto height field to VISUALLY HAVE FOCUS (this prop is used by InputText; but only setting self._input_widget to the field that will now be generated gives it FOCUS BEHAVIOR):
    self.auto_height_field.focused = true
    --* insert a field with dynamically adjusted height, to push the buttons to just above the keyboard:
    local field = InputText:new(self.auto_height_field)

    -- #((conditionally give auto height field focus))
    if self.focus_field == self.auto_height_field_index then
        --! force the computed auto field to really have focus behavior):
        self._input_widget = field
    end

    self.input_fields[self.auto_height_field_index] = field
    local group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = difference,
        },
        field,
    }
    table.insert(self.MiddleContainer, self.field_spacer)
    table.insert(self.MiddleContainer, group)
    table.insert(self.MiddleContainer, self.field_spacer)

    return true
end

--- @private
function MultiInputDialog:insertRows()
    count = #self.fields
    for row_nr = 1, count do
        self:insertFieldRowIfActiveTab(row_nr)
    end
end

--- @private
function MultiInputDialog:insertFieldRowIfActiveTab(row_nr)
    local target_tab
    local row = self.fields[row_nr]
    local is_field_set = not row.text
    self:registerFieldValues(row, is_field_set)
    target_tab = self.active_tab and ((is_field_set and row[1] and row[1].tab) or row.tab)

    --* administration for inactive tabs:
    if self.active_tab and target_tab < self.active_tab then
        if is_field_set then
            self.field_nr = self.field_nr + #row
        else
            self.field_nr = self.field_nr + 1
        end

    --* only insert fields for when they are in a non tabbed dialog or are in the active tab:
    elseif not target_tab or target_tab == self.active_tab then
        self.field_nr = self.field_nr + 1
        self:insertFieldContainers(row, is_field_set)
    end
end

--- @private
function MultiInputDialog:registerFieldValues(row, is_field_set)
    if self.has_field_rows and is_field_set then
        local count2 = #row
        for field = 1, count2 do
            table.insert(self.field_values, row[field].text)
        end
        return
    end
    table.insert(self.field_values, row.text)
end

--* MID suffix to prevent future name clashes, should we also add InputDialog#finalizeWidget:
--- @private
function MultiInputDialog:finalizeWidgetMID()
    local config = {
        radius = self.fullscreen and 0 or Size.radius.window,
        bordersize = self.fullscreen and 0 or Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.TopContainer,
            self.MiddleContainer,
            self.BottomContainer,
        }
    }
    if self.fullscreen then
        config.width = self.screen_width
        config.covers_fullscreen = true
        config.x = 0
        config.y = 0
        config.height = self.max_dialog_height
    end
    self.dialog_frame = FrameContainer:new(config)

    if self.fullscreen then
        self[1] = self.dialog_frame
    else
        self[1] = CenterContainer:new{
            dimen = Geom:new{
                w = self.screen_width,
                h = config.height or self.screen_height - self.keyboard_height,
            },
            ignore_if_over = "height",
            self.dialog_frame,
        }
    end

    self:refreshDialog()
end

--- @private
function MultiInputDialog:refreshDialog()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

--- @private
function MultiInputDialog:setFieldProp(prop, default_value)
    return prop or default_value
end

return MultiInputDialog
