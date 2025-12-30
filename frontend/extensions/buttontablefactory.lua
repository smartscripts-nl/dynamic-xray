
local require = require

local ButtonTable = require("ui/widget/buttontable")
local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local math = math
local table = table
local type = type

local count

--* see ((TABS)) for more info:

--- @class ButtonTableFactory
local ButtonTableFactory = WidgetContainer:extend{}

function ButtonTableFactory:getHorizontallyArrangedButtonTable(subject, items_per_row, button_factory)
	local buttons = {}
	local buttons_count = #subject
	local rows_needed = math.ceil(buttons_count / items_per_row)
	for i = 1, rows_needed do
		buttons[i] = {}
	end
	local button, row
	for i = 1, buttons_count do
		button = subject[i].icon and subject[i] or button_factory(i)
		row = math.ceil(i / items_per_row)
		table.insert(buttons[row], button)
	end

	return buttons
end

--* see ((TextViewer#showToc)) for an example how to use this:
function ButtonTableFactory:getVerticallyArrangedButtonTable(source_items, button_factory, info_button, close_button)
	local button_table = {}

	--* prevent repeated injections of info button into the ButtonTable:
    --* this Registry var will be unset each time the Xray info popup is loaded, via ((xray paragraph info: after load callback)) > ((XrayUI#onInfoPopupLoadShowToc)):
	if info_button and not KOR.registry:get("toc_info_button_injected") then
		table.insert(source_items, info_button)
		KOR.registry:set("toc_info_button_injected", true)
	end
	local buttons_count = #source_items
	local display_buttons_count = source_items[buttons_count].icon and buttons_count - 1 or buttons_count
	local max_buttons_per_row = buttons_count < 10 and 3 or 4

	local rows_needed = math.ceil(buttons_count / max_buttons_per_row)
	for i = 1, rows_needed do
		button_table[i] = {}
	end
	local button
	if buttons_count < max_buttons_per_row then
		for i = 1, buttons_count do
			--* first case: info button:
			button = source_items[i].icon and source_items[i] or button_factory(i)
			button.text_font_bold = source_items[i].font_bold or source_items[i].text_font_bold
			button.font_face = source_items[i].font_face or source_items[i].text_font_face
			button.font_size = source_items[i].font_size or source_items[i].text_font_size
			table.insert(button_table[1], button)
		end
		table.insert(button_table[1], close_button)

	elseif buttons_count == max_buttons_per_row then
		for i = 1, buttons_count do
			button = source_items[i].icon and source_items[i] or button_factory(i)
			button.text_font_bold = source_items[i].font_bold or source_items[i].text_font_bold
			button.font_face = source_items[i].font_face or source_items[i].text_font_face
			button.font_size = source_items[i].font_size or source_items[i].text_font_size
			table.insert(button_table[1], button)
		end
		table.insert(button_table, { close_button })

	else
		local close_button_injected = false
		local target_row
		count = #source_items
		for i = 1, count do
			if i <= rows_needed then
				target_row = i
			elseif i % rows_needed == 0 then
				target_row = rows_needed
			else
				target_row = i % rows_needed
			end
			button = source_items[i].icon and source_items[i] or button_factory(i)
			button.text_font_bold = source_items[i].font_bold or source_items[i].text_font_bold
			button.font_face = source_items[i].font_face or source_items[i].text_font_face
			button.font_size = source_items[i].font_size or source_items[i].text_font_size
			table.insert(button_table[target_row], button)
		end
		local row_buttons
		for i = 1, rows_needed do
			row_buttons = #button_table[i]

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

--- @param button_table table The target table for generating a ButtonTable
function ButtonTableFactory:injectButtonIntoTargetRows(button_table, button, starting_row, max_per_row)
	if not button_table or not button then
		return
	end
	if not max_per_row then
		max_per_row = 3
	end
	--* add new row when the table is empty or the last row is up to max_per_row filled with items:
	if #button_table < starting_row or #button_table[#button_table] == max_per_row then
		table.insert(button_table, {})
	end
	table.insert(button_table[#button_table], button)
end

--* see ((TABS)) for more info:
function ButtonTableFactory:getTabsTable(parent)
	local nr_indicator, button
	count = #parent.tabs_table_buttons[1]
	for i = 1, count do
		--! this MUST be a local var; otherwise all buttons are shown in bold:
		local current = i
		button = parent.tabs_table_buttons[1][current]
		nr_indicator = not DX.s.is_mobile_device and not button.text:match("%d+[.] ") and current .. ". " or ""
		if current == parent.active_tab then
			--* example of usage: ((ImpressionsList#_showViewer))
			--* callbacks defined in ((htmlBoxTabbed tab button callbacks))
			--* target_button_text function optionally defined in ((Dialogs#htmlBoxTabbed)):
			if button.is_target_tab and type(button.target_button_text) == "function" then
				button.text = nr_indicator .. button.target_button_text()
			end
			if not button.text:match(KOR.icons.active_tab_bare) then
				button.text = KOR.icons.active_tab_bare .. " " .. nr_indicator .. button.text
			end
			button.text_font_bold = true
		else
			button.text = nr_indicator .. button.text
			button.text_font_bold = false
		end
	end
	return ButtonTable:new{
		width = parent.width,
		buttons = parent.tabs_table_buttons,
		button_font_face = "x_smallinfofont",
		button_font_size = 13,
		button_font_weight = "normal",
		decrease_top_padding = 0,
		padding = 0,
		show_parent = parent,
	}
end

return ButtonTableFactory
