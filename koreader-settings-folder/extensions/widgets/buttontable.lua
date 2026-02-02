
local require = require

local Button = require("extensions/widgets/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local Size = require("extensions/modules/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Geom = require("ui/geometry")
local Screen = Device.screen

local math = math
local table_insert = table.insert

--* compare ((ButtonTableFactory)) for easy construction of horizontally or vertically arranged button tables (to be called before generating the ButtonTable, so we can deliver an arranged button set):
--- @class ButtonTable
local ButtonTable = FocusManager:extend{
    width = nil,
    --* If requested, allow ButtonTable to shrink itself if 'width' can
    --* be reduced without any truncation or font size getting smaller.
    shrink_unneeded_width = false,
    --* But we won't go below this: buttons are tapable, we want some
    --* minimal width so they are easy to tap (this is mostly needed
    --* for CJK languages where button text can be one or two glyphs).
    shrink_min_width = Screen:scaleBySize(100),

    buttons = {
        {
            { text = "OK", enabled = true, callback = nil },
            { text = "Cancel", enabled = false, callback = nil },
        },
    },
    sep_width = Size.line.medium,
    padding = Size.padding.default,

    zero_sep = false,
    button_font_face = "cfont",
    button_font_size = 18,

    is_active_tab = false,
    background = nil,
    button_lines = 2,
    button_font_weight = "bold",
    decrease_top_padding = nil,
    increase_top_padding = nil,
    no_bottom_spacer = false,
    no_separators = false,
    readonly = false,
    sep_color = KOR.colors.tabs_table_separators,
}

function ButtonTable:init()
    self.width = self.width or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    self.buttons_layout = {}
    self.button_by_id = {}
    self.container = VerticalGroup:new{ width = self.width }
    self[1] = self.container
    if self.zero_sep then
        --* If we're asked to add a first line, don't add a vspan before: caller
        --* must do its own padding before.
        self:addVerticalSeparator()
    end
    local row_cnt = #self.buttons
    local table_min_needed_width = -1
    local buttons_layout_line, horizontal_group, row, column_cnt, available_width, default_button_width, min_needed_button_width, unspecified_width_buttons, vertical_sep, inserted, button

    for i = 1, row_cnt do
        buttons_layout_line = {}
        horizontal_group = HorizontalGroup:new{}
        row = self.buttons[i]
        column_cnt = #row
        available_width = self.no_separators and self.width or self.width - self.sep_width * (column_cnt - 1)
        unspecified_width_buttons = 0
        for j = 1, column_cnt do
            --* disabled, to create less distance between rows:
            --self:addVerticalSpan()
            local btn_entry = row[j]
            if btn_entry and btn_entry.width then
                available_width = available_width - btn_entry.width
            else
                unspecified_width_buttons = unspecified_width_buttons + 1
            end
        end
        default_button_width = math.floor(available_width / unspecified_width_buttons)
        min_needed_button_width = -1
        local max_button_height = 0
        for j = 1, column_cnt do
            local btn_entry = row[j]
            if btn_entry then

                --! here each button is generated:
                button, max_button_height, min_needed_button_width = self:generateButton(btn_entry, max_button_height, default_button_width, min_needed_button_width)

                buttons_layout_line[j] = button
                table_insert(horizontal_group, button)
            end
        end --* end for each button

        --* insert equal height vertical separators:
        if not self.no_separators then
            vertical_sep = LineWidget:new{
                background = self.sep_color,
                dimen = Geom:new{
                    w = self.sep_width,
                    h = max_button_height - Screen:scaleBySize(10),
                }
            }
            inserted = 0
            for j = 1, column_cnt - 1 do
                    table_insert(horizontal_group, j + inserted + 1, vertical_sep)
                inserted = inserted + 1
            end
        end

        table_insert(self.container, horizontal_group)
        if not self.no_bottom_spacer then
            self:addVerticalSpan()
            if i < row_cnt then
                self:addVerticalSeparator()
            end
        end
        if not self.no_bottom_spacer and column_cnt > 0 then
            --* Only add lines that are not separator to the focusmanager
            table_insert(self.buttons_layout, buttons_layout_line)
        end
        -- #((shrink button row))
        --* width used here was computed in call to ((ButtonTable#generateButton)) above > ((compute min needed button width)):
        if self.shrink_unneeded_width and table_min_needed_width ~= false then
            if min_needed_button_width then
                if min_needed_button_width >= 0 and min_needed_button_width < default_button_width then
                    local row_min_width = self.width - (default_button_width - min_needed_button_width) * unspecified_width_buttons
                    if table_min_needed_width < row_min_width then
                        table_min_needed_width = row_min_width
                    end
                end
            else
                --* If any one row can't be made smaller, give up
                table_min_needed_width = false
            end
        end
    end --* end for each button line
    if Device:hasDPad() then
        self.layout = self.buttons_layout
        self:refocusWidget()
    else
        self.key_events = {}  --* deregister all key press event listeners
    end
    if self.shrink_unneeded_width and table_min_needed_width ~= false
            and table_min_needed_width > 0 and table_min_needed_width < self.width then
        self.width = table_min_needed_width > self.shrink_min_width and table_min_needed_width or self.shrink_min_width
        self.shrink_unneeded_width = false
        self:free()
        self:init()
    end
end

function ButtonTable:addVerticalSpan()
    table_insert(self.container, VerticalSpan:new{
        width = Size.span.vertical_default,
    })
end

function ButtonTable:addVerticalSeparator(black_line)
    table_insert(self.container, LineWidget:new{
        background = black_line and KOR.colors.black or KOR.colors.separator_vertical_color,
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        },
    })
end

function ButtonTable:setupGridScrollBehaviour()
    --* So that the last row get the same height as all others,
    --* we add an invisible separator below it
    self.container:resetLayout()
    table_insert(self.container, VerticalSpan:new{
        width = self.sep_width,
    })
    self.container:getSize() --* have it recompute its offsets and size

    --* Generate self.step_scroll_grid (so that what we add next is not part of it)
    self:getStepScrollGrid()

    --* Insert 2 lines off-dimensions in VerticalGroup (that will show only when overflowing)
    table_insert(self.container, 1, LineWidget:new{
        background = KOR.colors.black,
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        },
    })
    table_insert(self.container._offsets, 1, { x = self.width, y = -self.sep_width })
    table_insert(self.container, LineWidget:new{
        background = KOR.colors.black,
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        },
    })
    table_insert(self.container._offsets, { x = self.width, y = self.container._size.h + self.sep_width })
