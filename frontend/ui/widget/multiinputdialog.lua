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
                -- input_type = nil, -- default for text
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
                        -- do something
                    end
                },
                {
                    text = _("Use settings"),
                    callback = function(touchmenu_instance)
                        local fields = sample_input:getFields()
                        -- check for user input
                        if fields[1] ~= "" and fields[2] ~= ""
                            and fields[3] ~= 0 then
                            -- insert code here
                            UIManager:close(sample_input)
                            -- If we have a touch menu: Update menu entries,
                            -- when called from a menu
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        else
                            -- not all fields where entered
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


local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
-- ! use KOR.dialogs instead of Dialogs!
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local KOR = require("extensions/kor")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Registry = require("extensions/registry")
local ScreenHelpers = require("extensions/screenhelpers")
local Size = require("ui/size")
local System = require("extensions/system")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

--- @class MultiInputDialog
local MultiInputDialog = InputDialog:extend{
    bottom_v_padding = Size.padding.small,
    description_padding = Size.padding.small,
    description_margin = Size.margin.small,
    fields = nil, -- array, mandatory
    has_field_rows = false,
    input_fields = nil, -- array
    description_face = nil,
    --[[is_popout = false,
    is_borderless = true,
    fullscreen = true,]]
    input_face = Font:getFace("x_smallinfofont"),
    description_face = Font:getFace("x_smallinfofont"),
    description_prefix = "  ",
    -- leave this prop alone, because consumed by inputdialog:
    title_tab_buttons = nil,
    title_tab_callbacks = nil,
    field_values = {},
    input_registry = nil,
    initial_auto_field_height = 10,
    one_line_height = Registry.is_ubuntu_device and 20 or 30,
}

function MultiInputDialog:init()
    -- init title and buttons in base class
    -- ! don't call free() on MeasureData, because otherwise no title bar text!:
    local VerticalGroupData, MeasureData
    InputDialog.init(self)
    if self.title and self.title_bar then
        VerticalGroupData = VerticalGroup:new{
            align = "left",
            self.title_bar,
        }
        MeasureData = VerticalGroup:new{
            align = "left",
            self.title_bar,
        }
    else
        VerticalGroupData = VerticalGroup:new{
            align = "left",
        }
        MeasureData = VerticalGroup:new{
            align = "left",
        }
    end

    -- don't use halved input fields in portrait display:
    if ScreenHelpers:isPortraitScreen() then
        self.has_field_rows = false
    end

    self.input_fields = {}
    self.input_description = {}
    -- info: SmartScripts: for some reason (maybe because of InputDialog.init above?) we have to force the font here:
    local input_face = self.input_face or Font:getFace("x_smallinfofont")

    Registry:unset("edit_button_target")
    local full_width = self.title_bar and self.title_bar:getSize().w or self.width
    self.full_width = full_width
    self.auto_height_field_present = false
    self.auto_field_height = nil
    local screen_height = Screen:getHeight()
    local screen_width = Screen:getWidth()
    local max_dialog_height = screen_height - KOR.dialogs:getKeyboardHeight()
    self.button_table_height = self.button_table:getSize().h
    self.button_group = CenterContainer:new{
        dimen = Geom:new{
            w = full_width,
            h = self.button_table_height,
        },
        self.button_table,
    }
    -- Add same vertical space after as before InputText
    local bottom_group = CenterContainer:new{
        dimen = Geom:new{
            w = full_width,
            h = self.description_padding + self.description_margin,
        },
        VerticalSpan:new{ width = self.description_padding + self.description_margin },
    }
    self.a_field_was_focussed = false
    for x = 1, 2 do
        -- MeasureData can be used to compute height of auto-height fields to be inserted in VerticalGroupData:
        local data_group = x == 1 and MeasureData or VerticalGroupData
        local is_resulting_form = x == 2

        -- very important: for the second loop for the production form reset all props for the actual fields:
        self.field_nr = 0
        self.field_values = {}
        self.input_fields = {}
        -- to make the FocusManager work correctly, even under Ubuntu; this prop will be initially set by ((MultiInputDialog#injectFieldRow)) and will upon switching between fields be dynamically updated to the active field by ((MultiInputDialog#onSwitchFocus)):
        self._input_widget = nil

        if is_resulting_form and self.auto_height_field_present then
            local current_height = MeasureData:getSize().h
            local difference = max_dialog_height - current_height
            -- don't know why we need this correction:
            local correction = Registry.is_ubuntu_device and 15 or 42
            self.auto_field_height = self.initial_auto_field_height + difference + correction
        end

        for row_nr, row in ipairs(self.fields) do
            local is_field_set = not row.text
            if self.has_field_rows and is_field_set then
                for field = 1, #row do
                    table.insert(self.field_values, row[field].text)
                end
            else
                table.insert(self.field_values, row.text)
            end
            local target_tab = self.active_tab and ((is_field_set and row[1] and row[1].tab) or row.tab)
            if self.active_tab and target_tab < self.active_tab then
                if is_field_set then
                    self.field_nr = self.field_nr + #row
                else
                    self.field_nr = self.field_nr + 1
                end

            elseif not target_tab or target_tab == self.active_tab then
                self.garbage = row_nr
                self.field_nr = self.field_nr + 1
                self:injectFieldRow(data_group, row, is_field_set, input_face, x)
            end
        end
        if x == 1 then
            table.insert(MeasureData, bottom_group)
            if self.auto_height_field_present then
                table.insert(MeasureData, self.button_group)
            end
        end
    end

    self:storeInputFieldsInRegistry()

    if not self.auto_height_field_present then
        table.insert(MeasureData, bottom_group)
    end
    table.insert(VerticalGroupData, bottom_group)
    self:insertButtonGroupWithHeightCorrection(VerticalGroupData, MeasureData, max_dialog_height)

    local config = {
        radius = self.fullscreen and 0 or Size.radius.window,
        bordersize = self.fullscreen and 0 or Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroupData,
    }
    if self.fullscreen then
        config.width = screen_width
        config.covers_fullscreen = true
        config.x = 0
        config.y = 0
        config.height = max_dialog_height
    end
    self.dialog_frame = FrameContainer:new(config)

    if self.fullscreen then
        self[1] = self.dialog_frame
    else
        self[1] = CenterContainer:new{
            dimen = Geom:new{
                w = screen_width,
                h = config.height or screen_height - self._input_widget:getKeyboardDimen().h,
            },
            ignore_if_over = "height",
            self.dialog_frame,
        }
    end

    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

--- Returns an array of our input field's *text* field.
function MultiInputDialog:getFields()
    local field_values = {}
    for i, field in ipairs(self.input_fields) do
        table.insert(field_values, field:getText())
        self.garbage = i
    end
    return field_values
end

function MultiInputDialog:getValues()
    for i, field in ipairs(self.input_fields) do
        local value_index = field.value_index
        self.field_values[value_index] = field:getText()
        self.garbage = i
    end
    local values = {}
    for i, value in ipairs(self.field_values) do
        table.insert(values, value)
        self.garbage = i
    end
    return values
end

--- BEWARE: Live ref to an internal component!
function MultiInputDialog:getRawFields()
    return self.input_fields
end

function MultiInputDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self._input_widget:unfocus()
    self._input_widget:onCloseKeyboard()
    UIManager:setDirty(nil, function()
        return "ui", self.dialog_frame.dimen
    end)

    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
end

-- ================= ADDED ======================

-- DataGroup can be MeasureData or VerticalGroupData; MeasureData can be used to compute height of auto-height fields to be inserted in VerticalGroupData:
function MultiInputDialog:injectFieldRow(DataGroup, field_source, is_field_row, input_face, loop_round)

    local force_one_line_field = is_field_row
    local halved_descriptions = {}
    local halved_fields = {}

    local fields = is_field_row and #field_source or 1
    for i = 1, fields do
        local field = is_field_row and field_source[i] or field_source
        if force_one_line_field then
            field.scroll = true
        end
        if i == 2 then
            -- self.field_nr counts ALL fields, even those in different tabs:
            self.field_nr = self.field_nr + 1
        end
        local width = math.floor(self.width * 0.9)
        if fields > 1 then
            width = math.floor(width * 0.49)

        -- make single row long field align with halved fields:
        elseif self.has_field_rows then
            width = math.floor(width * 1.045)
        end

        local force_one_line = force_one_line_field or field.force_one_line_height
        local height = not field.height and force_one_line and self.one_line_height or field.height
        if height == "auto" and self.auto_field_height then
            height = self.auto_field_height
        elseif height == "auto" then
            height = self.initial_auto_field_height
            self.auto_height_field_present = true
        end

        local is_focus_field = false
        if i == 1 and not self.a_field_was_focussed and loop_round == 2 then
            self.a_field_was_focussed = true
            is_focus_field = true
        end
        local field_config = {
            value_index = self.field_nr,

            text = field.text or "",
            hint = field.hint or "",
            description = field.description,
            info_popup_text = field.info_popup_text,
            -- this can be used to give the field with the dscription focus upon clicking on its info_popup_text label; see ((focus field upon click on info label)):
            info_icon_field_no = #self.input_fields + 1,
            tab = field.tab,
            disable_paste = field.disable_paste or false,
            left_side = field.left_side or false,
            right_side = field.right_side or false,
            width = field.width or width,
            -- #((force one line field height))
            height = height,
            force_one_line = force_one_line,
            allow_newline = field.allow_newline or false,
            cursor_at_end = field.cursor_at_end == true,
            top_line_num = field.top_line_num or 1,
            is_adaptable = field.is_adaptable or false,

            input_type = field.input_type or "string",
            text_type = field.text_type,
            face = field.input_face or input_face,
            focused = is_focus_field,
            scroll = field.scroll or false,
            scroll_by_pan = field.scroll_by_pan or false,
            parent = self,
            padding = field.padding,
            margin = field.info_popup_text and 0 or field.margin,
            -- Allow these to be specified per field if needed
            alignment = field.alignment or self.alignment,
            justified = field.justified or self.justified,
            lang = field.lang or self.lang,
            para_direction_rtl = field.para_direction_rtl or self.para_direction_rtl,
            auto_para_direction = field.auto_para_direction or self.auto_para_direction,
            alignment_strict = field.alignment_strict or self.alignment_strict,
        }
        table.insert(self.input_fields, InputText:new(field_config))

        local active_field = #self.input_fields

        if fields > 1 then
            table.insert(halved_fields, self.input_fields[active_field])
        end
        if field.is_edit_button_target then
            Registry:set("edit_button_target", self.input_fields[active_field])
        end
        if not self._input_widget then
            -- sets the field to which scollbuttons etc. are coupled:
            self._input_widget = self.input_fields[active_field]
        end

        local field_height = self.input_fields[active_field]:getSize().h

        -- for single field rows:
        if (not self.has_field_rows and field.description) or (fields == 1 and field.description) then
            local description_height
            self.input_description[active_field], description_height = self:getDescription(field, math.floor(self.width * 0.9))
            local group = LeftContainer:new{
                dimen = Geom:new{
                    w = self.full_width,
                    h = description_height,
                },
                self.input_description[active_field],
            }
            table.insert(DataGroup, group)

        -- for rows with more than one field and no descriptions: when no title bar present, add some extra margin above the fields:
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

        -- for one field rows immediately insert the input field:
        if not self.has_field_rows or fields == 1 then
            local group = CenterContainer:new{
                dimen = Geom:new{
                    w = self.full_width,
                    h = field_height,
                },
                self.input_fields[active_field],
            }
            table.insert(DataGroup, group)

        -- handle rows with multipe fields:
        elseif self.has_field_rows and fields > 1 then

            local tile_width = self.full_width / fields

            local has_description = self.input_fields[active_field].description
            local description_label = has_description and self:getDescription(self.input_fields[active_field], tile_width) or nil
            if i == 1 then
                if has_description then

                    self.input_description[active_field] = FrameContainer:new{
                        padding = self.description_padding,
                        margin = 0,
                        bordersize = 0,
                        -- description in a multiple field row:
                        description_label,
                    }
                    table.insert(halved_descriptions, LeftContainer:new{
                        dimen = Geom:new{
                            w = tile_width,
                            h = self.input_description[active_field]:getSize().h,
                        },
                        self.input_description[active_field],
                    })
                end
            end

            -- insert right side field:
            if i == 2 and has_description then
                self.input_description[active_field] = FrameContainer:new{
                    padding = self.description_padding,
                    margin = 0,
                    bordersize = 0,
                    description_label,
                }
                table.insert(halved_descriptions, LeftContainer:new{
                    dimen = Geom:new{
                        w = tile_width,
                        h = self.input_description[active_field]:getSize().h,
                    },
                    self.input_description[active_field],
                })
            end
        end
    end
    if #halved_descriptions > 0 or #halved_fields > 0 then
        local tile_width = self.full_width / fields
        local tile_height = halved_fields[1]:getSize().h

        if #halved_descriptions > 0 then
            halved_descriptions.align = "center"
            table.insert(DataGroup, HorizontalGroup:new(halved_descriptions))
        end
        local group = HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{
                    w = tile_width,
                    h = tile_height,
                },
                -- left side field:
                halved_fields[1],
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = tile_width,
                    h = tile_height,
                },
                -- right_side field:
                halved_fields[2],
            },
        }
        table.insert(DataGroup, group)
    end
