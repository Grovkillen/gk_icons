# Changelog

All notable changes to GK Icons are documented in this file.

## 1.02.000 (2026-11-06)

### Added

* The icon minimize (corners turned inwards, the counterpart of Redmine's maximize), asked for by GK GUI Stuff for the size button of its panel in the whole window.
* The icon masks-theater (two theatre masks), asked for by GK People for the corner ribbon while an administrator sees the pages as another person.
* The icon world (a globe), asked for by GK GUI Stuff for the head of its card for links to other websites.

### Changed

* Icons in text is an appearance setting in GK Records' register (Administration, Appearance in GK GUI Stuff, group Text and links) instead of a function: off in a new installation, and when it is optional each person may switch it off. It also applies to someone not logged in. Show on the setting draws a sentence with the code written out and with the icon drawn. A function switched on before is not carried over.
* Icons in text are now drawn through GK Core Stuff's shared pass for formatted text, instead of GK Icons reading and rewriting each formatted text itself. The codes are replaced where they were before (also in a link's text, never in code); without GK Core Stuff they stay as written.
* The editor's Insert icon button stands just before Redmine's Help button with a space of its own, instead of taking the space that stood before Help, and a toolbar drawn before the script ran is found through its block, so the button keeps its place if Redmine changes the tools before Help.
* The recipes' homepage and download links use `rel="noopener noreferrer"` and name their place, so GK GUI Stuff can show them as external links.
* GK Icons now requires GK GUI Stuff. The Icons tab of the icon library is drawn on GK GUI Stuff's library, so that the icon library and GK GUI Stuff's style guide look and work the same; without GK GUI Stuff the tab says that it is required. The Groups tab is unchanged.
* The icon library keeps everything it had: the ranked search, the chips for the packs, the installation's own groups and (for administrators) the states, a disabled pack's chip greyed with its reason, core's page numbers with Per page and the larger choices, Sort, a click that copies the icon as A click copies says, the checked icons over every page with the box Checked icons, Reload from disk, and the panel with the large picture, the four sizes, the aspect ratio, the icon's groups, its state and similar icons. Your choices of view, per page and sort are carried over.
* In the icon library a chosen chip is filled in its colour instead of a light tone, and its count is a part of the chip after a solid divider instead of a number in brackets.
* View as is a view switch (Grid or List) with a dashed edge instead of a select, and is remembered in the browser as before. The list is Redmine's table with headings, the open icon's row marked as Redmine marks a selected row.
* The codes in the panel (Name, Used in text, In a plugin) are fields that select all on focus with a copy button; Copied stands by the button, and screen readers hear what was copied.
* For administrators an icon's state (active, disabled, missing) is GK GUI Stuff's flag instead of a status badge: on the icon's name in the panel, and in the grid as the flag's pennant at a disabled or missing icon with the word on hover. The panel says the state once, as the flag on the name, with Change the state... below the groups; the State column of the list shows the state as GK GUI Stuff's flag in the text's flow, the pennant before the word in the state's role.
* The state chip for icons missing on disk reads Missing on disk, capitalised as the other chips.
* The four sizes in the panel (16, 24, 32 and 48 px) stand in one row at every width of the panel. On the Packs tab a pack's state is the flag on the pack's name, with the latest reason as the pennant's tooltip, and the Status column shows the state as the flag in the text's flow, the pennant before the word, instead of a badge.
* The arrow keys, Home and End move between the icons (and to the page before or after), Enter opens an icon's panel, Esc closes it and gives the focus back, and the icon open stands in the address, so that a link leads to it.
* Show for icons in text has the line through the middle of the text, when GK GUI Stuff offers it.
* A click on an icon in text confirms the copy with GK GUI Stuff's shared whisper under the icon. Without GK GUI Stuff the confirmation stands at the icon as before.
* An instance's own icon packs are looked for in `gk/icon_packs` in the attachments folder. The earlier folder `icon_packs` there is still read as long as it exists, so nothing needs to be moved; a pack with the same key in the new folder replaces it. The machine's folder and `GK_ICON_PACKS` are as before.

### Fixed

* Save for the state of the selected icons works again after a first Save that was stopped because no state was chosen; Redmine's guard against double submission no longer blocks it.
* The icon picker's button follows its field when the field is set back from outside and says so with a change event, such as a form's Undo all.

## 1.01.000 (2026-10-28)

### Changed

* The plugin's functions are declared in the register of GK Records (1.04.000 or later) instead of GK GUI Stuff's, and are still switched on under Administration > Functions in GK GUI Stuff. Without GK Records they are off.
* Settings, icon packs: whether a pack folder exists is shown as Redmine's status badge (found green, missing grey), in the middle of its row, instead of plain text.

## 1.00.000 (2026-10-26)

* First release.
