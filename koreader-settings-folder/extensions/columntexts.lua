
local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local KOR = require("extensions/kor")
local ScrollTextWidget = require("extensions/widgets/scrolltextwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local DX = DX
local math_ceil = math.ceil
local math_floor = math.floor
local table_concat = table.concat
local table_insert = table.insert
local type = type

local count

--- @class ColumnTexts
local ColumnTexts = WidgetContainer:extend{
	is_landscape_screen = nil,
}

function ColumnTexts:getTwoColumnTexts(column1_items, column2_items, use_second_text_column, iconless_column, separator)
	if not separator then
		separator = ""
	end
	if not column2_items then
		column2_items = {}
	end
	if iconless_column then
		iconless_column = table_concat(iconless_column, separator)
	end
	if not use_second_text_column then
		column1_items = table_concat(column1_items, separator)
		column2_items = nil

		return column1_items, column2_items, iconless_column
	end

	count = #column1_items
	local half_point = math_ceil(count / 2)
	for i = count, half_point + 1, -1 do
		table_insert(column2_items, 1, column1_items[i])
		column1_items[i] = nil
	end
	column1_items = table_concat(column1_items, separator)
	column2_items = table_concat(column2_items, separator)

	return column1_items, column2_items, iconless_column
end

function ColumnTexts:getThreeColumnTexts(column1_items, column2_items, column3_items, use_text_columns, iconless_column, separator)
	if not separator then
		separator = ""
	end
	if not column2_items then
		column2_items = {}
	end
	if not column3_items then
		column3_items = {}
	end
	if iconless_column then
		iconless_column = table_concat(iconless_column, separator)
	end
	if not use_text_columns then
		column1_items = table_concat(column1_items, separator)
		column2_items = nil
		column3_items = nil

		return column1_items, column2_items, column3_items, iconless_column
	end

	local target
	count = #column1_items
	local first_column_limit = math_floor(count / 3)
	local second_column_limit = 2 * first_column_limit
	local overfloat_items = count % 3
	if overfloat_items == 1 then
		first_column_limit = first_column_limit + 1
		second_column_limit = second_column_limit + 1
	end
	if overfloat_items == 2 then
		second_column_limit = second_column_limit + 1
	end
	for i = first_column_limit + 1, count do
		target = i <= second_column_limit and column2_items or column3_items
		table_insert(target, column1_items[i])
	end
	column1_items = KOR.tables:slice(column1_items, 1, first_column_limit)
	column1_items = table_concat(column1_items, separator)
	column2_items = table_concat(column2_items, separator)
	column3_items = table_concat(column3_items, separator)

	return column1_items, column2_items, column3_items, iconless_column
end

function ColumnTexts:getDuoWidget(args)

	local separator = "\n\n"
	local parent = args.parent
	--* the caller is responsible for supplying two texts, one for each of the columns:
	local column1_text = args.column1_text
		:gsub("\n\n\n+", separator)
	local column2_text = args.column2_text
		:gsub("^\n", "")
		:gsub("\n\n\n+", separator)
	local face = args.face
	local width = args.width
	local container_width = args.container_width
	local height = args.height

	local horizontal_padding = math_floor(Screen:scaleBySize(50) / 2)
	local half_width = math_floor(width / 2) - horizontal_padding

	local widget1 = ScrollTextWidget:new{
		text = column1_text,
		face = face,
		line_height = KOR.registry.line_height or 0.95,
		alignment = "left",
		justified = false,
		dialog = parent,
		width = half_width,
		height = height,
	}
	local widget2 = ScrollTextWidget:new{
		text = column2_text,
		face = face,
		line_height = KOR.registry.line_height or 0.95,
		alignment = "left",
		justified = false,
		dialog = parent,
		width = half_width,
		height = height,
	}

	local widget = CenterContainer:new{
		dimen = Geom:new{
			w = container_width,
			h = height,
		},
		HorizontalGroup:new{
			CenterContainer:new{
				dimen = Geom:new{
					w = half_width + horizontal_padding,
					h = height,
				},
				HorizontalGroup:new{
					HorizontalSpan:new{
						w = horizontal_padding,
					},
					widget1,
				}
			},
			CenterContainer:new{
				dimen = Geom:new{
					w = half_width + horizontal_padding,
					h = height,
				},
				HorizontalGroup:new{
					HorizontalSpan:new{
						w = horizontal_padding,
					},
					widget2,
				}
			},
		}
	}

	return widget, widget1, widget2
end

function ColumnTexts:getThreeWidget(args)

	local parent = args.parent
	--* the caller is responsible for supplying the texts, one for each of the columns:
	local column1_text = self:manipulateColumnTexts(1, args.column1_text)

	local column2_text = self:manipulateColumnTexts(2, args.column2_text)

	local column3_text = self:manipulateColumnTexts(3, args.column3_text)

	local face = args.face
	local width = args.width
	local container_width = args.container_width
	local height = args.height

	local horizontal_padding = math_floor(Screen:scaleBySize(50) / 2)
	local third_width = math_floor(width / 3) - horizontal_padding

	local widget1 = ScrollTextWidget:new{
		text = column1_text,
		face = face,
		line_height = KOR.registry.line_height or 0.95,
		alignment = "left",
		justified = false,
		dialog = parent,
		width = third_width,
		height = height,
	}
	local widget2 = ScrollTextWidget:new{
		text = column2_text,
		face = face,
		line_height = KOR.registry.line_height or 0.95,
		alignment = "left",
		justified = false,
		dialog = parent,
		width = third_width,
		height = height,
	}
	local widget3 = ScrollTextWidget:new{
		text = column3_text,
		face = face,
		line_height = KOR.registry.line_height or 0.95,
		alignment = "left",
		justified = false,
		dialog = parent,
		width = third_width,
		height = height,
	}

	local widget = CenterContainer:new{
		dimen = Geom:new{
			w = container_width,
			h = height,
		},
		HorizontalGroup:new{
			CenterContainer:new{
				dimen = Geom:new{
					w = third_width + horizontal_padding,
					h = height,
				},
				HorizontalGroup:new{
					HorizontalSpan:new{
						w = horizontal_padding,
					},
					widget1,
				}
			},
			CenterContainer:new{
				dimen = Geom:new{
					w = third_width + horizontal_padding,
					h = height,
				},
				HorizontalGroup:new{
					HorizontalSpan:new{
						w = horizontal_padding,
					},
					widget2,
				}
			},
			CenterContainer:new{
				dimen = Geom:new{
					w = third_width + horizontal_padding,
					h = height,
				},
				HorizontalGroup:new{
					HorizontalSpan:new{
						w = horizontal_padding,
					},
					widget3,
				}
			},
		}
	}

	return widget, widget1, widget2, widget3
end

--- @private
function ColumnTexts:manipulateColumnTexts(column_no, column_text)
	local separator = "\n\n"
	if type(column_text) == "function" then
		column_text = column_text()
	end
	if not column_text then
		return
	end
	if column_no == 1 then
		return column_text:gsub("\n\n\n+", separator)
	end

	return column_text
		:gsub("^\n", "")
		:gsub("\n\n\n+", separator)
end

function ColumnTexts:resetCache()
	self.is_landscape_screen = Screen:getWidth() > Screen:getHeight()
end

function ColumnTexts:useTwoColumnDisplay(items_count)
	if not items_count or DX.s.is_mobile_device then
		return false
	end
	if self.is_landscape_screen == nil then
		self.is_landscape_screen = Screen:getWidth() > Screen:getHeight()
	end
	return
		DX.s.show_items_in_two_columns
		and items_count > 2
		and self.is_landscape_screen
end

return ColumnTexts
