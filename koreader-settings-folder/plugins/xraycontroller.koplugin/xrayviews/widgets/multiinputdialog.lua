--[[--
Widget for taking multiple user inputs.
--]]--

local require = require

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("xrayviews/widgets/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("xrayviews/widgets/checkbutton")
local Device = require("device")
local Font = require("modules/font")
local FrameContainer = require("xrayviews/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("xrayviews/widgets/inputdialog")
local InputText = require("xrayviews/widgets/inputtext")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("modules/size")
local TextBoxWidget = require("xrayviews/widgets/textboxwidget")
--* TitleBar is initialized and inherited from base class InputDialog
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DX = DX
local G_reader_settings = G_reader_settings
local math_floor = math_floor
local table_insert = table_insert

local count, count2
local LEFT_SIDE = 1

--* if we extend FocusManager here, then crash because of ((MultiInputDialog#init)) > InputDialog.init(self)
--- @class MultiInputDialog
local MultiInputDialog = InputDialog:extend{
    --* to make the FocusManager work correctly, even under Ubuntu; this prop will be initially set by ((MultiInputDialog#generateRows)) and will upon switching between fields be dynamically updated to the active field by ((MultiInputDialog#onSwitchFocus)):
    _input_widget = nil,
    active_tab = nil,
    a_field_was_focussed = false,
    auto_height_field = nil,
    auto_height_field_index = nil,
    auto_height_field_tab_index = nil,
    bottom_v_padding = Size.padding.small,
    button_spacer = nil,
    description_face = Font:getDefaultDescriptionFontFace(),
    description_padding = Size.padding.small,
    description_prefix = "  ",
    description_margin = Size.margin.small,
    field_spacer = VerticalSpan:new{ width = Screen:scaleBySize(10) },
    field_nr = 0,
    fields = nil, --* array, mandatory
    focus_field = nil,
    footer_description = nil,
    has_field_rows = false,
    input_face = Font:getDefaultInputFontFace(),
    --* ALL fields, even those in inactive tabs:
    input_fields = {},
    keyboard_height = nil,
    --! leave the props below alone, because consumed by inputdialog:
    field_values = {},
    input_registry = nil,
    initial_auto_field_height = 10,
    one_line_height = DX.s.is_ubuntu and 15 or 30,
    submenu_buttontable = nil,
    --* only the fields in the active tab:
    tab_fields = {},
    title_tab_callbacks = nil,
    top_paddings_tabs = nil,
}

function MultiInputDialog:init()
    --! crucial statement to prevent contamination of field values with the values of an older previous MultiInputDialog instance:
    self:resetRegistryValues()
    --* NB: title and buttons are initialized in base class
    self:initMainContainers()
    self:initWidgetProps()
    self:initSpacers()
    self:insertRows()
    self:insertFooterDescription()
    self:insertTopPadding()
    self:registerInputFields()
    self:insertButtonGroup()
    --* adapt content of MiddleContainer: either a field with auto field height, or a spacer, to push the buttons to just above the keyboard:
    self:adaptMiddleContainerHeight()
    self:buildWidget()
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
        table_insert(field_values, field:getText())
    end
    return field_values
end

--* get the values of ALL fields, even those in non active tabs:
function MultiInputDialog:getAllTabsFieldsValues()
    local field
    count = #self.input_fields
    for i = 1, count do
        --* these values were set in ((MultiInputDialog#fieldAddToInputs)):
        field = self.input_fields[i]
        local value_index = field.value_index
        --* checkboxes don't have method getText and don't have a value_index; see e.g. ((MultiInputDialog checkbox example)):
        if self.field_values[value_index] then
            self.field_values[value_index] = field.type == "checkbox" and field.checked and 1 or field:getText()
        end
    end
    local values = {}
    count = #self.field_values
    for i = 1, count do
        --* value here can be an empty text "", but never nil, because that would result in the value not being added:
        table_insert(values, self.field_values[i])
    end
    return values
end

--- @private
function MultiInputDialog:onSwitchFocus(inputbox)
    count = #self.tab_fields
    for i = 1, count do
        self:onUnfocus(self.tab_fields[i])
    end
    --* focus new inputbox
    self:onFocus(inputbox)
end

--- @private
function MultiInputDialog:onUnfocus(inputbox)
    --* unfocus current inputbox
    inputbox:unfocus()
    inputbox:onCloseKeyboard()
end

--- @private
function MultiInputDialog:onFocus(inputbox)
    self:refreshDialog()
    --* focus new inputbox
    self._input_widget = inputbox
    --* a checkbox — e.g. ((MultiInputDialog checkbox example)) — doesn't have the focus-method:
    if not self._input_widget.focus then
        return
    end
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
end

--- @private
function MultiInputDialog:generateRows(field_config, is_field_row)
    self.fields_count = is_field_row and #field_config or 1
    local is_two_field_row = is_field_row and self.fields_count > 1
    self.force_one_line_field = is_field_row

    if is_two_field_row then
        for i = 1, 2 do
            self.field_nr = self.field_nr + 1
            field_config[i].field_nr = self.field_nr
        end
        self:insertTwoFieldRow(field_config)
    else
        self.field_nr = self.field_nr + 1
        field_config.field_nr = self.field_nr
        self:insertSingleFieldRow(field_config)
    end
end

--- @private
function MultiInputDialog:setFieldEditButtonWidth()
    --* compute with of edit buttons to be inserted at the right side of each field in a two field row:
    local index = "field_edit_button_width"
    self.edit_button_width = KOR.registry:get(index)
    if not self.edit_button_width then
        self.edit_button_width = G_reader_settings:readSetting(index)
    end
    if self.edit_button_width then
        return
    end

    local measure_edit_button = self:getEditFieldButton(0)
    self.edit_button_width = measure_edit_button:getSize().w
    measure_edit_button:free()

    KOR.registry:set(index, self.edit_button_width)
    G_reader_settings:saveSetting(index, self.edit_button_width)
end

--- @private
function MultiInputDialog:generateCustomEditButton(field)
    if not field.custom_edit_button then
        return false
    end
    field.custom_edit_button = Button:new(field.custom_edit_button)

    local button_spacer_width = self.button_spacer:getSize().w
    self.field_width = self.field_width - field.custom_edit_button:getSize().w - button_spacer_width

    return true
end

--- @private
function MultiInputDialog:setFieldWidth(field_config)
    self.field_width = math_floor(self.width * 0.9)
    if self.fields_count > 1 then
        --! don't make this factor bigger, because then in some situations fields don't fit and jump to next row:
        local factor = 0.49
        self.field_width = math_floor(self.field_width * factor)
        if not self:generateCustomEditButton(field_config) and field_config.input_type ~= "number" then
            self.field_width = self.field_width - self.edit_button_width
        end

    --* make single row long field align with halved fields:
    elseif self.has_field_rows then
        self.field_width = math_floor(self.field_width * 1.045)
    end
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:fieldAddToInputs(field_config, field_side)

    self:setFieldWidth(field_config)
    self:setFieldProps(field_config, field_side)

    local field

    --* the field with computed autoheight will be inserted into the form in ((MultiInputDialog#insertComputedHeightField)):
    if field_config.height == "auto" then
        --! auto_height_field is the field of which the height is to be adapted, in ((MultiInputDialog#adaptMiddleContainerHeight)):
        self.auto_height_field = KOR.tables:shallowCopy(self.field_config)
        --! we need this index to replace the temporary input field with the field with computed height:
        self.auto_height_field_index = #self.input_fields + 1
        self.auto_height_field_tab_index = #self.tab_fields + 1
        self.field_config.height = self.initial_auto_field_height
        field = InputText:new(self.field_config)
        table_insert(self.input_fields, field)
        self:fieldAddToCurrentTabFields(field)

        return field
    end

    -- #((set dropdown field width))
    local config = KOR.tables:shallowCopy(self.field_config)
    if field_config.dropdown_items then
        config.width = math_floor(self.screen_width * 0.6)
    end
    field = field_config.type == "checkbox" and CheckButton:new{
            text = field_config.text,
            type = "checkbox",
            checked = self.field_config.checked,
            parent = self,
            callback = self.field_config.callback,
        }
        or
    InputText:new(config)
    table_insert(self.input_fields, field)
    self:fieldAddToCurrentTabFields(field)
    if self.field_config.focused then
        --* sets the field to which scollbuttons etc. are coupled:
        self._input_widget = field
    end

    return field
end

--* these tab_fields are needed for applying focus in ((MultiInputDialog#focusFocusField)):
--- @private
function MultiInputDialog:fieldAddToCurrentTabFields(field)
    if not self.active_tab or (self.active_tab and self.active_tab == field.tab) then
        table_insert(self.tab_fields, field)
    end
end

--* compare ((MultiInputDialog#isFocusField)):
--- @private
function MultiInputDialog:focusFocusField()

    if not self.focus_field then
        self.focus_field = 1
    end

    --* self.focus_field:
    --* set by the caller and read in ((MultiInputDialog#isFocusField))
    --* or dynamically set there
    --* self.tab_fields were populated via ((MultiInputDialog#fieldAddToInputs)) > ((MultiInputDialog#fieldAddToCurrentTabFields)):
    count = #self.tab_fields
    for i = 1, count do
        self:onUnfocus(self.tab_fields[i])
    end
    --* for tabs > 1 focus_field set dynamically by ((MultiInputDialog#isFocusField)):
    self:onFocus(self.input_fields[self.focus_field])
end

--* compare ((MultiInputDialog#insertComputedHeightField)) > ((conditionally give auto height field focus)), where a computed height field might be given focus:
--* in case of self.focus_field being set, focus will be applied by ((MultiInputDialog#focusFocusField)):
--- @private
function MultiInputDialog:isFocusField(field, height, field_side)

    local input_field_to_be_added = #self.input_fields + 1
    local focus_added = false

    --* self.focus_field set by caller is only applicable for tab 1 being active:
    if self.active_tab == 1 and input_field_to_be_added == self.focus_field and not self.a_field_was_focussed then
        self.a_field_was_focussed = true
        focus_added = true

    elseif not self.active_tab and not self.a_field_was_focussed and field.focused then
        self.a_field_was_focussed = true
        focus_added = true
        self.focus_field = input_field_to_be_added
    end

    --* give focus to first left_side field or to auto height field:
    if
        (not self.a_field_was_focussed and height == "auto" and (not self.focus_field or self.focus_field == 1))
        or
        (self.active_tab and self.active_tab > 1 and field_side == LEFT_SIDE and not self.a_field_was_focussed)
    then
        self.a_field_was_focussed = true
        focus_added = true
        --* dynamically computed focus_field for tabs > 1:
        self.focus_field = input_field_to_be_added
    end

    return self.a_field_was_focussed
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:setFieldProps(field_config, field_side)

    local force_one_line = self.force_one_line_field or field_config.force_one_line_height
    local height = not field_config.height and force_one_line and self.one_line_height or field_config.height
    if height == "auto" then
        self.auto_height_field_present = true
    end
    if field_config.dropdown_items then
        field_config.allow_newline = false
        field_config.scroll = false
    end

    self.field_config = {
        value_index =
            field_config.field_nr,
        text =
            self:setFieldProp(field_config.text, ""),
        hint =
            self:setFieldProp(field_config.hint, ""),

        --* for checkboxes; see ((MultiInputDialog checkbox example)):
        checked =
            self:setFieldProp(field_config.checked == 1, false),
        callback =
            field_config.callback,
        type =
            field_config.type,
        description =
            field_config.description,
        dropdown_items =
            field_config.dropdown_items,
        dropdown_disable_immediate_commit =
            field_config.dropdown_disable_immediate_commit,
        --* this property was set from ((InformationManager#showAddDialog)) or ((InformationManager#showEditDialog)) and will be read in ((InputText#addChars)) > ((InputText#initTextBox)) and block snippet replacement there:
        is_snippet_dialog =
            self.is_snippet_dialog,
        info_popup_title =
            field_config.info_popup_title,
        info_popup_text =
            field_config.info_popup_text,
        tab =
            field_config.tab,
        --* e.g. used to insert a button for setting xray_type of an Xray item in ((XrayFormsData#getFormFields)):
        custom_edit_button =
            field_config.custom_edit_button,
        disable_paste =
            self:setFieldProp(field_config.disable_paste, false),
        left_side =
            self:setFieldProp(field_config.left_side, false),
        right_side =
            self:setFieldProp(field_config.right_side, false),
        width =
            self:setFieldProp(field_config.width, self.field_width),
        height =
            height,
        -- #((force one line field height))
        force_one_line =
            force_one_line,
        allow_newline =
            field_config.allow_newline,
        cursor_at_end =
            field_config.cursor_at_end == true,
        top_line_num =
            self:setFieldProp(field_config.top_line_num, 1),
        is_adaptable =
            self:setFieldProp(field_config.is_adaptable, false),
        input_type =
            self:setFieldProp(field_config.input_type, "string"),
        text_type =
            field_config.text_type,
        face =
            self:setFieldProp(field_config.input_face, self.input_face),
        --* this prop is used by InputText:
        focused =
            self:isFocusField(field_config, height, field_side),
        scroll =
            field_config.scroll,
        scroll_by_pan =
            self:setFieldProp(field_config.scroll_by_pan, false),
        parent =
            self,
        padding =
            field_config.padding,
        margin =
            field_config.info_popup_text and 0 or field_config.margin,

        --* allow these to be specified per field if needed
        alignment =
            self:setFieldProp(field_config.alignment, self.alignment),
        justified =
            self:setFieldProp(field_config.justified, self.justified),
        lang =
            self:setFieldProp(field_config.lang, self.lang),
        para_direction_rtl =
            self:setFieldProp(field_config.para_direction_rtl, self.para_direction_rtl),
        auto_para_direction =
            self:setFieldProp(field_config.auto_para_direction, self.auto_para_direction),
        alignment_strict =
            self:setFieldProp(field_config.alignment_strict, self.alignment_strict),
    }
end

--- @private
function MultiInputDialog:insertIntoTargetContainer(group, is_field)
    if is_field and self.auto_height_field_present and not self.auto_height_field_injected then
        self.auto_height_field_injected = true
        return
    end
    if self.auto_height_field and self.auto_height_field_injected then
        table_insert(self.BottomContainer, group)
    else
        table_insert(self.TopContainer, group)
    end
end

--* compare ((MultiInputDialog#insertTwoFieldRow)):
--- @private
function MultiInputDialog:insertSingleFieldRow(field_config)

    --- @type InputDialog parent
    local parent = self

    if self.force_one_line_field then
        field_config.scroll = true
    end
    local field = self:fieldAddToInputs(field_config, LEFT_SIDE)
    local field_height = field:getSize().h

    if field_config.dropdown_items then
        local dropdown_button, reset_button = parent:getDropdownButtons(field, field_config)
        field = CenterContainer:new{
            dimen = Geom:new{
                w = self.full_width,
                h = field_height,
            },
            VerticalGroup:new{
                VerticalSpan:new{
                    width = math_floor(self.screen_height * 0.6),
                },
                HorizontalGroup:new{
                    self.button_spacer,
                    self.button_spacer,
                    --* width of this field was set in ((set dropdown field width)):
                    field,
                    dropdown_button,
                    self.button_spacer,
                    reset_button,
                }
            }
        }
    end

    if field_config.description then
        local desc_container = self:getDescriptionContainer(field, field_config)
        self:insertIntoTargetContainer(HorizontalGroup:new(desc_container))
    end

    local group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = field_height,
        },
        field,
    }
    self:insertIntoTargetContainer(group, "is_field")
end

--* compare ((MultiInputDialog#insertSingleFieldRow)):
--- @private
function MultiInputDialog:insertTwoFieldRow(row)
    local desc_containers = {}
    local field_containers = {}
    local field_config
    local has_descriptions = row[1].description
    local field
    for field_side = 1, 2 do
        --* here we get the field_config per field in the row:
        field_config = row[field_side]
        if self.force_one_line_field then
            field_config.scroll = true
        end
        field = self:fieldAddToInputs(field_config, field_side)
        if field_config.is_edit_button_target then
            KOR.registry:set("edit_button_target", field)
        end
        if has_descriptions then
            desc_containers[field_side] = self:getDescriptionContainer(field, field_config)
        end
        field_containers[field_side] = self:getFieldContainer(field, field_config)
    end

    if has_descriptions then
        self:insertIntoTargetContainer(HorizontalGroup:new(desc_containers))
    end

    -- #((field edit buttons for two field rows))
    local group = HorizontalGroup:new{
        align = "center",
        field_containers[1],
        field_containers[2],
    }
    self:insertIntoTargetContainer(group)
end

--- @private
function MultiInputDialog:getDescriptionContainer(field, field_config)
    local tile_width = self.full_width / self.fields_count
    local description_label = self:getDescription(field, field_config, tile_width)
    local description = FrameContainer:new{
        padding = self.description_padding,
        margin = 0,
        bordersize = 0,
        --* description in a multiple field row:
        description_label,
    }
    return LeftContainer:new{
        dimen = Geom:new{
            w = tile_width,
            h = description:getSize().h,
        },
        description,
    }
end

--* compare ((InputDialog#getDropdownButtons)) for a comparable way of attaching callbacks to fields:
--- @private
function MultiInputDialog:getDescription(field, field_config, width)
    --* limit width of popup info dialog:
    if width >= self.screen_width - 20 then
        width = math_floor(self.screen_width * 0.6)
    end
    local text = field_config.info_popup_text and
        Button:new{
        text_icon = {
            text = self.description_prefix .. " " .. field_config.description .. " ",
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
            self:onSwitchFocus(field)
                --* info_popup_title and info_popup_text e.g. defined in ((XrayFormsData#getFormFields)):
            KOR.dialogs:niceAlert(field_config.info_popup_title, field_config.info_popup_text, {
                width = width,
                --* otherwise dialog might remain partly visible, overlapping the keyboard, after closing the dialog:
                move_to_top = true,
            })
        end,
    }
    or
    TextBoxWidget:new{
        text = self.description_prefix .. (field_config.description or ""),
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
function MultiInputDialog:getFieldContainer(field, field_config)
    local tile_width = self.full_width / self.fields_count
    local tile_height = field:getSize().h
    local has_no_button = (field.input_type == "number" and not field.custom_edit_button) or field_config.type == "checkbox"

    if field_config.dropdown_items then
        local dropdown_button, reset_button = self:getDropdownButtons(field, field_config)
        field = HorizontalGroup:new{
            field,
            dropdown_button,
            reset_button
        }
    end

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
    --* handling example: ((XrayButtons#forItemEditorTypeSwitch)) > ((XrayDialogs#modifyXrayTypeFieldValue))
    -- #((configure custom edit button))
    if field.custom_edit_button then

        self.custom_edit_button = field.custom_edit_button
        KOR.registry:set("xray_type_button", self.custom_edit_button)
        -- for focus switch in ((XrayButtons#forItemEditorTypeSwitch)):
        KOR.registry:set("xray_type_focusser", {
            parent = self,
            field = field,
        })

        return CenterContainer:new{
            dimen = Geom:new{
                w = tile_width,
                h = tile_height,
            },
            HorizontalGroup:new{
                align = "center",
                field,
                self.button_spacer,
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
                self:onSwitchFocus(field)
            end)
        end,
    }
end

--- @private
function MultiInputDialog:insertButtonGroup()
    table_insert(self.BottomContainer, self.field_spacer)
    self.button_table_height = self.button_table:getSize().h
    self.button_group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = self.button_table_height,
        },
        self.button_table,
    }
    table_insert(self.BottomContainer, self.button_group)
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

    --! init base class:
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
    self.input_face = self.input_face or Font:getDefaultInputFontFace()
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
    table_insert(self.MiddleContainer, VerticalSpan:new{ width = difference })
end

--- @private
function MultiInputDialog:insertComputedHeightField(difference)

    --* self.auto_height_field will be set in ((MultiInputDialog#fieldAddToInputs)), when a field there has height = "auto":
    if not self.auto_height_field or self.input_fields[self.auto_height_field_index].tab ~= self.active_tab then
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
    KOR.registry:set("edit_button_target", field)

    -- #((conditionally give auto height field focus))
    if self.focus_field == self.auto_height_field_index then
        --! force the computed auto field to really have focus behavior):
        self._input_widget = field
    end

    self.input_fields[self.auto_height_field_index] = field
    --! this is also very important for correct behavior in ((MultiInputDialog#onSwitchFocus)), which would otherwise in the loop there reference a no longer existing, replaced field:
    self.tab_fields[self.auto_height_field_tab_index] = field

    local group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = difference,
        },
        field,
    }
    table_insert(self.MiddleContainer, self.field_spacer)
    table_insert(self.MiddleContainer, group)
    table_insert(self.MiddleContainer, self.field_spacer)

    return true
end

--- @private
function MultiInputDialog:initSpacers()
    self.button_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(4),
    }
end

--- @private
function MultiInputDialog:insertRows()
    count = #self.fields
    self:setFieldEditButtonWidth()
    for row_nr = 1, count do
        self:insertFieldRowIfActiveTab(row_nr)
    end
end

--- @private
function MultiInputDialog:insertFooterDescription()
    if not self.footer_description then
        return
    end
    local width = math_floor(0.9 * self.width)
    local group = TextBoxWidget:new{
        text = self.footer_description,
        face = Font:getFace("x_smallinfofont", 11),
        alignment = "left",
        width = width,
    }
    local height = group:getSize().h
    table_insert(self.TopContainer, CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = height
        },
        group,
    })
end

--- @private
function MultiInputDialog:insertTopPadding()
    if not self.top_paddings_tabs or not self.top_paddings_tabs:match(self.active_tab) then
        return
    end

    local vertical_span = VerticalSpan:new{
        width = Size.padding.default,
    }
    --* insert the padding right after the titlebar:
    table_insert(self.TopContainer, 2, vertical_span)
end

--- @private
function MultiInputDialog:insertFieldRowIfActiveTab(row_nr)
    local target_tab
    local row = self.fields[row_nr]
    local is_field_set = not row.text
    self:registerFieldValues(row, is_field_set)
    target_tab = self.active_tab and ((is_field_set and row[1] and row[1].tab) or row.tab)

    --* only administrate for fields in inactive tabs, don't generate them:
    if self.active_tab and target_tab ~= self.active_tab then
        if is_field_set then
            self.field_nr = self.field_nr + #row
        else
            self.field_nr = self.field_nr + 1
        end

    --* only insert fields for when they are in a non tabbed dialog or are in the active tab:
    elseif not target_tab or target_tab == self.active_tab then
        self:generateRows(row, is_field_set)
    end
end

--- @private
function MultiInputDialog:registerFieldValues(row, is_field_set)
    local value
    if self.has_field_rows and is_field_set then
        count2 = #row
        for field = 1, count2 do
            --* value will be set to "" if the field is in an inactive tab:
            --* for storage in the database these empty texts will be set to nil in ((XrayDataSaver#setEmptyPropsToNil)):
            value = row[field].text or ""
            table_insert(self.field_values, value)
        end
        return
    end
    --* value will be set to "" if the field is in an inactive tab:
    value = row.text or ""
    table_insert(self.field_values, value)
end

--- @protected
function MultiInputDialog:buildWidget()
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

--! crucial method to prevent contamination of field values with the values of an older/previous MultiInputDialog instances:
function MultiInputDialog:resetRegistryValues()
    self.input_fields = {}
    self.field_values = {}
    self.tab_fields = {}
    KOR.registry:unset("field_edit_button_width", "edit_button_target", "xray_type_button", "xray_type_focusser", self.input_registry)
end

--- @private
function MultiInputDialog:setFieldProp(prop, default_value)
    return prop or default_value
end

return MultiInputDialog
