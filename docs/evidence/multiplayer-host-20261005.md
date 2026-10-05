# Desktop multiplayer trial, October 5, 2026

Status: **in flight**. Desktop Host implements Team Deathmatch on six existing
arenas and optional 5v5 Sabotage on Sector 9. These source witnesses support the
[multiplayer-first plan](../plans/multiplayer-first-playable.md); full integration,
packages and release remain separate gates.

The host owns its matching native process. Watch, Join, Leave and return to menu
share that match; Stop server and app exit retire the owned process. Existing
dedicated hosting remains available. No cloud account or paid runtime is needed.

## Actual desktop witnesses

The earlier played witnesses below used source `dbe28271140caa4be75cd78ba4fe37a31852f9f4`,
native source `ae4ad91870d0f3fb5c60bc4aa11eee2da8c94d62` and native SHA-256
`a55e29cc543481af33f74d0f3f82c16d0c2de50a596625525ca5d7bf4a5c47cb`.
They ran through real owned Host readiness, ordinary networking and presentation
on Windows using Godot 4.7.2 Compatibility and Radeon 780M. Automation supplied
ordinary movement, fire and Use. It did not grant equipment or teleport players.
The install-check and package-smoke changes at that checkpoint preserved
ordinary gameplay, native and asset bytes. Later server corrections have
their own source and verification scope.

| Witness | Observed result | Limit |
|---|---|---|
| TDM moving combat | Unchanged canonical moving/fire route and ACK expectations passed with one rule bot | This passing run did not resolve a kill |
| 5v5 Sabotage | Eight-state ordinary route planted a charge and detonated it; authoritative round score became Union 0, Free Coalition 1 | Zero rule bots; this rendered route did not defuse |
| Two independent desktop apps | Distinct human participants received 504 unique matching server ticks, including players and team scores | Both ran on one computer over loopback |

Each successful run exited 0, had clean error logs and its own PASS marker. Both
desktop processes and each owned native child retired; an independent socket
probe confirmed the stopped listener refused connections. These observations
do not establish a physical two-machine LAN session or human enjoyment.

The [curated receipt](../screenshots/multiplayer-host-20261005/receipt.json)
binds original captures, canonical routes, logs and private lifecycle receipts
by SHA-256. Original failures remain retained: an early private Windows
closed-port predicate was invalid, and a later TDM run failed the unchanged
ACK-gap expectation. The quiet passing route did not weaken that expectation.
The server's instrumented mixed-party campaign fixture failed two whole
coverage runs. Precomputing its exact worlds and navigation before live sockets
preserves every timing and gameplay assertion. The corrected native checkpoint
`dff0b39b` passes the full 991-test server suite and unfiltered workspace line
coverage at 93.66 percent. The original failures remain separate from that proof.

A later two-desktop Sabotage attempt exposed a real empty-room defect: the
opening round advanced before either fighter joined, producing 1:1 after the
eventual detonation. The same native checkpoint keeps empty or parked-only
Muster at round one until an attached contestant arrives. Its regression tests
cover delayed humans, agents, spectators, resume and one rule bot. A new rendered
two-desktop result still requires the final paired native/client source.

The complete combined client checker at `f38ce343` passed 132 of 133 harnesses
but correctly failed on a music decoder still alive at exit. The owning fixture
now requires its five actual playback references to retire after ordinary scene
exit. Its focused real-native run passes with clean logs; final composed whole
client and package gates remain required.

## Literal captures

The Host controls below come from clean source `e82893e3`. All three bot
choices in both presets and the Multiplayer page were captured at three actual
window sizes. All 21 literal frames pass layout checks and independent visual
review. The real renderer exits 0 with clean logs and retires. No native match
was launched for this static witness. The small Sabotage image is an actual
800x600 window; earlier static source bindings remain in the curated receipt.

![Team Deathmatch Host controls](../screenshots/multiplayer-host-20261005/host-tdm.png)

![Sabotage Host controls in a small window](../screenshots/multiplayer-host-20261005/host-sabotage-small.png)

![Ordinary approach and plant prompt](../screenshots/multiplayer-host-20261005/04_sabotage_use_prompt.png)

![Planted charge in Sector 9](../screenshots/multiplayer-host-20261005/07_sabotage_planted_world.png)

![Authoritative detonation result](../screenshots/multiplayer-host-20261005/08_sabotage_detonated.png)

![Independent second desktop in the shared match](../screenshots/multiplayer-host-20261005/independent_desktop_shared_match.png)

## First human trial

Use a build containing Host, then follow [Playing](../PLAYING.md) and
[Hosting](../HOSTING.md). Start TDM with a few bots, Watch, Join, leave and join
again. Try Sector 9 Sabotage next. For another computer, enable LAN hosting and
give the peer the host's actual LAN address and chosen port.

Record the build, mode, map, human/bot counts and whether the second player was
on another machine. Report confusing controls, team readability, weapon starts,
objective clarity, spawn problems, frame hitches and disconnect behavior. A
short description of the moment is sufficient. Human feedback determines which
maps and fights need refinement before broader campaign production resumes.
