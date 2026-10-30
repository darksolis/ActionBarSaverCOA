Darkveil ActionBarSaver v18 — one-pass CoA capture fix

Changes:
- Save now scans the spellbook and action bars in one pass.
- Prioritizes the real action extra spell ID (e.g. Noctis Blade 680615)
  over the ambiguous book index returned as the raw action value.
- Builds a complete temporary profile and will not overwrite existing
  profiles if any actions cannot be identified.
- Tries the classic PickupCompanion API if present, without clearing
  an existing action slot if pickup fails.
- Minimap uses a built-in fallback icon.

IMPORTANT: Existing incomplete profiles do not repair themselves. Put
all actions on your bars correctly, then perform a new Save Named or
New Snapshot. This build is statically checked but not client-tested.

Backup your WTF/SavedVariables/ActionBarSaver.lua before installing.
