# GK Icons

GK Icons gives Redmine and the GK plugins one way to write and draw icons: Redmine's own icons, a set of extra icons built from the same source as Redmine's, and external icon packs that are installed separately. Icons can be written in wiki text, issues and notes, and other plugins draw them through the same helper.

## Features

- A view helper, `gk_icon(name)`, that draws an icon the same way as Redmine's `sprite_icon`. An icon Redmine has is drawn from Redmine's sprite; an icon Redmine lacks comes from the plugin's own sprite, built from Tabler Icons v3.43.0 (the same source Redmine uses). A JavaScript counterpart (`GkIcons.svg`) draws the same icons in the browser.
- External icon packs: a pack is a folder of `.svg` and `.png` files, with an optional `pack.yml` (name, version, license, attribution, variants, shortcodes and whether the icons take the text's colour). A pack icon is written `pack/name`, for example `fa/hammer`. Packs are found by themselves, without a setting or a restart, in `<attachments storage path>/icon_packs` and in the folders listed in the environment variable `GK_ICON_PACKS`, among other roots shown on the settings page.
- Packs are read into the database and served from there as sprites, and read again in the background when a pack folder changes. An icon whose file is removed from disk keeps its copy in the database, so texts that already use it do not break.
- Icon states: an administrator can mark single icons or whole packs as active or disabled. Only active icons are offered in the library and the picker; the settings decide whether disabled icons and icons missing on disk are still drawn where they are already used.
- Icon groups across packs, which icons can be put in and taken out of.
- Icons in text: codes such as `:fa/hammer:` or `:gk/status-done:` in wiki pages, issue descriptions and notes are drawn as icons, never inside code, pre blocks, form fields or link addresses. Unknown codes stay as text.
- The icon library page: every icon (Redmine's, GK's and the packs'), with search, groups, Redmine's page numbers, a grid or a list, and a click that copies the icon as a text code or as a name and shows it in a panel (large, at four sizes, its aspect ratio, how it is written, similar icons). Administrators also get the tabs Icons, Packs and Groups to manage states and groups, and a button to read the packs again from disk.
- An icon picker for other plugins: any input with `data-gk-icons-picker` becomes a button that shows the chosen icon and opens a searchable list.
- Insert icon in the editor: a button in Redmine's wiki toolbar opens the same searchable list and writes the chosen icon's code where the cursor stands (the function "Insert icon in the editor").
- Icon files are served with a restrictive Content Security Policy, so a pack's SVG cannot run scripts when opened on its own.
- With gk_records, every state change, group change, group membership change and pack reading that changed something is kept as an event, and state changes ask for a reason.

## Requirements

- Redmine 6.0.0 or higher.
- Ruby 3.2 or later, the version your Redmine release runs on.
- PostgreSQL.

This plugin is developed and tested on Windows 11 with PostgreSQL only. That is a deliberate choice made for the maintainer's own convenience: the production system and the whole toolchain run there, and supporting other platforms and databases would cost time without adding anything for our own use. The Ruby code avoids needless Windows or PostgreSQL specific constructs, so it may well run on Linux, but that is untested and not supported. The migrations use only ordinary column types, but PostgreSQL is the only database the plugin is tested on.

GK plugins:

- Required: none.
- Optional: gk_records (reasons and history for icon and pack states and groups), gk_gui_stuff (the switchable functions "Icons in text", "Icon library for all signed-in users" and "Insert icon in the editor"; without it all three stay off), gk_compat (core's colour variables in the older supported series; without it the stylesheet's fallback colours are used), gk_fields (the icon groups' names and descriptions in other languages), gk_scenarios (the plugin's scenario checks).

## Installation

The plugin directory must be named `gk_icons` (it is the plugin id): `plugins/gk_icons/`.

1. Unpack the release package into Redmine's `plugins` directory.
2. Run the migrations: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`
3. Restart Redmine.

Uninstall:

1. `bundle exec rake redmine:plugins:migrate NAME=gk_icons VERSION=0 RAILS_ENV=production`
2. Remove the `plugins/gk_icons` directory and restart Redmine.

Icon packs are not part of the release package. Put each pack in its own folder under one of the pack roots.

### Adding an icon pack

The pack roots are the machine's `icon_packs` folder, the instance's `<attachments storage path>/icon_packs` and the folders in the environment variable `GK_ICON_PACKS`. A pack is a folder with svg (or png) files and an optional `pack.yml` (key, name, version, license, attribution, homepage, `mono`, and for icons in text `text_scale`, `text_shift` and `text_gap`, which the Packs tab of the icon library can override; an icon in text is drawn as high as the text's capitals by what it draws, measured when the pack is read in, and the three fine-tune that). The folder holds the icons directly; a subfolder is read as a variant of the same icons.

The plugin has recipes for common packs in `config/icon_pack_recipes/`: Font Awesome Free, Line Awesome, Lucide, Bootstrap Icons, Tabler Icons, Phosphor, Heroicons, Material Symbols and flag-icons. Each recipe says where the package is downloaded, which folder in it has the icons, and the `pack.yml` to put beside them. A package with several styles (Font Awesome solid, regular and brands; Phosphor's weights) is made into one pack per style, so that each can be written in text (`:fa/house:`, `:far/house:`). To add one:

1. Download the file the recipe names from its page (the recipe's `verified` is the version it was tried with).
2. Unpack it, and copy each pack's `from` folder into a pack root as a folder named by the pack's `folder`. Where the recipe has `match`, `exclude` or `strip`, copy only those files and take `strip` off their names.
3. Save the pack's `pack.yml` from the recipe in the folder, with the version you downloaded, and copy the license file beside it.
4. Press Reload from disk in the icon library. The packs tab lists the new packs; the recipes' `pack.yml` are shown there too.

A pack without a recipe works the same way: a folder of svg files and its own `pack.yml`. The license is information for the administrator; the plugin does not decide what may be used.

## Configuration

- Administration > Plugins > Configure (GK Icons): whether disabled icons and icons missing on disk are shown or not where they are already used, the list of GK's icons, and the pack roots with each found pack (key, number of icons, variants, license and a sample).
- Administration > Icon library: manage the states of icons and packs, and the icon groups.
- With gk_gui_stuff, Administration > Functions switches "Icons in text", "Icon library for all signed-in users" and "Insert icon in the editor" on or off. All three are off in a new installation.

## Usage

- Write `:pack/name:` (or `:gk/name:` for Redmine's icons and GK's) in a wiki page, issue description or note to show an icon, when "Icons in text" is on. With "Insert icon in the editor" on, the toolbar button writes the code for you.
- Open the icon library to find an icon and copy how it is written. Administrators can always open it from Administration; while "Icon library for all signed-in users" is on, everyone signed in, administrators too, opens it from the account menu.

## Changelog

See CHANGELOG.md.

## License

GPL-2.0-or-later, the same license as Redmine. Copyright (C) 2026 Jimmy Westberg. See the LICENSE file for the full text.

The plugin's own icons are built from Tabler Icons (MIT License). Its license text is in LICENSE_TABLER.txt. External icon packs carry their own licenses.
