# Changelog

All notable changes to TalentBarSaver are listed here. Newest version first.

## [0.5.0] - 2026-11-25

### Added
- **Quick menu.** Shift-click the minimap button to load any profile with one click. If you have unsaved changes, the menu also offers to save them.
- **Unsaved changes hint.** When you change your bars after loading or saving a profile:
  - the profile shows *(changed)* in the Profiles tab, with a "Save changes" button
  - a small dot appears on the minimap button, and the tooltip tells you about it
  - loading screens do not reset the hint
- **Key bindings per profile (optional, off by default).** Turn it on in a profile's `...` menu. Your key bindings are saved with the profile and loaded with it. Profiles with saved bindings show *[keys]*.
  - `/tbs undobinds` restores the bindings from before the last profile load.
  - Never changed in combat.
- **Glyph reminder.** Your glyphs are saved with a profile. After loading it, you get a hint in chat if your glyphs do not match. Nothing is changed automatically. You can turn it off in Options.
  - Profiles saved before 0.5.0 have no glyph data yet. Save them once (`...` > Save current bars) to start the check.

### Changed
- Saving your current bars into a profile now marks that profile as loaded.
- Internal: all optional features are separate modules in `Core/` and share the same hooks, so new features are easier to add.

## [0.4.0] - 2026-11-25

### Added
- **Talent-based spec detection.** Your spent talents are compared point by point with every linked template. The best match (at least 80%) wins.
  - Specs with the same main tree are now told apart, e.g. Ret PvE, Ret PvP and PREG, or Feral cat and bear.
  - Works for specs that were spent by hand or existed before the addon was installed.
  - If two templates match equally (e.g. identical hybrid builds), the template you applied last wins.
- The chat message and the Links tab show why a profile was chosen, e.g. `template PREG, 100% match`.

### Changed
- **Compact profile list.** One line per profile: gear set icon, name, Load and a `...` menu.
  - Click the icon to pick a gear set.
  - Use `...` to save your current bars into a profile, rename it or delete it.
- Dialog and menu buttons (Yes, No, Accept, Cancel) are now always in English. Before, they followed the client language.
- The Help tab and README explain the new detection and the new profile list.

### Fixed
- Switching between specs with the same main tree loaded the wrong profile and gear set (e.g. PvE gear for a PvP spec).

## [0.3.0] - 2026-11-25

### Added
- **Gear sets.** Link an Equipment Manager set to a profile. It is equipped whenever the profile is loaded.
  - Automatic switches always equip the linked set.
  - Manual loads (Load, Apply now, `/tbs restore`) equip it too. You can turn this off in Options.
- Nothing is equipped in combat or while dead. The set is equipped right afterwards.
- Missing items, and items that are only in your bank, are listed in chat with item links. Everything that is available is equipped anyway.
- A message appears if a linked gear set was deleted or renamed.
- Gear set icons are shown next to profiles, in menus, in chat messages and on the minimap button.

## [0.2.0] - 2026-11-25

### Added
- **Help tab** with a step-by-step setup guide, tips and all commands. It opens automatically the first time you use `/tbs`.
- **Minimap button.** Left-click opens the window, right-click opens Talented, drag to move. Turn it on or off in Options or with `/tbs minimap`.

### Changed
- The whole addon is now in English: window, buttons, dialogs, chat messages, tooltips and code comments.
- The German `LIESMICH.txt` was removed. The README covers everything.

## [0.1.0] - 2026-11-25

### Added
- First version. Talented and Action Bar Saver 2 combined into one addon.
- **Template → profile links.** Link each Talented template to an action bar profile.
- **Fallback per talent tree** for specs without a matching template.
- **Automatic switching** after Talented applies a template and on a dual spec change.
- Loading waits until the spellbook has updated, so new talent spells end up on your bars.
- Nothing is loaded in combat. A pending switch runs right after combat ends.
- **Window** (`/tbs`) with tabs for profiles, links and options.
- `/tbs` slash command. All `/abs` commands still work.

### Fixed (Action Bar Saver 2)
- `String.format` typo that caused a Lua error when restoring a profile in combat.
- Wrong variable in error messages.
- The error list was not cleared between restores.
- The item name was missing from error messages.
- Empty spellbook tabs were not handled.

### Removed (Talented)
- The "Restore bars with ABS" option. It never worked, because it looked for a global `ABS` that does not exist. The new integration replaces it.
