
local require = require

local Device = require("device")
local Input = Device.input
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local pairs = pairs

--- @class System
local System = WidgetContainer:extend{
	crashed = false,
	hold_menu_input_delay = 0.9,
}

function System:isClosingGesture(direction, excluded_direction)
	local closing_directions = { "northeast", "south", "southwest", "north" }
	for _, closing_direction in pairs(closing_directions) do
		if direction == closing_direction and closing_direction ~= excluded_direction then
			return true
		end
	end
	return false
end

function System:inhibitInputOnHold()
	--* currently this value is 0.9:
	Input:inhibitInputUntil(self.hold_menu_input_delay)
end

return System
