
--* info_params and choice_params props for buttons as used here are loaded from resp. ((ButtonInfoPopup)) or ((ButtonChoicePopup)) methods...

local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local pairs = pairs
local table = table
local type = type

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

--* info_params and choice_params props for buttons as used here are loaded from resp. ((ButtonInfoPopup)) or ((ButtonChoicePopup)) methods...

--- @class ButtonProps
local ButtonProps = WidgetContainer:new{
	alert_dialog = nil,
	auto_exec_delay = 12,
	auto_exec_delay_display_correction = 2,
	auto_exec_enabled = false,
	button_color_default = KOR.colors.button_default,
	button_color_disabled = KOR.colors.button_disabled,
	button_color_invisible = KOR.colors.button_invisible,
	--* this one will be set upon initalisation of the very first button in ((Button#init)):
	fixed_icon_height = nil,
	registry_index = "auto_exec_schedule_active",
}

--* returns default_color, disabled_color, white color:
function ButtonProps:getButtonColors()
	return self.button_color_default, self.button_color_disabled, self.button_color_invisible
end

--* example: local button_enabled, button_color = KOR.buttonprops:getButtonState(truthy_or_falsy_value):
function ButtonProps:getButtonState(condition)
	--* in stock KOReader these were named DEFAULT_COLOR, DISABLED_COLOR and INVISIBLE_COLOR:
	if condition then
		return true, self.button_color_default, self.button_invisible
	end
	return false, self.button_color_disabled, self.button_invisible
end

function ButtonProps:setAutoExec(callback)
	UIManager:scheduleIn(self.auto_exec_delay, function()
		if KOR.registry:get(self.registry_index) then

			KOR.registry:unset(self.registry_index)
			UIManager:close(self.alert_dialog)

			callback()
		end
	end)
	KOR.registry:set(self.registry_index, true)

	return self.auto_exec_delay - self.auto_exec_delay_display_correction
end

function ButtonProps:initInfoCallback(parent_button)
	local info_props = {}
	self:setCustomIconForLastRemainingButton(parent_button)
	for name, prop in pairs(parent_button.info_params) do
		self:setParentButtonAndPopupProps(parent_button, info_props, name, prop)
	end

	--* ButtonInfoPopup could have defined a overruling info_callback:
	if not parent_button.info_callback then
		--- only show the info callback upon tap:
		parent_button["info_callback"] = function()
			self:resetMovableState(parent_button)
			self:popupInfo(info_props)
		end
	end
	parent_button["info_callbacks_show_indicators"] = true
end

function ButtonProps:popupInfo(info_props)
	if info_props.immediate_callback then
		info_props.immediate_callback()
		return
	end

	local text = info_props.text
	local icon = info_props.icon
	local icon_size_ratio = info_props.icon_size_ratio
	local info = info_props.info
	local overruling_button_label = info_props.overruling_button_label
	local callback = info_props.callback
	local callback_label = info_props.callback_label:lower()
	local font_face = "x_smallinfofont"
	local font_size = 14
	local font_bold = true

	local icon_text = icon and {
		icon = icon,
		icon_size_ratio = icon_size_ratio,
		text = " " .. callback_label or " voer uit",
	} or nil
	--* we have a text icon:
	if text then
		text = text .. " " .. callback_label
	end

	local auto_exec_delay = self.auto_exec_enabled and self:setAutoExec(callback)
	local buttons = {{
		 {
			 icon_text = icon_text,
			 text = text,
			 text_font_face = font_face,
			 text_font_size = font_size,
			 font_bold = font_bold,
			 callback = function()
				 self:execOrShowButtonDisabledMessage(callback, info_props)
			 end
		 },
		 {
			 icon = "back",
			 icon_size_ratio = 0.4,
			 callback = function()
				 KOR.registry:unset(self.registry_index)
				 UIManager:close(self.alert_dialog)
			 end,
		 },
	 }}

	local title = "toelichting"
	if not info then
		info = "???"
	end
	local parts = KOR.strings:split(info, " ?| ?")
	if #parts > 1 then
		title = parts[1]
		info = self:addDisabledButtonMessage(info_props, parts[2])
	end
	-- #((setting overruling_button_label for info popup))
	--* compare ((setting overruling_button_label for choice popup))
	if overruling_button_label then
		info = info
			:gsub("^:", "[" .. overruling_button_label .. "] " .. KOR.icons.arrow_bare .. "\n", 1)
	end

	if auto_exec_delay then
		auto_exec_delay = auto_exec_delay - self.auto_exec_delay_display_correction
		info = info .. "\n\nauto-exec in " .. auto_exec_delay .. " seconden..."
	end

	local args = {
		buttons = buttons,
	}
	self.alert_dialog = KOR.dialogs:niceAlert(title, info, args)
end

function ButtonProps:initChoiceCallback(parent)
	local choice_props = {}
	for name, prop in pairs(parent.choice_params) do
		self:setParentButtonAndPopupProps(parent, choice_props, name, prop)
	end

	--- only show the popup info and choice dialog upon hold:
	parent["hold_callback"] = function()
		self:resetMovableState(parent)
		self:popupChoice(choice_props)
	end
	parent["show_hold_callback_indicator"] = true
end

function ButtonProps:popupChoice(choice_props)
	local text = choice_props.text
	local icon = choice_props.icon
	local icon_size_ratio = choice_props.icon_size_ratio
	local info = choice_props.info
	local overruling_button_label = choice_props.overruling_button_label
	local callback = choice_props.callback
	local callback_label = choice_props.overrule_callback_label or choice_props.callback_label:lower()
	local hold_callback = choice_props.hold_callback
	local hold_callback_label = choice_props.overrule_hold_callback_label or choice_props.hold_callback_label and choice_props.hold_callback_label:lower()
	local font_face = choice_props.font_face or choice_props.text_font_face or "x_smallinfofont"
	local font_size = choice_props.font_size or choice_props.text_font_size or 14
	local font_bold = true
	if choice_props.font_bold == false or choice_props.text_font_bold == false then
		font_bold = false
	end
	if text == "spring" and choice_props.overrule_callback_label and text ~= choice_props.overrule_callback_label then
		font_bold = true
	end
	if text == "bewerk" and choice_props.overrule_hold_callback_label and text ~= choice_props.overrule_hold_callback_label then
		font_bold = true
	end

	local icon_text = icon and {
		icon = icon,
		icon_size_ratio = icon_size_ratio,
		text = " " .. callback_label or " hoofdfunctie",
	}

	icon = self:setCustomIconForLastButton(icon, choice_props, hold_callback_label)
	local icon_text_hold = icon and hold_callback and {
		icon = icon,
		icon_size_ratio = icon_size_ratio,
		text = " " .. hold_callback_label or " nevenfunctie",
	}

	local hold_text
	--* we have a text icon:
	--* for editing xray items from the Xray info popup buttons:
	if choice_props.overrule_callback_label then
		local button_text = text
			:gsub("^%d+%. ", "")
			:gsub(" .+$", " ")
		text = button_text .. choice_props.overrule_callback_label
		if choice_props.overrule_hold_callback_label then
			hold_text = button_text .. choice_props.overrule_hold_callback_label
		end
	elseif text then
		local text_icon = text
		text = text_icon .. " " .. callback_label
		hold_text = text_icon .. " " .. hold_callback_label
	end

	local auto_exec_delay = self.auto_exec_enabled and  self:setAutoExec(hold_callback)
	local buttons = {{
		 {
			 icon_text = icon_text,
			 text = text,
			 text_font_face = font_face,
			 text_font_size = font_size,
			 font_bold = font_bold,
			 callback = function()
				 self:execOrShowButtonDisabledMessage(callback, choice_props)
			 end
		 },
		 {
			 icon = "back",
			 icon_size_ratio = 0.4,
			 callback = function()
				 KOR.registry:unset(self.registry_index)
				 UIManager:close(self.alert_dialog)
			 end,
		 },
	 }}
	if hold_callback then
		table.insert(buttons[1], 2, {
			icon_text = icon_text_hold,
			text = hold_text,
			text_font_face = font_face,
			text_font_size = font_size,
			font_bold = font_bold,
			callback = function()
				self:execOrShowButtonDisabledMessage(hold_callback, choice_props)
			end
		})
	end

	-- #((set more then two popup choice callbacks))
	self:injectAdditionalChoiceCallbacks(buttons, choice_props, {
		icon = icon,
		icon_size_ratio = icon_size_ratio,
		text = text,
		font_face = font_face,
		font_size = font_size,
		font_bold = font_bold,
	})

	local title = "toelichting"
	local parts = KOR.strings:split(info, " ?| ?")
	if #parts > 1 then
		title = parts[1]
		--* this prop is set in ((ButtonChoicePopup#forXrayTocItemEdit)):
		if choice_props.is_xray_toc_item then
			title = choice_props.text:gsub("^%d+%. ", "")
		end
		info = self:addDisabledButtonMessage(choice_props, parts[2])
	end
	-- #((setting overruling_button_label for choice popup))
	--* compare ((setting overruling_button_label for info popup))
	if overruling_button_label then
		info = info
			:gsub("%[[^%]]+%]", "[" .. overruling_button_label .. "]", 1)
	end

	if auto_exec_delay then
		info = info .. "\n\nauto-exec hoofdfunctie in " .. auto_exec_delay .. " seconden..."
	end

	local args = {
		buttons = buttons,
	}
	-- #((linked xray items in popup))
	if choice_props.extra_wide_dialog then
		args.width = KOR.dialogs:getThreeQuarterDialogWidth()
	end
	self.alert_dialog = KOR.dialogs:niceAlert(title, info, args)
end

--- @protected
function ButtonProps:resetMovableState(parent)
	--* this code I copied from ((ButtonTable#init)):
	if parent.show_parent and parent.show_parent.movable then
		parent.show_parent.movable:resetEventState()
	end
end

function ButtonProps:setParentButtonAndPopupProps(parent_button, popup_props, name, prop)

	--!! crucial for a button that does something !!:
	if name == "callback" then
		parent_button["callback"] = function()
			self:resetMovableState(parent_button)
			prop()
		end
		--! crucial prop for popup:
		popup_props["callback"] = function()
			prop()
		end
	elseif name == "text" then
		parent_button[name] = prop
		--! crucial prop for popup:
		popup_props.text = prop
	elseif name == "text_icon" or name == "icon_icon" then
		parent_button[name] = prop
		--! crucial prop for popup:
		popup_props.icon = prop.icon
	elseif name == "icon_text" then
		parent_button[name] = prop
		--! crucial prop for popup:
		popup_props.icon_text = prop.icon_text
	elseif name == "icon" then
		parent_button[name] = prop
		--! crucial prop for popup:
		popup_props.icon = prop
	else
		parent_button[name] = prop
		popup_props[name] = prop
	end
end

--* called from methods in ((ButtonInfoPopup)) or ((ButtonChoicePopup)):
--- @protected
function ButtonProps:setOverruleProps(params, overrule_props)
	params["bordersize"] = 0
	params.allow_hold_when_disabled = true
	--* when using same height for all buttons in a row:
	if params.icon_height then
		params.icon_size_ratio = nil
		overrule_props.icon_size_ratio = nil
	end

	local skip_modify_params = not overrule_props

	local info = params.info or overrule_props and overrule_props.info
	local callback_label = params.callback_label or overrule_props and overrule_props.callback_label
	local hold_callback_label = params.hold_callback_label or overrule_props and overrule_props.hold_callback_label
	if hold_callback_label and callback_label and info then
		info = info
			:gsub(":", "[" .. callback_label .. "] " .. KOR.icons.arrow_bare .. "\n", 1)
			:gsub("\n\n:", "\n\n[" .. hold_callback_label .. "] " .. KOR.icons.arrow_bare .. "\n", 1)
		-- #((set extra callback label))
		local extra_callback_label = params.extra_callback_label
		if extra_callback_label then
			info = info
				:gsub("\n\n:", "\n\n[" .. extra_callback_label .. "] " .. KOR.icons.arrow_bare .. "\n", 1)
		end

		if overrule_props then
			overrule_props.info = info
		end
		params.info = info
	end

	if skip_modify_params then
		return
	end
	for field, value in pairs(overrule_props) do
		params[field] = value
	end
	if (overrule_props.enabled == false or (type(overrule_props.enabled) == "function" and not overrule_props.enabled())) then
		params["enabled"] = false
		params.disabled_message = "... button uitgeschakeld ...\n\n"
	end
	if params["enabled"] == false then
		if params["icon_text"] then
			params["icon_text"].fgcolor = KOR.colors.button_disabled
		elseif params["text_icon"] then
			params["text_icon"].fgcolor = KOR.colors.button_disabled
		elseif params["text"] then
			params["fgcolor"] = KOR.colors.button_disabled
		end
	end
end

function ButtonProps:set(params, overrule_props, debug)
	local mode = (params.hold_callback or (overrule_props and overrule_props.hold_callback)) and "choice_props" or "info_text"
	self:setOverruleProps(params, overrule_props, debug)
	local button_props
	if mode == "info_text" then
		button_props = {
			info_params = params,
		}
		self:initInfoCallback(button_props)
	else
		button_props = {
			choice_params = params,
		}
		self:initChoiceCallback(button_props)
	end

	return button_props
end

function ButtonProps:forceIconSettings(button, overrule_props)
	if not overrule_props then
		return button
	end
	local props = { "icon", "icon_size_ratio", "icon_height", "icon_width", "rotation_angle" }
	local prop
	local count = #props
	for i = 1, count do
		prop = props[i]
		if overrule_props[prop] then
			button[prop] = overrule_props[prop]
		end
	end
	return button
end

function ButtonProps:addDisabledButtonMessage(button_props, info)
	--* disabled_message prop could be set in ((ButtonProps#setOverruleProps)):
	if button_props and button_props.disabled_message and info then
		return button_props.disabled_message .. info
	end
	return info
end

function ButtonProps:execOrShowButtonDisabledMessage(callback, button_props)
	KOR.registry:unset(self.registry_index)
	UIManager:close(self.alert_dialog)
	if button_props.disabled_message then
		KOR.messages:notify("button was uitgeschakeld...")
		return
	end
	callback()
end

function ButtonProps:getFixedIconHeight(for_close_button)
	local fixed_icon_height = self.fixed_icon_height
	local factor = DX.s.is_ubuntu and 0.7 or 1.7
	if DX.s.is_mobile_device then
		factor = 0.94
	end
	if not fixed_icon_height then
		fixed_icon_height = DGENERIC_ICON_SIZE * factor
		self.fixed_icon_height = fixed_icon_height
	end

	if for_close_button then
		factor = factor - 0.2
		return DGENERIC_ICON_SIZE * factor
	end

	return self.fixed_icon_height
end

function ButtonProps:injectAdditionalChoiceCallbacks(buttons, choice_props, props)
	if choice_props.extra_callbacks then

		local icon = props.icon
		local icon_size_ratio = props.icon_size_ratio
		local text = props.text
		local font_face = props.font_face
		local font_size = props.font_size
		local font_bold = props.font_bold

		local extra_callbacks = choice_props.extra_callbacks
		for i = 1, #extra_callbacks do
			local ec = extra_callbacks[i]
			local extra_callback_label = ec.overrule_callback_label or ec.callback_label:lower()

			icon = self:setCustomIconForLastButton(icon, choice_props, extra_callback_label)

			local extra_callback = ec.callback
			local icon_text = icon and {
				icon = icon,
				icon_size_ratio = icon_size_ratio,
				text = " " .. extra_callback_label,
			} or nil
			--* we have a text icon:
			if text then
				text = ec.overrule_callback_label or text .. " " .. extra_callback_label
			end
			local item = {
				icon_text = icon_text,
				text = text,
				overruling_button_label = ec.overruling_button_label,
				text_font_face = font_face,
				text_font_size = font_size,
				font_bold = font_bold,
				callback = function()
					self:execOrShowButtonDisabledMessage(extra_callback, choice_props)
				end
			}
			if ec.for_separate_rows then
				KOR.buttontablefactory:injectButtonIntoTargetRows(buttons, item, 2, 3)
			else
				table.insert(buttons[1], 3, item)
			end
		end
	end
end

function ButtonProps:setCustomIconForLastButton(icon, props, label)
	if label == props.last_button_text and props.last_button_icon then
		return props.last_button_icon
	end
	return icon
end

function ButtonProps:setCustomIconForLastRemainingButton(parent)
	if parent.info_params.last_button_icon then
		parent.info_params.icon = parent.info_params.last_button_icon
		parent.info_params.last_button_icon = nil
	end
end

return ButtonProps
