local KOR = require("extensions/kor")
local Registry = require("extensions/registry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class ReaderSearch
local ReaderSearch = WidgetContainer:extend {
    -- [...]
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)

    -- [...]

    KOR:registerPlugin("readersearch", self)
end

-- [...]

function ReaderSearch:onShowFindAllResults(not_cached)
    if not self.last_search_hash or (not not_cached and self.findall_results == nil) then
        -- no cached results, show input dialog
        self:onShowFulltextSearchInput()
        return
    end

    -- for consumption in ((XrayItems#onMenuHold)):
    Registry:set("reader_search_active", true)

    -- [...]
end

-- [...]

return ReaderSearch
