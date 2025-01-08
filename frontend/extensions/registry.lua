
local Event = require("ui/event")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

-- used as registry for global vars:
--- @class Registry
local Registry = WidgetContainer:new{
	device = nil,
	ereader_model = nil,
	half_screen_width = nil,
	hold_menu_input_delay = 0.9,
	is_android_device = false,
	is_kobo_device = false,
	is_non_kobo_device = true,
	is_ubuntu_device = false,
	line_height = 0.13,
	-- set with Registry:set("ui" ...; see ((set ui)):
	ui = nil,
}

function Registry:get(index, force_update)
	if index == "ereader_model" then

		if self.ereader_model then
			return self.ereader_model
		end

		local device = require("device")
		self.ereader_model = self.ereader_model or (device.model == "Kobo_frost" and "Forma" or "Boox Page")
		if lfs.attributes("/home/alex/Desktop/KOReader-books") then
			device.model = "Ubuntu"
			self.device = "ubuntu"
			self.ereader_model = "Ubuntu"
			self.is_ubuntu_device = true
		else
			if self.ereader_model == "Forma" then
				self.is_kobo_device = true
				self.is_non_kobo_device = false
				self.device = "kobo"
			else
				self.is_android_device = true
				self.device = "android"
			end
		end
		return self.ereader_model

	elseif force_update and (index == "ui" or index == "view" or index == "document") then
		self:get("ui"):handleEvent(Event:new("SetContext"))
	end

	return AX_registry[index]
end

function Registry:getOnce(index, force_update)
	local value = self:get(index, force_update)
	self:unset(index)
	return value
end

function Registry:set(index, value)
	AX_registry[index] = value
	if index == "ui" then
		self.ui = value
	end
end

function Registry:getDocument()
	return self:get("document")
end

function Registry:getUI()
	return self:get("ui")
end

function Registry:unset(index, ...)
	AX_registry[index] = nil
	for _, prop in ipairs({ ... }) do
		AX_registry[prop] = nil
	end
end

return Registry
