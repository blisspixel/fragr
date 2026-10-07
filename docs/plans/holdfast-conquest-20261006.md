# Holdfast Atoll and Conquest

**Status:** in flight, 2026-10-06. Development implementation, no played
acceptance or population claim yet. Nick selected the island, vehicles and
capture-point interpretation of the multiplayer reference.

Build an original coastal horseshoe with Harbour, Village, Airfield, Server
Halls and Lighthouse Tip. A continuous infantry route connects all five;
open roads support the shared jeep. Work, repairs and coastal life establish
the place. Union installations use issued black/red equipment, local buildings
use sun-worn plaster, bone, olive and rust. Do not copy a historical map layout.

The land footprint is 320 metres across inside a 440-metre playable water area.
Land stands three metres above the seabed, with registered water at 2.2 metres.
Broad coastal steps and low docks support returning to shore. The current fleet
has three jeeps, two boats and a light aircraft. Native movement, seats and
damage tests pass; composed controls and art acceptance remain in flight. The
[water rendering plan](island-water-rendering-20261006.md) separates measured
presenter cost from server population evidence.

Two sides start with 200 tickets. Five sites start neutral. A living participant
on foot or in an exposed vehicle seat within 8 metres, and within 3 vertical
metres of a site's ground, contributes their side. Presence by both sides
contests and freezes progress. One uncontested side takes eight seconds to
neutralize enemy ownership and another eight to capture. Additional bodies do
not accelerate capture. Empty partial progress decays. Every resolved death
costs that side one ticket. Every second, the side holding at least three sites
bleeds its opponent by one ticket per site above two. Zero tickets ends the
round; simultaneous zero is a draw. The ten-minute mode clock compares tickets.

Round start and mode changes reset sites and tickets. Existing authoritative
damage, side assignment, respawn safety, navigation, Action and snapshots are
the seams. Snapshot state includes site geometry and retained ownership,
capturing side, progress, contested state and ticket counts. No parallel port,
client scoring or persistent conquest ledger.

Prove capture, contest, neutralization, decay, death debit, bleed, reset,
end-of-round and malformed client boundaries. Validate all site and vehicle
approaches against collision and shared navigation. Then run a composed match
and inspect the actual client at infantry height and in a jeep. Rendering and
fun remain separate acceptance from these logic tests.
