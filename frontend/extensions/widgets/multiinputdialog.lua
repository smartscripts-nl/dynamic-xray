--[[--
Widget for taking multiple user inputs.

Example for input of two strings and a number:

    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local @{ui.uimanager|UIManager} = require("ui/uimanager")
    local @{gettext|_} = require("gettext")

    local sample_input
    sample_input = MultiInputDialog:new{
        title = _("Title to show"),
        fields = {
            {
                description = _("Describe this field"),
                -- input_type = nil, --* default for text
                text = _("First input"),
                hint = _("Name"),
            },
            {
                text = "",
                hint = _("Address"),
            },
            {
                description = _("Enter a number"),
                input_type = "number",
                text = 666,
                hint = 123,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(sample_input)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        --* do something
                    end
                },
                {
                    text = _("Use settings"),
                    callback = function(touchmenu_instance)
                        local fields = sample_input:getFields()
                        --* check for user input
                        if fields[1] ~= "" and fields[2] ~= ""
                            and fields[3] ~= 0 then
                            --* insert code here
                            UIManager:close(sample_input)
                            --* If we have a touch menu: Update menu entries,
                            --* when called from a menu
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        else
                            --* not all fields where entered
                        end
                    end
                },
            },
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()


It is strongly recommended to use a text describing the action to be
executed, as demonstrated in the example above. If the resulting phrase would be
longer than three words it should just read "OK".
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

--* if we extend FocusManager here, then crash because of ((MultiInputDialog#init)) > InputDialog.init(self)
--- @class MultiInputDialog
local MultiInputDialog = InputDialog:extend{
    bottom_v_padding = Size.padding.small,
    description_face = Font:getDefaultDialogFontFace(),
    description_padding = Size.padding.small,
    description_prefix = "  ",
    description_margin = Size.margin.small,
    field_nr = 0,
    fields = nil, --* array, mandatory
    field_values = {},
    has_field_rows = false,
    initial_auto_field_height = 10,
    input_face = Font:getDefaultDialogFontFace(),
    input_fields = nil, --* array
    input_registry = nil,
    keyboard_height = nil,
    mobile_auto_height_correction = 15,
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
    self:initContainers()
    self:initWidgetProps()
    self:initBottomGroup()
    self:insertFieldsController()
    self:storeInputFieldsInRegistry()
    self:addButtons()
    self:finalizeWidgetMID()
    KOR.dialogs:registerWidget(self)
end

--- Returns an array of our input field's *text* field.
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
    UIManager:setDirty(nil, function()
        return "ui", self.dialog_frame.dimen
    end)

    --* focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
end

--* DataGroup can be MeasureData or VerticalGroupData; MeasureData can be used to compute height of auto-height fields to be inserted in VerticalGroupData:
--- @private
function MultiInputDialog:insertFieldRow(DataGroup, field_source, is_field_row)

    self.halved_descriptions = {}
    self.halved_fields = {}

    self.fields_count = is_field_row and #field_source or 1
    local has_two_fields_per_row = is_field_row and self.fields_count > 1
    self.edit_button_width = 0
    --* insert a edit button at the right side of each field in a two field row:
    if has_two_fields_per_row then
        local measure_edit_button = self:getEditButton(0)
        self.edit_button_width = measure_edit_button:getSize().w
        measure_edit_button:free()
    end
    for field_side = 1, self.fields_count do
        self:insertField(DataGroup, field_side, field_source, is_field_row)
    end
    --* self.halved_fields and self.halved_descriptions are reset to empty table after each row; see ((MultiInputDialog#insertFieldRow)):
    if #self.halved_descriptions > 0 or #self.halved_fields > 0 then
        local tile_width = self.full_width / self.fields_count
        local tile_height = self.halved_fields[1]:getSize().h

        if #self.halved_descriptions > 0 then
            self.halved_descriptions.align = "center"
            table.insert(DataGroup, HorizontalGroup:new(self.halved_descriptions))
        end
        local field_1 = self.halved_fields[1]
        local field_2 = self.halved_fields[2]
        local add_halved_field_edit_buttons = true
        local group

        if add_halved_field_edit_buttons then
            group = HorizontalGroup:new{
                align = "center",
                CenterContainer:new{
                    dimen = Geom:new{
                        w = tile_width,
                        h = tile_height,
                    },
                    --* left side field + button:
                    HorizontalGroup:new{
                        align = "center",
                        field_1,
                        self:getEditButton(field_1),
                    }
                },
                CenterContainer:new{
                    dimen = Geom:new{
                        w = tile_width,
                        h = tile_height,
                    },
                    --* right_side field + button:
                    HorizontalGroup:new{
                        field_2,
                        self:getEditButton(field_2),
                    }
                },
            }
        --* halved fields without edit buttons:
        else
            group = HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{
                    w = tile_width,
                    h = tile_height,
                },
                --* left side field:
                    field_1,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = tile_width,
                    h = tile_height,
                },
                --* right_side field:
                    field_2,
                },
            }
        end
        table.insert(DataGroup, group)
    end
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:insertField(DataGroup, field_side, field_source, is_field_row)

    self.force_one_line_field = is_field_row
    local field = is_field_row and field_source[field_side] or field_source
    if self.force_one_line_field then
        field.scroll = true
    end
    if field_side == 2 then
        --* self.field_nr counts ALL fields, even those in different tabs:
        self.field_nr = self.field_nr + 1
    end
    self:fieldAddToInputs(field, field_side)

    self.current_field = #self.input_fields

    --* self.fields_count is either 1 or 2 (for two field row):
    if self.fields_count > 1 then
        table.insert(self.halved_fields, self.input_fields[self.current_field])
    end
    if field.is_edit_button_target then
        KOR.registry:set("edit_button_target", self.input_fields[self.current_field])
    end
    if not self._input_widget then
        --* sets the field to which scollbuttons etc. are coupled:
        self._input_widget = self.input_fields[self.current_field]
    end

    self:insertFieldIntoDataGroup(DataGroup, field)
    self:insertFieldIntoRow(DataGroup, field_side)
end

--- @private
function MultiInputDialog:setFieldWidth()
    self.field_width = math.floor(self.width * 0.9)
    if self.fields_count > 1 then
        --! don't make this factor bigger, because then in some situations fields don't fit and jump to next row:
        local factor = 0.47
        self.field_width = math.floor(self.field_width * factor) - self.edit_button_width

        --* make single row long field align with halved fields:
        elseif self.has_field_rows then
            self.field_width = math.floor(self.field_width * 1.045)
        end
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:fieldAddToInputs(field, field_side)
    self:setFieldWidth()
    self:setFieldProps(field, field_side)
    table.insert(self.input_fields, InputText:new(self.field_config))
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:setFieldProps(field, field_side)
    local force_one_line = self.force_one_line_field or field.force_one_line_height
    local height = not field.height and force_one_line and self.one_line_height or field.height
    if height == "auto" and self.auto_field_height then
        height = self.auto_field_height
    elseif height == "auto" then
        height = self.initial_auto_field_height
        self.auto_height_field_present = true
    end

    local is_focus_field = false
    --* target container will be self.MeasureData if target_container == 1, or self.VerticalGroupData if target_container == 2:
    if field_side == 1 and not self.a_field_was_focussed and self.target_container == 2 then
        self.a_field_was_focussed = true
        is_focus_field = true
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
        focused =
            is_focus_field,
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
function MultiInputDialog:insertFieldIntoDataGroup(DataGroup, field)
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
            table.insert(DataGroup, group)

            --* for rows with more than one field and no descriptions: when no title bar present, add some extra margin above the fields:
        elseif not self.title then
            local group = CenterContainer:new{
                dimen = Geom:new{
                    w = self.full_width,
                    h = 2 * self.description_margin,
                },
                VerticalSpan:new{ width = self.description_padding + self.description_margin },
            }
            table.insert(DataGroup, group)
        end
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:insertFieldIntoRow(DataGroup, field_side)
    --* for one field rows immediately insert the input field:
    if not self.has_field_rows or self.fields_count == 1 then
        self:insertSingleFieldInRow(DataGroup)

    --* handle rows with multipe fields:
    elseif self.has_field_rows and self.fields_count > 1 then
        self:insertDuoFieldsInRow(field_side)
    end
end

--- @private
function MultiInputDialog:insertSingleFieldInRow(DataGroup)
    local field_height = self.input_fields[self.current_field]:getSize().h
    local group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = field_height,
        },
        self.input_fields[self.current_field],
    }
    table.insert(DataGroup, group)
end

--- @private
--- @param field_side number 1 if left side, 2 if right side
function MultiInputDialog:insertDuoFieldsInRow(field_side)
    local tile_width = self.full_width / self.fields_count

    local has_description = self.input_fields[self.current_field].description
    local description_label = has_description and self:getDescription(self.input_fields[self.current_field], tile_width) or nil
    if field_side == 1 then
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

    --* insert right side field:
    if field_side == 2 and has_description then
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
                    icon = "info",
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
                    --* this prop can be set in ((MultiInputDialog#insertFieldRow)):
                    if field.info_icon_field_no then
                        self:onSwitchFocus(self.input_fields[field.info_icon_field_no])
                    end
                    --* info_popup_title and info_popup_text e.g. defined in ((XrayDialogs#getFormFields)):
                    KOR.dialogs:niceAlert(field.info_popup_title, field.info_popup_text)
                end,
            }
            or TextBoxWidget:new{
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
    local label_height = label:getSize().h

    return label, label_height
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
function MultiInputDialog:getEditButton(field)
    return Button:new{
        icon = "edit",
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

    --* in case of a tab with a field with auto height, the computed height of that field will push the button_table down to just above the keyboard; if no such field is present, we need this spacer to get the same effect:
    if DX.s.editor_vertical_align_buttontable and not self.auto_height_field_present then
        table.insert(self.MeasureData, self.button_group)
        --* apply height correction if needed:
        local difference = self.max_dialog_height - self.MeasureData:getSize().h
        --* free memory (don't use MeasureData:free() for that, because then no titlebar text!):
        self.MeasureData = self.VerticalGroupData
        if difference > 0 then
            table.insert(self.VerticalGroupData, CenterContainer:new{
                dimen = Geom:new{
                    w = self.full_width,
                    h = difference,
                },
                VerticalSpan:new{ width = self.full_width },
            })
        end
    end
    --* add some padding above the button_group:
    table.insert(self.VerticalGroupData, VerticalSpan:new{ width = 10 })
    table.insert(self.VerticalGroupData, self.button_group)
end

--- @private
function MultiInputDialog:storeInputFieldsInRegistry()
    if self.input_registry then
        --* input_fields were populated in ((MultiInputDialog#fieldAddToInputs)):
        KOR.registry:set(self.input_registry, self.input_fields)
    end
end

--- @private
function MultiInputDialog:initContainers()
    --! don't call free() on self.MeasureData, because otherwise no title bar text!:
    InputDialog.init(self)
    if self.title and self.title_bar then
        self.VerticalGroupData = VerticalGroup:new{
            align = "left",
            self.title_bar,
        }
        self.MeasureData = VerticalGroup:new{
            align = "left",
            self.title_bar,
        }
        return
    end

    self.VerticalGroupData = VerticalGroup:new{
        align = "left",
    }
    self.MeasureData = VerticalGroup:new{
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
    --[[if self.fullscreen then
        local vertical_elements = 0
        if self.description then
            vertical_elements = vertical_elements + 1
        end
        if self.has_field_rows then
            vertical_elements = vertical_elements + #self.fields / 2
        else
            vertical_elements = vertical_elements + #self.fields
        end
        vertical_elements = math.ceil(vertical_elements)
        input_face = vertical_elements == 5 and Registry.default_dialog_font or Font:getDefaultDialogFontFace() or Font:getDefaultDialogFontFace(4)
    else
        input_face = Font:getDefaultDialogFontFace(4)
    end]]

    KOR.registry:unset("edit_button_target")
    self.full_width = self.title_bar and self.title_bar:getSize().w or self.width
    self.auto_height_field_present = false
    self.auto_field_height = nil
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
    --* keyboard was initialised in ((InputText#initKeyboard)):
    self.keyboard_height = self._input_widget:getKeyboardDimen().h
    KOR.registry:set("keyboard_height", self.keyboard_height)
    self.max_dialog_height = self.screen_height - self.keyboard_height
end

--- @private
function MultiInputDialog:initBottomGroup()
    self.button_table_height = self.button_table:getSize().h
    self.button_group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = self.button_table_height,
        },
        self.button_table,
    }
    --* Add same vertical space after as before InputText
    self.bottom_group = CenterContainer:new{
        dimen = Geom:new{
            w = self.full_width,
            h = self.description_padding + self.description_margin,
        },
        VerticalSpan:new{ width = self.description_padding + self.description_margin },
    }
end

--- @private
function MultiInputDialog:insertFieldsController()
    self.a_field_was_focussed = false
    for x = 1, 2 do
        --* target container will be self.MeasureData if target_container == 1, or self.VerticalGroupData if target_container == 2:
        self.target_container = x

        --* very important: for the second loop for the production form reset all props for the actual fields:
        self.field_nr = 0
        self.field_values = {}
        self.input_fields = {}
        self:insertMeasurementOrProductionFields()
    end
end

--- @private
function MultiInputDialog:insertMeasurementOrProductionFields()
    --* target container will be self.MeasureData if target_container == 1, or self.VerticalGroupData if target_container == 2:
    --* MeasureData can be used to compute height of auto-height fields to be inserted in VerticalGroupData:
    local is_resulting_form = self.target_container == 2

    --* to make the FocusManager work correctly, even under Ubuntu; this prop will be initially set by ((MultiInputDialog#insertFieldRow)) and will upon switching between fields be dynamically updated to the active field by ((MultiInputDialog#onSwitchFocus)):
    self._input_widget = nil

    if is_resulting_form and self.auto_height_field_present then
        local current_height = self.MeasureData:getSize().h
        local difference = self.max_dialog_height - current_height
        --? don't know why we need this correction:
        local correction = DX.s.is_ubuntu and 0 or 42
        self.auto_field_height = self.initial_auto_field_height + difference + correction
        if DX.s.is_mobile_device then
            self.auto_field_height = self.auto_field_height - self.mobile_auto_height_correction
        end
    end

    count = #self.fields
    for row_nr = 1, count do
        self:insertFieldRowController(row_nr)
    end
    --* target container will be self.MeasureData if target_container == 1, or self.VerticalGroupData if target_container == 2:
    if self.target_container == 1 then
        table.insert(self.MeasureData, self.bottom_group)
        if self.auto_height_field_present then
            table.insert(self.MeasureData, self.button_group)
        end
    end
end

--- @private
function MultiInputDialog:insertFieldRowController(row_nr)
    local target_tab
    local data_group = self.target_container == 1 and self.MeasureData or self.VerticalGroupData

    local row = self.fields[row_nr]
    local is_field_set = not row.text
    self:insertFieldValues(row, is_field_set)
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
        self:insertFieldRow(data_group, row, is_field_set)
    end
end

--- @private
function MultiInputDialog:insertFieldValues(row, is_field_set)
    if self.has_field_rows and is_field_set then
        local count2 = #row
        for field = 1, count2 do
            table.insert(self.field_values, row[field].text)
        end
        return
    end

    table.insert(self.field_values, row.text)
end

--- @private
function MultiInputDialog:addButtons()
    if not self.auto_height_field_present then
        table.insert(self.MeasureData, self.bottom_group)
    end
    table.insert(self.VerticalGroupData, self.bottom_group)
    self:insertButtonGroup()
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
        self.VerticalGroupData,
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

    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

--- @private
function MultiInputDialog:setFieldProp(prop, default_value)
    return prop or default_value
end

return MultiInputDialog