end

function MultiInputDialog:getDescription(field, width)
    local text = field.info_popup_text and
    Button:new{
        icon = "info",
        padding = 0,
        margin = 0,
        text_font_bold = false,
        align = "left",
        bordersize = 0,
        width = width,
        -- y_pos detected and set in ((Button#onTapSelectButton)) - look for two statements with self.callback(pos):
        -- via ((Dialogs#alertInfo)) these pos data will be consumed in ((move InfoMessage to y pos)) > ((ScreenHelpers#moveMovableToYpos)):
        callback = function(y_pos)
            -- #((focus field upon click on info label))
            -- this prop can be set in ((MultiInputDialog#injectFieldRow)):
            if field.info_icon_field_no then
                self:onSwitchFocus(self.input_fields[field.info_icon_field_no])
            end
            System:nextTick(function()
                KOR.dialogs:alertInfo("\n" .. field.info_popup_text .. "\n", nil, nil, y_pos)
            end)
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

function MultiInputDialog:insertButtonGroupWithHeightCorrection(VerticalGroupData, MeasureData, max_dialog_height)

    if not self.auto_height_field_present then
        table.insert(MeasureData, self.button_group)
        -- apply height correction if needed:
        local difference = max_dialog_height - MeasureData:getSize().h
        -- free memory (don't use MeasureData:free() for that, because then no titlebar text!):
        MeasureData = VerticalGroupData
        if difference > 0 then
            local correction = self.is_ubuntu_device and 50 or 18
            table.insert(VerticalGroupData, CenterContainer:new{
                dimen = Geom:new{
                    w = self.full_width,
                    h = difference + correction,
                },
                VerticalSpan:new{ width = self.full_width },
            })
        end
    end

    table.insert(VerticalGroupData, self.button_group)
end

function MultiInputDialog:storeInputFieldsInRegistry()
    if self.input_registry then
        Registry:set(self.input_registry, self.input_fields)
    end
end

return MultiInputDialog
