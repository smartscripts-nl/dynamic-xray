
local Registry = require("extensions/registry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class ButtonTableGenerators
local ButtonTableGenerators = WidgetContainer:extend{}

-- see ((TextViewer#showToc)) for an example how to use this:
function ButtonTableGenerators:getVerticallyArrangedButtonTable(source_items, button_factory, info_button, close_button)
	local button_table = {}

	-- info: prevent repeated injections of info button into the ButtonTable:
	-- this Registry var was unset in ((xray paragraph info: after load callback)):
	if info_button and not Registry:get("toc_info_button_injected") then
		table.insert(source_items, info_button)
		Registry:set("toc_info_button_injected", true)
	end
	local buttons_count = #source_items
	local display_buttons_count = source_items[buttons_count].icon and buttons_count - 1 or buttons_count
	local max_buttons_per_row = buttons_count < 10 and 3 or 4

	local rows_needed = math.ceil(buttons_count / max_buttons_per_row)
	for i = 1, rows_needed do
		button_table[i] = {}
	end
	if buttons_count < max_buttons_per_row then
		for i = 1, buttons_count do
			-- first case: info button:
			local button = source_items[i].icon and source_items[i] or button_factory(i)
			table.insert(button_table[1], button)
		end
		table.insert(button_table[1], close_button)

	elseif buttons_count == max_buttons_per_row then
		for i = 1, buttons_count do
			local button = source_items[i].icon and source_items[i] or button_factory(i)
			table.insert(button_table[1], button)
		end
		table.insert(button_table, { close_button })

	else
		local close_button_injected = false
		for i = 1, #source_items do
			local target_row
			if i <= rows_needed then
				target_row = i
			elseif i % rows_needed == 0 then
				target_row = rows_needed
			else
				target_row = i % rows_needed
			end
			local button = source_items[i].icon and source_items[i] or button_factory(i)
			table.insert(button_table[target_row], button)
		end
		for i = 1, rows_needed do
			local row_buttons = #button_table[i]

			-- #((TextViewer toc popup: add close button for popup and info dialog))
			-- if we are on the last row and that row is not filled out:
			if row_buttons < max_buttons_per_row then
				for x = 1, max_buttons_per_row - row_buttons do
					if i == rows_needed and x == max_buttons_per_row - row_buttons and close_button then
						close_button_injected = true
						table.insert(button_table[i], close_button)
					else
						table.insert(button_table[i], {
							text = " ",
							callback = function()
								x = nil
							end,
						})
					end
				end
			end
		end
		if not close_button_injected then
			table.insert(button_table, { close_button })
		end
	end

	return button_table, display_buttons_count
end

return ButtonTableGenerators
