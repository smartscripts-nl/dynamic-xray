# Dynamic Xray plugin

A KOReader plugin to view "xray items", i.e. user defined explanations of persons, places and terms in books or even entire series.

Dynamic Xray plugin was inspired by the X-ray system on Kindles (see explanation on [Amazon X-Ray on Kindle | All you need to know - YouTube](https://youtu.be/mreow-OrGsU?si=c_3NhHKBDa1BFEvI)). Dynamic Xray differs from the Kindle system in that the user can define items dynamically, while on Kindles these items are "baked into" the ebook.

Dynamic Xray uses a stripped down version of my personal extensions system for KOReader.

## Installation

1. Clone this repo somewhere. From there:
2. Copy the folder "extensions" under frontend to the frontend folder of your KOReader installation (DON'T overwrite your KOReader frontend folder with the frontend folder from the archive!)
3. Copy xraycontroller.koplugin under the plugins folder to your KOReader plugins folder (same warning as under the previous step: don't overwrite your entire plugins folder!)
4. Copy the svg icons under resources/icons/mdlight to the corresponding folder under your KOReader installation dir (don't overwrite your original folders and files here!)
5. The "koreader-settings" folder in the archive represents the settings folder of your koreader installation. In most cases this folder will be named "koreader". In its root you should find settings.reader.lua.
6. In that target folder create a folder patches if it doesn't exist yet and copy koreader/patches/2-xray-patches.lua to that target patches folder.
7. Copy koreader/settings/settings_manager.lua to the settings folder of the koreader settings folder of your current installation (this folder should already have a settings subfolder, with many files in it).
8. If you want to translate messages in the Dynamic Xray system, you can do that in frontend/extensions/translations/xray-translations.po. In that file add your translations after "msgstr" entries, but take care that you adhere to the instructions at the start of that file.

## Tip for navigating the code

* Use a JetBrains IDE (e.g. PhpStorm) with the extensions EmmyLua and Better Highlights. With that you get clickable comments and very good type hints, which makes it much, much easier to navigate through the code.

* Also with Better Highlights you can colorize comments differently depending on the use case, for much improved readability.

* In Better Highlights settings set (( and ) as wikilink start and end - the default is [[ and ]] -, so you can add clickable comments to --[[ ]] lua commented blocks.

## Development history and usage

See [Dynamic Xray plugin · koreader/koreader · Discussion #12964 · GitHub](https://github.com/koreader/koreader/discussions/12964) for the development history of this plugin and for Dynamic Xray usage examples by screenprints and screencasts.

## No support provided

Alas, I don't have time to support this plugin. Use it at your own risk. If and when the KOReader developers community would integrate this plugin into the source code of KOReader, you can probably get support there.

## License

GNU General Public License (GPLv3): open source software, free to use, modify and distribute your version. Naming me as the author of the very first version would be nice.