end

function ButtonTable:getStepScrollGrid()
    if not self.step_scroll_grid then
        local step_rows = {}
        local offsets = self.container._offsets
        local idx = self.zero_sep and 2 or 1
        local row_num = 1
        while idx <= #self.container do
            --* fix sometimes occurring crash:
            if offsets[idx + 1] and offsets[idx + 2] then
                local row = {
                    row_num = row_num, --* (not used, but may help with debugging)
                    top = offsets[idx].y, --* top of our vspan above text
                    content_top = offsets[idx + 1].y, --* top of our text widget
                    content_bottom = offsets[idx + 2].y - 1, --* bottom of our text widget
                    bottom = idx + 4 <= #self.container and offsets[idx + 4].y - 1 or self.container:getSize().h - 1
                    --* bottom of our vspan + separator below text
                    --* To implement when needed:
                    --* columns = { array of similar info about each button in that row's HorizontalGroup }
                    --* Its absence means free scrolling on the x-axis (if scroll ends up being needed)
                }
                table_insert(step_rows, row)
                row_num = row_num + 1
            end
            idx = idx + 4
        end
        self.step_scroll_grid = step_rows
    end
    return self.step_scroll_grid
end

function ButtonTable:getButtonById(id)
    return self.button_by_id[id] --* nil if not found
end


--* ==================== SMARTSCRIPTS =====================

function ButtonTable:generateButton(btn_entry, max_button_height, default_button_width, min_needed_button_width)
    local DEFAULT_COLOR = not self.readonly and KOR.colors.black or KOR.colors.white
    local min_width, button_dim, config

    local is_bold = self.button_font_weight == "bold"
    if btn_entry.text_font_bold == false or btn_entry.font_bold == false then
        is_bold = false
    elseif btn_entry.text_font_bold == true or btn_entry.font_bold == true then
        is_bold = true
    end

    --! this must be done like this, because of config.callback, which calls btn_entry.callback:
    config = KOR.tables:shallowCopy(btn_entry)
    if not btn_entry.fgcolor then
        config.fgcolor = DEFAULT_COLOR
    end
    if not btn_entry.width then
        config.width = default_button_width
    end
    config.align = btn_entry.align or "center"
    config.background = self.background or KOR.colors.background
    config.button_lines = self.button_lines
    config.text_font_size = btn_entry.font_size or self.button_font_size
    config.decrease_top_padding = self.decrease_top_padding
    config.increase_top_padding = self.increase_top_padding

    config.text_font_face = btn_entry.text_font_face or self.button_font_face
    config.is_active_tab = btn_entry.is_active_tab
    config.is_tab_button = btn_entry.is_tab_button
    config.text_font_size = btn_entry.text_font_size
    config.text_font_bold = is_bold

    config.bordersize = 0
    config.margin = 0
    config.padding = Size.padding.buttontable --* a bit taller than standalone buttons, for easier tap
    config.padding_h = btn_entry.align == "left" and Size.padding.large or Size.padding.button
    --* if avoid_text_truncation prop is set: allow text to take more of the horizontal space if centered...
    --* show_parent can also be set...

    --! in case of props info_text or choice_callback, callback will be generated by ((ButtonInfoPopup)) or ((ButtonChoicePopup)) > ((ButtonProps#initInfoCallback)) or ((ButtonProps#initChoiceCallback)) !:
    config.callback = not self.info_text and not self.choice_callback and btn_entry.callback and function()
        if self.show_parent and self.show_parent.movable then
            self.show_parent.movable:resetEventState()
        end
        btn_entry.callback()
    end
    local button = Button:new(config)

    --* value computed here will be used in ((shrink button row)), after all the buttons (in a row?) have been generated:
    -- #((compute min needed button width))
    if self.shrink_unneeded_width and not btn_entry.width and min_needed_button_width ~= false then
        --* We gather the largest min width of all buttons without a specified width,
        --* and will see how it does when this largest min width is applied to all
        --* buttons (without a specified width): we still want to keep them the same
        --* size and balanced.
        min_width = button:getMinNeededWidth()
        if min_width then
            if min_needed_button_width < min_width then
                min_needed_button_width = min_width
            end
        else
            --* If any one button in this row can't be made smaller, give up
            min_needed_button_width = false
        end
    end
    if btn_entry.id then
        self.button_by_id[btn_entry.id] = button
    end
    button_dim = button:getSize()
    if button_dim.h and button_dim.h > max_button_height then
        max_button_height = button_dim.h
    end

    return button, max_button_height, min_needed_button_width
end

return ButtonTable
