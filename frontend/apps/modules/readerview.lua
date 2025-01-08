--[[--
ReaderView module handles all the screen painting for document browsing.
]]

local OverlapGroup = require("ui/widget/overlapgroup")
local XrayHelpers = require("extensions/xrayhelpers")

--- @class ReaderView
local ReaderView = OverlapGroup:extend{
    -- [...]
}

-- [...]

function ReaderView:paintTo(bb, x, y)

    -- [...]

    -- draw temporary highlight
    if self.highlight.temp then
        self:drawTempHighlight(bb, x, y)
    end
    -- paint xray indicators
    XrayHelpers:ReaderViewGenerateXrayInformation(self.ui, bb, x, y)

    -- [...]
end

-- [...]

return ReaderView
