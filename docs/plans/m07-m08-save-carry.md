# M07 to M08 durable campaign carry

**Status:** in flight, 2026-10-03. Written before implementation.
**Spend:** $0. Local source work and checks only.

## Goal and boundary

Continue the accepted Declared Goods exit into Custodian of Record through the
existing local campaign run document and writer lock. Preserve actual health,
armor, finite ammunition, weapon selection, body, difficulty, remaining
continues and completed M03 through M06 outcomes. Clear only the prior map's
personal supply claims. M08 stays in Episode II and grants no continue refill.

Save version 9 requires the actual proximity-mine count alongside the existing
grenade count. Use the existing independent four-mine and six-grenade caps.
Inventory capture and restore own both counts; no second persistence route or
loadout protocol revision is needed. Retry restores the M08 mission-entry
anchor through the existing recovery seam, never a mid-fight checkpoint.

## Migration contract

Decode versions 6 through 8 with their exact grenade-bearing equipment shape
and no mine field. Decode versions 2 through 5 with their exact equipment
shape and neither explosive count. Historical upgrades assign zero mines;
versions before 6 also assign zero grenades. Reject unknown equipment fields,
missing historical counts, forged future missions, impossible weapon finds,
invalid rules and incompatible authored content. Version 8 can represent M07
and its pending M08 edge, but cannot represent playable M08.

Read-only previews preserve source bytes. Writable upgrades and promotion use
the existing bounded reader, content hashes, writer lock, content-addressed
exact-byte archive and atomic replacement. Replacement failures preserve the
original run and retry reuses its archive. M08 may persist its completed exit
awaiting M09, including actual remaining mines, but M09 is not playable.

## Implementation and evidence

1. Extend saved equipment and strict historical shapes, then verify malformed
   and valid counts independently of grenades.
2. Enable M08 promotion and retain earlier outcomes in its run projection,
   continue and retry paths. Keep unimplemented future mission admission shut.
3. Exercise exact historical migrations, byte archives, injected replacement
   failure, promotion without refill and real M08 inventory/recovery behavior.
4. Check an owned local child and client continuation against the promoted
   document. Require actual MapInfo, readiness and mine counts on the wire.
5. Run focused checks, complete native/client gates and current CI before
   parent integration. Record actual results and remaining gates here.

The accepted M07 route remains immutable in its original branch. Its final
15 HP and one Cell are a separate pacing limitation, not altered by this work.

## Current evidence

Version 9 and strict historical readers are implemented. Four focused native
tests pass: exact v8 source preservation and archive retry, M08 promotion with
one or zero remaining continues and no refill, historical mine-field refusal
across v2 through v8, and actual M08 mine placement followed by same-process
and reopened continues. M08 completion saves its actual finite exit counts
and earlier outcomes; a fresh admission refuses that pending M09 document.
The server library passes 869 tests with three ignored tests. Warning-denied
server Clippy passes. All 16 owned local-child tests pass after updating the
historical v2 fixture to omit both explosive fields.

The new client lifecycle harness passes a real v8 M07 exit through the actual
saved M08 button, story-input barrier, readiness and private loadout. It retains
15 HP, the last Cell, saved synthetic body and all earlier outcomes, preserves
preview bytes and archives them exactly once. A second owned M08 child restores
three entry mines, ordinary input places one, and the saved retry anchor retains
three while the live count is two. Both children stop cleanly. Frontend and
local-preview harnesses pass, including refusal of a playable M09 entry.

Complete fresh workspace and client verification remain in progress. This
work does not change M07 combat balance or establish M08 fresh-player, pacing,
difficulty, final art or whole rendered-route acceptance.
