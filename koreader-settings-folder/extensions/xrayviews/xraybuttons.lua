--[[--
This extension is part of the Dynamic Xray plugin; it has buttons which are generated for dialogs and forms in XrayController and its other extensions.

The Dynamic Xray plugin has kind of a MVC structure:
M = ((XrayModel)) > data handlers: ((XrayDataLoader)), ((XrayDataSaver)), ((XrayFormsData)), ((XraySettings)), ((XrayTappedWords)) and ((XrayViewsData))
V = ((XrayUI)), ((XrayPageNavigator)), ((XrayTranslations)) and ((XrayTranslationsManager)), and ((XrayDialogs)) and ((XrayButtons))
C = ((XrayController))

XrayDataLoader is mainly concerned with retrieving data FROM the database, while XrayDataSaver is mainly concerned with storing data TO the database.

The views layer has two main streams:
1) XrayUI, which is only responsible for displaying tappable xray markers (lightning or star icons) in the ebook text;
2) XrayPageNavigator, XrayDialogs and XrayButtons, which are responsible for displaying dialogs and interaction with the user.
When the ebook text is displayed, XrayUI has done its work and finishes. Only after actions by the user (e.g. tapping on an xray item in the book), XrayDialogs will be activated.

These modules are initialized in ((initialize Xray modules)) and ((XrayController#init)).
--]]--

local require = require

local Button = require("extensions/widgets/button")
local ButtonDialogTitle = require("extensions/widgets/buttondialogtitle")
local ButtonTable = require("extensions/widgets/buttontable")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()
local Screen = require("device").screen
local Size = require("ui/size")
local T = require("ffi/util").template

local DX = DX
local has_items = has_items
local has_no_text = has_no_text
local has_text = has_text
local table = table

local count

--- @class XrayButtons
local XrayButtons = WidgetContainer:new{
    button_info = {
        add_item = _("Add Xray item."),
        edit_item = _("Edit this Xray item."),
        show_item = _("Show this Xray item."),
        show_context = _("Show all occurrences of this Xray item."),
        toggle_main_xray_item = _("Toggle to mark this Xray item as important."),
    },
    context_buttons_max_buttons = 16,
    hits_buttons_max = 30,
    info_max_total_buttons = 16,
    related_item_icons_font_size = 14,
    related_item_text_font_size = 18,
    max_buttons_per_row = 4,
    xray_type_chooser = nil,
}

