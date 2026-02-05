
local require = require

local ButtonTable = require("extensions/widgets/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("extensions/modules/font")
local FrameContainer = require("extensions/widgets/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KOR = require("extensions/kor")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("extensions/modules/size")
local TextWidget = require("extensions/widgets/textwidget")
local TitleBar = require("extensions/widgets/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
--local logger = require("logger")
local Screen = Device.screen

local DX = DX
local has_no_text = has_no_text
local math = math
local math_ceil = math.ceil
local math_floor = math.floor
local math_min = math.min
local table = table
local table_insert = table.insert
local table_remove = table.remove

local scale_by_size = Screen:scaleBySize(1000000) / 1000000
local function _fontSize(dimen, nominal, max)
    --* The nominal font size is based on 64px ListMenuItem height.
    --* Keep ratio of font size to item height
    local font_size = math.floor(nominal * dimen.h / 64 / scale_by_size)
    --* But limit it to the provided max, to avoid huge font size when
    --* only 4-6 items per page
    if max and font_size >= max then
        return max
    end
    return font_size
end

local count, dimen

--- @class FilesBox
local FilesBox = InputContainer:extend{
    active_item_background = KOR.colors.background_gray_light,
    avail_height = nil,
    avail_width = nil,
    boxes = {},
    columns = DX.s.SeriesManager_columns_count,
    column_width = nil,
    font_face = "x_smallinfofont",
    font_size = 14,
    fullscreen = true,
    --* items must have props path and info (=text):
    items = {},
    key_events_module = nil,
    modal = true,
    non_series_box = nil,
    padding_vertical = nil,
    padding_vertical_height = Size.padding.fullscreen,
    row_spacer = nil,
    row_spacer_height = nil,
    subtitle = nil,
    thumbnail_width = nil,
    title = nil,
    titlebar = nil,
    titlebar_height = nil,
    window_size = "fullscreen",
    word_line_height = nil,
}

function FilesBox:init()
    self:initHotkeys()
    self:setPadding()
    self:setModuleProps()
    self:initFrame()
    self:initRowSpacer()
    self:setWidth()
    --* height will be computed below, after we build top and bottom components, when we know how much height they are taking
    self:generateTitleBar()
    self:computeLineHeight()
    self:computeWindowRegion()
    self:setColumnWidth()
    self:computeThumbnailDimensions()
    self:generateBoxes()
    if self.non_series_box then
        self:injectSingleRow()
    else
        self:injectRows()
    end
    self:setSeparator()
    self:generateWidget()
    self:finalizeWidget()
end

--- @private
function FilesBox:generateBoxes()
    if self.non_series_box then
        local box = self:generateBox(self.non_series_box)
        table_insert(self.boxes, box)
        return
    end
    local box
    count = #self.items
    for i = 1, count do
        box = self:generateBox({
            title_info = self.items[i].title_info,
            meta_info = self.items[i].meta_info,
            percentage_read = self.items[i].percentage_read,
            description = self.items[i].description,
            is_current_ebook = self.items[i].path == DX.m.current_ebook_full_path,
            path = self.items[i].path,
            callback = self.items[i].callback,
            hold_callback = self.items[i].hold_callback,
        })
        table_insert(self.boxes, box)
    end
end

--- @private
function FilesBox:generateBox(params)
    local bookinfo = KOR.bookinfomanager:getBookInfo(params.path, true)

    local thumbnail, title_info, meta_info, progress_bar = self:getBoxElements(params, bookinfo)

    local button_table = self:getBoxButtons(params)

    return self:getBoxContainer(params, thumbnail, title_info, meta_info, progress_bar, button_table)
end

--- @private
function FilesBox:getBoxElements(params, bookinfo)
    local thumbnail = self:getBookCover(bookinfo, params.path, nil, self.thumbnail_width, false, 0)

    local mark_by_text = params.is_current_ebook and not DX.s.SeriesManager_mark_active_title_with_border
    local font_size = mark_by_text and self.font_size + 1 or self.font_size
    local face = Font:getFace(self.font_face, font_size)
    local title_info = TextWidget:new{
        text = params.title_info,
        bold = mark_by_text,
        face = face,
        padding = 0,
    }
    local meta_info = TextWidget:new{
        text = params.meta_info,
        face = face,
        padding = 0,
    }
    local progress_bar
    if params.percentage_read then
        progress_bar = ProgressWidget:new{
            width = math_floor((self.column_width - self.thumbnail_width) * 0.7),
            height = Screen:scaleBySize(10),
            percentage = params.percentage_read,
            ticks = nil,
            last = nil,
        }
    end

    return thumbnail, title_info, meta_info, progress_bar
end

--- @private
function FilesBox:getBoxButtons(params)
    local buttons = {{
          KOR.buttoninfopopup:forBookDescription({
              callback = function()
                  KOR.dialogs:textOrHtmlBox({
                      title = params.title_info,
                      content = params.description,
                      no_buttons_row = true,
                      use_computed_height = true,
                  })
              end,
          }),
          KOR.buttoninfopopup:forBookCoverPreviewSmall({
              callback = function()
                  KOR.dialogs:showBookCover(params.path)
              end,
          }),
          KOR.buttoninfopopup:forBookMetadataEdit({
              icon = "edit-lighter",
              callback = function()
                  KOR.ebookmetadata:editEbookMetadata(params.path)
                  return true
              end
          }),
          KOR.buttoninfopopup:forBookOpen({
              icon = "folder-open",
              callback = function()
                  UIManager:close(self)
                  KOR.files:openFile(params.path)
              end,
          }),
      }}
    if params.is_current_ebook then
        table_remove(buttons[1])
    end
    if params.description == "-" or has_no_text(params.description) then
        table_remove(buttons[1], 1)
    end
    local buttons_count = #buttons[1]
    local generic_icon_size = 40
    local icon_size = math_floor(Screen:scaleBySize(generic_icon_size) * 0.9)

    return ButtonTable:new{
        no_separators = true,
        background = params.is_current_ebook and self.active_item_background or KOR.colors.white,
        width = buttons_count * icon_size,
        buttons = buttons,
    }
end

--- @private
function FilesBox:getBoxContainer(params, thumbnail, title_info, meta_info, progress_bar, button_table)
    dimen = Geom:new{
        w = self.column_width,
        h = self.thumbnail_width
    }
    local elements = VerticalGroup:new{
        title_info,
        meta_info,
        button_table,
    }
    if progress_bar then
        table_insert(elements, #elements, progress_bar)
    end
    local box = CenterContainer:new{
        dimen = dimen,
        HorizontalGroup:new{
            thumbnail,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.column_width - self.thumbnail_width,
                    h = self.thumbnail_width,
                },
                elements,
            },
        },
    }
    if DX.s.SeriesManager_mark_active_title_with_border and params.is_current_ebook then
        box = FrameContainer:new{
            radius = Size.radius.window,
            bordersize = Size.border.default,
            background = self.active_item_background,
            color = KOR.colors.darker_indicator_color,
            box,
        }
    end
    return box
end

--- @private
function FilesBox:injectRows()
    local row
    local row_completed
    self.content_widget = VerticalGroup:new{}
    count = #self.boxes
    for i = 1, count do
        row_completed = i > 1 and (i % self.columns == 0 or i == count)
        if not row then
            row = HorizontalGroup:new{}
        end
        table_insert(row, CenterContainer:new{
            dimen = dimen,
            self.boxes[i],
        })

        if row_completed then
            table_insert(self.content_widget, CenterContainer:new{
                dimen = { w = self.screen_width, h = self.thumbnail_width + self.row_spacer_height },
                row,
            })
            row = nil
        end
    end
end

--- @private
function FilesBox:injectSingleRow()
    self.content_widget = VerticalGroup:new{}
    local row = HorizontalGroup:new{}
    local half_width = math_floor(self.screen_width / 2)
    local sdimen = KOR.tables:shallowCopy(dimen)
    sdimen.w = half_width
    table_insert(row, CenterContainer:new{
        dimen = sdimen,
        self.boxes[1],
    })
    table_insert(self.content_widget, CenterContainer:new{
        dimen = { w = half_width, h = self.thumbnail_width + self.row_spacer_height },
        row,
        self.row_spacer,
    })
end

--- @private
function FilesBox:computeLineHeight()
    if not self.word_line_height then
        local test_widget = TextWidget:new{
            text = "z",
            face = Font:getFace(self.font_face, self.font_size),
        }
        self.word_line_height = test_widget:getSize().h
        test_widget:free()
    end
end

--- @private
function FilesBox:initFrame()
    self.frame_content_fullscreen = {
        radius = 0,
        bordersize = 0,
        fullscreen = true,
        covers_fullscreen = true,
        padding = 0,
        margin = 0,
        background = KOR.colors.background,
        --* make the borders white to hide them completely:
        color = KOR.colors.background,
    }
end

--- @private
function FilesBox:initRowSpacer()
    self.row_spacer_height = Screen:scaleBySize(15)
    self.row_spacer =
    VerticalSpan:new{ width = self.row_spacer_height }
end

function FilesBox:onCloseWidget()

    if self.after_close_callback then
        self.after_close_callback()
    end
    self.additional_key_events = nil

    --* NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
end

function FilesBox:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self.box_frame.dimen
    end)
    return true
end

function FilesBox:onClose()
    KOR.dialogs:unregisterWidget(self)
    UIManager:close(self)

    return true
end

--- @private
function FilesBox:finalizeWidget()

    --* self.region was set in ((FilesBox#computeThumbnailDimensions)):
    self[1] = WidgetContainer:new{
        align = "top",
        dimen = self.region,
        --* box_frame was generated in ((FilesBox#generateWidget)):
        self.box_frame,
    }

    UIManager:setDirty(self, function()
        return "partial", self.refresh_target.dimen
    end)

    --* make FilesBox widget closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
end

--- @private
function FilesBox:generateWidget()

    local frame = self.frame_content_fullscreen

    local content_height = self.content_widget:getSize().h

    local elements = VerticalGroup:new{
        align = "center",
        self.titlebar,
        self.separator,
        self.padding_vertical,
    }
    local total_height = self.titlebar_height + self.separator:getSize().h + 2 * self.padding_vertical_height + content_height
    local diff = self.screen_height - total_height
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local width = diff < 0 and self.width - scrollbar_width or self.width
    local main_content = CenterContainer:new{
            dimen = Geom:new{
            w = width,
                h = content_height,
            },
            self.content_widget,
    }
    if diff >= 0 then
        table_insert(elements, main_content)
        table_insert(elements, self.padding_vertical)
    end
    if diff > 0 then
        table_insert(elements, VerticalSpan:new{ width = diff })

    --* when the content does not fit in the available height, show a scrollbar:
    elseif diff < 0 then
        -- Our scrollable container needs to be known as widget.cropping_widget in
        -- the widget that is passed to UIManager:show() for UIManager to ensure
        -- proper interception of inner widget self repainting/invert (mostly used
        -- when flashing for UI feedback that we want to limit to the cropped area).
        self.cropping_widget = ScrollableContainer:new{
            dimen = Geom:new{
                w = width + scrollbar_width,
                h = self.screen_height - self.titlebar_height - 2 * self.padding_vertical_height,
            },
            show_parent = self,
            --ignore_events = { "swipe" },
            main_content,
        }
        table_insert(elements, self.cropping_widget)
        table_insert(elements, self.padding_vertical)

        self.refresh_target = self.cropping_widget
    end
    table_insert(frame, elements)
    self.box_frame = FrameContainer:new(frame)
    if diff >= 0 then
        self.refresh_target = self.box_frame
    end
end

--- @private
function FilesBox:computeWindowRegion()
    self.avail_height = self.screen_height - self.titlebar:getSize().h

    --* Region in which the window will be aligned center/top/bottom:
    self.region = Geom:new{
        x = 0,
        y = 0,
        w = self.screen_width,
        h = self.avail_height,
    }
end

--- @private
function FilesBox:setColumnWidth()
    self.column_width = math_floor(self.avail_width / self.columns)
end

--- @private
function FilesBox:computeThumbnailDimensions()
    local rows
    local items_count = #self.items
    rows = math_ceil(items_count / self.columns)

    --* the thumbnail should be 1/4 of the available box width and the text should take 3/4 of it:
    self.thumbnail_width = math_floor(self.avail_width / (self.columns * 4))
end

--- @private
function FilesBox:initHotkeys()
    KOR.keyevents:addHotkeysForFilesBox(self, self.key_events_module)
end

--- @private
function FilesBox:setModuleProps()
    self.columns = DX.s.SeriesManager_columns_count
    dimen = nil
    self.boxes = {}
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
    local factor = DX.s.SeriesManager_mark_active_title_with_border and 7 or 4
    if DX.s.SeriesManager_columns_count == 3 then
        factor = DX.s.SeriesManager_mark_active_title_with_border and 5 or 2
    end
    self.avail_width = DX.s.SeriesManager_columns_count == 2 and self.screen_width - factor * Size.padding.default or self.screen_width - factor * Size.padding.button
end

--- @private
function FilesBox:setPadding()
    self.padding_vertical = VerticalSpan:new{ width = self.padding_vertical_height }
end

--- @private
function FilesBox:setSeparator()
    self.separator = LineWidget:new{
        background = self.tabs_table and KOR.colors.tabs_table_separators or KOR.colors.line_separator,
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
end

--- @private
function FilesBox:generateTitleBar()
    local config = {
        width = self.screen_width,
        title = self.title,
        subtitle = self.subtitle,
        title_face = Font:getFace("smallinfofontbold"),
        --* FilesBox delivers the separator, so we don't want a separator in the titlebar:
        with_bottom_line = false,
        close_callback = function()
            self:onClose()
        end,
        close_hold_callback = function()
            self:onHoldClose()
        end,
        has_small_close_button_padding = true,
        align = self.title_alignment,
        show_parent = self,
        lang = self.lang_out,
        top_buttons_left = self.top_buttons_left,
    }
    self.titlebar = TitleBar:new(config)
    self.titlebar_height = self.titlebar:getSize().h
end

--- @private
function FilesBox:setWidth()
    self.width = self.screen_width
end

function FilesBox:getBookCover(bookinfo, full_path, width, height, is_deleted)

    local wleft

    if width then
        height = width
    else
        width = height
    end

    local cover_bb_used = false
    local wleft_height = height
    local wleft_width = wleft_height --* make it squared

    self.underline_h = 1 --* smaller than default (3) to not shift our vertical aligment

    --* we'll add a VerticalSpan of same size as underline container for balance
    local cdimen = Geom:new{
        w = width,
        h = height - 2 * self.underline_h
    }

    local border_size = Size.border.thin
    local max_img_w = cdimen.h - 2 * border_size --* width = height, squared
    local max_img_h = cdimen.h - 2 * border_size

    if KOR.bookinfomanager:hasCover(full_path) then

        cover_bb_used = true

        --* Let ImageWidget do the scaling and give us the final size
        local scale_factor = math_min(max_img_w / bookinfo.cover_w, max_img_h / bookinfo.cover_h)
        local wimage = ImageWidget:new{
            image = bookinfo.cover_bb,
            scale_factor = scale_factor,
        }
        wimage:_render()
        local image_size = wimage:getSize() --* get final widget size
        local image_container = CenterContainer:new{
            dimen = Geom:new{ w = wleft_width, h = wleft_height },
            FrameContainer:new{
                width = image_size.w + 2 * border_size,
                height = image_size.h + 2 * border_size,
                margin = 0,
                padding = 0,
                bordersize = border_size,
                dim = false,
                wimage,
            }
        }
        wleft = image_container
        return wleft, cover_bb_used
    end

    local fake_cover_w = max_img_w * 0.6
    local fake_cover_h = max_img_h
    wleft = CenterContainer:new{
        dimen = Geom:new{ w = wleft_width, h = wleft_height },
        FrameContainer:new{
            width = fake_cover_w + 2 * border_size,
            height = fake_cover_h + 2 * border_size,
            margin = 0,
            padding = 0,
            bordersize = border_size,
            dim = is_deleted,
            CenterContainer:new{
                dimen = Geom:new{ w = fake_cover_w, h = fake_cover_h },
                TextWidget:new{
                    text = "⛶", --* U+26F6 Square four corners
                    face = Font:getFace("cfont", _fontSize(cdimen, 20, 24)),
                },
            },
        },
    }

    return wleft, cover_bb_used, bookinfo
end

return FilesBox
