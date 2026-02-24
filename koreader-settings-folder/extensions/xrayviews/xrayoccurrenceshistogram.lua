
--* see ((Dynamic Xray: module info)) for more info

local require = require

local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local HistogramWidget = require("extensions/widgets/histogramwidget")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local math_floor = math.floor

--- @class XrayOccurrencesHistogram
local XrayOccurrencesHistogram = WidgetContainer:new{
    chapters_count = nil,
    information_dialog = nil,
    occurrences_per_chapter = nil,
    occurrences_subject = nil,
}

function XrayOccurrencesHistogram:generateChapterOccurrencesHistogram(data)

    if not data.ratio_per_chapter or not DX.s.PN_show_chapter_hits_histogram then
        local height = data.histogram_height + data.histogram_bottom_line_height
        return DX.pn:getEmptyFillElement(data.info_panel_width, height)
    end

    self.occurrences_subject = data.occurrences_subject
    self.occurrences_per_chapter = data.occurrences_per_chapter
    local ratio_per_chapter = data.ratio_per_chapter
    local current_chapter_index = data.current_chapter_index
    self.chapters_count = data.chapters_count
    local info_panel_width = data.info_panel_width
    local histogram_height = data.histogram_height
    local histogram_bottom_line_height = data.histogram_bottom_line_height

    local bottom_line = LineWidget:new{
        background = KOR.colors.histogram_bar_light,
        dimen = Geom:new{
            w = info_panel_width,
            h = histogram_bottom_line_height,
        }
    }
    --* at about 50 items will give a nice distribution of not too wide histogram bars; if there are significantly less chapters, we reduce the width of the histogram, so the bars will not get too wide:
    local histogram_width = info_panel_width
    if self.chapters_count <= 45 then
        histogram_width = math_floor(self.chapters_count / 50 * histogram_width)
    end

    return CenterContainer:new{
        dimen = Geom:new{ w = info_panel_width, h = histogram_height + histogram_bottom_line_height },
        VerticalGroup:new{
            HistogramWidget:new{
                current_chapter_index = current_chapter_index,
                height = histogram_height,
                histogram_type = "chapterpages",
                nb_items = self.chapters_count,
                occurrences_per_chapter = self.occurrences_per_chapter,
                ratios = ratio_per_chapter,
                show_parent = self,
                width = histogram_width,
            },
            bottom_line,
        }
    }
end

--- @private
function XrayOccurrencesHistogram:handleBeforeGotoPageRequest(page)
    UIManager:close(self.information_dialog)
    if not page then
        KOR.messages:notify(_("page number of chapter could not be determined"))
        return false
    end
    DX.pn:closePageNavigator()
    return true
end

function XrayOccurrencesHistogram:chapterTapCallback(n)
    return self:showChapterInformation(n)
end

function XrayOccurrencesHistogram:chapterHoldCallback(n)
    return self:showChapterInformation(n)
end

--- @private
function XrayOccurrencesHistogram:showChapterInformation(n)
    --* DX.vd.book_chapters was populated in ((XrayDataLoader#_populateViewsDataBookChapters)):
    local chapter_title = DX.vd.book_chapters[n] or "-"
    local page
    local display_page = ""
    if chapter_title ~= "-" then
        page = KOR.toc:getPageFromItemTitle(chapter_title)
        display_page = _(", page") .. " " .. page
    end

    local buttons = DX.b:forChapterInformationPopup(self, page)

    if page then
        local needles = DX.vd:getXrayItemNameVariants(self.occurrences_subject)

        local chapter_html = KOR.pagetexts:getChapterText("as_html", needles, page)
        local title = self.occurrences_subject.name
        if chapter_title ~= "-" then
            title = title .. ", in: " .. chapter_title
        end
        self.information_dialog = KOR.dialogs:htmlBox({
            title = title,
            fullscreen = true,
            html = T("<p><strong>Stats</strong><br />%1</p><ul><li>Chapter %2/%3%4<br/>\n\"%5\"</li>\n<li>Occurrences: %6</li></ul><p>%7<br /><strong>All mentions int the chapter</strong><br />%8</p>\n", " ", n, self.chapters_count, display_page, chapter_title, self.occurrences_per_chapter[n], " ", " ") .. chapter_html,
            buttons = buttons,
        })
        return true
    end

    self.information_dialog = KOR.dialogs:niceAlert(self.occurrences_subject, T(_("Chapter %1/%2%3%4\"%5\"%6Occurrences: %7"), n, self.chapters_count, display_page, "\n", chapter_title, "\n\n", self.occurrences_per_chapter[n]), {
        buttons = buttons
    })
    return true
end

return XrayOccurrencesHistogram
