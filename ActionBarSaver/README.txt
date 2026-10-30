ACTIONBARSAVER - DARKVEIL EDITION
Version: v18-darkveil | Target: ArdenWoW / CoA Classic (3.3.5)

Created by Darkveil
Based on ActionBarSaver by Shadowed. CoA compatibility modifications, custom
spellbook registry, one-pass profile capture, and Darkveil interface edition.

OVERVIEW
ActionBarSaver creates local backups of your character's action bars, useful
when the ArdenWoW server does not reliably retain its action bar layout.
Version 18 scans learned spells and captures the current action bars in one
pass, using custom CoA spell IDs when the client exposes them. Existing saved
profiles are kept if a new capture cannot be completed reliably.

INSTALLATION
1. Exit World of Warcraft fully.
2. Back up your current SavedVariables files before replacing any addon:
   WTF/Account/<ACCOUNT>/SavedVariables/ActionBarSaver.lua
   (Also back up any character-level ActionBarSaver.lua file, if present.)
3. Extract the ActionBarSaver folder into Interface/AddOns/.
   Avoid double nesting (ActionBarSaver/ActionBarSaver/).
4. Launch ArdenWoW and enable ActionBarSaver in the AddOns list.
5. Open the Darkveil control panel from the minimap icon or /absui.

QUICK START
1. Arrange the bars as desired while out of combat.
2. Open /absui and choose Scan Spellbook if needed.
3. Click New Snapshot or save a named profile.
4. Confirm that the chat reports a successful full save. If the addon
   refuses a capture, do not assume the backup is complete.
5. Type /reload or exit the game normally so SavedVariables are written.
6. After a server-side bar reset, choose your profile and Restore Selected.
7. Review /abs errors after restore if any slots are reported as skipped.

IN-GAME CONTROLS
- Minimap button: left-click to open panel, right-click to scan spellbook,
  drag to reposition.
- Dashboard: manage profiles, create snapshots, restore, inspect spells,
  toggle restore settings, and delete a profile with confirmation.
- Interface -> AddOns -> ActionBarSaver: interface entry when supported.

SLASH COMMANDS
/absui                       Toggle the custom control panel
/absminimap show             Show the minimap launcher
/absminimap hide             Hide the minimap launcher
/absminimap reset            Reset launcher position
/abs scan                    Rebuild local spellbook registry
/abs save <name>             Save a named profile
/abs saveforce <name>        Force overwrite (use carefully)
/abs snapshot                Create a numbered backup
/abs restore <name>          Restore a saved profile while out of combat
/abs list                    List saved profiles
/abs audit <name>            Review a saved profile's action count
/abs errors                  Report skipped/failed restore actions
/abs lookup <spell or ID>    Search learned spellbook records
/abs inspect <slot>          Inspect live action slot references
/abs rename <old> <new>      Rename a profile
/abs delete <name>           Delete a profile (UI has confirmation)
/abs macro                   Toggle macro restoration
/abs rank                    Toggle highest-rank restoration
/abs count                   Toggle item-count checking
/abs link "<a>" "<b>"       Link interchangeable spell names
/abs map ...                 Advanced manual profile spell mapping

SAFETY AND LIMITATIONS
- Always retain at least one known-good local profile before testing changes.
- Do not overwrite a good backup when the server loads empty/partial bars.
- The addon is designed to preserve unmatched slots rather than clear them.
- Some companion/pet actions may depend on client-specific behavior and can
  remain unrestored. Check chat errors when using those slots.
- A valid one-pass save is not a guarantee that every unsupported client
  action type can be restored. Test a complete layout before relying on it.
- SavedVariables are written to disk at reload/logout, not immediately at
  the moment the Save button is pressed.

FILES
ActionBarSaver.lua          Core capture, restore, registry, and UI logic
ActionBarSaver.toc          Addon metadata/load order
Textures/                   Custom interface textures
localization/               Language files
README.txt                  This file

This package preserves the working v18 Lua, TOC, localization, and textures.
It removes only obsolete intermediate patch notes and readme files.
