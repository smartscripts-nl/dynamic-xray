
local require = require

local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local Math = require("optmath")

local math = math
local table = table
local tostring = tostring

--* here extend InputContainer instead of Widget class, so clicks on histogram bars will be detected:
--- @class HistogramWidget
local HistogramWidget = InputContainer:extend{
    day_ts = nil,
    height = nil,
    histogram_bar_dark = KOR.colors.histogram_bar_dark,
    histogram_bar_light = KOR.colors.histogram_bar_light,
    histogram_type = nil,
    is_touch_device = Device:isTouchDevice(),
    max_ratio_indices = {},
    next_reading_target_epages_index = nil,
    nb_items = nil,
    ratios = nil, --* table of 1...nb_items items, each with (0 <= value <= 1)
    rounded_bars = false,
    show_parent = nil,
    time_units_timestamps = nil,
    width = nil,
}

function HistogramWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    if self.is_touch_device then
        self.ges_events = {}
    end
    local item_width = math.floor(self.width / self.nb_items)
    local nb_item_width_add1 = self.width - self.nb_items * item_width
    local nb_item_width_add1_mod = math.floor(self.nb_items / nb_item_width_add1)
    self.item_widths = {}
    for n = 1, self.nb_items do
        local w = item_width
        if nb_item_width_add1 > 0 and n % nb_item_width_add1_mod == 0 then
            w = w + 1
            nb_item_width_add1 = nb_item_width_add1 - 1
        end
        table.insert(self.item_widths, w)
    end
    if BD.mirroredUILayout() then
        self.do_mirror = true
    end

    if self.is_touch_device then
        self.ges_events.EmptySpacetap = {
            GestureRange:new {
                ges = "tap",
                range = self.dimen,
            },
            doc = "Nullify taps on empty space in the widget.",
        }
    end

    self:setBarTapHandlers()
end

--* compare ((HistogramWidget#setBarTapHandlers)):
function HistogramWidget:setBarTapGestures(xp, i_x, yp, i_y, i_w, i_h, n)
    if self.is_touch_device then

        if self.histogram_type == "months" then
            local dimen = Geom:new{ x = xp + i_x, y = yp + i_y, w = i_w, h = i_h }
            self.ges_events["ShowMonth" .. n] = {
                GestureRange:new{
                    ges = "tap",
                    range = dimen,
                },
                doc = "Show reading statistics for this month.",
            }
            self.ges_events["ShowMonthHold" .. n] = {
                GestureRange:new{
                    ges = "hold",
                    range = dimen,
                },
                doc = "Show reading calendar for this month.",
            }

        elseif self.histogram_type == "days" then
            local dimen = Geom:new{ x = xp + i_x, y = yp + i_y, w = i_w, h = i_h }
            self.ges_events["ShowDay" .. n] = {
                GestureRange:new{
                    ges = "tap",
                    range = dimen,
                },
                doc = "Show reading statistics for this day.",
            }
            self.ges_events["ShowDayHold" .. n] = {
                GestureRange:new{
                    ges = "hold",
                    range = dimen,
                },
                doc = "Show reading calendar for this day.",
            }

        elseif self.histogram_type == "day" then
            local dimen = Geom:new{ x = xp + i_x, y = yp + i_y, w = i_w, h = i_h }
            self.ges_events["ShowHour" .. n] = {
                GestureRange:new{
                    ges = "tap",
                    range = dimen,
                },
                doc = "Show reading statistics for this day/hour.",
            }
            self.ges_events["ShowHourHold" .. n] = {
                GestureRange:new{
                    ges = "hold",
                    range = dimen,
                },
                doc = "Show reading calendar for this day.",
            }

        elseif self.histogram_type == "chapterpages" then
            local dimen = Geom:new{ x = xp + i_x, y = yp + i_y, w = i_w, h = i_h }
            self.ges_events["ShowChapter" .. n] = {
                GestureRange:new{
                    ges = "tap",
                    range = dimen,
                },
                doc = "Show ocurrences per chapter.",
            }
            self.ges_events["ShowChapterHold" .. n] = {
                GestureRange:new{
                    ges = "hold",
                    range = dimen,
                },
                doc = "Show ocurrences per chapter.",
            }
        end
    end
end

--! compare ((HistogramWidget#setBarTapGestures)); there the handlers defined below must be linked!:
function HistogramWidget:setBarTapHandlers()
    --* handle clicks on histogram bars:
    --* these dynamically defined methods have to be called from ((HistogramWidget#setBarTapGestures)):
    if self.histogram_type == "months" then
        for n = 1, KOR.histogramcontroller.histogram_months do
            self["onShowMonth" .. n] = function()
                return self.show_parent:monthTapCallback(n)
            end
            self["onShowMonthHold" .. n] = function()
                return self.show_parent:monthHoldCallback(n)
            end
        end

    elseif self.histogram_type == "days" then
        for n = 1, KOR.histogramcontroller.histogram_days do
            self["onShowDay" .. n] = function()
                return self.show_parent:dayTapCallback(n)
            end
            self["onShowDayHold" .. n] = function()
                return self.show_parent:dayHoldCallback(n)
            end
        end

    elseif self.histogram_type == "day" then
        for n = 1, 24 do
            self["onShowHour" .. n] = function()
                return self.show_parent:hourTapCallback()
            end
            self["onShowHourHold" .. n] = function()
                return self.show_parent:hourHoldCallback()
            end
        end

    elseif self.histogram_type == "chapterpages" then
        for n = 1, self.nb_items do
            self["onShowChapter" .. n] = function()
                return self.show_parent:chapterTapCallback(n)
            end
            self["onShowChapterHold" .. n] = function()
                return self.show_parent:chapterHoldCallback(n)
            end
        end
    end
end

function HistogramWidget:onEmptySpacetap()
    return true
end

function HistogramWidget:paintTo(bb, xp, yp)
    local i_x = 0
    local r = self.rounded_bars and 6 or nil
    for n = 1, self.nb_items do
        if self.do_mirror then
            n = self.nb_items - n + 1
        end

        local i_w = self.item_widths[n]
        local ratio = self.ratios and self.ratios[n] or 0
        local i_h = Math.round(ratio * self.height)
        if i_h == 0 and ratio > 0 then
            --* show at least 1px
            i_h = 1
        end
        local i_y = self.height - i_h
        if i_h > 0 then
            -- #((paint histogram bar))
            --* indicate columns with most read pages by darker color:
            local color = #self.max_ratio_indices > 0 and KOR.tables:tableHas(self.max_ratio_indices, n)
                and self.histogram_bar_dark
                or
                self.histogram_bar_light
            bb:paintRoundedRect(xp + i_x, yp + i_y, i_w, i_h, color, r)
            self:setBarTapGestures(xp, i_x, yp, i_y, i_w, i_h, n)

            --* mark bar with next target of epages by painting a light bar of 5px height above it:
            if n == self.next_reading_target_epages_index then
                bb:paintRoundedRect(xp + i_x, yp, i_w, 5, self.histogram_bar_light, r)
            end
        end
        i_x = i_x + i_w
    end
end

return HistogramWidget
