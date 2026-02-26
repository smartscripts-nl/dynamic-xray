
local require = require

local KOR = require("extensions/kor")
local Screen = require("device").screen
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local T = require("ffi/util").template

local DX = DX
local table_concat = table.concat

--- @class XrayInformation
local XrayInformation = WidgetContainer:extend {
    match_reliability_explanations = nil,
    -- #((xray match reliability indicators))
    --* these match reliability indicators will be injected in the dialog with page or paragraphs information in ((XrayUI#showParagraphInformation)) > ((xray items dialog add match reliability explanations)):
    match_reliability_indicators = {
        full_name = KOR.icons.xray_full_bare,
        alias = KOR.icons.xray_alias_bare,
        first_name = KOR.icons.xray_half_left_bare,
        last_name = KOR.icons.xray_half_right_bare,
        partial_match = KOR.icons.xray_partial_bare,
        linked_item = KOR.icons.xray_link_bare,
        tag = KOR.icons.tag_open_bare,
    },
}

--* called from ((TextViewer#showToc)) or ((XrayTappedWords#getXrayItemAsDictionaryEntry)), for info icon:
function XrayInformation:getMatchReliabilityExplanation()
    if self.match_reliability_explanations then
        return self.match_reliability_explanations
    end
    local indicators = self.match_reliability_indicators
    local explanations = {
        indicators.full_name .. _(" full name"),
        indicators.alias .. _(" alias"),
        indicators.first_name .. _(" first name"),
        indicators.last_name .. _(" surname"),
        indicators.partial_match .. _(" partial hit"),
        indicators.linked_item .. _(" linked item"),
    }
    self.match_reliability_explanations = table_concat(explanations, "\n") .. "\n\n" .. _([[The type of similarity determines the icon and indicates how reliable this hit is (a wrong hit might be shown). Full names and aliases are the most reliable of all.
]]) .. "\n"
    return self.match_reliability_explanations
end

function XrayInformation:getMatchReliabilityIndicator(name)
    return self.match_reliability_indicators[name]
end

function XrayInformation:showGeneralDXTips(parent, active_tab)
    local screen_dims = Screen:getSize()

    KOR.dialogs:htmlBoxTabbed(active_tab or 1, {
        parent = parent or DX.pn,
        title = _("General DX tips"),
        modal = true,
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(10),
        window_size = {
            h = screen_dims.h * 0.9,
            w = screen_dims.w * 0.8,
        },
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
        end,
        no_buttons_row = true,
        tabs = {
            {
                tab = _("items"),
                html = _([[<ul>
<li><strong>should I add or not?</strong><br/>If you add an item from a text selection in the book, you can <em>use the add dialog to determine whether this item is important enough</em> in the book to add: because in the title bar of the dialog you will see how many times this item is mentioned in the book.<br /> </li>
<li><strong>best format for person names:</strong><br />If a person is mainly mentioned by his/her last name in the book, then add the name in this format:<br /> <br /><em>LastName, FirstName</em><br/> <br />Doing so will make DX find more hits. In every other case you can best use this format:<br /> <br /><em>FirstName LastName</em><br /> </li>
<li><strong>defining tag-groups:</strong><br />If you want to <em>be able to explore items as a related group</em> (e.g. by being associated to the same event or a same ship), then give each of these items the same tag. In Page Navigator or in the Exporter you can now explore these items as a group.<br /> </li>
<li><strong>adding quotes</strong><br />from a text selection in the book you can - by tapping on the button "+ Xray quote" - <em>add your favorite or important quotes to an item</em>. By doing this you'll have them always quickly at hand in the Page Navigator or in the Item Viewer.</li>
</ul>]])
            },
            {
                tab = _("navigation tips"),
                html = _([[<ul>
<li><strong>the best way to navigate?</strong>
    <ol>
    <li>If you want to quickly see which Xray items are mentioned in the current page, then tap on the <em>in-page lightning icon</em>. The overview this provides is the best readable of all DX dialogs.</li>
    <li>Do you want to see which items are in the current page and <em>you want at the same time to explore relations</em>, then the Page Navigator is you best option. There you can explore relations via the buttons in the side bar. The Page Navigator can be called by <em>longpressing the in-page lightning icon</em>, or with Shift+X on your physical (BT) keyboard.</li>
    <li>Do you want to <em>explore all items in the current series or book</em>, then call the Items List. With a gesture defined by you, or with Shift+L on your physical (BT) keyboard. If you tap on a iten in the list, you can then explore relations between item via the context buttons in the footer of the Item Viewer.<br /> </li>
    </ol>
    </li>
    <li><strong>using the bars in the Occurrences-per-Chapter-Histogram</strong><br />In this Histogram in the Page Navigator you can <em>quickly inspect the locations in the chapter where the active item in the info panel is being mentioned</em>, by tapping on the bar belonging to that chapter. So you don't have to jump to the chapter in the ebook first, to do this.</li>
<ul>]])
            },
            {
                tab = _("importing items"),
                html = _([[<ul>
    <li><strong>how?</strong><br />with the bucket icon:
        <ol>
            <li>in the footer of the Items List</li>
            <li>in the popup menu of the Page Navigator<br /> </li>
        </ol>
    </li>
    <li><strong>why?</strong><br />By importing items you can <em>see how often those items occur in the current ebook</em>.<br /> </li>
    <li><strong>importing from books in the same series:</strong><br />If you start reading a book in a series from which you alread read other titles, you can import the items defined with a <em>tap on the bucket icon</em>.<br /> </li>
    <li><strong>importing from books in another series:</strong><br />Sometimes your book is part of a follow-up series for a previous series. You can then import the items of that previous series by <em>longpressing the bucket icon</em> and then tap on the button "external".</li>
</ul>]])
            },
        },
    })
    return true
end

function XrayInformation:showPageNavigatorHelp(parent, active_tab)
    local screen_dims = Screen:getSize()

    KOR.dialogs:htmlBoxTabbed(active_tab or 1, {
        parent = parent or DX.pn,
        title = "Page Navigator hulp",
        modal = true,
        button_font_weight = "normal",
        --* htmlBox will always have a close_callback and therefor a close button; so no need to define a close_callback here...
        no_filter_button = true,
        title_shrink_font_to_fit = true,
        text_padding_top_bottom = Screen:scaleBySize(10),
        window_size = {
            h = screen_dims.h * 0.8,
            w = screen_dims.w * 0.7,
        },
        after_close_callback = function()
            KOR.registry:unset("add_parent_hotkeys")
        end,
        no_buttons_row = true,
        tabs = {
            {
                tab = _("Browsing"),
                html = _([[With the arrows in the right bottom corner you can browse through pages.<br>
    If you longpress the arrow buttons, PN will jump to the previous/next occurrence of the item shown in the bottom information panel.<br>
<br>
If you have a physical (BT) keyboard, you can also browse with Space and Shift+Space. If you reach the end of a page, the viewer will jump to the next page if you press Space. If you reach the top of a page, then Shift+Space will take you to the previous page.<br>
<br>
With the target icon you can jump back to the page on which you started navigating through the pages.<br>
<br>
With the XraySetting "PN_panels_font_size" (see cog icon in top left corner) you can change the font size of the side and bottom panels.]])
            },
            {
                tab = _("Filtering"),
                html = _([[Tap on items in the side panel to see explantions of those items.<br>
<br>
<strong>Filtered browsing</strong><br>
<br>
If you longpress on an item in the side panel, that will be used as a filter criterium (a filter icon appears on the right side of it). After this the Navigator will only jump to the next or previous page where the filtered item is mentioned.<br>
<br>
<strong>Resetting the filter</strong><br>
<br>
Longpress on the filtered item in the side panel.]])
            },
            {
                tab = _("Hotkeys"),
                html = self:getPageNavigatorHotkeysInfo(),
            },
        },
    })
    return true
end

--- @private
function XrayInformation:getPageNavigatorHotkeysInfo()
    return self.hotkeys_information or _("For usage with physical (BT) keyboards:") .. [[<br>
                <br>
<strong>]] .. _("Global hotkeys (while reading)") .. [[</strong><br>
<br>
<table style='border-collapse: collapse'>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+G</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("show a glossary for the current ebook - or add it by marking its boundaries in the ebook")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+H</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("show this Help information dialog")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+L</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("show Xray List")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+M</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("show current series books or Metadata of a non-series book")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+X</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("show Xray Page Navigator")
            .. [[</td></tr>
</table>
                <br>
<strong>In Page Navigator</strong><br>
<br>
<table style='border-collapse: collapse'>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>U</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("open dialog for jumping to a specific page number")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>E</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Edit Xray item shown in bottom info panel")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>I</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("show this Information dialog")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>J</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Page Navigator: Jump to page currently displayed in e-book")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+J</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("e-book: Jump to page currently displayed in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>L</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("show Items List")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>M</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("toggle the Page Navigator popup Menu with additional actions")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>N</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("jump to Next page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>P</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("jump to Previous page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>S</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("open Dynamic Xray Settings")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>Shift+S</td><td style='padding: 8px 12px; border: 1px solid #444444; text-align: left'>]]
            .. _("Search for an Xray item in the Page Navigator")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>V</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("View details of item currently displayed in bottom info panel")
            .. [[</td></tr>
    <tr><td style='padding: 8px 12px; border: 1px solid #444444'>]] .. _("1 - 9") .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Show information of corresponding Xray item in side panel in bottom information panel")
            .. [[</td></tr>
    <tr><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]] .. _("space") .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("browse to next page in Page Navigator")
            .. [[</td></tr>
    <tr><td style='white-space: pre; text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Shift+space")
            .. [[</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("browse to previous page in Page Navigator")
            .. [[</td></tr>
</table>
<br>
<strong>In this help dialog</strong><br>
<br>
<table>
    <tr><td style='white-space: pre; padding: 8px 22px; border: 1px solid #444444'>1, 2, 3</td><td style='text-align: left; padding: 8px 12px; border: 1px solid #444444'>]]
            .. _("Jump to the corresponding tab in the dialog")
            .. [[</td></tr>
</table>]]
end

function XrayInformation:showReliabilityIndicatorsExplanation()
    KOR.dialogs:textBoxTabbed(1, {
        title = "Uitleg bij dit venster",
        is_standard_tabbed_dialog_lower = true,
        tabs = {
            {
                tab = "betrouwbaarheidsikonen",
                info = self:getMatchReliabilityExplanation()
            },
            {
                tab = "viewer-buttons",
                info = [[PAGINA- OF ALINEA-IKOON LINKSBOVEN

schakel tussen xray markeringen in de tekst voor de hele pagina of per alinea

FOOTER-IKONEN

* lijst: ga naar lijst van xray-items in dit boek
* wegwijzer: klikbare index van items
]]
            },
            {
                tab = "index-buttons",
                info = "Tik op een item om erheen te springen.\n\nEen item bewerken: houd de bijbehorende button langer ingedrukt en kies voor \"Bewerk\".\n"
            },
        }
    })
    return true
end

function XrayInformation:showListAndViewerHelp(initial_tab)

    --* these hotkeys are mostly defined in ((KeyEvents#addHotkeysForXrayList)):
    local list_info = DX.d.help_texts["list"] or T(_([[Shift+X = show Items List

Titlebar %1/%2 = items displayed in series/book mode
Titlebar %3 = only linked items, from longpressed word
Browse to next/previous page: Space/Shift+Space
Longpress item: quick access to actions.

A, P, B = activate tab starting with that character
1 through 9 = open corresponding item in list
F = Filter list
I = Import items and update hits
Shift+I = show this Information dialog
M = toggle book or series Mode
O = toggle sOrt by alphabet or hits count
S = show books in Series
V = add item
X = import items from eXternal series
]]), KOR.icons.xray_series_mode_bare, KOR.icons.xray_book_mode_bare, KOR.icons.xray_tapped_collection_bare)
    DX.d:setHelpText("list", list_info)

    --* these hotkeys are mostly defined in ((KeyEvents#addHotkeysForXrayItemViewer)):
    local viewer_info = DX.d.help_texts["viewer"] or T(_([[

You can also navigate through items by tapping near to the left or right border of the viewer dialog.
Browse to next/previous info screen: Space/Shift+Space

1, 2 = activate first or second tab

A = Add item
D = Delete current item for current book
Shift+D = Delete current item for entire series
E = Edit current item
Shift+I = show this Information dialog
L = go back to List
N = go to Next item (when Right doesn't work)
O = Open chapter no...
P = go to Previous item (when Left doesn't work)
S = show Series manager
Shift+S = Show all hits in book
]]), KOR.icons.series_mode_bare, KOR.icons.book_bare)
    DX.d:setHelpText("viewer", viewer_info)

    KOR.dialogs:textBoxTabbed(initial_tab, {
        title = _("(BT) Hotkeys and more"),
        is_standard_tabbed_dialog = true,
        tabs = {
            {
                tab = _("In Items List"),
                info = list_info,
            },
            {
                tab = _("In item viewer"),
                info = viewer_info,
            },
        }
    })
    return true
end

return XrayInformation
