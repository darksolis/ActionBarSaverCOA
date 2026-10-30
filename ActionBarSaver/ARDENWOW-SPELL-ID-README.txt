ArdenWoW CoA ActionBarSaver spell-ID patch

- Saves spell ID + name + rank.
- Restores exact spell ID using spellbook ID lookup, then PickupSpell(ID).
- Refuses to substitute a different spell with the same name.
- Makes a safety profile __arden_before_restore before the first restore per login.
- /abs errors shows failures by exact spell ID and slot.

Back up WTF/Account/<account>/SavedVariables/ActionBarSaver.lua before installing.
Create a NEW /abs save myprofile with your bars currently correct and test.
An old saved profile can be tried too; it already stored numeric spell IDs.
Custom/server-only spells may be un-restorable if the client API cannot pick them up.
