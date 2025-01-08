--[[
ReaderUI is an abstraction for a reader interface.

It works using data gathered from a document interface.
]]--

local Device = require("device")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local Registry = require("extensions/registry")
local Screen = Device.screen

--- @class ReaderUI
local ReaderUI = InputContainer:extend {
    -- [...]
}

-- [...]

function ReaderUI:init()
    self.active_widgets = {}

    -- cap screen refresh on pan to 2 refreshes per second
    local pan_rate = Screen.low_pan_rate and 2.0 or 30.0

    -- ! extensions MUST be registered here, not later! Otherwise not available as KOR.extension_name:
    self:registerExtensions()


    -- [...]

    ReaderUI.instance = self

    -- so we can request document etc. in other scripts:
    Registry:set("document", self.document)
    -- #((set ui))
    Registry:set("ui", self)
    Registry:set("view", self.view)
    Registry:set("footer", self.view.footer)
    Registry:set("inebook", true)
end

-- [...]

-- ! Watch out: extensions which are loaded here MUST also be typed in ((KOR)) and have a @class declaration themselves, to have them available for code hinting!
--- @class ExtensionsInit
function ReaderUI:registerExtensions()
    -- ! if you want to have support for self.ui when using these extensions as a module somewhere, load them not via require, but refence their methods like so: KOR.extension_name:method() ...
    for _, name in ipairs(KOR.extensions_list) do
        local extension = require("extensions/" .. name)
        local instance
        --- extensions without constructor are for now bookinfomanager and readcollection...
        if extension.new then
            instance = extension:new {
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            }
        else
            table.insert(KOR.extensions_without_constructor, name)
            instance = extension
        end
        instance.name = "reader" .. name
        --instance.name = name
        KOR[name] = instance

        if instance.init then
            -- e.g. call ((Collection#init)):
            instance:init()
        end
    end
end

return ReaderUI
