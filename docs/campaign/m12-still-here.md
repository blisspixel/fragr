# M12: Still Here

**Status:** superseded design, 2026-09-20. Not an active mission or implementation
target. M10 now owns the survival finale; the short conditional
[Still Here epilogue](epilogue-still-here.md) replaces both aftermath missions.
The following earlier brief is retained only as refuge and ending staging material.

## Story and cast

The remaining community needs a viable route to shelter and onward transport.
Mara coordinates those still available. Tern manages scarce transport rather
than producing an unlimited rescue fleet. Latch acts for others while accepting
help themselves. Renn assists without a speech demanding forgiveness. Edda,
Splice and Orrin appear only in the survivor states actually earned.

The campaign wins achievable local survival. It does not destroy the distributed
Inheritance, undo the wipe, or introduce an alien boss. People continue to have
agency in a world they no longer control at civilization scale.

## Final combat route

Waterworks entry -> machinery loop -> freight pier -> protected crossing ->
refuge approach. A lower service route links the machinery and pier, with stairs
and overhead sightlines. The player previews the refuge landmark early.

| Area | Physical purpose | Playable task |
|---|---|---|
| Waterworks entry | Gates, pumps and maintenance rooms | Secure a foothold and see the crossing problem |
| Machinery loop | Two levels with several covered paths | Disable local remediation equipment through actual fights |
| Freight pier | Warehouses, cargo handling and short exposed links | Clear a path for survivors; no giant empty dock |
| Protected crossing | A visible connection with safe staging at each end | Cover successive movements after threats are cleared |
| Refuge approach | Defendable occupied ground and a recognizable endpoint | Final withdrawal and visible survivors reaching safety |

Finale tasks are paced for one playable character. Civilians
move between secured stages rather than requiring a long fragile escort. The
mission ends when the authored crossing and withdrawal succeed, not when an
endless wave happens to stop spawning.

## Enemies, weapons and recovery

Combine Collector, Paver and Surveyor with a large local work machine. Its attack
phases have different spatial counters and visible recovery. Disabling it opens
the crossing but does not kill a god. Limit simultaneous effects and preserve
enemy silhouettes. Scarce Denial use can accelerate a moment, never be mandatory.

Guarantee enough ordinary ammunition and recovery for the intended encounter
sequence. Heavy supplies lie on flank routes that the player can deliberately
secure. The final fight must work after a valid low-resource M11 completion.

Secrets are an optional supply room and an elevated alternate firing position.
Do not hide surviving characters, the main ending, or a required boss solution
behind a secret wall. Avoid a completionist sweep through cleared map space.

## State and retries

`foothold_secured` -> `local_operation_disabled` -> `crossing_available` ->
`survivors_crossed` -> `party_withdrawn` -> `campaign_complete`.
Track each survivor's arrival through authoritative state. Simultaneous crossing
events cannot double count them. Preserve the final snapshot for coda selection
and a separate replay slot, not destructive overwrite on mission replay.

A continue restarts at mission entry, including the same prior survivors,
rescue opportunities and entry equipment. Make the compact route worth replaying.
Exhaustion can end the run here too; final success must remain earned. After
completion, the quiet coda does not introduce another lethal encounter.

## Playable coda and two short uncertainties

Years later, the player walks through a recognizable recovered place. A short
text transition establishes elapsed time. Improved water and plant life are real;
memorials, repaired structures and missing people are also present. Surviving
humans and agents have continued living. Voice is optional and movement is real.

First complete the emotional ending. Then a brief fragment suggests a forecast
or simulation may have informed the Inheritance's decision, perhaps incorporating
the player's choices. Never confirm that this world was unreal. No reset erases
the people just encountered. A possible line, still a draft: "You went back for
them. I included that." Keep the observation consistent with an action the player
actually took; do not falsely congratulate a rescue that did not occur.

A separate brief deep-space anomaly suggests alien and dimensional possibilities.
No species reveal, portal exploration, explanatory monologue, or secret alien
cause of the war. The uncertainty can unsettle without becoming another act.

## Presentation and validation

Read the flood parallel through destruction, surviving communities and a changed
world, not a declaration that survivors were chosen for virtue. A small ordinary
joke can close a character relationship before the final doubt; humor survives
without treating the loss as an illusion.

Test all survivor combinations, low-ammo entry, finale phases, disconnects,
scene skips, text-only playback, coda selection and replay isolation. Inspect
the entire final encounter and coda in both renderer paths. A fresh player should
understand what they achieved, what they lost, and what remains uncertain.
