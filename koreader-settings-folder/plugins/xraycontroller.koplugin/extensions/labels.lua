
local KOR = require("extensions/kor")
local _ = KOR:initCustomTranslations()

--- @class Labels
local Labels
Labels = {
    edit = {
        icon = "edit",
        icon_size_ratio = 0.5,
        text = _(" edit"),
    },
    new_item = {
        icon = "add",
        text = _(" add"),
    },
    show = {
        icon = "view",
        text = _(" view"),
    },
    remove = {
        icon = "dustbin",
        icon_size_ratio = 0.5,
        text = _(" remove"),
    },
    search = {
        icon = "appbar.search",
        text = _(" search"),
    },
}
return Labels
