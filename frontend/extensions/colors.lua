
local Blitbuffer = require("ffi/blitbuffer")

--- @class Colors This is kind of a stylesheet for colors used in the scripts
return {
    -- info: Blitbuffer.COLOR_DARK_GRAY (disabled color, substitutes de facto the missing Blitbuffer.COLOR_GRAY_8; colors go from COLOR_BLACK, COLOR_GRAY_1 to COLOR_GRAY_E AND COLOR_WHITE):

    black = Blitbuffer.COLOR_BLACK,

    active_tab = Blitbuffer.COLOR_BLACK,
    inactive_tab = Blitbuffer.COLOR_GRAY_4,

    background = Blitbuffer.COLOR_WHITE,
    background_gray = Blitbuffer.COLOR_LIGHT_GRAY,

    bold_button_text_color = Blitbuffer.COLOR_DARK_GRAY,

    button_default = Blitbuffer.COLOR_BLACK,
    button_disabled = Blitbuffer.COLOR_DARK_GRAY,
    button_invisible = Blitbuffer.COLOR_WHITE,
    button_label = Blitbuffer.COLOR_GRAY_3,

    label_enabled = Blitbuffer.COLOR_BLACK,
    label_disabled = Blitbuffer.COLOR_DARK_GRAY,

    darker_indicator_color = Blitbuffer.COLOR_GRAY_5,
    lighter_indicator_color = Blitbuffer.COLOR_GRAY_7,
    lighter_indicator_hold_color = Blitbuffer.COLOR_GRAY_9,

    lighter_text = Blitbuffer.COLOR_GRAY_3,

    readonly_inverted = Blitbuffer.COLOR_WHITE,

    line_separator = Blitbuffer.COLOR_GRAY_9,

    menu_line = Blitbuffer.COLOR_DARK_GRAY,
    menu_mandatory_dim = Blitbuffer.COLOR_DARK_GRAY,
    menu_underline = Blitbuffer.COLOR_BLACK,

    title_bar_bottom_line = Blitbuffer.COLOR_GRAY,

    xray_page_or_paragraph_match_marker = Blitbuffer.COLOR_GRAY_9,
}
