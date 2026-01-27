
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local AX_registry = AX_registry
local AXR_registry = AXR_registry
--! don't declare has_content or has_text or last_file locally here!
local math = math
local type = type

--* used as registry for global vars:
--- @class Registry
local Registry = WidgetContainer:new{
    current_ebook = nil,
    --* will be populated by ((Font#getDefaultDialogFontFace)):
    default_dialog_font = nil,
    half_screen_width = nil,
    info_callbacks_show_indicators = true,
    input_text_font_size = 20,
    line_height = 0.13,
    line_height_red_hat_text = 0.24,
    menu_subpages = {},
    return_to_list = false,
    scroll_messages = {
        "dynamische hoogte",
        "vaste hoogte met scroll",
        "vaste hoogte zonder scroll",
    },
    use_overlay_when_opening_files = true,
    use_scrolling_dialog = 2,
}

--* AX_registry defined in ((ExtensionsInit)) (as early as possible):
function Registry:get(index, set_if_missing_callback)
    if index == "current_ebook" and not AX_registry[index] then
        AX_registry[index] = last_file()
        return AX_registry[index]
    end
    if AX_registry[index] == nil and set_if_missing_callback then
        AX_registry[index] = set_if_missing_callback()
    end
    return AX_registry[index]
end

function Registry:getMenuPage(module)
    return self.menu_subpages[module]
end

function Registry:getMenuSelectNumber(module, items_per_page)
    local subpage = self.menu_subpages[module]
    if subpage then
        return math.floor(subpage * items_per_page - 1)
    end
end

function Registry:setMenuPage(module, page)
    self.menu_subpages[module] = page
end

function Registry:getOnce(index, default_value)
    local value = self:get(index)
    self:unset(index)
    if not value and default_value then
        return default_value
    end
    return value
end

function Registry:isset(indices)
    if not indices or type(indices) ~= "table" then
        return false
    end
    local prop
    local count = #indices
    for i = 1, count do
        prop = indices[i]
        if self:get(prop) then
            return true
        end
    end
    return false
end

function Registry:save(index, value)
    self:set(index, value)
end

function Registry:set(index, value)
    AX_registry[index] = value
end

function Registry:unset(index, ...)
    AX_registry[index] = nil
    local prop
    local args = { ... }
    local count = #args
    for i = 1, count do
        prop = args[i]
        AX_registry[prop] = nil
    end
end

function Registry:toggleScrollingDialog()

    --* we don't have to see an info alert to inform us about the change; we can see that the setting has changed because the height of the window changes and will be fixed if use_scrolling_dialog is 3:
    self.use_scrolling_dialog = self.use_scrolling_dialog + 1
    if self.use_scrolling_dialog > 3 then
        self.use_scrolling_dialog = 1
    end
    KOR.messages:notify("scrolling ingesteld op " .. self.scroll_messages[self.use_scrolling_dialog])
end

--* AXR_registry (renewable upon file updates etc.) defined in ((ExtensionsInit)) (as early as possible):
function Registry:r_get(index)
    return AXR_registry[index]
end

function Registry:r_set(index, value)
    --* AXR_registry is a resettable registry:
    AXR_registry[index] = value
end

return Registry
