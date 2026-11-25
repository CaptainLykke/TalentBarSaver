# TalentBarSaver

A World of Warcraft addon for **Wrath of the Lich King 3.3.5a** that combines talent templates, action bar profiles and gear sets in one place.

It merges [Talented](https://www.curseforge.com/wow/addons/talented) (talent template editor) and [Action Bar Saver 2](https://github.com/Shadowed/ActionBarSaver) (action bar profiles), and connects them. Assign an action bar profile to each talent template, and your bars switch automatically when you apply a template or change your dual spec. Each profile can also equip a gear set from the Equipment Manager.

This is useful for classes that play more than two specs. For example, a Paladin who switches between Retribution, Holy and Protection no longer has to type `/abs restore …` after every respec.

## Features

- **Template → profile:** link every Talented template to an action bar profile.
- **Smart spec detection:** your spent talents are compared point by point with every linked template, so specs with the same main tree (Ret PvE / Ret PvP / PREG, Feral cat / bear) are told apart.
- **Automatic switching:**
  - after Talented has successfully applied a template
  - on a dual spec change, using the linked template that matches your talents best (at least 80%)
- **Fallback per talent tree:** if no linked template matches, the profile linked to the tree with the most points is loaded.
- **Simple profile list:** one line per profile with gear set icon, Load and a small menu for save, rename and delete.
- **Gear sets:** link an Equipment Manager set to a profile. It is equipped whenever the profile is loaded.
  - Missing items, and items that are only in the bank, are listed in chat. Everything that is available is equipped anyway.
  - The set icon is shown next to the profile and on the minimap button.
- **Combat safe:** no bars are restored and no gear is equipped in combat. A pending switch runs once combat ends.
- **Waits for new spells:** restoring is delayed until the spellbook has updated, so talent spells (e.g. Divine Storm) end up on the bars.
- **Profile window** (`/tbs`) with four tabs:
  - **Profiles:** save, load, rename and delete profiles; click a profile's icon to link a gear set
  - **Links:** link templates and talent trees to profiles
  - **Options:** automatic switching, gear sets, minimap button, macros, spell rank
  - **Help:** a short in-game how-to, shown the first time you open the window
- **Minimap button:** left-click opens the window, right-click opens Talented, drag to move. It can be turned off under Options or with `/tbs minimap`.
- **All original commands** still work: `/abs save`, `/abs restore`, `/abs list`, …

## Installation

1. Close WoW.
2. Copy the `TalentBarSaver` folder to `<WoW>\Interface\AddOns\`.
3. Remove the standalone `Talented` and `ActionBarSaver` folders from `Interface\AddOns`. Running them alongside TalentBarSaver causes Lua errors.
4. Start WoW and type `/tbs`.

### Migrating existing templates and profiles

WoW stores saved variables per addon folder. TalentBarSaver uses the same variable names as the original addons (`TalentedDB`, `ActionBarSaverDB`), so you only need to merge the two old files once.

With WoW closed, run this in `<WoW>\WTF\Account\<ACCOUNT>\SavedVariables\`:

```powershell
Get-Content .\Talented.lua, .\ActionBarSaver.lua | Set-Content .\TalentBarSaver.lua
```

## Usage

| Command | Description |
|---|---|
| `/tbs` | Open or close the window (`/abs` without arguments works too) |
| `/tbs save <name>` | Save the current action bars as a profile |
| `/tbs restore <name>` | Load a profile |
| `/tbs list` | List all profiles |
| `/tbs errors` | Show buttons that could not be restored last time |
| `/tbs minimap` | Show or hide the minimap button |
| `/tbs help` | Show all commands |
| `/talented` | Talented options |

**Typical setup**

1. Arrange your bars for Retribution and save them as `ret-pve`. Do the same for Holy and Protection.
2. In Talented (key `N`), create the templates "Ret PvE", "Holy PvE" and "Prot PvE".
3. Open `/tbs`, go to **Links**, and pick a profile for each template.
4. Optional: set a fallback profile for each talent tree.
5. Optional: create gear sets in the Equipment Manager. In the **Profiles** tab, click the icon in front of a profile and pick a set.

From then on, apply a template in Talented or switch your dual spec, and your bars and gear follow.

## Project structure

```
TalentBarSaver/
├── TalentBarSaver.toc     Load order
├── Libs/                  Ace3 libraries (from Talented)
├── Locales/               Talented translations
├── Talented/              Talented source (two small hooks added)
├── ABS/                   Action Bar Saver 2 source (bug fixes + profile API)
└── Core/
    ├── Bridge.lua         Template / spec → profile logic
    ├── GearSets.lua       Profile → Equipment Manager set
    ├── LayoutUI.lua       Profile window (AceGUI-3.0)
    └── MinimapButton.lua  Minimap button
```

New features go into `Core/`. Add new files to the `.toc` below `# TalentBarSaver modules`.

### Changes to the original addons

**Talented**
- Texture paths point to `Interface\AddOns\TalentBarSaver\Talented\Textures\`
- The "Restore bars with ABS" option is removed. It never worked, because it looked for a global `ABS`.
- Hooks `Talented:OnTemplateApplied(template)` and `Talented:OnTemplateRenamed(old, new, class)`

**Action Bar Saver 2**
- Fixed: `String.format` typo, which caused a Lua error when restoring in combat
- Fixed: wrong variable in error messages
- Fixed: the error list was not cleared between restores
- Fixed: the item name was missing from error messages
- Fixed: empty spellbook tabs were not handled
- Profile API: `GetProfileList`, `ProfileExists`, `DeleteProfile`, `RenameProfile`
- `/tbs` slash command

### Saved variables

| Variable | Content |
|---|---|
| `TalentedDB` | Talent templates and Talented options |
| `ActionBarSaverDB` | Action bar profiles and options |
| `ActionBarSaverDB.bridge` | Template/tree links, gear set links, last applied template per character and talent group, window position, minimap button settings |

## Compatibility

- WoW client **3.3.5a** (Interface 30300)
- Replaces the standalone Talented and Action Bar Saver 2 addons. Do not run them at the same time.

## Credits

- **Talented** by Jerry, Kader Edition
- **Action Bar Saver 2** by Shadowed
- Ace3 libraries by the Ace3 team

All credit for the original addons goes to their authors. TalentBarSaver adds the integration layer and the profile window.
