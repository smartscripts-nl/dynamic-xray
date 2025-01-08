
local Device = require("device")
local Input = Device.input
local Registry = require("extensions/registry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class System
local System = WidgetContainer:extend{}

function System:isClosingGesture(direction, excluded_direction)
	local closing_directions = { "northeast", "south", "southwest", "north" }
	for _, closing_direction in pairs(closing_directions) do
		if direction == closing_direction and closing_direction ~= excluded_direction then
			return true
		end
	end
	return false
end

function System:inhibitInput(until_seconds)
	if not until_seconds then
		until_seconds = Registry.hold_menu_input_delay
	end
	Input:inhibitInputUntil(until_seconds)
end

function System:nextTick(callback)
	if Registry.is_non_kobo_device then
		callback()
		return
	end
	UIManager:nextTick(function()
		callback()
	end)
end

return System
