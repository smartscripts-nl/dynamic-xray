
local FocusManager = require("ui/widget/focusmanager")

--- @class InputDialog
local InputDialog = FocusManager:extend{
    -- [...]
}

function InputDialog:init()

    -- [...]

    -- InputText
    if not self.text_height or self.fullscreen then
        -- We need to find the best height to avoid screen overflow

        -- [...]

        -- Find out available height
        local title_bar_height = self.title_bar and self.title_bar:getHeight() or 0
        local available_height = self.screen_height
            - 2*self.border_size
            - title_bar_height
            - vspan_before_input_text:getSize().h
            - input_pad_height
            - vspan_after_input_text:getSize().h
            - buttons_container:getSize().h
            - keyboard_height

        self:storeKeyboardHeight(keyboard_height)

        -- [...]
    end

    -- [...]
end

-- [...]

-- ----------------------- ADDED --------------------------

-- see ((MAX DIALOG HEIGHT)):
function InputDialog:storeKeyboardHeight(keyboard_height)
    local stored_height = G_reader_settings:readSetting("keyboard_height")
    if not stored_height or stored_height ~= keyboard_height then
        G_reader_settings:saveSetting("keyboard_height", keyboard_height)
    end
end

return InputDialog
