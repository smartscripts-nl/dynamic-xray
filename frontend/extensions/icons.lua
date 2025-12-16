-- Zoek karakters op in Lettertypecatalogus op Mac, voor font NotoSans Nerd Font. Wijs gewenste karakter aan => code

--* small nbsp:
local spacer = "\u{202F}"

--- @class Icons
return {
    --* these are svg icons:
    chevron_left = "chevron.left",
    chevron_right = "chevron.right",
    chevron_first = "chevron.first",
    chevron_last = "chevron.last",

    --- specials:
    normal_spacer = "\u{2002}",
    en_dash_bare = "\u{2013}",

    arrow = "  →  ",
    arrow_bare = "→",
    arrow_down = "  ↓  ",
    arrow_down_bare = "↓",
    arrow_left = "  ←  ",
    arrow_left_bare = "←",
    arrow_up = "  ↑  ",
    arrow_up_bare = "↑",
    bullet = "  •  ",
    bullet_bare = "•",
    separator = "  •  ",
    enter = "⮠",
    first = "▕◁", --* de facto these are two characters
    first_bare = "▕◁ ", --* de facto these are four characters
    last = "▷▏", --* de facto these are two characters
    next = "▷",
    previous = "◁",
    last_bare = " ▷▏", --* de facto these are four characters,
    next_bare = "▷",
    previous_bare = "◁",

    active_tab = "\u{E98C}" .. spacer, -- massive right arrow
    active_tab_bare = "\u{E98C}",
    active_tab_minimal = "•\u{2002}",
    active_tab_minimal_bare = "•",
    alt_toc_symbol_bare = "\u{E298}", -- two-folders in circle (custom toc uses a pen in square symbol)
    back = "\u{E75A}" .. spacer, -- NW arrow; there is also a back.svg (rounded arrow to top left)
    back_bare = "\u{E75A}",
    book = "\u{E28B}" .. spacer, -- empty book
    book_bare = "\u{E28B}",
    bookmark = "\u{F097}" .. spacer, -- empty bookmark, E7C3 bookmark add
    bookmark_bare = "\u{F097}",
    bookmark_add = "\u{E7C3}" .. spacer, -- empty bookmark, E7C3 bookmark add
    bookmark_add_bare = "\u{E7C3}",
    bookmark_outline = "\u{E7C2}" .. spacer, -- bookmark open
    bookmark_outline_bare = "\u{E7C2}",
    checkmark = "\u{F00C}" .. spacer, -- ✓
    checkmark_bare = "\u{F00C}",
    clipboard = "\u{E84C}" .. spacer,
    clipboard_bare = "\u{E84C}",
    copy = "\u{E88E}" .. spacer, --  clipboard E84C, E890 content duplicate
    copy_bare = "\u{E88E}",
    description = "\u{F405}" .. spacer, -- E7BD book with one closed side; F15C file with text; F15B file without text, F405 book opened with lines
    description_bare = "\u{F405}",
    edit = "\u{F044}" .. spacer, -- pencil in checkbox
    edit_bare = "\u{F044}",
    erase = "\u{F014}" .. spacer, -- recycle bin
    erase_bare = "\u{F014}",
    file_open = "\u{F016}" .. spacer,
    file_open_bare = "\u{F016}",
    filter = "\u{E932}",
    filter_reset = "\u{E934}",
    highlight_bare = "\u{2592}",
    hold_callback_indicator = "\u{E340}" .. spacer, --  E340
    hold_callback_indicator_bare = "\u{E340}",
    lightning = "\u{26A1}" .. spacer,
    lightning_bare = "\u{26A1}",
    list = "\u{E978}" .. spacer, -- list numbers F0CB, E29A
    list_bare = "\u{E978}",
    lock = "\u{F023}" .. spacer,
    lock_bare = "\u{F023}",
    mark_current = "\u{F140}" .. spacer, -- E295 , E3D5 , E7B7 , E8A2 , E8A3 , F140 
    mark_current_bare = "\u{F140}",
    reset = "\u{EB58}" .. spacer, -- EB59 undo
    reset_bare = "\u{EB58}",
    save = "\u{F0C7}" .. spacer,
    save_bare = "\u{F0C7}",
    search = "\u{EA48}" .. spacer,
    search_bare = "\u{EA48}",
    spacer = "\u{2002}",
    today = "\u{E7EE}" .. spacer,
    today_bare = "\u{E7EE}",
    xray_add_item_bare = "\u{E713}",
    xray_alias = "\u{EF23}" .. spacer,
    xray_alias_bare = "\u{EF23}",
    xray_book_mode_bare = "\u{E28B}",
    xray_full = "\u{E39B}" .. spacer, -- full moon
    xray_full_bare = "\u{E39B}",
    xray_half_left = "\u{E3CE}" .. spacer, -- half moon left
    xray_half_left_bare = "\u{E3CE}",
    xray_half_right = "\u{E3DC}" .. spacer, -- half moon right
    xray_half_right_bare = "\u{E3DC}",
    xray_item = "★",
    xray_link = "\u{EAE1}" .. spacer,
    xray_link_bare = "\u{EAE1}",
    xray_partial = "\u{F140}" .. spacer,
    xray_partial_bare = "\u{F140}",
    xray_person_bare = "\u{F2C0}",
    xray_person_important_bare = "\u{F007}",
    xray_series_mode_bare = "\u{F2C0}",
    xray_tapped_collection = "\u{E70D}" .. spacer,
    xray_tapped_collection_bare = "\u{E70D}",
    xray_term_bare = "\u{EDE7}",
    xray_term_important_bare = "\u{EDE6}",
}
