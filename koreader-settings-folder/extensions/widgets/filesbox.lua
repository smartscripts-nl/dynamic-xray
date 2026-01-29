
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

local has_no_text = has_no_text
local math = math
local math_ceil = math.ceil
local math_floor = math.floor
local math_min = math.min
local table = table
local table_insert = table.insert
local type = type

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
    boxes = {},
    columns = 3,
    column_width = nil,
    font_face = "x_smallinfofont",
    font_size = 15,
    fullscreen = true,
    --* items must have props path and info (=text):
    items = {},
    row_spacer = nil,
    row_spacer_height = nil,
    subtitle = nil,
    thumbnail_width = nil,
    title = nil,
    window_size = "fullscreen",
    word_line_height = nil,
}

function FilesBox:init()
    self:setModuleProps()
    self:initFrame()
    self:initRowSpacer()
    self:setWidth()
    --* height will be computed below, after we build top and bottom components, when we know how much height they are taking
    self:generateTitleBar()
    self:setPaddingAndSpacing()
    self:computeLineHeight()
    self:computeWindowRegion()
    self:computeThumbnailDimensions()
    self:generateBoxes()
    self:injectRows()
    self:setSeparator()
    self:generateWidget()
    self:finalizeWidget()
end

--- @private
function FilesBox:generateBoxes()
    local box
    count = #self.items
    for i = 1, count do
        box = self:generateBox({
            info = self.items[i].info,
            meta_info = self.items[i].meta_info,
            font_bold = self.items[i].font_bold,
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
    if not bookinfo then
        return
    end
    local thumbnail, info, meta_info = self:getBoxElements(params, bookinfo)

    self.column_width = math_floor(self.screen_width / self.columns)
    local button_table = self:getBoxButtons(params, bookinfo)

    return self:getBoxContainer(thumbnail, info, meta_info, button_table)
end

--- @private
function FilesBox:getBoxElements(params, bookinfo)
    local thumbnail = self:getBookCover(bookinfo, params.path, nil, self.thumbnail_width, false, 0)

    local face = Font:getFace(self.font_face, self.font_size)
    local info = TextWidget:new{
        text = params.info,
        bold = params.font_bold,
        face = face,
        padding = 0,
    }
    local meta_info = TextWidget:new{
        text = params.meta_info,
        face = face,
        padding = 0,
    }
    return thumbnail, info, meta_info
end

--- @private
function FilesBox:getBoxButtons(params, bookinfo)
    local buttons = {{
          KOR.buttoninfopopup:forBookDescription({
              callback = function()
                  local description = params.description or bookinfo.description
                  if has_no_text(description) then
                      KOR.messages:notify(_("no description found"))
                      return true
                  end
                  KOR.dialogs:textBox({
                      title = params.info,
                      info = description,
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
          KOR.buttoninfopopup:forBookOpen({
              icon = "folder-open",
              callback = function()
                  UIManager:close(self)
                  KOR.files:openFile(params.path)
              end,
          }),
      }}
    local buttons_count = #buttons[1]
    local generic_icon_size = 40
    local icon_size = Screen:scaleBySize(generic_icon_size)

    return ButtonTable:new{
        width = buttons_count * icon_size + buttons_count * (Size.line.medium + Size.padding.small),
        buttons = buttons,
    }
end

--- @private
function FilesBox:getBoxContainer(thumbnail, info, meta_info, button_table)
    dimen = Geom:new{
        w = self.column_width,
        h = self.thumbnail_width
    }
    return CenterContainer:new{
        dimen = dimen,
        HorizontalGroup:new{
            thumbnail,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.column_width - self.thumbnail_width,
                    h = self.thumbnail_width,
                },
                VerticalGroup:new{
                    info,
                    meta_info,
                    button_table,
                }
            },
        }
    }
end

--- @private
function FilesBox:injectRows()
    local row
    local row_completed
    count = #self.boxes
    self.content_widget = VerticalGroup:new{}
    for i = 1, count do
        row_completed = i > 1 and (i % self.columns == 0 or i == count)
        row = row or HorizontalGroup:new{}
        table_insert(row, CenterContainer:new{
            dimen = dimen,
            self.boxes[i]
        })

        if row_completed then
            table_insert(self.content_widget, CenterContainer:new{
                dimen = { w = self.screen_width, h = self.thumbnail_width + self.row_spacer_height },
                row,
                self.row_spacer,
            })
            row = nil
        end
    end
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
    KOR.dialogs:closeAllOverlays()

    return true
end

--- @private
function FilesBox:finalizeWidget()
    --* self.region was set in ((FilesBox#computeThumbnailDimensions)):
    self[1] = WidgetContainer:new{
            align = "top",
            dimen = self.region,
            self.box_frame,
        }

    UIManager:setDirty(self, function()
        return "partial", self.box_frame.dimen
    end)

    --* make FilesBox widget closeable with ((Dialogs#closeAllWidgets)):
    KOR.dialogs:registerWidget(self)
end

--- @private
function FilesBox:generateWidget()

    local frame = self.frame_content_fullscreen

    local content_height = self.content_widget:getSize().h

    local elements = VerticalGroup:new{
        self.box_title,
        self.separator,
        self.content_top_margin,
        --* content
        CenterContainer:new{
            dimen = Geom:new{
                w = self.inner_width,
                h = content_height,
            },
            self.content_widget,
        },
        self.content_bottom_margin,
    }

    elements.align = "left"
    table.insert(frame, elements)
    self.box_frame = FrameContainer:new(frame)
end

--- @private
function FilesBox:computeWindowRegion()
    self.avail_height = self.screen_height - self.box_title:getSize().h

    --* Region in which the window will be aligned center/top/bottom:
    self.region = Geom:new{
        x = 0,
        y = 0,
        w = self.screen_width,
        h = self.avail_height,
    }

    local rows
    local items_count = #self.items
    rows = math_ceil(items_count / self.columns)

    self.thumbnail_width = math_floor(self.screen_width / (3 * self.columns))
end

--- @private
function FilesBox:computeThumbnailDimensions()
    local rows
    local items_count = #self.items
    rows = math_ceil(items_count / self.columns)

    self.thumbnail_width = math_floor(self.screen_width / (3 * self.columns))
end

--- @private
function FilesBox:setModuleProps()
    dimen = nil
    self.boxes = {}
    self.screen_height = Screen:getHeight()
    self.screen_width = Screen:getWidth()
end

--- @private
function FilesBox:setPaddingAndSpacing()
    --* This padding and the resulting width apply to the content
    --* below the title:  lookup word and definition
    self.content_padding_h = self.content_padding or (self.window_size == "fullscreen" or self.window_size == "max" or type(self.window_size) == "table") and Size.padding.closebuttonpopupdialog or Size.padding.large
    local content_padding_v = Size.padding.fullscreen --* added via VerticalSpan
    self.content_width = self.inner_width - 2 * self.content_padding_h

    self.content_padding_v =  content_padding_v

    --* Spans between components
    self.content_top_margin = VerticalSpan:new{ width = content_padding_v }
    self.content_bottom_margin = VerticalSpan:new{ width = content_padding_v }
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
        width = self.inner_width,
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
    self.box_title = TitleBar:new(config)
end

--- @private
function FilesBox:setWidth()
    self.width = self.screen_width
    self.inner_width = self.width
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
