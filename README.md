# Dynamic Xray plugin

A KOReader plugin to view "xray items", i.e. user defined explanations of persons, places and terms in books or even entire series.

Dynamic Xray plugin was inspired by the X-ray system on Kindles (see explanation on [Amazon X-Ray on Kindle | All you need to know - YouTube](https://youtu.be/mreow-OrGsU?si=c_3NhHKBDa1BFEvI)). Dynamic Xray differs from the Kindle system in that the user can define items dynamically, while on Kindles these items are "baked into" the ebook.

Dynamic Xray uses a stripped down version of my personal extensions system for KOReader.

## Installation

1. Import xray-items.sql into statistics.sqlite3.

2. Read code-explanations.lua carefully!

3. Follow the instructions in that file.

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
