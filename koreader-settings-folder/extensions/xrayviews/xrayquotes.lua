--* see ((Dynamic Xray: module info)) for more info

local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local has_text = has_text
local math = math
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort
local tonumber = tonumber

local count

--- @class XrayQuotes
local XrayQuotes = WidgetContainer:new{}

function XrayQuotes:generateQuotesList(item)
    if not item.pos_chapter_quotes then
        return
    end
    local data = item.pos_chapter_quotes
    local items = KOR.strings:split(data, "@@")
    local ebooks, lookup = {}, {}
    local parts, etitle

    count = #items
    for i = 1, count do
        parts = KOR.strings:split(items[i], "||", true)
        etitle = parts[3]
        local sindex = tonumber(parts[2]) or math.huge

        --* create ebook entry if needed:
        local ebook = lookup[etitle]
        if not ebook then
            ebook = {
                title = etitle,
                series_index = sindex,
                quotes = {}
            }
            lookup[etitle] = ebook
            table_insert(ebooks, ebook)
        end

        table_insert(ebook.quotes, {
            ebook = parts[1],
            series_index = sindex,
            pos0 = parts[4],
            chapter = parts[5],
            quote = parts[6],
        })
    end

    table_sort(ebooks, function(a, b)
        return a.series_index < b.series_index
    end)

    local html, text = {}, {}
    local ebook
    count = #ebooks
    for b = 1, count do
        ebook = ebooks[b]
        if ebook.title ~= "???" then
            local prefix = ebook.series_index ~= math.huge
                    and ebook.series_index .. ". "
                    or ""
            table_insert(html,
        "<p class='chaptertitle'><strong>" ..
                prefix ..
                KOR.strings:upper(ebook.title) ..
                "</strong></p>"
            )
            table_insert(text,
        prefix .. KOR.strings:upper(ebook.title)
            )
        end

        KOR.tables:sortByPosition(ebook.quotes)

        for i = 1, #ebook.quotes do
            local q = ebook.quotes[i]
            local page = KOR.document:getPageFromXPointer(q.pos0)

            table_insert(html,
        "<p class='chaptertitle'><strong>" ..
                q.chapter ..
                "</strong></p>" ..
                "<ul><li><em>pagina</em>: " ..
                page ..
                "<br /> </li></ul>" ..
                "<p>" .. q.quote .. "</p>"
            )
            table_insert(text,
                q.chapter .. "\n" ..
                _("page") .. ": " ..
                page ..
                "\n \n" ..
                q.quote
            )
        end
    end

    html = table_concat(html, "<p> </p>")
    text = table_concat(text, "\n \n")
    KOR.registry:set("mark_items_in_italics", true)
    html = self:markItemInHtml(html, item)
    KOR.registry:unset("mark_items_in_italics")
    return html, text
end

function XrayQuotes:saveQuote(item)
    --* quote_props contains props "quote" and "pos0"; set for existing bookmark in ((Xray quote from existing bookmark)):
    local quote_props = KOR.registry:getOnce("xray_quote_props")
    local pos0 = quote_props.pos0
    local chapter
    if pos0 then
        chapter = KOR.toc:getTocTitleByPage(pos0)
    end
    local quote = quote_props.quote
    local id = item.id
    DX.ds.storeQuote(item, quote, pos0, chapter)

    local prefix = DX.m.current_ebook_basename .. "||" .. (DX.m.current_series_index or "???") .. "||" .. (DX.m.current_title or "???") .. "||"

    if not DX.m.items_by_id[id].pos_chapter_quotes then
        DX.m.items_by_id[id].pos_chapter_quotes = prefix .. pos0 .. "||" .. chapter .. "||" .. quote
    else
        DX.m.items_by_id[id].pos_chapter_quotes = DX.m.items_by_id[id].pos_chapter_quotes .. "@@" .. prefix .. pos0 .. "||" .. chapter .. "||" .. quote
    end
    KOR.messages:notify("citaat opgeslagen...")
end

--- @private
function XrayQuotes:markItemInHtml(html, item)

    --* to disable item registration in ((XrayPages#markedItemRegister)):
    KOR.registry:set("skip_item_registration", true)
    local subjects = {
        "name",
        "aliases",
        "short_names",
    }
    for l = 1, 3 do
        if has_text(item[subjects[l]]) then
            html = DX.p:markItem(item, item[subjects[l]], html, l)
        end
    end
    KOR.registry:unset("skip_item_registration")
    return html
end

return XrayQuotes
