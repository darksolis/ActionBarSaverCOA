ActionBarSaver ArdenWoW/CoA v7

FIX: WoW 3.3.5 has PickupSpell(index, BOOKTYPE_SPELL), not PickupSpellBookItem.
The latter was introduced in patch 4.0.1. This patch uses the correct 3.3.5 API.

Restore remains non-destructive: failed pickups do not clear existing slots.
Only spellbook-verified, unambiguous matches are attempted.

IMPORTANT: Copy your existing SavedVariables/ActionBarSaver.lua (and .bak)
before changing addons. Do not delete SavedVariables or overwrite backups.
Keep in mind saved profiles that contain unresolved or bad spell identities
may still not restore until captured correctly.

TEST: /abs scan, /abs inspect 68, /abs list, /abs audit <profile>.
Only after reviewing an intact profile, use /abs restore <profile>.

Not tested against a running ArdenWoW client.
