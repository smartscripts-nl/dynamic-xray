
local Blitbuffer = require("ffi/blitbuffer")

--- @class Colors This is kind of a stylesheet for Blitbuffer colors used in the KOReader scripts
return {

    --* see ((BLITBUFFER_COLORS)) for color definitions

    --* Blitbuffer.COLOR_DARK_GRAY (disabled color, substitutes de facto the missing Blitbuffer.COLOR_GRAY_8; colors go from COLOR_BLACK, COLOR_GRAY_1 to COLOR_GRAY_E AND COLOR_WHITE):

    black = Blitbuffer.COLOR_BLACK,

    active_tab = Blitbuffer.COLOR_BLACK,
    inactive_tab = Blitbuffer.COLOR_GRAY_4,
    tabs_table_separators = Blitbuffer.COLOR_GRAY,

    background = Blitbuffer.COLOR_WHITE,
    background_gray = Blitbuffer.COLOR_LIGHT_GRAY,
    background_gray_light = Blitbuffer.COLOR_GRAY_D,
    background_inverted = Blitbuffer.COLOR_LIGHT_GRAY,

    bold_button_text_color = Blitbuffer.COLOR_DARK_GRAY,

    button_active = Blitbuffer.COLOR_GRAY_D,
    button_default = Blitbuffer.COLOR_BLACK,
    button_disabled = Blitbuffer.COLOR_GRAY_B,
    button_invisible = Blitbuffer.COLOR_WHITE,
    button_label = Blitbuffer.COLOR_GRAY_3,
    button_light = Blitbuffer.COLOR_GRAY_7,

    label_enabled = Blitbuffer.COLOR_BLACK,
    label_disabled = Blitbuffer.COLOR_DARK_GRAY,

    darker_indicator_color = Blitbuffer.COLOR_GRAY_5,
    lighter_indicator_color = Blitbuffer.COLOR_GRAY_7,
    lighter_indicator_hold_color = Blitbuffer.COLOR_GRAY_9,

    histogram_bar_dark = Blitbuffer.COLOR_GRAY_1,
    histogram_bar_light = Blitbuffer.COLOR_GRAY_5,

    lighter_legend_item = Blitbuffer.COLOR_GRAY_6,

    lighter_text = Blitbuffer.COLOR_GRAY_3,

    readonly_inverted = Blitbuffer.COLOR_WHITE,

    line_separator = Blitbuffer.COLOR_GRAY_9,

    menu_line = Blitbuffer.COLOR_DARK_GRAY,
    menu_mandatory_dim = Blitbuffer.COLOR_DARK_GRAY,
    menu_underline = Blitbuffer.COLOR_BLACK,

    scrollbar_color = Blitbuffer.COLOR_LIGHT_GRAY,

    separator_vertical_color = Blitbuffer.COLOR_GRAY,

    title_bar_bottom_line = Blitbuffer.COLOR_GRAY,
    title_bar_with_submenu_bottom_line = Blitbuffer.COLOR_GRAY_9,
    title_bar_bottom_line_light = Blitbuffer.COLOR_LIGHT_GRAY,

    white = Blitbuffer.COLOR_WHITE,

    xray_item_status_indicators_color = Blitbuffer.COLOR_GRAY_5,
    xray_page_or_paragraph_match_marker = Blitbuffer.COLOR_GRAY_9,
}
