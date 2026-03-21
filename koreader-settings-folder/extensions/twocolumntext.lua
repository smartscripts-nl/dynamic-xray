
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

local count

--- @class TwoColumnText
local TwoColumnText = WidgetContainer:extend{
	is_landscape_screen = nil,
}

function TwoColumnText:getColumnTexts(column1_items, column2_items, use_second_text_column, iconless_column, separator)
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

function TwoColumnText:getWidget(args)

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

function TwoColumnText:resetCache()
	self.is_landscape_screen = Screen:getWidth() > Screen:getHeight()
end

function TwoColumnText:useTwoColumnDisplay(items_count)
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

return TwoColumnText
