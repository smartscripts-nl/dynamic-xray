# Dynamic Xray plugin

A KOReader plugin to view "xray items", i.e. user defined explanations of persons, places and terms in books or even entire series.

Dynamic Xray (DX) plugin was inspired by the X-ray system on Kindles (see explanation on [Amazon X-Ray on Kindle | All you need to know - YouTube](https://youtu.be/mreow-OrGsU?si=c_3NhHKBDa1BFEvI)). DX differs from the Kindle system in that the user can define items dynamically, while on Kindles these items are "baked into" the ebook. The advantage of the former approach is that you can dynamically add and modify items, but the advantage of the Kindle approach is that it isn't error-prone. DX is, because it uses matching of the words in ebook texts to determine whether Xray items are present. Which can lead to incorrect hits. But in at about 95% of cases the matches will be correct.

Dynamic Xray uses a stripped down version of my personal extensions system for KOReader.

## Installation

1. Clone this repo somewhere. From there:
2. Copy the folder "extensions" under frontend to the frontend folder of your KOReader installation **(DON'T overwrite your KOReader frontend folder with the frontend folder from the repository!)**
3. Copy xraycontroller.koplugin under the plugins folder to your KOReader plugins folder **(same warning as under the previous step: don't overwrite your entire plugins folder!)**
4. Copy the svg icons under resources/icons/mdlight to the corresponding folder under your KOReader installation dir **(don't overwrite your original folders and files here!)**
5. The "koreader-settings-and-patches" folder in this repository represents the settings folder of your koreader installation. In most cases this target folder will be named "koreader". In its root you should find settings.reader.lua.
6. In that target folder create a folder patches if it doesn't exist yet and copy koreader-settings-and-patches/patches/2-xray-patches.lua to that target patches folder.
7. Copy koreader-settings-and-patches/settings/settings_manager.lua to the settings subfolder of the koreader settings folder of your current installation (this folder should already be present and should contain many files, e.g. sqlite3-files for KOReader's databases).
8. If you want to translate messages in the Dynamic Xray system, you can do that in frontend/extensions/translations/xray-translations.po. In that file add your translations after "msgstr" entries, but take care that you adhere to the instructions at the start of that file.
9. You could also choose to disable these translations (and therefor see all DX button labels etc. in English) by adding one character to the msgid blocks in the transations file. E.g. change msgid "Short names" to msgid "aShort names".

## Usage tips

### Adding Xray items

* The patch file adds a button "+ Xray" to the popup dialog for text selections. With this button you can add new Xray items from the text selection.
* From the list of Xray items (to which you can assign a gesture, for quickly showing it), you can view and edit items, or add new items, by tapping on the plus-icon in the dialog footer.
* If in the add/edit Xray item dialog, under the first tab "xray-item" you don't see buttons, that is caused by the textarea for the description of the Xray item being too high. In these cases the buttons _are_ present, but hidden under the keyboard. You can rectify this by:
  * tapping on the "metadata" tab at the top of the dialog
  * and then tapping again on "xray-item".
  * You now should see the buttons.
  * If not, you could try closing the dialog and then re-opening it.
  * This should be a one time problem, DX remembers the correct height for the textarea under the first tab, which will allow the buttons below to remain visible upon subsequent calls of the dialog.

### Displaying help information about the function of buttons
DX uses mostly buttons with only icons, so without explanatory labels. However, if a button contains a point on the right side of the icon, or a downwards pointing arrow on the left side, this means that you can trigger a popup with help information about the function of that button by longpressing it.
* An arrow means that a button has more than one action available upon longpress.
* A point signifies a one action button.
* These actions can then be executed by tapping on the buttons at the bottom of the help dialog.
* If you don't longpress the main button, which had the help information, but simply tap it, its main function will be immediately triggered.

## About the code

* DX is added by patching the stock KOReader code, so you don't have to modify the code of the basic KOReader version.
* The DX plugin is structured to resemble an MVC structure:
    * M = XrayModel > data handlers: XrayDataLoader, XrayFormsData, XraySettings, XrayTappedWords and XrayViewsData (extensions)
    * V = XrayUI, and XrayDialogs and XrayButtons (extensions)
    * C = XrayController (plugin)

## Development history and usage

See [Dynamic Xray plugin · koreader/koreader · Discussion #12964 · GitHub](https://github.com/koreader/koreader/discussions/12964)
for the development history of this plugin and for Dynamic Xray usage examples by screenprints and screencasts.

## Tip for navigating the code

* Use a JetBrains IDE (e.g. PhpStorm) with the extensions EmmyLua and Better Highlights. With that you get clickable comments and very good type hints, which makes it much, much easier to navigate through the code.

* Also with Better Highlights you can colorize comments differently depending on the use case, for much improved readability.

* In Better Highlights settings set (( and )) as wikilink start and end - the default is [[ and ]] -, so you can add clickable comments to --(( )) lua commented blocks.

## No support provided

Alas, I don't have time to support this plugin. Use it at your own risk. If and when the KOReader developers community would integrate this plugin into the source code of KOReader, you can probably get support there.

## License

GNU General Public License (GPLv3): open source software, free to use, modify and distribute your version. Naming me as the author of the very first version would be nice.
