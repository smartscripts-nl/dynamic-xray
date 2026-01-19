# Dynamic Xray plugin
# Kindle-like functionality for KOReader

A KOReader plugin to view "xray items", i.e. user defined explanations of persons and terms in single books or even entire series:

* This DX plugin was inspired by the X-ray system on Kindles (see explanation
  on [Amazon X-Ray on Kindle | All you need to know - YouTube](https://youtu.be/mreow-OrGsU?si=c_3NhHKBDa1BFEvI)).
* "Terms" in Dynamic Xray (DX) can be names of things, entities, concepts, definitions, places, named events, names of literary or philosophical movements, and much more. It's all up to the imagination of the user...
* DX differs from the Kindle system in that the user can define items dynamically, while on Kindles these items are "baked into" the ebook.
* The advantage of the DX approach is that the user can dynamically add and modify items or link them to other items; the advantage of the Kindle approach is that it isn't error-prone.
* DX can produce false hits, because it uses matching of the words in ebook texts to determine whether Xray items are present. For example, DX will be in trouble if there are two or more persons with the same first name in a book; DX won't be able to differentiate between them. But in about 95% of cases, the matches shown will be correct.
* All interface texts can be translated by the user.
* Some hotkeys for buttons in DX dialogs can be configured by the user, from within KOReader. The Page Navigator can be called while reading an ebook, with Shift+X.
* The Page Navigator module now offers an extra side tab to quickly inspect Xray items which are linked to the items named in the page. From there can then edit them, view more details about them or search all their locations in the current ebook. You can see this feature in action in the [videos section](#videos).

## Table of contents in this readme
- [Use cases](#use-cases)
  - [Fiction books](#fiction-books)
  - [Non-fiction books](#non-fiction-books)
- [Installation](#installation)
  - [Updating to new versions](#updating-to-new-versions)
  - [Entering your own translations for the DX interface](#entering-your-own-translations-for-the-dx-interface)
- [Usage tips](#usage-tips)
  - [Browsing with the Page Navigator (most Kindle-like)](#adding-xray-items)
  - [Adding Xray items](#browsing-with-the-page-navigator-most-kindle-like)
  - [Displaying help information about the function of buttons](#displaying-help-information-about-the-function-of-buttons)
- [DX in action](#dx-in-action)
    - [Videos](#videos)
    - [Images](#images)
- [DX Settings menu](#dx-settings-menu)
- [Problem solving](#problem-solving)
    - [Notification: DX couldn't be initialized](#notification-that-dx-couldnt-be-initiated)
    - [User uses a database file other than "bookinfo_cache.sqlite3"](#user-uses-a-database-file-other-than-bookinfo_cachesqlite3)
- [Issues to fix](#issues-to-fix)
- [Todos](#todos)
- [About the code](#about-the-code)
- [Development history and usage](#development-history-and-usage)
- [Icons](#icons)
- [Tips for navigating through the code](#tips-for-navigating-through-the-code)
- [License](#license)

## Use cases

### Fiction books
The user can use DX to keep track for an ebook or an entire series of many persons and terms, mark them as important, to see how they are linked to other items, what are their aliases, in which chapters they are mentioned and how frequent, etc.
### Non-fiction books
The user can use DX for study: to keep track of entities, concepts, definitions, places, named events, names of literary or philosophical movements etc., to see how these are linked to each other, in which chapters they can be found and how frequent, etc.

## Installation

1. Clone this repo somewhere. From there:
2. Copy _the contents of_ all folders under "koreader-settings-folder" to the corresponding folders under the settings folder (almost always named "koreader") of your KOReader installation.
   * **⚠️ NB: Don't overwrite entire folders in this target folder with the folders from the repository!** The only folders which you can safely overwrite are "extensions" and "plugins/xraycontroller.koplugin".
   * **⚠️ NB 2: the contents of the subfolder "icons" must be copied to the corresponding folder under the KOReader settings folder**, to have custom icons shown in the DX interface.
   * NB 3: thanks to the patches DX applies to KOReader, the plugin XrayController will also be loaded from KOReader's settings folder...
3. **⚠️ It's especially important that you copy koreader-settings-folder/patches/2-xray-patches.lua to a subfolder "patches" in your KOReader settings folder!** Without this, DX won't be available in your installation.
4. The "koreader-settings-and-patches" folder in this repository represents the settings folder of your koreader installation. In most cases, this target folder will be named "koreader". In its root you should find settings.reader.lua.
5. In that target folder, create a folder patches if it doesn't exist yet and copy koreader-settings-and-patches/patches/2-xray-patches.lua to that target patches folder.
6. Copy koreader-settings-and-patches/settings/settings_manager.lua to the settings subfolder of the koreader settings folder of your current installation (this folder should already be present and should contain many files, e.g. sqlite3-files for KOReader's databases).
7. **⚠️ Check whether the database filename in your KOReader settings folder is "bookinfo_cache.sqlite3".** If not, go through the additional steps listed in [User has a database filename other than "bookinfo_cache.sqlite3"](#user-uses-a-database-file-other-than-bookinfo_cachesqlite3)

### Updating to new versions

When you clone new versions of DX, make sure you also **⚠️ update the patch file** on your device. Otherwise, you might be confronted with crashes...

### Entering your own translations for the DX interface

As of 2025-12-25 translations are now stored in the table xray_translations in the database. This table will be automatically created upon KOReader start. The translations are lazily stored in that table, only when requested.

This will make the code and updates much easier to maintain for me _and_ for cloners... Users can translate texts in the TranslationsManager, which is reachable from the bubbles icon in the:
* top left corner of the list of Xray items
* top left corner of the information popup called with a tap on an Xray marker (lightning or star) in the ebook text
* top left corner of the Xray item viewer dialog
* the most left main menu item → Dynamic Xray → Translate interface

**⚠️ The folder frontend/extensions/translations with in it a .po-file has therefore now been removed.**

## Usage tips

### Browsing with the Page Navigator (most Kindle-like)

With the Page Navigator, you can browse through pages and see all known Xray items marked bold there. In the side panel you can tap on items to show their explanation in the bottom panel.

You can show this navigator by:
* pressing Shift+X on your (BT) keyboard; I'm not sure if this'll work on all KOReader installations
* longpressing the lightning or star Xray markers in pages
* tapping in KOReader's main menu: most left icon > Dynamic Xray > Show Page Navigator
* assigning a gesture for "Show Xray Page Navigator" (in the Gestures menu under "Reflowable documents...") and then use this gesture.

#### Generate a copyable list of all Xray items from Page Navigator

With the export button in Page Navigator you open a popup with a list of all Xray items. Including stats and additional info per item. This list you can copy to the clipboard and then print, if you like, for usage next to your e-reader.

#### Browsing by a specific item in the Page Navigator

When you longpress an item in the side panel, a filter icon will appear on the left side of that item. From now on, while browsing forward or backwards, the Navigator will only show pages which contain that filtered item. Very handy for study purposes!

If you want to undo the filter, longpress the filtered item in the side panel once again.

### Adding Xray items

* The patch file adds a button "+ Xray" to the popup dialog for text selections. With this button, you can add new Xray items from the text selection.
* From the list of Xray items (to which you can assign a gesture, for quickly showing it), you can view and edit items, or add new items, by tapping on the plus-icon in the dialog footer.
* When you select a longer text in the ebook and tap on "+ Xray", DX will set this text as the description of the new Xray item. You then only have to type its name in the field below the description.
* By clicking on lightning or star icons in the margins of ebook pages, you can call up an overview of Xray items in resp. the current page or the paragraph with the star icon.
* You can assign a gesture to quickly call up the list of all Xray items in the book or series: cog icon in the main KOReader menu → Taps and gestures → Gesture manager → Multiswipes → select a gesture → Reader → Show xray-items in this book/series
* In the same way, you can also attach a gesture to the action "Add an Xray item".

### Displaying help information about the function of buttons
DX uses mostly buttons with only icons, so without explanatory labels. However, if a button contains a point on the right side of the icon, or a downwards pointing arrow on the left side, this means that you can trigger a popup with help information about the function of that button by longpressing it.
* An arrow means that a button has more than one action available upon longpress.
* A point signifies a one action button.
* These actions can then be executed by tapping on the buttons at the bottom of the help dialog.
* If you don't longpress the main button, which has the help information, but simply tap it, its main function will be immediately triggered.

## DX in action

### Videos

* [See releases](https://github.com/smartscripts-nl/dynamic-xray/releases/tag/videos)

### Images

![01 Xray marker in page](images/01-xray-marker-in-page.png)
01 Xray marker in page

![02 Xray info dialog after click on marker](images/02-xray-info-dialog-after-click-on-marker.png)
02 Xray info dialog after click on marker

![02b Page Navigator](images/02b-page-navigator.png)
02b Page Navigator, with info panel with explanations of Xray items in the page.

![02c Page Navigator: hotkeys](images/02c-page-navigator-hotkeys.png)
02c Page Navigator: hotkeys.

![02d Tappable popup with linked items](images/02d-info-popup-with-linked-items.png)
02d Tappable popup with linked items after longpressing a name in the ebook

![03 List of Xray items](images/03-list-of-xray-items.png)
03 List of Xray items

![04 Xray item viewer tab 1](images/04-xray-item-viewer-tab-1.png)
04 Xray item viewer tab 1

![05 Xray item viewer tab 2](images/05-xray-item-viewer-tab-2.png)
05 Xray item viewer tab 2

![06 Xray item editor tab 1](images/06-xray-item-editor-tab-1.png)
06 Xray item editor tab 1

![07 Xray item editor tab 2](images/07-xray-item-editor-tab-2.png)
07 Xray item editor tab 2

![07b Larger field editor](images/07b-larger-field-editor.png)
07b Larger field editor, called with edit button next to field. Handy for fields with longer content.

![07c Larger field editor](images/07c-editor-tab-2-set-xray-type.png)
07c Editor tab 2: set Xray type from popup dialog: person, important person, term or important term.

![08 Help info for buttons](images/08-help-info-for-buttons.png)
08 Help info for buttons

![09 Manage XraySettings in a tabbed interface.](images/09-manage-xray-settings.png)
09 Manage XraySettings in a tabbed interface.

![09b Manage DX hotkeys.](images/09b-user-configurable-dx-hotkeys.png)
09b Manage DX hotkeys.

![09c Modify a DX hotkey.](images/09c-modify-a-dx-hotkey.png)
09c Modify a DX hotkey

![10 Interface translations list](images/10-interface-translations-list.png)
09b Interface translations list

![10b Translations navigator](images/10b-translations-navigator.png)
10b Translations navigator

![10c Editing a translation](images/10c-editing-a-translation.png)
10c Editing a translation

![10d Help info for translations editor](images/10d-help-info-for-translations-editor.png)
10d Help info for translations editor

## DX Settings menu

* Open the KOReader main menu
* Go to most left main item → Dynamic Xray (NB: this item is positioned at the bottom of the items, so you might have
  to navigate to the next subpage) → Settings
* This same settings menu is also reachable through the cog icon at the top left of these four dialogs:
    * the Xray items list
    * the Xray item viewer
    * the Xray Page Navigator
    * the popup dialog after you clicked upon a lightning or a star marker in the text of the e-book

## Problem solving

### Notification that DX couldn't be initiated

This lets the user know that somewhere in KOReader (maybe in DX, maybe in another plugin) an error occurred, which prevented DX from initializing. Alas, these error conditions are very hard to debug for me from a distance...

### User uses a database file other than "bookinfo_cache.sqlite3"

The default database filename in the KOReader settings dir will almost always be "bookinfo_cache.sqlite3". But apparently **⚠️ some
users have a different database filename**, with a prefix string attached by some other plugin at the front, e.g. "
PT_bookinfo_cache.sqlite3". In that case:

1. Go to the [DX Settings menu](#dx-settings-menu)
2. Enter and save the correct database file name for your installation in the setting "database_filename".
3. KOReader will automatically be reloaded and then create the xray_items table in your database.

## Issues to fix
* Currently none?

## Todos
* Base custom translations on indices instead of the texts they translate → continued usability of translations by the user much better protected, even when the actual text to be translated changes.

## About the code

* Dynamic Xray uses a stripped version of my personal extensions system for KOReader.
* DX is added by patching the stock KOReader code, so you don't have to modify the code of the basic KOReader version.
* The DX plugin is structured to resemble an MVC structure:
    * M = XrayModel > data handlers: XrayDataLoader, XrayDataSaver, XrayFormsData, XraySettings, XrayTappedWords and XrayViewsData (extensions)
    * V = XrayUI, XrayPageNavigator, XrayTranslations and XrayTranslationsManager, XrayDialogs and XrayButtons (extensions)
    * C = XrayController (plugin)
* The XrayHelpers extension of DX version 1.0 does not exist anymore, its methods have been redistributed over the above extensions. 
* In xray-info.lua you can find some explanations for programmers about the inner workings of DX. This file doesn't have a function in the plugin, is meant to be purely informational.
* Since the KOR extensions system uses many heavily modified stock KOReader modules and widgets, these modified files are loaded instead of the stock versions from the subfolders "modules" and "widgets" under the "extensions" folder.
* DeepWiki.com has an extensive analysis of the DX system. See [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/smartscripts-nl/dynamic-xray).

## Development history and usage

See [Dynamic Xray plugin · koreader/koreader · Discussion #12964 · GitHub](https://github.com/koreader/koreader/discussions/12964)
for the development history of this plugin and for Dynamic Xray usage examples by screenprints and screencasts.

## Icons

Most icons used by DX were downloaded from [Online Webfonts](https://www.onlinewebfonts.com/icon/), and some from [SVG Repo](https://www.svgrepo.com/). In some cases, I've renamed these icons, to clarify their function in DX.

## Tips for navigating through the code

* Use a JetBrains IDE (e.g. PhpStorm) with the extensions EmmyLua and Better Highlights. With that you get clickable comments and very good type hints, which makes it much, much easier to navigate through the code.

* Also, with Better Highlights, you can colorize comments differently depending on the use case, for much improved readability.

* In Better Highlights settings set (( and )) as wikilink start and end - the default is [[ and ]] -, so you can add clickable comments to --(( )) lua commented blocks.

## License

GNU General Public License (GPLv3): open source software, free to use, modify and distribute your version. Naming me as the author of the very first version would be nice.
See license.md in this repository or https://www.gnu.org/licenses/gpl-3.0-standalone.html for more details of the license.