--[[
Props needed when you want to add a more button:

nr add_more_button max_total_buttons source_items callback extra_item_callback is_bold (optionally, for when you want to indicate a string has been found in text selection e.g.)

When a more button has been added, this method returns true, so the caller knows it has to break its loop through the source items.
]]
--* called from ((XrayButtons#handleMoreButtonClick)), ((XrayButtons#forItemsCollectionPopup)) and ((XrayUI#showParagraphInformation)):
--! indicator_button_table will be nil when called from ((XrayUI#showParagraphInformation)):
function XrayButtons:addTappedWordCollectionButton(button_table, indicator_button_table, status_icons, item, data)
    local callback = data.callback
    local extra_item_callback = data.extra_item_callback
    local nr = data.nr
    local max_buttons_per_row = data.max_buttons_per_row or self.max_buttons_per_row
    local max_total_buttons = data.max_total_buttons

    if nr == 1 or (nr - 1) % max_buttons_per_row == 0 then
        table.insert(button_table, {})
        --* indicator_button_table will be nil when called from ((XrayUI#showParagraphInformation)):
        if indicator_button_table then
            table.insert(indicator_button_table, {})
        end
    end
    local current_row = #button_table
    local add_more_button = nr == max_total_buttons and #data.source_items > max_total_buttons

    if add_more_button and max_total_buttons and nr and nr == max_total_buttons then
        self:addMoreButton(button_table, indicator_button_table, {
            --* popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons - this prop to be consumed in ((XrayButtons#handleMoreButtonClick)):
            max_total_buttons_after_first_popup = max_total_buttons + 16,
            max_total_buttons = max_total_buttons,
            current_row = current_row,
            popup_buttons_per_row = max_buttons_per_row,
            source_items = data.source_items,
            title = _(" additional Xray items:"),
            item_callback = function(citem)
                extra_item_callback(citem)
            end,
            --* this is needed to support multiple more... popups in ((XrayButtons#handleMoreButtonClick)):
            extra_item_callback = function(citem)
                extra_item_callback(citem)
            end,
            item_hold_callback = function(citem, icon)
                KOR.dialogs:textBox({
                    title = icon .. citem.name,
                    info = DX.vd:getItemInfo(citem),
                    no_buttons_row = true,
                    use_computed_height = true,
                })
            end,
        })
        --* signal that more button has been added:
        return true
    end

    local icon, text, status_indicators, status_indicator_color = DX.tw:getTypeAndReliabilityIcons(item)
    table.insert(button_table[current_row], {
        text = text,
        --* is_bold prop was set in ((XrayTappedWords#collectionPopulateAndSort)):
        font_bold = item.is_bold,
        text_font_face = "x_smallinfofont",
        font_size = self.related_item_text_font_size,
        callback = function()
            callback()
        end,
        hold_callback = function()
            KOR.dialogs:textBox({
                title = icon .. " " .. item.name,
                title_shrink_font_to_fit = true,
                info = DX.vd:getItemInfo(item),
                use_computed_height = true,
            })
        end,
    })
    --* indicator_button_table will be nil when called from ((XrayUI#showParagraphInformation)):
    if not indicator_button_table then
        return
    end
    if status_icons then
        table.insert(status_icons, status_indicators)
    end
    local hits = DX.vd.list_display_mode == "series" and item.series_hits or item.book_hits
    text = has_items(hits) and status_indicators .. " " .. hits or text
    table.insert(indicator_button_table[current_row], {
        text = text,
        --* is_bold prop was set in ((XrayTappedWords#collectionPopulateAndSort)):
        font_bold = item.is_bold,
        text_font_face = "x_smallinfofont",
        fgcolor = status_indicator_color,
        font_size = self.related_item_icons_font_size,
        callback = function()
            callback()
        end,
        hold_callback = function()
            KOR.dialogs:textBox({
                title = icon .. " " .. item.name,
                title_shrink_font_to_fit = true,
                info = DX.vd:getItemInfo(item),
                use_computed_height = true,
            })
        end,
    })
end

--* context buttons with linked xray items for dialog for viewing an Xray item:
function XrayButtons:forItemViewerBottomContextButtons(buttons, needle_item, tapped_word)
    DX.tw:rememberTappedWord(tapped_word)
    if has_text(needle_item.name) then
        DX.m:addLinkedItemsAsContextButtonsForViewer(buttons, needle_item, self.max_buttons_per_row, self.context_buttons_max_buttons, tapped_word)
    end
end

--- @private
function XrayButtons:addFindAllHitsButton(buttons, needle_item, book_hits)
    if has_text(needle_item.name) and book_hits and book_hits > 0 then
        table.insert(buttons[1], #buttons[1] - 2,
        KOR.buttoninfopopup:forSearchAllLocations({
            info = T([[search-list-icon | Show all occurrences of this Xray item in the current ebook.
Hotkey %1 H]], KOR.icons.arrow_bare),
            callback = function()
                DX.c:viewItemHits(needle_item.name)
            end,
        }))
    end
end

--* indicator_buttons (for separate rows with indicators) will be nil when called from ((XrayButtons#forItemViewerBottomContextButtons)):
function XrayButtons:addMoreButton(buttons, indicator_buttons, props)
    local extra_buttons_count = #props.source_items - props.max_total_buttons + 1
    table.insert(buttons[props.current_row], {
        text = "[+" .. extra_buttons_count .. "]",
        font_bold = false,
        text_font_face = "x_smallinfofont",
        font_size = self.related_item_text_font_size,
        callback = function()
            self:handleMoreButtonClick(props, extra_buttons_count)
        end,
    })
    if not indicator_buttons then
        return
    end
    table.insert(indicator_buttons[props.current_row], {
        text = " ",
        font_bold = false,
        text_font_face = "x_smallinfofont",
        font_size = self.related_item_text_font_size,
        callback = function()
            self:handleMoreButtonClick(props, extra_buttons_count)
        end,
    })
end

--- @param parent XrayDialogs
function XrayButtons:forPageNavigator(parent)
    return {{
         {
             icon = "back",
             callback = function()
                 parent:closePageNavigator()
             end
         },
         KOR.buttoninfopopup:forXrayList({
             callback = function()
                 return parent:execShowListCallback()
             end
         }),
         KOR.buttoninfopopup:forXrayViewer({
             enabled_function = function()
                 return parent.current_item and true or false
             end,
             callback = function()
                 return parent:execViewItemCallback(parent)
             end,
         }),
         KOR.buttoninfopopup:forXrayItemEdit({
             enabled_function = function()
                 return parent.current_item and true or false
             end,
             info = "edit-ikoon | Bewerk het item dat in het infopaneel hieronder wordt weergegeven.",
             callback = function()
                 return parent:execEditCallback(parent)
             end,
         }),
         {
             text = KOR.icons.previous,
             callback = function()
                 return parent:execGotoPrevPageCallback(parent)
             end,
         },
         KOR.buttonchoicepopup:forXrayPageNavigatorToCurrentPage({
             callback = function()
                 return parent:execJumpToCurrentPageInNavigatorCallback(parent)
             end,
             hold_callback = function()
                 return parent:execJumpToCurrentPageInEbookCallback(parent)
             end,
         }),
         {
             text = KOR.icons.next,
             callback = function()
                 parent:execGotoNextPageCallback(parent)
             end,
         },
     }}
end

function XrayButtons:forPageNavigatorTopLeft(parent)
    return {
        {
            icon = "info-slender",
            callback = function()
                parent:showHelpInformation()
            end,
        },
        KOR.buttoninfopopup:forXrayTranslations(),
        KOR.buttoninfopopup:forXraySettings({
            callback = function()
                parent:execSettingsCallback(parent)
            end
        }),
    }
end

function XrayButtons:forUiInfo(parent, buttons)
    -- #((TextViewer toc button))
    --* the items for this and the next two buttons were generated in ((XrayUI#ReaderHighlightGenerateXrayInformation)) > ((headings for use in TextViewer)):
    --* compare the buttons for Xray items list as injected in ((inject xray list buttons)):

    --! upon a tap on a button these routines are executed: ((Xray page hits TOC search routine)) > ((TextViewer#findCallback)) > ((XrayModel#removeMatchReliabilityIndicators))

    table.insert(buttons, 1, KOR.buttoninfopopup:forXrayItemsIndex({
        callback = function()
            parent:showToc()
        end,
    }))
    table.insert(buttons, 2, KOR.buttoninfopopup:forXrayPreviousItem({
        id = "previ",
        callback = function()
            parent:blockUp()
        end,
    }))
    table.insert(buttons, 3, KOR.buttoninfopopup:forXrayNextItem({
        id = "nexti",
        callback = function()
            parent:blockDown()
        end,
    }))
    table.insert(buttons, 1, KOR.buttoninfopopup:forXrayPageNavigator({
        callback = function()
            DX.pn:showNavigator()
        end,
    }))
end

--- @param parent XrayDialogs
function XrayButtons:forUiInfoTopLeft(target, new_trigger, parent)
    return {
        KOR.buttoninfopopup:forXrayTogglePageOrParagraphInfo({
            icon = DX.s.ui_mode == "paragraph" and "paragraph" or "pages",
            callback = function()
                local question = T(_([[Do you indeed want to toggle the Xray information display mode to %1?]]), target, new_trigger)
                KOR.dialogs:confirm(question, function()
                    DX.s:toggleSetting("ui_mode", { "page", "paragraph" })
                    UIManager:close(parent.xray_ui_info_dialog)
                    parent.xray_ui_info_dialog = nil
                    UIManager:setDirty(nil, "full")
                end)
            end,
        }),
        KOR.buttoninfopopup:forXrayTranslations(),
        KOR.buttoninfopopup:forXraySettings({
            callback = function()
                UIManager:close(parent.xray_ui_info_dialog)
                parent.xray_ui_info_dialog = nil
                DX.s:showSettingsManager()
            end
        }),
    }
end

--- @private
function XrayButtons:handleMoreButtonClick(props, extra_buttons_count)
    local source_items = props.source_items
    local popup_buttons = {}
    local popup_indicator_buttons = {}
    local popup_viewer
    local max_total_buttons = props.max_total_buttons
    local mprops = {}

    --* here popup buttons are generated; if we want to limit them with a more button again, we have to point back to and use the arguments - nr add_more_button max_total_buttons source_items callback extra_item_callback needle_for_bold - needed for ((XrayButtons#addTappedWordCollectionButton))
    local shifted_source_items = {}
    --* first make sure we copy ALL the not yet shown items, before optionally updating max_total_buttons in the next code block:
    count = #source_items
    for nr = max_total_buttons, count do
        table.insert(shifted_source_items, source_items[nr])
    end
    --* popup buttons dialog doesn't have to display any additional info, except the buttons, so may contain more buttons; for example see ((XrayButtons#forItemViewerBottomContextButtons)):
    if props.max_total_buttons_after_first_popup then
        max_total_buttons = props.max_total_buttons_after_first_popup
    end
    count = #shifted_source_items
    mprops.add_more_button = count > max_total_buttons
    for nr = 1, count do
        local item = shifted_source_items[nr]

        --* modify a copy of the parent props:
        mprops.add_more_button = count > max_total_buttons
        mprops.nr = nr
        mprops.max_total_buttons = max_total_buttons
        mprops.max_buttons_per_row = props.max_buttons_per_row
        mprops.needle_for_bold = props.needle_for_bold
        mprops.source_items = shifted_source_items
        mprops.callback = function()
            UIManager:close(popup_viewer)
            props.item_callback(item)
        end
        mprops.extra_item_callback = function(citem)
            props.extra_item_callback(citem)
        end
        mprops.hold_callback = function()
            props.item_hold_callback(item, icon)
        end
        local more_button_added = self:addTappedWordCollectionButton(popup_buttons, popup_indicator_buttons, item, mprops)
        if more_button_added then
            break
        end
    end
    --* for dialog upon tapping in reader upon an item with related items, compare ((XrayDialogs#showTappedWordCollectionPopup)):
    popup_viewer = ButtonDialogTitle:new{
        title = extra_buttons_count .. props.title,
        title_align = "center",
        use_low_title = true,
        no_overlay = true,
        buttons = popup_buttons,
    }
    UIManager:show(popup_viewer)
end

--* compare buttons for list view ((XrayButtons#forListFooterLeft)), ((XrayButtons#forListFooterRight)), ((XrayButtons#forListContext)):
function XrayButtons:forItemViewer(needle_item, called_from_list, tapped_word, book_hits)
    local buttons = {
        {
            KOR.buttoninfopopup:forXrayList({
                callback = function()
                    DX.d:closeViewer()
                    DX.d:showList(needle_item)
                end,
            }),
            KOR.buttoninfopopup:forXrayPreviousItem({
                callback = function()
                    DX.d:viewPreviousItem(needle_item)
                end,
            }),
            KOR.buttoninfopopup:forXrayNextItem({
                callback = function()
                    DX.d:viewNextItem(needle_item)
                end,
            }),
            KOR.buttonchoicepopup:forXrayItemDelete({
                icon = "dustbin",
                icon_size_ratio = 0.5,
                callback = function()
                    DX.d:showDeleteItemConfirmation(needle_item)
                end,
                hold_callback = function()
                    DX.d:showDeleteItemConfirmation(needle_item, nil, "remove_all_instances_in_series")
                end,
            }),
            KOR.buttoninfopopup:forXrayItemAdd({
                callback = function()
                    DX.d:closeViewer()
                    -- #((enable return to viewer))
                    DX.c:setProp("return_to_viewer", true)
                    DX.c:resetFilteredItems()
                    DX.c:onShowNewItemForm()
                end,
            }),
            KOR.buttoninfopopup:forXrayItemEdit({
                callback = function()
                    DX.d:closeViewer()
                    DX.c:setProp("return_to_viewer", true)
                    DX.c:onShowEditItemForm(needle_item, false, 1)
                end,
            }),
            KOR.buttoninfopopup:forXrayToggleImportantItem({
                text = DX.vd.xray_type_icons_importance_toggle[needle_item.xray_type],
                callback = function()
                    DX.d:closeViewer()
                    local select_number, toggled_item = DX.fd:toggleIsImportantItem(needle_item)
                    DX.vd:updateItemsTable(select_number)
                    DX.d:showItemViewer(toggled_item, called_from_list, tapped_word)
                end,
            }),
            KOR.buttoninfopopup:forXrayTogglePersonOrTerm({
                text = DX.vd.xray_type_icons_person_or_term_toggle[needle_item.xray_type],
                callback = function()
                    DX.d:closeViewer()
                    local select_number, toggled_item = DX.fd:toggleIsPersonOrTerm(needle_item)
                    DX.vd:updateItemsTable(select_number)
                    DX.d:showItemViewer(toggled_item, called_from_list, tapped_word)
                end,
            }),

            --* if book_hits are available in current book, button for showing them will be added here by ((XrayButtons#addFindAllHitsButton))...

            KOR.buttoninfopopup:forXrayFromItemToChapter({
                enabled = has_text(needle_item.name),
                callback = function()
                    DX.d:showJumpToChapterDialog()
                end,
            }),

            KOR.buttoninfopopup:forXrayFromItemToDictionary({
                enabled = has_text(needle_item.name),
                callback = function()
                    local first_name = DX.m:getRealFirstOrSurName(needle_item.name)
                    KOR.dictionary:onLookupWord(first_name)
                end,
            }),
            {
                icon = "back",
                icon_size_ratio = 0.55,
                callback = function()
                    DX.d:closeViewer()
                end,
            },
        }
    }

    self:addFindAllHitsButton(buttons, needle_item, book_hits)
    self:forItemViewerBottomContextButtons(buttons, needle_item, tapped_word)

    return buttons
end

--* compare ((XrayButtons#forItemViewer)) and buttons for list view ((XrayButtons#forListFooterLeft)), ((XrayButtons#forListFooterRight)), ((XrayButtons#forListContext)):
function XrayButtons:forTappedWordItemViewer(needle_item, called_from_list, tapped_word, book_hits)
    local buttons = {
        {
            KOR.buttoninfopopup:forXrayList({
                callback = function()
                    DX.d:closeViewer()
                    DX.d:showList(needle_item)
                end,
            }),
            KOR.buttoninfopopup:forXrayPreviousItem({
                callback = function()
                    DX.d:viewPreviousTappedWordItem()
                end,
            }),
            KOR.buttoninfopopup:forXrayNextItem({
                callback = function()
                    -- #((next related item via button))
                    DX.d:viewNextTappedWordItem()
                end,
            }),
            KOR.buttonchoicepopup:forXrayItemDelete({
                icon = "dustbin",
                icon_size_ratio = 0.5,
                callback = function()
                    DX.d:showDeleteItemConfirmation(needle_item)
                end,
                hold_callback = function()
                    DX.d:showDeleteItemConfirmation(needle_item, nil, "remove_all_instances_in_series")
                end,
            }),
            KOR.buttoninfopopup:forXrayItemAdd({
                callback = function()
                    DX.d:closeViewer()
                    DX.c:resetFilteredItems()
                    DX.c:onShowNewItemForm()
                end,
            }),
            KOR.buttoninfopopup:forXrayItemEdit({
                callback = function()
                    DX.d:closeViewer()
                    DX.c:onShowEditItemForm(needle_item, false, 1)
                end,
            }),
            KOR.buttoninfopopup:forXrayToggleImportantItem({
                text = DX.vd.xray_type_icons_importance_toggle[needle_item.xray_type],
                callback = function()
                    DX.d:closeViewer()
                    local select_number, toggled_item = DX.fd:toggleIsImportantItem(needle_item)
                    DX.vd:updateItemsTable(select_number)
                    DX.d:showItemViewer(toggled_item, called_from_list, tapped_word)
                end,
            }),
            KOR.buttoninfopopup:forXrayTogglePersonOrTerm({
                text = DX.vd.xray_type_icons_person_or_term_toggle[needle_item.xray_type],
                callback = function()
                    DX.d:closeViewer()
                    local select_number, toggled_item = DX.fd:toggleIsPersonOrTerm(needle_item)
                    DX.vd:updateItemsTable(select_number)
                    DX.d:showItemViewer(toggled_item, called_from_list, tapped_word)
                end,
            }),

            --* if book_hits are available in current book, button for showing them will be added here by ((XrayButtons#addFindAllHitsButton))...

            KOR.buttoninfopopup:forXrayFromItemToChapter({
                enabled = has_text(needle_item.name),
                callback = function()
                    DX.d:showJumpToChapterDialog()
                end,
            }),

            KOR.buttoninfopopup:forXrayFromItemToDictionary({
                enabled = has_text(needle_item.name),
                callback = function()
                    local first_name = DX.m:getRealFirstOrSurName(needle_item.name)
                    KOR.dictionary:onLookupWord(first_name)
                end,
            }),
            {
                icon = "back",
                icon_size_ratio = 0.55,
                callback = function()
                    DX.d:closeViewer()
                end,
            },
        }
    }

    self:addFindAllHitsButton(buttons, needle_item, book_hits)
    self:forItemViewerBottomContextButtons(buttons, needle_item, tapped_word)

    return buttons
end

--- @param parent XrayTranslationsManager
function XrayButtons:forTranslationsContextDialog(parent, item)
    return {
        {
            {
                icon = "edit-light",
                callback = function()
                    UIManager:close(parent.translations_manipulate_dialog)
                    --- @type XrayTranslationsManager manager
                    local manager = parent._manager
                    manager:editTranslation(item)
                end
            },
        },
    }
end

--- @param parent XrayTranslationsManager
function XrayButtons:forTranslationsEditor(parent, item)
    return {
        {
            {
                icon = "back",
                callback = function()
                    UIManager:close(parent.edit_translation_input)
                    parent.edit_translation_input = nil
                end,
            },
            {
                icon = "list",
                callback = function()
                    UIManager:close(parent.edit_translation_input)
                    parent.edit_translation_input = nil
                    parent:manageTranslations()
                end,
            },
            {
                text = KOR.icons.previous,
                callback = function()
                    UIManager:close(parent.edit_translation_input)
                    parent:closeListDialog()
                    parent:editPreviousTranslation()
                end,
            },
            {
                text = KOR.icons.next,
                callback = function()
                    UIManager:close(parent.edit_translation_input)
                    parent:closeListDialog()
                    parent:editNextTranslation()
                end,
            },
            {
                icon = "save",
                is_enter_default = false,
                callback = function()
                    parent:saveUpdatedTranslation(item)
                end,
            },
        }
    }
end



--- @param parent XrayTranslationsManager
function XrayButtons:forTranslationsFilter(parent)
    return {
        {
            {
                icon = "back",
                callback = function()
                    UIManager:close(parent.filter_translations_input)
                    parent.filter_string = ""
                    parent:manageTranslations()
                end,
            },
            {
                icon = "yes",
                is_enter_default = true,
                callback = function()
                    parent.previous_filter = parent.filter_string
                    parent.filter_string = parent.filter_translations_input:getInputText():lower()
                    if parent.filter_string == "" then
                        parent:reset()
                    end
                    UIManager:close(parent.filter_translations_input)
                    parent:manageTranslations()
                end,
            },
        }
    }
end

function XrayButtons:forTranslationViewer(parent, translation)
    return {
        {
            {
                icon = "list",
                callback = function()
                    UIManager:close(parent.translation_viewer)
                    --* go to the subpage in the manager containing the currently displayed note:
                    parent:manageTranslations(translation, true)
                end,
            },
            {
                text = KOR.icons.previous,
                callback = function()
                    UIManager:close(parent.translation_viewer)
                    parent:showPreviousTranslation(translation)
                end,
            },
            {
                text = KOR.icons.next,
                callback = function()
                    UIManager:close(parent.translation_viewer)
                    parent:showNextTranslation(translation)
                end,
            },
            {
                icon = "edit-light",
                callback = function()
                    UIManager:close(parent.translation_viewer)
                    parent:editTranslation(translation)
                end,
            },
        }
    }
end

function XrayButtons:forItemViewerTabs(main_info, hits_info)
    local has_chapter_info = hits_info ~= ""
    local hits_tab_enabled, hits_tab_color = KOR.buttonprops:getButtonState(has_chapter_info)
    return {
        {
            tab = _("main information"),
            --* strangely enough usage of .redhat - defined in ((htmlbox.lua)) - forces a serif font for blockquotes, but not for paragraphs:
            html = "<div style='margin: 1em 2em' class='redhat'>" .. main_info .. "</div>",
        },
        {
            tab = _("hits per chapter"),
            --* this tab can be empty for items which were encountered in the current series of books, but not in the current book:
            enabled = hits_tab_enabled,
            fgcolor = hits_tab_color,
            html = "<div style='margin: 1em 2em' class='redhat'>" .. hits_info .. "</div>",
        },
    }
end

--- @param parent XrayDialogs
function XrayButtons:forItemViewerTopLeft(parent)
    return {
        {
            icon = "info-slender",
            callback = function()
                parent:showHelp(2)
            end
        },
        KOR.buttoninfopopup:forXrayTranslations(),
        KOR.buttoninfopopup:forXraySettings({
            callback = function()
                UIManager:close(parent.item_viewer)
                parent.item_viewer = nil
                DX.s:showSettingsManager()
            end
        }),
    }
end

--* compare buttons for item viewer ((XrayButtons#forItemViewer)):
--- @param manager XrayController
function XrayButtons:forListContext(manager, item)
    local importance_label = (item.xray_type == 2 or item.xray_type == 4) and KOR.icons.xray_person_bare .. "/" .. KOR.icons.xray_term_bare .. _(" normal") or KOR.icons.xray_person_important_bare .. "/" .. KOR.icons.xray_term_important_bare .. _(" important")
    local buttons = {
        {
            {
                icon_text = KOR.labels.new_item,
                callback = function()
                    UIManager:close(manager.item_context_dialog)
                    local exists_already = DX.c:guardIsExistingItem(item.name)
                    if exists_already then
                        return false
                    end
                    DX.c:onShowNewItemForm(item.name)
                end,
                hold_callback = function()
                    KOR.dialogs:alertInfo(manager.button_info.add_item)
                end,
            },
            {
                icon_text = KOR.labels.edit,
                callback = function()
                    UIManager:close(manager.item_context_dialog)
                    DX.c:onShowEditItemForm(item, "reload_manager")
                end,
                hold_callback = function()
                    KOR.dialogs:alertInfo(manager.button_info.edit_item)
                end,
            },
            {
                icon_text = KOR.labels.search,
                callback = function()
                    DX.c:viewItemHits(item.text)
                end,
                hold_callback = function()
                    KOR.dialogs:alertInfo(manager.button_info.show_context)
                end,
            },
        },
        {
            KOR.buttonchoicepopup:forXrayItemDelete({
                icon = "dustbin",
                icon_text = KOR.labels.remove,
                callback = function()
                    DX.d:showDeleteItemConfirmation(item, manager.item_context_dialog)
                end,
                hold_callback = function()
                    DX.d:showDeleteItemConfirmation(item, manager.item_context_dialog, "remove_all_instances_in_series")
                end,
            }),
            {
                text = importance_label,
                fgcolor = KOR.colors.lighter_text,
                callback = function()
                    UIManager:close(manager.item_context_dialog)
                    local select_number = DX.fd:toggleIsImportantItem(item)
                    DX.vd:updateItemsTable(select_number)
                    DX.vd.prepareData()
                    DX.d:showList()
                    return false
                end,
                hold_callback = function()
                    KOR.dialogs:alertInfo(manager.button_info.toggle_main_xray_item)
                end,
            },
            {
                icon_text = KOR.labels.show,
                callback = function()
                    UIManager:close(manager.item_context_dialog)
                    local info = DX.vd:getItemInfo(item)
                    KOR.dialogs:alertInfo(info)
                    return false
                end,
                hold_callback = function()
                    KOR.dialogs:alertInfo(manager.button_info.show_item)
                end,
            },
        },
    }

    return buttons
end

--* compare buttons for item viewer ((XrayButtons#forItemViewer)):
--* compare ((XrayButtons#forListFooterRight)):
function XrayButtons:forListFooterLeft(focus_item, dont_show, base_icon_size)
    local notify_list_display_mode = DX.vd.list_display_mode == "series" and _("series") or _("book")
    local notify_list_display_icon = DX.vd.list_display_mode == "series" and KOR.icons.xray_series_mode_bare or KOR.icons.xray_book_mode_bare
    local current_sorting_mode = DX.m.sorting_method == "name" and _("name") or _("occurrences count")
    local buttons = {
        Button:new(KOR.buttoninfopopup:forXrayToggleSortingMode({
            icon_size_ratio = base_icon_size + 0.1,
            info = T(_([[sorting-icon | sort Xray items by name or occurrences count in book.

Current sorting mode: %1.]]), current_sorting_mode:upper()),
            callback_label = current_sorting_mode == _("name") and _("occurrences count") or _("name"),
            callback = function()
                DX.c:toggleSortingMode()
            end,
            show_parent = DX.c,
        }))
    }
    if DX.m.current_series then
        table.insert(buttons, 1, Button:new(KOR.buttoninfopopup:forXrayToggleBookOrSeriesMode({
            icon_size_ratio = base_icon_size + 0.1,
            info = T([[book-icon | Switch between display of Xray items in %1 book or %2 series mode. In series mode all items for the entires series will be shown.

Current mode: %3 %4.]], KOR.icons.xray_book_mode_bare, KOR.icons.xray_series_mode_bare, notify_list_display_icon, notify_list_display_mode),
            callback_label = notify_list_display_mode == _("book") and _("series mode") or _("book mode"),
            callback = function()
                DX.d:showToggleBookOrSeriesModeDialog(focus_item, dont_show)
            end,
            show_parent = KOR.ui,
        })))
    end
    return buttons
end

--* compare buttons for item viewer ((XrayButtons#forItemViewer)):
--* compare ((XrayButtons#forListFooterLeft)):
function XrayButtons:forListFooterRight(base_icon_size)
    local buttons = {
        KOR.buttoninfopopup:forXrayPageNavigator({
            callback = function()
                DX.d:closeListDialog()
                DX.c:showPageNavigator()
            end,
        }),
        KOR.buttonchoicepopup:forXrayItemsImport({
            callback = function()
                DX.d:showRefreshHitsForCurrentEbookConfirmation()
            end,
            hold_callback = function()
                DX.d:showImportFromOtherSeriesDialog()
            end
        }),
        KOR.buttoninfopopup:forXrayItemAdd({
            callback = function()
                DX.d.called_from_list = true
                DX.c:onShowNewItemForm("")
            end,
        }),
    }

    if DX.m.current_series then
        table.insert(buttons, 2, Button:new(KOR.buttoninfopopup:forSeriesCurrentBook({
            icon_size_ratio = base_icon_size + 0.1,
            callback = function()
                KOR.descriptiondialog:showSeriesForEbookPath(KOR.registry.current_ebook)
            end
        })))
    end
    return buttons
end

--- @private
function XrayButtons:getListSubmenuButton(tab_no)
    local counts = DX.m.tab_display_counts

    local active_marker = KOR.icons.active_tab_bare
    local label = tab_no == 1 and _("everything") .. " (" or _("persons") .. " ("
    if tab_no == 3 then
        label = _("terms") .. " ("
    end
    local active_tab = DX.m:getActiveListTab()
    return {
        text = active_tab == tab_no and active_marker .. label .. counts[tab_no] .. ")" or label .. counts[tab_no] .. ")",
        fgcolor = active_tab == tab_no and KOR.colors.active_tab or KOR.colors.inactive_tab,
        text_font_bold = active_tab == tab_no,

        callback = function()
            DX.d:selectListTab(tab_no, counts)
        end,
    }
end

function XrayButtons:forEditDescription(callback, cancel_callback)
    return {
        {
            {
                icon = "back",
                icon_size_ratio = 0.7,
                id = "close",
                callback = function()
                    UIManager:close(DX.d.edit_item_description_dialog)
                    if cancel_callback then
                        cancel_callback()
                    end
                end,
            },
            {
                icon = "save",
                is_enter_default = true,
                callback = function()
                    local description = DX.d.edit_item_description_dialog:getInputText()
                    UIManager:close(DX.d.edit_item_description_dialog)
                    if callback then
                        callback(description)
                    end
                end,
            },
        },
    }
end

--* this button opens a popup editor with more space for the item description. Changes in this editor will be updated to the main description field if the user choose to save the content of the popup editor:
--- @private
function XrayButtons:forItemEditorEditButton()
    return KOR.buttoninfopopup:forXrayItemEdit({
        callback = function()
            DX.d:dispatchFocusSwitch()
        end,
    })
end

--- @private
function XrayButtons:forItemEditorTypeSwitch(item_copy, button_props)
    local callback = function()

        --* make xray_type field focussed:
        DX.d:switchFocusForXrayType("for_button_tap")
        self:unfocusXrayButton()

        --* input fields were stored in Registry in ((MultiInputDialog#init)) > ((MultiInputDialog#registerInputFields)):
        local input_fields = KOR.registry:get("xray_item")
        local current_field_values = {}
        for i = 1, 4 do
            --* these values will be restored in ((XrayDialogs#dispatchFocusSwitch)):
            table.insert(current_field_values, input_fields[i]:getText())
        end
        local buttons = {
            {},
            {},
            {},
            {},
            {
                {
                    icon = "back",
                    icon_size_ratio = 0.5,
                    callback = function()
                        --* this dialog instance was set in ((XrayButtons#forItemEditorTypeSwitch)):
                        UIManager:close(self.xray_type_chooser)
                        KOR.screenhelpers:refreshDialog()
                    end,
                }
            }
        }
        local row, active_marker
        -- #((xray choose type dialog))
        --* item_copy can be nil in case of adding a new item:
        local active_type = KOR.registry:getOnce("xray_item_type_chosen") or item_copy and item_copy.xray_type or 1
        for i = 1, 4 do
            row = i
            --! this MUST be a local var, for changeType to work as expected:
            local itype = i
            active_marker = itype == active_type and KOR.icons.active_tab_bare .. " " or ""
            table.insert(buttons[row], {
                text = active_marker .. DX.vd.xray_type_choice_labels[itype],
                align = "left",
                callback = function()
                    DX.d:modifyXrayTypeFieldValue(itype)
                end,
            })
        end
        self.xray_type_chooser = ButtonDialogTitle:new{
            title = "Kies Xray type",
            title_align = "center",
            no_overlay = true,
            modal = true,
            font_weight = "normal",
            width = Screen:scaleBySize(250),
            buttons = buttons,
        }
        UIManager:show(self.xray_type_chooser)
    end
    if button_props then
        button_props.callback = callback
        return KOR.buttoninfopopup:forXrayTypeSet(button_props, "add_horizontal_button_padding")
    end
    return KOR.buttoninfopopup:forXrayTypeSet({
        callback = callback,
    })
end

function XrayButtons:forFilterDialog()
    local icon_size_ratio = 0.45
    return {
        {
            --* filter reset button will never be needed here, because we reset filters with the filter reset button in the dialog footer; see ((XrayDialogs#getListFilter)) > ((XrayController#resetFilteredItems)):
            KOR.buttoninfopopup:forXrayFilterByImportantType({
                callback = function()
                    KOR.dialogs:closeOverlay()
                    UIManager:close(DX.d.filter_xray_items_input)
                    DX.c:filterItemsByImportantTypes()
                end,
            }),
            KOR.buttoninfopopup:forXrayFilterByText({
                icon_size_ratio = icon_size_ratio,
                is_enter_default = true,
                callback = function()
                    --* items de facto filtered by text in ((XrayViewsData#filterAndPopulateItemTables)):
                    local form = DX.d.filter_xray_items_input
                    local filter_string = form:getInputText()
                    KOR.dialogs:closeOverlay()
                    UIManager:close(form)
                    if has_no_text(filter_string) then
                        return
                    end
                    DX.c:filterItemsByText(filter_string)
                end,
            }),
            {
                icon = "back",
                callback = function()
                    KOR.dialogs:closeOverlay()
                    UIManager:close(DX.d.filter_xray_items_input)
                end,
            }
        }
    }
end

--- @private
--- @return boolean true if more_button was added
function XrayButtons:injectItemsCollectionButton(buttons, indicator_buttons, status_icons, copies, nr, add_more_button)
    local item = copies[nr]

    local item_with_alias_found = false
    local more_button_added, is_alias, is_non_bold_alias

    is_alias = item.reliability_indicator and item.reliability_indicator == DX.tw.match_reliability_indicators.alias
    is_non_bold_alias = is_alias and not item.is_bold
    if is_non_bold_alias then
        item_with_alias_found = true
    end
    --? why return here?:
    if is_alias or item_with_alias_found then
        return false
    end
    more_button_added = self:addTappedWordCollectionButton(buttons, indicator_buttons, status_icons, item, {
        add_more_button = add_more_button,
        max_total_buttons = self.hits_buttons_max,
        max_buttons_per_row = self.max_buttons_per_row,
        nr = nr,
        source_items = copies,
        is_bold = item.is_bold,
        callback = function()
            -- #((related item button callback))
            DX.tw:registerCurrentItem(copies[nr])
            DX.d:viewTappedWordItem(copies[nr])
        end,
        extra_item_callback = function(citem)
            DX.d:viewTappedWordItem(citem)
        end,
    })
    if more_button_added then
        return true
    end
    return false
end

--* called from ((XrayTappedWords#getXrayItemAsDictionaryEntry)) > ((multiple related xray items found)):
--* items_found sorted and purged in ((XrayTappedWords#collectionSortAndPurge)):
function XrayButtons:forItemsCollectionPopup(items_found, tapped_word)
    --* is_bold prop will here be added to items:
    local copies = DX.tw:collectionPopulateAndSort(items_found, tapped_word)
    --* copies here don't have reliability indicators yet...
    --* via ((XrayTappedWords#setPopupResult)) below these buttons can be used to show the items as a list in ((XrayTappedWords#getCurrentListTabItems))

    local buttons = {}
    local indicator_buttons = {}
    count = #copies
    local add_more_button = count > self.hits_buttons_max
    local status_icons = {}
    local more_button_injected
    local buttons_count = count
    for nr = 1, count do
        more_button_injected = self:injectItemsCollectionButton(buttons, indicator_buttons, status_icons, copies, nr, add_more_button)
        if more_button_injected then
            buttons_count = nr
            break
        end
    end

    -- #((store tapped word popup collection info))
    --* we use the status_icons to force the item type and reliability icons shown in the list of this collection to be the same as in the popup:
    DX.tw:setPopupResult(copies, status_icons)

    local combined_rows = {}
    count = #buttons
    for i = 1, count do
        --* insert separator row at start of rows:
        if i == 1 then
            table.insert(combined_rows, {})
        end
        table.insert(combined_rows, indicator_buttons[i])
        table.insert(combined_rows, buttons[i])
        --* insert separator row between and at end of rows:
        if i <= count then
            table.insert(combined_rows, {})
        end
    end
    buttons = combined_rows
    table.insert(buttons, {
        KOR.buttoninfopopup:forXrayList(),
        {
            icon = "info-slender",
            icon_size_ratio = 0.53,
            callback = function()
                KOR.dialogs:textBoxTabbed(1, {
                    title = _("Explanation of Xray buttons"),
                    modal = true,
                    tabs = {
                        {
                            tab = _("bold items"),
                            info = [[BOLD ITEMS

Bold items contain the selected text in their name or in their aliases. They will be shown first in the list of buttons.

OTHER ITEMS
NNon-bold items were either linked from a bold item or they have a linkword in common with that item.]],
                        },
                        {
                            tab = _("reliability icons"),
                            info = DX.tw:getMatchReliabilityExplanation(),
                        },
                    },
                })
            end
        },
        KOR.buttoninfopopup:forSearchAllLocations({
            info = T(_([[search-list-icon | Show all occurrences of this Xray item in the current ebook.
Sneltoets %1 H]]), KOR.icons.arrow_bare),
            callback = function()
                UIManager:close(DX.d.xray_item_chooser)
                DX.c:viewItemHits(tapped_word)
            end,
        }),
        KOR.buttoninfopopup:forXrayFromItemToDictionary({
            enabled = has_text(tapped_word),
            callback = function()
                KOR.dictionary:onLookupWord(tapped_word)
            end,
        }),
        KOR.buttoninfopopup:forXrayItemAdd({
            callback = function()
                UIManager:close(DX.d.xray_item_chooser)
                DX.c:onShowNewItemForm("")
            end,
        }),
    })
    return buttons, buttons_count
end

--- @param mode string either "add" or "edit"
function XrayButtons:forItemEditor(mode, active_form_tab, reload_manager, item_copy)
    local edit_or_type_change_button = active_form_tab == 1 and
        self:forItemEditorEditButton()
        or
        {
            icon = "info-slender",
            callback = function()
                KOR.dialogs:niceAlert(_("Tips"), _("Tips about how to get best results with Xray items will soon follow..."))
            end
        }
    local dialog_will_be_closed_message = _([[This will close the form.

Continue?]])
    local buttons = {
        {
            KOR.buttonchoicepopup:forXrayGoBackFromForm({
                callback = function()
                    -- #((cancel item form))
                    DX.d:setProp("form_was_cancelled", true)
                    local returned_to_viewer = DX.d:closeForm(mode)
                    if not returned_to_viewer and DX.d.called_from_list then
                        DX.d:showListWithRestoredArguments()
                    end
                end,
                hold_callback = function()
                    DX.d:closeForm(mode)
                end,
            }),
            KOR.buttoninfopopup:forXrayList({
                callback = function()
                    KOR.dialogs:confirm(dialog_will_be_closed_message, function()
                        DX.c:setProp("return_to_viewer", false)
                        DX.d:closeForm(mode)
                        DX.d:showList(DX.d.item_requested)
                    end)
                end,
                info = _("Close form and go to list of Xray items."),
            }),
            KOR.buttoninfopopup:forXrayPageNavigator({
                callback = function()
                    KOR.dialogs:confirm(dialog_will_be_closed_message, function()
                        DX.c:setProp("return_to_viewer", false)
                        DX.d:closeForm(mode)
                        DX.c:showPageNavigator(DX.d.item_requested)
                    end)
                end,
                info = _("Close form and show Page Navigator."),
            }),
            edit_or_type_change_button,
            --* button to save and then force redirection to the list of items (opened if it wasn't open already):
            KOR.buttoninfopopup:forXrayItemSaveAndShowList({
                callback = function()
                    if mode == "add" then
                        DX.c:saveNewItem("return_to_list")
                        return
                    end
                    DX.c:saveUpdatedItem(item_copy, "return_to_list", reload_manager)
                end,
            }),
            KOR.buttoninfopopup:forXrayItemSave({
                callback = function()
                    local return_to_list = KOR.registry:getOnce("force_xray_list_reload") or DX.d.list_is_opened
                    KOR.dialogs:closeAllOverlays()
                    if mode == "add" then
                        DX.c:saveNewItem(return_to_list)
                        return
                    end
                    DX.c:saveUpdatedItem(item_copy, return_to_list, reload_manager)
                end,
            }),
        }
    }
    --* remove save and return to list button in case of tapped words viewer:
    if DX.m.use_tapped_word_data then
        table.remove(buttons[1], 5)
    end
    return buttons
end

function XrayButtons:forListSubmenu()

    --* insert buttons for Alles, Personen, Begrippen:
    local buttons = { {} }
    for i = 1, 3 do
        table.insert(buttons[1], self:getListSubmenuButton(i))
    end
    return ButtonTable:new{
        width = Screen:getWidth(),
        button_font_face = "x_smallinfofont",
        button_font_size = 17,
        button_font_weight = "normal",
        buttons = buttons,
        zero_sep = true,
        show_parent = DX.c,
    }
end

function XrayButtons:forListTopLeft(parent)
    return {
        {
            icon = "info-slender",
            callback = function()
                DX.d:showHelp(1)
            end
        },
        KOR.buttoninfopopup:forXrayTranslations(),
        KOR.buttoninfopopup:forXraySettings({
            callback = function()
                UIManager:close(parent.xray_items_chooser_dialog)
                parent.xray_items_chooser_dialog = nil
                DX.s:showSettingsManager()
            end
        }),
    }
end

--- @private
function XrayButtons:unfocusXrayButton()
    --* this registry var was set in ((MultiInputDialog#generateCustomEditButton)):
    local xray_type_button = KOR.registry:get("xray_type_button")
    xray_type_button.frame.fgcolor = KOR.colors.button
    xray_type_button.frame.radius = Size.radius.button
    if xray_type_button[1].background == KOR.colors.black then
        xray_type_button.frame.invert = false
        xray_type_button.frame.fgcolor = KOR.colors.black
        xray_type_button.frame.color = KOR.colors.black
        --* this also ensures the button border countours stay well defined:
        xray_type_button[1].background = xray_type_button[1].background:invert()
    end
    xray_type_button:refresh()
end

return XrayButtons
