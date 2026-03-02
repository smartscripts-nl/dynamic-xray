
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
local math_floor = math.floor

--- @class TwoColumnText
local TwoColumnText = WidgetContainer:extend{
	is_landscape_screen = nil,
}

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

	return CenterContainer:new{
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
					ScrollTextWidget:new{
						text = column1_text,
						face = face,
						line_height = KOR.registry.line_height or 0.95,
						alignment = "left",
						justified = false,
						dialog = parent,
						width = half_width,
						height = height,
					}
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
					ScrollTextWidget:new{
						text = column2_text,
						face = face,
						line_height = KOR.registry.line_height or 0.95,
						alignment = "left",
						justified = false,
						dialog = parent,
						width = half_width,
						height = height,
					}
				}
			},
		}
	}
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
