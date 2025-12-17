-- /home/alex/.config/koreader/settings/settings_manager.lua
return {
    ["xray_settings"] = {
        ["batch_count_for_import"] = {
            ["explanation"] = "Dit getal bepaalt in hoeveel batches Xray items uit een andere boeken worden geïmporteerd. Zijn dat heel veel items, dan is een hoger getal waarschijnlijk verstandig.",
            ["locked"] = 0,
            ["value"] = 5,
        },
        ["is_mobile_device"] = {
            ["explanation"] = "Deze variabele regelt een aantal standaard instellingen voor smalle schermen",
            ["locked"] = 0,
            ["value"] = false,
        },
        ["is_ubuntu"] = {
            ["explanation"] = "Deze variabele regelt een aantal instellingen voor gebruik van KOReader onder Ubuntu, bijv. dat je met de ESC-toets sommige vensters kunt sluiten",
            ["locked"] = 0,
            ["value"] = true,
        },
        ["landscape_description_field_height"] = {
            ["explanation"] = "Deze instelling door Dynamic Xray automatisch berekend en kan daarom niet worden aangepast door de gebruiker.",
            ["locked"] = 1,
        },
        ["portrait_description_field_height"] = {
            ["explanation"] = "Deze instelling door Dynamic Xray automatisch berekend en kan daarom niet worden aangepast door de gebruiker.",
            ["locked"] = 1,
        },
        ["ui_mode"] = {
            ["explanation"] = "Deze instelling bepaalt of er op paginas één bliksem marker, of ster-markers per alinea worden weergegeven",
            ["locked"] = 0,
            ["options"] = {
                [1] = "page",
                [2] = "paragraph",
            },
            ["value"] = "page",
        },
    },
    ["xray_settings_overrule"] = false,
}
