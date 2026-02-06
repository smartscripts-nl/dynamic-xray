
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DX = DX
local tonumber = tonumber
local type = type

--- @class StatisticsHelpers
local StatisticsHelpers = WidgetContainer:extend{}

--- @param percentage string If given, then in format "current_page/total_pages"
function StatisticsHelpers:getPagesReadPercentage(full_path, percentage)
    local current_page, total_pages
    local is_current_ebook = full_path == DX.m.current_ebook_full_path or not percentage
    if is_current_ebook then
        current_page = KOR.ui:getCurrentPage()
        total_pages = KOR.document:getPageCount()
        if current_page and total_pages and total_pages > 0 then
            --* this is the format expected by ((SeriesManager#getMetaInformation)):
            --! so here we return data for the current ebook, so we return total_pages also, because more up-to-date than data retrieved from db:
            return current_page .. "/" .. total_pages, current_page / total_pages, total_pages
        end
    end

    if type(percentage) == "string" then
        current_page, total_pages = percentage:match("^(%d+)/(%d+)")
        current_page = tonumber(current_page)
        total_pages = tonumber(total_pages)
        if not current_page or not total_pages then
            return
        end
        return percentage, current_page / total_pages
    end
end

return StatisticsHelpers
